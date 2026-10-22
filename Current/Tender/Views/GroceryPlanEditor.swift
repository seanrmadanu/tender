import SwiftUI

struct GroceryPlanEditor: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let item: GroceryItem
    @State private var name = ""
    @State private var shop = ""
    @State private var quantity = 1
    @State private var date = Date()
    @State private var remind = false
    @State private var saving = false
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (!remind || date.addingTimeInterval(-3600) > Date())
    }
    var body: some View {
        Form {
            Section("Shopping plan") {
                TenderField("Item name", text: $name)
                TenderField("Store (optional)", text: $shop).accessibilityIdentifier("plan-store")
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                DatePicker("When", selection: $date)
                Toggle("Remind me one hour before", isOn: $remind)
                if remind {
                    Text("Reminder: \(date.addingTimeInterval(-3600).formatted(date: .abbreviated, time: .shortened))")
                    if date.addingTimeInterval(-3600) <= Date() {
                        Text("Choose a time more than an hour ahead, or turn the reminder off.").foregroundStyle(Ink.warning)
                    }
                }
            }
        }.paperForm().navigationTitle("Edit Shopping Plan")
            .onAppear { name = item.name; shop = item.storeName ?? ""; quantity = item.quantity; date = item.plannedAt ?? Date(); remind = item.remind == true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(!valid || saving) }
            }
    }
    private func save() async {
        guard valid, !saving else { return }
        saving = true; defer { saving = false }
        if remind { guard await store.enableReminders() else { return } }
        if store.update({ ledger in
            guard let i = ledger.groceries.firstIndex(where: { $0.id == item.id }), ledger.groceries[i].purchasedAt == nil else { throw LedgerError.invalidExpense }
            ledger.groceries[i].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            ledger.groceries[i].storeName = shop.trimmingCharacters(in: .whitespacesAndNewlines)
            ledger.groceries[i].quantity = quantity
            ledger.groceries[i].plannedAt = date
            ledger.groceries[i].remind = remind
        }) { await store.refreshReminders(); dismiss() }
    }
}
