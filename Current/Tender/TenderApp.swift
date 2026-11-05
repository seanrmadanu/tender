import SwiftUI
import AppIntents

@main
struct TenderApp: App {
    @State private var auth = AccountAuth()
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--signup-ui-test") {
                    if let key = auth.storageKey { AuthenticatedLedgerView(accountKey: key, auth: auth).id(key) }
                    else { WelcomeLoginView() }
                }
                else if ProcessInfo.processInfo.arguments.contains("--ui-testing") && !ProcessInfo.processInfo.arguments.contains("--auth-startup-test") { UITestLedgerView() }
                else { accountContent }
                #else
                accountContent
                #endif
            }
            .environment(auth).tint(Ink.green)
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") && !ProcessInfo.processInfo.arguments.contains("--auth-startup-test") { return }
                #endif
                await auth.restore()
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetToLogin)) { _ in auth.forgetSession() }
            .onOpenURL { url in
                guard url.scheme == "tender", url.host == "ai-connect",
                      let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "request" })?.value,
                      code.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) != nil else { return }
                UserDefaults.standard.set(code.lowercased(), forKey: "pendingAIConnection")
                NotificationCenter.default.post(name: .openAIConnection, object: nil)
            }
        }
    }
    @ViewBuilder private var accountContent: some View {
        if auth.restoring { LedgerLoadingView() }
        else if let key = auth.storageKey { AuthenticatedLedgerView(accountKey: key, auth: auth).id(key) }
        else { WelcomeLoginView() }
    }
}
#if DEBUG
private struct UITestLedgerView: View {
    @State private var store = LedgerStore()
    var body: some View {
        ZStack { if store.startupReady { RootView() } else { LedgerLoadingView() } }
            .environment(store).task { await store.prepareForHome() }
    }
}
#endif
private struct AuthenticatedLedgerView: View {
    @State private var store: LedgerStore
    init(accountKey: String, auth: AccountAuth) { _store = State(initialValue: LedgerStore(accountKey: accountKey, accountAuth: auth)) }
    var body: some View {
        ZStack {
            if store.startupReady { RootView() }
            else { LedgerLoadingView() }
        }.environment(store).task { await store.prepareForHome() }
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
extension Notification.Name { static let openAIConnection = Notification.Name("openAIConnection") }
