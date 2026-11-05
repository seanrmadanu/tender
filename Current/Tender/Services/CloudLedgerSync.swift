import Foundation

@MainActor
extension LedgerStore {
    var aiClient: AIConnectionsClient { AIConnectionsClient(auth: accountAuth, accountScope: accountScope) }
    var canConnectAI: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ai-connections-test") { return true }
        #endif
        return isAccountLedger && accountAuth?.storageKey == accountScope
    }
    private var cloudStateURL: URL { root.appending(path: "cloud-sync.json") }
    func loadCloudSyncState() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-testing") && !args.contains("--preserve-test-ledger") { cloudState = CloudSyncState(); try? FileManager.default.removeItem(at: cloudStateURL); return }
        #endif
        guard FileManager.default.fileExists(atPath: cloudStateURL.path) else { return }
        do { cloudState = try JSONDecoder.tender.decode(CloudSyncState.self, from: Data(contentsOf: cloudStateURL)) }
        catch { cloudMessage = "Cloud sync settings could not be opened. Your phone ledger is preserved; reconnect from AI Connections." }
    }
    private func saveCloudState() throws { try JSONEncoder.tender.encode(cloudState).write(to: cloudStateURL, options: [.atomic, .completeFileProtection]) }
    func scheduleCloudSync() {
        guard cloudState.enabled, cloudConflict == nil, !cloudBusy else { return }
        cloudSyncTask?.cancel()
        cloudSyncTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(700)); try Task.checkCancellation() } catch { return }
            await synchronizeCloud()
        }
    }
    func synchronizeCloud(enabling: Bool = false) async {
        guard canConnectAI, storageHealthy, !ledger.isDemo, !cloudBusy, cloudConflict == nil, enabling || cloudState.enabled else { return }
        cloudBusy = true; defer { cloudBusy = false }
        do {
            if enabling {
                let health: AIServiceStatus = try await aiClient.call("health", authenticated: false)
                guard health.configured else { throw BankError.message("AI Connections is not ready on the server yet.") }
                try preserveCloudRecoveryCopy(ledger, prefix: "before-ai-connections")
            }
            for _ in 0..<4 {
                try Task.checkCancellation()
                let remote: CloudLedgerSnapshot = try await aiClient.call("v3/ledger")
                if !enabling && !remote.connected {
                    cloudState.enabled = false; try saveCloudState()
                    cloudMessage = "Cloud connections were disabled. Phone changes remain saved here."; return
                }
                let localAtStart = ledger
                let combined: Ledger
                if let other = remote.ledger {
                    do { combined = try CloudLedgerMerge.merge(base: cloudState.base, local: localAtStart, remote: other) }
                    catch { cloudConflict = remote; cloudMessage = "The phone and cloud changed the same information. Review the sync conflict before either version is replaced."; return }
                } else { combined = localAtStart }
                let saved: CloudLedgerSnapshot
                if remote.connected, remote.ledger == combined { saved = remote }
                else {
                    struct Upload: Encodable { var expectedRevision: Int; var timeZone: String; var ledger: Ledger; var appAccessVersion = 1 }
                    let body = try JSONEncoder.tender.encode(Upload(expectedRevision: remote.revision, timeZone: TimeZone.current.identifier, ledger: combined))
                    guard body.count < 8_000_000 else { throw BankError.message("This ledger exceeds the current 8 MB cloud limit. Keep using it on this phone.") }
                    do { saved = try await aiClient.call("v3/ledger", method: "PUT", body: body) }
                    catch let error as CloudServiceError where error.status == 409 { continue }
                }
                guard let accepted = saved.ledger else { throw BankError.message("Cloud response was incomplete. Your phone ledger is preserved.") }
                let latest: Ledger
                do { latest = try CloudLedgerMerge.merge(base: localAtStart, local: ledger, remote: accepted) }
                catch { cloudConflict = saved; cloudMessage = "A newer phone edit needs review before syncing."; return }
                // Save ledger first. A crash before saving its sync base merely
                // repeats a merge; saving the base first could erase a new entry.
                try JSONEncoder.tender.encode(latest).write(to: root.appending(path: "ledger.json"), options: [.atomic, .completeFileProtection])
                ledger = latest
                cloudState.enabled = true; cloudState.revision = saved.revision; cloudState.base = accepted; cloudState.events = saved.events
                try saveCloudState(); cloudMessage = nil
                if latest != localAtStart { await refreshReminders() }
                if latest == accepted { return }
            }
            cloudMessage = "The ledger kept changing during sync. Phone edits are saved; try Sync now again."
        } catch is CancellationError { /* Keep the saved ledger/outbox for the next sync. */ }
        catch { cloudMessage = "Cloud sync paused: \(error.localizedDescription) Phone edits remain saved and will retry when connected." }
    }
    private func preserveCloudRecoveryCopy(_ value: Ledger, prefix: String) throws {
        try JSONEncoder.tender.encode(value).write(to: root.appending(path: prefix + "-" + UUID().uuidString + ".json"), options: [.atomic, .completeFileProtection])
    }
    func resolveCloudConflict(usePhone: Bool) async {
        guard let conflict = cloudConflict, !cloudBusy else { return }
        cloudBusy = true; defer { cloudBusy = false }
        do {
            let localAtStart = ledger
            try preserveCloudRecoveryCopy(ledger, prefix: "phone-before-cloud-conflict")
            if let remote = conflict.ledger { try preserveCloudRecoveryCopy(remote, prefix: "cloud-before-conflict") }
            let chosen = usePhone ? ledger : conflict.ledger ?? ledger
            struct Upload: Encodable { var expectedRevision: Int; var timeZone: String; var ledger: Ledger; var appAccessVersion = 1 }
            let saved: CloudLedgerSnapshot
            if usePhone { saved = try await aiClient.call("v3/ledger", method: "PUT", body: JSONEncoder.tender.encode(Upload(expectedRevision: conflict.revision, timeZone: TimeZone.current.identifier, ledger: chosen))) }
            else {
                let newest: CloudLedgerSnapshot = try await aiClient.call("v3/ledger")
                guard newest.revision == conflict.revision else { cloudConflict = newest; cloudMessage = "The cloud changed again. Review the newest version."; return }
                saved = newest
            }
            guard var value = saved.ledger else { throw BankError.message("Cloud ledger is unavailable.") }
            do { value = try CloudLedgerMerge.merge(base: localAtStart, local: ledger, remote: value) }
            catch { cloudConflict = saved; cloudMessage = "A new phone edit needs review before this conflict can be resolved."; return }
            value.profilePhoto = ledger.profilePhoto
            _ = try value.validated()
            try JSONEncoder.tender.encode(value).write(to: root.appending(path: "ledger.json"), options: [.atomic, .completeFileProtection])
            ledger = value; cloudState.enabled = saved.connected; cloudState.revision = saved.revision; cloudState.base = saved.ledger; cloudState.events = saved.events
            try saveCloudState(); cloudConflict = nil; cloudMessage = nil
            await refreshReminders()
        } catch { cloudMessage = "Could not resolve the conflict. Both versions are preserved: \(error.localizedDescription)" }
    }
    func disconnectAllAI() async {
        guard !cloudBusy else { return }
        cloudBusy = true; defer { cloudBusy = false }
        do {
            let _: CloudLedgerSnapshot = try await aiClient.call("v3/disconnect", method: "POST")
            cloudSyncTask?.cancel(); cloudState.enabled = false; cloudConflict = nil; try saveCloudState()
            cloudMessage = "AI access is disconnected. Existing items and their source badges are kept."
        } catch { cloudMessage = "Disconnection could not be confirmed. Retry while online: \(error.localizedDescription)" }
    }
    func eraseCloudLedger() async throws {
        guard canConnectAI else { return }
        let _: CloudLedgerSnapshot = try await aiClient.call("v3/ledger", method: "DELETE")
        cloudSyncTask?.cancel(); cloudState = CloudSyncState(); cloudConflict = nil; try saveCloudState()
    }
    func wipeCloudBankRecords() async throws {
        guard canConnectAI else { return }
        let snapshot: CloudLedgerSnapshot = try await aiClient.call("v3/wipe-bank", method: "POST")
        cloudSyncTask?.cancel(); cloudState.enabled = false; cloudState.revision = snapshot.revision; cloudState.base = snapshot.ledger; cloudState.events = []
        cloudConflict = nil; try saveCloudState()
    }
}
