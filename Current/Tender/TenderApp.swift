import SwiftUI
import AppIntents

@main
struct TenderApp: App {
    @State private var store = LedgerStore()
    var body: some Scene {
        WindowGroup {
            Group {
                if store.hasLoaded {
                    RootView()
                } else {
                    ZStack {
                        Ink.paper.ignoresSafeArea()
                        VStack(spacing: 16) {
                            Text("tender").font(.system(.largeTitle, design: .serif))
                            ProgressView("Opening your ledger…")
                        }.foregroundStyle(Ink.green)
                    }.accessibilityIdentifier("ledger-loading")
                }
            }
            .environment(store).tint(Ink.green)
            .task { await store.loadIfNeeded() }
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
