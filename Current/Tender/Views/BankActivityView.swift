import SwiftUI

struct BankActivityRow: View {
    @Environment(LedgerStore.self) private var store
    let transaction: BankTransaction
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(symbol: transaction.isTransfer ? "arrow.left.arrow.right" : "building.columns")
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.merchant).font(.subheadline.weight(.semibold))
                Text("\(transaction.date) · \(transaction.pending ? "Pending" : transaction.isTransfer ? "Transfer/payment" : transaction.amountCents < 0 ? "Credit/refund" : "Posted")").font(.caption).foregroundStyle(Ink.muted)
                if store.ledger.expenses.contains(where: { $0.bankTransactionID == transaction.id }) { Label("Matched to expense", systemImage: "checkmark.circle").font(.caption) }
            }
            Spacer()
            Text(transaction.currency == "USD" ? Money.format(transaction.amountCents) : "\(transaction.amountCents) minor units · \(transaction.currency ?? "unknown currency")").font(.subheadline).monospacedDigit()
        }.frame(minHeight: 48).contentShape(Rectangle())
    }
}
struct BankActivityView: View {
    @Environment(LedgerStore.self) private var store
    @State private var selected: BankTransaction?
    private var transactions: [BankTransaction] { (store.ledger.bankActivity ?? []).flatMap(\.transactions).sorted { $0.date > $1.date } }
    var body: some View {
        List {
            Section {
                Text("Bank imports do not deduct balances. Review posted purchases to add them to your category totals, or match a receipt you already entered. Credits, transfers and pending entries stay outside spending totals.").font(.footnote)
                if let message = store.bankMessage { Text(message).foregroundStyle(Ink.warning) }
                ForEach(store.ledger.bankActivity ?? [], id: \.id) { item in
                    if let checked = item.checkedAt { Text("Activity checked \(checked.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                }
            }
            if transactions.isEmpty { Text("No bank activity yet. Connect a bank and wait for its history to become available.") }
            ForEach(transactions) { transaction in
                Button { selected = transaction } label: { BankActivityRow(transaction: transaction) }.buttonStyle(.plain)
            }
        }.paperForm().navigationTitle("Bank Activity")
            .refreshable { await store.refreshBank(force: true) }
            .sheet(item: $selected) { t in NavigationStack { ReviewBankPurchase(transaction: t) } }
    }
}
struct ReviewBankPurchase: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let transaction: BankTransaction
    @State private var category: UUID?
    @State private var match: UUID?
    private var account: Account? { store.ledger.accounts.first { $0.bankAccountKey == transaction.accountKey } }
    private var recorded: Bool { store.ledger.expenses.contains { $0.bankTransactionID == transaction.id } }
    private var candidates: [Expense] {
        store.ledger.expenses.filter { $0.accountID == account?.id && $0.bankTransactionID == nil && $0.amount == transaction.amountCents && abs($0.date.timeIntervalSince(transaction.purchaseDate ?? .distantPast)) < 4 * 86400 }
    }
    var body: some View {
        Form {
            Section { BankActivityRow(transaction: transaction) }
            if recorded { Text("This bank purchase is already matched to your recorded expenses.") }
            else if !transaction.canRecord { Text("Only posted USD purchases can become an expense. Pending entries may change; credits and transfers are shown here without increasing spending.") }
            else if account == nil { Text("First add or match this bank account in Settings → Accounts → Bank Connect.") }
            else {
                Section {
                    Picker("Category", selection: $category) { Text("Choose").tag(UUID?.none); ForEach(store.ledger.categories) { Text($0.name).tag(Optional($0.id)) } }
                    if !candidates.isEmpty {
                        Picker("Receipt match", selection: $match) {
                            Text("Record as a new expense").tag(UUID?.none)
                            ForEach(candidates) { Text("\($0.merchant) · \($0.date.formatted(date: .abbreviated, time: .omitted))").tag(Optional($0.id)) }
                        }
                        Text("Possible matches have the same account and amount within four days. Choose the correct existing purchase to avoid counting it twice.").font(.footnote)
                    }
                    Button(match == nil ? "Add to Expenses" : "Match Existing Expense") {
                        guard let category else { return }
                        if store.update({ try $0.recordBankPurchase(transaction, categoryID: category, matching: match) }) { dismiss() }
                    }.disabled(category == nil)
                } header: { Text("Review") } footer: { Text("No balance deduction. Bank-created expenses follow later bank corrections; matched manual receipts retain your entered values.") }
            }
        }.paperForm().navigationTitle("Review Purchase").toolbar { Button("Done") { dismiss() } }
    }
}
