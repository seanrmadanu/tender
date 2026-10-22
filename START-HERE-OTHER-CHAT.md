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
