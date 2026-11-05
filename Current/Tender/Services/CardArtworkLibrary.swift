import UIKit

@MainActor enum CardArtworkLibrary {
    static let catalog: CardArtworkCatalog = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing") && arguments.contains("--card-artwork-test") {
            return CardArtworkCatalog(artworks: [
                fixture("fixture-everyday", product: "Everyday debit", asset: "FixtureCardEveryday"),
                fixture("fixture-premium", product: "Premium debit", asset: "FixtureCardPremium")
            ])
        }
        #endif
        guard let url = Bundle.main.url(forResource: "CardArtworkCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let manifest = try? CardArtworkCatalog(data: data) else {
            return CardArtworkCatalog(artworks: [])
        }
        // Missing bundled artwork falls back to the standard display, including restored selections.
        return CardArtworkCatalog(artworks: manifest.artworks.filter { UIImage(named: $0.assetName) != nil })
    }()
    #if DEBUG
    private static func fixture(_ id: String, product: String, asset: String) -> CardArtwork {
        CardArtwork(id: id, issuer: "Test Bank", issuerAliases: [], productName: product, productAliases: [],
            accountTypes: ["depository"], accountSubtypes: ["checking"], automaticMatch: false, assetName: asset,
            permission: .init(status: "approved", rightsHolder: "Tender synthetic test fixture", sourceURL: "https://example.invalid/synthetic-fixture",
                reference: "Original test-only vector, not bank artwork", allowsBalanceOverlay: true))
    }
    #endif
}
