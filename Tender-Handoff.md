## v4.3.1 — Google iOS client configuration (October 23, 2026)

Configured the user-provided public Google iOS client ID and matching reversed URL scheme in Current/Tender/Info.plist. The existing tender shopping shortcut scheme is retained. The Gmail configured check can now enable Connect Gmail after rebuild/install. No tokens, client secrets, Google Cloud changes or live account requests were made.

Validation: plist lint, whitespace diff check and simulator-target build passed (Current/build/oct23-google-configuration-build.log). No runtime/UI/OAuth/email testing or device install, per user preference.

Tender account login remains pending: Gmail permission is separate from basic Google sign-in. A real account feature must validate Google identity, create backend sessions, isolate ledger/bank ownership per user, and handle sign-out/deletion without exposing the existing personal bridge. Do not treat the Gmail connection as completed Tender authentication. Google test-user/consent/scope settings remain user-managed and unverified.

Prior checkpoint: b60f415. Current only; Merged untouched.

---

## v4.3 — Optional subscription email review and loading page (October 22, 2026)

Work in **Current/Tender.xcodeproj**. Prior code checkpoint: **3442209 (v4.2)**. Merged and archived versions are untouched.

- Added optional multiple-Gmail subscription discovery with native OAuth/PKCE/state, separate device-only Keychain tokens, bounded on-device parsing, per-address sync status/disconnect and a review queue. Added manual paste fallback. No full email bodies or credentials in ledger exports; extracted details and subject previews are included.
- Added explicit review for trial/renewal dates, prices and existing-subscription matching. Unknown trial prices stay unknown and contribute no fictional cost. Confirmation never records a payment or cancels with the provider.
- Recurring entries retain source/email provenance, support cancel/resume without deleting history, ignore/restore bank estimates, stop cancelled reminders/reserves, and flag possible later posted charges by merchant. Trial reminders optionally fire three days before; other renewals one day before.
- Gmail checks on foreground entry and every approximately 15 minutes while active; existing bank refresh remains approximately five minutes. These are not continuous background updates. No backend, webhook or Plaid product was deployed/enabled.
- Added engraved, adaptive paper/green loading page with Tender wordmark and native progress. No artificial delay; only local ledger loading blocks initial navigation.
- Backups decode older optional-field-free ledgers; restores require reconnecting Gmail. Full local wipe removes Gmail credentials; bank-only wipe retains email setup. Older app versions may reject new zero/unknown-price trials, so use v4.3 to open new backups.

**Setup still needed:** Google iOS OAuth client, Gmail API, consent/test-user configuration, `TenderGoogleClientID`, reversed callback URL scheme. Connect Gmail is intentionally disabled until public configuration is present. Google restricted-scope production review remains outstanding. See `Current/docs/gmail-subscriptions.md` for steps, limits and privacy behavior. This is mailbox authorization, not Tender user sign-in.

**Verification:** Final simulator-target compilation passed in `Current/build/oct22-subscriptions-final-build.log`; whitespace diff check passed. No runtime/unit/UI/device/OAuth/email/bank/notification tests, installation or paid services. User owns behavior testing. Earlier sandbox-only build could not access Xcode package/cache services; permitted compilation succeeded. Live bank history availability remains unverified and may depend on the previously undeployed Worker.

---

## v4.2 — Budget, groceries, recurring and wallet updates (October 22, 2026)

- Budgets: top-right Edit enters card selection; select one to edit, or delete multiple with confirmation. Referenced expenses and recurring bills move to Uncategorized; history is retained.
- Groceries: relative day header plus calendar date; double-tap resets to today. Removed shopping-day card; planned basket total is beside Groceries. Single-section creation form with scan/mic icons, name, price, quantity, optional unit/store, date and reminder. Date defaults to selected day. Photo scans clear stale prices. Save disables during speech/scanning/saving.
- Dictation: retain committed words between timestamp-delimited utterances and recognition tasks; automatic final-result restart, explicit stop, retained text on errors. Spoken time alone respects selected day.
- Wallet: paged cards with selectable dots; Edit shows overlapping cards with removal controls (separated at accessibility sizes). Removed cards are archived, excluded from available cash/new payment choices, and restorable in Settings. Historical references/receipts remain valid. Explicit bank snapshot apply can restore an archived card; automatic refresh does not.
- Recurring: normalized merchant matching, bank plus recorded expense history with bank-receipt deduplication, two-charge tentative suggestions, future estimated next due date, history/status explanations and refresh. Create Recurring Payment also available on a bank purchase. Save works without pre-existing categories via Uncategorized; bank-linked Mark Paid avoids another balance deduction.

