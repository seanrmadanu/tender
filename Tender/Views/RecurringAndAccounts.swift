import SwiftUI

struct RecurringList: View {
    @Environment(LedgerStore.self) private var store
    @State private var edit: RecurringBill?
    var body: some View {
        SectionHeading(title: "Know what’s coming.", subtitle: "Subscriptions, bills, and the little renewals.")
        PaperCard { AmountRow(label: "Monthly equivalent", amount: store.ledger.recurring.reduce(0) { $0 + $1.monthlyEquivalent }); AmountRow(label: "Reserved for next 30 days", amount: store.ledger.upcomingReserve()) }
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
    }
}
struct RecurringForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var existing: RecurringBill? = nil
    @State private var name = ""
    @State private var amount = ""
    @State private var category: UUID?
    @State private var due = Date()
    @State private var cycle = BillingCycle.monthly
    @State private var remind = false
    @State private var account: UUID?
    @State private var delete = false
    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && (Money.cents(amount) ?? 0) > 0 && category != nil }
    var body: some View {
        Form {
            Section("Payment") { TextField("Name", text: $name); TextField("Amount (USD)", text: $amount).keyboardType(.decimalPad); Picker("Category", selection: $category) { Text("Choose").tag(UUID?.none); ForEach(store.ledger.categories) { Text($0.name).tag(Optional($0.id)) } }; Picker("Repeats", selection: $cycle) { ForEach(BillingCycle.allCases, id: \.self) { Text($0.rawValue).tag($0) } }; DatePicker("Next due", selection: $due, displayedComponents: .date) }
            Section { Toggle("Remind me one day before at 9 AM", isOn: $remind) } footer: { Text("Tender asks for notification access when you save a reminder. Due dates within one day may be too close for a reminder.") }
            if existing != nil {
                Section("Record payment") {
                    Picker("Paid from", selection: $account) { Text("Choose").tag(UUID?.none); ForEach(store.ledger.accounts) { Text($0.name).tag(Optional($0.id)) } }
                    Button("Mark Paid & Advance Due Date") { Task { await save(paid: true) } }.disabled(!valid || account == nil)
                }
                Section { Button("Delete Recurring Payment", role: .destructive) { delete = true } }
            }
        }.paperForm().navigationTitle(existing == nil ? "New Recurring Payment" : "Recurring Payment").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save(paid: false) } }.disabled(!valid) } }
            .onAppear { account = store.ledger.accounts.first?.id; category = store.ledger.categories.last?.id; if let e = existing { name = e.name; amount = Money.input(e.amount); category = e.categoryID; due = e.nextDue; cycle = e.cycle; remind = e.remind } }
            .confirmationDialog("Delete this recurring payment?", isPresented: $delete, titleVisibility: .visible) { Button("Delete", role: .destructive) { if store.update({ $0.recurring.removeAll { $0.id == existing?.id } }) { Task { await store.refreshReminders() }; dismiss() } } }
    }
    private func save(paid: Bool) async {
        guard let cents = Money.cents(amount), let category else { return }
        var bill = RecurringBill(name: name, amount: cents, categoryID: category, nextDue: due, cycle: cycle, remind: remind)
        if let existing {
            bill.id = existing.id
            let sameSchedule = existing.cycle == cycle && Calendar.current.isDate(existing.nextDue, inSameDayAs: due)
            bill.recurrenceAnchor = sameSchedule ? (existing.recurrenceAnchor ?? existing.nextDue) : due
        } else { bill.recurrenceAnchor = due }
        if remind { guard await store.enableReminders() else { return } }
        if paid { bill.nextDue = bill.advanced() }
        let result = store.update { ledger in
            if paid, let account { try ledger.record(Expense(merchant: name, amount: cents, categoryID: category, accountID: account, note: "Recurring payment")) }
            if let i = ledger.recurring.firstIndex(where: { $0.id == bill.id }) { ledger.recurring[i] = bill } else { ledger.recurring.append(bill) }
        }
        if result { await store.refreshReminders(); dismiss() }
    }
}
struct AccountForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var editing: Account?
    @State private var name = ""
    @State private var amount = ""
    var body: some View {
        Form {
            Section {
                NavigationLink { BankConnectionView() } label: { Label("Connect with Plaid", systemImage: "building.columns") }
                Text("Connect multiple banks and select each checking or savings account in Plaid. You can also add multiple manual accounts below.").font(.subheadline).foregroundStyle(.secondary)
            } header: { Text("Bank Connect") }
            Section("Your accounts (\(store.ledger.accounts.count))") {
                if !store.ledger.accounts.isEmpty { LabeledContent("Total available", value: Money.format(store.ledger.available)) }
                if store.ledger.accounts.isEmpty { Text("Add a checking account or cash wallet below.").foregroundStyle(.secondary) }
                ForEach(store.ledger.accounts) { account in
                    Button { editing = account; name = account.name; amount = Money.input(max(0, account.available)) } label: {
                        VStack(alignment: .leading, spacing: 6) { HStack { Text(account.name); Spacer(); Text(Money.format(account.available)).monospacedDigit() }; Text("\(account.source) · Updated \(account.updated.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Section(editing == nil ? "Add manual account" : "Update balance snapshot") {
                TextField("Account name", text: $name)
                TextField("Available balance (USD)", text: $amount).keyboardType(.decimalPad)
                Button(editing == nil ? "Add Account" : "Update Balance") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Money.cents(amount) == nil)
                if editing != nil { Button("Cancel Editing") { editing = nil; name = ""; amount = "" } }
            }
            Section { Text("Enter the balance available right now. Recording a new expense deducts from it. Updating a snapshot replaces the current balance, without changing your expense history. Manual entry accepts zero or positive cash balances; recorded spending and bank snapshots can show a negative balance. Credit-card debt is not modeled.").font(.footnote).foregroundStyle(.secondary) }
        }.paperForm().navigationTitle("Accounts").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
    }
    private func save() {
        guard let cents = Money.cents(amount) else { return }
        if store.update({ ledger in
            if let editing, let i = ledger.accounts.firstIndex(where: { $0.id == editing.id }) { ledger.accounts[i].name = name; ledger.setBalance(accountID: editing.id, available: cents); ledger.accounts[i].source = ledger.isDemo ? "Sample" : "Manual" }
            else { ledger.accounts.append(Account(name: name, available: cents, source: ledger.isDemo ? "Sample" : "Manual")) }
        }) { editing = nil; name = ""; amount = "" }
    }
}
