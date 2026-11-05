import SwiftUI
import UserNotifications

struct AIConnectionsView: View {
    @State private var fixturePendingCount = -1
    @Environment(LedgerStore.self) private var store
    @State private var connections: [AIConnection] = []
    @State private var configured = false
    @State private var checking = false
    @State private var message: String?
    @State private var code = ""
    @State private var authorization: AIAuthorizationRequest?
    @State private var enable = false
    @State private var conflictChoice: Bool?
    private var validCode: String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = URLComponents(string: trimmed)?.queryItems?.first(where: { $0.name == "request" })?.value ?? trimmed
        return parsed.range(of: "^[a-fA-F0-9]{64}$", options: .regularExpression) == nil ? nil : parsed.lowercased()
    }
    var body: some View {
        Form {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ai-connections-test") && store.cloudState.enabled {
                Button("Add synthetic ChatGPT purchase") { Task { try? AIConnectionsFixture.addPurchase(); await store.synchronizeCloud() } }.accessibilityIdentifier("ai-fixture-purchase")
                Button("Add synthetic Claude fixed expense") { Task { try? AIConnectionsFixture.addFixedExpense(); await store.synchronizeCloud() } }.accessibilityIdentifier("ai-fixture-fixed")
                Button("Add synthetic app changes") { Task { try? AIConnectionsFixture.addAppChanges(); await store.synchronizeCloud() } }.accessibilityIdentifier("ai-fixture-app-settings")
                if ProcessInfo.processInfo.arguments.contains("--ai-reminder-test") {
                    Button("Seed reminder conflict") { Task { do { try await AIConnectionsFixture.seedReminderConflict(store: store) } catch { store.error = error.localizedDescription } } }.accessibilityIdentifier("ai-fixture-reminder-conflict")
                    if store.cloudConflict != nil { Button("Resolve synthetic conflict with cloud") { Task { await store.resolveCloudConflict(usePhone: false) } }.accessibilityIdentifier("ai-fixture-resolve-cloud") }
                    Button("Check pending test reminders") { Task { fixturePendingCount = await UNUserNotificationCenter.current().pendingNotificationRequests().filter { $0.identifier == "ai-conflict-fixture" }.count } }.accessibilityIdentifier("ai-check-pending-reminders")
                    Text("\(fixturePendingCount) scheduled test reminders").accessibilityIdentifier("ai-pending-count")
                }
            }
            #endif
            Section {
                Label(store.cloudState.enabled ? "Cloud sync is on" : "Stored on this phone", systemImage: store.cloudState.enabled ? "checkmark.icloud" : "iphone")
                Text("Connect Tender to ChatGPT to manage purchases, groceries, subscriptions, budgets, reports, your profile, preferences and Archive from your conversations. Changes save immediately and show the assistant’s logo. Edit or delete them in Tender.").font(.subheadline)
                if store.cloudState.enabled {
                    Button("Sync now", systemImage: "arrow.triangle.2.circlepath") { Task { await store.synchronizeCloud(); await refreshConnections() } }.accessibilityIdentifier("ai-sync-now")
                    Button("Disconnect all AI access", role: .destructive) { Task { await store.disconnectAllAI(); await refreshConnections() } }
                } else {
                    Button("Enable AI Connections", systemImage: "icloud") { enable = true }.disabled(!configured || !store.canConnectAI).accessibilityIdentifier("ai-enable")
                }
                if store.cloudBusy { ProgressView("Syncing your ledger…") }
                if let warning = store.cloudMessage { Text(warning).font(.footnote).foregroundStyle(Ink.warning) }
                if !store.canConnectAI { Text("Sign in to your Tender account to enable connections.").font(.footnote) }
                if !configured {
                    Text("The cloud connection service is not ready or could not be reached. Your phone ledger stays available.").font(.footnote).foregroundStyle(Ink.muted)
                    Button("Check connection service") { Task { await refresh() } }.disabled(checking)
                }
            } footer: { Text("Enabling shares this account’s ledger—including balances, purchases, budgets and notes—with Tender’s cloud service. Receipt and profile-photo files stay on this phone. Each AI gets access only after you approve its connection. You can disconnect access here at any time.") }
            if store.cloudConflict != nil {
                Section("Sync needs review") {
                    Text("The phone and cloud contain conflicting edits. Recovery copies of both will be kept before you choose a version.")
                    LabeledContent("Phone purchases", value: String(store.ledger.expenses.count))
                    LabeledContent("Cloud purchases", value: String(store.cloudConflict?.ledger?.expenses.count ?? 0))
                    Button("Keep phone version") { conflictChoice = true }
                    Button("Use cloud version") { conflictChoice = false }
                }
            }
            Section("Connect your assistant") {
                ForEach([AssistantProvider.chatgpt, .claude], id: \.self) { provider in
                    HStack { AssistantMark(provider: provider, size: 24); Text(provider.name); Spacer(); Text(connections.contains { $0.provider == provider } ? "Connected" : "Not connected").font(.caption).foregroundStyle(Ink.muted) }
                }
                Text("In ChatGPT on the web, add Tender using Add custom MCP server in Plugins. In Claude, add a custom connector in Connectors. Use this server address:").font(.footnote)
                Text(AIConnectionsClient.server + "/mcp").font(.caption.monospaced()).textSelection(.enabled)
                Button("Copy server address", systemImage: "doc.on.doc") { UIPasteboard.general.string = AIConnectionsClient.server + "/mcp" }
                Text("Their sign-in window gives you a connection code. On iPhone, Open Tender fills it automatically. From a computer, paste the code here.").font(.footnote)
                TextField("Connection code", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable).accessibilityIdentifier("ai-connection-code")
                Button("Review connection") { Task { await openCode() } }.disabled(validCode == nil || !store.canConnectAI || checking)
                if let message { Text(message).font(.footnote).foregroundStyle(Ink.warning) }
            }
            if !connections.isEmpty {
                Section("Connected access") {
                    ForEach(connections) { connection in
                        HStack {
                            AssistantMark(provider: connection.provider); Text(connection.provider.name); Spacer()
                            Button("Disconnect", role: .destructive) { Task {
                                do { let _: AIEmptyResponse = try await store.aiClient.call("v3/connections/" + connection.id, method: "DELETE"); await refreshConnections() }
                                catch { message = error.localizedDescription }
                            } }.buttonStyle(.borderless)
                        }
                    }
                }
            }
            if !store.cloudState.events.isEmpty {
                Section("Recent AI changes") {
                    ForEach(store.cloudState.events.suffix(20).reversed()) { event in
                        HStack(alignment: .top) { AssistantMark(provider: event.provider); VStack(alignment: .leading) { Text(event.title); Text(event.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Ink.muted) } }
                    }
                }
            }
        }.paperForm().navigationTitle("AI Connections").navigationBarTitleDisplayMode(.inline)
            .disabled(store.cloudBusy)
            .task { await refresh(); await openPending() }
            .onChange(of: store.pendingAIAuthorization) { _, _ in Task { await openPending() } }
            .confirmationDialog("Enable cloud connections?", isPresented: $enable, titleVisibility: .visible) {
                Button("Enable and sync this account") { Task { await store.synchronizeCloud(enabling: true); await refreshConnections() } }.accessibilityIdentifier("ai-confirm-enable")
                Button("Cancel", role: .cancel) {}
            } message: { Text("Your ledger will be saved to your private Tender cloud account. AI tools can read or update it only after you approve each connection.") }
            .confirmationDialog("Resolve this sync conflict?", isPresented: Binding(get: { conflictChoice != nil }, set: { if !$0 { conflictChoice = nil } }), titleVisibility: .visible) {
                Button("Use selected version") { if let choice = conflictChoice { conflictChoice = nil; Task { await store.resolveCloudConflict(usePhone: choice) } } }
                Button("Cancel", role: .cancel) { conflictChoice = nil }
            } message: { Text("The selected version will replace conflicting records. Recovery copies are kept in Tender’s local files.") }
            .sheet(item: $authorization) { item in NavigationStack { AIConnectionApproval(request: item) { Task { await refreshConnections() } } } }
    }
    private func refresh() async {
        checking = true; defer { checking = false }
        do { let health: AIServiceStatus = try await store.aiClient.call("health", authenticated: false); configured = health.configured }
        catch { configured = false }
        if store.canConnectAI { await refreshConnections() }
    }
    private func refreshConnections() async {
        do { let result: AIConnectionList = try await store.aiClient.call("v3/connections"); connections = result.connections }
        catch { if store.cloudState.enabled { message = "Could not check connected access. Retry while online." } }
    }
    private func openPending() async { if let pending = store.pendingAIAuthorization { code = pending; store.pendingAIAuthorization = nil; await openCode() } }
    private func openCode() async {
        guard let validCode else { return }
        checking = true; defer { checking = false }
        do { authorization = try await store.aiClient.call("v3/authorize/" + validCode); message = nil }
        catch { message = error.localizedDescription }
    }
}

