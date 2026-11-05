import SwiftUI

enum SheetRoute: String, Identifiable { case expense, shopping, settings, account, recurring, grocery; var id: String { rawValue } }
struct RootView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.scenePhase) private var phase
    @State private var tab = 0
    @State private var sheet: SheetRoute?
    @State private var settingsPath: [SettingsRoute] = []
    @State private var settingsRootID = UUID()
    @State private var profileNavigation: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        @Bindable var store = store
        TabView(selection: $tab) {
            NavigationStack { OverviewView(sheet: $sheet, onOpenProfile: openProfile) }.tabItem { Label("Home", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { BudgetView() }.tabItem { Label("Budgets", systemImage: "chart.pie") }.tag(1)
            NavigationStack { GroceryView(sheet: $sheet) }.tabItem { Label("Groceries", systemImage: "basket") }.tag(3)
            NavigationStack { ActivityView() }.tabItem { Label("Activity", systemImage: "chart.xyaxis.line") }.tag(2)
            NavigationStack(path: $settingsPath) { SettingsView().navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .profile: ProfileSettingsView()
                case .aiConnections: AIConnectionsView()
                case .accounts: AccountForm()
                case .updates: UpdateSettingsView()
                case .archive: ArchiveSettingsView()
                case .backup: BackupSettingsView()
                case .privacy: PrivacySettingsView()
                }
            } }.id(settingsRootID).tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
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
        .onOpenURL { url in
            if url.scheme == "tender" && url.host == "shopping" { sheet = .shopping }
            else { Task { await store.acceptBankReturn(url) } }
        }
        .onChange(of: store.bankNetwork.revision) { _, _ in if phase == .active { Task { await store.networkDidChange() } } }
        .onReceive(NotificationCenter.default.publisher(for: .openShopping)) { _ in openShoppingIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .openAIConnection)) { _ in openAIIfNeeded() }
        .onChange(of: phase) { _, phase in if phase == .active { openShoppingIfNeeded(); openAssistantScreenIfNeeded(); Task { await store.gmail.refresh(store: store) }; Task { await store.refreshReminders(); await store.synchronizeCloud(); await store.networkDidChange() } } }
        .onAppear { openShoppingIfNeeded(); openAIIfNeeded(); openAssistantScreenIfNeeded() }
        .onChange(of: store.ledger.assistantScreenRequest) { _, _ in openAssistantScreenIfNeeded() }
        .onChange(of: sheet) { _, route in if route == nil { openAssistantScreenIfNeeded() } }
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
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                if phase == .active { await store.synchronizeCloud(); await store.refreshBank() }
            }
        }
    }
    private func openProfile() {
        profileNavigation?.cancel()
        settingsPath = []
        settingsRootID = UUID()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { tab = 4 }
        profileNavigation = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 300)) } catch { return }
            guard tab == 4 else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { settingsPath = [.profile] }
        }
    }
    private func openShoppingIfNeeded() {
        if UserDefaults.standard.bool(forKey: "openShopping") { UserDefaults.standard.removeObject(forKey: "openShopping"); sheet = .shopping }
    }
    private func openAIIfNeeded() {
        guard let code = UserDefaults.standard.string(forKey: "pendingAIConnection") else { return }
        UserDefaults.standard.removeObject(forKey: "pendingAIConnection")
        store.pendingAIAuthorization = code
        settingsPath = []; settingsRootID = UUID()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { tab = 4; settingsPath = [.aiConnections] }
    }
    private func openAssistantScreenIfNeeded() {
        guard phase == .active, sheet == nil, let request = store.ledger.assistantScreenRequest,
              let created = request.createdAt, abs(created.timeIntervalSinceNow) < 86_400 else { return }
        let key = "assistant-screen-" + store.root.lastPathComponent
        guard UserDefaults.standard.string(forKey: key) != request.id.uuidString else { return }
        UserDefaults.standard.set(request.id.uuidString, forKey: key)
        profileNavigation?.cancel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            switch request.screen {
            case .home: tab = 0
            case .budgets: tab = 1
            case .groceries: tab = 3
            case .activity: tab = 2
            case .shopping: sheet = .shopping
            case .addPurchase: sheet = .expense
            default:
                let route: SettingsRoute
                switch request.screen {
                case .profile: route = .profile
                case .accounts: route = .accounts
                case .updates: route = .updates
                case .archive: route = .archive
                case .backup: route = .backup
                case .privacy: route = .privacy
                default: route = .aiConnections
                }
                settingsPath = []; settingsRootID = UUID(); tab = 4; settingsPath = [route]
            }
        }
    }
}
struct OverviewView: View {
    @Environment(LedgerStore.self) private var store
    @Binding var sheet: SheetRoute?
    var onOpenProfile: () -> Void
    private var ledger: Ledger { store.ledger }
    @State private var selectedWalletID: UUID?
    @State private var openAccount: Account?
    private var focusedAccount: Account? { ledger.activeAccounts.first { $0.id == selectedWalletID } ?? ledger.primaryAccount }
    private var recentTransactions: [AccountActivityEntry] { Array(ledger.accountActivity(for: focusedAccount).prefix(4)) }
    @State private var activitySection = 0
    var body: some View {
        PaperScreen {
            if ledger.isDemo { Label("Sample ledger · not connected to a bank", systemImage: "sparkle").font(.caption).foregroundStyle(Ink.muted) }
            if store.cloudState.enabled, let message = store.cloudMessage {
                Label(message, systemImage: "icloud.slash").font(.footnote).foregroundStyle(Ink.warning)
            }
            Text("Accounts").font(.headline)
            if ledger.activeAccounts.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    Label("YOUR ACCOUNTS", systemImage: "wallet.bifold").font(.system(.caption, design: .monospaced)).tracking(1.5)
                    Text("Your wallet starts here.").font(.system(.title, design: .serif))
                    Text("Add your account or cash wallet to begin.").font(.subheadline)
                    Button { sheet = .account } label: { Label("Add your first account", systemImage: "plus.circle").frame(minHeight: 44) }
                        .buttonStyle(.plain)
                }.banknoteCard()
            } else if let current = focusedAccount {
                VStack(alignment: .leading, spacing: 10) {
                    LeatherWalletView(accounts: ledger.activeAccounts, initialAccount: current, total: ledger.available,
                        onSelect: { selectedWalletID = $0 }, onOpen: { openAccount = $0 })
                    BankSyncStatusView()
                }
            }
            PaperCard {
                Picker("Activity", selection: $activitySection) {
                    Text("Transactions").tag(0)
                    Text("Subscriptions").tag(1)
                }.pickerStyle(.segmented).accessibilityIdentifier("home-activity-switch")
                if activitySection == 0 {
                if recentTransactions.isEmpty {
                    Text("No transactions yet.").font(.subheadline).foregroundStyle(Ink.muted)
                }
                ForEach(recentTransactions) { transaction in
                    Divider()
                    NavigationLink {
                        switch transaction {
                        case .bank(let bank): ReviewBankPurchase(transaction: bank)
                        case .manual(let expense): ExpenseDetail(expense: expense)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            AccountActivityRow(entry: transaction)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Ink.muted)
                        }
                    }.buttonStyle(.plain)
                }
                Divider()
                NavigationLink { BankActivityView(accountID: focusedAccount?.id) } label: {
                    HStack {
                        Text("Show all transactions")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }.accessibilityIdentifier("show-all-bank-transactions")
                } else {
                    Text("Possible subscriptions").font(.headline)
                    let suggestions = Array(ledger.possibleSubscriptions(for: focusedAccount).prefix(4))
                    if suggestions.isEmpty {
                        Text("No possible subscriptions found yet.").font(.subheadline).foregroundStyle(Ink.muted)
                    }
                    ForEach(suggestions) { suggestion in
                        Divider()
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.merchant).font(.subheadline.weight(.semibold))
                                Text("\(suggestion.cycle.rawValue) · \(suggestion.occurrences) similar charges").font(.caption).foregroundStyle(Ink.muted)
                            }
                            Spacer()
                            Text(Money.format(suggestion.amount)).font(.subheadline)
                        }.frame(minHeight: 48)
                    }
                    Text("Based on repeated charges. These are suggestions to review.").font(.caption).foregroundStyle(Ink.muted)
                    Divider()
                    NavigationLink { PossibleSubscriptionsView(accountID: focusedAccount?.id) } label: {
                        HStack { Text("Show all possible subscriptions"); Spacer(); Image(systemName: "chevron.right") }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
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
        .navigationDestination(isPresented: Binding(get: { openAccount != nil }, set: { if !$0 { openAccount = nil } })) { if let account = openAccount { AccountDetailView(accountID: account.id) } }
        .bottomAdd("Add manual expense", identifier: "Record Purchase") { sheet = .expense }
        .refreshable { await store.refreshBank(force: true) }
        .toolbar { profileToolbar; ToolbarItem(placement: .topBarTrailing) { Text(Date().formatted(.dateTime.month(.abbreviated).day())).font(.system(.caption, design: .monospaced)).foregroundStyle(Ink.muted).padding(.horizontal, 8).padding(.vertical, 5).frame(minHeight: 44) } }
    }
    @ToolbarContentBuilder private var profileToolbar: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) { profileButton }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) { profileButton }
        }
    }
    private var profileButton: some View {
        Button(action: onOpenProfile) {
            ProfileAvatar(size: 54.4).frame(width: 60.8, height: 60.8)
                .background(.regularMaterial, in: Circle())
                .overlay { Circle().stroke(Ink.line, lineWidth: 0.7) }
                .contentShape(Circle())
        }.buttonStyle(.plain).buttonBorderShape(.circle)
            .accessibilityLabel("Profile photo").accessibilityIdentifier("profile-photo-button")
            .accessibilityValue(store.ledger.profilePhoto == nil ? "Default logo" : "Photo set")
    }
}
private struct LeatherWalletView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var textSize
    let accounts: [Account]
    let initialAccount: Account
    let total: Int64
    let onSelect: (UUID) -> Void
    let onOpen: (Account) -> Void
    @State private var order: [UUID] = []
    @State private var revealed = false
    @State private var lift: CGFloat = 0
    @State private var tilt = 0.0
    @State private var balanceVisible = false
    @State private var cardInFront = false
    @State private var dragX: CGFloat = 0
    @State private var dragY: CGFloat = 0
    @State private var dragAngle = 0.0
    @State private var outgoingID: UUID?
    @State private var placingAtBack = false
    @State private var stackNudge: CGFloat = 0
    @State private var switching = false
    @State private var swipeTask: Task<Void, Never>?
    private var height: CGFloat { textSize.isAccessibilitySize ? 520 : 350 }
    private var deck: [Account] {
        let ids = order.isEmpty ? [initialAccount.id] + accounts.filter { $0.id != initialAccount.id }.map(\.id) : order
        return ids.compactMap { id in accounts.first { $0.id == id } } + accounts.filter { !ids.contains($0.id) }
    }
    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width - 4, 460)
            let cardHeight: CGFloat = textSize.isAccessibilitySize ? 330 : width * 0.56
            ZStack {
                RoundedRectangle(cornerRadius: 25)
                    .fill(LinearGradient(colors: [Color(red: 0.47, green: 0.28, blue: 0.20), Color(red: 0.22, green: 0.11, blue: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { LeatherGrain().clipShape(RoundedRectangle(cornerRadius: 25)) }
                    .overlay { RoundedRectangle(cornerRadius: 21).inset(by: 6).stroke(.white.opacity(0.16), lineWidth: 1) }
                    .frame(width: width, height: 222)
                    .shadow(color: .black.opacity(0.3), radius: 14, y: 12)
                    .offset(y: 48 + lift * 18)
                ForEach(Array(deck.enumerated()), id: \.element.id) { index, card in
                    deckCard(card, index: index, width: width, height: cardHeight)
                }
                pocket(width: width)
                    .frame(width: width, height: textSize.isAccessibilitySize ? 195 : 168)
                    .shadow(color: .black.opacity(0.22), radius: 5, y: -3)
                    .offset(y: (textSize.isAccessibilitySize ? 106 : 72) + lift * 18)
                    .zIndex(100)
                    .allowsHitTesting(false)
                // Keep controls above the lifted cards as well as the leather pocket.
                walletControls(width: width)
                    .frame(width: width, height: textSize.isAccessibilitySize ? 195 : 168)
                    .offset(y: (textSize.isAccessibilitySize ? 106 : 72) + lift * 18)
                    .zIndex(300)
            }.frame(width: geometry.size.width, height: height)
        }.frame(height: height)
            .task(id: revealed) { await animateReveal() }
            .onChange(of: accounts.map(\.id)) { _, _ in
                order = deck.map(\.id)
                if let current = deck.first { onSelect(current.id) }
                if deck.count < 2 { withAnimation(.spring(duration: 0.25)) { tilt = 0 } }
            }
            .onDisappear {
                swipeTask?.cancel(); switching = false; outgoingID = nil; placingAtBack = false
                dragX = 0; dragY = 0; dragAngle = 0; stackNudge = 0
            }
    }
    private func deckCard(_ card: Account, index: Int, width: CGFloat, height: CGFloat) -> some View {
        let depth = CGFloat(min(index, 3))
        let outgoing = outgoingID == card.id || (outgoingID == nil && index == 0)
        let z = placingAtBack && outgoingID == card.id ? Double(180 - deck.count) : Double(200 - index)
        return WalletCard(account: card,
                                 balanceVisible: (index == 0 || outgoingID == card.id) && balanceVisible)
            .frame(width: width * 0.88, height: height)
            .scaleEffect(1 + lift * 0.025 - depth * 0.025 * lift)
            .rotationEffect(.degrees((index == 0 ? tilt : Double(depth) * 3 * Double(lift)) + (outgoing ? dragAngle : 0)))
            .shadow(color: .black.opacity(0.4), radius: 8 + lift * 10, y: 8 + lift * 8)
            .offset(x: depth * 12 * lift + (outgoing ? dragX : 0) + stackNudge,
                    y: -lift * (textSize.isAccessibilitySize ? 92 : 72) + depth * 7 * lift + (outgoing ? dragY : 0))
            .zIndex(cardInFront ? z : Double(50 - index))
            .opacity(index < 4 || outgoingID == card.id ? 1 : 0)
            .contentShape(RoundedRectangle(cornerRadius: 17))
            .onTapGesture { if revealed && !switching { onOpen(card) } }
            .highPriorityGesture(DragGesture(minimumDistance: 12)
                .onChanged { value in
                    guard revealed, deck.count > 1, !switching else { return }
                    dragX = max(-width, min(20, value.translation.width))
                    dragY = value.translation.height * 0.14
                    dragAngle = Double(dragX / width) * 16
                }
                .onEnded { value in
                    guard revealed, deck.count > 1, !switching else { return }
                    if (value.translation.width < -55 || value.predictedEndTranslation.width < -120) && abs(value.translation.width) > abs(value.translation.height) {
                        nextCard(width: width, velocity: min(5, abs(value.predictedEndTranslation.width - value.translation.width) / width))
                    } else {
                        withAnimation(.spring(duration: 0.3, bounce: 0.1)) { dragX = 0; dragY = 0; dragAngle = 0 }
                    }
                })
            .allowsHitTesting(revealed && index == 0 && !switching)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.name + ", available balance " + Money.format(card.available))
            .accessibilityIdentifier(index == 0 ? "wallet-front-card" : "wallet-back-card-" + card.id.uuidString)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Open card details. Swipe left for the next card.")
            .accessibilityAction(named: "Next card") { nextCard(width: width) }
            .accessibilityHidden(index != 0 || !revealed)
    }
    private func pocket(width: CGFloat) -> some View {
        LeatherPocket()
            .fill(LinearGradient(colors: [Color(red: 0.49, green: 0.29, blue: 0.21), Color(red: 0.36, green: 0.18, blue: 0.12), Color(red: 0.29, green: 0.13, blue: 0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay { LeatherGrain().clipShape(LeatherPocket()) }
            .overlay { LeatherPocket().stroke(.black.opacity(0.4), lineWidth: 1) }
            .overlay { LeatherPocket().stroke(Color(red: 0.72, green: 0.48, blue: 0.33).opacity(0.6), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 4])).padding(7) }
    }
    private func walletControls(width: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("TOTAL BALANCE").font(.system(.caption2, design: .monospaced).weight(.semibold)).tracking(1.8)
                    Text(Money.format(total)).font(.system(.title2, design: .serif).weight(.semibold)).lineLimit(1).minimumScaleFactor(0.65)
                }.accessibilityElement(children: .combine).accessibilityIdentifier("wallet-total-balance")
                Spacer(minLength: 0)
                Button { revealed.toggle() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up").rotationEffect(.degrees(revealed ? 180 : 0))
                            .animation(.easeInOut(duration: 0.18), value: revealed)
                        ZStack {
                            Text("Reveal").opacity(revealed ? 0 : 1)
                            Text("Hide").opacity(revealed ? 1 : 0)
                        }.animation(.easeInOut(duration: 0.16), value: revealed)
                    }.font(.subheadline.weight(.semibold)).lineLimit(1)
                        .frame(width: 112, height: 44)
                        .background(.black.opacity(0.22), in: Capsule())
                        .overlay { Capsule().stroke(.white.opacity(0.2), lineWidth: 1) }
                }.buttonStyle(.plain).disabled(switching).accessibilityIdentifier("wallet-reveal")
                    .accessibilityLabel(revealed ? "Hide card" : "Reveal card")
            }
            HStack {
                Label("tender", systemImage: "seal").font(.system(.caption, design: .serif).weight(.semibold)).tracking(3).opacity(0.48)
                Spacer()
                Button { nextCard(width: width) } label: { Label("Next card", systemImage: "arrow.left").font(.caption.weight(.medium)).frame(minHeight: 44) }
                    .buttonStyle(.plain).opacity(revealed && deck.count > 1 ? 1 : 0)
                    .disabled(!revealed || deck.count < 2 || switching).accessibilityIdentifier("wallet-next-card")
                    .accessibilityHidden(!revealed || deck.count < 2)
            }.frame(height: 44)
        }.padding(.horizontal, 22).padding(.top, 25)
            .foregroundStyle(Color(red: 0.98, green: 0.91, blue: 0.81))
    }
    @MainActor private func nextCard(width: CGFloat, velocity: Double = 1) {
        guard revealed, deck.count > 1, !switching else { return }
        let current = deck.map(\.id)
        if reduceMotion {
            order = Array(current.dropFirst()) + [current[0]]
            if let first = order.first { onSelect(first) }
            return
        }
        switching = true; outgoingID = current[0]
        swipeTask?.cancel()
        swipeTask = Task { @MainActor in
            do {
                withAnimation(.interpolatingSpring(mass: 1, stiffness: 260, damping: 29, initialVelocity: velocity)) {
                    dragX = -width * 0.95; dragY = -14; dragAngle = -18
                }
                try await Task.sleep(for: .milliseconds(240))
                var transaction = Transaction(); transaction.disablesAnimations = true
                let rotated = Array(current.dropFirst()) + [current[0]]
                withAnimation(.interpolatingSpring(mass: 1, stiffness: 200, damping: 23, initialVelocity: 0.7)) {
                    placingAtBack = true; order = rotated
                    dragX = 0; dragY = 0; dragAngle = 0; stackNudge = -7
                }
                withTransaction(transaction) { onSelect(rotated[0]) }
                try await Task.sleep(for: .milliseconds(270))
                withAnimation(.spring(duration: 0.28, bounce: 0.2)) { stackNudge = 0 }
                try await Task.sleep(for: .milliseconds(250))
                outgoingID = nil; placingAtBack = false; switching = false
            } catch { switching = false }
        }
    }
    @MainActor private func animateReveal() async {
        if reduceMotion {
            lift = revealed ? 1 : 0; tilt = revealed && deck.count > 1 ? -7 : 0; cardInFront = revealed
            withAnimation(.easeOut(duration: 0.15)) { balanceVisible = revealed }
            return
        }
        if !revealed && lift == 0 { return }
        do {
            if revealed {
                withAnimation(.spring(duration: 0.42, bounce: 0.12)) { lift = 1 }
                try await Task.sleep(for: .milliseconds(180))
                cardInFront = true
                withAnimation(.easeOut(duration: 0.18)) { balanceVisible = true }
                withAnimation(.spring(duration: 0.36, bounce: 0.18)) { tilt = deck.count > 1 ? -7 : 0 }
            } else {
                withAnimation(.easeOut(duration: 0.15)) { balanceVisible = false; tilt = 0 }
                cardInFront = false
                withAnimation(.spring(duration: 0.44, bounce: 0.08)) { lift = 0 }
            }
        } catch { }
    }
}


