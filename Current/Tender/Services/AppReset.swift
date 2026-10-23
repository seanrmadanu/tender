import Foundation
import Security
import UserNotifications
import WebKit

/// Clears Tender's remembered state. Provider SDKs must additionally sign out
/// here when they are introduced; the current build has no account auth SDK.
@MainActor
enum AppReset {
    static func forgetLoginAndPreferences() async throws {
        // Reserved account-session service. Only Tender-owned entries are removed.
        let result = SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.sean.tender.auth"
        ] as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            throw BankError.message("Could not clear saved login. Unlock your device and retry Reset App.")
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