Validation: simulator-target compilation succeeded, including final edits, in
Current/build/oct22-page-updates-final-build.log. No runtime/unit/UI tests or live
bank/device/microphone calls; user requested to handle functional testing. Updated
an existing test expectation for the intentional two-charge threshold but did not run it.
No backend deployment, new Plaid product, signing change or personal data reset.
Live bank subscription detection remains unverified; an older deployed Worker or
missing transaction history may still need follow-up. Decisions/questions saved in
Current/docs/review-when-back.md. Previous checkpoint: cc52259. Merged untouched.

---

## v4.1.7 — Shopping name wrapping and keyboard dismissal, October 22, 2026

Shopping Mode uses a vertical name field with three reserved lines (72-point
minimum). Long names wrap and then scroll within that area instead of growing
the card with their length. Removed PRICE PER ITEM caption to reuse its space;
price retains its accessibility label. The three-line region scales with system
text size for accessibility. Existing banknote styling and quantity wheel retained.

Added a keyboard-down button above both text and decimal keyboards, and a Done
submit action on the name field. Both fields now bind directly to an explicit
name/price focus state rather than nested TenderField focus states. Full field
hit regions retained. Opening the scanner/photo picker and saving the cart clear
focus; interactive scroll dismissal remains available through PaperScreen.

Validation: simulator-target compilation passed (build only), evidence in
Current/build/oct22-shopping-text-build.log. No UI tests or device installation;
user will check wrapping, layout and keyboard behavior on iPhone. Previous
checkpoint: 1bc1f24. Price OCR and product recognition unchanged in this revision.

---

## v4.1.6 — Simple scanned product names, October 22, 2026

Added a small local vocabulary of common product words. A single recognized
product kind anywhere in eligible OCR lines takes priority over incidental
text: TUBES followed by GREEK YOGURT becomes Yogurt. Cabernet becomes Wine,
and kitchen faucet becomes Faucet. Whole-word matching avoids Tea in TEAPOT;
multiple recognized kinds retain the existing descriptive fallback (e.g.
CHICKEN PASTA). Unknown products also retain that fallback. Names stay editable.
No internet lookup was added. This cannot recover product text OCR failed to
recognize and is not a general product catalog or guaranteed label detector.

Five focused shelf-parser code tests passed, including synthetic TUBES/YOGURT,
spelling variation, split ICE/CREAM, compound products and unchanged price guards.
Evidence: Current/build/oct22-simple-product-names.log. No UI/device tests or
phone install; user will test actual scans. Prior checkpoint: b0b32d0.

---

## Latest scanner update — v4.1.5, October 22, 2026

Active project: Current/Tender.xcodeproj; Merged remains untouched.
The three user screenshots displayed prices 5.79, 9.79 and 99.97 but incorrect
names (S finance tracker, p, N). ShelfLabelParser previously selected the first
line containing any letters. It now skips isolated characters, known page/UI
text, package-size-only lines and price lines, and joins up to three consecutive
uppercase product-title lines. Returns no name when only rejected text remains.

38/38 core checks passed in the run started before the model switch. Fixtures
are synthetic text, not captured OCR from the user's images. No new UI tests,
iPhone installation or end-to-end accuracy claim. User requested to handle
real scanner/app testing; don't rerun broad suites by default. This text parser
cannot recover words missed by OCR or reliably isolate every label from a page.
Version checkpoint and detailed log accompany this change.

---

## Latest UI update — v4.1.3

