import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var fresh = false
    @State private var exporter = false
    @State private var importer = false
    @State private var restoreConfirm = false
    @State private var pendingRestore: Data?
    @State private var document = ExportDocument(data: Data())
    @State private var exportType = UTType.json
    @State private var filename = "Tender-Ledger.json"
    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) { Image(systemName: "seal").font(.largeTitle); VStack(alignment: .leading, spacing: 5) { Text("tender").font(.system(.title, design: .serif)); Text("A little more intentional.").font(.subheadline).foregroundStyle(.secondary) } }.padding(.vertical, 8)
                LabeledContent("Ledger", value: store.ledger.isDemo ? "Sample data" : "Personal · local storage")
                LabeledContent("Currency", value: "USD")
            }
            Section {
                Text("1. In Shortcuts, find Tender → Open Shopping Mode. Create a shortcut with that action.\n\n2. Open Settings → Accessibility → Touch → Back Tap → Triple Tap.\n\n3. Select your Shopping Mode shortcut.")
                Text("You can also use an Open URLs action with tender://shopping. Back Tap is configured by you in iOS Settings; the app cannot assign it automatically.").font(.footnote).foregroundStyle(.secondary)
                Link("Apple’s Back Tap instructions", destination: URL(string: "https://support.apple.com/guide/shortcuts/apd897693606/ios")!)
            } header: { Text("Triple-tap shopping shortcut") }
            Section {
                Button { exportCompleteBackup() } label: { Label("Export Backup with Bills & Photos", systemImage: "archivebox") }
                Button { exportJSON() } label: { Label("Export Ledger Only (JSON)", systemImage: "externaldrive") }
                Button { prepare(Data(store.csv().utf8), type: .commaSeparatedText, name: "Tender-Expenses.csv") } label: { Label("Export Expenses (CSV)", systemImage: "tablecells") }
                Button { prepare(Data(store.summary(days: 7).utf8), type: .plainText, name: "Tender-Weekly-Summary.txt") } label: { Label("Export Weekly Summary", systemImage: "calendar") }
                Button { prepare(Data(store.summary().utf8), type: .plainText, name: "Tender-Monthly-Summary.txt") } label: { Label("Export Monthly Summary", systemImage: "chart.bar.doc.horizontal") }
                Button { importer = true } label: { Label("Restore Ledger from JSON", systemImage: "arrow.clockwise.icloud") }
            } header: { Text("iCloud & analysis") } footer: { Text("Choose iCloud Drive in Files. The complete backup includes bills and photos (up to 60 MB of attachments). Ledger JSON, CSV, and summaries are smaller files for analysis. Share selected exports with Claude or ChatGPT; neither gets automatic access to iCloud. Exports are snapshots, not automatic sync.") }
            Section("Privacy") {
                Text("Expenses, bills, and price photos stay in the app’s Documents folder with iOS file protection. OCR runs on device. Bank Connect contacts Plaid through your configured bridge only when you use it. Tender does not upload your ledger to an AI service.")
                Text("Exports contain sensitive financial records. Share only the files you choose. Your iCloud and device backup behavior follows your Apple settings.").font(.footnote).foregroundStyle(.secondary)
            }
            if store.ledger.isDemo {
                Section {
                    NavigationLink("Remove Sample Data…") { SampleCleanupView() }
                } footer: { Text("Choose any real entries to keep. A local recovery copy is saved before sample data is removed.") }
            }
            Section {
                Button(store.ledger.isDemo ? "Start My Own Ledger" : "Reset to an Empty Ledger", role: .destructive) { fresh = true }.disabled(!store.storageHealthy)
            } footer: { Text("Keeps the default categories. Removes the current expenses, balances, recurring entries, and grocery list. Export first if you want to keep them.") }
        }.paperForm().navigationTitle("Settings").navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
            .fileExporter(isPresented: $exporter, document: document, contentType: exportType, defaultFilename: filename) { result in if case .failure = result { store.error = "Couldn’t export this file. Choose another Files location and try again." } }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.json]) { result in
                do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; let values = try url.resourceValues(forKeys: [.fileSizeKey]); guard (values.fileSize ?? 0) < LedgerArchive.maximumEncodedBytes else { throw LedgerError.invalidBackup }; pendingRestore = try Data(contentsOf: url); restoreConfirm = true }
                catch { store.error = "Couldn’t read this backup. Choose a Tender backup under 120 MB (ledger-only files must be under 30 MB)." }
            }
            .confirmationDialog("Replace your ledger with this backup? A copy of the current JSON will be kept on this device. Complete backups restore bill and price photos. Ledger-only exports do not include images.", isPresented: $restoreConfirm, titleVisibility: .visible) { Button("Replace Ledger", role: .destructive) { if let pendingRestore { store.restore(pendingRestore) }; pendingRestore = nil }; Button("Cancel", role: .cancel) { pendingRestore = nil } }
            .confirmationDialog("Start a fresh ledger? This removes the current ledger entries. Export a backup first if needed.", isPresented: $fresh, titleVisibility: .visible) { Button("Start Fresh", role: .destructive) { if store.update({ $0 = .empty() }) { Task { await store.refreshReminders() }; dismiss() } } }
    }
    private func exportCompleteBackup() {
        do { prepare(try store.completeBackup(), type: .json, name: "Tender-Complete-Backup.json") }
        catch { store.error = "Couldn’t create a complete backup. Check that all attached files are present and together are under 60 MB. You can still export the ledger on its own." }
    }
    private func exportJSON() { do { prepare(try JSONEncoder.tender.encode(store.ledger), type: .json, name: "Tender-Ledger.json") } catch { store.error = "Couldn’t prepare this backup." } }
    private func prepare(_ data: Data, type: UTType, name: String) { document = ExportDocument(data: data); exportType = type; filename = name; exporter = true }
}
