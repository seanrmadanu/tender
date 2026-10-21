import Foundation
import Security

struct BankConfiguration: Codable {
    var server: String
    var token: String
    static func load() -> BankConfiguration? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.sean.tender.bank", kSecAttrAccount as String: "bridge", kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func save() throws {
        let data = try JSONEncoder().encode(self)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.sean.tender.bank", kSecAttrAccount as String: "bridge"]
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
struct BankSnapshot: Decodable, Identifiable {
    var id: String
    var name: String
    var mask: String?
    var currency: String?
    var availableCents: Int64?
    var currentCents: Int64?
    var retrievedAt: Date
}
struct BankAccountsResponse: Decodable {
    var accounts: [BankSnapshot]
    var errors: [String]
    var cached: Bool
    var environment: String
}
struct LinkTokenResponse: Decodable { var linkToken: String; var environment: String }
struct BankConnection: Decodable, Identifiable { var id: String; var name: String }
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
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count < 5_000_000 else {
            let code = (response as? HTTPURLResponse)?.statusCode
            if code == 401 { throw BankError.message("The bridge access token was rejected. Check your saved configuration.") }
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
    func exchange(_ token: String) async throws { let _: [String: Bool] = try await call("v1/exchange", method: "POST", body: ["publicToken": token]) }
    func disconnect() async throws { let _: [String: Bool] = try await call("v1/connections", method: "DELETE") }
}
