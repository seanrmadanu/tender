## v4.5.1 — Google account login configuration (October 23, 2026)

Integrated the updated user-supplied GoogleService-Info (1).plist into Current/Tender/GoogleService-Info.plist for Firebase project tender-84bd7. Added its matching reversed client callback scheme in Info.plist, retaining the separate Gmail OAuth client and tender shortcut scheme. The existing Google OAuth-to-Firebase flow now passes its configuration gate. No authentication logic or user data changed.

Validation: simulator-target build passed (Current/build/oct23-firebase-google-config-build.log); verified the built app contains matching Firebase project/bundle/client callback configuration; plist lint and git diff --check passed. No runtime/UI/live-auth tests or device installation, per user preference. Rebuild/run Current/Tender.xcodeproj on the phone and test Continue with Google. Apple/phone and per-user bank backend authorization remain pending. No Worker deployment or account reset. Previous checkpoint: 00e5b97. Merged and archives untouched.

---

## v4.5 — Firebase email authentication and per-user local ledgers (October 23, 2026)

Bundled the supplied Firebase iOS plist for tender-84bd7. Added real email/password sign-up, sign-in, password reset and persisted Firebase REST sessions in device-only Keychain. Launch refreshes/verifies saved identity before mounting Home; sign-out clears the session and notifications. No live authentication or email was attempted by the assistant.

Each verified Firebase UID receives a separate project-scoped hashed local ledger directory and separate Gmail credential keys. Existing personal ledger/bank credentials are not inherited. Account-based bank UI and automatic bridge calls are blocked until the Worker validates Firebase identities and routes vaults by UID. Manual accounts and local finance features are available after successful login. No Worker deployment.

Google OAuth-to-Firebase flow is implemented with state, PKCE and nonce/client checks, but the supplied plist lacks CLIENT_ID and REVERSED_CLIENT_ID. Enable Google (and Email/Password) in Firebase Authentication and download the updated plist. Google cannot start until that configuration is added. Apple/phone remain setup-dependent. Old Gmail client configuration remains separate.

Reset App clears Firebase login, all local Tender account/legacy directories, Gmail/bank credentials, app preferences/caches/cookies and notifications, then drops in-memory session state. It attempts revocation of saved legacy bank connections first when credentials exist. Exported backups, online Firebase account and OS/Google grants remain. No data reset was executed.

Validation: final simulator-target build passed in Current/build/oct23-firebase-auth-final-build.log and git diff --check passed. No runtime/UI/device/live-email/OAuth/reset tests or installation, per user instruction. Full behavior remains user-verifiable. Details and remaining setup: Current/docs/firebase-auth.md. Prior checkpoint fc844fb; prior usable personal-bank edition 37f14da. Merged untouched.

---

## v4.4 development checkpoint — Login entry and Settings reset (October 23, 2026)

Normal launch shows the engraved login page with email/Google/Apple/phone options. This is a SETUP-REQUIRED UI foundation, not working authentication: provider actions display unavailable status, no credentials are collected, and there is no path into Home yet. Legacy ledger loading and automatic network refresh do not start. Existing files/credentials are preserved until explicit reset. Prior working personal app: 37f14da.

Settings → Reset App reuses confirmed backup/deletion and remote bank revoke logic, clears preferences and returns to login on success. Busy email/bank operations block deletion. It does not delete external backups or Google grants. Settings is currently gated by the unfinished auth integration.

Build-only verification passed: Current/build/oct23-login-reset-final-build.log. No functional/device/reset/auth tests or installs. Full account-service configuration, session handling and per-user bank/local data isolation remain required. Recommended Firebase setup and implementation checklist: Current/docs/account-login.md. No paid services enabled, no data erased and no deployment. Merged untouched.

---

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

# Active: v4.1.5 — Shelf-label product names

October 22, 2026. Reject isolated OCR characters, known surrounding page text,
and package-size-only lines when selecting a product name. Join up to three
consecutive uppercase title lines. Prior checkpoint: `4470db1`.
38/38 core checks passed before the model-switch pause; no additional simulator
or device tests. User will test real scans. See Current/docs/verification.md.