struct WalletRollingBalance: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var fontSize: CGFloat = 29
    let amount: Int64
    let roll: Bool
    var centered = false
    var banknoteStyle = false
    @State private var progress: CGFloat = 1
    private struct RollKey: Equatable { var amount: Int64; var roll: Bool }
    var body: some View {
        let characters = Array(Money.format(amount))
        GeometryReader { geometry in
            let size = min(fontSize, geometry.size.width / (CGFloat(characters.count) * 0.66))
            let line = size * 1.25
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(characters.enumerated()), id: \.offset) { _, character in
                    if let digit = character.wholeNumberValue, !reduceMotion {
                        let travel = 10 + digit
                        VStack(spacing: 0) {
                            ForEach(0...travel, id: \.self) { index in
                                glyph(String((travel - index) % 10)).frame(width: size * 0.64, height: line)
                            }
                        }.offset(y: -CGFloat(travel) * line * (1 - progress))
                            .frame(width: size * 0.64, height: line, alignment: .top).clipped()
                    } else {
                        glyph(String(character)).frame(width: size * (character.isNumber || character == "$" ? 0.64 : 0.47), height: line)
                    }
                }
            }.font(.system(size: size, weight: banknoteStyle ? .heavy : .medium, design: banknoteStyle ? .rounded : .serif).monospacedDigit())
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        }.frame(height: fontSize * 1.25)
            .accessibilityElement(children: .ignore).accessibilityLabel(Money.format(amount))
            .task(id: RollKey(amount: amount, roll: roll)) {
                guard roll else { return }
                var transaction = Transaction(); transaction.disablesAnimations = true
                // The shared cooldown follows the wallet, rather than restarting for each card.
                guard !reduceMotion, store.claimWalletBalanceRoll() else {
                    withTransaction(transaction) { progress = 1 }
                    return
                }
                withTransaction(transaction) { progress = 0 }
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(.timingCurve(0.16, 0.72, 0.2, 1, duration: 0.72)) { progress = 1 }
            }
    }
    private func glyph(_ value: String) -> some View {
        Text(value).lineLimit(1).fixedSize(horizontal: true, vertical: false).overlay {
            if banknoteStyle {
                Canvas { context, bounds in
                    for y in stride(from: 1.0, to: bounds.height, by: 2.6) {
                        var line = Path()
                        line.move(to: CGPoint(x: 0, y: y))
                        line.addLine(to: CGPoint(x: bounds.width, y: y))
                        context.stroke(line, with: .color(Color(red: 0.93, green: 0.96, blue: 0.84)), lineWidth: 0.45)
                    }
                }.mask { Text(value) }
            }
        }
    }
}

