import SwiftUI
import PhotosUI
import QuickLook

struct GroceryView: View {
    @Environment(LedgerStore.self) private var store
    @Binding var sheet: SheetRoute?
    @State private var item: GroceryItem?
    @State private var selectedDate = Date()
    @State private var adding = false
    private var items: [GroceryItem] { store.ledger.groceries.filter { Calendar.current.isDate($0.purchasedAt ?? $0.plannedAt ?? Date(), inSameDayAs: selectedDate) } }
    private var estimate: Int64 { items.filter { $0.purchasedAt == nil }.reduce(0) { $0 + ($1.estimatedUnitPrice ?? 0) * Int64($1.quantity) } }
    var body: some View {
        PaperScreen {
            HStack(alignment: .firstTextBaseline) {
                Text("Groceries").font(.largeTitle.bold())
                Spacer()
                VStack(alignment: .trailing) {
                    Text(Money.format(estimate)).font(.headline).monospacedDigit()
                    Text("Planned total").font(.caption).foregroundStyle(Ink.muted)
                }
            }
            HStack {
                Button { changeDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Previous day")
                Spacer()
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 3) {
                        Text(relativeDay(now: context.date)).font(.headline)
                        Text(selectedDate.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Ink.muted)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                        .onTapGesture(count: 2) { selectedDate = Date() }
                        .accessibilityElement(children: .combine)
                        .accessibilityHint("Double-tap the date to return to today")
                        .accessibilityAction(named: "Return to Today") { selectedDate = Date() }
                }
                Spacer()
                Button { changeDay(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Next day")
            }
            Text("Swipe left for earlier days, right for later. Double-tap the date for today.").font(.caption).foregroundStyle(Ink.muted)
            if items.isEmpty { EmptyNote(symbol: "basket", title: "Nothing planned for this day.", message: "Add an item, scan a shelf label or dictate a shopping plan.") }
            ForEach(items) { grocery in
                Button { item = grocery } label: {
                    HStack(spacing: 12) {
                        CategoryIcon(symbol: grocery.purchasedAt == nil ? "basket" : "checkmark.seal")
                        VStack(alignment: .leading, spacing: 4) {
                            Text(grocery.name).font(.headline)
                            Text("\(grocery.quantity) × \(grocery.unit) · \(grocery.purchasedAt == nil ? "Planned" : "Purchased")").font(.caption)
                            if let shop = grocery.storeName, !shop.isEmpty { Text(shop).font(.caption) }
                            if let planned = grocery.plannedAt, grocery.purchasedAt == nil { Text(planned.formatted(date: .omitted, time: .shortened)).font(.caption) }
                        }
                        Spacer()
                        if let expense = store.ledger.expenses.first(where: { $0.id == grocery.expenseID }) { Text(Money.format(expense.amount)).monospacedDigit() }
                        else if let price = grocery.estimatedUnitPrice { Text(Money.format(price * Int64(grocery.quantity))).monospacedDigit() }
                        Image(systemName: "chevron.right")
                    }.frame(minHeight: 56).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            Text("Plans never deduct money. Open an item and choose Record Purchase after buying it.").font(.footnote).foregroundStyle(Ink.muted)
        }.navigationTitle("Groceries").navigationBarTitleDisplayMode(.inline).toolbar(.hidden, for: .navigationBar).bottomAdd("Add item") { adding = true }
            .simultaneousGesture(DragGesture(minimumDistance: 60).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                changeDay(value.translation.width < 0 ? -1 : 1)
            })
            .sheet(item: $item) { grocery in NavigationStack { GroceryDetail(itemID: grocery.id) } }
            .sheet(isPresented: $adding) { NavigationStack { GroceryForm(initialDate: selectedDate, onSaved: { selectedDate = $0 }) } }
    }
    private func relativeDay(now: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: selectedDate)).day ?? 0
        if days == 0 { return "Today" }
        if days < 0 { return "\(-days) day\(days == -1 ? "" : "s") ago" }
        return "In \(days) day\(days == 1 ? "" : "s")"
    }
    private func changeDay(_ delta: Int) { selectedDate = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate)! }
}
struct GroceryForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var initialName = ""
    var initialPrice = ""
    var initialDate = Date()
    var onSaved: (Date) -> Void = { _ in }
    @State private var name = ""
    @State private var quantity = 1
    @State private var unit = "each"
    @State private var price = ""
    @State private var shop = ""
    @State private var plannedAt = Date()
    @State private var remind = false
    @State private var phrase = ""
    @State private var choosingPhoto = false
    @State private var saving = false
    @FocusState private var inputFocused: Bool
    @State private var speech = ShoppingSpeech()
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var imageData: Data?
    @State private var scanning = false
    @State private var message: String?
    @State private var recordedItem: GroceryItem?
    @State private var initialized = false
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !unit.isEmpty &&
        (price.isEmpty || (Money.cents(price) ?? 0) > 0) && !scanning && !saving && !speech.recording &&
        (!remind || plannedAt.addingTimeInterval(-3600) > Date())
    }
    var body: some View {
        Form {
            Section {
                HStack(alignment: .top) {
                    TextField("Item name", text: $name, axis: .vertical)
                        .lineLimit(2...3).focused($inputFocused).frame(minHeight: 48)
                    Button {
                        inputFocused = false; speech.stop()
                        if UIImagePickerController.isSourceTypeAvailable(.camera) { camera = true } else { choosingPhoto = true }
                    } label: { Image(systemName: "text.viewfinder").frame(width: 44, height: 44) }
                        .buttonStyle(.borderless).accessibilityLabel("Scan price label")
                        .contextMenu { Button("Choose label photo", systemImage: "photo") { inputFocused = false; choosingPhoto = true } }
                        .disabled(scanning || speech.recording)
                    Button {
                        inputFocused = false
                        if speech.recording { speech.stop(); interpret() }
                        else { Task { await speech.start(appendingTo: phrase.isEmpty ? name : phrase) } }
                    } label: { Image(systemName: speech.recording ? "stop.circle.fill" : "mic").frame(width: 44, height: 44) }
                        .buttonStyle(.borderless).accessibilityLabel(speech.recording ? "Stop dictation" : "Dictate item or shopping plan").disabled(scanning)
                }
                HStack {
                    Text("$")
                    TextField("Price (optional)", text: $price).keyboardType(.decimalPad).focused($inputFocused)
                    Picker("Quantity", selection: $quantity) { ForEach(1...99, id: \.self) { Text("\($0)").tag($0) } }
                        .pickerStyle(.menu).fixedSize().accessibilityLabel("Quantity")
                }
                TenderField("Unit or package size", text: $unit)
                TenderField("Store (optional)", text: $shop)
                DatePicker("When", selection: $plannedAt)
                Toggle("Remind me one hour before", isOn: $remind)
                if remind && plannedAt.addingTimeInterval(-3600) <= Date() {
                    Text("Choose a time more than an hour ahead, or turn the reminder off.").font(.caption).foregroundStyle(Ink.warning)
                }
                if speech.recording { Label("Listening… pause whenever you need. Tap stop when finished.", systemImage: "waveform").font(.caption) }
                if let message = speech.message { Text(message).font(.caption).foregroundStyle(Ink.warning) }
                if scanning { ProgressView("Reading label…") }
                if let message { Text(message).font(.caption).foregroundStyle(Ink.warning) }
                Button("Record Purchase") { Task { await save(purchase: true) } }.disabled(!valid || (Money.cents(price) ?? 0) <= 0)
            } footer: { Text("Add to Cart saves a plan. Record Purchase opens an expense to confirm.") }
        }.paperForm().navigationTitle("Shopping Item").navigationBarTitleDisplayMode(.inline)
            .bottomAdd("Add to Cart", enabled: valid) { Task { await save(purchase: false) } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { inputFocused = false; UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
            }
            .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
            .onAppear { guard !initialized else { return }; initialized = true; name = initialName; price = initialPrice; plannedAt = initialDate }
            .onDisappear { speech.stop() }
            .onChange(of: speech.text) { _, text in phrase = text; if !text.isEmpty { name = ShoppingPlanParser.parse(text).item } }
            .onChange(of: speech.recording) { wasRecording, recording in if wasRecording && !recording { interpret() } }
            .onChange(of: photo) { _, item in Task { do { if let data = try await item?.loadTransferable(type: Data.self) { await scan(data) } } catch { message = "Could not load photo." } } }
            .sheet(isPresented: $camera) { CameraPicker { data in Task { await scan(data) } } }
            .sheet(item: $recordedItem, onDismiss: { dismiss() }) { item in
                NavigationStack { ExpenseForm(initialAmount: Money.input((item.estimatedUnitPrice ?? 0) * Int64(item.quantity)), initialCategory: store.ledger.categories.first(where: { $0.name == "Groceries" })?.id, initialMerchant: item.storeName?.isEmpty == false ? item.storeName! : item.name, groceryID: item.id) }
            }
    }
    private func interpret() {
        if !speech.text.isEmpty { phrase = speech.text }
        guard !phrase.isEmpty else { return }
        let draft = ShoppingPlanParser.parse(phrase)
        name = draft.item
        if !draft.store.isEmpty { shop = draft.store }
        if draft.hasExplicitDate { plannedAt = draft.date }
        else if draft.hasExplicitTime {
            let calendar = Calendar.current
            plannedAt = calendar.date(bySettingHour: calendar.component(.hour, from: draft.date), minute: calendar.component(.minute, from: draft.date), second: 0, of: plannedAt) ?? plannedAt
        }
        if draft.hasExplicitTime { remind = plannedAt.addingTimeInterval(-3600) > Date() }
    }
    private func scan(_ data: Data) async {
        guard let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.85), jpeg.count <= 20_000_000 else { message = "Choose a photo under 20 MB."; return }
        scanning = true; defer { scanning = false }; imageData = jpeg; price = ""; name = ""; unit = "each"
        do {
            let label = ShelfLabelParser.parse(try await ReceiptOCR.read(jpeg))
            if let value = label.name { name = value }
            if let value = label.price { price = Money.input(value) }
            if let value = label.unit { unit = value }
            message = label.price == nil ? "Price is unclear or there are multiple offers. Enter the applicable unit price." : "Review the detected name, package size and price. Member offers may have conditions."
        } catch { message = "Label could not be read. You can enter the details manually." }
    }
    private func save(purchase: Bool) async {
        guard valid else { message = "Enter an item, a valid optional price, and a future reminder time."; return }
        saving = true; inputFocused = false
        defer { saving = false }
        if remind && !purchase { guard await store.enableReminders() else { return } }
        var file: String?
        do { if let imageData, Money.cents(price) != nil { file = try store.attach(imageData, extension: "jpg") } }
        catch { message = "Photo could not be saved."; return }
        let observations = Money.cents(price).map { [PriceObservation(price: $0, store: shop, photo: file)] } ?? []
        let item = GroceryItem(name: name.trimmingCharacters(in: .whitespacesAndNewlines), quantity: quantity, unit: unit, observations: observations, plannedAt: plannedAt, storeName: shop, remind: !purchase && remind)
        if store.update({ $0.groceries.append(item) }) {
            onSaved(item.plannedAt ?? plannedAt)
            await store.refreshReminders()
            if purchase { recordedItem = item } else { dismiss() }
        } else if let file { try? FileManager.default.removeItem(at: store.attachmentURL(file)) }
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
    @State private var savedPrice = false
    @State private var purchase = false
    @State private var discard = false
    @State private var editingPlan = false
    @FocusState private var inputFocused: Bool
    private var hasDraft: Bool { !price.isEmpty || !shop.isEmpty || imageData != nil }
    private var item: GroceryItem? { store.ledger.groceries.first { $0.id == itemID } }
    var body: some View {
        Form {
            if let item {
                Section("Shopping plan") {
                    if let date = item.purchasedAt { Text("Purchased \(date.formatted(date: .abbreviated, time: .shortened))") }
                    else {
                        Button("Edit Shopping Plan") { editingPlan = true }
                        DatePicker("Planned for", selection: Binding(get: { self.item?.plannedAt ?? Date() }, set: { value in
                            _ = store.update { ledger in if let i = ledger.groceries.firstIndex(where: { $0.id == itemID }) { ledger.groceries[i].plannedAt = value } }
                            Task { await store.refreshReminders() }
                        }))
                        Button("Record Purchase") { purchase = true }.disabled(item.estimatedUnitPrice == nil)
                    }
                    if let shop = item.storeName, !shop.isEmpty { LabeledContent("Store", value: shop) }
                }
                Section("Estimate") { LabeledContent("Per \(item.unit)", value: item.estimatedUnitPrice.map { Money.format($0) } ?? "No prices yet"); Stepper("Quantity: \(item.quantity)", value: Binding(get: { self.item?.quantity ?? 1 }, set: { value in _ = store.update { ledger in if let i = ledger.groceries.firstIndex(where: { $0.id == itemID }) { ledger.groceries[i].quantity = value } } }), in: 1...99) }
                Section {
                    TenderField("Store (optional)", text: $shop).focused($inputFocused)
                    TenderField("Price per \(item.unit) (USD)", text: $price).keyboardType(.decimalPad).focused($inputFocused)
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choose Price Photo", systemImage: "photo") }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) { Button { camera = true } label: { Label("Photograph Shelf Price", systemImage: "camera") } }
                    if reading { ProgressView("Reading label…") }
                    if imageData != nil { Label("Photo attached", systemImage: "checkmark.circle") }
                    if !ocr.isEmpty { Text(ocr).font(.caption).textSelection(.enabled) }
                    if !price.isEmpty && (Money.cents(price) ?? 0) <= 0 { Text("Enter a price greater than zero, like 3.49, with up to two decimal places.").font(.caption).foregroundStyle(Ink.warning) }
                    Button("Save Price Observation") { save() }.disabled((Money.cents(price) ?? 0) <= 0 || reading)
                    if savedPrice { Label("Price saved", systemImage: "checkmark.circle.fill").foregroundStyle(Ink.green).accessibilityIdentifier("grocery-price-saved") }
                } header: { Text("Collect a price") } footer: { Text("Enter the price per unit to save. Store and photo are optional. Review any photo text before entering a price; OCR can misread shelf labels.") }
                Section("Price history") {
                    ForEach(item.observations.sorted { $0.date > $1.date }) { observation in
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(observation.store.isEmpty ? "Store not specified" : observation.store, value: Money.format(observation.price))
                            Text(observation.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            if let file = observation.photo { Button("View Price Photo") { let url = store.attachmentURL(file); if FileManager.default.fileExists(atPath: url.path) { preview = url } else { store.error = "This price photo isn’t on this device. Restore a complete backup containing this photo." } } }
                        }
                    }
                }
                Section { Button("Delete Item", role: .destructive) { deleting = true } }
            }
        }.paperForm().navigationTitle(item?.name ?? "Grocery Item").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { if hasDraft { Button("Close") { discard = true } } }
                ToolbarItem(placement: .confirmationAction) {
                    if hasDraft { Button("Save Price") { save() }.disabled((Money.cents(price) ?? 0) <= 0 || reading) }
                    else { Button("Done") { dismiss() } }
                }
            }
            .confirmationDialog("Discard this unsaved price?", isPresented: $discard, titleVisibility: .visible) { Button("Discard", role: .destructive) { dismiss() }; Button("Keep Editing", role: .cancel) {} }
            .onChange(of: price) { _, newValue in if !newValue.isEmpty { savedPrice = false } }
            .onChange(of: photo) { _, item in Task { do { if let data = try await item?.loadTransferable(type: Data.self) { await scan(data) } } catch { ocr = "Couldn’t load this image." } } }
            .sheet(isPresented: $camera) { CameraPicker { data in Task { await scan(data) } } }
            .quickLookPreview($preview)
            .sheet(isPresented: $editingPlan) { if let item { NavigationStack { GroceryPlanEditor(item: item) } } }
            .sheet(isPresented: $purchase) { if let item { NavigationStack { ExpenseForm(initialAmount: Money.input((item.estimatedUnitPrice ?? 0) * Int64(item.quantity)), initialCategory: store.ledger.categories.first(where: { $0.name == "Groceries" })?.id, initialMerchant: item.storeName?.isEmpty == false ? item.storeName! : item.name, groceryID: item.id) } } }
            .confirmationDialog("Delete this item and its price history?", isPresented: $deleting, titleVisibility: .visible) { Button("Delete", role: .destructive) { if store.update({ $0.groceries.removeAll { $0.id == itemID } }) { Task { await store.refreshReminders() }; dismiss() } } }
    }
    private func scan(_ data: Data) async {
        guard let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.8), jpeg.count <= 20_000_000 else { ocr = "Choose a supported photo under 20 MB."; return }
        imageData = jpeg; reading = true
        defer { reading = false }
        do {
            let label = ShelfLabelParser.parse(try await ReceiptOCR.read(jpeg))
            if let value = label.price { price = Money.input(value) }
            ocr = "Detected: " + (label.name ?? "Unknown item") + " · " + (label.unit ?? "Unknown package size") + ". Review the price above."
        }
        catch { ocr = "Text couldn’t be read. Enter the price above." }
    }
    private func save() {
        guard let cents = Money.cents(price), cents > 0 else { return }
        do {
            let file = try imageData.map { try store.attach($0, extension: "jpg") }
            if store.update({ ledger in if let i = ledger.groceries.firstIndex(where: { $0.id == itemID }) { ledger.groceries[i].observations.append(PriceObservation(price: cents, store: shop.trimmingCharacters(in: .whitespacesAndNewlines), photo: file)) } }) { price = ""; shop = ""; imageData = nil; ocr = ""; photo = nil; savedPrice = true; inputFocused = false }
            else if let file { try? FileManager.default.removeItem(at: store.attachmentURL(file)) }
        } catch { store.error = "Couldn’t save this photo. Check storage and try again." }
    }
}