---

# Active: v4.1.4 — Shelf label parsing fix

Nutrition fractions no longer trigger multi-buy ambiguity or become item names.
37/37 core tests passed; full-image/device scan pending. Previous checkpoint:
`9fdd514`. See Current/docs/verification.md and the latest Git commit.

---

# Active: v4.1.3 — Quantity wheel

October 22, 2026. Replaced Shopping Mode quantity buttons with an inline native
scrolling picker, matching the requested Timer-style interaction. Range 1–99;
cart/purchase behavior preserved. 2/2 simulator UI tests passed.
Pre-change checkpoint: `f9fa895`. See latest Git commit.

---

# Active: v4.1.2 — Shopping Mode quick cart

October 22, 2026. Added quantity beside unit price and a top-right scanner icon.
Add to Cart now saves directly without the Shopping Item form. Quantity totals,
optional metadata, duplicate prevention and linked purchases verified locally.
Pre-change checkpoint: `73765ed`. See latest Git commit and verification.md.

---

# Active: v4.1.1 — Startup follow-up

October 22, 2026. Local ledger loading/migration moved off the main actor,
unchanged startup rewrites removed, startup Keychain read moved off main, and
a loading state prevents premature edits. Core 36/36 and selected UI 3/3 passed.
Pre-fix checkpoint: `4b08b5e`. Physical iPhone launch timing remains unverified.
See the latest Git commit and Current/docs/verification.md.

---

# Active: v4.1 — V3 import, feature audit, original design restoration

October 21, 2026. The supplied folder is named V3; its ZIP describes its source
as v4. `Current/` now contains that feature update and our follow-up fixes.

Local branch: `codex/integrate-v3-2026-10-21`.

| Checkpoint | Purpose |
| --- | --- |
| `354b234` | Original Current before importing V3; recoverable source ZIP also saved. |
| `d180ba4` | Verified ZIP import and build/test-selector fixes. |
| `cc23baa` | First feature-audit fixes: grocery planning, parsers, receipt state and linked bank purchases. |
| Latest design-restoration commit | Original banknote heading, card surface/border and readable dark-mode buttons; see Git log. |

To inspect an old version without changing Current, use `git show <commit>:<path>`
or create a separate worktree. The source snapshot contains no credentials or
build caches; private deployment settings are retained in Current only.

---

# v4 — Personal feature testing source (October 21, 2026)

Implements the personal-stage requests listed in Current/docs/feature-status.md.
29 mock backend tests passed; Mac/iPhone validation remains required.
Original v3 source remains in the input handoff ZIP/version history.

---

# Tender source versions

Organized October 21, 2026. These are source-history labels, separate from the installed app's version number.

| Version | Location | Status and contents |
| --- | --- | --- |
| v1 | `Archives/v1/` | Earlier project, previously `version/v1/Money app 2`. Preserved as historical source. |
| v2 | `Archives/v2/` | Other-chat continuation, previously `version/V2/Money app`. Its design, reports, backup, recurrence, and bank improvements were integrated into the active app. |
| v3 | Git `354b234` and `Archives/snapshots/2026-10-21-before-v3-import.zip` | Preserved pre-import continuation: integrated V2, empty personal ledger and approved one-time reset, grocery saving fixes, manual and multiple bank accounts, Cloudflare backend, browser Plaid login, and private setup helpers. |

Open **Current/Tender.xcodeproj** for current work. There is one active working copy; future edits belong in Current. The separate Merged folder is excluded from Git and left untouched. Earlier original ZIP downloads are preserved as `Archives/v1-original.zip` and `Archives/v2-original.zip`.

During reorganization, both extracted historical project trees were checked byte-for-byte before and after moving. Current source, private configuration, dependencies, build evidence, signing settings, and application identity were preserved. Root launchers open or configure the current project. No bank storage reset or paid-plan change was performed.

See `Tender-change-log.log` for the chronological record and `Tender-Handoff.md` for current setup, tests, and remaining work. For a future archived version, copy source without credentials, bank data, build output, or dependency caches; label it clearly and update this index.
