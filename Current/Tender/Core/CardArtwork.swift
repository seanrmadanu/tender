import Foundation

/// Only entries with recorded display and overlay permission can enter the app catalog.
/// Approval evidence is reviewed by a person; these fields are not a substitute for that review.
struct CardArtwork: Codable, Equatable, Identifiable, Sendable {
    struct Permission: Codable, Equatable, Sendable {
        var status: String
        var rightsHolder: String
        var sourceURL: String
        var reference: String
        var allowsBalanceOverlay: Bool
        var isApproved: Bool {
            status == "approved" && !rightsHolder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                URL(string: sourceURL)?.scheme == "https" && !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && allowsBalanceOverlay
        }
    }
    var id: String
    var issuer: String
    var issuerAliases: [String]
    var productName: String
    var productAliases: [String]
    var accountTypes: [String]
    var accountSubtypes: [String]
    var automaticMatch: Bool
    var assetName: String
    var permission: Permission

    func supports(_ account: Account) -> Bool {
        guard account.isCash != true, let details = account.bankDetails,
              let bank = details.institutionName, matches(bank, in: issuerAliases + [issuer]) else { return false }
        if let type = details.accountType, !matches(type, in: accountTypes) { return false }
        if let subtype = details.accountSubtype, !accountSubtypes.isEmpty, !matches(subtype, in: accountSubtypes) { return false }
        return true
    }
    private func matches(_ text: String, in choices: [String]) -> Bool {
        choices.contains { Self.normalized($0) == Self.normalized(text) }
    }
    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    func reliablyMatches(_ account: Account) -> Bool {
        // A checking product identifies an account, not the artwork of its debit card.
        // Nicknames and a last-four mask are never evidence of a particular card design.
        guard automaticMatch, supports(account), account.bankAccountKey != nil,
              let details = account.bankDetails, details.accountType == "credit", details.accountSubtype == "credit card" else { return false }
        return matches(details.officialName ?? details.bankName, in: productAliases + [productName])
    }
}

struct CardArtworkCatalog: Sendable {
    private struct Manifest: Decodable { var schemaVersion: Int; var artworks: [CardArtwork] }
    let artworks: [CardArtwork]
    init(artworks: [CardArtwork]) {
        // A duplicate identity is ambiguous, even if only one duplicate is approved.
        let counts = Dictionary(grouping: artworks, by: \.id).mapValues(\.count)
        self.artworks = artworks.filter {
            !$0.id.isEmpty && $0.id.count <= 128 && counts[$0.id] == 1 && !$0.assetName.isEmpty &&
                !$0.issuer.isEmpty && !$0.productName.isEmpty && !$0.accountTypes.isEmpty && $0.permission.isApproved
        }
    }
    init(data: Data) throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.schemaVersion == 1, manifest.artworks.count <= 1_000 else { throw LedgerError.invalidBackup }
        self.init(artworks: manifest.artworks)
    }
    func choices(for account: Account) -> [CardArtwork] {
        artworks.filter { $0.supports(account) }.sorted { $0.productName.localizedStandardCompare($1.productName) == .orderedAscending }
    }
    func automaticArtwork(for account: Account) -> CardArtwork? {
        let matches = artworks.filter { $0.reliablyMatches(account) }
        return matches.count == 1 ? matches[0] : nil
    }
    func artwork(for account: Account) -> CardArtwork? {
        guard account.usesStandardCardDisplay != true else { return nil }
        if let id = account.cardArtworkID { return choices(for: account).first { $0.id == id } }
        return automaticArtwork(for: account)
    }
}

enum CardArtworkChoice { case automatic, standard, artwork(String) }
extension Ledger {
    mutating func chooseCardArtwork(_ choice: CardArtworkChoice, accountID: UUID, catalog: CardArtworkCatalog) throws {
        guard let index = accounts.firstIndex(where: { $0.id == accountID && $0.isArchived != true && $0.isCash != true }) else { throw LedgerError.invalidBackup }
        switch choice {
        case .automatic:
            accounts[index].cardArtworkID = nil; accounts[index].usesStandardCardDisplay = nil
        case .standard:
            accounts[index].cardArtworkID = nil; accounts[index].usesStandardCardDisplay = true
        case .artwork(let id):
            guard catalog.choices(for: accounts[index]).contains(where: { $0.id == id }) else { throw LedgerError.invalidBackup }
            accounts[index].cardArtworkID = id; accounts[index].usesStandardCardDisplay = nil
        }
    }
}
