## Latest local status — October 21, 2026

Work in **Tender.xcodeproj**. V3 was imported with a recoverable pre-import
checkpoint, then audited against all 18 requests. Original banknote styling was
restored; Merged is a separate untouched collaborator copy. Core 32/32 and backend
30/30 passed; all 9 distinct UI cases passed across the suite and focused retest.
See [the 18-item status](docs/feature-status.md),
[verification](docs/verification.md), and
[remaining setup](docs/remaining-setup.md).

Five requests remain partial/setup-dependent: consumer onboarding, Capital One,
native iCloud, Apple/Google sign-in, and online account deletion/isolation.
Bank transaction code is local; its new Worker has not been deployed here.
Checkpoint history is in VERSION-HISTORY.md; detailed changes are appended to
Tender-change-log.log. Earlier notes below are retained as history.

---

# Personal testing update (v4 source)

Start with [the personal test guide](docs/personal-test-guide.md) and
[the 18-item status table](docs/feature-status.md). The older README below
records previous behavior; those two documents describe this revision.

Run `Check Personal Build.command` on your Mac before using the update.
No iOS compilation, live bank test or backend deployment was performed here.

---

# Tender — current working version (v3)

A native iOS personal finance tracker with an engraved banknote visual language: ivory paper, green ink, fine curved lines, and solid surfaces for readable financial data.

**Continuing in another chat?** Start with [Tender-Handoff.md](../Tender-Handoff.md) for the complete change record, current deployment state, test evidence, and remaining steps. The chronological history is in [Tender-change-log.log](../Tender-change-log.log).

For hands-on testing, use the [iPhone feature and workflow checklist](../Tender-Test-Checklist.md). On October 21 the user reported successful Plaid connection and visible balances; other live workflows still need testing.

Open `Tender.xcodeproj` in Xcode, select the **Tender** scheme, and run on an iPhone simulator. The app targets iOS 18 or newer and uses SwiftUI, Swift Charts, Vision, App Intents, and UserNotifications. Xcode resolves the official Plaid LinkKit SDK, pinned to version 7.2.2.

New installations start with an **empty personal ledger**: no sample balances, expenses, subscriptions, grocery prices, or budget allocations. Add your accounts and set category budgets. Currency is USD.

For this personal installation, the user approved clearing all old entries. The next launch of this build resets a pre-migration ledger once, after saving a protected recovery copy. New records and intentionally restored backups survive subsequent launches. The sample-review screen remains available for explicitly loaded demo data.

**October 21 update:** integrated the continuation stored under `../Archives/v2` into this main project, preserving its engraving, backup, recurrence, bank matching, login repair, and framework runpath changes. Grocery prices can be entered while adding an item, store names are optional, and the detail form has a visible top **Save Price** button. Multiple bank accounts keep separate identities across refreshes. See [current verification](docs/verification.md).

Double-click **Set up Cloudflare Plaid.command** to enter your Plaid Production keys privately on this Mac and upload them to your deployed Cloudflare Worker. The browser flow works with the free Apple Personal Team; no native Universal Link setup is required for this path. See [bank setup](docs/bank-connect.md).

## Implemented

| Feature | Current behavior |
| --- | --- |
| Expense categories | Create/edit monthly envelopes, record expenses, recategorize existing expenses, track remaining allocations. |
| Balances | Manual account snapshots, exact-cent deductions, history-only entries, snapshot-aware deletion, browser/native Plaid flows, and bank balance retrieval through the included backend. Reapplying the same bank account updates its linked ledger account. Existing connections support Repair Login. User reports successful Plaid connection and visible balances; further live cases are in the checklist. |
| Shopping Mode | Enter an amount and category; compare with that envelope and cash after tracked bills due within 30 days. Available through a visible button, App Shortcut, or `tender://shopping`. |
| Reports | Daily spending chart, tappable calendar heatmap, category totals, previous-month navigation, seven-day summary, and deterministic spending observations. |
| Recurring payments | Weekly/monthly/yearly schedules, monthly equivalents, next-due reminders, and Mark Paid with account deduction and date advancement. Monthly/yearly renewals preserve their original day across shorter months. |
| Grocery list | Quantities, check-off, optional prices when adding an item, price history with optional store names, shelf-price photos, on-device OCR, and a basket estimate based on up to five recent observations. |
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

Run the backend tests (Node 22 or newer; includes Cloudflare runtime tests):

```sh
cd backend
npm ci
npm test
cd ..
```

Run the financial-core tests on a Mac with Swift 6 or newer:

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

## Current working copy and free bank host

Use `Money app/Current/Tender.xcodeproj` (or the root **Open Current Tender.command** shortcut). It includes the V2 changes under `../Archives/v2` plus the newer grocery, account, reset and bank-hosting work. This is the v3 continuation; `../Archives/v1` and `../Archives/v2` are separate historical copies.

Cloudflare hosting is deployed at https://tender-bank-bridge.tender-bank-bridge.workers.dev on the verified Free plan. Run **Set up Cloudflare Plaid.command** for private Production key entry, then configure the bridge token in Tender. This uses an external-browser Plaid flow compatible with the free Apple Personal Team; bank authorization is still required. See [bank setup](docs/bank-connect.md).
