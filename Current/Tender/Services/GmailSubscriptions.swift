import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

private struct GmailCredential: Codable {
    var access: String
    var refresh: String
    var expires: Date
}
private enum GmailKeys {
    static let service = "com.sean.tender.gmail"
    static func read(_ email: String) throws -> GmailCredential {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: email, kSecReturnData: true] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw BankError.message("Reconnect this Gmail address to continue.") }
        return try JSONDecoder().decode(GmailCredential.self, from: data)
    }
    static func save(_ value: GmailCredential, email: String) throws {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: email] as CFDictionary
        let data = try JSONEncoder().encode(value)
        let attributes = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary
        let result = SecItemUpdate(query, attributes)
        if result == errSecItemNotFound {
            guard SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: email, kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly] as CFDictionary, nil) == errSecSuccess else { throw BankError.message("Could not save Gmail access securely.") }
        } else if result != errSecSuccess { throw BankError.message("Unlock your phone and retry saving Gmail access.") }
    }
    static func remove(_ email: String? = nil) throws {
        var query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service]
        if let email { query[kSecAttrAccount] = email }
        let result = SecItemDelete(query as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw BankError.message("Could not remove Gmail access. Unlock your phone and retry.") }
    }
}

@MainActor @Observable
final class GmailSubscriptions: NSObject, ASWebAuthenticationPresentationContextProviding {
    var busy = false
    var message: String?
    private var session: ASWebAuthenticationSession?
    private var lastAttempt: Date?
    private var clientID: String { Bundle.main.object(forInfoDictionaryKey: "TenderGoogleClientID") as? String ?? "" }
    private var callbackScheme: String { clientID.split(separator: ".").reversed().joined(separator: ".") }
    var configured: Bool {
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return clientID.hasSuffix(".apps.googleusercontent.com") && types.contains { ($0["CFBundleURLSchemes"] as? [String] ?? []).contains(callbackScheme) }
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    private func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw BankError.message("Could not start a secure connection. Try again.") }
        return Data(bytes).urlBase64
    }
    private func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(values.sorted { $0.key < $1.key }.map { ($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "=" + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }.joined(separator: "&").utf8)
    }
    private func request(_ url: URL, token: String? = nil, values: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: url); request.timeoutInterval = 25
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        if let values { request.httpMethod = "POST"; request.httpBody = form(values); request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), data.count < 5_000_000 else {
            throw BankError.message("Google could not complete this request. Retry, or reconnect the email address if access expired.")
        }
        return data
    }
    private struct Token: Decodable { var access_token: String; var refresh_token: String?; var expires_in: Double; var scope: String? }
    private func exchange(_ values: [String: String]) async throws -> Token {
        try JSONDecoder().decode(Token.self, from: await request(URL(string: "https://oauth2.googleapis.com/token")!, values: values))
    }
    func connect(store: LedgerStore) async {
        guard configured, !busy, store.storageHealthy, !store.bankMaintenance, !store.ledger.isDemo else { message = "Gmail setup is not configured in this build yet."; return }
        busy = true; message = nil; defer { busy = false; session = nil }
        do {
            let state = try randomToken(), verifier = try randomToken()
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).urlBase64
            let redirect = callbackScheme + ":/oauthredirect"
            var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            url.queryItems = ["client_id": clientID, "redirect_uri": redirect, "response_type": "code", "scope": "https://www.googleapis.com/auth/gmail.readonly", "state": state, "code_challenge": challenge, "code_challenge_method": "S256", "access_type": "offline", "prompt": "consent select_account"].map { URLQueryItem(name: $0.key, value: $0.value) }
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let auth = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: callbackScheme) { url, error in
                    if let url { continuation.resume(returning: url) }
                    else { continuation.resume(throwing: error ?? BankError.message("Gmail connection cancelled.")) }
                }
                auth.presentationContextProvider = self
                auth.prefersEphemeralWebBrowserSession = true
                session = auth
                if !auth.start() { continuation.resume(throwing: BankError.message("Could not open Google sign-in.")) }
            }
            let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard callback.scheme == callbackScheme, query.first(where: { $0.name == "state" })?.value == state,
                  let code = query.first(where: { $0.name == "code" })?.value else { throw BankError.message("Google authorization was cancelled or could not be verified.") }
            let token = try await exchange(["code": code, "client_id": clientID, "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": verifier])
            guard token.scope?.components(separatedBy: " ").contains("https://www.googleapis.com/auth/gmail.readonly") == true else { throw BankError.message("Gmail read permission was not granted.") }
            struct Profile: Decodable { var emailAddress: String }
            let profile = try JSONDecoder().decode(Profile.self, from: await request(URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!, token: token.access_token))
            let email = profile.emailAddress.lowercased()
            guard let refresh = token.refresh_token ?? (try? GmailKeys.read(email).refresh) else { throw BankError.message("Reconnect and allow offline access to keep this account linked.") }
            try GmailKeys.save(GmailCredential(access: token.access_token, refresh: refresh, expires: Date().addingTimeInterval(token.expires_in)), email: email)
            if !store.update({ ledger in
                if ledger.subscriptionMailboxes == nil { ledger.subscriptionMailboxes = [] }
                if !ledger.subscriptionMailboxes!.contains(where: { $0.id == email }) { ledger.subscriptionMailboxes!.append(SubscriptionMailbox(id: email)) }
            }) { try? GmailKeys.remove(email); return }
            message = "Connected \(email). Tap Check Emails to find suggestions."
        } catch { message = error.localizedDescription }
    }
    private func access(_ email: String) async throws -> String {
        var credential = try GmailKeys.read(email)
        if credential.expires < Date().addingTimeInterval(60) {
            let token = try await exchange(["client_id": clientID, "grant_type": "refresh_token", "refresh_token": credential.refresh])
            credential.access = token.access_token; credential.expires = Date().addingTimeInterval(token.expires_in)
            credential.refresh = token.refresh_token ?? credential.refresh
            try GmailKeys.save(credential, email: email)
        }
        return credential.access
    }
    private struct MessageList: Decodable {
        struct Entry: Decodable { var id: String }
        var messages: [Entry]?
        var nextPageToken: String?
    }
    private struct Mail: Decodable {
        struct Part: Decodable {
            struct Header: Decodable { var name: String; var value: String }
            struct Body: Decodable { var data: String? }
            var mimeType: String?; var filename: String?; var headers: [Header]?; var body: Body?; var parts: [Part]?
            var plainText: String {
                guard filename?.isEmpty != false else { return "" }
                if mimeType == "text/plain", let data = body?.data?.fromURLBase64, let text = String(data: data, encoding: .utf8) { return String(text.prefix(20000)) }
                let children = (parts ?? []).map(\.plainText).filter { !$0.isEmpty }.joined(separator: "\n")
                if !children.isEmpty { return String(children.prefix(20000)) }
                if mimeType == "text/html", let data = body?.data?.fromURLBase64, let html = String(data: data, encoding: .utf8) {
                    return String(html.replacingOccurrences(of: #"(?is)<(script|style)\b[^>]*>.*?</\1>"#, with: "", options: .regularExpression).replacingOccurrences(of: #"<[^>]+>"#, with: "\n", options: .regularExpression).prefix(20000))
                }
                return ""
            }
        }
        var id: String; var internalDate: String?; var payload: Part
    }
    func refresh(store: LedgerStore, force: Bool = false) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        #endif
        guard !busy, configured, store.storageHealthy, !store.bankMaintenance, !store.ledger.isDemo,
              !(store.ledger.subscriptionMailboxes ?? []).isEmpty,
              force || Date().timeIntervalSince(lastAttempt ?? .distantPast) > 900 else { return }
        busy = true; lastAttempt = Date(); message = nil; defer { busy = false }
        var failures: [String] = []
        for mailbox in store.ledger.subscriptionMailboxes ?? [] {
            do {
                let token = try await access(mailbox.id)
                let seen = Set((store.ledger.subscriptionEmails ?? []).map(\.id))
                var page: String?
                // Bound each sync; persist each parsed result so interrupted syncs resume.
                var count = 0
                repeat {
                    var url = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
                    url.queryItems = [URLQueryItem(name: "q", value: "newer_than:1y {subscription membership trial renewal renews cancellation cancelled canceled}"), URLQueryItem(name: "maxResults", value: "100")]
                    if let page { url.queryItems?.append(URLQueryItem(name: "pageToken", value: page)) }
                    let list = try JSONDecoder().decode(MessageList.self, from: await request(url.url!, token: token))
                    for item in list.messages ?? [] where !seen.contains(mailbox.id + ":" + item.id) {
                        let mail = try JSONDecoder().decode(Mail.self, from: await request(URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(item.id)?format=full")!, token: token))
                        let headers = mail.payload.headers ?? []
                        let subject = headers.first { $0.name.lowercased() == "subject" }?.value ?? ""
                        let sender = headers.first { $0.name.lowercased() == "from" }?.value ?? "Unknown service"
                        let received = Date(timeIntervalSince1970: (Double(mail.internalDate ?? "") ?? 0) / 1000)
                        if let evidence = SubscriptionEmailParser.parse(id: mailbox.id + ":" + item.id, mailbox: mailbox.id, sender: sender, subject: subject, body: mail.payload.plainText, received: received) {
                            guard store.update({ ledger in
                                if ledger.subscriptionEmails == nil { ledger.subscriptionEmails = [] }
                                if !ledger.subscriptionEmails!.contains(where: { $0.id == evidence.id }) { ledger.subscriptionEmails!.append(evidence) }
                            }) else { throw BankError.message("Could not save email suggestions.") }
                        }
                    }
                    page = list.nextPageToken; count += 1
                } while page != nil && count < 5
                _ = store.update { ledger in if let i = ledger.subscriptionMailboxes?.firstIndex(where: { $0.id == mailbox.id }) { ledger.subscriptionMailboxes?[i].checkedAt = Date() } }
                if page != nil { failures.append("\(mailbox.id): only the newest 500 matching emails were checked.") }
            } catch { failures.append("\(mailbox.id): \(error.localizedDescription)") }
        }
        message = failures.isEmpty ? "Emails checked. Review detected subscriptions and cancellations below." : failures.joined(separator: "\n")
    }
    func disconnect(_ email: String, store: LedgerStore) {
        guard !busy else { return }
        do {
            try GmailKeys.remove(email)
            _ = store.update { ledger in ledger.subscriptionMailboxes?.removeAll { $0.id == email }; ledger.subscriptionEmails?.removeAll { $0.mailbox == email } }
            message = "Disconnected on this device. Confirmed subscriptions remain. You can also revoke Tender in your Google Account permissions."
        } catch { message = error.localizedDescription }
    }
    static func clearCredentials() throws { try GmailKeys.remove() }
}
private extension Data { var urlBase64: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") } }
private extension String { var fromURLBase64: Data? { let s = replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"); return Data(base64Encoded: s + String(repeating: "=", count: (4 - s.count % 4) % 4)) } }
