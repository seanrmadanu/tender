import SwiftUI
import AppIntents

@main
struct TenderApp: App {
    @State private var store = LedgerStore()
    @State private var showLogin = true
    var body: some Scene {
        WindowGroup {
            // Fresh installs and upgrades both start at account entry. The old
            // personal ledger is not loaded or migrated into an arbitrary login.
            Group {
                if showLogin { WelcomeLoginView() }
                else if store.hasLoaded { RootView().environment(store) }
                else { LedgerLoadingView().task { await store.loadIfNeeded() } }
            }.tint(Ink.green)
                .onReceive(NotificationCenter.default.publisher(for: .resetToLogin)) { _ in showLogin = true }
        }
    }
}
struct ShoppingIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Shopping Mode"
    static var description = IntentDescription("Check a purchase against your category budget and recorded cash.")
    static var openAppWhenRun: Bool = true
    @MainActor func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "openShopping")
        NotificationCenter.default.post(name: .openShopping, object: nil)
        return .result()
    }
}
struct TenderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShoppingIntent(), phrases: ["Open shopping mode in \(.applicationName)", "Check my budget in \(.applicationName)"], shortTitle: "Shopping Mode", systemImageName: "basket")
    }
}
extension Notification.Name { static let openShopping = Notification.Name("openShopping") }

extension Notification.Name { static let resetToLogin = Notification.Name("resetToLogin") }