private struct AIConnectionApproval: View {
    @Environment(LedgerStore.self) private var store
    @Environment(AccountAuth.self) private var auth
    @Environment(\.dismiss) private var dismiss
    var request: AIAuthorizationRequest
    var finished: () -> Void
    @State private var busy = false
    @State private var approved = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Label { Text(request.clientName).font(.headline) } icon: { AssistantMark(provider: request.provider, size: 28) }
                LabeledContent("Return address", value: request.redirectHost)
                if let domain = request.clientDomain { LabeledContent("Published identity", value: domain) }
                else { Text("The client name is self-reported. Approve only the connection you just started at the return address above.").font(.footnote) }
                Text("Sharing as \(auth.email)").font(.footnote)
                Text(request.scopes.contains("ledger.write") ? "Can read and immediately update supported app information, including purchases, groceries, recurring payments, budgets, profile, preferences and Archive. Those items show the connection’s source badge and use normal edit/delete controls." : "Can read the account balances, budgets and purchases you ask about.")
                Text("Bank access is limited to bank names and balances. Cannot retrieve account/card numbers or credentials, send payments, reset Tender or delete all data. Camera/photos, sign-in and system permissions stay in Tender.").font(.footnote)
            }
            if approved {
                Section { Text("Approved. Return to the original ChatGPT or Claude sign-in window to finish connecting."); Button("Done") { dismiss() } }
            } else {
                Section {
                    Button(store.cloudState.enabled ? "Approve connection" : "Enable cloud and approve connection") { Task {
                        busy = true; defer { busy = false }
                        if !store.cloudState.enabled { await store.synchronizeCloud(enabling: true) }
                        guard store.cloudState.enabled, store.cloudConflict == nil else { error = store.cloudMessage ?? "Resolve the cloud sync conflict first."; return }
                        do { let _: AIEmptyResponse = try await store.aiClient.call("v3/authorize/" + request.id, method: "POST"); approved = true; finished() }
                        catch { self.error = error.localizedDescription }
                    } }
                    if !store.cloudState.enabled { Text("This also saves this account’s ledger, including balances and notes, to your private Tender cloud account. Receipt/photo files stay here.").font(.footnote) }
                    if busy { ProgressView("Connecting…") }
                    if let error { Text(error).foregroundStyle(Ink.warning) }
                }
            }
        }.paperForm().navigationTitle("Connect " + request.provider.name).navigationBarTitleDisplayMode(.inline)
            .disabled(busy).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
    }
}