Shopping Mode quantity now uses a native scrolling wheel beside unit price,
replacing minus/plus controls. 2/2 simulator cart/purchase tests passed and
the dark screenshot was reviewed. Earlier notes below describe prior versions.

---

## Latest change — October 22, 2026: quick cart

Shopping Mode Add to Cart now saves directly, without a second form. Quantity
uses minus/count/plus beside unit price; scan icon is top right. Category, price,
store and planning metadata are optional for a named cart item. Purchase totals
include quantity and can link the saved cart item. Three distinct UI regressions
passed; camera/OCR hardware validation remains pending. See
[verification](Current/docs/verification.md). Version v4.1.2; prior versions kept.

---

## Latest fix — October 22, 2026

Startup disk work now runs off the main actor; unchanged ledgers are no longer
rewritten on launch. Core tests 36/36 and startup/persistence UI tests 3/3 pass.
The reported 30-second iPhone stall still needs on-device confirmation after
installing this build. See [verification](Current/docs/verification.md).

---

## Latest local status — October 21, 2026

Work in **Current/Tender.xcodeproj**. V3 was imported with a recoverable pre-import
checkpoint, then audited against all 18 requests. Original banknote styling was
restored; Merged is a separate untouched collaborator copy. Core 32/32 and backend
30/30 passed; all 9 distinct UI cases passed across the suite and focused retest.
See [the 18-item status](Current/docs/feature-status.md),
[verification](Current/docs/verification.md), and
[remaining setup](Current/docs/remaining-setup.md).

Five requests remain partial/setup-dependent: consumer onboarding, Capital One,
native iCloud, Apple/Google sign-in, and online account deletion/isolation.
Bank transaction code is local; its new Worker has not been deployed here.
Checkpoint history is in VERSION-HISTORY.md; detailed changes are appended to
Tender-change-log.log. Earlier notes below are retained as history.

---

## October 21, 2026 — personal feature implementation update

The user authorized implementation in this continuation and then chose to test
the personal app first. Friends will connect real banks later, after separate
sign-ins and bank-data isolation are implemented. The older planning-only
instructions below are historical and superseded for this personal stage.

Current source-history label: **v4 personal testing source**. Open
`Current/Tender.xcodeproj`. Read `Current/docs/personal-test-guide.md` before
installing, and `Current/docs/feature-status.md` for all 18 requested items.

Implemented source includes wallet account cards, bank transaction import and
review/matching, foreground cached-bank checks, structured receipt parsing and
original-image retention, cash wallets, shelf-price suggestions, dated shopping
plans, local speech planning/reminders, recurring suggestions, reorganized
navigation/Settings, larger input targets, backup-first deletion, and restore
reauthorization. Capital One now has safe diagnostics; its actual failure is
not confirmed fixed. Consumer authentication/isolation and native iCloud
containers remain deferred.

29 mocked backend tests passed in this environment. The 29 Swift core tests,
8 updated UI tests, and iOS build were not run because Swift/Xcode are absent.
The Cloudflare runtime test could not run because npm dependency retrieval was
blocked (HTTP 403). No deployment, live bank calls, data deletion or paid-service
change occurred. Source is ready for Mac validation, not a verified release.

The vault adapter now migrates legacy encrypted state into atomic encrypted
chunks to fit transaction history. Preserve the existing keys/vault identity.
Do not downgrade to the old vault reader after migration. The old automatic
legacy-ledger reset was retired so existing entries are preserved.

---

# Tender — continuation handoff and change record

Last updated: October 21, 2026. This is the portable starting point for another chat. It records implemented work, verification, and unfinished setup; it does not imply a live bank connection has succeeded.

**Latest planning status:** Read `Tender-Requested-Changes.md` before using older next-step lists. User supplied extensive redesign/import/receipt/grocery/voice/auth/privacy feedback and explicitly requested planning only. Apple/Google sign-in are prioritized; free Personal Team retained. Those feature changes are not implemented. `START-HERE-OTHER-CHAT.md` explains the small source-only ZIP handoff. User reports Capital One fails during external-browser linking even though another Plaid connection/balances work.