private struct WalletCard: View {
    let account: Account
    let balanceVisible: Bool
    private var artwork: CardArtwork? { CardArtworkLibrary.catalog.artwork(for: account) }
    var body: some View {
        ZStack {
            if account.isCash == true {
                CashWalletCard(account: account, balanceVisible: balanceVisible)
            } else if let artwork {
                GeometryReader { geometry in
                    Image(artwork.assetName).resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .background(.black)
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(account.bankAccountKey == nil ? "RECORDED AVAILABLE" : "BANK AVAILABLE")
                                    Spacer(minLength: 4)
                                    if let mask = account.bankDetails?.mask { Text("•••• " + mask) }
                                }.font(.system(.caption2, design: .monospaced))
                                WalletRollingBalance(amount: account.available, roll: balanceVisible)
                            }.padding(10).foregroundStyle(.white)
                                .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 10))
                                .padding(10).opacity(balanceVisible ? 1 : 0)
                        }
                }.clipShape(RoundedRectangle(cornerRadius: 17))
            } else {
            cardSurface {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        Text(account.bankDetails?.institutionName ?? account.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                        Spacer(minLength: 6)
                        Image(systemName: "wave.3.right").font(.caption)
                    }
                    Spacer(minLength: 2)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(account.bankAccountKey == nil ? "RECORDED AVAILABLE" : "BANK AVAILABLE").font(.system(.caption2, design: .monospaced)).tracking(1.3)
                        WalletRollingBalance(amount: account.available, roll: balanceVisible)
                    }.opacity(balanceVisible ? 1 : 0)
                    HStack {
                        Text("PRIMARY").font(.system(.caption2, design: .monospaced)).tracking(2)
                        Spacer()
                        if let mask = account.bankDetails?.mask { Text("•••• " + mask).font(.system(.caption, design: .monospaced)) }
                    }
                }.padding(20)
            }
            }
        }
    }
    private func cardSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.13, green: 0.22, blue: 0.19), Color(red: 0.035, green: 0.065, blue: 0.055)], startPoint: .topLeading, endPoint: .bottomTrailing)
            WalletEtching()
            LinearGradient(colors: [.white.opacity(0.12), .clear, .white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing)
            content()
        }.foregroundStyle(Color(red: 0.95, green: 0.93, blue: 0.85))
            .clipShape(RoundedRectangle(cornerRadius: 17))
            .overlay { RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.2), lineWidth: 1) }
    }
}

