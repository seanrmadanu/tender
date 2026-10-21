# Tender

A native iOS personal finance tracker with an engraved banknote visual language: ivory paper, green ink, fine curved lines, and solid surfaces for readable financial data.

Open `Tender.xcodeproj` in Xcode, select the **Tender** scheme, and run on an iPhone simulator. The app targets iOS 18 or newer and uses SwiftUI, Swift Charts, Vision, App Intents, and UserNotifications. Xcode resolves the official Plaid LinkKit SDK, pinned to version 7.2.2.

The first launch contains a clearly labeled **sample ledger**. Choose **Settings → Start My Own Ledger**, add a manual account balance from the Overview balance card, then set category allocations. Currency is USD.

**October 20 update:** the source now includes richer vector engraving, restrained animations that respect Reduce Motion, category-based bill review, backups containing receipt and grocery photos, recurring-date corrections, repeat bank-snapshot matching, and Plaid login repair. The backend's eight mocked-provider tests pass. The updated Swift code has **not** been compiled or run in this environment; Xcode and Swift are unavailable here. See the exact remaining checks in [verification notes](docs/verification.md).

You can try the sample ledger and all manual features before setting up Plaid. A real bank connection additionally requires provider approval, a running HTTPS backend, and Apple signing/Universal Link configuration.

## Implemented

| Feature | Current behavior |
| --- | --- |
| Expense categories | Create/edit monthly envelopes, record expenses, recategorize existing expenses, track remaining allocations. |
| Balances | Manual account snapshots, exact-cent deductions, history-only entries, snapshot-aware deletion, native Plaid Link flow, and bank balance retrieval through the included backend. Reapplying the same bank account updates its linked ledger account. Existing connections support Repair Login. Live verification awaits provider setup. |
| Shopping Mode | Enter an amount and category; compare with that envelope and cash after tracked bills due within 30 days. Available through a visible button, App Shortcut, or `tender://shopping`. |
| Reports | Daily spending chart, tappable calendar heatmap, category totals, previous-month navigation, seven-day summary, and deterministic spending observations. |
| Recurring payments | Weekly/monthly/yearly schedules, monthly equivalents, next-due reminders, and Mark Paid with account deduction and date advancement. Monthly/yearly renewals preserve their original day across shorter months. |
| Grocery list | Quantities, check-off, store-specific price history, shelf-price photos, on-device OCR, and a basket estimate based on up to five recent observations. |
| Bills | Image/PDF attachments, camera capture, photo library import, on-device text recognition for images, and Quick Look. Filter Activity by category, month, merchant/note text, and attachment presence; open category expense lists from Budgets and Reports. |
| iCloud and AI analysis | Complete JSON backups with attachments, smaller ledger-only JSON, CSV, and text exports through Files. Choose iCloud Drive as the destination and share chosen files with an assistant. Restore accepts both backup formats and validates them before replacing the ledger. |
| Summaries | Current month, previous months, and last seven days, with text export. |

## Triple Back Tap

1. In Shortcuts, add Tender’s **Open Shopping Mode** action to a shortcut. Alternatively, use **Open URLs** with `tender://shopping`.
2. In iPhone Settings, open **Accessibility → Touch → Back Tap → Triple Tap**.
3. Select the shortcut.

The app cannot assign Back Tap itself. The gesture needs a physical iPhone for end-to-end verification. [Apple’s instructions](https://support.apple.com/guide/shortcuts/apd897693606/ios).

## Data and arithmetic

- All money is stored as integer cents. Text input accepts at most two decimal places; scientific notation and ambiguous thousands separators are rejected.
- An expense normally deducts from the selected account. Turn off **Deduct from current balance** for historical expenses already included in your balance.
- Replacing a balance creates a new snapshot revision. Deleting expenses recorded before that snapshot changes expense history without inflating current cash.
- Budgets reset by calendar month without rollover. Transfers, income, credit-card debt modeling, multiple currencies, and bank-transaction reconciliation are outside this first version.
- Shopping Mode is an estimate based on recorded data. It reserves each tracked recurring occurrence in the next 30 days, plus one unpaid overdue occurrence per recurring entry. It does not reserve money when you merely check a purchase.
- Grocery estimates exclude unchecked items with no observed price, and label that incompleteness. Package sizes and tax can change actual costs.

## Storage and export

The ledger is atomically saved to `Documents/Tender/ledger.json`; bill and price images are stored in `Documents/Tender/Attachments/` with iOS complete file protection. Tender does not send the ledger to analytics or AI services. Vision recognizes text on the device. Files access is requested through system pickers. When invoked, Bank Connect uses Plaid and your configured bridge; Plaid's SDK and privacy terms apply to that flow.

**Export Backup with Bills & Photos** creates a portable JSON archive containing the ledger and all referenced receipt/PDF and grocery-photo bytes. It allows up to 20 MB per attachment and 60 MB of attachments in total; the encoded backup must be under 120 MB. Missing or oversized attachments stop complete export with an error, rather than silently producing an incomplete backup.

**Export Ledger Only (JSON)** is the smaller, readable option for analysis. It includes attachment filenames but no attachment bytes. Restore accepts legacy ledger-only files under 30 MB as well as complete backups. Complete restore stages photos under new filenames, preserves existing files until the ledger replacement succeeds, and removes staged files on failure. A restore also keeps a copy of the previous ledger JSON in the local Tender folder. Missing legacy attachments are reported when opened. Files are accessible using the device’s Files/Finder file sharing.

iCloud Drive exports are explicit snapshots, **not automatic multi-device sync**. Claude and ChatGPT do not automatically have access to your private iCloud. Upload or share the selected export for analysis. Native automatic iCloud sync would require an Apple signing team, configured iCloud container, conflict handling, and signed-device testing.

## Verification

Run the backend tests (Node 22 or newer, no npm dependencies):

```sh
cd backend
npm test
cd ..
```

Run the 14 financial-core tests on a Mac with Swift 6 or newer:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/ModuleCache" \
swift test --scratch-path /private/tmp/tender-core-tests --disable-sandbox
```

Build for the simulator:

```sh
xcodebuild -project Tender.xcodeproj -scheme Tender \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/tender-build \
  CODE_SIGNING_ALLOWED=NO build
```

Run UI tests using **Product → Test** in Xcode, or `xcodebuild test` with an available iPhone simulator destination. Debug UI tests use a separate `TenderUITests` storage directory; personal app data remains separate.

See [verification notes](docs/verification.md) and [bank connection options](docs/bank-connect.md). Physical-device camera capture, notification delivery, Back Tap, iCloud Drive save/restore, and Apple signing require device/account validation.

## iPhone installation

Select an Apple development team in **Signing & Capabilities**, use a unique bundle ID if necessary, connect your iPhone, and run the Tender scheme. No iCloud entitlement is needed for the current Files export flow. Bank login credentials are entered only in Plaid's secure flow. Plaid API secrets stay on the backend. Complete [bank setup](docs/bank-connect.md) before connecting a bank.
