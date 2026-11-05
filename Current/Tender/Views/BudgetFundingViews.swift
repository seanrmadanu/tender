import SwiftUI

struct FixedExpensePicker: View {
    @Environment(LedgerStore.self) private var store
    @Binding var selection: UUID?
    var body: some View {
        Picker("Fixed expense", selection: $selection) {
            Text("Envelope purchase").tag(UUID?.none)
            ForEach((store.ledger.fixedExpenses ?? []).filter { $0.archivedAt == nil || $0.id == selection }) {
                Text($0.name + ($0.archivedAt == nil ? "" : " (archived)")).tag(Optional($0.id))
            }
        }
    }
}

struct BudgetFundingSummary: View {
    @Environment(LedgerStore.self) private var store
    var detailed = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Money available for envelopes").font(.headline)
            if detailed {
                ForEach(store.ledger.activeAccounts) { account in
                    AmountRow(label: account.name, amount: account.available)
                }
            }
            if store.ledger.activeAccounts.isEmpty { Text("Add an account or cash balance in Settings to fund your budget.").font(.footnote).foregroundStyle(Ink.muted) }
            Divider()
            AmountRow(label: "Account balances", amount: store.ledger.available)
            AmountRow(label: "Unpaid fixed expenses", amount: store.ledger.fixedReserve())
            AmountRow(label: "Available for budgeting", amount: store.ledger.budgetCapacity())
                .accessibilityIdentifier("budget-capacity")
            if detailed { Text("Based on saved balances, including cash. Keep offline balances up to date. Add obligations you want to protect as fixed expenses below.").font(.caption).foregroundStyle(Ink.muted) }
            if store.bankIsOffline || store.bankMessage != nil { Text("Bank information may be outdated. Review balances before allocating.").font(.caption).foregroundStyle(Ink.warning) }
        }
    }
}

struct FixedExpenseForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var existing: FixedExpense?
    @State private var name = ""
    @State private var amount = ""
    @State private var payment = false
    @State private var deleting = false
    private var cents: Int64? { Money.cents(amount) }
    private var cleaned: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        Form {
            Section {
                TenderField("Name, such as Rent", text: $name).accessibilityIdentifier("fixed-expense-name")
                TenderField("Monthly amount (USD)", text: $amount, numeric: true).accessibilityIdentifier("fixed-expense-amount")
            } footer: { Text("A monthly reserve for rent, utilities or other commitments. This sets money aside in your plan; it does not move money or record a purchase.") }
            if let existing {
                Section("This month") {
                    AmountRow(label: "Payments recorded", amount: store.ledger.fixedPaid(existing))
                    AmountRow(label: "Still reserved", amount: store.ledger.fixedOutstanding(existing))
                    Button("Add manual payment", systemImage: "receipt") { payment = true }
                    Text("You can also link a bank or manual purchase from Review monthly payments. Linked payments release this month's reserve, and stay out of envelope spending.").font(.caption)
                }
                Section { Button("Delete Fixed Expense", role: .destructive) { deleting = true } }
            }
        }.paperForm().navigationTitle(existing == nil ? "Add Fixed Expense" : "Fixed Expense").navigationBarTitleDisplayMode(.inline)
            .onAppear { if let existing { name = existing.name; amount = Money.input(existing.amount) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let cents else { return }
                        var fixed = existing ?? FixedExpense(name: cleaned, amount: cents)
                        fixed.name = cleaned; fixed.amount = cents
                        if store.update({ try $0.saveFixedExpense(fixed) }) { dismiss() }
                    }.disabled(cleaned.isEmpty || cleaned.count > 80 || (cents ?? 0) <= 0)
                        .accessibilityIdentifier("save-fixed-expense")
                }
            }
            .sheet(isPresented: $payment) {
                if let existing {
                    NavigationStack { ExpenseForm(initialAmount: Money.input(store.ledger.fixedOutstanding(existing)), initialCategory: store.ledger.categories.first(where: { $0.symbol == "house" })?.id ?? store.ledger.categories.first?.id, initialMerchant: existing.name, initialFixedExpenseID: existing.id) }
                }
            }
            .confirmationDialog("Delete this fixed expense?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let existing, store.update({ ledger in
                        if let index = ledger.fixedExpenses?.firstIndex(where: { $0.id == existing.id }) { ledger.fixedExpenses?[index].archivedAt = Date() }
                    }) { dismiss() }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Its payments stay in your history. Restore the reserve from Settings → Archive.") }
    }
}

