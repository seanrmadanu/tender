import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import Vision
import OSLog

@MainActor @Observable
final class LedgerStore {
    let gmail: GmailSubscriptions
    let isAccountLedger: Bool
    let accountScope: String?
    let accountAuth: AccountAuth?
    var cloudState = CloudSyncState()
    var cloudBusy = false
    var cloudMessage: String?
    var cloudConflict: CloudLedgerSnapshot?
    var pendingAIAuthorization: String?
    @ObservationIgnored var cloudSyncTask: Task<Void, Never>?
    private var bankPreferenceSuffix: String { accountScope.map { "." + $0 } ?? "" }
    var bankClient: BankClient? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--bank-import-test") {
            return BankClient(configuration: BankConfiguration(server: "https://fixture.invalid", token: ""))
        }
        #endif
        if let accountScope {
            guard let accountAuth else { return nil }
            return BankClient(configuration: BankConfiguration(server: BankConfiguration.accountServer, token: ""), accountAuth: accountAuth, accountScope: accountScope)
        }
        return BankConfiguration.load().map { BankClient(configuration: $0) }
    }
    var ledger: Ledger
    var error: String?
    private(set) var hasLoaded = false
    private(set) var startupReady = false
    private var preparingHome = false
    var storageHealthy = false
    private var loadingTask: Task<Ledger, Error>?
    private let startupLog = Logger(subsystem: "com.sean.tender", category: "Startup")
    var bankUpdating = false
    var bankMaintenance = false
    var bankMessage: String?
    let bankNetwork = BankNetworkStatus()
    var bankConnections: [BankConnection] = []
    var bankConnectionIssues: [BankConnectionIssue] = []
    var bankImportNotice: String?
    private var requestWasOffline = false
    private var checkedRemoteConnections = false
    var bankIsOffline: Bool { bankNetwork.isOffline || requestWasOffline }
    var hasBankAccounts: Bool { ledger.accounts.contains { $0.bankAccountKey != nil } }
    var hasPendingBankImport: Bool { ledger.bankSync?.pendingImport == true }
    var bankLastUpdated: Date? { (ledger.accounts.filter { $0.bankAccountKey != nil && $0.isArchived != true }.compactMap(\.snapshotAt) + [ledger.bankSync?.balancesCheckedAt].compactMap { $0 }).min() }
    private var lastBankAttempt: Date?
    private var lastBankAttemptSucceeded = false
    @ObservationIgnored private var lastWalletBalanceRoll: ContinuousClock.Instant?
    func claimWalletBalanceRoll() -> Bool {
        let now = ContinuousClock.now
        guard lastWalletBalanceRoll.map({ $0.duration(to: now) >= .seconds(180) }) ?? true else { return false }
        lastWalletBalanceRoll = now
        return true
    }
    var bankAccessPaused: Bool { UserDefaults.standard.bool(forKey: "bankAccessPaused" + bankPreferenceSuffix) }
    let root: URL
    init(accountKey: String? = nil, accountAuth: AccountAuth? = nil) {
        self.accountScope = accountKey; self.accountAuth = accountAuth
        isAccountLedger = accountKey != nil
        gmail = GmailSubscriptions(scope: accountKey ?? "legacy")
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"), accountKey != nil {
            root = URL.documentsDirectory.appending(path: "TenderUITestsAuth", directoryHint: .isDirectory)
            ledger = .empty()
            return
        }
        #endif
        if let accountKey {
            // accountKey is a SHA256 digest of Firebase project + verified UID.
            root = URL.documentsDirectory.appending(path: "TenderAccounts", directoryHint: .isDirectory).appending(path: accountKey, directoryHint: .isDirectory)
        } else {
            #if DEBUG
            let directory = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? "TenderUITests" : "Tender"
            #else
            let directory = "Tender"
            #endif
            root = URL.documentsDirectory.appending(path: directory, directoryHint: .isDirectory)
        }
        ledger = .empty()
    }
    // Initialization stays cheap: no filesystem, validation, or migration work
    // can hold the system launch screen on the main actor.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        if loadingTask == nil {
            let root = root
            var initial: Ledger?
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            let testing = arguments.contains("--ui-testing")
            if testing && !arguments.contains("--preserve-test-ledger") {
                initial = arguments.contains("--sample-ledger") ? Ledger.sample() : Ledger.empty()
                if arguments.contains("--legacy-reset-test") { initial = Ledger.sample(); initial?.freshStartVersion = nil }
            }
            if testing && arguments.contains("--wallet-startup-test") && !arguments.contains("--preserve-test-ledger") {
                initial = Ledger.empty()
                initial?.accounts = [Account(name: "Test Bank · Checking · ··1234", available: 999, bankAccountKey: "production:fixture-checking")]
            }
            if testing && arguments.contains("--budget-funding-test") && !arguments.contains("--preserve-test-ledger") {
                var fixture = Ledger.empty()
                fixture.accounts = [Account(name: "Checking", available: 50_000, bankAccountKey: "production:funding-checking")]
                let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX")
                let day = formatter.string(from: Date())
                fixture.bankActivity = [BankActivityItem(id: "funding-item", checkedAt: Date(), transactions: [
                    BankTransaction(id: "production:funding-item:coffee", accountKey: "production:funding-checking", merchant: "Fixture Coffee", amountCents: 1000, currency: "USD", date: day, pending: false, category: "FOOD_AND_DRINK", isTransfer: false),
                    BankTransaction(id: "production:funding-item:transfer", accountKey: "production:funding-checking", merchant: "Fixture Transfer", amountCents: 10_000, currency: "USD", date: day, pending: false, category: "TRANSFER_OUT", isTransfer: true),
                    BankTransaction(id: "production:funding-item:pending", accountKey: "production:funding-checking", merchant: "Fixture Pending", amountCents: 1500, currency: "USD", date: day, pending: true, category: "FOOD_AND_DRINK", isTransfer: false)
                ])]
                initial = fixture
            }
            let slowTestLoad = testing && arguments.contains("--slow-ledger-load")
            #else
            let slowTestLoad = false
            #endif
            let seed = initial
            loadingTask = Task.detached(priority: .userInitiated) {
                // Exercise first-frame responsiveness without touching a real ledger.
                if slowTestLoad { try await Task.sleep(for: .seconds(5)) }
                return try LedgerPersistence.load(root: root, initial: seed)
            }
        }
        let started = ContinuousClock.now
        do {
            ledger = try await loadingTask!.value
            loadCloudSyncState()
            storageHealthy = true
        } catch {
            storageHealthy = false
            self.error = "Your saved ledger could not be opened. The original file has been preserved. Restore a valid backup in Settings before making changes."
        }
        hasLoaded = true
        loadingTask = nil
        startupLog.info("Local ledger load finished in \(String(describing: started.duration(to: .now)), privacy: .public); healthy=\(self.storageHealthy, privacy: .public)")
    }
    func prepareForHome() async {
        guard !startupReady, !preparingHome else { return }
        preparingHome = true
        defer { preparingHome = false; startupReady = true }
        await loadIfNeeded()
        guard storageHealthy, !ledger.isDemo else { return }
        if cloudState.enabled { await synchronizeCloud() }
        // Home's first balance must come from the completed launch refresh.
        // Do not reveal saved balances on a timer while that request is pending.
        // Offline/failure paths retain the saved ledger and its freshness warning.
        let needsBankRefresh = hasBankAccounts || hasPendingBankImport || isAccountLedger
        if needsBankRefresh { _ = await refreshBank(force: true) }
    }
    @discardableResult func update(_ change: (inout Ledger) throws -> Void) -> Bool {
        guard storageHealthy else { error = "Restore a valid backup before editing this ledger."; return false }
        do {
            var next = ledger
            next.initializeMonthlyAllocationIfNeeded()
            try change(&next)
            _ = try next.validated()
            try JSONEncoder.tender.encode(next).write(to: root.appending(path: "ledger.json"), options: [.atomic, .completeFileProtection])
            ledger = next
            scheduleCloudSync()
            return true
        } catch LedgerError.staleEdit {
            self.error = "This item changed while you were editing. Reopen it to review the newest version."
            return false
        } catch LedgerError.budgetUnavailable {
            self.error = "Your monthly allocation must fit within the account balances remaining after fixed expenses. Envelope allocations must also fit within that total."
            return false
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
        guard !cloudState.enabled && !cloudBusy else { error = "Disconnect AI Connections in Settings before restoring a backup, so cloud changes cannot replace the restored ledger."; return }
        guard !bankUpdating, !bankMaintenance, !gmail.busy else { error = "Wait for bank and email updates to finish before restoring."; return }
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
            next.initializeMonthlyAllocationIfNeeded()
            next.subscriptionMailboxes = [] // Backups never restore Google access.
            next.bankSync = nil
            next.freshStartVersion = 1
            for i in next.accounts.indices where next.accounts[i].bankAccountKey != nil { next.accounts[i].needsReconnection = true }
            let file = root.appending(path: "ledger.json")
            if FileManager.default.fileExists(atPath: file.path) {
                let backup = root.appending(path: "before-restore-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: file, to: backup)
            }
            try JSONEncoder.tender.encode(next).write(to: file, options: [.atomic, .completeFileProtection])
            ledger = next; storageHealthy = true
            UserDefaults.standard.set(true, forKey: "bankAccessPaused" + bankPreferenceSuffix)
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
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && !ProcessInfo.processInfo.arguments.contains("--ai-reminder-test") { return }
        #endif
        let center = UNUserNotificationCenter.current()
        let old = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: old.map(\.identifier))
        guard ledger.appPreferences?.remindersEnabled != false else { return }
        var reminders: [(String, Date, String, String)] = []
        for bill in ledger.activeRecurring where bill.remind {
            let day = Calendar.current.date(byAdding: .day, value: bill.trialEndsAt == nil ? -1 : -3, to: bill.trialEndsAt ?? bill.nextDue)!
            let fire = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
            reminders.append((bill.id.uuidString, fire, bill.trialEndsAt == nil ? "Estimated renewal" : "Trial ending soon", bill.name + " · " + (bill.renewalAmountUnknown == true ? "Check renewal price" : Money.format(bill.amount))))
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
    func markBankImportPending(_ pending: Bool) {
        _ = update { ledger in
            if ledger.bankSync == nil { ledger.bankSync = BankSyncRecord() }
            ledger.bankSync?.pendingImport = pending
        }
    }
    func acceptBankReturn(_ url: URL) async {
        guard url.scheme == "tender", url.host == "bank-link-complete" else { return }
        // A callback only wakes verification. The backend owns the session and
        // verifies Plaid completion; the URL can never import or authorize data.
        await refreshBank(force: true)
    }
    func networkDidChange() async {
        if !bankNetwork.isOffline {
            requestWasOffline = false; lastBankAttempt = nil
            await refreshBank()
        }
    }
    @discardableResult func refreshBank(force: Bool = false, finishingImport: Bool = false) async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && !ProcessInfo.processInfo.arguments.contains("--bank-import-test") { return false }
        #endif
        guard !bankUpdating, (!bankMaintenance || finishingImport), !ledger.isDemo, storageHealthy else { return false }
        guard !bankNetwork.isOffline else { requestWasOffline = true; return false }
        guard force || hasBankAccounts || hasPendingBankImport || (!checkedRemoteConnections && isAccountLedger) else { return false }
        let retryInterval: TimeInterval = hasPendingBankImport ? 15 : (lastBankAttemptSucceeded ? 300 : 30)
        guard force || Date().timeIntervalSince(lastBankAttempt ?? .distantPast) >= retryInterval else { return false }
        guard let client = bankClient else { return false }
        bankUpdating = true; lastBankAttempt = Date(); lastBankAttemptSucceeded = false
        defer { bankUpdating = false }
        do {
            var reauthorized = finishingImport
            // Resume a finished login after backgrounding, app termination, or
            // a lost callback. Users never need a Check Connection control.
            if !finishingImport {
                let pending: HostedBankSessionResponse = try await client.call("v1/hosted-link")
                if let session = pending.session {
                    let result: HostedBankResult = try await client.call("v1/hosted-link/finish", method: "POST", body: ["sessionID": session.id])
                    if result.status == "connected" { resumeBankAccess(); reauthorized = true; markBankImportPending(false) }
                    else { markBankImportPending(result.status == "pending") }
                } else if hasPendingBankImport { markBankImportPending(false) }
            }
            let connections: BankConnectionsResponse = try await client.call("v1/connections")
            bankConnections = connections.connections; checkedRemoteConnections = true; requestWasOffline = false
            guard !bankAccessPaused else { bankMessage = "Reconnect your bank to resume automatic updates."; return false }
            guard !bankConnections.isEmpty else {
                bankMessage = hasBankAccounts ? "Your bank needs to be connected again. Saved information may be outdated." : nil
                lastBankAttemptSucceeded = !hasBankAccounts
                return lastBankAttemptSucceeded
            }
            let result: BankSyncResponse = try await client.call("v1/sync", method: "POST")
            guard result.environment == "production" else { throw BankError.message("Test bank data cannot be imported into this account.") }
            try Task.checkCancellation()
            var syncResult = BankSyncResult()
            guard update({ ledger in
                syncResult = try ledger.synchronizeBankAccounts(result.accounts, environment: result.environment, reauthorized: reauthorized)
                try ledger.receiveBankActivity(result.items)
                if ledger.bankSync == nil { ledger.bankSync = BankSyncRecord() }
                ledger.bankSync?.balancesCheckedAt = result.balancesCheckedAt
                ledger.bankSync?.activityCheckedAt = result.activityCheckedAt
            }) else { throw BankError.message("Bank information was received but couldn’t be saved. Your previous information is still available.") }
            bankConnectionIssues = Dictionary(grouping: result.connectionIssues, by: \.itemID).values.compactMap { values in
                values.first(where: \.requiresReauthentication) ?? values.first
            }.sorted { $0.name < $1.name }
            var messages = Array(Set(result.errors)).sorted()
            if syncResult.unavailable > 0 { messages.append("Some accounts could not be updated. Their saved information may be outdated.") }
            bankMessage = messages.isEmpty ? nil : messages.joined(separator: "\n")
            if syncResult.added > 0 { bankImportNotice = syncResult.added == 1 ? "Bank account imported" : "\(syncResult.added) bank accounts imported" }
            lastBankAttemptSucceeded = result.errors.isEmpty && syncResult.unavailable == 0
            return lastBankAttemptSucceeded
        } catch is CancellationError { return false }
        catch BankError.offline { requestWasOffline = true; return false }
        catch { bankMessage = error.localizedDescription; return false }
    }
    func resumeBankAccess() {
        UserDefaults.standard.set(false, forKey: "bankAccessPaused" + bankPreferenceSuffix)
        lastBankAttempt = nil
    }
    func eraseLocalData(bankOnly: Bool) throws {
        guard !bankUpdating, !gmail.busy else { throw BankError.message("Wait for bank/email updates to finish before deleting data.") }
        if !bankOnly { try GmailSubscriptions.clearCredentials() }
        var next = bankOnly ? ledger : Ledger.empty()
        if bankOnly {
            let bankIDs = Set(next.accounts.filter { $0.bankAccountKey != nil }.map(\.id))
            let removedIDs = Set(next.expenses.filter { bankIDs.contains($0.accountID) }.map(\.id))
            next.expenses.removeAll { bankIDs.contains($0.accountID) }
            next.archivedItems?.expenses.removeAll { bankIDs.contains($0.expense.accountID) }
            next.archivedCards?.removeAll { bankIDs.contains($0.id) }
            next.accounts.removeAll { bankIDs.contains($0.id) }
            if next.primaryAccountID.map(bankIDs.contains) == true { next.primaryAccountID = nil }
            next.bankActivity = nil
            next.bankTransactionDetails = nil
            next.bankSync = nil
            for i in next.groceries.indices where next.groceries[i].expenseID.map(removedIDs.contains) == true {
                next.groceries[i].expenseID = nil
                next.groceries[i].purchasedAt = nil
                next.groceries[i].checked = false
                next.groceries[i].remind = false
            }
        }
        try JSONEncoder.tender.encode(try next.validated()).write(to: root.appending(path: "ledger.json"), options: [.atomic, .completeFileProtection])
        ledger = next; bankMessage = nil
        bankConnections = []; bankConnectionIssues = []; checkedRemoteConnections = false
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
        if !isAccountLedger { try BankConfiguration.remove() }
        UserDefaults.standard.set(true, forKey: "bankAccessPaused" + bankPreferenceSuffix)
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
        var lines = ["Tender — \(heading)", "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(min(interval.end, Date()).formatted(date: .abbreviated, time: .omitted))", ledger.isDemo ? "SAMPLE DATA" : "USD · Personal ledger", "", "Spent: \(Money.format(ledger.spent(in: interval)))", "Available balance: \(Money.format(ledger.available)) (recorded bank/manual snapshots, adjusted for recorded expenses)", "Monthly budget: \(Money.format(ledger.monthlyBudget))", "Upcoming 30-day bills: \(Money.format(ledger.upcomingReserve()))", ""]
        for c in ledger.categories { lines.append("\(c.name): \(Money.format(ledger.spent(category: c.id, in: interval))) spent; monthly allocation \(Money.format(c.limit))") }
        lines.append("Needs an envelope: \(Money.format(SpendingSummary(entries: ledger.spendingEntries(in: interval)).unassigned))")
        lines.append("\nBased on posted USD bank purchases and recorded expenses. Pending bank entries, transfers and credits are excluded. No account credentials or bill images included.")
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
