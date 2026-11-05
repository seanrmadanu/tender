import XCTest
@testable import TenderCore

final class CardArtworkTests: XCTestCase {
    private func art(_ id: String = "example-gold") -> CardArtwork {
        CardArtwork(id: id, issuer: "Example Bank", issuerAliases: ["Example Bank, N.A."], productName: "Example Gold",
            productAliases: ["Example Gold Card"], accountTypes: ["credit", "depository"], accountSubtypes: ["credit card", "checking"],
            automaticMatch: true, assetName: "TestOnlyArtwork",
            permission: .init(status: "approved", rightsHolder: "Synthetic test fixture", sourceURL: "https://example.invalid/art",
                reference: "Test-only original artwork", allowsBalanceOverlay: true))
    }
    private func account(type: String? = "credit", subtype: String? = "credit card", product: String = "Example Gold Card") -> Account {
        Account(name: "My renamed account", available: 100, bankAccountKey: "production:test",
            bankDetails: BankAccountDetails(itemID: "test", institutionName: "Example Bank, N.A.", bankName: product,
                mask: "1234", currentBalance: 100, currency: "USD", officialName: product, accountType: type, accountSubtype: subtype))
    }
    func testAutomaticMatchRequiresExactIssuerAndCreditProduct() {
        let catalog = CardArtworkCatalog(artworks: [art()])
        XCTAssertEqual(catalog.artwork(for: account())?.id, "example-gold")
        XCTAssertNil(catalog.artwork(for: account(product: "Gold")))
        XCTAssertNil(catalog.artwork(for: account(type: "depository", subtype: "checking")))
        XCTAssertNil(catalog.artwork(for: account(type: nil, subtype: nil)))
        var wrongBank = account(); wrongBank.bankDetails?.institutionName = "Other Bank"
        XCTAssertNil(catalog.artwork(for: wrongBank))
        var nickname = account(product: "Credit card"); nickname.name = "Example Gold Card"
        XCTAssertNil(catalog.artwork(for: nickname))
        var manual = account(); manual.bankAccountKey = nil
        XCTAssertNil(catalog.artwork(for: manual))
    }
    func testAmbiguousVariantsRequireUserSelection() throws {
        let catalog = CardArtworkCatalog(artworks: [art(), art("gold-variant")])
        XCTAssertNil(catalog.automaticArtwork(for: account()))
        var ledger = Ledger.empty(); ledger.accounts = [account()]
        try ledger.chooseCardArtwork(.artwork("gold-variant"), accountID: ledger.accounts[0].id, catalog: catalog)
        XCTAssertEqual(catalog.artwork(for: ledger.accounts[0])?.id, "gold-variant")
        try ledger.chooseCardArtwork(.standard, accountID: ledger.accounts[0].id, catalog: catalog)
        XCTAssertNil(catalog.artwork(for: ledger.accounts[0]))
        try ledger.chooseCardArtwork(.automatic, accountID: ledger.accounts[0].id, catalog: CardArtworkCatalog(artworks: [art()]))
        XCTAssertEqual(CardArtworkCatalog(artworks: [art()]).artwork(for: ledger.accounts[0])?.id, "example-gold")
    }
    func testCheckingCanSelectButNeverAssumesADebitCardDesign() throws {
        let catalog = CardArtworkCatalog(artworks: [art()])
        var ledger = Ledger.empty(); ledger.accounts = [account(type: "depository", subtype: "checking")]
        let id = ledger.accounts[0].id
        XCTAssertNil(catalog.artwork(for: ledger.accounts[0]))
        XCTAssertEqual(catalog.choices(for: ledger.accounts[0]).count, 1)
        try ledger.chooseCardArtwork(.artwork("example-gold"), accountID: id, catalog: catalog)
        XCTAssertNotNil(catalog.artwork(for: ledger.accounts[0]))
        ledger.accounts[0].bankDetails?.institutionName = "Another Bank"
        XCTAssertNil(catalog.artwork(for: ledger.accounts[0]))
        XCTAssertThrowsError(try ledger.chooseCardArtwork(.artwork("example-gold"), accountID: id, catalog: catalog))
        ledger.accounts[0].isCash = true
        XCTAssertThrowsError(try ledger.chooseCardArtwork(.automatic, accountID: id, catalog: catalog))
    }
    func testUnapprovedRevokedAndDuplicateArtCannotDisplay() {
        var pending = art("pending"); pending.permission.status = "pending"
        var revoked = art("revoked"); revoked.permission.status = "revoked"
        var missingEvidence = art("missing"); missingEvidence.permission.reference = " "
        var noOverlay = art("no-overlay"); noOverlay.permission.allowsBalanceOverlay = false
        let catalog = CardArtworkCatalog(artworks: [art(), art(), pending, revoked, missingEvidence, noOverlay])
        XCTAssertTrue(catalog.artworks.isEmpty)
        var selected = account(); selected.cardArtworkID = "removed-id"
        XCTAssertNil(CardArtworkCatalog(artworks: [art()]).artwork(for: selected))
    }
    func testSelectionSurvivesProviderRefreshArchiveAndCompleteBackup() throws {
        let catalog = CardArtworkCatalog(artworks: [art()])
        var ledger = Ledger.empty(); ledger.accounts = [account(type: "depository", subtype: "checking")]
        let id = ledger.accounts[0].id
        try ledger.chooseCardArtwork(.artwork("example-gold"), accountID: id, catalog: catalog)
        let now = Date()
        let snapshot = BankSnapshot(id: "test", name: "Checking", institutionName: "Example Bank", currency: "USD", availableCents: 200,
            retrievedAt: now, officialName: "New official account name", accountType: "depository", accountSubtype: "checking")
        _ = try ledger.synchronizeBankAccounts([snapshot], environment: "production", now: now)
        XCTAssertEqual(ledger.accounts[0].cardArtworkID, "example-gold")
        XCTAssertEqual(ledger.accounts[0].bankDetails?.officialName, "New official account name")
        ledger.archiveCardAndHistory(id)
        let archive = try LedgerArchive(ledger: ledger, attachments: [:]).validated()
        let decoded = try JSONDecoder.tender.decode(LedgerArchive.self, from: JSONEncoder.tender.encode(archive))
        ledger = decoded.ledger; try ledger.restoreCardAndHistory(id)
        XCTAssertEqual(ledger.accounts[0].id, id)
        XCTAssertEqual(ledger.accounts[0].cardArtworkID, "example-gold")
        XCTAssertEqual(ledger.accounts[0].available, 200)
        XCTAssertNotNil(catalog.artwork(for: ledger.accounts[0]))
    }
    func testOlderAccountDataDecodesWithoutArtworkOrProductMetadata() throws {
        var ledger = Ledger.empty(); ledger.accounts = [account()]
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder.tender.encode(ledger)) as? [String: Any])
        var accounts = try XCTUnwrap(json["accounts"] as? [[String: Any]])
        accounts[0].removeValue(forKey: "cardArtworkID"); accounts[0].removeValue(forKey: "usesStandardCardDisplay")
        var details = try XCTUnwrap(accounts[0]["bankDetails"] as? [String: Any])
        for key in ["officialName", "accountType", "accountSubtype"] { details.removeValue(forKey: key) }
        accounts[0]["bankDetails"] = details; json["accounts"] = accounts
        let restored = try JSONDecoder.tender.decode(Ledger.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(restored.accounts[0].cardArtworkID)
        XCTAssertNil(restored.accounts[0].bankDetails?.officialName)
        XCTAssertNil(CardArtworkCatalog(artworks: [art()]).artwork(for: restored.accounts[0]))
    }
    func testShippingManifestContainsNoUnlicensedOrFictionalBankArt() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tender/Resources/CardArtworkCatalog.json")
        XCTAssertTrue(try CardArtworkCatalog(data: Data(contentsOf: url)).artworks.isEmpty)
    }
}
