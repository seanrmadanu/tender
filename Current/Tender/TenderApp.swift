import SwiftUI
import AppIntents

@main
struct TenderApp: App {
    @State private var auth = AccountAuth()
    var body: some Scene {
        WindowGroup {
            Group {
                if auth.restoring { LedgerLoadingView() }
                else if let key = auth.storageKey { AuthenticatedLedgerView(accountKey: key).id(key) }
                else { WelcomeLoginView() }
            }
            .environment(auth).tint(Ink.green)
            .task { await auth.restore() }
            .onReceive(NotificationCenter.default.publisher(for: .resetToLogin)) { _ in auth.forgetSession() }
        }
    }
}
private struct AuthenticatedLedgerView: View {
    @State private var store: LedgerStore
    init(accountKey: String) { _store = State(initialValue: LedgerStore(accountKey: accountKey)) }
    var body: some View {
        Group {
            if store.hasLoaded { RootView() }
            else { LedgerLoadingView() }
        }.environment(store).task { await store.loadIfNeeded() }
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
