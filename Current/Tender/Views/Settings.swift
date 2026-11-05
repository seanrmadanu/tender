import SwiftUI
import UniformTypeIdentifiers
import QuickLook
enum SettingsRoute: Hashable { case profile, aiConnections, accounts, updates, archive, backup, privacy }

struct SettingsView: View {
    @Environment(AccountAuth.self) private var auth
    @State private var resetting = false
    @Environment(LedgerStore.self) private var store
    var body: some View {
        Form {
            Section {
                NavigationLink { ProfileSettingsView() } label: { ProfileIdentityHeader() }
                    .accessibilityIdentifier("profile-settings-header")
                    .listRowInsets(EdgeInsets())
            }
            Section("Signed in") {
                Text(auth.email)
                Button("Sign Out", role: .destructive) { auth.signOut() }
                    .disabled(auth.busy || store.gmail.busy || store.bankUpdating || store.bankMaintenance)
                if let message = auth.message { Text(message).font(.caption) }
            }
            Section("Your money") {
                NavigationLink { AccountForm() } label: { Label("Accounts & Cash Wallet", systemImage: "wallet.bifold") }
                NavigationLink { EmailSubscriptionsView() } label: { Label("Subscription Emails", systemImage: "envelope") }
                NavigationLink { AIConnectionsView() } label: { Label("AI Connections", systemImage: "sparkles") }.accessibilityIdentifier("ai-connections-settings")
            }
            Section("Preferences") {
                NavigationLink { ProfileSettingsView() } label: { Label("Profile", systemImage: "person.crop.square") }
                    .accessibilityIdentifier("profile-settings")
                NavigationLink { UpdateSettingsView() } label: { Label("Bank Updates & Reminders", systemImage: "arrow.triangle.2.circlepath") }
                NavigationLink { ShortcutSettingsView() } label: { Label("Shopping Shortcut", systemImage: "hand.tap") }
            }
            Section("Your data") {
                NavigationLink { ArchiveSettingsView() } label: { Label("Archive", systemImage: "archivebox") }
                NavigationLink { BackupSettingsView() } label: { Label("Backup & Restore", systemImage: "icloud") }
                NavigationLink { PrivacySettingsView() } label: { Label("Privacy & Delete Data", systemImage: "lock.shield") }
                Button(role: .destructive) { resetting = true } label: { Label("Reset App", systemImage: "arrow.counterclockwise") }
                if store.ledger.isDemo { NavigationLink("Review Old Sample Data") { SampleCleanupView() } }
            }
            Section { Text("Your ledger is stored on this device for this account. Gmail access is optional. Connect your bank through Plaid for bank updates, or keep accounts and cash up to date manually.").font(.footnote).foregroundStyle(.secondary) }
            Section {
                LabeledContent("Version", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("installed-app-version")
            }
        }.paperForm().navigationTitle("Settings")
            .task { await auth.loadProfileIfNeeded() }
            .sheet(isPresented: $resetting) { NavigationStack { PrivacySettingsView(resetApp: true).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { resetting = false } } } } }
    }
}
struct UpdateSettingsView: View {
    @Environment(LedgerStore.self) private var store
    var body: some View {
        Form {
            Section {
                Text("Bank balances and activity update automatically when you open Tender, every five minutes while it is active, and after the internet reconnects. Banks can take time to post changes.")
                BankSyncStatusView()
                Text("Without internet, Tender keeps your last saved information and shows when it was updated.").font(.footnote)
            } header: { Text("Bank freshness") }
            Section {
                Toggle("Shopping & recurring reminders", isOn: Binding(get: { store.ledger.appPreferences?.remindersEnabled ?? true }, set: { value in
                    let saved = store.update { ledger in
                        if ledger.appPreferences == nil { ledger.appPreferences = AppPreferences() }
                        ledger.appPreferences?.remindersEnabled = value
                    }
                    if saved { Task { await store.refreshReminders() } }
                })).accessibilityIdentifier("app-reminders-enabled")
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
    private var remoteAccessUnknown: Bool { !store.isAccountLedger && BankConfiguration.load() == nil && (resetApp || store.ledger.accounts.contains { $0.bankAccountKey != nil }) }
    var body: some View {
        Form {
            Section("Protection") {
                Text("Bank credentials stay in the encrypted backend vault. Device access uses Keychain; ledger and receipt files use iOS file protection. Photo recognition and this app’s shopping speech recognition run on device.")
                Text("AI Connections is optional. Approved assistants can use your shared app information, including bank names and balances. Bank account/card numbers and connection credentials are excluded from AI tools. Receipt and profile-photo files stay on this device. Your exported backups follow your own storage settings.").font(.footnote)
            }
            Section {
                if !resetApp { Button("Wipe My Bank Information", role: .destructive) { bankOnly = true; confirm = true }.disabled(busy || store.bankUpdating || store.gmail.busy) }
                Button(resetApp ? "Reset App" : "Delete All My Tender Data", role: .destructive) { bankOnly = false; confirm = true }.disabled(busy || store.bankUpdating || store.gmail.busy)
                if resetApp { Text("Forgets your saved Tender login, clears all local Tender accounts, ledgers, receipts, credentials, preferences and notifications, revokes saved bank connections, and returns to the login page. You will need to sign in again. Exported backups remain in Files. Your online Firebase account remains; you can sign in again to start a fresh local ledger.").font(.footnote) }
                if remoteAccessUnknown { Text("No connection credentials are saved. Deletion can remove device data, but cannot verify or revoke old remote bank access.").font(.footnote).foregroundStyle(Ink.warning) }
                if busy { ProgressView("Revoking bank access and deleting data…") }
                if let message { Text(message).font(.footnote) }
            } footer: { Text("Bank wipe revokes saved bank connections and removes linked accounts, their expense records, imported activity and local recovery copies. Delete All also removes manual records, photos, email suggestions and Gmail credentials on this device. Revoke Google access in your Google Account to remove the grant entirely. Reset signs you out; it does not delete your Firebase account. Independently exported backups remain yours to delete in Files.") }
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
            if store.isAccountLedger {
                if bankOnly { try await store.wipeCloudBankRecords() }
                else { try await store.eraseCloudLedger() }
                guard let client = store.bankClient else { throw BankError.message("Sign in again before removing bank access.") }
                try await client.disconnect()
            }
            if resetApp || !store.isAccountLedger { if let config = BankConfiguration.load() { try await BankClient(configuration: config).disconnect() } }
            try store.eraseLocalData(bankOnly: bankOnly)
            if resetApp {
                try await AppReset.forgetLoginAndPreferences()
                NotificationCenter.default.post(name: .resetToLogin, object: nil)
            }
            message = unknown ? "Device data removed. Old remote bank access could not be verified or revoked; manage it with the bank/provider." : bankOnly ? "Bank information removed and saved connections revoked." : "Tender data deleted. Restore a saved backup if you return, then reconnect your bank."
        } catch { message = "Deletion could not finish: " + error.localizedDescription + " Retry before assuming all data was removed." }
    }
}

struct ArchiveSettingsView: View {
    @Environment(LedgerStore.self) private var store
    var body: some View {
        List {
            Section { Text("Restore items you removed from Tender. Restoring a manual expense reapplies its balance deduction only while its original balance snapshot is still current.").font(.footnote) }
            Section("Envelopes") {
                ForEach(store.ledger.archivedItems?.envelopes ?? []) { item in
                    restoreRow(item.category.name) { _ = store.update { $0.restoreCategory(item.id) } }
                }
                if (store.ledger.archivedItems?.envelopes ?? []).isEmpty { Text("No archived envelopes").foregroundStyle(.secondary) }
            }
            Section("Expenses") {
                ForEach(store.ledger.archivedItems?.expenses ?? []) { item in
                    restoreRow(item.expense.merchant + " · " + Money.format(item.expense.amount)) { _ = store.update { try $0.restoreExpense(item.id) } }
                }
                if (store.ledger.archivedItems?.expenses ?? []).isEmpty { Text("No archived expenses").foregroundStyle(.secondary) }
            }
            Section("Fixed expenses") {
                ForEach((store.ledger.fixedExpenses ?? []).filter { $0.archivedAt != nil }) { fixed in
                    restoreRow(fixed.name) { _ = store.update { ledger in if let index = ledger.fixedExpenses?.firstIndex(where: { $0.id == fixed.id }) { ledger.fixedExpenses?[index].archivedAt = nil } } }
                }
                if !(store.ledger.fixedExpenses ?? []).contains(where: { $0.archivedAt != nil }) { Text("No archived fixed expenses").foregroundStyle(.secondary) }
            }
            Section("Subscriptions & recurring payments") {
                ForEach(store.ledger.archivedItems?.recurring ?? []) { item in
                    restoreRow(item.name) { if store.update({ $0.restoreRecurring(item.id) }) { Task { await store.refreshReminders() } } }
                }
                if (store.ledger.archivedItems?.recurring ?? []).isEmpty { Text("No archived payments").foregroundStyle(.secondary) }
            }
            Section("Groceries") {
                ForEach(store.ledger.archivedItems?.groceries ?? []) { item in
                    restoreRow(item.name) { if store.update({ $0.restoreGrocery(item.id) }) { Task { await store.refreshReminders() } } }
                }
                if (store.ledger.archivedItems?.groceries ?? []).isEmpty { Text("No archived groceries").foregroundStyle(.secondary) }
            }
            Section("Accounts & cards") {
                ForEach(store.ledger.accounts.filter { $0.isArchived == true }) { item in
                    HStack {
                        NavigationLink { ArchivedCardDetailView(accountID: item.id) } label: { Text(item.name) }
                        Button("Restore") { _ = store.update { try $0.restoreCardAndHistory(item.id) } }
                            .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("restore-card-" + item.id.uuidString)
                    }
                }
                if !store.ledger.accounts.contains(where: { $0.isArchived == true }) { Text("No archived accounts").foregroundStyle(.secondary) }
            }
        }.paperForm().navigationTitle("Archive")
    }
    private func restoreRow(_ name: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(name); Spacer()
            Button("Restore", action: action).buttonStyle(.bordered).frame(minHeight: 44)
        }
    }
}

struct ArchivedCardDetailView: View {
    @Environment(LedgerStore.self) private var store
    let accountID: UUID
    @State private var preview: URL?
    private var account: Account? { store.ledger.accounts.first { $0.id == accountID } }
    private var history: ArchivedCardHistory? { store.ledger.archivedCards?.first { $0.id == accountID } }
    var body: some View {
        List {
            Section {
                Text("This card’s saved information is kept here until you restore it.").font(.footnote)
                Text("Saved balance: " + Money.format(account?.available ?? 0))
            }
            Section("Bank transactions") {
                ForEach((history?.bankItems ?? []).flatMap(\.transactions).sorted { $0.date > $1.date }) { transaction in
                    VStack(alignment: .leading, spacing: 8) {
                        BankActivityRow(transaction: transaction)
                        if let details = history?.details[transaction.id] {
                            if !details.note.isEmpty { Text(details.note).font(.subheadline) }
                            ForEach(details.attachments, id: \.self) { file in
                                Button("View receipt") { preview = store.attachmentURL(file) }
                            }
                        }
                    }
                }
            }
            Section("Manual & categorized expenses") {
                ForEach(history?.expenses ?? []) { expense in
                    VStack(alignment: .leading, spacing: 8) {
                        ExpenseListRow(expense: expense)
                        if !expense.note.isEmpty { Text(expense.note).font(.subheadline) }
                        if let file = expense.attachment { Button("View receipt") { preview = store.attachmentURL(file) } }
                    }
                }
            }
            Section("Related groceries") { ForEach(history?.groceries ?? []) { Text($0.name) } }
            Section("Related recurring payments") { ForEach(history?.recurring ?? []) { Text($0.name) } }
        }.paperForm().navigationTitle(account?.name ?? "Archived card")
            .quickLookPreview($preview)
    }
}
