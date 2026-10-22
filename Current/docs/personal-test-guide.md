# Latest local continuation

October 21, 2026: the source is now integrated into `Current/` and compiled on
this Mac. Core 32/32 and backend 30/30 passed; all nine distinct UI cases passed
across the initial suite and focused retest. See `verification.md` for exact
coverage. The original banknote styling was restored using our pre-import Git
checkpoint and screenshots; `Merged/` remains untouched.

Additional fixes: future plans open their saved date, plans can be edited,
ambiguous same-line shelf prices require review, informal shopping speech parses
correctly, receipt replacement clears previous recognition and bank removals
clear linked purchase flags. Existing private configuration is preserved.

The physical-device and deployment instructions below still apply. Earlier
statements that Xcode/Swift were unavailable describe the incoming archive's
origin environment, not the current verified Mac build.

---

# Personal testing build — October 21, 2026

This update implements the personal-feature stage agreed in this conversation.
It is source for testing, not a verified iPhone release. Existing real bank
connections must stay on the current personal backend; do not give this build
or its shared bridge token to friends for real bank access.

## Start without losing your setup

1. In the currently working app, save a complete backup with receipts/photos.
2. Extract this archive separately. Open `Current/Tender.xcodeproj`. Retain your
   existing bundle ID and your own signing team. Do not uninstall the old app
   to troubleshoot; its ledger and Keychain should be retained by an update.
3. Run `Current/Check Personal Build.command` on your Mac. It runs core Swift
   tests and builds for the simulator without changing signing or deployment.
   Then run UI tests in Xcode on a simulator and build/run on your iPhone.
4. The updated backend is needed for `/v1/transactions/sync` and richer login
   diagnostics. It has NOT been deployed from this environment. Use your
   existing configured Cloudflare workspace and preserve every private secret,
   environment setting, Durable Object identity and existing vault. Copy the
   changed backend source modules (including new `transactions.mjs` and
   `vault-storage.mjs`) into that workspace, run `npm ci` and `npm test`, then
   use its existing deployment process when ready. Do not rerun setup with new
   encryption keys or replace private `.env` files from a template.
5. Do not roll the backend back to the old storage implementation after the
   first v4 vault write. The new code reads the legacy vault and atomically
   migrates it into encrypted chunks. Old code does not read those chunks.
   App-only rollback does not require a backend rollback. Preserve the updated
   vault adapter if reverting another backend change.

The automatic updater calls provider-cached accounts and Transactions Sync.
It never invokes `/transactions/refresh`, recurring add-ons, or on-demand
balance refresh automatically. Existing Transactions enrollment/product fees
still follow your provider plan; no plan was upgraded.

## Focused checks with your real records

- Home: swipe through each account card. Confirm the right bank/account names.
  Compare its cached bank balance and the separate manually adjusted ledger
  balance. A retrieval timestamp is not a bank-confirmed freshness timestamp.
- Pull to update. Disconnect the phone's network and try again. Old information
  should remain, with an update error rather than invented current values.
  Updates run on foreground entry and every five minutes while active; iOS
  background refresh is not implemented.
- Bank Activity: find a posted purchase. If you already entered a receipt,
  match that expense. Otherwise choose a category and add it once. Its amount
  should enter recorded spending without another balance deduction. Pending,
  transfers, credits/refunds and non-USD activity cannot become purchases in
  this version. Credits/refunds are visible but do not automatically reduce
  category totals. This is not full income/refund accounting.
- Imported bank-created expense values follow bank corrections/removals.
  Manually entered receipts matched to imports retain their reviewed values.
  Disconnection alone preserves recorded local history. A later explicit bank
  wipe removes the linked accounts and their records.
- Receipt: scan a real receipt, correct merchant/total/date, tap recognized line
  items to correct them, then save. View the original image afterward. Photos
  are retained; PDF attachments are viewable but not automatically parsed.
  OCR is a conservative local parser and will miss some layouts/discounts.
- Cash: set a cash wallet's opening balance under Settings → Accounts. Record
  a cash purchase and verify only that wallet changes. With no wallet, a new
  zero-balance wallet is created and may show negative cash until corrected.
- Groceries: scan a shelf label, review the unit price/package, select quantity,
  and Add to Cart. Confirm no expense is created. Record Purchase afterward
  and confirm one expense is linked; cancelling the expense leaves the plan.
- Date navigation: swipe LEFT to earlier dates and RIGHT to later dates, as
  requested. Arrow buttons and the date picker provide alternatives.
- Shopping voice: dictate or type “I want ice cream tomorrow when I go to
  Costco at 5 PM.” Tap Fill Details for Review. Check item/store/date/time and
  the 4 PM reminder, then save. Dictation uses on-device US-English recognition
  when available; the text entry path remains available if permission or the
  device's recognition support is missing. Test actual notification delivery.
- Activity → Recurring: suggestions need at least three similarly priced
  purchases on a weekly/monthly/yearly cadence. Review before adding. Suggestions
  can be false positives and do not charge or create expenses automatically.
- Settings → Backup & Restore: save a complete backup to iCloud Drive via Files.
  Verify it exists before testing a restore. Restore pauses bank updates and
  marks restored bank accounts for reconnection/matching; it does not secretly
  revoke a working remote connection. Reauthorize a saved bank through Repair
  Login before resuming updates. Previously revoked bank permissions cannot be
  restored by importing a backup.
- Privacy deletion is destructive; do not use it just to prove a screen works.
  If you deliberately test it, export first. A cancelled/failed backup export
  must not start deletion. Failed remote revocation retains local data for
  retry. If connection credentials are absent, the UI explains that deletion
  is local-only and remote revocation cannot be verified. Independent Files
  backups are not deleted by the app.

## Capital One: evidence needed

This update does not claim to fix Capital One's generic browser failure. It
supports both current `exit` and legacy `on_exit` provider diagnostics, and it
prevents silently resuming a different pending bank session.

After the backend update, resume the existing login or use Repair Login if
already connected. Return to Tender and select Check Connection. If a provider
error is available, share the Bank Login Diagnostic (code/type/request ID/Link
session ID). Do not share tokens, credentials or full financial payloads.

The current bank product supports USD checking/savings, not credit-card debt.
Confirm whether the failed Capital One flow concerns a supported account type.
The actual error may require provider-side institution/OAuth configuration or
availability investigation; it cannot be determined from “something went wrong.”

## Deferred by agreement

Before friends connect real banks: Apple/Google authentication, server-enforced
per-user vaults and sessions, account deletion at the auth provider, audited
isolation tests, consumer onboarding without owner bridge credentials, and
sufficient Plaid production capacity. Do not distribute the personal token.

Native iCloud containers remain deferred; the current free-team signing setup
is preserved. Backup/restore uses the standard Files picker. No paid services,
App Store distribution or TestFlight enrollment were configured here.

## Verification in this environment

- 29 Node backend tests passed using mocked provider responses. Output is in
  `verification/backend-tests.txt`.
- 29 Swift core tests are supplied (18 inherited, 11 new); NOT RUN here.
- 8 updated UI tests are supplied; NOT RUN here.
- Xcode, Swift compiler, iOS rendering, real microphone/camera, notifications,
  actual iCloud restore, live bank import, and iPhone launch were not available.
- Installing backend dev dependencies failed with an npm registry HTTP 403.
  The Miniflare Cloudflare runtime test was updated but could not be rerun here.
  Chunk migration/rollback behavior passed separate storage-adapter tests.
- No live bank requests, production deployment, account wipe or private-secret
  modification occurred during this work.
