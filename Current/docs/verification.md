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

## Shelf-label product names — October 22, 2026

v4.1.5 replaces first-alphabetic-line selection with product-name filtering.
Rejects isolated characters, known page/UI text, size-only lines and prices;
joins up to three consecutive uppercase title lines. Synthetic cases cover
Greek yogurt, Cabernet, faucet, and no usable name, while checking the prices.

38/38 core tests passed in build/oct22-scanner-name-tests.log, from the run
started before the model-switch pause. Results inspected on continuation;
no repeat run, new simulator build, UI suite or physical-device test performed.
User will test real scans. Original image OCR transcripts were not supplied;
passing synthetic cases does not establish that the phone's names are fixed.
Price extraction and the existing nutrition/multi-buy guards are unchanged.

---

## Shelf-label nutrition filtering — October 22, 2026

User screenshot showed serving-size text used as the item name and no price.
Found a deterministic parser bug: a nutrition fraction such as 1/3 was treated
as a multi-buy offer by the global deal detector. Shelf parsing now excludes
nutrition/serving lines before choosing the name, price and multi-buy status.
37/37 core tests passed, including a synthetic OCR-text regression containing
serving size, nutrition facts and $4.06; genuine multi-buy ambiguity is retained.
Evidence: build/oct22-scanner-nutrition-tests.log. No new UI/build run.
The public source-image download returned HTTP 403; full-image OCR reproduction
and device rescan remain unverified. This fix cannot recover text Vision missed.

---

## Quantity wheel — October 22, 2026

Replaced Shopping Mode's quantity buttons with an inline native wheel, 1–99.
Simulator build and **2/2 UI tests passed**: wheel selection persists in the
cart and drives the correct purchase total, account deduction and linked item.
Reviewed the dark-mode screenshot at `build/oct22-shopping-quantity-wheel.png`.
Evidence: `build/oct22-quantity-wheel-tests.log` and
`/private/tmp/Tender-oct22-quantity-wheel.xcresult`.
No physical iPhone installation; maximum text size/VoiceOver not retested.

---

## Shopping Mode quick cart — October 22, 2026

Shopping Mode now saves directly to today's grocery list. No extra Shopping Item
sheet or category/account/store/reminder entry is required for Add to Cart.
Quantity controls sit beside unit price; the total feeds budget checks and the
purchase form. A scan icon opens the camera (photo picker on devices without a
camera; long-press offers a photo). Inline confirmation prevents duplicate taps
and dismisses the keyboard. Scanned prices/photos are saved as observations when
a price is available. Cart entries remain unpurchased until Record Purchase.

Three distinct simulator UI regressions passed across focused runs:
- Direct cart save without category or account; no expense; no duplicate; two
  units at $2.50 persist as a $5.00 planned item after relaunch.
- Quantity total is used by the budget check and purchase form; recording $5
  deducts once from a $100 account and links the existing cart item as purchased.
- Name-only item saves without a price and dismisses the keyboard.

Final direct/name-only run: **2/2 passed** in
`build/oct22-quick-cart-fresh-runner.log`. Purchase case: **1/1 passed** in
`build/oct22-quick-cart-retest.log`. Simulator build succeeded. The initial
purchase test matched both Home and Shopping Mode Record Purchase buttons; a
stable Shopping Mode identifier fixed the selector. A later run used a stale
installed test harness; it was removed and reinstalled, then both updated tests
passed. Tender's app data was not uninstalled or reset; tests use the isolated
TenderUITests ledger and disable bank requests.

Reviewed the final dark-mode screenshots with keyboard dismissed, and an earlier
light-mode screenshot. Final screenshot: `build/oct22-shopping-quick-cart-dark.png`.
Camera capture/OCR accuracy, VoiceOver operation and maximum text-size layout
still need device/visual validation. No physical iPhone installation or live bank
action occurred. Core and backend were unchanged; their earlier results below
remain historical, not new runs for this UI change.

