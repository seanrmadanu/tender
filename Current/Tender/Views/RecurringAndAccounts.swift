import SwiftUI

struct RecurringList: View {
    @Environment(LedgerStore.self) private var store
    @State private var edit: RecurringBill?
    @State private var suggestion: SubscriptionSuggestion?
    private var suggestions: [SubscriptionSuggestion] { store.ledger.subscriptionSuggestions }
    var body: some View {
        SectionHeading(title: "Know what’s coming.", subtitle: "Subscriptions, bills, and the little renewals.")
        PaperCard { AmountRow(label: "Monthly equivalent", amount: store.ledger.recurring.reduce(0) { $0 + $1.monthlyEquivalent }); AmountRow(label: "Reserved for next 30 days", amount: store.ledger.upcomingReserve()) }
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
        }
        if !suggestions.isEmpty {
            SectionHeading(title: "Possible subscriptions", subtitle: "Bank and recorded purchases · review before adding")
            ForEach(suggestions) { candidate in
                Button { suggestion = candidate } label: {
                    HStack { VStack(alignment: .leading) { Text(candidate.merchant); Text("\(candidate.occurrences) similar charges · \(candidate.cycle.rawValue)\(candidate.occurrences == 2 ? " · Early hint" : "")").font(.caption) }; Spacer(); Text(Money.format(candidate.amount)) }
                }.frame(minHeight: 48)
            }
            Text("Two charges are an early hint, not a confirmed subscription. Regular purchases can look recurring; confirm the merchant and schedule before saving.").font(.footnote)
        }
        if store.ledger.recurring.isEmpty { EmptyNote(symbol: "repeat", title: "No surprises.", message: "Add a recurring payment to see upcoming costs and request a reminder.") }
        ForEach(store.ledger.recurring.sorted { $0.nextDue < $1.nextDue }) { bill in
            Button { edit = bill } label: {
                PaperCard {
                    HStack { CategoryIcon(symbol: "repeat"); VStack(alignment: .leading, spacing: 4) { Text(bill.name).font(.headline); Text("\(bill.cycle.rawValue) · \(bill.nextDue.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(Ink.muted) }; Spacer(); Text(Money.format(bill.amount)).font(.headline) }
                    Label(bill.remind ? "Reminder requested · one day before" : "Reminders off", systemImage: bill.remind ? "bell" : "bell.slash").font(.caption).foregroundStyle(Ink.muted)
                }
            }.buttonStyle(.plain)
        }
        Text("A recurring entry reserves cash for planning. It becomes an expense only when you choose Mark Paid. Reminders cover the next due date and refresh when you edit or mark a payment paid.").font(.footnote).foregroundStyle(Ink.muted)
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
    @State private var initialized = false
    @State private var saving = false
    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && (Money.cents(amount) ?? 0) > 0 && !saving }
    var body: some View {
        Form {
            Section("Payment") { TenderField("Name", text: $name); TenderField("Amount (USD)", text: $amount).keyboardType(.decimalPad); Picker("Category", selection: $category) { Text("Uncategorized").tag(UUID?.none); ForEach(store.ledger.categories) { Text($0.name).tag(Optional($0.id)) } }; Picker("Repeats", selection: $cycle) { ForEach(BillingCycle.allCases, id: \.self) { Text($0.rawValue).tag($0) } }; DatePicker("Next due", selection: $due, displayedComponents: .date) }
            Section { Toggle("Remind me one day before at 9 AM", isOn: $remind) } footer: { Text("Tender asks for notification access when you save a reminder. Due dates within one day may be too close for a reminder.") }
            if existing != nil {
                Section("Record payment") {
                    Picker("Paid from", selection: $account) { Text("Choose").tag(UUID?.none); ForEach(store.ledger.activeAccounts) { Text($0.name).tag(Optional($0.id)) } }
                    Button("Mark Paid & Advance Due Date") { Task { await save(paid: true) } }.disabled(!valid || account == nil)
                    Text("If this payment is already in Activity, do not record it again. Move Next due forward and Save instead. Bank-linked payments do not deduct the saved balance again.").font(.caption)
                }
                Section { Button("Delete Recurring Payment", role: .destructive) { delete = true } }
            }
        }.paperForm().navigationTitle(existing == nil ? "New Recurring Payment" : "Recurring Payment").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save(paid: false) } }.disabled(!valid) } }
            .onAppear { guard !initialized else { return }; initialized = true; account = store.ledger.activeAccounts.first?.id; category = store.ledger.categories.last?.id; if let candidate = suggestion { name = candidate.merchant; amount = Money.input(candidate.amount); due = candidate.nextDue; cycle = candidate.cycle }; if let e = existing { name = e.name; amount = Money.input(e.amount); category = e.categoryID; due = e.nextDue; cycle = e.cycle; remind = e.remind } }
            .confirmationDialog("Delete this recurring payment?", isPresented: $delete, titleVisibility: .visible) { Button("Delete", role: .destructive) { if store.update({ $0.recurring.removeAll { $0.id == existing?.id } }) { Task { await store.refreshReminders() }; dismiss() } } }
    }
    private func save(paid: Bool) async {
        guard valid, let cents = Money.cents(amount) else { return }
        saving = true; defer { saving = false }
        let fallbackID = store.ledger.categories.first(where: { $0.name == "Uncategorized" })?.id ?? UUID()
        let category = category ?? fallbackID
        var bill = RecurringBill(name: name, amount: cents, categoryID: category, nextDue: due, cycle: cycle, remind: remind)
        if let existing {
            bill.id = existing.id
            let sameSchedule = existing.cycle == cycle && Calendar.current.isDate(existing.nextDue, inSameDayAs: due)
            bill.recurrenceAnchor = sameSchedule ? (existing.recurrenceAnchor ?? existing.nextDue) : due
        } else { bill.recurrenceAnchor = due }
        if remind { guard await store.enableReminders() else { return } }
        if paid { bill.nextDue = bill.advanced() }
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
    @State private var adding = false
    var body: some View {
        Form {
            Section {
                Text("Add a manual account or cash wallet below. Connect a bank only when you want bank information.")
            } header: { Text("No bank connection needed") } footer: {
                Text("Use any nickname, like Chase, Capital One, or Cash. No account number, bank login, or Plaid account is required. Manual records stay on this device unless you export or back them up.")
            }
            Section("Your accounts (\(store.ledger.activeAccounts.count))") {
                if !store.ledger.activeAccounts.isEmpty { LabeledContent("Total available", value: Money.format(store.ledger.available)) }
                if store.ledger.activeAccounts.isEmpty { Text("Add an account to start tracking purchases.").foregroundStyle(.secondary) }
                ForEach(store.ledger.activeAccounts) { account in
                    NavigationLink { AccountDetailView(accountID: account.id) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack { Text(account.name); Spacer(); Text(Money.format(account.available)).monospacedDigit() }
                            Label(account.bankAccountKey == nil ? "Manual account" : "Connected through Plaid", systemImage: account.bankAccountKey == nil ? "pencil" : "link").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }.accessibilityIdentifier("account-\(account.name)")
                }
            }
            if store.ledger.accounts.contains(where: { $0.isArchived == true }) {
                Section("Removed cards · history retained") {
                    ForEach(store.ledger.accounts.filter { $0.isArchived == true }) { account in
                        HStack {
                            NavigationLink(account.name) { AccountDetailView(accountID: account.id) }
                            Button("Restore") { _ = store.update { ledger in
                                if let i = ledger.accounts.firstIndex(where: { $0.id == account.id }) { ledger.accounts[i].isArchived = false }
                            } }.buttonStyle(.borderless)
                        }
                    }
                    Text("Restored cards use their saved ledger balance. Review the balance before recording purchases.").font(.caption)
                }
            }
            Section {
                NavigationLink { BankConnectionView() } label: { Label("Connect with Plaid", systemImage: "building.columns") }
            } header: { Text("Optional bank connection") } footer: { Text("Retrieve balances for supported checking and savings accounts. You can keep using every manual feature without connecting.") }
        }.paperForm().navigationTitle("Accounts").navigationBarTitleDisplayMode(.inline).bottomAdd("Add Account") { adding = true }
            .sheet(isPresented: $adding) { NavigationStack { ManualAccountForm() } }
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
                TenderField("Available balance (USD)", text: $amount).keyboardType(.decimalPad)
            } header: { Text(existing == nil ? "Your account" : "Update recorded balance") } footer: { Text("A nickname and balance are enough. No banking details are collected. Enter 0 if you want to start tracking purchases without an opening balance.") }
            Section { Text("New purchases deduct from this balance. Updating the balance replaces the current amount and keeps your purchase history. For an older purchase already included in the balance, turn off Deduct from current balance.").font(.footnote).foregroundStyle(.secondary) }
        }.paperForm().navigationTitle(existing == nil ? "Manual Account" : "Update Balance").navigationBarTitleDisplayMode(.inline)
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
                    Text(account.bankAccountKey == nil ? "Manual account · no bank connection" : "Connected account · reviewed balance snapshot").font(.caption).foregroundStyle(.secondary)
                    Text("Updated \(account.updated.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
                if account.isArchived != true { Section {
                    NavigationLink("Update Balance") { ManualAccountForm(existing: account) }
                } }
                Section("Purchases (\(purchases.count))") {
                    if purchases.isEmpty { Text("Your purchases for this account will appear here.").foregroundStyle(.secondary) }
                    ForEach(purchases) { expense in
                        Button { selectedExpense = expense } label: { ExpenseListRow(expense: expense) }.buttonStyle(.plain)
                    }
                }
            }
        }.paperForm().navigationTitle(account?.name ?? "Account").navigationBarTitleDisplayMode(.inline)
            .bottomAdd("Add Purchase", enabled: account != nil && account?.isArchived != true) { addPurchase = true }
            .sheet(isPresented: $addPurchase) { NavigationStack { ExpenseForm(initialAccount: accountID) } }
            .sheet(item: $selectedExpense) { expense in NavigationStack { ExpenseDetail(expense: expense) } }
    }
}
