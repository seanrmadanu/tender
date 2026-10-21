import SwiftUI

struct SampleCleanupView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selection = PersonalLedgerSelection()
    @State private var confirm = false
    var body: some View {
        Form {
            Section {
                Text("Keep only entries you added yourself. Leave everything off to start empty.")
                Text("The previous app mixed your edits with sample data. A recovery copy and attached files will stay on this device.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Account balances to keep") {
                ForEach(store.ledger.accounts) { account in
                    Toggle("\(account.name) · \(Money.format(account.available))", isOn: selected(account.id, in: $selection.accounts))
                }
                Text("An account needed by a kept expense will remain with a zero balance unless you select its balance here.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Expenses to keep") {
                ForEach(store.ledger.expenses.sorted { $0.date > $1.date }) { expense in
                    Toggle(isOn: selected(expense.id, in: $selection.expenses)) {
                        VStack(alignment: .leading) {
                            Text("\(expense.merchant) · \(Money.format(expense.amount))")
                            Text(expense.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Groceries and prices to keep") {
                ForEach(store.ledger.groceries) { item in
                    Toggle("\(item.name) · \(item.observations.count) prices", isOn: selected(item.id, in: $selection.groceries))
                }
            }
            Section("Recurring payments to keep") {
                ForEach(store.ledger.recurring) { bill in
                    Toggle("\(bill.name) · \(Money.format(bill.amount))", isOn: selected(bill.id, in: $selection.recurring))
                }
            }
            Section {
                Toggle("Keep existing budget allocations", isOn: $selection.keepBudgets)
            } footer: { Text("Leave off to start category budgets at zero. Category names are retained.") }
            Section { Button("Remove Unselected Sample Data", role: .destructive) { confirm = true } }
        }.paperForm().navigationTitle("Review Sample Ledger").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Keep selected entries and remove the rest? A recovery copy will be saved first.", isPresented: $confirm, titleVisibility: .visible) {
                Button("Create Personal Ledger", role: .destructive) {
                    do {
                        let next = try store.ledger.personalLedger(keeping: selection)
                        if store.replaceWithPersonalLedger(next) { Task { await store.refreshReminders() }; dismiss() }
                    } catch { store.error = "The selected entries couldn’t be converted. Your ledger is unchanged." }
                }
            }
    }
    private func selected(_ id: UUID, in values: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(get: { values.wrappedValue.contains(id) }, set: { on in
            if on { values.wrappedValue.insert(id) } else { values.wrappedValue.remove(id) }
        })
    }
}
