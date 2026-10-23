import Foundation
import Security
import UserNotifications
import WebKit

/// Clears Tender’s persisted Firebase REST session and app-owned local state.
/// A successful reset posts resetToLogin to clear the in-memory session too.
@MainActor
enum AppReset {
    static func forgetLoginAndPreferences() async throws {
        // Firebase session service. Only Tender-owned entries are removed.
        let result = SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.sean.tender.auth"
        ] as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            throw BankError.message("Could not clear saved login. Unlock your device and retry Reset App.")
        }
        try BankConfiguration.remove()
        try GmailSubscriptions.clearCredentials()
        // Full reset covers every local account and the legacy personal ledger.
        for folder in ["Tender", "TenderAccounts"] {
            let url = URL.documentsDirectory.appending(path: folder, directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        UserDefaults.standard.set(true, forKey: "bankAccessPaused")
        URLCache.shared.removeAllCachedResponses()
        for cookie in HTTPCookieStorage.shared.cookies ?? [] {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        await WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        let notifications = UNUserNotificationCenter.current()
        notifications.removeAllPendingNotificationRequests()
        notifications.removeAllDeliveredNotifications()
    }
}
