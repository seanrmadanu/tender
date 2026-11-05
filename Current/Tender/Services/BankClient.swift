import Foundation
import Security

struct BankConfiguration: Codable, Sendable {
    private static var keychainService: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return "com.sean.tender.bank.ui-tests" }
        #endif
        return "com.sean.tender.bank"
    }
    static let accountServer = "https://tender-bank-bridge.tender-bank-bridge.workers.dev"
    var server: String
    var token: String
    static func load() -> BankConfiguration? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.keychainService, kSecAttrAccount as String: "bridge", kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func save() throws {
        let data = try JSONEncoder().encode(self)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.keychainService, kSecAttrAccount as String: "bridge"]
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw BankError.message("The bank configuration couldn’t be saved in Keychain.") }
        } else if status != errSecSuccess { throw BankError.message("Keychain is unavailable. Unlock your device and try again.") }
    }
    var url: URL? {
        guard let url = URL(string: server), let host = url.host, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, !host.isEmpty else { return nil }
        #if targetEnvironment(simulator)
        if url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host) { return url }
        #endif
        return url.scheme == "https" ? url : nil
    }
}
enum BankError: LocalizedError {
    case message(String)
    case offline
    var errorDescription: String? { switch self {
        case .message(let value): value
        case .offline: "You’re offline. Saved bank information may be outdated."
    } }
}
struct BankAccountsResponse: Decodable {
    var accounts: [BankSnapshot]
    var errors: [String]
    var cached: Bool
    var environment: String
}
struct LinkTokenResponse: Decodable { var linkToken: String; var environment: String }
struct BankConnection: Decodable, Identifiable { var id: String; var name: String }
struct BankStatus: Decodable { var environment: String; var connectionCount: Int; var oauthConfigured: Bool; var linkMode: String? }
struct HostedBankSession: Decodable, Identifiable {
    var id: String
    var url: URL
    var expiresAt: Date
    var presentation: String? = nil
    var safeURL: URL? { url.scheme == "https" && url.host == "secure.plaid.com" && url.user == nil && url.password == nil ? url : nil }
}
struct HostedBankSessionResponse: Decodable { var session: HostedBankSession? }
struct HostedBankResult: Decodable { var status: String; var diagnostic: BankDiagnostic? }
struct BankConnectionsResponse: Decodable { var connections: [BankConnection] }
private final class NoBankRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
@MainActor
struct BankClient {
    var configuration: BankConfiguration
    var accountAuth: AccountAuth? = nil
    var accountScope: String? = nil
    func call<T: Decodable>(_ route: String, method: String = "GET", body: [String: String]? = nil) async throws -> T {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--bank-import-test") {
            if route == "v1/sync" && ProcessInfo.processInfo.arguments.contains("--wallet-startup-test") {
                if ProcessInfo.processInfo.arguments.contains("--wallet-startup-failure-test") {
                    throw BankError.message("Bank update failed. Showing saved balances.")
                }
                try await Task.sleep(for: .seconds(ProcessInfo.processInfo.arguments.contains("--wallet-startup-timeout-test") ? 10 : 0.35))
            }
            return try BankUITestTransport.call(route, method: method)
        }
        #endif
        let configuration: BankConfiguration
        if let accountScope {
            guard let accountAuth else { throw BankError.message("Sign in again to connect your bank.") }
            configuration = try await accountAuth.bankConfiguration(expectedScope: accountScope)
        } else { configuration = self.configuration }
        guard let base = configuration.url, configuration.token.count >= 32 else { throw BankError.message("Save your bank bridge URL and access token first.") }
        let route = accountScope == nil ? route : route.replacingOccurrences(of: "v1/", with: "v2/", options: .anchored)
        var request = URLRequest(url: base.appending(path: route))
        request.httpMethod = method; request.timeoutInterval = route.hasSuffix("/sync") ? 90 : 35
        request.setValue("Bearer " + configuration.token, forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: NoBankRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff].contains(error.code) { throw BankError.offline }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch is CancellationError { throw CancellationError() }
        catch { throw BankError.message("Bank information couldn’t update. Your saved information is still available and may be outdated.") }
        if let accountScope, accountAuth?.storageKey != accountScope { throw BankError.message("Sign-in changed. Open Accounts again.") }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 25_000_000 else {
            let code = (response as? HTTPURLResponse)?.statusCode
            if code == 401 { throw BankError.message(accountScope == nil ? "The bridge access token was rejected. Check your saved configuration." : "Bank authorization was rejected. Sign in again. If this continues, the account bank service needs its latest update.") }
            if [400, 404, 409, 502, 503].contains(code ?? 0), let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"], message.count < 500 {
                throw BankError.message(message)
            }
            if code == 429 { throw BankError.message("Wait one minute before refreshing balances again.") }
            throw BankError.message("The bank service couldn’t complete this request. Your ledger balances haven’t changed.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { throw BankError.message("The bank service returned an invalid timestamp.") }
            return date
        }
        return try decoder.decode(T.self, from: data)
    }
    func exchange(_ token: String, institution: String) async throws { let _: [String: Bool] = try await call("v1/exchange", method: "POST", body: ["publicToken": token, "institutionName": institution]) }
    func disconnect() async throws { let _: [String: Bool] = try await call("v1/connections", method: "DELETE") }
}

struct BankActivityError: Decodable { var itemID: String; var message: String }
struct BankActivityResponse: Decodable { var environment: String; var errors: [BankActivityError]; var items: [BankActivityItem] }
struct BankDiagnostic: Decodable {
    var code: String?; var type: String?; var requestID: String?; var sessionID: String?
    var summary: String { [code.map { "Error: " + $0 }, type.map { "Type: " + $0 }, requestID.map { "Request: " + $0 }, sessionID.map { "Link session: " + $0 }].compactMap { $0 }.joined(separator: "\n") }
}
extension BankConfiguration {
    static func remove() throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Self.keychainService, kSecAttrAccount as String: "bridge"]
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw BankError.message("Could not remove bank access from Keychain. Try again while the device is unlocked.") }
    }
}

struct BankConnectionIssue: Decodable, Identifiable {
    var itemID: String
    var name: String
    var requiresReauthentication: Bool
    var message: String
    var id: String { itemID }
}
struct BankSyncResponse: Decodable {
    var environment: String
    var accounts: [BankSnapshot]
    var items: [BankActivityItem]
    var connectionIssues: [BankConnectionIssue]
    var errors: [String]
    var balancesCheckedAt: Date?
    var activityCheckedAt: Date?
}
