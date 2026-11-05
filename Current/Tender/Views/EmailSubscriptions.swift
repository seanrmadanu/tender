import SwiftUI

struct EmailSubscriptionsView: View {
    @Environment(LedgerStore.self) private var store
    @State private var review: SubscriptionEmail?
    @State private var consent = false
    @State private var disconnect: String?
    var body: some View {
        List {
            Section {
                Text("Find free trials, renewals and cancellation notices across your Gmail addresses. Connecting email is optional; bank estimates and manual tracking still work.")
                if !store.gmail.configured {
                    Label("Gmail setup required", systemImage: "wrench.and.screwdriver")
                    Text("This build needs a Google iOS OAuth client and callback scheme before you can connect. You can paste a notice below in the meantime.").font(.footnote)
                }
                Button("Connect Gmail", systemImage: "envelope.badge") { consent = true }.disabled(!store.gmail.configured || store.gmail.busy)
                Button("Check Emails", systemImage: "arrow.clockwise") { Task { await store.gmail.refresh(store: store, force: true) } }.disabled(store.gmail.busy || !store.gmail.configured || (store.ledger.subscriptionMailboxes ?? []).isEmpty)
                NavigationLink("Paste a subscription notice") { PasteSubscriptionNotice() }
                if store.gmail.busy { ProgressView("Checking email access…") }
                if let message = store.gmail.message { Text(message).font(.footnote).foregroundStyle(Ink.muted) }
            }
            Section("Connected addresses") {
                ForEach(store.ledger.subscriptionMailboxes ?? []) { mailbox in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(mailbox.id)
                        Text(mailbox.checkedAt.map { "Checked " + $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not checked yet").font(.caption)
                        Button("Disconnect", role: .destructive) { disconnect = mailbox.id }.disabled(store.gmail.busy)
                    }
                }
            }
            Section("Needs review") {
                let pending = (store.ledger.subscriptionEmails ?? []).filter { !$0.reviewed }.sorted { $0.received > $1.received }
                if pending.isEmpty { Text("No new notices. Connect an address or paste an email to get started.") }
                ForEach(pending) { email in
                    Button { review = email } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(email.kind == "cancellation" ? "Cancellation detected" : email.kind == "trial" ? "Possible free trial" : "Possible renewal").font(.headline)
                            Text(email.subject).lineLimit(3)
                            Text(email.mailbox).font(.caption).foregroundStyle(Ink.muted)
                        }
                    }
                }
            }
            Section { Text("Email content can be wrong or misleading. Sender names are not proof of identity. Review dates, prices and service names before confirming. Tender does not open email links, send mail, or cancel services for you. Disconnect stops this device's access; your Google Account lets you revoke the grant entirely.").font(.footnote) }
        }.paperForm().navigationTitle("Subscription Emails")
            .confirmationDialog("Allow optional Gmail scanning?", isPresented: $consent, titleVisibility: .visible) {
                Button("Continue to Google") { Task { await store.gmail.connect(store: store) } }
            } message: { Text("Google's read-only permission can read your mailbox, not only receipts. Tender searches up to 500 matching messages from the last year per address, parses them on this iPhone, and saves only review details—not full bodies or attachments. Details are included in backups you explicitly export. Each address connects separately.") }
            .confirmationDialog("Disconnect this address?", isPresented: Binding(get: { disconnect != nil }, set: { if !$0 { disconnect = nil } }), titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { if let email = disconnect { store.gmail.disconnect(email, store: store) }; disconnect = nil }
            } message: { Text("Pending email suggestions for this address are removed. Confirmed subscriptions and their source labels stay.") }
            .sheet(item: $review) { email in NavigationStack { ReviewSubscriptionEmail(email: email) } }
    }
}
struct PasteSubscriptionNotice: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var service = ""
    @State private var text = ""
    var body: some View {
        Form {
            TextField("Service name", text: $service)
            TextField("Paste trial, renewal or cancellation text", text: $text, axis: .vertical).lineLimit(6...12)
            Text("Parsed on this device. A short preview and extracted details are saved.").font(.caption)
            Button("Find Subscription Details") {
                guard let email = SubscriptionEmailParser.parse(id: UUID().uuidString, mailbox: "Pasted notice", sender: service, subject: String(text.prefix(120)), body: text, received: Date()) else { store.error = "No trial, subscription or renewal wording was found. You can add a recurring payment manually."; return }
                if store.update({ if $0.subscriptionEmails == nil { $0.subscriptionEmails = [] }; $0.subscriptionEmails?.append(email) }) { dismiss() }
            }.disabled(service.isEmpty || text.isEmpty)
        }.paperForm().navigationTitle("Import Notice")
    }
}
struct ReviewSubscriptionEmail: View {
    @Environment(LedgerStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let email: SubscriptionEmail
    @State private var name = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var dateConfirmed = false
    @State private var cycle = BillingCycle.monthly
    @State private var match: UUID?
    @State private var remind = false
    @State private var saving = false
    var body: some View {
        Form {
            Section("Email detected · review required") {
                Text(email.subject); Text(email.mailbox).font(.caption)
                Text("Received " + email.received.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                Picker("Subscription", selection: $match) {
                    Text(email.kind == "cancellation" ? "Choose the cancelled subscription" : "Create separate subscription").tag(UUID?.none)
                    ForEach(store.ledger.recurring) { Text($0.name + ($0.sourceMailbox.map { " · " + $0 } ?? "")).tag(Optional($0.id)) }
                }
                if email.kind != "cancellation" {
                    TextField("Service name", text: $name)
                    TenderField("Renewal price in USD", text: $amount, numeric: true)
                    DatePicker(email.kind == "trial" ? "Trial ends" : "Next renewal", selection: $date, displayedComponents: .date)
                    Toggle("I checked this date", isOn: $dateConfirmed)
                    Picker("Billing frequency", selection: $cycle) { ForEach(BillingCycle.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Toggle(email.kind == "trial" ? "Remind me 3 days before" : "Remind me 1 day before", isOn: $remind)
                    Text("Unknown prices and dates need your review. Saving updates the subscription only; it does not record a payment. Trials without a known price are excluded from estimated costs.").font(.caption)
                } else { Text("Confirming stops Tender's reminders. It does not cancel anything with the provider.") }
                Button(email.kind == "cancellation" ? "Confirm Cancellation" : "Confirm Subscription") { Task { await confirm() } }
                    .disabled(saving || (email.kind == "cancellation" ? match == nil : name.trimmingCharacters(in: .whitespaces).isEmpty || !dateConfirmed || !((Money.cents(amount) ?? 0) > 0 || (email.kind == "trial" && amount.isEmpty))))
                Button("Ignore Notice") { finish() }.disabled(saving)
            }
        }.paperForm().navigationTitle("Review Notice").toolbar { Button("Close") { dismiss() } }
            .onAppear { name = email.merchant; amount = email.amount.map(Money.input) ?? ""; date = email.date ?? Date(); cycle = email.cycle ?? .monthly }
    }
    private func finish() { if store.update({ ledger in if let i = ledger.subscriptionEmails?.firstIndex(where: { $0.id == email.id }) { ledger.subscriptionEmails?[i].reviewed = true } }) { dismiss() } }
    private func confirm() async {
        saving = true; defer { saving = false }
        if remind && email.kind != "cancellation" { guard await store.enableReminders() else { return } }
        if store.update({ ledger in
            if email.kind == "cancellation" {
                guard let i = ledger.recurring.firstIndex(where: { $0.id == match }) else { throw LedgerError.invalidExpense }
                ledger.recurring[i].cancelledAt = min(email.received, Date()); ledger.recurring[i].remind = false
                ledger.recurring[i].source = "Cancellation confirmed from email"
                ledger.recurring[i].sourceMailbox = email.mailbox; ledger.recurring[i].sourceEvidenceID = email.id
            } else {
                let existing = ledger.recurring.first { $0.id == match }
                var bill = existing ?? RecurringBill(name: name, amount: 0, categoryID: ledger.ensureCategory(named: "Uncategorized"), nextDue: date)
                bill.name = name; bill.amount = Money.cents(amount) ?? 0; bill.renewalAmountUnknown = amount.isEmpty
                bill.nextDue = date; bill.cycle = cycle; bill.recurrenceAnchor = date; bill.remind = remind
                bill.trialEndsAt = email.kind == "trial" ? date : nil
                bill.cancelledAt = nil; bill.source = "Email detected · user confirmed"; bill.sourceMailbox = email.mailbox; bill.sourceEvidenceID = email.id
                if let i = ledger.recurring.firstIndex(where: { $0.id == bill.id }) { ledger.recurring[i] = bill } else { ledger.recurring.append(bill) }
            }
            if let i = ledger.subscriptionEmails?.firstIndex(where: { $0.id == email.id }) { ledger.subscriptionEmails?[i].reviewed = true }
        }) { await store.refreshReminders(); dismiss() }
    }
}
