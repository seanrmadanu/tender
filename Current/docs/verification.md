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
