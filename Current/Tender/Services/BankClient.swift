import Foundation
import Security

struct BankConfiguration: Codable, Sendable {
    private static var keychainService: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return "com.sean.tender.bank.ui-tests" }
        #endif
        return "com.sean.tender.bank"
    }
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
    var errorDescription: String? { switch self { case .message(let value): value } }
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
    var safeURL: URL? { url.scheme == "https" && url.host == "secure.plaid.com" && url.user == nil && url.password == nil ? url : nil }
}
struct HostedBankSessionResponse: Decodable { var session: HostedBankSession? }
struct HostedBankResult: Decodable { var status: String; var diagnostic: BankDiagnostic? }
struct BankConnectionsResponse: Decodable { var connections: [BankConnection] }
private final class NoBankRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct BankClient {
    var configuration: BankConfiguration
    func call<T: Decodable>(_ route: String, method: String = "GET", body: [String: String]? = nil) async throws -> T {
        guard let base = configuration.url, configuration.token.count >= 32 else { throw BankError.message("Save your bank bridge URL and access token first.") }
        var request = URLRequest(url: base.appending(path: route))
        request.httpMethod = method; request.timeoutInterval = 35
        request.setValue("Bearer " + configuration.token, forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: NoBankRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw BankError.message("Couldn’t reach your bank bridge. Check its address and connection.") }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 25_000_000 else {
            let code = (response as? HTTPURLResponse)?.statusCode
            if code == 401 { throw BankError.message("The bridge access token was rejected. Check your saved configuration.") }
            if [400, 404, 409, 502].contains(code ?? 0), let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"], message.count < 500 {
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
