import SwiftUI

/// One consumer action: authorize with Plaid, then import automatically.
struct BankConnectionView: View {
    var itemID: String? = nil
    var startOnAppear = true
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @State private var hosted: HostedBankSession?
    @State private var operation: Task<Void, Never>?
    @State private var authentication = BankAuthenticationSession()
    @State private var working = false
    @State private var checking = false
    @State private var connected = false
    @State private var message: String?
    private var inAppEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "TenderInAppBankLogin") as? Bool == true }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "building.columns").font(.largeTitle).foregroundStyle(Ink.green)
                Text(itemID == nil ? "Import your bank account" : "Reconnect your bank").font(.system(.title, design: .serif))
                Text("Securely sign in through Plaid. Tender imports your accounts and keeps balances and bank activity updated automatically.")
                if working || checking { ProgressView(connected ? "Importing bank information…" : "Connecting securely…") }
                if store.bankIsOffline {
                    Label("You’re offline. Connect to the internet to import your bank account.", systemImage: "wifi.slash")
                } else if let message { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("bank-import-message") }
                if !working && !checking {
                    Button(connected ? "Try Again" : hosted == nil ? "Try Again" : "Continue Bank Login") { begin() }
                        .buttonStyle(PrimaryButton()).disabled(store.bankIsOffline)
                }
                Text("Your bank login is handled securely by Plaid.").font(.footnote).foregroundStyle(.secondary)
            }.padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
        }.paperForm().navigationTitle("Import Bank Account").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear { store.bankMaintenance = true; if startOnAppear { begin() } }
            .onDisappear { operation?.cancel(); authentication.cancel(); store.bankMaintenance = false }
            .onChange(of: phase) { _, value in
                if value == .active, hosted != nil, !working, !checking { operation?.cancel(); operation = Task { await verifyAndWait() } }
            }
            .onChange(of: store.bankNetwork.revision) { _, _ in
                if !store.bankIsOffline && !working && !checking {
                    if connected { operation = Task { await importAccounts() } }
                    else if hosted != nil { operation = Task { await verifyAndWait() } }
                    else { begin() }
                }
            }
            .onOpenURL { url in
                if let hosted, BankAuthenticationSession.matches(url, sessionID: hosted.id), !working, !checking {
                    operation?.cancel(); operation = Task { await verifyAndWait() }
                }
            }
    }
    private func begin() {
        operation?.cancel()
        operation = Task { await start() }
    }
    @MainActor private func start() async {
        guard !working, !checking else { return }
        working = true; message = nil
        do {
            guard !store.bankIsOffline else { throw BankError.offline }
            guard let client = store.bankClient else { throw BankError.message("Bank import is unavailable. Sign in to your Tender account and try again.") }
            if connected { working = false; await importAccounts(); return }
            var body = ["presentation": inAppEnabled ? "inApp" : "appReturn"]
            if let itemID { body["itemID"] = itemID }
            let session: HostedBankSession = try await client.call("v1/hosted-link", method: "POST", body: body)
            try Task.checkCancellation()
            guard let url = session.safeURL else { throw BankError.message("Bank login couldn’t open securely. Please try again.") }
            hosted = session; store.markBankImportPending(true)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--bank-import-test") {
                working = false; await verifyAndWait(); return
            }
            #endif
            if session.presentation == "inApp" { try await authentication.open(session) }
            else {
                let opened = await withCheckedContinuation { continuation in openURL(url) { continuation.resume(returning: $0) } }
                guard opened else { throw BankError.message("Bank login couldn’t open. Please try again.") }
            }
            try Task.checkCancellation()
            working = false
            message = "Finish signing in through Plaid. Your accounts will import automatically when you return."
            await verifyAndWait()
        } catch is CancellationError { working = false }
        catch { working = false; message = error.localizedDescription }
    }
    @MainActor private func verifyAndWait() async {
        guard !checking, let session = hosted, let client = store.bankClient else { return }
        checking = true
        defer { checking = false }
        do {
            for _ in 0..<20 {
                try Task.checkCancellation()
                let result: HostedBankResult = try await client.call("v1/hosted-link/finish", method: "POST", body: ["sessionID": session.id])
                try Task.checkCancellation()
                switch result.status {
                case "connected":
                    hosted = nil; connected = true; store.resumeBankAccess(); store.markBankImportPending(false)
                    await importAccounts(); return
                case "expired", "failed", "cancelled":
                    hosted = nil; store.markBankImportPending(false)
                    message = result.status == "expired" ? "This bank login expired. Please try again." : "Bank login wasn’t completed. Your saved accounts are unchanged. Please try again."
                    return
                default: break
                }
                try await Task.sleep(for: .seconds(3))
            }
        } catch is CancellationError { return }
        catch { message = error.localizedDescription }
    }
    @MainActor private func importAccounts() async {
        let success = await store.refreshBank(force: true, finishingImport: true)
        guard !Task.isCancelled else { return }
        if success { dismiss() }
        else { message = store.bankIsOffline ? "You’re offline. Your bank is connected; information will update when the internet returns." : store.bankMessage ?? "Your bank is connected. Information couldn’t update yet; Tender will retry automatically." }
    }
}

/// Shared freshness information, including across app relaunches.
struct BankSyncStatusView: View {
    @Environment(LedgerStore.self) private var store
    @State private var reconnect: BankReconnectRoute?
    var body: some View {
        if store.hasBankAccounts || store.hasPendingBankImport || store.bankMessage != nil {
            VStack(alignment: .leading, spacing: 10) {
                if store.bankIsOffline {
                    Label("You’re offline. Bank information may be outdated.", systemImage: "wifi.slash")
                        .foregroundStyle(Ink.warning).accessibilityIdentifier("bank-offline-warning")
                } else if !store.bankUpdating, let message = store.bankMessage { Text(message).foregroundStyle(Ink.warning) }
                else if !store.bankUpdating && store.hasPendingBankImport { Text("Waiting for bank login to finish. Accounts import automatically.") }
                HStack(spacing: 6) {
                    Text("Last updated")
                    if store.bankUpdating {
                        BankDateSkeleton().accessibilityIdentifier("bank-update-progress")
                    } else if let date = store.bankLastUpdated {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    } else { Text("Not updated yet") }
                }.foregroundStyle(.secondary)
                if !store.bankIsOffline {
                    ForEach(store.bankConnectionIssues.filter(\.requiresReauthentication)) { issue in
                        Button("Reconnect \(issue.name)") { reconnect = BankReconnectRoute(itemID: issue.itemID) }
                    }
                    if store.bankAccessPaused {
                        ForEach(store.bankConnections) { connection in
                            Button("Reconnect \(connection.name)") { reconnect = BankReconnectRoute(itemID: connection.id) }
                        }
                    }
                }
            }.font(.footnote)
                .sheet(item: $reconnect) { route in NavigationStack { BankConnectionView(itemID: route.itemID) } }
        }
    }
}
private struct BankReconnectRoute: Identifiable { var itemID: String; var id: String { itemID } }
