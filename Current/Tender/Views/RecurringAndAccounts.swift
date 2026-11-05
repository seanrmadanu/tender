import SwiftUI

struct RecurringList: View {
    @Environment(LedgerStore.self) private var store
    @State private var edit: RecurringBill?
    @State private var suggestion: SubscriptionSuggestion?
    private var suggestions: [SubscriptionSuggestion] { store.ledger.subscriptionSuggestions }
    var body: some View {
        SectionHeading(title: "Know what’s coming.", subtitle: "Subscriptions, bills, and the little renewals.")
        PaperCard { AmountRow(label: "Monthly equivalent", amount: store.ledger.activeRecurring.reduce(0) { $0 + $1.monthlyEquivalent }); AmountRow(label: "Reserved for next 30 days", amount: store.ledger.upcomingReserve()) }
        NavigationLink { EmailSubscriptionsView() } label: {
            Label("Trials & subscription emails", systemImage: "envelope")
        }
        PaperCard {
            HStack {
                Text("Find recurring payments").font(.headline)
                Spacer()
                Button { Task { await store.refreshBank(force: true) } } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                    .disabled(store.bankUpdating).accessibilityLabel("Refresh bank history")
            }
            if store.bankUpdating { ProgressView("Checking bank history…") }
            if let message = store.bankMessage { Text(message).font(.caption).foregroundStyle(Ink.warning) }
            if (store.ledger.bankActivity ?? []).flatMap(\.transactions).isEmpty {
                Text("No bank transactions are available yet. Balances alone cannot reveal subscriptions. You can add a payment manually or use recorded expenses.").font(.subheadline)
            }
            Text("Suggestions need at least two similarly priced weekly, monthly or yearly charges from the same merchant and account. Review each suggestion before adding it.").font(.caption).foregroundStyle(Ink.muted)
            if suggestions.isEmpty { Text("No repeated-payment matches yet.").font(.caption) }
            NavigationLink("Review bank purchases") { BankActivityView() }
            if !(store.ledger.ignoredSubscriptionIDs ?? []).isEmpty {
                Button("Review ignored suggestions again") { _ = store.update { $0.ignoredSubscriptionIDs = [] } }
            }
        }
        if !suggestions.isEmpty {
            SectionHeading(title: "Possible subscriptions", subtitle: "Bank and recorded purchases · review before adding")
            ForEach(suggestions) { candidate in
                Button { suggestion = candidate } label: {
                    HStack { VStack(alignment: .leading) { Text(candidate.merchant); Text("\(candidate.occurrences) similar charges · \(candidate.cycle.rawValue)\(candidate.occurrences == 2 ? " · Early hint" : "")").font(.caption) }; Spacer(); Text(Money.format(candidate.amount)) }
                }.frame(minHeight: 48)
                Button("Ignore suggestion", role: .destructive) {
                    _ = store.update { ledger in
                        if ledger.ignoredSubscriptionIDs == nil { ledger.ignoredSubscriptionIDs = [] }
                        ledger.ignoredSubscriptionIDs?.append(candidate.id)
                    }
                }.font(.caption)
            }
            Text("Two charges are an early hint, not a confirmed subscription. Regular purchases can look recurring; confirm the merchant and schedule before saving.").font(.footnote)
        }
        if store.ledger.recurring.isEmpty { EmptyNote(symbol: "repeat", title: "No surprises.", message: "Add a recurring payment to see upcoming costs and request a reminder.") }
        ForEach(store.ledger.recurring.sorted { $0.nextDue < $1.nextDue }) { bill in
            Button { edit = bill } label: {
                PaperCard {
                    HStack { CategoryIcon(symbol: "repeat"); VStack(alignment: .leading, spacing: 4) { HStack { Text(bill.name).font(.headline); AssistantBadge(origin: bill.assistantOrigin, edited: bill.assistantLastEdit) }; Text("\(bill.cycle.rawValue) · \(bill.nextDue.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Ink.muted) }; Spacer(); Text(bill.renewalAmountUnknown == true ? "Price unknown" : Money.format(bill.amount)).font(.headline) }
                    Text(bill.cancelledAt != nil ? "Cancelled · history retained" : bill.trialEndsAt != nil ? "Trial · renewal estimate" : (bill.source ?? "Manually tracked")).font(.caption).foregroundStyle(Ink.muted)
                    if let mailbox = bill.sourceMailbox { Text(mailbox).font(.caption).foregroundStyle(Ink.muted) }
                    if let charge = store.ledger.possibleChargeAfterCancellation(bill) {
                        Label("Possible charge after cancellation: " + Money.format(charge.amountCents) + " on " + charge.date + ". Review in bank purchases.", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Ink.warning)
                    }
                    if bill.cancelledAt == nil {
                        Label(bill.remind ? (bill.trialEndsAt != nil ? "Reminder requested · three days before" : "Reminder requested · one day before") : "Reminders off", systemImage: bill.remind ? "bell" : "bell.slash").font(.caption).foregroundStyle(Ink.muted)
                    }
                }
            }.buttonStyle(.plain)
        }
        Text("Active entries reserve estimated cash for planning. Cancelled entries and unknown trial prices are excluded. Bank estimates cannot confirm whether you cancelled with the provider. It becomes an expense only when you choose Mark Paid. Reminders cover the next due date and refresh when you edit or mark a payment paid.").font(.footnote).foregroundStyle(Ink.muted)
            .sheet(item: $edit) { bill in NavigationStack { RecurringForm(existing: bill) } }
            .sheet(item: $suggestion) { candidate in NavigationStack { RecurringForm(suggestion: candidate) } }
    }
}
struct RecurringForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var existing: RecurringBill? = nil
    var suggestion: SubscriptionSuggestion? = nil
    @State private var name = ""
    @State private var amount = ""
    @State private var category: UUID?
    @State private var due = Date()
    @State private var cycle = BillingCycle.monthly
    @State private var remind = false
    @State private var account: UUID?
    @State private var delete = false
    @State private var cancelled = false
    @State private var initialized = false
    @State private var saving = false
    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && ((Money.cents(amount) ?? 0) > 0 || (existing?.renewalAmountUnknown == true && amount.isEmpty)) && !saving }
    var body: some View {
        Form {
            Section("Payment") { TenderField("Name", text: $name); TenderField("Amount (USD)", text: $amount, numeric: true); Picker("Category", selection: $category) { Text("Uncategorized").tag(UUID?.none); ForEach(store.ledger.categories) { Text($0.name).tag(Optional($0.id)) } }; Picker("Repeats", selection: $cycle) { ForEach(BillingCycle.allCases, id: \.self) { Text($0.rawValue).tag($0) } }; DatePicker("Next due", selection: $due, displayedComponents: .date) }
            Section { Toggle(existing?.trialEndsAt != nil ? "Remind me three days before at 9 AM" : "Remind me one day before at 9 AM", isOn: $remind).disabled(cancelled) } footer: { Text("Tender asks for notification access when you save a reminder. Due dates within one day may be too close for a reminder.") }
            if existing != nil {
                Section {
                    Toggle("Cancelled with provider", isOn: $cancelled)
                    Text("This stops Tender reminders and forecasts after saving. It does not cancel the service. Turn off to resume tracking.").font(.caption)
                }
                Section("Record payment") {
                    Picker("Paid from", selection: $account) { Text("Choose").tag(UUID?.none); ForEach(store.ledger.activeAccounts) { Text($0.name).tag(Optional($0.id)) } }
                    Button("Mark Paid & Advance Due Date") { Task { await save(paid: true) } }.disabled(!valid || account == nil || cancelled || (Money.cents(amount) ?? 0) <= 0)
                    Text("If this payment is already in Activity, do not record it again. Move Next due forward and Save instead. Bank-linked payments do not deduct the saved balance again.").font(.caption)
                }
                Section { Button("Delete Recurring Payment", role: .destructive) { delete = true } }
            }
        }.paperForm().navigationTitle(existing == nil ? "New Recurring Payment" : "Recurring Payment").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save(paid: false) } }.disabled(!valid) } }
            .onAppear { guard !initialized else { return }; initialized = true; account = store.ledger.activeAccounts.first?.id; category = store.ledger.categories.last?.id; if let candidate = suggestion { name = candidate.merchant; amount = Money.input(candidate.amount); due = candidate.nextDue; cycle = candidate.cycle }; if let e = existing { name = e.name; amount = e.renewalAmountUnknown == true ? "" : Money.input(e.amount); category = e.categoryID; due = e.nextDue; cycle = e.cycle; remind = e.remind; cancelled = e.cancelledAt != nil } }
            .confirmationDialog("Delete this recurring payment?", isPresented: $delete, titleVisibility: .visible) { Button("Delete", role: .destructive) { if store.update({ if let id = existing?.id { $0.archiveRecurring(id) } }) { Task { await store.refreshReminders() }; dismiss() } } }
    }
    private func save(paid: Bool) async {
        guard valid else { return }
        let cents = Money.cents(amount) ?? 0
        saving = true; defer { saving = false }
        let fallbackID = store.ledger.categories.first(where: { $0.name == "Uncategorized" })?.id ?? UUID()
        let category = category ?? fallbackID
        var bill = existing ?? RecurringBill(name: name, amount: cents, categoryID: category, nextDue: due, cycle: cycle, remind: remind)
        bill.name = name; bill.amount = cents; bill.categoryID = category; bill.nextDue = due; bill.cycle = cycle
        bill.remind = remind && !cancelled; bill.renewalAmountUnknown = cents == 0
        bill.cancelledAt = cancelled ? (existing?.cancelledAt ?? Date()) : nil
        if let suggestion { bill.source = "Estimated from purchase history"; bill.bankSuggestionID = suggestion.id }
        if bill.trialEndsAt != nil { bill.trialEndsAt = due }
        if let existing {
            bill.id = existing.id
            let sameSchedule = existing.cycle == cycle && Calendar.current.isDate(existing.nextDue, inSameDayAs: due)
            bill.recurrenceAnchor = sameSchedule ? (existing.recurrenceAnchor ?? existing.nextDue) : due
        } else { bill.recurrenceAnchor = due }
        if bill.remind { guard await store.enableReminders() else { return } }
        if paid { bill.nextDue = bill.advanced(); bill.trialEndsAt = nil }
        let result = store.update { ledger in
            if !ledger.categories.contains(where: { $0.id == category }) {
                ledger.categories.append(BudgetCategory(id: category, name: "Uncategorized", symbol: "tag", limit: 0))
            }
            if paid, let account { try ledger.record(Expense(merchant: name, amount: cents, categoryID: category, accountID: account, note: "Recurring payment"), deductFromBalance: ledger.accounts.first(where: { $0.id == account })?.bankAccountKey == nil) }
            if let i = ledger.recurring.firstIndex(where: { $0.id == bill.id }) { ledger.recurring[i] = bill } else { ledger.recurring.append(bill) }
        }
        if result { await store.refreshReminders(); dismiss() }
    }
}
struct AccountForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private enum AddFlow: String, Identifiable {
        case explanation, manual
        var id: String { rawValue }
    }
    @State private var addFlow: AddFlow?
    @State private var showPlaid = false
    @State private var cashAmount = ""
    @State private var cashSaved = false
    @State private var pendingPlaid = false
    private var cashWallet: Account? { store.ledger.activeAccounts.first { $0.isCash == true } }
    var body: some View {
        Form {
            Section("Add an account") {
                Button { showPlaid = true } label: {
                    Label("Import Bank Account via Plaid", systemImage: "building.columns")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.accessibilityIdentifier("import-bank-plaid")
                Button { addFlow = .explanation } label: {
                    Label("Add Offline Account", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.accessibilityIdentifier("add-info-manually")
            }
            Section {
                HStack {
                    Text("USD").font(.subheadline).foregroundStyle(.secondary)
                    TenderField("Cash on hand", text: $cashAmount, numeric: true)
                        .accessibilityLabel("Cash on hand (USD)").accessibilityIdentifier("cash-on-hand")
                }
                Button(cashWallet == nil ? "Add Cash" : "Update Cash") { saveCash() }
                    .disabled(Money.cents(cashAmount) == nil)
                    .accessibilityIdentifier("save-cash")
                if cashSaved { Label("Cash saved", systemImage: "checkmark.circle").font(.footnote) }
            } header: { Text("Cash") } footer: {
                Text("Track the cash you have on hand. Keep this amount and cash purchases up to date manually.")
            }
            Section { BankSyncStatusView() }
            if let notice = store.bankImportNotice { Section { Label(notice, systemImage: "checkmark.circle") } }
            Section("Your accounts (\(store.ledger.activeAccounts.count))") {
                if !store.ledger.activeAccounts.isEmpty { LabeledContent("Total available", value: Money.format(store.ledger.available)) }
                if store.ledger.activeAccounts.isEmpty { Text("Add an account to start tracking purchases.").foregroundStyle(.secondary) }
                ForEach(store.ledger.activeAccounts) { account in
                    NavigationLink { AccountDetailView(accountID: account.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(account.name); Spacer(); Text(Money.format(account.available)).monospacedDigit() }
                            Label(account.bankAccountKey == nil ? "Offline account" : "Connected through Plaid", systemImage: account.bankAccountKey == nil ? "pencil" : "link").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("account-\(account.name)")
                }
            }
            if store.ledger.accounts.contains(where: { $0.isArchived == true }) {
                Section("Removed cards · history retained") {
                    ForEach(store.ledger.accounts.filter { $0.isArchived == true }) { account in
                        HStack {
                            NavigationLink(account.name) { AccountDetailView(accountID: account.id) }
                            Button("Restore") { _ = store.update { try $0.restoreCardAndHistory(account.id) } }.buttonStyle(.borderless)
                        }
                    }
                    Text("Restored cards use their saved ledger balance. Review the balance before recording purchases.").font(.caption)
                }
            }
        }.scrollIndicators(.hidden).paperForm().navigationTitle("Accounts").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showPlaid) { NavigationStack { BankConnectionView() } }
            .sheet(item: $addFlow, onDismiss: {
                if pendingPlaid { pendingPlaid = false; showPlaid = true }
            }) { flow in
                NavigationStack {
                    if flow == .manual { ManualAccountForm() }
                    else {
                        ManualAccountExplanation(
                            goBack: { addFlow = nil },
                            continueManually: { addFlow = .manual },
                            connectPlaid: { pendingPlaid = true; addFlow = nil }
                        )
                    }
                }.presentationDetents(flow == .explanation ? [.medium, .large] : [.large])
                    .presentationDragIndicator(.hidden)
            }
            .onAppear { cashAmount = cashWallet.map { Money.input($0.available) } ?? "" }
            .onChange(of: cashAmount) { _, _ in cashSaved = false }
    }
    private func saveCash() {
        guard let cents = Money.cents(cashAmount) else { return }
        cashSaved = store.update { ledger in
            if let cashWallet { ledger.setBalance(accountID: cashWallet.id, available: cents) }
            else { ledger.accounts.append(Account(name: "Cash", available: cents, isCash: true)) }
        }
        if cashSaved { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
    }
}

private struct ManualAccountExplanation: View {
    let goBack: () -> Void
    let continueManually: () -> Void
    let connectPlaid: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("An offline account is a local record for tracking money yourself. It does not connect to a bank or sync balances or transactions, even if you enter a real bank name or balance. You’re responsible for updating purchases and balances. For automatic updates, choose Import Bank Account via Plaid.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Continue", action: continueManually).buttonStyle(PrimaryButton())
                    .accessibilityIdentifier("continue-manual-account")
                Button(action: connectPlaid) {
                    Text("Add Account via Plaid").frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.bordered)
                    .accessibilityIdentifier("explanation-connect-plaid")
                Button(action: goBack) { Text("Go Back").frame(maxWidth: .infinity, minHeight: 44) }
            }.padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
        }.paperForm().navigationTitle("Add Offline Account").navigationBarTitleDisplayMode(.inline)
    }
}

