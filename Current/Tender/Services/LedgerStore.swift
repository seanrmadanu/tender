import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import Vision

@MainActor @Observable
final class LedgerStore {
    var ledger: Ledger
    var error: String?
    var storageHealthy = true
    var bankUpdating = false
    var bankMaintenance = false
    var bankMessage: String?
    var bankSnapshots: [BankSnapshot] = []
    var bankFetchedAt: Date?
    private var lastBankAttempt: Date?
    var bankAccessPaused: Bool { UserDefaults.standard.bool(forKey: "bankAccessPaused") }
    var automaticBankUpdates: Bool {
        get { UserDefaults.standard.object(forKey: "automaticBankUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "automaticBankUpdates") }
    }
    let root: URL
    init() {
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        root = URL.documentsDirectory.appending(path: testing ? "TenderUITests" : "Tender", directoryHint: .isDirectory)
        #else
        root = URL.documentsDirectory.appending(path: "Tender", directoryHint: .isDirectory)
        #endif
        do {
            try FileManager.default.createDirectory(at: root.appending(path: "Attachments"), withIntermediateDirectories: true)
            let file = root.appending(path: "ledger.json")
            #if DEBUG
            if testing && !ProcessInfo.processInfo.arguments.contains("--preserve-test-ledger") {
                var initial = ProcessInfo.processInfo.arguments.contains("--sample-ledger") ? Ledger.sample() : Ledger.empty()
                if ProcessInfo.processInfo.arguments.contains("--legacy-reset-test") { initial = Ledger.sample(); initial.freshStartVersion = nil }
                try JSONEncoder.tender.encode(initial).write(to: file, options: .atomic)
            }
            #endif
            if FileManager.default.fileExists(atPath: file.path) {
                ledger = try JSONDecoder.tender.decode(Ledger.self, from: Data(contentsOf: file)).validated()
                // Preserve every existing ledger. The earlier one-time reset is retired.
                if ledger.freshStartVersion == nil { ledger.freshStartVersion = 1 }
                for i in ledger.groceries.indices where ledger.groceries[i].plannedAt == nil {
                    ledger.groceries[i].plannedAt = Calendar.current.startOfDay(for: Date())
                }
                try JSONEncoder.tender.encode(ledger).write(to: file, options: [.atomic, .completeFileProtection])
            } else { ledger = .empty() }
        } catch {
            ledger = .empty(); storageHealthy = false
            self.error = "Your saved ledger could not be opened. The original file has been preserved. Restore a valid backup in Settings before making changes."
        }
    }
    @discardableResult func update(_ change: (inout Ledger) throws -> Void) -> Bool {
        guard storageHealthy else { error = "Restore a valid backup before editing this ledger."; return false }
        do {
            var next = ledger
            try change(&next)
            _ = try next.validated()
            try JSONEncoder.tender.encode(next).write(to: root.appending(path: "ledger.json"), options: [.atomic, .completeFileProtection])
            ledger = next
            return true
        } catch { self.error = "Couldn’t save this change. Check the values and available storage, then try again."; return false }
    }
    @discardableResult func replaceWithPersonalLedger(_ next: Ledger) -> Bool {
        guard storageHealthy, ledger.isDemo else { return false }
        do {
            let backup = root.appending(path: "before-sample-cleanup-\(UUID().uuidString).json")
            try JSONEncoder.tender.encode(ledger).write(to: backup, options: [.atomic, .completeFileProtection])
            // Attachments are retained, so this local recovery copy can still open them.
            return update { $0 = next }
        } catch { self.error = "Couldn’t preserve a recovery copy. Your existing ledger is unchanged."; return false }
    }
    func restore(_ data: Data) {
        guard !bankUpdating, !bankMaintenance else { error = "Wait for the bank operation to finish before restoring."; return }
        var stagedFiles: [URL] = []
        do {
            guard data.count < LedgerArchive.maximumEncodedBytes else { throw LedgerError.invalidBackup }
            var next: Ledger
            if let archive = try? JSONDecoder.tender.decode(LedgerArchive.self, from: data) {
                _ = try archive.validated()
                next = archive.ledger
                var renamed: [String: String] = [:]
                // Preserve existing files until the replacement ledger commits.
                for (name, bytes) in archive.attachments {
                    let newName = UUID().uuidString + "." + (name as NSString).pathExtension
                    let destination = attachmentURL(newName)
                    stagedFiles.append(destination)
                    try bytes.write(to: destination, options: [.atomic, .completeFileProtection])
                    renamed[name] = newName
                }
                next.renameAttachments(renamed)
            } else {
                guard data.count < 30_000_000 else { throw LedgerError.invalidBackup }
                next = try JSONDecoder.tender.decode(Ledger.self, from: data).validated()
            }
            next.freshStartVersion = 1
            for i in next.accounts.indices where next.accounts[i].bankAccountKey != nil { next.accounts[i].needsReconnection = true }
            let file = root.appending(path: "ledger.json")
            if FileManager.default.fileExists(atPath: file.path) {
                let backup = root.appending(path: "before-restore-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: file, to: backup)
            }
            try JSONEncoder.tender.encode(next).write(to: file, options: [.atomic, .completeFileProtection])
            ledger = next; storageHealthy = true
            UserDefaults.standard.set(true, forKey: "bankAccessPaused")
            bankSnapshots = []; bankFetchedAt = nil
            bankMessage = "Backup restored. Reauthorize your bank in Settings before fetching current information."
            Task { await refreshReminders() }
        } catch {
            for file in stagedFiles { try? FileManager.default.removeItem(at: file) }
            self.error = "This isn’t a supported Tender backup, or it couldn’t be saved. Your current ledger is unchanged."
        }
    }
    func completeBackup() throws -> Data {
        var attachments: [String: Data] = [:]
        var total = 0
        for name in ledger.attachmentNames {
            let file = attachmentURL(name)
            let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size > 0, size <= 20_000_000, total + size <= LedgerArchive.maximumAttachmentBytes else { throw LedgerError.invalidBackup }
            let bytes = try Data(contentsOf: file)
            total += bytes.count
            attachments[name] = bytes
        }
        let archive = try LedgerArchive(ledger: ledger, attachments: attachments).validated()
        let data = try JSONEncoder.tender.encode(archive)
        guard data.count < LedgerArchive.maximumEncodedBytes else { throw LedgerError.invalidBackup }
        return data
    }
    func attach(_ data: Data, extension ext: String) throws -> String {
        guard data.count <= 20_000_000 else { throw CocoaError(.fileWriteFileExists) }
        let name = UUID().uuidString + "." + ext
        try data.write(to: attachmentURL(name), options: [.atomic, .completeFileProtection])
        return name
    }
    func attachmentURL(_ name: String) -> URL { root.appending(path: "Attachments").appending(path: (name as NSString).lastPathComponent) }
    func refreshReminders() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        #endif
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier))
        var reminders: [(String, Date, String, String)] = []
        for bill in ledger.recurring where bill.remind {
            let day = Calendar.current.date(byAdding: .day, value: -1, to: bill.nextDue)!
            let fire = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
            reminders.append((bill.id.uuidString, fire, "Upcoming payment", "\(bill.name) · \(Money.format(bill.amount))"))
        }
        for item in ledger.groceries where item.remind == true && item.purchasedAt == nil {
            if let date = item.plannedAt {
                reminders.append(("shopping-" + item.id.uuidString, date.addingTimeInterval(-3600), "Shopping in one hour", "\(item.name)\(item.storeName.map { " at " + $0 } ?? "")"))
            }
        }
        for (id, date, title, body) in reminders.filter({ $0.1 > Date() }).sorted(by: { $0.1 < $1.1 }).prefix(60) {
            let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            do { try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))) }
            catch { self.error = "A reminder could not be scheduled. Check notification access in Settings." }
        }
    }
    func refreshBank(force: Bool = false) async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return }
        #endif
        guard !bankUpdating, !bankMaintenance, !bankAccessPaused, !ledger.isDemo, storageHealthy,
              force || automaticBankUpdates, let config = BankConfiguration.load(),
              force || Date().timeIntervalSince(lastBankAttempt ?? .distantPast) >= 300 else { return }
        bankUpdating = true; lastBankAttempt = Date(); bankMessage = nil
        defer { bankUpdating = false }
        let client = BankClient(configuration: config)
        var messages: [String] = []
        do {
            // accounts/get uses provider cached balances. Never call paid live refresh
            // or overwrite a locally adjusted ledger balance in this automatic path.
            let response: BankAccountsResponse = try await client.call("v1/accounts")
            guard response.environment == "production" else { throw BankError.message("Sandbox data is not imported into your personal ledger.") }
            let incomingIDs = Set(response.accounts.map(\.id))
            bankSnapshots.removeAll { incomingIDs.contains($0.id) }
            bankSnapshots += response.accounts
            bankFetchedAt = Date(); messages += response.errors
        } catch { messages.append(error.localizedDescription) }
        do {
            let result: BankActivityResponse = try await client.call("v1/transactions/sync", method: "POST")
            guard result.environment == "production" else { throw BankError.message("Sandbox activity was not imported.") }
            if !update({ try $0.receiveBankActivity(result.items) }) { messages.append("Bank activity could not be saved. Previous activity is retained.") }
            messages += result.errors.map(\.message)
        } catch { messages.append("Activity update failed: " + error.localizedDescription) }
        bankMessage = messages.isEmpty ? nil : messages.joined(separator: "\n")
    }
    func resumeBankAccess() {
        UserDefaults.standard.set(false, forKey: "bankAccessPaused")
        lastBankAttempt = nil
    }
    func eraseLocalData(bankOnly: Bool) throws {
        guard !bankUpdating else { throw BankError.message("Wait for the bank update to finish before deleting data.") }
        var next = bankOnly ? ledger : Ledger.empty()
        if bankOnly {
            let bankIDs = Set(next.accounts.filter { $0.bankAccountKey != nil }.map(\.id))
            let removedIDs = Set(next.expenses.filter { bankIDs.contains($0.accountID) }.map(\.id))
            next.expenses.removeAll { bankIDs.contains($0.accountID) }
            next.accounts.removeAll { bankIDs.contains($0.id) }
            next.bankActivity = nil
            for i in next.groceries.indices where next.groceries[i].expenseID.map(removedIDs.contains) == true {
                next.groceries[i].expenseID = nil
                next.groceries[i].purchasedAt = nil
                next.groceries[i].checked = false
                next.groceries[i].remind = false
            }
        }
        try JSONEncoder.tender.encode(try next.validated()).write(to: root.appending(path: "ledger.json"), options: [.atomic, .completeFileProtection])
        ledger = next; bankSnapshots = []; bankFetchedAt = nil; bankMessage = nil
        // Remove recovery copies as well as unreferenced receipt files; backups the
        // user exported to Files remain under their control.
        for file in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            where file.pathExtension == "json" && file.lastPathComponent != "ledger.json" {
            try FileManager.default.removeItem(at: file)
        }
        for file in try FileManager.default.contentsOfDirectory(at: root.appending(path: "Attachments"), includingPropertiesForKeys: nil)
            where !next.attachmentNames.contains(file.lastPathComponent) {
            try FileManager.default.removeItem(at: file)
        }
        try BankConfiguration.remove()
        UserDefaults.standard.set(true, forKey: "bankAccessPaused")
        Task { await refreshReminders() }
    }
    func enableReminders() async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return false }
        #endif
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if !granted { error = "Notifications are off. Enable Tender in iPhone Settings → Notifications." }
            return granted
        } catch { self.error = "Notification permission couldn’t be requested."; return false }
    }
    func summary(days: Int? = nil) -> String {
        let interval: DateInterval
        if let days { interval = DateInterval(start: Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date()))!, end: Date()) }
        else { interval = ledger.month() }
        let heading = days == nil ? "Monthly summary" : "Last 7 days"
        var lines = ["Tender — \(heading)", "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(min(interval.end, Date()).formatted(date: .abbreviated, time: .omitted))", ledger.isDemo ? "SAMPLE DATA" : "USD · Personal ledger", "", "Spent: \(Money.format(ledger.spent(in: interval)))", "Available balance: \(Money.format(ledger.available)) (recorded bank/manual snapshots, adjusted for recorded expenses)", "Monthly category budget: \(Money.format(ledger.monthlyBudget))", "Upcoming 30-day bills: \(Money.format(ledger.upcomingReserve()))", ""]
        for c in ledger.categories { lines.append("\(c.name): \(Money.format(ledger.spent(category: c.id, in: interval))) spent; monthly allocation \(Money.format(c.limit))") }
        lines.append("\nBased only on recorded expenses. Estimates aren’t guarantees. No account credentials or bill images included.")
        return lines.joined(separator: "\n")
    }
    func csv() -> String {
        func quote(_ text: String) -> String {
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: { text.hasPrefix($0) }) ? "'" + text : text
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let rows = ledger.expenses.sorted { $0.date > $1.date }.map { e in
            [quote(e.date.ISO8601Format()), quote(e.merchant), Money.input(e.amount), quote(ledger.categories.first { $0.id == e.categoryID }?.name ?? "Unknown"), quote(e.note)].joined(separator: ",")
        }
        return (["date,merchant,amount_usd,category,note"] + rows).joined(separator: "\n")
    }
}
extension JSONEncoder {
    static var tender: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }
}
extension JSONDecoder {
    static var tender: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText, .plainText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
enum ReceiptOCR {
    static func read(_ data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(data: data).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
}
