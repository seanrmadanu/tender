# Card artwork catalog

The implementation supports bundled issuer artwork, exact automatic matching, per-account manual selection, offline rendering, and a standard fallback. Home retains the existing holder, reveal, hide and swipe motion. The account's live balance is placed on a dark panel above the image after reveal; original images are fitted without cropping.

**Current asset status:** no issuer artwork has been approved or bundled. `Tender/Resources/CardArtworkCatalog.json` intentionally contains an empty array. The two `FixtureCard*` images are original fictional vectors, accessible only through a Debug build launched with both `--ui-testing` and `--card-artwork-test`. They are not official bank images and never enter the production catalog. Cash cards use the user's supplied note border, centered block lettering and live balance; see [cash-card design](cash-card.md).

## Add an approved design

1. Obtain the image from its issuer or an authorized card-art provider, with an explicit grant covering distribution in Tender and compositing its balance panel. Record the source, rights holder, approval reference and any attribution, territory, expiration, or presentation conditions in `docs/card-art-permissions/`. A public marketing image alone is not an approval.
2. Add the image in an Xcode image set under `Tender/Assets.xcassets/`. Use a stable, unique asset name. The app uses `scaledToFit` to retain the whole design. Do not put customer names, full card numbers, security codes or photographs of personal cards into the shared asset catalog.
3. Add its entry to the manifest. Use a stable ID so user selections and restored backups continue to resolve. Give each issuer and product explicit aliases verified against provider data. Do not use broad substring or bank-name-only matching.
4. Run the core and simulator artwork checks, and review the balance panel against the actual asset at small and large text sizes. Check all grant conditions before marking the entry approved.

Example schema (illustrative pending entry; not a license or a shipping asset):

```json
{
  "id": "issuer-product-design-v1",
  "issuer": "Issuer's exact name",
  "issuerAliases": ["Verified alternative institution name"],
  "productName": "Exact card product",
  "productAliases": ["Verified official product name from provider"],
  "accountTypes": ["depository"],
  "accountSubtypes": ["checking"],
  "automaticMatch": false,
  "assetName": "IssuerProductDesignV1",
  "permission": {
    "status": "pending",
    "rightsHolder": "Issuer or authorized licensor",
    "sourceURL": "https://issuer.example/approved-artwork",
    "reference": "docs/card-art-permissions/issuer-product-design-v1.md",
    "allowsBalanceOverlay": false
  }
}
```

Only approved entries with permission evidence and balance-overlay authorization are eligible. Missing asset files, duplicate IDs, removed/revoked designs and unavailable saved IDs fall back to the standard card. Permission fields are human-reviewed records, not a legal verification service. Remove or revoke an entry when its grant no longer applies; old saved IDs remain in backups but cannot bypass the current catalog.

## Matching and data

- Plaid fields `official_name`, `type` and `subtype` are carried as `officialName`, `accountType` and `accountSubtype` by the bridge and retained on `BankAccountDetails`. This additive bridge change needs a normal bank-service deployment to reach linked devices. Older bridge responses remain compatible.
- Automatic matching requires a linked credit-card account, an exact issuer alias, an exact official card-product alias, and exactly one approved design. If `official_name` is absent, the provider's account name may be used; the user-editable Tender nickname is never used. Multiple designs require a user choice.
- Depository/checking accounts always require selection. A checking-account product or last-four mask does not identify debit-card artwork. Manual choices are restricted to designs compatible with the account's known issuer/type/subtype. This feature does not broaden the bridge's existing depository-account import scope.
- Selection is stored on the account, so provider refreshes, ledger persistence, grouped card archive/restore and full backups preserve it. Artwork is bundled app content; backups store the design ID, not an additional copy of the image.
- No artwork download, remote tracking, Apple Wallet pass access, issuer provisioning entitlement, PAN collection or bank scraping is used.

Primary references checked October 30, 2026: [Plaid Accounts fields](https://plaid.com/docs/api/accounts/), [Apple issuer provisioning](https://applepaypartners.apple.com/issuers/features/in-app-provisioning), and [Chase website terms](https://www.chase.com/digital/resources/terms-of-use).