struct ManualAccountForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var existing: Account? = nil
    @State private var name = ""
    @State private var amount = ""
    @State private var cash = false
    var body: some View {
        Form {
            Section {
                TenderField("Account name", text: $name)
                if existing?.bankAccountKey == nil { Toggle("Cash wallet", isOn: $cash) }
                TenderField("Available balance (USD)", text: $amount, numeric: true)
            } header: { Text(existing == nil ? "Your account" : "Update recorded balance") } footer: { Text("A nickname and balance are enough. No banking details are collected. Enter 0 if you want to start tracking purchases without an opening balance.") }
            Section { Text("New purchases deduct from this balance. Updating the balance replaces the current amount and keeps your purchase history. For an older purchase already included in the balance, turn off Deduct from current balance.").font(.footnote).foregroundStyle(.secondary) }
        }.paperForm().navigationTitle(existing == nil ? "Offline Account" : "Update Balance").navigationBarTitleDisplayMode(.inline)
            .bottomAdd(existing == nil ? "Add Account" : "Save", identifier: "save-manual-account") { save() }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { if let existing { name = existing.name; amount = Money.input(max(0, existing.available)); cash = existing.isCash == true } }
    }
    private func save() {
        guard let cents = Money.cents(amount), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { store.error = "Enter an account name and a valid balance."; return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.update({ ledger in
            if let existing, let i = ledger.accounts.firstIndex(where: { $0.id == existing.id }) {
                ledger.accounts[i].name = trimmedName
                if existing.bankAccountKey == nil { ledger.accounts[i].isCash = cash }
                ledger.setBalance(accountID: existing.id, available: cents)
                ledger.accounts[i].source = "Manual"
            } else { ledger.accounts.append(Account(name: trimmedName, available: cents, isCash: cash)) }
        }) { dismiss() }
    }
}

