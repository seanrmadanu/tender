import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import Vision

@MainActor @Observable
final class LedgerStore {
    var ledger: Ledger
    var error: String?
    var storageHealthy = true
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
                // User approved clearing all pre-migration entries on 2026-10-21.
                // Persist the marker with the replacement ledger so this runs only once.
                if ledger.freshStartVersion == nil {
                    let recovery = root.appending(path: "before-approved-fresh-start.json")
                    if !FileManager.default.fileExists(atPath: recovery.path) {
                        try JSONEncoder.tender.encode(ledger).write(to: recovery, options: [.atomic, .completeFileProtection])
                    }
                    let empty = Ledger.empty()
                    try JSONEncoder.tender.encode(empty).write(to: file, options: [.atomic, .completeFileProtection])
                    ledger = empty
                }
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
            next.freshStartVersion = 1 // An explicit restore must survive the next launch.
            let file = root.appending(path: "ledger.json")
            if FileManager.default.fileExists(atPath: file.path) {
                let backup = root.appending(path: "before-restore-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: file, to: backup)
            }
            try JSONEncoder.tender.encode(next).write(to: file, options: [.atomic, .completeFileProtection])
            ledger = next; storageHealthy = true
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
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        // Keep the nearest future reminders within a conservative request cap.
        var scheduled = 0
        for bill in ledger.recurring.filter(\.remind).sorted(by: { $0.nextDue < $1.nextDue }) {
            let content = UNMutableNotificationContent()
            content.title = "Upcoming payment"
            content.body = "\(bill.name) · \(Money.format(bill.amount)) due \(bill.nextDue.formatted(date: .abbreviated, time: .omitted))"
            content.sound = .default
            let reminder = Calendar.current.date(byAdding: .day, value: -1, to: bill.nextDue)!
            var parts = Calendar.current.dateComponents([.year, .month, .day], from: reminder)
            parts.hour = 9; parts.minute = 0
            let fireDate = Calendar.current.date(from: parts)!
            guard fireDate > Date() else { continue }
            guard scheduled < 60 else { break }
            scheduled += 1
            do { try await center.add(UNNotificationRequest(identifier: bill.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))) }
            catch { self.error = "The payment reminder couldn’t be scheduled. Check notification access in Settings." }
        }
    }
    func enableReminders() async -> Bool {
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