## Paste this into the next chat

> Continue Tender in `/Users/sean/Documents/ChatGPT/Money app`. Read `Tender-Handoff.md`, `Tender-change-log.log`, and the current source/diff before editing. The active `Current/Tender.xcodeproj` (v3) already incorporates the newer `Archives/v2`; do not replace it with an older snapshot. Private Cloudflare setup is complete and the user reports successful Plaid connection with visible balances. Use `Tender-Test-Checklist.md` for further live workflows and address any reported failures. Preserve the engraved ivory/green design and deterministic integer-cent calculations. Never ask me to paste secrets into chat. Keep this handoff and the chronological changelog updated after changes, distinguishing simulator/mock tests from user reports and independent live verification. Do not upgrade paid services or delete the encrypted bank vault as a troubleshooting step.

## Where to work

- Workspace: `/Users/sean/Documents/ChatGPT/Money app`.
- Current app: `Current/Tender.xcodeproj`, source-history label v3, scheme `Tender`, SwiftUI, iOS 18+. All application-relative paths below are relative to `Current/` unless stated otherwise. Handoff/changelog remain at the workspace root.
- Historical copies: `Archives/v1` and `Archives/v2`. Original ZIP downloads are retained beside them. The old nested `version/` wrappers were removed; v3 is the live `Current/` folder, not a duplicate project.
- Earlier root source was preserved in ignored `build/before-v2-integration/` before integration.
- Detailed history: `Tender-change-log.log`. Sections 1–9 describe inherited work; sections 10 onward record this continuation. Later sections supersede earlier setup status.
- Source layout: `README.md` and `VERSION-HISTORY.md` at the workspace root explain which version to open. Root launchers forward into `Current/`.
- Git baseline inspected: `8926709` (`Initial commit: Tender iOS money app`). Current continuation changes remain uncommitted; no push or PR was made.
- Read current Git status and any newly added project instructions first: other chats may have changed files since this document was written.

## User decisions already made

- Banks: Chase and Capital One. Current provider configuration uses US and USD.
- Plaid dashboard showed Production Trial access, with 0 of 10 connections used before any real connection here. This is a historical observation; recheck before linking.
- User wants free hosting and the free Trial, not a paid service upgrade.
- User has a free Apple Personal Team. Bundle ID is `com.sean.tender`; existing signing settings were retained.
- Manual accounts must work without connecting a bank: enter balances and purchases yourself.
- User explicitly approved clearing the old ledger: **“Nothing to keep — clear everything.”**
- User created Cloudflare and explicitly authorized Wrangler account/user read and Worker script write permissions. Login succeeded. No need to request the same authorization again unless it expires or new permissions are needed.
- Keep the banknote engraving/ivory paper/green ink design with legible controls.
- Maintain a log that can be handed to another chat.
- User wants to test with their existing Plaid-connected account and real records, without a separate test account. Checklist updated accordingly. Already-reflected purchases should use deduction OFF; Mark Paid always deducts and needs special care with refreshed snapshots.

## Changes completed so far

### V2 integration and existing features retained

Integrated the newer V2 continuation into the active project (now `Current/`) while retaining its visual design, report navigation, full backups, recurring-date anchors, bank-account matching, login repair, and LinkKit framework runpaths. Their file contents were preserved byte-for-byte when moved into `Archives/`.

The app includes category envelopes, expense recording and filtering, shopping-budget checks, monthly charts and heatmaps, recurring payments/reminders, grocery price history/photos/OCR, receipt attachments, reports, and manual Files exports. These are implemented features; physical-device verification limits are listed below.

### Removed random/demo values and implemented the approved reset