---

## Startup follow-up — October 22, 2026

User reported a blank launch screen for more than 30 seconds when opening the
iPhone icon. Confirmed source issue: LedgerStore initialized synchronously on
the main actor, reading/decoding/validating and rewriting the whole ledger on
every launch. The update had added the unconditional rewrite. The exact
30-second device stall has not been reproduced or profiled on the phone.

Changed startup to initialize cheaply and load/validate/migrate on a detached
worker task. Normal launches no longer rewrite an unchanged file. The opening
screen appears while storage loads; editing and bank/reminder work begin only
after the saved ledger is ready. Load failure preserves the original and keeps
editing blocked. Startup bank Keychain access also runs off the main actor.
Local load duration is logged under com.sean.tender / Startup without financial
data or credentials. The original paper/green design and connected-bank setup
are retained.

Verification: 36/36 core tests and 3/3 selected simulator UI tests passed. New
regressions cover unchanged file bytes/mtime, one-time migration retaining
records, corrupt-file preservation, and 10,000 synthetic bank records. That
fixture loaded in 0.038 seconds on this Mac; this is not an iPhone launch timing.
The UI test deliberately delays storage for five seconds and verifies that the
opening screen is visible first, editing is unavailable, and Home then opens.
Account persistence and legacy preservation UI tests also passed.

Evidence: Current/build/oct22-startup-core-tests.log,
Current/build/oct22-startup-ui-tests.log and
/private/tmp/Tender-oct22-startup.xcresult. No physical iPhone install, personal
ledger reset, backend deployment or live bank request was performed. Install the
updated Current build over the existing app, then retest from the iPhone icon;
do not uninstall or clear data. If the blank delay persists, collect device
startup timing before attributing it to network or storage.

---

# Verified locally — October 21, 2026

Active source is `Current/`. No physical iPhone install, live bank requests,
production Worker deployment, data wipe, or GitHub push occurred in this session.
Private .env (0600), Worker configuration, Xcode signing project and shared scheme
match their pre-import hashes.

| Check | Result | Local evidence |
| --- | --- | --- |
| ZIP integrity and source manifest | Passed: CRC and every listed file hash | `Archives/V3/Tender-ChatGPT-Handoff.zip` |
| Core Swift tests | **32/32 passed** | `build/v3-audit-core-tests.log` |
| Node backend + Miniflare runtime | **30/30 passed** | `build/v3-import-backend-tests.log` |
| iOS simulator build | Passed | `build/v3-restored-design-build.log` |
| Full UI suite | 8/9 initially passed; new plan-editor test had an ambiguous duplicate field selector | `build/v3-audit-ui-tests.log` |
| Focused UI rerun after selector fix and design restoration | **3/3 passed**, including the previously failing case; **all 9 distinct UI cases passed across these runs** | `build/v3-restored-design-ui-tests.log` |
| Final shared-button check | **1/1 passed** after the large-text adjustment | `build/v3-final-button-test.log` |
| Visual review | Home light/dark, populated and empty accounts, account details, Activity, Reports and large text | `docs/design-review.md`, `build/ui-restored-*.png` |

The UI-test selector fix adds a stable accessibility identifier to the plan
editor's store field, distinguishing it from the price-observation field behind
the sheet. Assertions were retained: future cart visibility, edited store saved,
and persistence after relaunch/date navigation.

Simulator fixtures live in the separate TenderUITests ledger and Keychain
namespace with automatic bank requests disabled. They do not represent the
user's connected bank balances. No new sample values were added to the personal
ledger.

Unverified live/device paths: Capital One OAuth, transaction deployment and
real history import, camera/OCR accuracy on real photos, microphone and speech,
notification delivery, Files/iCloud backup/restore, and destructive deletion.
Apple/Google sign-in, per-user server isolation and native iCloud sync remain
incomplete; see `feature-status.md` and `remaining-setup.md`.

---

# Historical verification notes (superseded where noted above)

