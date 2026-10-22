import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import ImageIO

struct ActivityView: View {
    @Environment(LedgerStore.self) private var store
    @Binding var sheet: SheetRoute?
    @State private var section = 0
    @State private var selected: Expense?
    @State private var categoryID: UUID?
    @State private var billsOnly = false
    @State private var thisMonth = true
    @State private var search = ""
    private var filtered: [Expense] {
        let interval = thisMonth ? store.ledger.month() : nil
        return store.ledger.expenses.filter { e in
            (categoryID == nil || e.categoryID == categoryID) && (!billsOnly || e.attachment != nil) &&
            (interval == nil || (e.date >= interval!.start && e.date < interval!.end)) &&
            (search.isEmpty || e.merchant.localizedCaseInsensitiveContains(search) || e.note.localizedCaseInsensitiveContains(search))
        }.sorted { $0.date > $1.date }
    }
    var body: some View {
        PaperScreen {
            NavigationLink { ReportView() } label: { Label("Reports", systemImage: "chart.xyaxis.line") }
            NavigationLink { BankActivityView() } label: { Label("Bank Activity", systemImage: "building.columns") }
            Picker("Activity type", selection: $section) { Text("Expenses").tag(0); Text("Recurring").tag(1) }.pickerStyle(.segmented)
            if section == 0 {
                SectionHeading(title: "The everyday details.", subtitle: "Your expenses, with their paper trail.")
                PaperCard {
                    Picker("Category", selection: $categoryID) {
                        Text("All categories").tag(UUID?.none)
                        ForEach(store.ledger.categories) { Text($0.name).tag(Optional($0.id)) }
                    }.pickerStyle(.menu)
                    Toggle("This month only", isOn: $thisMonth)
                    Toggle("With bills attached", isOn: $billsOnly)
                    Divider().overlay(Ink.line)
                    AmountRow(label: "\(filtered.count) matching expenses", amount: filtered.reduce(0) { $0 + $1.amount })
                }
                if filtered.isEmpty { EmptyNote(symbol: "receipt", title: "No matching entries.", message: "Add an expense, or adjust your search and filters.") }
                ForEach(filtered) { e in
                    Button { selected = e } label: { ExpenseListRow(expense: e) }.buttonStyle(.plain)
                }
            } else { RecurringList() }
        }.navigationTitle("Activity")
            .searchable(text: $search, prompt: "Merchant or bill text")
            .bottomAdd(section == 0 ? "Add expense" : "Add recurring payment") { sheet = section == 0 ? .expense : .recurring }
            .sheet(item: $selected) { e in NavigationStack { ExpenseDetail(expense: e) } }
    }
}

struct ExpenseListRow: View {
    @Environment(LedgerStore.self) private var store
    let expense: Expense
    private var category: BudgetCategory? { store.ledger.categories.first { $0.id == expense.categoryID } }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(symbol: category?.symbol ?? "tag")
            VStack(alignment: .leading, spacing: 5) {
                Text(expense.merchant).font(.subheadline.weight(.semibold))
                Text("\(category?.name ?? "Unknown") · \(expense.date.formatted(.dateTime.month(.abbreviated).day()))").font(.caption).foregroundStyle(Ink.muted)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 5) {
                Text("−\(Money.format(expense.amount))").font(.subheadline.weight(.semibold)).monospacedDigit().fixedSize()
                if expense.attachment != nil { Image(systemName: "paperclip").font(.caption).accessibilityLabel("Bill attached") }
            }
        }.padding(.vertical, 6).frame(minHeight: 44).contentShape(Rectangle())
    }
}

