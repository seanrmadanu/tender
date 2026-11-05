import SwiftUI
import PhotosUI

struct BudgetView: View {
    @Environment(LedgerStore.self) private var store
    @State private var editing: BudgetCategory?
    @State private var adding = false
    @State private var selecting = false
    @State private var selected = Set<UUID>()
    @State private var deleting = false
    @State private var editingAllocations = false
    @State private var addingFixed = false
    @State private var editingFixed: FixedExpense?
    var body: some View {
        PaperScreen {
            SectionHeading(title: "Give your money a purpose.", subtitle: "Monthly envelopes · \(Date().formatted(.dateTime.month(.wide)))")
            PaperCard { BudgetFundingSummary(detailed: false) }
            PaperCard {
                HStack { Text("Fixed expenses").font(.headline); Spacer(); Button("Add", systemImage: "plus") { addingFixed = true }.accessibilityIdentifier("add-fixed-expense") }
                if store.ledger.activeFixedExpenses.isEmpty { Text("Reserve rent, utilities and other monthly commitments before allocating to envelopes.").font(.subheadline).foregroundStyle(Ink.muted) }
                ForEach(store.ledger.activeFixedExpenses) { fixed in
                    Button { editingFixed = fixed } label: {
                        HStack { VStack(alignment: .leading, spacing: 4) { HStack { Text(fixed.name); AssistantBadge(origin: fixed.assistantOrigin, edited: fixed.assistantLastEdit) }; Text("\(Money.format(store.ledger.fixedPaid(fixed))) paid this month").font(.caption).foregroundStyle(Ink.muted) }; Spacer(); Text(Money.format(store.ledger.fixedOutstanding(fixed))).monospacedDigit(); Image(systemName: "chevron.right").font(.caption) }.frame(minHeight: 44)
                    }.buttonStyle(.plain)
                }
            }
            NavigationLink { MonthlyPaymentsReview() } label: { Label("Review monthly payments", systemImage: "list.bullet.rectangle").frame(minHeight: 44) }.accessibilityIdentifier("review-monthly-payments")
            PaperCard {
                Button { editingAllocations = true } label: {
                    HStack(spacing: 12) {
                        AmountRow(label: "Total monthly allocation", amount: store.ledger.monthlyBudget)
                        Image(systemName: "pencil").frame(width: 24).opacity(selecting ? 1 : 0)
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).disabled(!selecting)
                    .accessibilityLabel("Total monthly allocation, \(Money.format(store.ledger.monthlyBudget))")
                    .accessibilityHint("Change your overall monthly budget and envelope allocations.")
                    .accessibilityIdentifier("edit-monthly-allocations")
                AmountRow(label: "Remaining this month", amount: store.ledger.monthlyBudget - store.ledger.envelopeSpent(in: store.ledger.month()))
                    .accessibilityIdentifier("monthly-budget-remaining")
                AmountRow(label: "Allocated to envelopes", amount: store.ledger.allocatedToEnvelopes)
                    .accessibilityIdentifier("monthly-envelope-total")
                AmountRow(label: store.ledger.unallocatedBudget < 0 ? "Overallocated by" : "Available to allocate",
                          amount: abs(store.ledger.unallocatedBudget), warning: store.ledger.unallocatedBudget < 0)
                    .accessibilityIdentifier("monthly-unallocated")
                if store.ledger.monthlyBudget > store.ledger.budgetCapacity() || store.ledger.allocatedToEnvelopes > store.ledger.budgetCapacity() {
                    Text("Your saved plan exceeds the funds currently available. Edit allocations to bring it within the available balance.").font(.footnote).foregroundStyle(Ink.warning)
                }
            }
            ForEach(store.ledger.categories) { category in
                if selecting {
                    Button {
                        if selected.contains(category.id) { selected.remove(category.id) } else { selected.insert(category.id) }
                    } label: { categoryCard(category) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("budget-select-" + category.id.uuidString)
                        .accessibilityAddTraits(selected.contains(category.id) ? .isSelected : [])
                        .popover(isPresented: Binding(get: { deleting && store.ledger.categories.first(where: { selected.contains($0.id) })?.id == category.id }, set: { deleting = $0 }), attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(selected.count == 1 ? "Delete \(category.name)?" : "Delete \(selected.count) envelopes?").font(.headline)
                                Text("You can restore these envelopes from Settings → Archive. Their purchases stay in Uncategorized until restored.").font(.subheadline)
                                HStack(spacing: 16) {
                                    Button("Cancel") { deleting = false }
                                        .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered)
                                    Button(role: .destructive) {
                                        if store.update({ $0.archiveCategories(selected) }) { deleting = false; selected.removeAll(); selecting = false }
                                    } label: {
                                        Text("Delete").foregroundStyle(.white).lineLimit(1).frame(maxWidth: .infinity, minHeight: 44)
                                    }.buttonStyle(.borderedProminent).tint(Ink.destructive)
                                        .accessibilityIdentifier("confirm-delete-envelopes")
                                }
                            }.padding(20).frame(idealWidth: 300).presentationCompactAdaptation(.popover)
                        }
                } else {
                    NavigationLink {
                        CategoryReviewView(categoryID: category.id, interval: store.ledger.month(), envelopeOnly: true)
                    } label: { categoryCard(category) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Review \(category.name) expenses and bills")
                }
            }
            Text("Budgets reset by calendar month. Unspent allocations don’t roll over. Adding an expense always uses your chosen category.").font(.footnote).foregroundStyle(Ink.muted)
        }.navigationTitle("Budgets")
            .toolbar(selecting ? .hidden : .visible, for: .tabBar)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Done" : "Edit") { selecting.toggle(); selected.removeAll() }
            } }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(selected.count) selected").font(.subheadline).foregroundStyle(Ink.muted)
                        HStack(spacing: 18) {
                            Button {
                                editing = store.ledger.categories.first { selected.contains($0.id) }
                            } label: {
                                Label("Edit", systemImage: "pencil").lineLimit(1).frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.bordered).disabled(selected.count != 1)
                            Button(role: .destructive) { deleting = true } label: {
                                Label("Delete", systemImage: "trash").lineLimit(1).frame(maxWidth: .infinity, minHeight: 44)
                            }.buttonStyle(.bordered).tint(Ink.destructive).disabled(selected.isEmpty)
                        }
                    }.padding(16)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Ink.muted.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal).padding(.bottom, 8)
                } else {
                    HStack {
                        Spacer()
                        Button { adding = true } label: {
                            Label("Add category", systemImage: "plus")
                                .font(.headline).padding(.horizontal, 18).frame(minHeight: 52)
                        }.buttonStyle(FloatingActionButtonStyle())
                    }.padding(.horizontal, 18).padding(.vertical, 8)
                }
            }
            .sheet(item: $editing) { category in NavigationStack { CategoryForm(category: category) } }
            .sheet(isPresented: $adding) { NavigationStack { CategoryForm(category: nil) } }
            .sheet(isPresented: $editingAllocations) { NavigationStack { MonthlyAllocationsForm() } }
            .sheet(isPresented: $addingFixed) { NavigationStack { FixedExpenseForm() } }
            .sheet(item: $editingFixed) { fixed in NavigationStack { FixedExpenseForm(existing: fixed) } }
    }
    private func categoryCard(_ category: BudgetCategory) -> some View {
        PaperCard {
            HStack {
                CategoryIcon(symbol: category.symbol)
                Text(category.name).font(.headline)
                AssistantBadge(origin: nil, edited: category.assistantLastEdit)
                Spacer()
                Image(systemName: selecting ? (selected.contains(category.id) ? "checkmark.circle.fill" : "circle") : "receipt")
                    .font(.title3).frame(minWidth: 44, minHeight: 44)
            }
            AmountRow(label: "Remaining", amount: store.ledger.remaining(category))
            BudgetMeter(spent: store.ledger.envelopeSpent(category: category.id, in: store.ledger.month()), limit: category.limit)
            Text("\(Money.format(store.ledger.envelopeSpent(category: category.id, in: store.ledger.month()))) spent / \(Money.format(category.limit)) allocated")
                .font(.caption).foregroundStyle(Ink.muted)
        }
    }

}
struct MonthlyAllocationsForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [UUID: String] = [:]
    @State private var totalDraft: String?
    @State private var saveError: String?
    private func input(for category: BudgetCategory) -> String {
        drafts[category.id] ?? (category.limit == 0 ? "" : Money.input(category.limit))
    }
    private var allocations: [UUID: Int64]? {
        var result: [UUID: Int64] = [:]
        for category in store.ledger.categories {
            let text = input(for: category)
            guard let amount = text.isEmpty ? 0 : Money.cents(text) else { return nil }
            result[category.id] = amount
        }
        return result
    }
    private var totalInput: String { totalDraft ?? (store.ledger.monthlyBudget == 0 ? "" : Money.input(store.ledger.monthlyBudget)) }
    private var total: Int64? {
        // Preserve large legacy totals when only envelope amounts are being edited.
        if totalDraft == nil { return store.ledger.monthlyBudget }
        return totalInput.isEmpty ? 0 : Money.cents(totalInput)
    }
    private var withinFunding: Bool { if let total, let allocations { return total <= store.ledger.budgetCapacity() && allocations.values.reduce(0, +) <= total }; return false }
    var body: some View {
        Form {
            Section { BudgetFundingSummary(); Button("Use available amount") { totalDraft = Money.input(store.ledger.budgetCapacity()) } }
            Section {
                TenderField("Total monthly allocation (USD)", text: Binding(get: { totalInput }, set: { totalDraft = $0 }), numeric: true).accessibilityIdentifier("monthly-budget-input")
                if let total, let allocations {
                    let assigned = allocations.values.reduce(0, +)
                    AmountRow(label: "Total monthly allocation", amount: total)
                        .accessibilityIdentifier("allocation-draft-total")
                    AmountRow(label: "Allocated to envelopes", amount: assigned)
                        .accessibilityIdentifier("allocation-draft-assigned")
                    AmountRow(label: assigned > total ? "Overallocated by" : "Available to allocate", amount: abs(total - assigned), warning: assigned > total)
                        .accessibilityIdentifier("allocation-draft-unallocated")
                    if assigned > total {
                        Text("Your envelopes exceed the monthly total. Reduce an envelope amount or increase your monthly allocation.")
                            .font(.footnote).foregroundStyle(Ink.warning)
                    }
                    if total > store.ledger.budgetCapacity() { Text("The maximum allocation is \(Money.format(store.ledger.budgetCapacity())) after fixed expenses.").foregroundStyle(Ink.warning).font(.footnote).accessibilityIdentifier("allocation-cap-warning") }
                } else {
                    Text("Enter valid amounts for your monthly total and envelopes.").foregroundStyle(Ink.warning)
                }
            } footer: { Text("Set one monthly budget, then divide it among any number of envelopes. Adding an envelope doesn’t change your total.") }
            Section {
                ForEach(store.ledger.categories) { category in
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            Label(category.name, systemImage: category.symbol)
                            Spacer(minLength: 0)
                            amountField(category).frame(width: 120)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Label(category.name, systemImage: category.symbol)
                            amountField(category)
                        }
                    }
                }
            } header: { Text("Monthly allocations · USD") }
            footer: { Text("Allocations are spending limits. Changing them doesn’t move money or alter your purchases.") }
        }.paperForm().navigationTitle("Monthly allocations").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let allocations, let total else { return }
                        if store.update({ try $0.setMonthlyAllocations(allocations, total: total) }) { dismiss() }
                        else { saveError = store.error; store.error = nil }
                    }.disabled(!withinFunding).accessibilityIdentifier("save-monthly-allocations")
                }
            }
            .alert("Allocations couldn’t be saved", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "") }
    }
    private func amountField(_ category: BudgetCategory) -> some View {
        TenderField("0.00", text: Binding(get: { input(for: category) }, set: { drafts[category.id] = $0 }), numeric: true).multilineTextAlignment(.trailing).frame(minHeight: 44)
            .accessibilityLabel(category.name + " monthly allocation in US dollars")
            .accessibilityIdentifier("monthly-allocation-" + category.id.uuidString)
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
    private var proposedTotal: Int64 {
        store.ledger.allocatedToEnvelopes - (store.ledger.categories.first { $0.id == category?.id }?.limit ?? 0) + (Money.cents(amount) ?? 0)
    }
    var body: some View {
        Form {
            Section { BudgetFundingSummary() }
            Section("Envelope") { TenderField("Category name", text: $name); TenderField("Monthly allocation (USD)", text: $amount, numeric: true); Picker("Icon", selection: $symbol) { ForEach(symbols, id: \.self) { Label($0, systemImage: $0).tag($0) } } }
            Section {
                AmountRow(label: "Monthly budget", amount: store.ledger.monthlyBudget)
                AmountRow(label: proposedTotal > store.ledger.monthlyBudget ? "Overallocated by" : "Available to allocate",
                          amount: abs(store.ledger.monthlyBudget - proposedTotal), warning: proposedTotal > store.ledger.monthlyBudget)
            } footer: { Text("This envelope uses your existing monthly budget. Change the overall total from Budgets → Edit.") }
            Section { Text("An allocation is a spending limit, not a transfer or an expense.").foregroundStyle(.secondary) }
        }.paperForm().navigationTitle(category == nil ? "New Category" : "Edit Category").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Money.cents(amount) == nil || proposedTotal > min(store.ledger.monthlyBudget, store.ledger.budgetCapacity())) } }
            .onAppear { if let category { name = category.name; amount = Money.input(category.limit); symbol = category.symbol } }
    }
    private func save() {
        guard let cents = Money.cents(amount) else { return }
        if store.update({ ledger in
            var updated = category ?? BudgetCategory(name: name, symbol: symbol, limit: cents)
            updated.name = name; updated.symbol = symbol; updated.limit = cents
            try ledger.setCategoryAllocation(updated)
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
    @State private var quantity = 1
    @State private var unit = "each"
    @State private var camera = false
    @State private var choosingPhoto = false
    @State private var photo: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var scanning = false
    @State private var message: String?
    @State private var savedCartID: UUID?
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var itemName = ""
    private enum InputField: Hashable { case name, price }
    @FocusState private var focusedInput: InputField?
    private var category: BudgetCategory? { store.ledger.categories.first { $0.id == categoryID } }
    private var cartPurchased: Bool { store.ledger.groceries.first { $0.id == savedCartID }?.purchasedAt != nil }
    private var unitPrice: Int64? { Money.cents(amount) }
    private var total: Int64? { unitPrice.map { $0 * Int64(quantity) } }
    private var canAdd: Bool {
        !scanning && savedCartID == nil &&
        (!itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (unitPrice ?? 0) > 0) &&
        (amount.isEmpty || (unitPrice ?? 0) > 0)
    }
    private var decision: ShoppingDecision? { guard let c = category, let value = total, value > 0, value <= 99_999_999_999 else { return nil }; return store.ledger.shopping(amount: value, category: c) }
    var body: some View {
        PaperScreen {
            SectionHeading(title: "A moment before checkout.", subtitle: "Check the numbers. Then make the call.")
            PaperCard {
                TextField("Item or purchase name", text: $itemName, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded { focusedInput = .name })
                    .focused($focusedInput, equals: .name)
                    .submitLabel(.done)
                    .onSubmit { focusedInput = nil }
                    .accessibilityLabel("Item or purchase name")
                    .accessibilityIdentifier("shopping-item-name")
                if textSize.isAccessibilitySize {
                    priceInput
                    quantityControl
                } else {
                    HStack(spacing: 8) { priceInput; quantityControl }
                }
                if let total, total > 0 { AmountRow(label: "Total · \(quantity) × \(unit)", amount: total).accessibilityIdentifier("shopping-total") }
                if scanning { ProgressView("Reading label…") }
                if let message { Text(message).font(.caption).foregroundStyle(Ink.warning) }
                Picker("Category", selection: $categoryID) { Text("Choose an envelope").tag(UUID?.none); ForEach(store.ledger.categories) { Text($0.name).tag(Optional($0.id)) } }.pickerStyle(.menu)
            }.disabled(scanning)
            if let decision {
                PaperCard {
                    Label(decision.fits ? "Within your recorded budget" : "This needs a second look", systemImage: decision.fits ? "checkmark.seal" : "exclamationmark.triangle").font(.headline).foregroundStyle(decision.fits ? Ink.green : Ink.warning)
                    if !decision.hasAccount { Text("Add an account balance before checking available cash.").font(.subheadline) }
                    AmountRow(label: "Category after purchase", amount: decision.categoryAfter)
                    AmountRow(label: "Cash after purchase & bills", amount: decision.cashAfter)
                    Text(decision.fits ? "This amount fits both checks using your recorded balances." : "The purchase exceeds your category allocation, cash after bills, or both.").font(.subheadline).foregroundStyle(Ink.muted)
                }
            } else { Text("Category is optional for your cart. Choose one and enter a price to check your budget.").font(.subheadline).foregroundStyle(Ink.muted) }
            Button(savedCartID == nil ? "Add to Cart" : (cartPurchased ? "Purchase Recorded" : "Added to Cart"), systemImage: savedCartID == nil ? "cart.badge.plus" : "checkmark") { addToCart() }
                .buttonStyle(PrimaryButton()).disabled(!canAdd).accessibilityIdentifier("shopping-add-cart")
            if savedCartID != nil { Text(cartPurchased ? "Saved in today’s purchases." : "Saved in today’s grocery list. No money spent.").font(.caption).foregroundStyle(Ink.muted).accessibilityIdentifier("shopping-cart-confirmation") }
            Button("Record Purchase") { record = true }.buttonStyle(PrimaryButton()).disabled(decision?.hasAccount != true || scanning || cartPurchased).accessibilityIdentifier("shopping-record-purchase")
            Text("Estimates use recorded balances and upcoming bills. Bank data may be delayed. Adding to Cart doesn’t spend or reserve money.").font(.footnote).foregroundStyle(Ink.muted)
            if store.ledger.isDemo { Label("You’re checking sample data", systemImage: "sparkle").font(.footnote) }
        }.animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: decision != nil)
            .navigationTitle("Shopping Mode").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button { focusedInput = nil } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Hide keyboard")
                    .accessibilityIdentifier("shopping-hide-keyboard")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        focusedInput = nil
                        if CameraPicker.isAvailable { camera = true }
                        else { choosingPhoto = true }
                    } label: { Image(systemName: "text.viewfinder").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Scan price label").accessibilityIdentifier("shopping-scan-label").disabled(scanning)
                    .contextMenu { Button("Choose label photo", systemImage: "photo") { focusedInput = nil; choosingPhoto = true } }
                }
            }
            .onChange(of: itemName) { _, _ in savedCartID = nil }
            .onChange(of: amount) { _, _ in savedCartID = nil }
            .onChange(of: quantity) { _, _ in savedCartID = nil }
            .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
            .onChange(of: photo) { _, item in Task {
                do { if let data = try await item?.loadTransferable(type: Data.self) { await scan(data) } }
                catch { message = "Could not load this photo. Try another image." }
            } }
            .sheet(isPresented: $camera) { CameraPicker { data in Task { await scan(data) } } }
            .sheet(isPresented: $record) { NavigationStack { ExpenseForm(initialAmount: total.map(Money.input) ?? "", initialCategory: categoryID, initialMerchant: itemName, groceryID: savedCartID) } }
    }
    private var priceInput: some View {
        HStack(spacing: 4) {
            Text("$").font(.title)
            TenderField("0.00", text: $amount, numeric: true)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { focusedInput = .price })
                .focused($focusedInput, equals: .price)
                .font(.system(.title, design: .serif)).accessibilityLabel("Price per item in US dollars")
                .accessibilityIdentifier("shopping-unit-price")
        }.frame(maxWidth: .infinity)
    }
    private var quantityControl: some View {
        Picker("Quantity", selection: $quantity) {
            ForEach(1...99, id: \.self) { value in
                Text("\(value)").font(.body.monospacedDigit()).tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(width: 108, height: 116)
        .clipped()
        .accessibilityLabel("Quantity")
        .accessibilityIdentifier("shopping-quantity")
    }
    private func addToCart() {
        guard canAdd else { return }
        var file: String?
        do {
            if let imageData, unitPrice != nil { file = try store.attach(imageData, extension: "jpg") }
            let name = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
            let observations = unitPrice.map { [PriceObservation(price: $0, store: "", photo: file)] } ?? []
            let item = GroceryItem(name: name.isEmpty ? "Shopping item" : name, quantity: quantity, unit: unit,
                                   observations: observations, plannedAt: Date(), remind: false)
            if store.update({ $0.groceries.append(item) }) {
                savedCartID = item.id
                focusedInput = nil
                message = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else {
                if let file { try? FileManager.default.removeItem(at: store.attachmentURL(file)) }
                message = "Couldn’t save this item. Please try again."
            }
        } catch { message = "Couldn’t save the label photo. Please try again." }
    }
    private func scan(_ data: Data) async {
        focusedInput = nil
        guard let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85), jpeg.count <= 20_000_000 else {
            message = "Choose a photo under 20 MB."; return
        }
        scanning = true
        focusedInput = nil
        savedCartID = nil
        defer { scanning = false }
        // Never carry a previous item's price into an ambiguous new scan.
        amount = ""; itemName = ""; unit = "each"; imageData = nil
        do {
            let label = ShelfLabelParser.parse(try await ReceiptOCR.read(jpeg))
            itemName = label.name ?? ""
            amount = label.price.map(Money.input) ?? ""
            unit = label.unit ?? "each"
            imageData = jpeg
            message = label.price == nil ? "Price is unclear. Enter the shelf price, or save the item without a price." : "Check the scanned price before adding."
        } catch { message = "Couldn’t read the label. Enter the item or price here." }

    }
}