# Current verification — v4 personal testing source

October 21, 2026: 29 mock Node backend tests passed. See
`../verification/backend-tests.txt`. Swift core/UI tests and the app build
were not run here (no Swift/Xcode). The updated Cloudflare runtime test is
unrun: npm ci failed with registry HTTP 403. No production deployment or live
provider requests occurred. Read `personal-test-guide.md` and `feature-status.md`.

Older verification below describes earlier revisions, not these changes.

---

# Verification — October 21, 2026

The active project in `Money app/Current/` now contains the V2 continuation plus the current fixes. Historical snapshots now live separately in `Money app/Archives/`. The pre-integration root source is preserved under ignored `build/before-v2-integration/`.

## Verified on this Mac

- **18 Swift core tests passed.** Exact-cent arithmetic, shopping/reserves, monthly and leap-year recurrences, complete backup validation, legacy decoding, empty defaults, multiple bank snapshots without duplicate cash, matching a manual account, rejection of Sandbox/unknown balances, and selective sample cleanup preserving real entries and attachment references.
- **10 Node backend tests passed using a mocked Plaid provider.** Authentication, encrypted storage, login repair/account-selection update mode, malformed input, persistence/restart, throttling, disconnect retry, multiple banks/accounts, institution labels, and partial bank failures. These do not prove live Plaid connectivity.
- **6 iPhone 17 simulator UI tests passed** on iOS 26.2. Expense persistence, multiple manual-account persistence, grocery observations with a store, prices entered during item creation and through the top Save Price button without a store, price history after relaunch, navigation/shopping/reports, and clearing an old sample ledger through Settings.
- Native app and test builds succeeded. The packaged simulator app contains `Frameworks/LinkKit.framework/LinkKit`, and simulator launches succeeded with the V2 runpath settings.
- Reviewed screenshots of the empty personal ledger and saved grocery-price form. Ivory paper/engraving is preserved; the saved-price confirmation is visible with the keyboard dismissed.
- Local Plaid setup assistant checked with temporary test configuration: owner-only file permissions, key preservation on reruns, and separate data paths when switching environments. No real Plaid credentials used.

Evidence: `build/oct21-core-tests.log`, `build/oct21-backend-tests.log`, `build/oct21-final.log`, and screenshots under `build/oct21-final-attachments/`. The passing simulator result bundle is `/private/tmp/Tender-oct21-final.xcresult`.

One earlier UI run saved prices correctly but asserted the wrong accessibility label for combined price-history rows. The test now checks the actual combined label. An intermediate build exposed duplicate Swift source basenames; the core cleanup file was renamed before the passing build.

## Earlier setup state — superseded by the October 21 Cloudflare update below

The user has created a Plaid account. The main project's ignored `backend/.env` contains generated bridge access/encryption keys and the existing Apple team/bundle settings, with file permissions 0600. Plaid client ID, secret, and HTTPS redirect are still blank. No backend was deployed, no provider call was made, and no real bank was linked. Run `Set up Plaid.command` locally after choosing the HTTPS host, then follow [bank setup](bank-connect.md).

New installations start empty with zero allocations. Existing device ledgers are preserved; use **Settings → Remove Sample Data…** to select real records to keep. The old version had no record-level sample provenance, so automatic deletion would risk user data. Cleanup writes a recovery JSON and retains attachments locally.

## Still needs physical-device/account verification

- Signed iPhone launch, Keychain, and external-browser Hosted Link completion. Associated Domains are only needed if opting into the separate native Link route.
- Live bank coverage and balance retrieval under the user's approved Trial access.
- Real camera/OCR, local notification delivery, Back Tap, and iCloud backup/restore with attachments.
- VoiceOver, largest Dynamic Type, and appearance/layout coverage beyond the inspected screens.

## Scope