private struct LeatherPocket: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        return Path { path in
            path.move(to: CGPoint(x: 0, y: 18))
            path.addQuadCurve(to: CGPoint(x: 20, y: 1), control: .zero)
            path.addLine(to: CGPoint(x: w * 0.22, y: 1))
            path.addCurve(to: CGPoint(x: w * 0.5, y: 22), control1: CGPoint(x: w * 0.33, y: 1), control2: CGPoint(x: w * 0.39, y: 22))
            path.addCurve(to: CGPoint(x: w * 0.78, y: 1), control1: CGPoint(x: w * 0.61, y: 22), control2: CGPoint(x: w * 0.67, y: 1))
            path.addLine(to: CGPoint(x: w - 20, y: 1))
            path.addQuadCurve(to: CGPoint(x: w, y: 18), control: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w, y: h - 23))
            path.addQuadCurve(to: CGPoint(x: w - 23, y: h), control: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: 23, y: h))
            path.addQuadCurve(to: CGPoint(x: 0, y: h - 23), control: CGPoint(x: 0, y: h))
            path.closeSubpath()
        }
    }
}

private struct WalletEtching: View {
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            for i in 0..<50 {
                var path = Path()
                let offset = CGFloat(i) * 5
                path.move(to: CGPoint(x: size.width * 0.5 + offset, y: -10))
                path.addCurve(to: CGPoint(x: size.width * 0.3 + offset, y: size.height + 10), control1: CGPoint(x: -offset, y: size.height * 0.55), control2: CGPoint(x: size.width + offset, y: size.height * 0.45))
                context.stroke(path, with: .color(.white.opacity(0.045)), lineWidth: 0.5)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct LeatherGrain: View {
    var body: some View {
        Canvas { context, size in
            for i in 0..<1100 {
                let x = CGFloat((i * 73 + 19) % 997) / 997 * size.width
                let y = CGFloat((i * 137 + 41) % 991) / 991 * size.height
                let dot = CGRect(x: x, y: y, width: i.isMultiple(of: 3) ? 1.5 : 0.7, height: 0.7)
                context.fill(Path(ellipseIn: dot), with: .color(i.isMultiple(of: 2) ? .white.opacity(0.065) : .black.opacity(0.12)))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
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