struct MonthlyPaymentsReview: View {
    @Environment(LedgerStore.self) private var store
    var initialMonth = Date()
    @State private var offset = 0
    @State private var bank: BankTransaction?
    @State private var manual: Expense?
    @State private var result: String?
    private var date: Date { Calendar.current.date(byAdding: .month, value: offset, to: initialMonth)! }
    private var interval: DateInterval { store.ledger.month(at: date) }
    var body: some View {
        let entries = store.ledger.spendingEntries(in: interval)
        let suggestions = store.ledger.suggestedPurchases(in: interval)
        List {
            Section {
                HStack {
                    Button { offset -= 1 } label: { Image(systemName: "chevron.left").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel("Previous payment month")
                    Spacer(); Text(date.formatted(.dateTime.month(.wide).year())).font(.headline); Spacer()
                    Button { offset += 1 } label: { Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44) }
                        .disabled(interval.end > Date()).accessibilityLabel("Next payment month")
                }.buttonStyle(.borderless)
                AmountRow(label: "Posted spending", amount: entries.reduce(0) { $0 + $1.amount })
                Text("Review purchases individually, choose an envelope, or link a fixed expense. Transfers, credits and pending bank entries are excluded. Matching a manual receipt keeps it from being counted twice.").font(.footnote).foregroundStyle(.secondary)
                if !suggestions.isEmpty {
                    Button("Apply \(suggestions.count) suggested categories") {
                        var count = 0
                        if store.update({ count = try $0.categorizeSuggestedPurchases(in: interval) }) { result = "\(count) purchases categorized. Balances are unchanged." }
                    }.accessibilityIdentifier("apply-monthly-suggestions")
                    Text("Suggestions use the bank's category and your existing envelopes. Purchases with uncertain receipt matches stay for individual review.").font(.caption)
                }
                if let result { Text(result).font(.footnote).foregroundStyle(Ink.green) }
            }
            Section("Purchases") {
                if entries.isEmpty { Text("No posted purchases in this month.") }
                ForEach(entries) { entry in
                    Button { open(entry) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.merchant).font(.headline)
                                AssistantBadge(origin: entry.assistantOrigin, edited: entry.assistantLastEdit)
                                Text(entry.date.formatted(.dateTime.day().month(.wide).year())).font(.caption).foregroundStyle(.secondary)
                                if let fixed = store.ledger.fixedExpenses?.first(where: { $0.id == entry.fixedExpenseID }) { Text("Fixed expense · " + fixed.name).font(.caption).foregroundStyle(Ink.green) }
                                else if let category = store.ledger.categories.first(where: { $0.id == entry.categoryID }) { Text(category.name).font(.caption).foregroundStyle(.secondary) }
                                else if let transaction = transaction(entry), let suggested = store.ledger.suggestedCategory(for: transaction) { Text("Suggested: " + suggested.name).font(.caption).foregroundStyle(Ink.green) }
                                else { Text("Choose an envelope").font(.caption).foregroundStyle(Ink.warning) }
                            }
                            Spacer(minLength: 8); Text(Money.format(entry.amount)).monospacedDigit(); Image(systemName: "chevron.right").font(.caption)
                        }.foregroundStyle(Ink.green).padding(.vertical, 5)
                    }.accessibilityIdentifier("review-payment-" + entry.id)
                }
            }
        }.paperForm().navigationTitle("Monthly Payments").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $bank) { transaction in NavigationStack { ReviewBankPurchase(transaction: transaction) } }
            .sheet(item: $manual) { expense in NavigationStack { ExpenseDetail(expense: expense) } }
    }
    private func transaction(_ entry: SpendingEntry) -> BankTransaction? { store.ledger.reviewableBankPurchases.first { $0.id == entry.bankTransactionID } }
    private func open(_ entry: SpendingEntry) {
        if let expense = store.ledger.expenses.first(where: { $0.id == entry.expenseID }), expense.bankTransactionID != nil || entry.bankTransactionID == nil { manual = expense }
        else if let transaction = transaction(entry) { bank = transaction }
    }
}