- New installations use an empty personal ledger with zero budget allocations.
- Added `freshStartVersion` and a one-time migration for old unmarked ledgers.
- Before replacement, the store retains a protected `before-approved-fresh-start.json` recovery copy. Attachments are retained; this is not secure deletion of historical files.
- New entries persist across launches. Explicitly restored backups are marked as intentional so the migration does not erase them on the next launch.
- Personal data lives under the app's `Documents/Tender`; UI tests use `Documents/TenderUITests`.
- Debug sample fixtures remain available only through explicit test/demo paths. Do not launch the personal app with `--sample-ledger` or UI-testing arguments.
- The user's physical iPhone was not remotely cleared. Migration runs when the updated app is installed and launched there.

### Fixed grocery price entry and persistence

- Added an optional price when creating an item.
- Store names and photos are optional when recording a price.
- Added a visible top **Save Price** action, validation, and saved confirmation.
- Closing with an unsaved draft asks whether to discard it; saving dismisses the keyboard.
- Verified observations survive a full relaunch and feed the estimate using up to five recent observations.
- Test values such as $1.49/$3.49 are test fixtures, not seeded personal data.

### Added clear manual accounts and account-specific purchases

- Prominent **Add Manual Account** and “No bank connection needed” explanation.
- Account list displays counts/totals and distinguishes manual from connected accounts.
- Account detail shows balance, timestamp, purchases, **Update Balance**, and **Add Purchase**.
- Add Purchase preselects the account whose detail screen is open.
- Zero balances are allowed. Updating a balance creates a new snapshot revision while retaining purchase history.
- History-only expenses can disable **Deduct from current balance**.
- Verified two accounts persist independently and a purchase affects only the selected account across relaunches.

### Multiple bank accounts and safe balance snapshots

- Persist bank labels and separate account names/masks.
- Stable provider keys prevent duplicate accounts when refreshing the same connection.
- A returned account can be mapped to an existing unlinked manual account.
- Adding another bank retains earlier connections; partial provider failures preserve successful results.
- Existing-bank repair/account selection uses the existing Item and access token.
- Only reviewed Production USD depository available balances enter the personal ledger. Unknown balances remain unknown; Sandbox snapshots cannot become personal cash.
- Snapshot revisions prevent deletion of an old expense from incorrectly increasing a newly refreshed balance.

### Cloudflare backend and browser bank login

- Extracted shared Node/Cloudflare logic into `backend/bridge.mjs` and configuration into `backend/config.mjs`.
- Added a SQLite-backed Durable Object Worker with an encrypted persistent vault, bearer authentication, environment separation, persisted refresh throttling, bounded requests, and no provider/request payload logging.
- Added external-browser Plaid Hosted Link for the free Apple Personal Team. The current path does not require native Universal Links/Associated Domains.
- App supports **Resume Bank Login** and **Check Connection**. Pending sessions survive app closure and backend restart.
- Completion is checked server-side; a browser redirect alone does not authorize a balance change.
- Session ownership, single-exchange protection, and interrupted-exchange markers prevent blind retries of one-use public tokens. An uncertain exchange fails closed for recovery.
- Hosted Link opens in the external browser, not an embedded authentication web view. The backend uses `hosted_link.is_mobile_app: false` for that browser flow.
- Native LinkKit remains available for a separately configured native path.
- Cloudflare runtime fixes include explicit UTF-8 encryption input and manual rejection of provider redirects.

### Private setup helpers

- Current helper: **`Set up Cloudflare Plaid.command`**, backed by `scripts/configure-cloudflare.py` and `scripts/configure-bank.py`.
- Hidden local prompts collect Production credentials; local `.env` is owner-only mode 0600 and Git-ignored.
- Existing bridge/encryption keys are preserved. Worker secrets are uploaded through stdin, without secret command-line arguments or temporary JSON files.
- Helper uploads `PLAID_CLIENT_ID`, `PLAID_SECRET`, `TENDER_API_TOKEN`, and `TENDER_ENCRYPTION_KEY`.
- Only the bridge access token is copied to the local clipboard for entry into Tender. Secret values are not printed.
- App stores its bridge settings in device-only Keychain; Plaid secrets are not embedded in the app.
- Older `Set up Plaid.command` remains for the Node/native route. Prefer the Cloudflare helper for this deployment.

## Deployment state — distinguish deployed from connected