struct AccountDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var deletingCard = false
    @Environment(LedgerStore.self) private var store
    let accountID: UUID
    @State private var addPurchase = false
    @State private var selectedExpense: Expense?
    private var account: Account? { store.ledger.accounts.first { $0.id == accountID } }
    private var purchases: [Expense] { store.ledger.expenses.filter { $0.accountID == accountID }.sorted { $0.date > $1.date } }
    var body: some View {
        Form {
            if let account {
                Section {
                    LabeledContent("Available balance", value: Money.format(account.available))
                    Text(account.bankAccountKey == nil ? "Manual account · no bank connection" : "Connected through Plaid · updates automatically").font(.caption).foregroundStyle(.secondary)
                    Text("Updated \(account.updated.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
                if account.isArchived != true && account.bankAccountKey == nil { Section {
                    NavigationLink("Update Balance") { ManualAccountForm(existing: account) }
                } }
                if account.isArchived != true && account.isCash != true {
                    Section {
                        NavigationLink { CardArtworkPicker(accountID: account.id) } label: {
                            LabeledContent("Card design", value: account.usesStandardCardDisplay == true ? "Standard display" :
                                (CardArtworkLibrary.catalog.artwork(for: account)?.productName ?? "Automatic"))
                        }.accessibilityIdentifier("choose-card-design")
                    }
                }
                if account.bankAccountKey != nil {
                    Section {
                        BankSyncStatusView()
                        if let details = account.bankDetails {
                            if let bank = details.institutionName { LabeledContent("Bank", value: bank) }
                            if let mask = details.mask { LabeledContent("Ending in", value: mask) }
                            if let balance = details.currentBalance { LabeledContent("Current balance", value: Money.format(balance)) }
                        }
                        Text("Balances and bank activity update automatically. Your bank may take time to post new purchases.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Purchases (\(purchases.count))") {
                    if purchases.isEmpty { Text("Your purchases for this account will appear here.").foregroundStyle(.secondary) }
                    ForEach(purchases) { expense in
                        Button { selectedExpense = expense } label: { ExpenseListRow(expense: expense) }.buttonStyle(.plain)
                    }
                }
                if account.isArchived != true {
                    Section {
                        Button("Delete Card", systemImage: "trash", role: .destructive) { deletingCard = true }
                            .accessibilityIdentifier("delete-card")
                    } footer: { Text("Move this card and its related transactions, expenses, receipts and notes to Settings → Archive.") }
                }

            }
        }.paperForm().navigationTitle(account?.name ?? "Account").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete this card and archive its information?", isPresented: $deletingCard, titleVisibility: .visible) {
                Button("Delete Card", role: .destructive) {
                    if store.update({ $0.archiveCardAndHistory(accountID) }) { Task { await store.refreshReminders() }; dismiss() }
                }.accessibilityIdentifier("confirm-delete-card")
                Button("Cancel", role: .cancel) {}
            } message: { Text("You can restore the card and its history together from Settings → Archive.") }
            .bottomAdd("Add Purchase", enabled: account != nil && account?.isArchived != true) { addPurchase = true }
            .sheet(isPresented: $addPurchase) { NavigationStack { ExpenseForm(initialAccount: accountID) } }
            .sheet(item: $selectedExpense) { expense in NavigationStack { ExpenseDetail(expense: expense) } }
    }
}

struct SubscriptionsView: View {
    @State private var adding = false
    var body: some View {
        PaperScreen { RecurringList() }.navigationTitle("Subscriptions")
            .bottomAdd("Add subscription") { adding = true }
            .sheet(isPresented: $adding) { NavigationStack { RecurringForm() } }
    }
}

struct PossibleSubscriptionsView: View {
    @Environment(LedgerStore.self) private var store
    var accountID: UUID?
    private var account: Account? { store.ledger.accounts.first { $0.id == accountID } }
    var body: some View {
        List {
            Section {
                if let account { Label(account.name, systemImage: "creditcard") }
                Text("Repeated charges can suggest a subscription. Review these estimates before treating them as confirmed payments.").font(.footnote)
            }
            let suggestions = store.ledger.possibleSubscriptions(for: account)
            if suggestions.isEmpty { Text("No possible subscriptions found yet.") }
            ForEach(suggestions) { suggestion in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(suggestion.merchant)
                        Text("\(suggestion.cycle.rawValue) · \(suggestion.occurrences) similar charges").font(.caption).foregroundStyle(Ink.muted)
                    }
                    Spacer(); Text(Money.format(suggestion.amount))
                }
            }
        }.paperForm().navigationTitle("Possible subscriptions")
    }
}
