import SwiftUI

enum SheetRoute: String, Identifiable { case expense, shopping, settings, account, recurring, grocery; var id: String { rawValue } }
struct RootView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    @State private var sheet: SheetRoute?
    var body: some View {
        @Bindable var store = store
        TabView(selection: $tab) {
            NavigationStack { OverviewView(sheet: $sheet) }.tabItem { Label("Overview", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { BudgetView() }.tabItem { Label("Budgets", systemImage: "chart.pie") }.tag(1)
            NavigationStack { ActivityView(sheet: $sheet) }.tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }.tag(2)
            NavigationStack { GroceryView(sheet: $sheet) }.tabItem { Label("Groceries", systemImage: "basket") }.tag(3)
            NavigationStack { ReportView() }.tabItem { Label("Reports", systemImage: "chart.xyaxis.line") }.tag(4)
        }
        .sheet(item: $sheet) { route in
            NavigationStack {
                switch route {
                case .expense: ExpenseForm()
                case .shopping: ShoppingView()
                case .settings: SettingsView()
                case .account: AccountForm()
                case .recurring: RecurringForm()
                case .grocery: GroceryForm()
                }
            }.environment(store).tint(Ink.green)
        }
        .alert("Couldn’t complete this action", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("Dismiss", role: .cancel) {} } message: { Text(store.error ?? "") }
        .onOpenURL { url in if url.scheme == "tender" && url.host == "shopping" { sheet = .shopping } }
        .onReceive(NotificationCenter.default.publisher(for: .openShopping)) { _ in openShoppingIfNeeded() }
        .onChange(of: phase) { _, phase in if phase == .active { openShoppingIfNeeded(); Task { await store.refreshReminders() } } }
        .onAppear { openShoppingIfNeeded() }
    }
    private func openShoppingIfNeeded() {
        if UserDefaults.standard.bool(forKey: "openShopping") { UserDefaults.standard.removeObject(forKey: "openShopping"); sheet = .shopping }
    }
}
struct OverviewView: View {
    @Environment(LedgerStore.self) private var store
    @Binding var sheet: SheetRoute?
    private var ledger: Ledger { store.ledger }
    var body: some View {
        PaperScreen {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YOUR EVERYDAY LEDGER").font(.system(.caption2, design: .monospaced).weight(.semibold)).tracking(2).foregroundStyle(Ink.muted)
                    Text("A little more intentional.").font(.system(.title2, design: .serif))
                }
                Spacer()
                Button { sheet = .settings } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44).background(Ink.card, in: Circle()).overlay(Circle().stroke(Ink.line, lineWidth: 1)) }.accessibilityLabel("Settings and exports")
            }
            if ledger.isDemo {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                    Text("Sample ledger · explore freely").font(.caption.weight(.medium))
                    Spacer()
                    Button("Start fresh") { sheet = .settings }.font(.caption.weight(.bold)).frame(minHeight: 44)
                }.foregroundStyle(Ink.muted)
            }
            balanceCard
            HStack(spacing: 12) {
                Button { sheet = .expense } label: { Label("Add expense", systemImage: "plus").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton())
                Button { sheet = .shopping } label: { Image(systemName: "bag").font(.title3).frame(width: 56, height: 54).background(Ink.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Ink.line, lineWidth: 1)) }.accessibilityLabel("Open shopping mode")
            }
            VStack(alignment: .leading, spacing: 15) {
                HStack { SectionHeading(title: "This month", subtitle: Date().formatted(.dateTime.month(.wide).year())); Spacer(); Image(systemName: "leaf").foregroundStyle(Ink.accent).font(.title2) }
                PaperCard {
                    AmountRow(label: "Spent so far", amount: ledger.spent(in: ledger.month()))
                    BudgetMeter(spent: ledger.spent(in: ledger.month()), limit: ledger.monthlyBudget)
                    AmountRow(label: "Monthly allocation", amount: ledger.monthlyBudget)
                    Text("\(Money.format(ledger.monthlyBudget - ledger.spent(in: ledger.month()))) left across your categories").font(.caption).foregroundStyle(Ink.muted)
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                SectionHeading(title: "Your envelopes", subtitle: "A place for every dollar.")
                ForEach(ledger.categories.prefix(3)) { category in
                    HStack(spacing: 12) {
                        CategoryIcon(symbol: category.symbol)
                        VStack(alignment: .leading, spacing: 4) { Text(category.name).font(.subheadline.weight(.semibold)); Text("\(Money.format(ledger.spent(category: category.id, in: ledger.month()))) of \(Money.format(category.limit))").font(.caption).foregroundStyle(Ink.muted) }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) { Text(Money.format(ledger.remaining(category))).font(.subheadline.weight(.semibold)); Text("remaining").font(.caption2).foregroundStyle(Ink.muted) }
                    }
                }
            }
            PaperCard {
                HStack { Image(systemName: "hand.tap").font(.title2); Text("Pause before you purchase.").font(.system(.headline, design: .serif)) }
                Text("Shopping Mode checks your category and cash before you commit. Add it to Triple Back Tap in Settings.").font(.subheadline).foregroundStyle(Ink.muted)
                Button("Check a purchase →") { sheet = .shopping }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
        }
        .navigationTitle("tender").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Image(systemName: "seal").foregroundStyle(Ink.green) }; ToolbarItem(placement: .topBarTrailing) { Text(Date().formatted(.dateTime.month(.abbreviated).day())).font(.system(.caption, design: .monospaced)).foregroundStyle(Ink.muted) } }
    }
    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("AVAILABLE BALANCE").font(.system(.caption, design: .monospaced).weight(.medium)).tracking(1.5); Spacer(); Image(systemName: "building.columns") }
            MoneyText(amount: ledger.available).font(.system(.largeTitle, design: .serif).weight(.medium)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) { Text("After upcoming bills").font(.caption).opacity(0.85); MoneyText(amount: ledger.available - ledger.upcomingReserve()).font(.title3.weight(.semibold)).monospacedDigit() }
                Spacer()
                Button { sheet = .account } label: { Image(systemName: "arrow.up.right").font(.headline).frame(width: 44, height: 44).overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1)) }.accessibilityLabel("Manage account balances")
            }
            Text(ledger.isDemo ? "SAMPLE DATA · NOT YOUR BANK BALANCE" : "RECORDED BALANCES · BILLS RESERVED FOR 30 DAYS").font(.system(.caption2, design: .monospaced)).opacity(0.85)
        }.padding(24).foregroundStyle(Color(red: 0.97, green: 0.96, blue: 0.90)).background {
            ZStack { Color(red: 0.08, green: 0.23, blue: 0.18); Engraving(light: true).mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)) }
        }.clipShape(RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).inset(by: 7).stroke(.white.opacity(0.22), lineWidth: 0.5))
    }
}
