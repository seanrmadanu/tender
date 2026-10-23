import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var resetting = false
    @Environment(LedgerStore.self) private var store
    var body: some View {
        Form {
            Section {
                HStack { Image(systemName: "seal").font(.largeTitle); VStack(alignment: .leading) { Text("tender").font(.system(.title, design: .serif)); Text("Personal edition · USD").font(.caption) } }
            }
            Section("Your money") {
                NavigationLink { AccountForm() } label: { Label("Accounts & Cash Wallet", systemImage: "wallet.bifold") }
                NavigationLink { EmailSubscriptionsView() } label: { Label("Subscription Emails", systemImage: "envelope") }
                NavigationLink { BankConnectionView() } label: { Label("Bank Connections", systemImage: "building.columns") }
            }
            Section("Preferences") {
                NavigationLink { UpdateSettingsView() } label: { Label("Bank Updates & Reminders", systemImage: "arrow.triangle.2.circlepath") }
                NavigationLink { ShortcutSettingsView() } label: { Label("Shopping Shortcut", systemImage: "hand.tap") }
            }
            Section("Your data") {
                NavigationLink { BackupSettingsView() } label: { Label("Backup & Restore", systemImage: "icloud") }
                NavigationLink { PrivacySettingsView() } label: { Label("Privacy & Delete Data", systemImage: "lock.shield") }
                Button(role: .destructive) { resetting = true } label: { Label("Reset App", systemImage: "arrow.counterclockwise") }
                if store.ledger.isDemo { NavigationLink("Review Old Sample Data") { SampleCleanupView() } }
            }
            Section { Text("Apple/Google sign-in and separate online accounts are planned for the friends’ beta. This build uses your existing personal bank connection.").font(.footnote).foregroundStyle(.secondary) }
        }.paperForm().navigationTitle("Settings")
            .sheet(isPresented: $resetting) { NavigationStack { PrivacySettingsView(resetApp: true).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { resetting = false } } } } }
    }
}
struct UpdateSettingsView: View {
    @Environment(LedgerStore.self) private var store
    var body: some View {
        Form {
            Section {
                Toggle("Automatically check bank information", isOn: Binding(get: { store.automaticBankUpdates }, set: { store.automaticBankUpdates = $0 }))
                Text("Checks when you open Tender and every five minutes while it is active. Retrieves provider-cached balances and available transaction updates; it does not request a paid on-demand bank refresh. Banks can take time to post changes.").font(.footnote)
                Button("Check Now") { Task { await store.refreshBank(force: true) } }.disabled(store.bankUpdating || store.bankAccessPaused || BankConfiguration.load() == nil)
                if let date = store.bankFetchedAt { LabeledContent("Last balance retrieval", value: date.formatted(date: .abbreviated, time: .shortened)) }
                if let message = store.bankMessage { Text(message).foregroundStyle(Ink.warning) }
                Text("Wallet cards label cached balances. Recorded ledger balances remain separate and change only through reviewed snapshots or manual entries.").font(.footnote)
            } header: { Text("Bank freshness") }
            Section {
                Text("Shopping reminders arrive one hour before the time you confirm. Recurring payment reminders arrive the previous day at 9 AM. iOS controls delivery; Tender schedules the nearest 60 future reminders.")
                Button("Enable Notifications") { Task { _ = await store.enableReminders(); await store.refreshReminders() } }
            } header: { Text("Reminders") }
        }.paperForm().navigationTitle("Updates & Reminders")
    }
}
struct ShortcutSettingsView: View {
    var body: some View {
        Form {
            Text("1. In Shortcuts, create a shortcut using Tender → Open Shopping Mode.\n\n2. Open iPhone Settings → Accessibility → Touch → Back Tap → Triple Tap.\n\n3. Select your shortcut.")
            Text("You can also use tender://shopping in an Open URLs action.").font(.footnote)
        }.paperForm().navigationTitle("Shopping Shortcut")
    }
}
struct BackupSettingsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var exporter = false
    @State private var importer = false
    @State private var confirm = false
    @State private var pending: Data?
    @State private var document = ExportDocument(data: Data())
    @State private var type = UTType.json
    @State private var filename = "Tender-Backup.json"
    @State private var saved: String?
    var body: some View {
        Form {
            Section {
                Button("Save Complete Backup", systemImage: "icloud.and.arrow.up") {
                    do { prepare(try store.completeBackup(), name: "Tender-Backup.json", type: .json) }
                    catch { store.error = "Backup could not be created. Check that attachments are present and total no more than 60 MB." }
                }
                Button("Restore Backup", systemImage: "icloud.and.arrow.down") { importer = true }.disabled(store.bankUpdating)
                if let saved { Text(saved).font(.footnote) }
            } footer: { Text("Choose iCloud Drive in the Files sheet. The complete backup includes receipts and photos. Saving is manual; this free-team build does not enable an iCloud container or automatic synchronization. Restoring requires bank reauthorization before updates resume.") }
            Section {
                DisclosureGroup("Export for analysis") {
                    Button("Ledger JSON") { do { prepare(try JSONEncoder.tender.encode(store.ledger), name: "Tender-Ledger.json", type: .json) } catch { store.error = "Could not create export." } }
                    Button("Expenses CSV") { prepare(Data(store.csv().utf8), name: "Tender-Expenses.csv", type: .commaSeparatedText) }
                    Button("Weekly Summary") { prepare(Data(store.summary(days: 7).utf8), name: "Tender-Weekly.txt", type: .plainText) }
                    Button("Monthly Summary") { prepare(Data(store.summary().utf8), name: "Tender-Monthly.txt", type: .plainText) }
                }
            } footer: { Text("Analysis exports omit attachment files. Exports contain financial information; bank access tokens are never included.") }
        }.paperForm().navigationTitle("Backup & Restore")
            .fileExporter(isPresented: $exporter, document: document, contentType: type, defaultFilename: filename) { result in
                switch result { case .success: saved = "Backup/export saved to your selected location."; case .failure: store.error = "The file could not be saved. Try another Files location." }
            }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) < LedgerArchive.maximumEncodedBytes else { throw LedgerError.invalidBackup }
                    pending = try Data(contentsOf: url); confirm = true
                } catch { store.error = "Choose a valid Tender backup under 120 MB." }
            }
            .confirmationDialog("Replace this ledger with your backup? A local recovery copy will be kept. Bank updates will pause until you reauthorize your connection.", isPresented: $confirm, titleVisibility: .visible) {
                Button("Restore", role: .destructive) { if let pending { store.restore(pending) }; pending = nil }
                Button("Cancel", role: .cancel) { pending = nil }
            }
    }
    private func prepare(_ data: Data, name: String, type: UTType) { document = ExportDocument(data: data); filename = name; self.type = type; exporter = true }
}
struct PrivacySettingsView: View {
    var resetApp = false
    @Environment(LedgerStore.self) private var store
    @State private var bankOnly = true
    @State private var confirm = false
    @State private var exporter = false
    @State private var busy = false
    @State private var document = ExportDocument(data: Data())
    @State private var message: String?
    private var remoteAccessUnknown: Bool { BankConfiguration.load() == nil && store.ledger.accounts.contains { $0.bankAccountKey != nil } }
    var body: some View {
        Form {
            Section("Protection") {
                Text("Bank credentials stay in the encrypted backend vault. Device access uses Keychain; ledger and receipt files use iOS file protection. Photo recognition and this app’s shopping speech recognition run on device.")
                Text("No financial data is sent to an AI service. Your exported backups and Apple device backups follow your own storage settings.").font(.footnote)
            }
            Section {
                if !resetApp { Button("Wipe My Bank Information", role: .destructive) { bankOnly = true; confirm = true }.disabled(busy || store.bankUpdating || store.gmail.busy) }
                Button(resetApp ? "Reset App" : "Delete All My Tender Data", role: .destructive) { bankOnly = false; confirm = true }.disabled(busy || store.bankUpdating || store.gmail.busy)
                if resetApp { Text("Forgets your saved Tender login, clears this device’s ledger, receipts, credentials, preferences and notifications, revokes saved bank connections, and returns to the login page. You will need to sign in again. Exported backups remain in Files. Sign-in still requires setup in this build.").font(.footnote) }
                if remoteAccessUnknown { Text("No connection credentials are saved. Deletion can remove device data, but cannot verify or revoke old remote bank access.").font(.footnote).foregroundStyle(Ink.warning) }
                if busy { ProgressView("Revoking bank access and deleting data…") }
                if let message { Text(message).font(.footnote) }
            } footer: { Text("Bank wipe revokes saved bank connections and removes linked accounts, their expense records, imported activity and local recovery copies. Delete All also removes manual records, photos, email suggestions and Gmail credentials on this device. Revoke Google access in your Google Account to remove the grant entirely. There is no online sign-in account in this personal edition. Independently exported backups remain yours to delete in Files.") }
        }.paperForm().navigationTitle(resetApp ? "Reset App" : "Privacy & Delete Data")
            .onAppear { if resetApp { bankOnly = false } }
            .confirmationDialog(remoteAccessUnknown ? "Delete device data? Old remote bank access cannot be revoked without connection settings." : bankOnly ? "Wipe bank data and revoke access?" : "Delete all Tender data and revoke bank access?", isPresented: $confirm, titleVisibility: .visible) {
                Button("Save Backup, Then Delete", role: .destructive) {
                    do { document = ExportDocument(data: try store.completeBackup()); exporter = true }
                    catch { store.error = "Backup could not be prepared. No data has been deleted." }
                }
                Button("Delete Without a Backup", role: .destructive) { Task { await erase() } }
                Button("Cancel", role: .cancel) {}
            }
            .fileExporter(isPresented: $exporter, document: document, contentType: .json, defaultFilename: "Tender-Before-Deletion.json") { result in
                if case .success = result { Task { await erase() } }
                else { message = "Backup was not saved. No deletion was performed." }
            }
    }
    private func erase() async {
        guard !busy, !store.bankUpdating, !store.gmail.busy else { return }
        busy = true; store.bankMaintenance = true; defer { busy = false; store.bankMaintenance = false }
        do {
            let unknown = remoteAccessUnknown
            if let config = BankConfiguration.load() { try await BankClient(configuration: config).disconnect() }
            try store.eraseLocalData(bankOnly: bankOnly)
            if resetApp {
                try await AppReset.forgetLoginAndPreferences()
                NotificationCenter.default.post(name: .resetToLogin, object: nil)
            }
            message = unknown ? "Device data removed. Old remote bank access could not be verified or revoked; manage it with the bank/provider." : bankOnly ? "Bank information removed and saved connections revoked." : "Tender data deleted. Restore a saved backup if you return, then reconnect your bank."
        } catch { message = "Deletion could not finish: " + error.localizedDescription + " Retry before assuming all data was removed." }
    }
}
