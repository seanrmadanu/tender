import SwiftUI

struct CardArtworkPicker: View {
    @Environment(LedgerStore.self) private var store
    let accountID: UUID
    private var account: Account? { store.ledger.accounts.first { $0.id == accountID } }
    private var catalog: CardArtworkCatalog { CardArtworkLibrary.catalog }
    var body: some View {
        List {
            if let account {
                Section {
                    Text(account.name).font(.headline)
                    LabeledContent("Current design", value: catalog.artwork(for: account)?.productName ?? "Standard display")
                    if let id = account.cardArtworkID, !catalog.choices(for: account).contains(where: { $0.id == id }) {
                        Text("Your selected design is no longer available. Choose another design or use the standard display.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section {
                    option("Automatic", subtitle: catalog.automaticArtwork(for: account)?.productName ?? "Use original artwork when an exact match is available.",
                           selected: account.cardArtworkID == nil && account.usesStandardCardDisplay != true,
                           choice: .automatic, identifier: "card-artwork-automatic")
                    option("Standard display", subtitle: "Show the account name and available balance.", selected: account.usesStandardCardDisplay == true,
                           choice: .standard, identifier: "card-artwork-standard")
                }
                let choices = catalog.choices(for: account)
                if choices.isEmpty {
                    Section {
                        Label("Original artwork isn’t available for this bank yet.", systemImage: "creditcard")
                        Text("Your card will use the standard display until a matching design is available.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(choices) { art in
                            Button {
                                _ = store.update { try $0.chooseCardArtwork(.artwork(art.id), accountID: accountID, catalog: catalog) }
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    CardArtworkThumbnail(artwork: art)
                                    HStack {
                                        Text(art.productName).foregroundStyle(.primary)
                                        Spacer()
                                        if account.cardArtworkID == art.id && account.usesStandardCardDisplay != true {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.green)
                                        }
                                    }
                                }.padding(.vertical, 8)
                            }.buttonStyle(.plain)
                                .accessibilityLabel(art.productName + (account.cardArtworkID == art.id ? ", selected" : ""))
                                .accessibilityIdentifier("card-artwork-" + art.id)
                        }
                    } header: { Text(account.bankDetails?.institutionName ?? "Card designs") }
                    footer: { Text("Choose the design that matches your card. A checking account name alone can’t identify its debit card design.") }
                }
            }
        }.paperForm().navigationTitle("Card design").navigationBarTitleDisplayMode(.inline)
    }
    private func option(_ title: String, subtitle: String, selected: Bool, choice: CardArtworkChoice, identifier: String) -> some View {
        Button {
            _ = store.update { try $0.chooseCardArtwork(choice, accountID: accountID, catalog: catalog) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.green) }
            }.frame(minHeight: 44)
        }.buttonStyle(.plain).accessibilityLabel(title + (selected ? ", selected" : "")).accessibilityIdentifier(identifier)
    }
}

struct CardArtworkThumbnail: View {
    let artwork: CardArtwork
    var body: some View {
        Image(artwork.assetName).resizable().scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel(artwork.issuer + " " + artwork.productName + " artwork")
    }
}
