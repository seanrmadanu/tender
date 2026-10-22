import SwiftUI
import PhotosUI

struct BudgetView: View {
    @Environment(LedgerStore.self) private var store
    @State private var editing: BudgetCategory?
    @State private var adding = false
    @State private var selecting = false
    @State private var selected = Set<UUID>()
    @State private var deleting = false
    var body: some View {
        PaperScreen {
            SectionHeading(title: "Give your money a purpose.", subtitle: "Monthly envelopes · \(Date().formatted(.dateTime.month(.wide)))")
            PaperCard { AmountRow(label: "Total monthly allocation", amount: store.ledger.monthlyBudget); AmountRow(label: "Remaining this month", amount: store.ledger.monthlyBudget - store.ledger.spent(in: store.ledger.month())) }
            ForEach(store.ledger.categories) { category in
                Button {
                    if selecting {
                        if selected.contains(category.id) { selected.remove(category.id) } else { selected.insert(category.id) }
                    } else { editing = category }
                } label: {
                    PaperCard {
                        HStack { CategoryIcon(symbol: category.symbol); Text(category.name).font(.headline); Spacer(); Image(systemName: selecting ? (selected.contains(category.id) ? "checkmark.circle.fill" : "circle") : "pencil").font(.title3) }
                        AmountRow(label: "Remaining", amount: store.ledger.remaining(category))
                        BudgetMeter(spent: store.ledger.spent(category: category.id, in: store.ledger.month()), limit: category.limit)
                        Text("\(Money.format(store.ledger.spent(category: category.id, in: store.ledger.month()))) spent / \(Money.format(category.limit)) allocated").font(.caption).foregroundStyle(Ink.muted)
                    }
                }.buttonStyle(.plain)
                if !selecting { NavigationLink {
                    CategoryReviewView(categoryID: category.id, interval: store.ledger.month())
                } label: {
                    Label("Review \(category.name) expenses & bills", systemImage: "receipt").font(.subheadline).frame(minHeight: 44)
                } }
            }
            Text("Budgets reset by calendar month. Unspent allocations don’t roll over. Adding an expense always uses your chosen category.").font(.footnote).foregroundStyle(Ink.muted)
        }.navigationTitle("Budgets")
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button(selecting ? "Done" : "Edit") { selecting.toggle(); selected.removeAll() }
            } }
            .safeAreaInset(edge: .bottom) {
                if selecting {
                    HStack {
                        Text("\(selected.count) selected").font(.subheadline)
                        Spacer()
                        Button("Edit", systemImage: "pencil") {
                            editing = store.ledger.categories.first { selected.contains($0.id) }
                        }.disabled(selected.count != 1)
                        Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }.disabled(selected.isEmpty)
                    }.padding().background(Ink.paper)
                } else {
                    HStack { Spacer(); Button("Add category", systemImage: "plus") { adding = true }.buttonStyle(.borderedProminent) }.padding()
                }
            }
            .confirmationDialog("Delete \(selected.count) categories?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete Categories", role: .destructive) {
                    if store.update({ $0.removeCategories(selected) }) { selected.removeAll(); selecting = false }
                }
            } message: { Text("Purchases and recurring payments are kept under Uncategorized. Only the selected budgets are removed.") }
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
            Section("Envelope") { TenderField("Category name", text: $name); TenderField("Monthly allocation (USD)", text: $amount).keyboardType(.decimalPad); Picker("Icon", selection: $symbol) { ForEach(symbols, id: \.self) { Label($0, systemImage: $0).tag($0) } } }
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
                        if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true }
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
            TextField("0.00", text: $amount).keyboardType(.decimalPad)
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
