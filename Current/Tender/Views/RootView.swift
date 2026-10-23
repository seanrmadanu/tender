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
            NavigationStack { OverviewView(sheet: $sheet) }.tabItem { Label("Home", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { BudgetView() }.tabItem { Label("Budgets", systemImage: "chart.pie") }.tag(1)
            NavigationStack { ActivityView(sheet: $sheet) }.tabItem { Label("Activity", systemImage: "list.bullet.rectangle") }.tag(2)
            NavigationStack { GroceryView(sheet: $sheet) }.tabItem { Label("Groceries", systemImage: "basket") }.tag(3)
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
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
        .onChange(of: phase) { _, phase in if phase == .active { openShoppingIfNeeded(); Task { await store.gmail.refresh(store: store) }; Task { await store.refreshReminders(); await store.refreshBank() } } }
        .onAppear { openShoppingIfNeeded() }
        .task {
            await store.gmail.refresh(store: store)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(900)) } catch { break }
                if phase == .active { await store.gmail.refresh(store: store) }
            }
        }
        .task {
            await store.refreshReminders()
            await store.refreshBank()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(300)) } catch { break }
                if phase == .active { await store.refreshBank() }
            }
        }
    }
    private func openShoppingIfNeeded() {
        if UserDefaults.standard.bool(forKey: "openShopping") { UserDefaults.standard.removeObject(forKey: "openShopping"); sheet = .shopping }
    }
}
struct OverviewView: View {
    @Environment(LedgerStore.self) private var store
    @Binding var sheet: SheetRoute?
    private var ledger: Ledger { store.ledger }
    @State private var selectedCard: UUID?
    @State private var editingCards = false
    @State private var removingCard: Account?
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        PaperScreen {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR EVERYDAY LEDGER").font(.system(.caption2, design: .monospaced).weight(.semibold)).tracking(2).foregroundStyle(Ink.muted)
                Text("A little more intentional.").font(.system(.title2, design: .serif))
            }
            if ledger.isDemo { Label("Sample ledger · not connected to a bank", systemImage: "sparkle").font(.caption).foregroundStyle(Ink.muted) }
            HStack {
                Text("Accounts").font(.headline)
                Spacer()
                Button(editingCards ? "Done" : "Edit") { editingCards.toggle() }.disabled(ledger.activeAccounts.isEmpty)
            }
            if ledger.activeAccounts.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    Label("YOUR ACCOUNTS", systemImage: "wallet.bifold").font(.system(.caption, design: .monospaced)).tracking(1.5)
                    Text("Your wallet starts here.").font(.system(.title, design: .serif))
                    Text("Add your account or cash wallet to begin.").font(.subheadline)
                    Button { sheet = .account } label: { Label("Add your first account", systemImage: "plus.circle").frame(minHeight: 44) }
                        .buttonStyle(.plain)
                }.banknoteCard()
            } else if editingCards {
                VStack(spacing: textSize.isAccessibilitySize ? 12 : -30) {
                    ForEach(ledger.activeAccounts) { account in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(account.name).font(.headline)
                                Text(Money.format(account.available)).font(.subheadline).monospacedDigit()
                            }
                            Spacer()
                            Button(role: .destructive) { removingCard = account } label: {
                                Image(systemName: "trash").frame(width: 44, height: 44)
                            }.accessibilityLabel("Remove \(account.name) from wallet")
                        }.padding(.bottom, textSize.isAccessibilitySize ? 0 : 30).banknoteCard()
                    }
                }
                Text("Removing a card keeps its purchases. Restore it in Settings → Accounts.").font(.caption).foregroundStyle(Ink.muted)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(ledger.activeAccounts) { account in
                            NavigationLink { AccountDetailView(accountID: account.id) } label: {
                                WalletAccountCard(account: account).padding(.horizontal, 3)
                            }.buttonStyle(.plain).containerRelativeFrame(.horizontal).id(account.id)
                        }
                    }.scrollTargetLayout()
                }.scrollTargetBehavior(.paging).scrollIndicators(.hidden).scrollPosition(id: $selectedCard)
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(ledger.activeAccounts) { account in
                            Button { selectedCard = account.id } label: {
                                Circle().fill((selectedCard ?? ledger.activeAccounts.first?.id) == account.id ? Ink.green : Ink.muted.opacity(0.35))
                                    .frame(width: 7, height: 7).frame(width: 44, height: 44)
                            }.accessibilityLabel("Show \(account.name)")
                                .accessibilityAddTraits((selectedCard ?? ledger.activeAccounts.first?.id) == account.id ? .isSelected : [])
                        }
                    }.frame(minWidth: 0)
                }.scrollIndicators(.hidden).defaultScrollAnchor(.center).frame(height: 44)
                    .frame(maxWidth: .infinity)
                Text("\(ledger.activeAccounts.count) accounts · Swipe or tap a dot to switch.").font(.caption).foregroundStyle(Ink.muted)
            }
            if store.bankUpdating { ProgressView("Checking bank information…") }
            if let message = store.bankMessage { Text(message).font(.caption).foregroundStyle(Ink.warning) }
            if store.bankAccessPaused { Text("Bank access is paused. Reconnect in Settings to retrieve current information.").font(.caption).foregroundStyle(Ink.warning) }
            NavigationLink { BankActivityView() } label: { Label("Bank activity", systemImage: "building.columns") }
            ForEach(Array((ledger.bankActivity ?? []).flatMap(\.transactions).sorted { $0.date > $1.date }.prefix(5))) { transaction in
                NavigationLink { ReviewBankPurchase(transaction: transaction) } label: { BankActivityRow(transaction: transaction) }.buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 15) {
                HStack { SectionHeading(title: "This month", subtitle: Date().formatted(.dateTime.month(.wide).year())); Spacer(); Image(systemName: "leaf").foregroundStyle(Ink.accent).font(.title2) }
                PaperCard {
                    AmountRow(label: "Recorded spending", amount: ledger.spent(in: ledger.month()))
                    Text("Review imported bank purchases to include them in these totals.").font(.caption).foregroundStyle(Ink.muted)
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
                Button("Check a purchase →") { sheet = .shopping }.accessibilityIdentifier("open-shopping").font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
        }
        .navigationTitle("tender").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove card from wallet?", isPresented: Binding(get: { removingCard != nil }, set: { if !$0 { removingCard = nil } }), titleVisibility: .visible) {
            if let account = removingCard {
                Button("Remove \(account.name)", role: .destructive) {
                    if store.update({ $0.archiveAccount(account.id) }) {
                        selectedCard = store.ledger.activeAccounts.first?.id
                        if store.ledger.activeAccounts.isEmpty { editingCards = false }
                    }
                    removingCard = nil
                }
            }
        } message: { Text("Purchases and receipts stay in Activity. This card stops contributing to available cash. Bank connection access is managed separately in Settings.") }
        .bottomAdd("Record Purchase") { sheet = .expense }
        .refreshable { await store.refreshBank(force: true) }
        .toolbar { ToolbarItem(placement: .topBarLeading) { Image(systemName: "seal").foregroundStyle(Ink.green) }; ToolbarItem(placement: .topBarTrailing) { Text(Date().formatted(.dateTime.month(.abbreviated).day())).font(.system(.caption, design: .monospaced)).foregroundStyle(Ink.muted) } }
    }
}
struct WalletAccountCard: View {
    @Environment(LedgerStore.self) private var store
    let account: Account
    private var snapshot: BankSnapshot? { store.bankSnapshots.first { "production:" + $0.id == account.bankAccountKey } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(account.name).font(.headline); Spacer(); Image(systemName: account.isCash == true ? "banknote" : "building.columns") }
            Text(snapshot?.availableCents != nil ? "BANK AVAILABLE · CACHED" : "RECORDED AVAILABLE").font(.system(.caption, design: .monospaced).weight(.medium)).tracking(1.5)
            MoneyText(amount: snapshot?.availableCents ?? account.available).font(.system(.largeTitle, design: .serif).weight(.medium)).minimumScaleFactor(0.6).lineLimit(1)
            if let snapshot {
                Text("Retrieved \(snapshot.retrievedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                Text(Date().timeIntervalSince(snapshot.retrievedAt) > 900 ? "Stale retrieval · pull down to retry. Bank update time unknown." : "Bank update time unknown. Pending purchases may be missing.").font(.caption)
                Text("Ledger after manual entries: \(Money.format(account.available))").font(.caption)
            } else {
                Text("Recorded \((account.snapshotAt ?? account.updated).formatted(date: .abbreviated, time: .shortened))").font(.caption)
                Text(account.bankAccountKey == nil ? "Manual balance · update when needed" : "Saved snapshot · not a live bank balance").font(.caption)
            }
        }.frame(maxWidth: .infinity, minHeight: 210, alignment: .leading).banknoteCard()
    }
}

// The original banknote surface stays dark green in both appearances. Ink.green
// is a foreground color and becomes pale in Dark Mode, so it cannot be this fill.
private extension View {
    func banknoteCard() -> some View {
        padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(Color(red: 0.97, green: 0.96, blue: 0.90))
            .background {
                ZStack {
                    Color(red: 0.08, green: 0.23, blue: 0.18)
                    Engraving(light: true).mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).inset(by: 7).stroke(.white.opacity(0.22), lineWidth: 0.5))
    }
}