| Item | Last verified state |
| --- | --- |
| Worker | `tender-bank-bridge` deployed successfully |
| Public address | `https://tender-bank-bridge.tender-bank-bridge.workers.dev` |
| Deployment version | `5875a86c-b3ed-4917-9dfb-6f69c3c7ebd2` |
| Cloudflare plan | Dashboard showed Free / $0 / Current plan; no upgrade selected |
| Runtime | Production, US, browser mode; `BANK_VAULT` Durable Object |
| Public health / authenticated status | Initially unconfigured; after private upload, authenticated status returned Production, browser mode, and 0 saved connections |
| Private keys | User entered keys locally; Cloudflare secret upload and authenticated bridge verification completed successfully |
| Real banks | User reports successful Plaid connection and visible balances on October 21; no independent live inspection performed, specific banks/accounts not recorded |
| iPhone | Agent installed/launched simulator build; user reports app connection, device/build details not specified |

Recheck current state rather than assuming the user has not run the helper since the last check. A successful authenticated bridge status alone does not prove Plaid credentials or live bank access work.

This is a personal, single-user bearer-token backend, not a multiuser financial service. Do not delete the Durable Object vault or regenerate its encryption key as a retry strategy. Removing a Plaid Item does not restore a consumed Trial slot; repair existing connections where possible.

## File map for the next chat

| Files | Responsibility |
| --- | --- |
| `Tender/Core/Ledger.swift`, `Tender/Services/LedgerStore.swift` | Empty ledger, reset marker, migration, persistence |
| `Tender/Core/BankSnapshot.swift` | Stable matching and reviewed bank balance application |
| `Tender/Core/Backup.swift`, `Tender/Core/PersonalLedgerSelection.swift` | Backup validation and sample selection |
| `Tender/Views/Groceries.swift` | Price entry, history, saved confirmation |
| `Tender/Views/RecurringAndAccounts.swift` | Manual account forms/details and purchases |
| `Tender/Views/ActivityAndExpenses.swift` | Expense form and initial account selection |
| `Tender/Services/BankClient.swift` | Authenticated bridge client and Hosted Link models |
| `Tender/Views/BankConnection.swift` | Setup, browser sessions, repair, review/apply balances |
| `backend/bridge.mjs`, `backend/config.mjs` | Common authenticated/encrypted provider bridge |
| `backend/server.mjs` | Node adapter and local encrypted storage |
| `backend/worker.mjs`, `backend/wrangler.jsonc` | Cloudflare adapter, Durable Object, deployment configuration |
| `backend/hosted.test.mjs`, `backend/worker.test.mjs` | Browser-session and Cloudflare runtime regression coverage |
| `UITests/TenderUITests.swift` | Persistence, grocery, reset, manual-account purchase UI cases |
| `scripts/configure-cloudflare.py`, `scripts/configure-bank.py` | Private setup and secret upload |
| `README.md`, `docs/bank-connect.md`, `docs/verification.md` | Product behavior, setup instructions, evidence |

## Verification completed

- **18 Swift core tests passed:** `build/oct21-free-core-tests.log`.
- **19 backend tests passed:** `build/oct21-cloudflare-backend-tests.log`. Includes original Node coverage, Hosted Link recovery/ownership, and local Cloudflare runtime persistence across restarts. Plaid responses were mocked.
- **All 7 simulator UI cases passed across two runs.** Six existing cases passed in `/private/tmp/Tender-oct21-free.xcresult`; the new reset/purchase case passed after correcting ambiguous/combined accessibility selectors in `/private/tmp/Tender-oct21-reset-final.xcresult`. Do not describe this as one all-green seven-case result bundle.
- Grocery tests verify optional-store entry, a second observation, calculated estimate, and persistence after relaunch.
- New reset test verifies old samples become empty once, new manual accounts survive relaunch, and purchases deduct from the selected account.
- Final app build succeeded: `build/oct21-cloudflare-final-build.log`.
- Final simulator app installed and launched normally without demo/test flags; empty ledger visually inspected: `build/oct21-empty-final.png`.
- Free-plan screenshot: `build/cloudflare-free-plan.png`.
- Setup helper tested with dummy values for stdin-only upload, no secret output, mode 0600, and key preservation.
- `git diff --check` passed before handoff; these results describe the recorded source state, not future edits.
- After version reorganization, `Current/Tender.xcodeproj` built successfully for iOS Simulator with fresh derived data at `/private/tmp/tender-layout-build`. Log: `build/oct21-layout-build.log` relative to Current. Historical files and private configuration were verified preserved; helper paths, ignore rules, shell syntax, and README links were checked.

