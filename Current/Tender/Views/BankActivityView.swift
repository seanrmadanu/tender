import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook

struct BankActivityRow: View {
    @Environment(LedgerStore.self) private var store
    let transaction: BankTransaction
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryIcon(symbol: transaction.isTransfer ? "arrow.left.arrow.right" : "building.columns")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(transaction.merchant).font(.subheadline.weight(.semibold))
                    let expense = store.ledger.expenses.first { $0.bankTransactionID == transaction.id }
                    AssistantBadge(origin: expense?.assistantOrigin, edited: expense?.assistantLastEdit ?? store.ledger.bankTransactionDetails?[transaction.id]?.assistantLastEdit)
                }
                Text("\(transaction.displayDate) · \(transaction.pending ? "Pending" : transaction.isTransfer ? "Transfer/payment" : transaction.amountCents < 0 ? "Credit/refund" : "Posted")").font(.caption).foregroundStyle(Ink.muted)
                Text(transaction.relativeDate).font(.caption).foregroundStyle(Ink.muted)
                if store.ledger.expenses.contains(where: { $0.bankTransactionID == transaction.id }) { Label("Matched to expense", systemImage: "checkmark.circle").font(.caption) }
            }
            Spacer()
            Text(transaction.currency == "USD" ? Money.format(transaction.amountCents) : "\(transaction.amountCents) minor units · \(transaction.currency ?? "unknown currency")").font(.subheadline).monospacedDigit()
        }.frame(minHeight: 48).contentShape(Rectangle())
    }
}
struct AccountActivityRow: View {
    let entry: AccountActivityEntry
    var body: some View {
        switch entry {
        case .bank(let transaction): BankActivityRow(transaction: transaction)
        case .manual(let expense): ExpenseListRow(expense: expense)
        }
    }
}
struct BankActivityView: View {
    var accountID: UUID? = nil
    @Environment(LedgerStore.self) private var store
    @State private var selectedExpense: Expense?
    @State private var selected: BankTransaction?
    private enum DateRange: String, CaseIterable { case all = "All dates", week = "Last 7 days", month = "Last 30 days", thisMonth = "This month", custom = "Custom dates" }
    @State private var range = DateRange.all
    @State private var customDates = false
    @State private var start = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var end = Date()
    @State private var draftStart = Date()
    @State private var draftEnd = Date()
    private var transactions: [AccountActivityEntry] {
        let today = Calendar.current.startOfDay(for: Date())
        let lower: Date
        switch range {
        case .all: lower = .distantPast
        case .week: lower = Calendar.current.date(byAdding: .day, value: -6, to: today) ?? today
        case .month: lower = Calendar.current.date(byAdding: .day, value: -29, to: today) ?? today
        case .thisMonth: lower = Calendar.current.dateInterval(of: .month, for: today)?.start ?? today
        case .custom: lower = Calendar.current.startOfDay(for: start)
        }
        let upper = range == .custom ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end)) ?? .distantFuture : Date.distantFuture
        let source = accountID.map { id in store.ledger.accountActivity(for: store.ledger.accounts.first { $0.id == id }) } ?? store.ledger.activeAccounts.flatMap { store.ledger.accountActivity(for: $0) }
        return source.filter { $0.date >= lower && $0.date < upper }.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
    var body: some View {
        List {
            Section {
                if let id = accountID, let account = store.ledger.accounts.first(where: { $0.id == id }) { Label(account.name, systemImage: "creditcard").font(.headline) }
                Text("Bank imports do not deduct balances. Review posted purchases to add them to your category totals, or match a receipt you already entered. Credits, transfers and pending entries stay outside spending totals.").font(.footnote)
                Text("Showing imported bank history. Date filters apply to transactions your bank has made available.").font(.caption).foregroundStyle(Ink.muted)
                if let message = store.bankMessage { Text(message).font(.caption).foregroundStyle(Ink.warning) }
                if range == .custom { Text("\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))").font(.caption) }
            }
            if transactions.isEmpty { Text("No transactions in this date range.") }
            ForEach(transactions) { entry in
                switch entry {
                case .bank(let transaction):
                    Button { selected = transaction } label: { BankActivityRow(transaction: transaction) }.buttonStyle(.plain)
                        .accessibilityIdentifier("bank-transaction-" + transaction.id)
                case .manual(let expense):
                    Button { selectedExpense = expense } label: { ExpenseListRow(expense: expense) }.buttonStyle(.plain)
                        .accessibilityIdentifier("manual-transaction-" + expense.id.uuidString)
                }
            }
        }.paperForm().navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(DateRange.allCases, id: \.self) { option in
                            Button { if option == .custom { draftStart = start; draftEnd = end; customDates = true } else { range = option } } label: {
                                if option == range { Label(option.rawValue, systemImage: "checkmark") } else { Text(option.rawValue) }
                            }
                        }
                    } label: { Label("Date range", systemImage: "calendar") }
                }
            }
            .sheet(isPresented: $customDates) {
                NavigationStack {
                    Form {
                        DatePicker("From", selection: $draftStart, in: ...draftEnd, displayedComponents: .date)
                        DatePicker("To", selection: $draftEnd, in: draftStart...Date(), displayedComponents: .date)
                    }.navigationTitle("Transaction dates")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { customDates = false } }
                            ToolbarItem(placement: .confirmationAction) { Button("Apply") { start = draftStart; end = draftEnd; range = .custom; customDates = false } }
                        }
                }.presentationDetents([.medium])
            }
            .refreshable { await store.refreshBank(force: true) }
            .sheet(item: $selected) { t in NavigationStack { ReviewBankPurchase(transaction: t) } }
            .sheet(item: $selectedExpense) { e in NavigationStack { ExpenseDetail(expense: e) } }
    }
}
struct ReviewBankPurchase: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let transaction: BankTransaction
    @State private var category: UUID?
    @State private var match: UUID?
    @State private var fixedExpense: UUID?
    @State private var recurring = false
    private var account: Account? { store.ledger.accounts.first { $0.bankAccountKey == transaction.accountKey } }
    private var recorded: Bool { store.ledger.expenses.contains { $0.bankTransactionID == transaction.id } }
    private var candidates: [Expense] {
        store.ledger.expenses.filter { $0.accountID == account?.id && $0.bankTransactionID == nil && $0.amount == transaction.amountCents && abs($0.date.timeIntervalSince(transaction.purchaseDate ?? .distantPast)) < 4 * 86400 }
    }
    var body: some View {
        Form {
            Section {
                if let account {
                    Label(account.name, systemImage: "creditcard").font(.headline)
                    if let institution = account.bankDetails?.institutionName { Text(institution).font(.subheadline).foregroundStyle(Ink.muted) }
                } else { Label("Bank account unavailable", systemImage: "creditcard") }
                BankActivityRow(transaction: transaction)
            }
            BankTransactionDetailsEditor(transactionID: transaction.id)
            if transaction.canRecord {
                Button("Create Recurring Payment", systemImage: "repeat") { recurring = true }
            }
            if recorded {
                Text("This bank purchase is already matched to your recorded expenses.")
                if let expense = store.ledger.expenses.first(where: { $0.bankTransactionID == transaction.id }) {
                    NavigationLink("Edit envelope or fixed expense") { ExpenseDetail(expense: expense) }
                }
            }
            else if !transaction.canRecord { Text("Only posted USD purchases can become an expense. Pending entries may change; credits and transfers are shown here without increasing spending.") }
            else if account?.isArchived == true { Text("This card was removed from your wallet. Restore it in Settings → Accounts to record a new purchase.") }
            else if account == nil { Text("Import this bank account from Settings → Accounts.") }
            else {
                Section {
                    Picker("Category", selection: $category) { Text("Choose").tag(UUID?.none); ForEach(store.ledger.categories) { Text($0.name).tag(Optional($0.id)) } }
                    if !store.ledger.activeFixedExpenses.isEmpty { FixedExpensePicker(selection: $fixedExpense) }
                    if !candidates.isEmpty {
                        Picker("Receipt match", selection: $match) {
                            Text("Record as a new expense").tag(UUID?.none)
                            ForEach(candidates) { Text("\($0.merchant) · \($0.date.formatted(date: .abbreviated, time: .omitted))").tag(Optional($0.id)) }
                        }
                        Text("Possible matches have the same account and amount within four days. Choose the correct existing purchase to avoid counting it twice.").font(.footnote)
                    }
                    Button(match == nil ? "Add to Expenses" : "Match Existing Expense") {
                        guard let category else { return }
                        if store.update({ ledger in
                            try ledger.recordBankPurchase(transaction, categoryID: category, matching: match)
                            if let index = ledger.expenses.firstIndex(where: { $0.bankTransactionID == transaction.id }) { ledger.expenses[index].fixedExpenseID = fixedExpense }
                        }) { dismiss() }
                    }.disabled(category == nil)
                } header: { Text("Review") } footer: { Text("No balance deduction. Bank-created expenses follow later bank corrections; matched manual receipts retain your entered values.") }
            }
        }.paperForm().navigationTitle("Review Purchase").toolbar { Button("Done") { dismiss() } }
            .onAppear {
                if category == nil { category = store.ledger.suggestedCategory(for: transaction)?.id ?? store.ledger.exactManualMatch(for: transaction)?.categoryID }
                if match == nil { match = store.ledger.exactManualMatch(for: transaction)?.id }
            }
            .sheet(isPresented: $recurring) {
                NavigationStack { RecurringForm(suggestion: SubscriptionSuggestion(id: transaction.id, merchant: transaction.merchant,
                    amount: transaction.amountCents, cycle: .monthly,
                    nextDue: Calendar.current.date(byAdding: .month, value: 1, to: transaction.purchaseDate ?? Date()) ?? Date(), occurrences: 1)) }
            }
    }
}

