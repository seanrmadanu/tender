import SwiftUI
import PhotosUI
import QuickLook

struct GroceryView: View {
    @Environment(LedgerStore.self) private var store
    @Binding var sheet: SheetRoute?
    @State private var item: GroceryItem?
    private var estimate: Int64 { store.ledger.groceries.filter { !$0.checked }.reduce(0) { $0 + ($1.estimatedUnitPrice ?? 0) * Int64($1.quantity) } }
    var body: some View {
        PaperScreen {
            SectionHeading(title: "A better kind of list.", subtitle: "Collect prices today. Plan smarter next time.")
            PaperCard {
                Text("ESTIMATED BASKET").font(.system(.caption, design: .monospaced)).tracking(1.5).foregroundStyle(Ink.muted)
                Text(Money.format(estimate)).font(.system(.largeTitle, design: .serif))
                Text("Unchecked items · average of up to 5 recent prices per item").font(.caption).foregroundStyle(Ink.muted)
                if store.ledger.groceries.contains(where: { !$0.checked && $0.estimatedUnitPrice == nil }) { Label("Some items have no price and aren’t included", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Ink.warning) }
            }
            if store.ledger.groceries.isEmpty { EmptyNote(symbol: "basket", title: "What’s on your list?", message: "Add an item, then photograph a shelf label to start collecting prices.") }
            ForEach(store.ledger.groceries) { grocery in
                HStack(spacing: 12) {
                    Button { _ = store.update { ledger in if let i = ledger.groceries.firstIndex(where: { $0.id == grocery.id }) { ledger.groceries[i].checked.toggle() } } } label: { Image(systemName: grocery.checked ? "checkmark.circle.fill" : "circle").font(.title2).frame(width: 44, height: 44) }.accessibilityLabel(grocery.checked ? "Uncheck \(grocery.name)" : "Check off \(grocery.name)")
                    Button { item = grocery } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) { Text(grocery.name).font(.headline).strikethrough(grocery.checked); Text("\(grocery.quantity) × \(grocery.unit) · \(grocery.observations.count) prices").font(.caption).foregroundStyle(Ink.muted) }
                            Spacer()
                            if let price = grocery.estimatedUnitPrice { Text(Money.format(price * Int64(grocery.quantity))).font(.subheadline.weight(.semibold)) } else { Text("Add price").font(.caption) }
                            Image(systemName: "chevron.right").font(.caption)
                        }.frame(minHeight: 50).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.opacity(grocery.checked ? 0.65 : 1)
            }
            Text("Estimates use your own observations. Package sizes, quantities, promotions, and sales tax can change checkout totals. Checking an item does not record an expense.").font(.footnote).foregroundStyle(Ink.muted)
        }.navigationTitle("Groceries").toolbar { Button { sheet = .grocery } label: { Label("Add grocery item", systemImage: "plus") } }
            .sheet(item: $item) { grocery in NavigationStack { GroceryDetail(itemID: grocery.id) } }
    }
}
struct GroceryForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var quantity = 1
    @State private var unit = "each"
    var body: some View {
        Form {
            Section("Item") { TextField("Name", text: $name); Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99); TextField("Unit (each, carton, lb…)", text: $unit) }
            Text("Use the same package size and unit when collecting prices for this item.").font(.footnote).foregroundStyle(.secondary)
        }.paperForm().navigationTitle("Add Grocery Item").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Add") { if store.update({ $0.groceries.append(GroceryItem(name: name, quantity: quantity, unit: unit)) }) { dismiss() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || unit.trimmingCharacters(in: .whitespaces).isEmpty) } }
    }
}
struct GroceryDetail: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let itemID: UUID
    @State private var price = ""
    @State private var shop = ""
    @State private var photo: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var ocr = ""
    @State private var reading = false
    @State private var camera = false
    @State private var preview: URL?
    @State private var deleting = false
    private var item: GroceryItem? { store.ledger.groceries.first { $0.id == itemID } }
    var body: some View {
        Form {
            if let item {
                Section("Estimate") { LabeledContent("Per \(item.unit)", value: item.estimatedUnitPrice.map { Money.format($0) } ?? "No prices yet"); Stepper("Quantity: \(item.quantity)", value: Binding(get: { self.item?.quantity ?? 1 }, set: { value in _ = store.update { ledger in if let i = ledger.groceries.firstIndex(where: { $0.id == itemID }) { ledger.groceries[i].quantity = value } } }), in: 1...99) }
                Section {
                    TextField("Store", text: $shop)
                    TextField("Price per \(item.unit) (USD)", text: $price).keyboardType(.decimalPad)
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choose Price Photo", systemImage: "photo") }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button { camera = true } label: { Label("Photograph Shelf Price", systemImage: "camera") } }
                    if reading { ProgressView("Reading label…") }
                    if imageData != nil { Label("Photo attached", systemImage: "checkmark.circle") }
                    if !ocr.isEmpty { Text(ocr).font(.caption).textSelection(.enabled) }
                    Button("Save Price Observation") { save() }.disabled((Money.cents(price) ?? 0) <= 0 || shop.trimmingCharacters(in: .whitespaces).isEmpty || reading)
                } header: { Text("Collect a price") } footer: { Text("Review the photo text and type the correct price per unit. OCR can misread shelf labels.") }
                Section("Price history") {
                    ForEach(item.observations.sorted { $0.date > $1.date }) { observation in
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(observation.store, value: Money.format(observation.price))
                            Text(observation.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            if let file = observation.photo { Button("View Price Photo") { let url = store.attachmentURL(file); if FileManager.default.fileExists(atPath: url.path) { preview = url } else { store.error = "This price photo isn’t on this device. Restore a complete backup containing this photo." } } }
                        }
                    }
                }
                Section { Button("Delete Item", role: .destructive) { deleting = true } }
            }
        }.paperForm().navigationTitle(item?.name ?? "Grocery Item").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
            .onChange(of: photo) { _, item in Task { do { if let data = try await item?.loadTransferable(type: Data.self) { await scan(data) } } catch { ocr = "Couldn’t load this image." } } }
            .sheet(isPresented: $camera) { CameraPicker { data in Task { await scan(data) } } }
            .quickLookPreview($preview)
            .confirmationDialog("Delete this item and its price history?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete", role: .destructive) { if store.update({ $0.groceries.removeAll { $0.id == itemID } }) { dismiss() } } }
    }
    private func scan(_ data: Data) async {
        guard let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.8), jpeg.count <= 20_000_000 else { ocr = "Choose a supported photo under 20 MB."; return }
        imageData = jpeg; reading = true
        defer { reading = false }
        do { let text = try await ReceiptOCR.read(jpeg); ocr = text.isEmpty ? "No text found. Enter the price above." : "Review label text:\n" + text }
        catch { ocr = "Text couldn’t be read. Enter the price above." }
    }
    private func save() {
        guard let cents = Money.cents(price) else { return }
        do {
            let file = try imageData.map { try store.attach($0, extension: "jpg") }
            if store.update({ ledger in if let i = ledger.groceries.firstIndex(where: { $0.id == itemID }) { ledger.groceries[i].observations.append(PriceObservation(price: cents, store: shop, photo: file)) } }) { price = ""; shop = ""; imageData = nil; ocr = ""; photo = nil }
            else if let file { try? FileManager.default.removeItem(at: store.attachmentURL(file)) }
        } catch { store.error = "Couldn’t save this photo. Check storage and try again." }
    }
}
