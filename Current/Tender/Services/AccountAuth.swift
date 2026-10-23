import SwiftUI
import Security
import CryptoKit
import AuthenticationServices
import UserNotifications

private struct SavedAccountSession: Codable {
    var uid: String
    var email: String
    var token: String
    var refresh: String
    var expires: Date
}
private enum AccountSessionKeys {
    static let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: "com.sean.tender.auth", kSecAttrAccount: "firebase"]
    static func read() throws -> SavedAccountSession? {
        var query = query; query[kSecReturnData] = true
        var result: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary, &result)
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess, let data = result as? Data else { throw BankError.message("Unlock your phone to restore sign-in.") }
        return try JSONDecoder().decode(SavedAccountSession.self, from: data)
    }
    static func save(_ session: SavedAccountSession) throws {
        let data = try JSONEncoder().encode(session)
        let values: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let code = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if code == errSecItemNotFound {
            guard SecItemAdd(query.merging(values) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw BankError.message("Unable to remember your login securely.") }
        } else if code != errSecSuccess { throw BankError.message("Unable to remember your login securely.") }
    }
    static func clear() throws {
        let code = SecItemDelete(query as CFDictionary)
        guard code == errSecSuccess || code == errSecItemNotFound else { throw BankError.message("Unlock your phone and retry signing out.") }
    }
}
private final class NoAuthRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor @Observable
final class AccountAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private(set) var uid: String?
    private(set) var email = ""
    private(set) var restoring = true
    private(set) var busy = false
    var message: String?
    private var session: SavedAccountSession?
    private var browser: ASWebAuthenticationSession?
    private var configuration: [String: Any] {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let data = try? Data(contentsOf: url), let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              plist["BUNDLE_ID"] as? String == Bundle.main.bundleIdentifier else { return [:] }
        return plist
    }
    var configured: Bool { configuration["API_KEY"] as? String != nil }
    private var googleID: String { configuration["CLIENT_ID"] as? String ?? "" }
    var googleConfigured: Bool {
        let schemes = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []).flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        return !googleID.isEmpty && schemes.contains(googleID.split(separator: ".").reversed().joined(separator: "."))
    }
    var storageKey: String? {
        guard let uid else { return nil }
        return SHA256.hash(data: Data(((configuration["PROJECT_ID"] as? String ?? "") + ":" + uid).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    private func request(_ method: String, _ body: [String: Any]) async throws -> [String: Any] {
        guard let key = configuration["API_KEY"] as? String else { throw BankError.message("Firebase configuration is missing from this build.") }
        let allowed = ["accounts:signUp", "accounts:signInWithPassword", "accounts:sendOobCode", "accounts:signInWithIdp", "accounts:lookup"]
        guard allowed.contains(method) else { throw BankError.message("Invalid sign-in operation.") }
        let url = URL(string: "https://identitytoolkit.googleapis.com/v1/\(method)?key=\(key)")!
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }
    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let client = URLSession(configuration: .ephemeral, delegate: NoAuthRedirects(), delegateQueue: nil)
        defer { client.invalidateAndCancel() }
        let (data, response) = try await client.data(for: request)
        guard data.count < 1_000_000, let http = response as? HTTPURLResponse else { throw BankError.message("Unexpected sign-in response.") }
        let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(http.statusCode) else {
            let code = (result["error"] as? [String: Any])?["message"] as? String ?? ""
            let text: String
            if code.contains("OPERATION_NOT_ALLOWED") || code.contains("CONFIGURATION_NOT_FOUND") { text = "Enable this sign-in method in Firebase Authentication, then retry." }
            else if code.contains("EMAIL_EXISTS") { text = "An account already uses this email. Try Sign In." }
            else if code.contains("WEAK_PASSWORD") { text = "Choose a stronger password, then retry." }
            else if code.contains("TOO_MANY") { text = "Too many attempts. Wait before trying again." }
            else if code.contains("USER_DISABLED") { text = "This account is disabled. Contact support." }
            else if code.contains("API_KEY") || code.contains("PROJECT") { text = "Check this build's Firebase configuration and API-key restrictions." }
            else { text = "Sign-in could not be completed. Check your details or sign in again." }
            throw BankError.message(text)
        }
        return result
    }
    private func accept(_ result: [String: Any]) throws {
        guard let uid = result["localId"] as? String, !uid.isEmpty, let token = result["idToken"] as? String,
              let refresh = result["refreshToken"] as? String else { throw BankError.message("The account response was incomplete.") }
        let account = SavedAccountSession(uid: uid, email: result["email"] as? String ?? "", token: token, refresh: refresh,
                                          expires: Date().addingTimeInterval(Double(result["expiresIn"] as? String ?? "3600") ?? 3600))
        try AccountSessionKeys.save(account)
        session = account; email = account.email; self.uid = uid
    }
    func restore() async {
        guard restoring else { return }
        busy = true; defer { busy = false; restoring = false }
        do {
            guard let saved = try AccountSessionKeys.read() else { return }
            try await refresh(saved)
        } catch { message = "Could not restore sign-in. Check your connection and sign in again. Your saved ledger is preserved." }
    }
    private func refresh(_ saved: SavedAccountSession) async throws {
        guard let key = configuration["API_KEY"] as? String else { throw BankError.message("Firebase setup required.") }
        var request = URLRequest(url: URL(string: "https://securetoken.googleapis.com/v1/token?key=\(key)")!)
        request.httpMethod = "POST"; request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Bundle.main.bundleIdentifier ?? "", forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["grant_type": "refresh_token", "refresh_token": saved.refresh])
        let result = try await send(request)
        guard let uid = result["user_id"] as? String, uid == saved.uid, let token = result["id_token"] as? String,
              let refresh = result["refresh_token"] as? String else { throw BankError.message("Sign in again to continue.") }
        let lookup = try await self.request("accounts:lookup", ["idToken": token])
        guard let user = (lookup["users"] as? [[String: Any]])?.first, user["localId"] as? String == uid,
              user["disabled"] as? Bool != true else { throw BankError.message("Sign in again to continue.") }
        try accept(["localId": uid, "idToken": token, "refreshToken": refresh, "email": user["email"] as? String ?? saved.email, "expiresIn": result["expires_in"] as? String ?? "3600"])
    }
    func emailLogin(_ email: String, password: String, create: Bool) async {
        guard !busy else { return }; busy = true; message = nil; defer { busy = false }
        do { try accept(try await request(create ? "accounts:signUp" : "accounts:signInWithPassword", ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password, "returnSecureToken": true])) }
        catch { message = error.localizedDescription }
    }
    func resetPassword(_ email: String) async {
        guard !busy else { return }; busy = true; message = nil; defer { busy = false }
        do { _ = try await request("accounts:sendOobCode", ["requestType": "PASSWORD_RESET", "email": email.trimmingCharacters(in: .whitespacesAndNewlines)]); message = "If this email has an eligible account, a reset message will arrive. Check your inbox." }
        catch { message = "Could not request a reset. Check the email address and connection, then retry." }
    }
    func signOut() {
        guard !busy else { return }
        do {
            try AccountSessionKeys.clear()
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            UserDefaults.standard.removeObject(forKey: "openShopping")
            forgetSession()
        } catch { message = error.localizedDescription }
    }
    func forgetSession() { browser?.cancel(); browser = nil; session = nil; uid = nil; email = ""; message = nil }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    private func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw BankError.message("Could not start a secure sign-in.") }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    func googleLogin() async {
        guard !busy else { return }
        guard googleConfigured else { message = "Enable Google in Firebase Authentication, then download the updated GoogleService-Info.plist with CLIENT_ID and REVERSED_CLIENT_ID. This build needs that updated configuration."; return }
        busy = true; message = nil; defer { busy = false; browser = nil }
        do {
            let state = try random(), verifier = try random(), nonce = try random()
            let scheme = googleID.split(separator: ".").reversed().joined(separator: "."), redirect = scheme + ":/oauthredirect"
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
            var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            url.queryItems = ["client_id": googleID, "redirect_uri": redirect, "response_type": "code", "scope": "openid email profile", "state": state, "nonce": nonce, "code_challenge": challenge, "code_challenge_method": "S256", "prompt": "select_account"].map { URLQueryItem(name: $0.key, value: $0.value) }
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let browser = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: scheme) { url, error in
                    if let url { continuation.resume(returning: url) } else { continuation.resume(throwing: error ?? BankError.message("Sign-in cancelled.")) }
                }
                browser.presentationContextProvider = self; browser.prefersEphemeralWebBrowserSession = true; self.browser = browser
                if !browser.start() { continuation.resume(throwing: BankError.message("Google sign-in could not open.")) }
            }
            let query = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard callback.scheme == scheme, query.first(where: { $0.name == "state" })?.value == state,
                  let code = query.first(where: { $0.name == "code" })?.value else { throw BankError.message("Google sign-in could not be verified." ) }
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
            request.httpMethod = "POST"; request.timeoutInterval = 25
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = form(["client_id": googleID, "code": code, "redirect_uri": redirect, "grant_type": "authorization_code", "code_verifier": verifier])
            let result = try await send(request)
            guard let idToken = result["id_token"] as? String else { throw BankError.message("Google did not return a sign-in token.") }
            // Check this request's nonce/client before sending the exact token to
            // Firebase for cryptographic verification. Decoding alone never signs in.
            let parts = idToken.split(separator: ".")
            guard parts.count == 3 else { throw BankError.message("Invalid Google identity response.") }
            let encoded = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            guard let data = Data(base64Encoded: encoded + String(repeating: "=", count: (4 - encoded.count % 4) % 4)),
                  let claims = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  claims["nonce"] as? String == nonce, claims["aud"] as? String == googleID else {
                throw BankError.message("Google sign-in did not match this request.")
            }
            // Firebase validates Google's signed identity token; never trust locally decoded claims to establish a session.
            try accept(try await self.request("accounts:signInWithIdp", ["requestUri": "http://localhost", "postBody": String(data: form(["id_token": idToken, "providerId": "google.com", "nonce": nonce]), encoding: .utf8)!, "returnSecureToken": true]))
        } catch { message = error.localizedDescription }
    }
    private func form(_ values: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(values.map { ($0.key.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") + "=" + ($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "") }.joined(separator: "&").utf8)
    }
}
