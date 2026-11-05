import Foundation
import UserNotifications

struct AIConnection: Codable, Identifiable { var id: String; var provider: AssistantProvider; var scopes: [String] }
struct AIConnectionList: Decodable { var connections: [AIConnection] }
struct AIAuthorizationRequest: Codable, Identifiable {
    var id: String
    var provider: AssistantProvider
    var clientName: String
    var clientDomain: String?
    var redirectHost: String
    var scopes: [String]
    var expiresAt: String
    var approved: Bool
}
struct AIServiceStatus: Decodable { var configured: Bool }
struct AIEmptyResponse: Decodable {}
struct CloudServiceError: LocalizedError {
    var status: Int
    var message: String
    var errorDescription: String? { message }
}
private final class NoAIRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
@MainActor
struct AIConnectionsClient {
    static let server = "https://tender-ai-connections.tender-bank-bridge.workers.dev"
    var auth: AccountAuth?
    var accountScope: String?
    func call<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil, authenticated: Bool = true) async throws -> T {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            guard ProcessInfo.processInfo.arguments.contains("--ai-connections-test") else { throw BankError.message("AI networking is disabled during UI tests.") }
            return try AIConnectionsFixture.call(path, method: method, body: body)
        }
        #endif
        guard !authenticated || (accountScope != nil && auth?.storageKey == accountScope) else { throw BankError.message("Sign in again to connect an AI assistant.") }
        var request = URLRequest(url: URL(string: Self.server)!.appending(path: path))
        request.httpMethod = method; request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = body
        if authenticated, let auth, let accountScope { request.setValue("Bearer " + (try await auth.bankConfiguration(expectedScope: accountScope)).token, forHTTPHeaderField: "Authorization") }
        let config = URLSessionConfiguration.ephemeral; config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: NoAIRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard !authenticated || auth?.storageKey == accountScope else { throw BankError.message("Sign-in changed. Reopen AI Connections.") }
        guard data.count < 10_000_000, let http = response as? HTTPURLResponse else { throw BankError.message("Unexpected cloud response.") }
        guard (200..<300).contains(http.statusCode) else {
            let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String
            throw CloudServiceError(status: http.statusCode, message: message ?? "AI Connections is unavailable. Your phone's saved information is preserved.")
        }
        return try JSONDecoder.tender.decode(T.self, from: data)
    }
}

#if DEBUG
@MainActor
enum AIConnectionsFixture {
    private struct Upload: Decodable { var ledger: Ledger; var expectedRevision: Int }
    static var snapshot = CloudLedgerSnapshot(revision: 0, epoch: 0, connected: false, ledger: nil, events: [])
    static func call<T: Decodable>(_ path: String, method: String, body: Data?) throws -> T {
        var data: Data
        if path == "health" { data = Data("{\"configured\":true}".utf8) }
        else if path == "v3/connections" { data = Data("{\"connections\":[]}".utf8) }
        else if path == "v3/disconnect" { snapshot.connected = false; snapshot.epoch += 1; snapshot.revision += 1; data = try JSONEncoder.tender.encode(snapshot) }
        else if path == "v3/ledger" && method == "PUT" {
            let upload = try JSONDecoder.tender.decode(Upload.self, from: body!)
            guard upload.expectedRevision == snapshot.revision else { throw CloudServiceError(status: 409, message: "Fixture revision conflict") }
            snapshot.ledger = upload.ledger; snapshot.connected = true; snapshot.revision += 1; data = try JSONEncoder.tender.encode(snapshot)
        } else if path == "v3/ledger" { data = try JSONEncoder.tender.encode(snapshot) }
        else { throw CloudServiceError(status: 404, message: "Fixture endpoint unavailable") }
        return try JSONDecoder.tender.decode(T.self, from: data)
    }
    static func addPurchase() throws {
        guard var ledger = snapshot.ledger, let account = ledger.activeAccounts.first, let category = ledger.categories.first else { return }
        var expense = Expense(merchant: "AI fixture lunch", amount: 1200, categoryID: category.id, accountID: account.id)
        expense.assistantOrigin = AssistantOrigin(provider: .chatgpt, actionID: UUID().uuidString, createdAt: Date())
        try ledger.record(expense, deductFromBalance: false)
        snapshot.ledger = ledger; snapshot.revision += 1
    }
    static func seedReminderConflict(store: LedgerStore) async throws {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else { throw BankError.message("Allow simulator test notifications.") }
        let content = UNMutableNotificationContent(); content.title = "Synthetic reminder"
        try await center.add(UNNotificationRequest(identifier: "ai-conflict-fixture", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)))
        var remote = store.ledger; remote.appPreferences = AppPreferences(remindersEnabled: false)
        _ = store.update { $0.appPreferences = AppPreferences(remindersEnabled: true) }
        snapshot.ledger = remote; snapshot.revision += 1
        await store.synchronizeCloud()
    }
    static func addAppChanges() throws {
        guard var ledger = snapshot.ledger else { return }
        ledger.profileName = "Taylor AI"; ledger.appPreferences = AppPreferences(remindersEnabled: false)
        var item = GroceryItem(name: "AI fixture milk")
        item.plannedAt = Date(); item.assistantOrigin = AssistantOrigin(provider: .chatgpt, actionID: UUID().uuidString, createdAt: Date())
        ledger.groceries.append(item)
        ledger.assistantScreenRequest = AssistantScreenRequest(screen: .profile)
        snapshot.ledger = ledger; snapshot.revision += 1
    }
    static func addFixedExpense() throws {
        guard var ledger = snapshot.ledger else { return }
        var fixed = FixedExpense(name: "AI fixture utilities", amount: 2000)
        fixed.assistantOrigin = AssistantOrigin(provider: .claude, actionID: UUID().uuidString, createdAt: Date())
        try ledger.saveFixedExpense(fixed); snapshot.ledger = ledger; snapshot.revision += 1
    }
}
#endif