struct BankTransactionDetailsEditor: View {
    @Environment(LedgerStore.self) private var store
    let transactionID: String
    @State private var note = ""
    @State private var files: [String] = []
    @State private var initialized = false
    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var importing = false
    @State private var loading = false
    @State private var preview: URL?
    @State private var message: String?
    @State private var savedNote = ""
    private var currentID: String { store.ledger.currentBankTransactionID(transactionID) }
    var body: some View {
        Section("Notes") {
            TextField("Add details about this transaction", text: $note, axis: .vertical)
                .lineLimit(3...8).accessibilityIdentifier("bank-transaction-note")
            Button("Save Note") {
                if persist(files: files) { savedNote = note; message = "Note saved." }
            }.disabled(note == savedNote || note.count > 10_000 || loading)
            if note.count > 10_000 { Text("Keep notes under 10,000 characters.").foregroundStyle(Ink.warning) }
        }.onAppear { loadDetails() }
        Section {
            ForEach(files, id: \.self) { file in
                HStack {
                    Button { preview = store.attachmentURL(file) } label: {
                        Label("View receipt \((files.firstIndex(of: file) ?? 0) + 1)", systemImage: "doc.text")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        let remaining = files.filter { $0 != file }
                        if persist(files: remaining) { files = remaining; savedNote = note; message = "Receipt detached." }
                    } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }
                        .accessibilityLabel("Detach receipt \((files.firstIndex(of: file) ?? 0) + 1)")
                }.buttonStyle(.borderless)
            }
            PhotosPicker(selection: $photo, matching: .images) { Label("Choose Receipt Photo", systemImage: "photo") }
                .disabled(loading || files.count >= 20)
            if CameraPicker.isAvailable {
                Button { camera = true } label: { Label("Take Receipt Photo", systemImage: "camera") }
                    .disabled(loading || files.count >= 20)
            }
            Button { importing = true } label: { Label("Attach Receipt PDF or Image", systemImage: "paperclip") }
                .disabled(loading || files.count >= 20)
            if loading { ProgressView("Saving receipt…") }
            if let message { Text(message).font(.footnote) }
        } header: { Text("Receipts") } footer: {
            Text("The system photo picker shares only images you select. Receipts save to this transaction without creating an expense or changing your balance. Up to 20 receipts, 20 MB each.")
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { @MainActor in
                loading = true; defer { loading = false; photo = nil }
                do { if let data = try await item.loadTransferable(type: Data.self) { attach(data, pdf: false) } }
                catch { message = "Couldn’t load this photo. Try again." }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size > 0, size <= 20_000_000 else { message = "Choose a receipt under 20 MB."; return }
                attach(try Data(contentsOf: url), pdf: url.pathExtension.lowercased() == "pdf")
            } catch { message = "Couldn’t open this receipt. Try again." }
        }
        .sheet(isPresented: $camera) { CameraPicker { data in attach(data, pdf: false) } }
        .quickLookPreview($preview)
    }
    private func loadDetails() {
        guard !initialized else { return }; initialized = true
        let details = store.ledger.bankTransactionDetails?[currentID]
        note = details?.note ?? ""; savedNote = note; files = details?.attachments ?? []
    }
    private func persist(files: [String]) -> Bool {
        let success = store.update { try $0.saveBankTransactionDetails(BankTransactionDetails(note: note, attachments: files), for: transactionID) }
        if !success { message = "Couldn’t save your changes. Try again." }
        return success
    }
    private func attach(_ data: Data, pdf: Bool) {
        guard files.count < 20, data.count <= 20_000_000, !data.isEmpty else { message = "Choose a receipt under 20 MB; up to 20 receipts per transaction."; return }
        let bytes: Data
        if pdf {
            guard data.starts(with: Data("%PDF-".utf8)) else { message = "Choose a valid PDF."; return }
            bytes = data
        } else {
            guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85), jpeg.count <= 20_000_000 else {
                message = "Choose a supported photo under 20 MB."; return
            }
            bytes = jpeg
        }
        do {
            let name = try store.attach(bytes, extension: pdf ? "pdf" : "jpg")
            let next = files + [name]
            if persist(files: next) { files = next; savedNote = note; message = "Receipt saved." }
            else { try? FileManager.default.removeItem(at: store.attachmentURL(name)) }
        } catch { message = "Couldn’t save the receipt. Check available storage and try again." }
    }
}

extension BankTransaction {
    var displayDate: String {
        guard let date = purchaseDate else { return self.date }
        let formatter = DateFormatter(); formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }
    var relativeDate: String {
        guard let date = purchaseDate else { return "" }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days > 1 { return "\(days) days ago" }
        return "In \(-days) days"
    }
}