struct CategoryReviewView: View {
    @Environment(LedgerStore.self) private var store
    var categoryID: UUID
    var interval: DateInterval
    @State private var selected: Expense?
    @State private var billsOnly = false
    private var category: BudgetCategory? { store.ledger.categories.first { $0.id == categoryID } }
    private var expenses: [Expense] {
        store.ledger.expenses.filter { $0.categoryID == categoryID && $0.date >= interval.start && $0.date < interval.end }.sorted { $0.date > $1.date }
    }
    var body: some View {
        PaperScreen {
            SectionHeading(title: "Follow the paper trail.", subtitle: "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(min(interval.end.addingTimeInterval(-1), Date()).formatted(date: .abbreviated, time: .omitted))")
            PaperCard {
                AmountRow(label: "Spent in this period", amount: expenses.reduce(0) { $0 + $1.amount })
                Text("\(expenses.count) expenses · \(expenses.filter { $0.attachment != nil }.count) attached bills").font(.caption).foregroundStyle(Ink.muted)
                Toggle("Show attached bills only", isOn: $billsOnly)
            }
            if expenses.filter({ !billsOnly || $0.attachment != nil }).isEmpty {
                EmptyNote(symbol: "receipt", title: "No bills to review yet.", message: "Attach a receipt when adding an expense, or turn off the bill filter.")
            }
            ForEach(expenses.filter { !billsOnly || $0.attachment != nil }) { expense in
                Button { selected = expense } label: { ExpenseListRow(expense: expense) }.buttonStyle(.plain)
            }
        }.navigationTitle(category?.name ?? "Category").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { expense in NavigationStack { ExpenseDetail(expense: expense) } }
    }
}
struct ExpenseForm: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var initialAmount: String = ""
    var initialCategory: UUID? = nil
    var initialAccount: UUID? = nil
    var initialMerchant: String = ""
    var groceryID: UUID? = nil
    @State private var cash = false
    @State private var cashAccount: UUID?
    @State private var receipt = ReceiptDetails()
    @State private var hasReceipt = false
    @State private var initialized = false
    @State private var merchant = ""
    @State private var amount = ""
    @State private var category: UUID?
    @State private var account: UUID?
    @State private var date = Date()
    @State private var note = ""
    @State private var deductFromBalance = true
    @State private var photo: PhotosPickerItem?
    @State private var attachment: Data?
    @State private var attachmentExt = "jpg"
    @State private var imported = false
    @State private var camera = false
    @State private var reading = false
    @State private var readError: String?
    private var valid: Bool { !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (Money.cents(amount) ?? 0) > 0 && category != nil && (cash || account != nil) && !reading }
    var body: some View {
        Form {

            Section("Expense") {
                TenderField("Merchant or description", text: $merchant)
                TenderField("Amount (USD)", text: $amount).keyboardType(.decimalPad)
                Picker("Category", selection: $category) { Text("Choose").tag(UUID?.none); ForEach(store.ledger.categories) { Text($0.name).tag(Optional($0.id)) } }
                Toggle("Paid with cash", isOn: $cash)
                if !cash { Picker("Paid from", selection: $account) { Text("Choose").tag(UUID?.none); ForEach(store.ledger.accounts.filter { $0.isCash != true }) { Text($0.name).tag(Optional($0.id)) } } }
                if cash {
                    if store.ledger.accounts.contains(where: { $0.isCash == true }) {
                        Picker("Cash wallet", selection: $cashAccount) { ForEach(store.ledger.accounts.filter { $0.isCash == true }) { Text($0.name).tag(Optional($0.id)) } }
                    } else { Text("A cash wallet will be created with a zero opening balance. Set the amount you actually hold in Settings → Accounts.").font(.footnote) }
                }
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                TenderField("Notes", text: $note, axis: .vertical)
            }
            Section { Toggle("Deduct from current balance", isOn: $deductFromBalance) } footer: { Text("Leave this off for a purchase already reflected in a bank balance. Cash purchases deduct only from your cash wallet; set its opening balance in Settings → Accounts.") }
            if hasReceipt { ReceiptSummary(details: $receipt) }
            Section {
                PhotosPicker(selection: $photo, matching: .images) { Label("Choose Bill Photo", systemImage: "photo") }
                if UIImagePickerController.isSourceTypeAvailable(.camera) { Button { camera = true } label: { Label("Photograph Bill", systemImage: "camera") } }
                Button { imported = true } label: { Label("Attach PDF or Image", systemImage: "doc.badge.plus") }
                if reading { ProgressView("Reading bill on device…") }
                if attachment != nil { Label("Bill attached (\(attachmentExt.uppercased()))", systemImage: "checkmark.circle"); Button("Remove Attachment", role: .destructive) { attachment = nil; receipt = ReceiptDetails(); hasReceipt = false } }
                if let readError { Text(readError).foregroundStyle(Ink.warning) }
            } header: { Text("Paper trail") } footer: { Text("Photos prefill recognized details for review. Check the total, date and payment method before saving. The receipt image is retained; PDFs are retained as attachments. Recognition runs on device.") }
        }.paperForm().navigationTitle("Add Expense").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!valid) } }
            .onAppear { guard !initialized else { return }; initialized = true; amount = initialAmount; merchant = initialMerchant; category = initialCategory; account = initialAccount ?? store.ledger.accounts.first(where: { $0.isCash != true })?.id; cash = store.ledger.accounts.first(where: { $0.id == initialAccount })?.isCash == true; cashAccount = cash ? initialAccount : store.ledger.accounts.first(where: { $0.isCash == true })?.id; deductFromBalance = cash || store.ledger.accounts.first(where: { $0.id == account })?.bankAccountKey == nil }
            .onChange(of: account) { _, id in deductFromBalance = store.ledger.accounts.first(where: { $0.id == id })?.bankAccountKey == nil }
            .onChange(of: cash) { _, value in deductFromBalance = value || store.ledger.accounts.first(where: { $0.id == account })?.bankAccountKey == nil }
            .onChange(of: photo) { _, item in Task { do { if let data = try await item?.loadTransferable(type: Data.self) { await handlePhoto(data) } } catch { readError = "Couldn’t load this photo. Choose another image." } } }
            .fileImporter(isPresented: $imported, allowedContentTypes: [.pdf, .image]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let data = try Data(contentsOf: url)
                    guard data.count <= 20_000_000 else { readError = "Choose a bill under 20 MB."; return }
                    if url.pathExtension.lowercased() == "pdf" { attachment = data; attachmentExt = "pdf"; receipt = ReceiptDetails(); hasReceipt = false }
                    else { Task { await handlePhoto(data) } }
                } catch { readError = "Couldn’t open this bill. Try choosing it again." }
            }
            .sheet(isPresented: $camera) { CameraPicker { data in Task { await handlePhoto(data) } } }
    }
    private func handlePhoto(_ data: Data) async {
        guard data.count <= 20_000_000, UIImage(data: data) != nil else { readError = "Choose a supported photo under 20 MB."; return }
        attachment = data
        receipt = ReceiptDetails(); hasReceipt = false
        if let source = CGImageSourceCreateWithData(data as CFData, nil), let type = CGImageSourceGetType(source) { attachmentExt = UTType(type as String)?.preferredFilenameExtension ?? "jpg" }
        else { attachmentExt = "jpg" }; reading = true; readError = nil
        defer { reading = false }
        do {
            let text = try await ReceiptOCR.read(data)
            receipt = ReceiptParser.parse(text); hasReceipt = true
            if let value = receipt.merchant { merchant = value }
            if let value = receipt.total { amount = Money.input(value) }
            if let value = receipt.date, value <= Date() { date = value }
            if let payment = receipt.payment { cash = payment.lowercased().hasPrefix("cash") }
            if text.isEmpty { readError = "No text found. Enter the details manually; your image is attached." }
        }
        catch { readError = "Text couldn’t be read. Your photo is still attached." }
    }
    private func save() {
        guard valid, let cents = Money.cents(amount), let category else { return }
        var file: String?
        do { if let attachment { file = try store.attach(attachment, extension: attachmentExt) } }
        catch { readError = "Couldn’t save the attachment. Free storage and try again."; return }
        if store.update({ ledger in
            if let groceryID, ledger.groceries.first(where: { $0.id == groceryID })?.expenseID != nil { throw LedgerError.invalidExpense }
            let paidFrom: UUID
            if cash {
                if let wallet = ledger.accounts.first(where: { $0.isCash == true && ($0.id == cashAccount || cashAccount == nil) }) { paidFrom = wallet.id }
                else { let wallet = Account(name: "Cash wallet", available: 0, isCash: true); ledger.accounts.append(wallet); paidFrom = wallet.id }
            } else { guard let account else { throw LedgerError.invalidExpense }; paidFrom = account }
            var reviewedReceipt = receipt; reviewedReceipt.merchant = merchant; reviewedReceipt.total = cents; reviewedReceipt.date = date
            if cash { reviewedReceipt.payment = "Cash" }
            let expense = Expense(merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines), amount: cents, categoryID: category, accountID: paidFrom, date: date, note: note, attachment: file, receipt: hasReceipt ? reviewedReceipt : nil)
            try ledger.record(expense, deductFromBalance: deductFromBalance)
            if let groceryID, let i = ledger.groceries.firstIndex(where: { $0.id == groceryID }) {
                ledger.groceries[i].expenseID = expense.id; ledger.groceries[i].purchasedAt = date; ledger.groceries[i].checked = true; ledger.groceries[i].remind = false
            }
        }) { Task { await store.refreshReminders() }; dismiss() }
        else if let file { try? FileManager.default.removeItem(at: store.attachmentURL(file)) }
    }
}
struct ExpenseDetail: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var expense: Expense
    @State private var category: UUID?
    @State private var preview: URL?
    @State private var deleting = false
    var body: some View {
        Form {
            Section { LabeledContent("Merchant", value: expense.merchant); LabeledContent("Amount", value: Money.format(expense.amount)); LabeledContent("Date", value: expense.date.formatted(date: .abbreviated, time: .omitted)); LabeledContent("Account", value: store.ledger.accounts.first { $0.id == expense.accountID }?.name ?? "Unknown") }
            Section("Category") { Picker("Envelope", selection: $category) { ForEach(store.ledger.categories) { Text($0.name).tag(Optional($0.id)) } }; Button("Save Category") { if store.update({ ledger in if let i = ledger.expenses.firstIndex(where: { $0.id == expense.id }), let category { ledger.expenses[i].categoryID = category } }) { dismiss() } } }
            if let receipt = expense.receipt { ReceiptSummary(details: .constant(receipt), editable: false) }
            if !expense.note.isEmpty { Section("Notes & extracted text") { Text(expense.note).textSelection(.enabled) } }
            if let attachment = expense.attachment { Section("Bill") { Button("View Attached Bill") {
                let url = store.attachmentURL(attachment)
                if FileManager.default.fileExists(atPath: url.path) { preview = url } else { store.error = "This bill image isn’t on this device. Restore a complete backup that includes this attachment. Ledger-only exports do not include images." }
            } } }
            Section { Button("Delete Expense", role: .destructive) { deleting = true } } footer: { Text("Deleting reverses a balance deduction only if you haven’t replaced that account’s balance snapshot since recording it.") }
        }.paperForm().navigationTitle("Expense").navigationBarTitleDisplayMode(.inline).onAppear { category = expense.categoryID }
            .toolbar { Button("Done") { dismiss() } }.quickLookPreview($preview)
            .confirmationDialog("Delete this expense? Any still-applicable cash deduction will be reversed.", isPresented: $deleting, titleVisibility: .visible) { Button("Delete Expense", role: .destructive) {
                if store.update({ $0.removeExpense(id: expense.id) }) { dismiss() }
            } }
    }
}
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    var onCapture: (Data) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController { let vc = UIImagePickerController(); vc.sourceType = .camera; vc.delegate = context.coordinator; return vc }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.8) { parent.onCapture(data) }; parent.dismiss() }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct ReceiptSummary: View {
    @Binding var details: ReceiptDetails
    var editable = true
    @State private var editing: ReceiptLine?
    var body: some View {
        Section("Recognized receipt · review") {
            if editable {
                TenderField("Payment details (type and last four only)", text: Binding(get: { details.payment ?? "" }, set: { details.payment = $0 }))
            } else if let payment = details.payment { LabeledContent("Payment", value: payment) }
            LabeledContent("Recognized item count", value: "\(details.itemCount)")
            ForEach(details.items) { item in
                Button { if editable { editing = item } } label: {
                    HStack { Text("\(item.quantity) × \(item.name)"); Spacer(); Text(Money.format(item.total)).monospacedDigit(); if editable { Image(systemName: "pencil") } }
                }.buttonStyle(.plain)
            }
            Text("OCR may miss items, quantities, discounts or tax. Tap an item to correct it before saving. The expense total above is the amount recorded; line items are a reference, not a second deduction.").font(.footnote).foregroundStyle(.secondary)
        }.sheet(item: $editing) { line in
            NavigationStack { ReceiptLineEditor(line: line) { replacement in
                if let index = details.items.firstIndex(where: { $0.id == replacement.id }) { details.items[index] = replacement }
            } }
        }
    }
}
struct ReceiptLineEditor: View {
    @Environment(\.dismiss) private var dismiss
    let line: ReceiptLine
    var save: (ReceiptLine) -> Void
    @State private var name = ""
    @State private var price = ""
    @State private var quantity = 1
    var body: some View {
        Form {
            TenderField("Item", text: $name)
            Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
            TenderField("Line total (USD)", text: $price).keyboardType(.decimalPad)
        }.paperForm().navigationTitle("Receipt Item")
            .onAppear { name = line.name; price = Money.input(line.total); quantity = line.quantity }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    guard let amount = Money.cents(price), amount > 0 else { return }
                    var copy = line; copy.name = name; copy.quantity = quantity; copy.total = amount; save(copy); dismiss()
                }.disabled(name.isEmpty || (Money.cents(price) ?? 0) <= 0) }
            }
    }
}
