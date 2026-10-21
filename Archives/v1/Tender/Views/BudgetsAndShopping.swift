import SwiftUI

struct BudgetView: View {
    @Environment(LedgerStore.self) private var store
    @State private var editing: BudgetCategory?
    @State private var adding = false
    var body: some View {
        PaperScreen {
            SectionHeading(title: "Give your money a purpose.", subtitle: "Monthly envelopes · \(Date().formatted(.dateTime.month(.wide)))")
            PaperCard { AmountRow(label: "Total monthly allocation", amount: store.ledger.monthlyBudget); AmountRow(label: "Remaining this month", amount: store.ledger.monthlyBudget - store.ledger.spent(in: store.ledger.month())) }
            ForEach(store.ledger.categories) { category in
                Button { editing = category } label: {
                    PaperCard {
                        HStack { CategoryIcon(symbol: category.symbol); Text(category.name).font(.headline); Spacer(); Image(systemName: "pencil").font(.subheadline) }
                        AmountRow(label: "Remaining", amount: store.ledger.remaining(category))
                        BudgetMeter(spent: store.ledger.spent(category: category.id, in: store.ledger.month()), limit: category.limit)
                        Text("\(Money.format(store.ledger.spent(category: category.id, in: store.ledger.month()))) spent / \(Money.format(category.limit)) allocated").font(.caption).foregroundStyle(Ink.muted)
                    }
                }.buttonStyle(.plain)
                NavigationLink {
                    CategoryReviewView(categoryID: category.id, interval: store.ledger.month())
                } label: {
                    Label("Review \(category.name) expenses & bills", systemImage: "receipt").font(.subheadline).frame(minHeight: 44)
                }
            }
            Text("Budgets reset by calendar month. Unspent allocations don’t roll over. Adding an expense always uses your chosen category.").font(.footnote).foregroundStyle(Ink.muted)
        }.navigationTitle("Budgets")
            .toolbar { Button { adding = true } label: { Label("Add category", systemImage: "plus") } }
            .sheet(item: $editing) { category in NavigationStack { CategoryForm(category: category) } }
            .sheet(isPresented: $adding) { NavigationStack { CategoryForm(category: nil) } }
    }
}
struct CategoryForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let category: BudgetCategory?
    @State private var name = ""
    @State private var amount = ""
    @State private var symbol = "tag"
    private let symbols = ["tag", "carrot", "cup.and.saucer", "bag", "tram", "house", "heart", "airplane", "graduationcap", "gift"]
    var body: some View {
        Form {
            Section("Envelope") { TextField("Category name", text: $name); TextField("Monthly allocation (USD)", text: $amount).keyboardType(.decimalPad); Picker("Icon", selection: $symbol) { ForEach(symbols, id: \.self) { Label($0, systemImage: $0).tag($0) } } }
            Section { Text("An allocation is a spending limit, not a transfer or an expense.").foregroundStyle(.secondary) }
        }.paperForm().navigationTitle(category == nil ? "New Category" : "Edit Category").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Money.cents(amount) == nil) } }
            .onAppear { if let category { name = category.name; amount = Money.input(category.limit); symbol = category.symbol } }
    }
    private func save() {
        guard let cents = Money.cents(amount) else { return }
        if store.update({ ledger in
            if let category, let i = ledger.categories.firstIndex(where: { $0.id == category.id }) { ledger.categories[i].name = name; ledger.categories[i].limit = cents; ledger.categories[i].symbol = symbol }
            else { ledger.categories.append(BudgetCategory(name: name, symbol: symbol, limit: cents)) }
        }) { dismiss() }
    }
}
struct ShoppingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var categoryID: UUID?
    @State private var record = false
    private var category: BudgetCategory? { store.ledger.categories.first { $0.id == categoryID } }
    private var decision: ShoppingDecision? { guard let c = category, let value = Money.cents(amount), value > 0 else { return nil }; return store.ledger.shopping(amount: value, category: c) }
    var body: some View {
        PaperScreen {
            ZStack { Engraving().frame(height: 90); Image(systemName: "bag").font(.system(size: 34)).padding(20).background(Ink.paper, in: Circle()) }
            SectionHeading(title: "A moment before checkout.", subtitle: "Check the numbers. Then make the call.")
            PaperCard {
                Text("PLANNED PURCHASE").font(.system(.caption, design: .monospaced)).tracking(1.5).foregroundStyle(Ink.muted)
                HStack(alignment: .firstTextBaseline) { Text("$").font(.largeTitle); TextField("0.00", text: $amount).keyboardType(.decimalPad).font(.system(.largeTitle, design: .serif)).accessibilityLabel("Purchase amount in US dollars") }
                Picker("Category", selection: $categoryID) { Text("Choose an envelope").tag(UUID?.none); ForEach(store.ledger.categories) { Text($0.name).tag(Optional($0.id)) } }.pickerStyle(.menu)
            }
            if let decision {
                PaperCard {
                    Label(decision.fits ? "Within your recorded budget" : "This needs a second look", systemImage: decision.fits ? "checkmark.seal" : "exclamationmark.triangle").font(.headline).foregroundStyle(decision.fits ? Ink.green : Ink.warning)
                    if !decision.hasAccount { Text("Add an account balance before checking available cash.").font(.subheadline) }
                    AmountRow(label: "Category after purchase", amount: decision.categoryAfter)
                    AmountRow(label: "Cash after purchase & bills", amount: decision.cashAfter)
                    Text(decision.fits ? "This amount fits both checks using your recorded balances." : "The purchase exceeds your category allocation, cash after bills, or both.").font(.subheadline).foregroundStyle(Ink.muted)
                }
                Button("Record This Purchase") { record = true }.buttonStyle(PrimaryButton()).disabled(!decision.hasAccount)
            } else { Text("Enter an amount and choose a category to see both checks.").font(.subheadline).foregroundStyle(Ink.muted) }
            Text("Cash uses recorded account snapshots, adjusted by your expenses, minus tracked bills due in the next 30 days. Unrecorded spending and pending charges may be missing. Checking does not reserve money.").font(.footnote).foregroundStyle(Ink.muted)
            if store.ledger.isDemo { Label("You’re checking sample data", systemImage: "sparkle").font(.footnote) }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: decision != nil)
            .navigationTitle("Shopping Mode").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $record) { NavigationStack { ExpenseForm(initialAmount: amount, initialCategory: categoryID) } }
    }
}