Build evidence is ignored by Git; `/private/tmp` result bundles may disappear. Keep relevant logs/screenshots when handing off to another machine. No live bank test, physical-device test, TestFlight release, or App Store release is implied.

### Repeat useful checks

Run core checks from `Money app/Current` (temporary scratch avoids earlier iCloud/resource-fork build issues):

```sh
CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/ModuleCache" swift test --scratch-path /private/tmp/tender-core-tests --disable-sandbox
```

Backend requires Node 22 or newer:

```sh
cd backend
npm ci
npm test
```

For Xcode, open `Current/Tender.xcodeproj` and use the Tender scheme. Prior simulator was iPhone 17 / iOS 26.2, ID `60AE16AA-31C0-47FC-861D-69C5F0A1D20E`; verify available destinations first. Prior derived data: `/private/tmp/tender-oct21-build`; packages: `/private/tmp/tender-packages`. Use a fresh result-bundle path for each test run. Last simulator app was `/private/tmp/tender-oct21-build/Build/Products/Debug-iphonesimulator/Tender.app`.

## Next steps, in order

1. Inspect current files/diff. Private key upload and authenticated status verification have completed; do not print `.env` or ask for secrets in chat.
2. The first helper run uploaded keys but its final Python HTTP request was rejected by Cloudflare (403 / error 1010). Fixed the client identifier to `Tender-Setup/1.0`, clarified Production instructions, and safely reran with `--upload-saved`; the helper completed successfully. Do not re-enter keys merely because the earlier run said incomplete.
3. User now reports Plaid connected with balances visible. Do not repeat setup or reconnect existing banks. Use `Tender-Test-Checklist.md` to confirm account mapping/application, refresh, and persistence.
4. Confirm which device/build the user is testing if relevant to a failure. Build/install `Current/Tender.xcodeproj` on their iPhone with the existing Personal Team only if needed.
5. Determine whether both Chase and Capital One are already connected before offering another connection. Review/apply selected balances without duplicating existing accounts.
6. Verify multiple accounts remain distinct after refresh and relaunch. Exercise existing-bank repair rather than creating unnecessary Trial Items.
7. Verify physical camera/OCR, reminders, Back Tap, and iCloud export/restore with attachments. Keep recording what was actually tested.

If any setup or test fails, record the exact nonsecret error and investigate the existing implementation before replacing architecture or clearing state.

## Remaining product limits

- Bank connection currently supplies reviewed available-balance snapshots. Automatic transaction import/reconciliation is not implemented, even though the provider initialization includes Transactions.
- Transfers, income accounting, credit-card debt modeling, and multiple currencies are outside the current implementation.
- iCloud support is manual Files export/restore, not automatic CloudKit synchronization. Claude/ChatGPT only receive exports the user chooses to share.
- Arithmetic and spending observations are deterministic; no automatic AI analysis connection is configured.
- Back Tap must be assigned by the user in iPhone Accessibility settings to a Tender shortcut; the app cannot assign it itself.
- Physical-device OAuth completion, notifications, OCR, and iCloud round trips remain unverified. VoiceOver, largest Dynamic Type, and full appearance coverage also need further testing.

## Maintaining this handoff

After each work session, append a dated entry to `Tender-change-log.log` and update this document's current state, file map, verification, and next steps. Identify inherited work separately from new work. Never copy `.env`, provider tokens, bank credentials, recovery codes, or private financial exports into either log. Preserve earlier entries as history and explicitly mark superseded status.
