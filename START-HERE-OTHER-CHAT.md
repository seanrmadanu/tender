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

# Start here — Tender handoff

This small ZIP contains Tender's current source and project documentation. Read this file first, then `Tender-Requested-Changes.md`, `Tender-Handoff.md`, and the latest entries in `Tender-change-log.log`.

## Paste this message into the next chat

> Help me continue planning Tender using this ZIP. First read START-HERE-OTHER-CHAT.md and Tender-Requested-Changes.md, then inspect the current source and handoff. My active app is Current/Tender.xcodeproj (v3). Plaid works and I can see balances, but Capital One fails in the browser with “something went wrong.” I want Apple and Google sign-in first and still use a free Apple Personal Team. I am testing with my real connected account. The requested redesign/features are a planning backlog, not completed work or a final spec. Do not start writing feature code until we finish planning and I ask for implementation. Preserve working connections, real data, exact-cent arithmetic, and the banknote design. Keep Tender-change-log.log and Tender-Handoff.md updated when changes are eventually made. Never ask me to paste secrets in chat, embed private keys in the app, reset my data to fix an issue, or upgrade paid services without authorization.

## Contents

- `Current/`: active Xcode project, SwiftUI source/assets, tests, backend source/lockfile, setup scripts and app docs.
- `Tender-Requested-Changes.md`: latest detailed feedback and unresolved planning decisions.
- `Tender-Handoff.md`: implemented behavior, deployment history, evidence and limits. The requested-changes document supersedes its older next-step priorities.
- `Tender-change-log.log`: chronological work record.
- `Tender-Test-Checklist.md`: current-feature checks using real records; it is not a checklist of already implemented requested changes.
- `README.md` and `VERSION-HISTORY.md`: folder/version guide. Archive folders referenced there are intentionally not included in this ZIP.
- `PACKAGE-MANIFEST.json`: included files, byte counts and SHA-256 hashes for integrity checking.

## Intentionally excluded

Private `.env` files, credentials, access/encryption keys, financial exports, bank vault/data files, uploaded receipts, build logs/screenshots, cached binaries, `node_modules`, `.wrangler`, Xcode user state, Git history and historical versions. `.env.example` is included only as a configuration template. Runtime secrets and bank vault stay in the original local setup/deployed backend; the ZIP cannot authorize access to them on another computer.

The original workspace remains `/Users/sean/Documents/ChatGPT/Money app`. If you extract elsewhere, use the extraction folder as the new root and update absolute local paths as needed. This ZIP is a copy; edits made by another chat or computer do not automatically update the original workspace. Return changed files with a change log, or integrate deliberately. Do not overwrite the user's existing private `.env` or encrypted bank vault with an empty/new configuration.

## Rebuilding after extraction

Open `Current/Tender.xcodeproj`, select Tender and use existing signing identity on the original Mac. Xcode fetches the pinned Plaid SDK. Node 22+ is needed for backend tools; run `npm ci` in `Current/backend` to restore excluded dependencies. Swift core tests run from `Current` using `swift test --scratch-path /private/tmp/tender-core-tests --disable-sandbox`. Xcode requires macOS; a browser-only chat can inspect/edit source but cannot claim a signed iPhone test.

Private keys are not needed to review the source or plan changes. Backend mock tests do not require live credentials. For real bank access, use the already configured original device/backend, or set up credentials privately only when explicitly required. No real financial records or proof screenshots are bundled; previous test/live claims are documented observations, not newly reproduced evidence.