Plaid retrieves reviewed available-balance snapshots for USD depository accounts. It does not import transactions or model credit-card debt. Sandbox snapshots remain display-only. Summaries and budget arithmetic are deterministic. iCloud exports are manual snapshots; assistants need chosen exports shared with them. No TestFlight/App Store release or paid service activation was performed.

## October 21 — manual accounts, approved reset, Cloudflare browser flow

- Before reorganization, rechecked `version/V2/Money app` against the main project; V2 changes are retained. These historical folders are now `Archives/v1` and `Archives/v2`; the current continuation is labeled v3.
- 18 Swift core tests passed (`build/oct21-free-core-tests.log`).
- Six existing iPhone 17 simulator UI tests passed in `Tender-oct21-free.xcresult`. The new reset/purchase test initially matched ambiguous/combined accessibility labels; corrected its selectors after inspecting the actual hierarchy, then passed it in `/private/tmp/Tender-oct21-reset-final.xcresult` (`build/oct21-reset-final.log`).
- The new test verifies an old sample ledger becomes empty, two manual accounts persist, a purchase deducts from the selected second account, and another launch does not erase the new records.
- Grocery tests verify optional-store price entry, a second observation, average estimate and persistence after relaunch.
- 19 backend tests passed (`build/oct21-cloudflare-backend-tests.log`): original Node API tests, Hosted Link ownership/retry/recovery tests, and a real Cloudflare local-runtime test with mocked Plaid.
- Runtime test creates a browser session, restarts the Worker, completes/exchanges the session, restarts again, loads balances and verifies only one token exchange occurred. Cloudflare required explicit UTF-8 for encryption and manual redirect refusal; both are now exercised in the runtime test.
- Setup helper verified with dummy values: secrets passed on stdin, no private values printed, owner-only local configuration and preserved keys.
- Worker deployed at `https://tender-bank-bridge.tender-bank-bridge.workers.dev`. Public HTTPS health returned `environment: production, configured: false` before private setup. Cloudflare dashboard explicitly shows Free/$0/Current plan. No paid upgrade selected.
- No real bank authorization, bank balances or bank app-to-app login have been verified. Source/simulator checks do not mean the latest build is installed on the user's iPhone. The approved old-ledger reset occurs when that installation runs the new build; a protected recovery JSON is kept.
- Final build succeeded (`build/oct21-cloudflare-final-build.log`), installed and launched normally in the simulator without test/demo arguments. Screenshot: `build/oct21-empty-final.png`. Free-plan evidence: `build/cloudflare-free-plan.png`.

## Private setup follow-up — October 21

User entered keys locally. Cloudflare secret upload succeeded, but the helper's final verification request originally received HTTP 403 / Cloudflare 1010 for Python urllib's default client identifier. Updated it to identify as `Tender-Setup/1.0` and distinguish upload success from verification failures. Reran the helper with `--upload-saved` successfully: authenticated status reports Production, browser mode, and zero saved connections. Private values were not printed and existing keys were preserved. This does not validate Plaid credentials against the provider or complete a real bank login; app connection and physical-device checks remain pending.

## Version folder reorganization — October 21

Moved the active app and supporting files into `Current/` (v3), with historical source in sibling `Archives/v1` and `Archives/v2`. Historical file hashes, private configuration bytes/permissions, Git ignore rules, helper root paths, and launcher syntax were checked. The relocated `Current/Tender.xcodeproj` built successfully for iOS Simulator with fresh derived data (`/private/tmp/tender-layout-build`); evidence is `Current/build/oct21-layout-build.log` relative to the workspace root. This was a structure change; earlier app test results remain recorded above, and physical-device installation is still pending.

## User-reported live Plaid success — October 21

The user now reports successful Plaid connection and visible balances. This supersedes the earlier not-yet-connected setup state. Specific banks/accounts, device/build details, snapshot application, refresh and persistence have not been independently inspected. The manual test plan is `Tender-Test-Checklist.md` at the workspace root; its unchecked cases remain pending. No new app tests or live bank calls were performed while writing it.
