import SwiftUI
import struct LinkKit.LinkTokenConfiguration
import class LinkKit.PlaidLinkSession
import struct LinkKit.Plaid

struct BankConnectionView: View {
    @Environment(LedgerStore.self) private var store
    @State private var server = ""
    @State private var token = ""
    @State private var configured = false
    @State private var busy = false
    @State private var message: String?
    @State private var linkSession: PlaidLinkSession?
    @State private var showingLink = false
    @State private var response: BankAccountsResponse?
    @State private var selected: BankSnapshot?
    @State private var disconnect = false
    @State private var connections: [BankConnection] = []
    @State private var confirmNew = false
    @State private var setupExpanded = true
    private var configuration: BankConfiguration { BankConfiguration(server: server.trimmingCharacters(in: .whitespacesAndNewlines), token: token.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var client: BankClient { BankClient(configuration: configuration) }
    var body: some View {
        Form {
            Section {
                Label(configured ? "Plaid bridge configured" : "Set up your bank connection", systemImage: "building.columns")
                Text("Connect checking and savings accounts through Plaid. Your bank login stays in Plaid’s secure flow. Retrieved balances are reviewed before you apply them to your ledger.").font(.subheadline).foregroundStyle(.secondary)
                Link("Open Plaid Dashboard", destination: URL(string: "https://dashboard.plaid.com")!)
            } footer: { Text("New US/Canada developers may qualify for Plaid’s free Trial with up to 10 bank connections. Check eligibility and current terms before selecting a paid plan.") }
            Section {
                DisclosureGroup("Connection Setup", isExpanded: $setupExpanded) {
                    Text("1. Add your Plaid keys to the private backend configuration.\n2. Run the bridge at an HTTPS address.\n3. Enter that address and the bridge access token below. Plaid API secrets stay on the backend.").font(.footnote).foregroundStyle(.secondary)
                    TextField("HTTPS bridge address", text: $server).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Bridge access token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Save Connection Settings") {
                        do { try configuration.save(); configured = true; setupExpanded = false; response = nil; connections = []; message = "Saved securely in this device’s Keychain." }
                        catch { message = error.localizedDescription }
                    }.disabled(configuration.url == nil || configuration.token.count < 32)
                }
                Button("Test Connection") { Task { await testConnection() } }.disabled(!configured || busy)
                Button(connections.isEmpty ? "Connect a Bank" : "Add Another Bank") { confirmNew = true }.disabled(!configured || busy)
                Button("Load Existing Connections") { Task { await loadConnections() } }.disabled(!configured || busy)
                Button("Load Cached Balances") { Task { await load(fresh: false) } }.disabled(!configured || busy)
                Button("Refresh Bank Balances") { Task { await load(fresh: true) } }.disabled(!configured || busy)
                if busy { ProgressView("Working with your bank service…") }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } footer: { Text("Refresh is included in the current free Trial; paid plans can charge per request. Use Repair Login for a bank you already connected. New connections consume Trial slots, even if later deleted.") }
            if !connections.isEmpty {
                Section("Connected banks (\(connections.count))") {
                    ForEach(connections) { connection in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(connection.name).font(.headline)
                            Button("Repair Login") { Task { await startLink(itemID: connection.id) } }.disabled(busy || !configured)
                                .accessibilityLabel("Repair login for \(connection.name)")
                        }
                    }
                }
            }
            if let response {
                Section {
                    Text(response.environment == "production" ? "Production bank data" : "Sandbox test data").font(.headline)
                    Text(response.cached ? "Cached snapshots may be out of date. Refresh before relying on them." : "Retrieved from the Balance endpoint. Bank pending-transaction behavior can vary.").font(.footnote).foregroundStyle(.secondary)
                    ForEach(Array(response.errors.enumerated()), id: \.offset) { _, error in Text(error).font(.footnote).foregroundStyle(Ink.warning) }
                    if response.accounts.isEmpty { Text("No checking or savings accounts returned.").foregroundStyle(.secondary) }
                    ForEach(response.accounts) { snapshot in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(snapshot.displayName).font(.headline)
                            LabeledContent("Available", value: snapshot.availableCents.map(Money.format) ?? "Unavailable")
                            LabeledContent("Current", value: snapshot.currentCents.map(Money.format) ?? "Unavailable")
                            Text("Retrieved \(snapshot.retrievedAt.formatted(date: .abbreviated, time: .shortened)) · \(snapshot.currency ?? "Unknown currency")").font(.caption).foregroundStyle(.secondary)
                            Button(store.ledger.accounts.contains { $0.bankAccountKey == response.environment + ":" + snapshot.id } ? "Update This Account…" : "Add This Account…") { selected = snapshot }
                                .disabled(snapshot.availableCents == nil || snapshot.currency != "USD" || response.environment != "production" || store.ledger.isDemo)
                        }.padding(.vertical, 5)
                    }
                } header: { Text("Bank snapshots") } footer: { Text("Only USD available balances can become ledger cash. Sandbox values are for connection testing and cannot be added to your ledger. No transactions are imported automatically.") }
            }
            if configured { Section { Button("Disconnect All Banks", role: .destructive) { disconnect = true }.disabled(busy) } footer: { Text("Revokes the backend’s Plaid connections. Previously applied ledger snapshots stay in your history.") } }
        }.paperForm().navigationTitle("Bank Connect").navigationBarTitleDisplayMode(.inline)
            .onAppear { if let saved = BankConfiguration.load() { server = saved.server; token = saved.token; configured = true; setupExpanded = false } }
            .confirmationDialog("Create a new bank connection? If this bank is already linked, cancel and use Load Existing Connections → Repair Login. New connections count toward your 10 Trial slots.", isPresented: $confirmNew, titleVisibility: .visible) {
                Button("Connect a New Bank") { Task { await startLink() } }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: server) { _, _ in configured = BankConfiguration.load()?.server == configuration.server && BankConfiguration.load()?.token == configuration.token }
            .onChange(of: token) { _, _ in configured = BankConfiguration.load()?.server == configuration.server && BankConfiguration.load()?.token == configuration.token }
            .sheet(isPresented: $showingLink) { linkSession?.sheet() }
            .sheet(item: $selected) { snapshot in NavigationStack { ApplyBankSnapshot(snapshot: snapshot, environment: response?.environment ?? "sandbox", cached: response?.cached ?? true) } }
            .confirmationDialog("Revoke all Plaid connections on your bridge? Trial connection slots won’t be restored.", isPresented: $disconnect, titleVisibility: .visible) { Button("Disconnect All Banks", role: .destructive) { Task { busy = true; defer { busy = false }; do { try await client.disconnect(); response = nil; connections = []; message = "Bank access revoked." } catch { message = error.localizedDescription } } } }
    }
    private func testConnection() async {
        busy = true; message = nil; defer { busy = false }
        do {
            let status: BankStatus = try await client.call("v1/status")
            message = "Bridge reached · " + (status.environment == "production" ? "Production" : "Sandbox test data") + " · \(status.connectionCount) saved bank connections." + (status.oauthConfigured ? "" : " OAuth domain/signing setup is still needed.")
        } catch { message = error.localizedDescription }
    }
    private func startLink(itemID: String? = nil) async {
        busy = true; message = nil; defer { busy = false }
        do {
            let result: LinkTokenResponse = try await client.call("v1/link-token", method: "POST", body: itemID.map { ["itemID": $0] })
            let config = LinkTokenConfiguration(token: result.linkToken, onSuccess: { success in
                showingLink = false
                Task {
                    busy = true; defer { busy = false }
                    do {
                        if itemID == nil { try await client.exchange(success.publicToken, institution: success.metadata.institution.name) }
                        // Update mode retains its original token; never exchange again.
                        await loadConnections()
                        await load(fresh: false)
                    } catch { message = "Link finished, but the bridge couldn’t store it. Check the bridge before connecting again." }
                }
            }, onExit: { exit in showingLink = false; if exit.error != nil { message = "Plaid couldn’t complete the connection. Check provider setup and try again." } }, onEvent: { _ in }, onLoad: {})
            linkSession = try Plaid.createPlaidLinkSession(configuration: config)
            showingLink = true
        } catch { message = error.localizedDescription }
    }
    private func loadConnections() async {
        busy = true; message = nil; defer { busy = false }
        do {
            let result: BankConnectionsResponse = try await client.call("v1/connections")
            connections = result.connections
            if connections.isEmpty { message = "No bank connections saved on this bridge." }
        } catch { message = error.localizedDescription }
    }
    private func load(fresh: Bool) async {
        busy = true; message = nil; defer { busy = false }
        do { response = try await client.call(fresh ? "v1/balances/refresh" : "v1/accounts", method: fresh ? "POST" : "GET") }
        catch { message = error.localizedDescription }
    }
}
struct ApplyBankSnapshot: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let snapshot: BankSnapshot
    let environment: String
    let cached: Bool
    @State private var account: UUID?
    private var bankKey: String { environment + ":" + snapshot.id }
    private var matchedAccount: Account? { store.ledger.accounts.first { $0.bankAccountKey == bankKey } }
    var body: some View {
        Form {
            Section { LabeledContent(snapshot.displayName, value: snapshot.availableCents.map(Money.format) ?? "Unavailable"); Text(cached ? "This is a cached bank snapshot and may be stale." : "This replaces the selected account’s recorded cash balance.").foregroundStyle(.secondary) }
            Section {
                if let matchedAccount {
                    LabeledContent("Linked ledger account", value: matchedAccount.name)
                    Text("Updates the existing account without creating duplicate cash.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Picker("Apply to", selection: $account) { Text("Create a new account").tag(UUID?.none); ForEach(store.ledger.accounts.filter { $0.bankAccountKey == nil }) { Text($0.name).tag(Optional($0.id)) } }
                }
            } footer: { Text("Select your existing account if you already entered this bank manually, to avoid counting it twice. Expenses stay unchanged. Pending purchases missing from this bank balance still need to be accounted for.") }
        }.paperForm().navigationTitle("Apply Bank Snapshot").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Apply") {
                guard snapshot.availableCents != nil else { return }
                if store.update({ ledger in
                    try ledger.applyBankSnapshot(snapshot, environment: environment, matching: account)
                }) { dismiss() }
            } } }
    }
}
