# Requested changes: personal implementation status

Updated October 21, 2026 after local source audit and simulator validation.

Active project: `Current/Tender.xcodeproj`. The separate `Merged/` copy is not
maintained or used as the UI baseline. Original styling comes from pre-import
Git checkpoint `354b234` and saved screenshots in `Current/build/`.

**13 items have a personal implementation in Current; 5 remain partial or
setup-dependent (#1, #2, #13, #17, #18).** This is a source/automated-test status,
not a claim that every camera, bank, notification, or iCloud path has passed on
an iPhone. The updated transaction backend has not been deployed in this session.

Core tests: 32 passed. Backend tests: 30 passed, including the Cloudflare runtime.
Simulator build passed. See `verification.md` for final UI results and evidence.

| # | Request | Current result |
|---|---|---|
| 1 | Simpler bank connection | Reuses saved personal setup; connected banks load automatically; owner settings are tucked into Advanced. Token-free consumer onboarding is deferred with multiuser sign-in. |
| 2 | Capital One | Added current/legacy Hosted Link diagnostics, safe sharing, automatic completion check on return, and protection against resuming the wrong pending session. Actual failure cause and fix still require device/provider evidence. |
| 3 | Wallet-style accounts | Horizontal paged engraved account cards with individual balances and timestamps. |
| 4 | Bank expenses | Cursor-based transaction sync, separate activity on Home/Activity, posted-purchase review and matching to existing receipts. No automatic second deduction. Pending/modified/removed records are handled. Refunds/transfers are displayed, not treated as purchase totals. |
| 5 | Automatic updates | Foreground and five-minute active checks, cached balance labels, retrieval timestamps, stale/error messages. No guaranteed real-time or background updates; explicit live balance refresh remains manual. |
| 6 | Receipt entry | Local OCR prefills merchant/total/date/cash method; structured editable recognized line items, quantities, prices and masked payment details; original image bytes preserved. Replacing/removing an image clears its old parsed details; recognized payment updates the cash selector and payment text is editable. PDFs remain attachments. |
| 7 | Cash | Dedicated cash-wallet type and payment selection; cash purchases affect that wallet only. |
| 8 | Price labels | Local scanner suggests name/package/price, offers quantity, rejects ambiguous multi-price/multi-buy guesses. Existing price collection also prefills a detected price. Audit fixed two different prices on one line being mistaken for a single price. |
| 9 | Two shopping actions | Add to Cart saves a grocery plan; Record Purchase opens reviewed expense entry and links a saved purchase to the plan. |
| 10 | Dated groceries | Plans and purchases grouped by date, date picker/arrows, LEFT for earlier and RIGHT for later dates. Legacy undated items are assigned a stable date on first load. Saving a future cart switches to its date; Edit Shopping Plan updates name/store/quantity/date/reminder. Bank removals clear linked purchase flags. |
| 11 | Voice plans | On-device US-English speech when supported, typed fallback, deterministic item/store/day/AM-PM-time parsing, review step, one-hour reminder scheduling. Informal “im going costco” and dotted 5:30 p.m. are covered by regressions. Complex language can require manual correction. |
| 12 | Subscriptions | Local suggestions after three similar regularly spaced bank purchases; review before creating a recurring bill. No paid recurring endpoint. |
| 13 | iCloud | Clear complete-backup/restore screen with advanced analysis exports collapsed. Standard Files → iCloud Drive; native container/sync deferred to a compatible signing plan. |
| 14 | Input targets | Shared field component gives each input a minimum 48-point focus target while keeping native text editing. |
| 15 | Add buttons | Main Home/Budgets/Activity/Groceries/Accounts and account-detail Add actions moved to lower-right safe-area buttons. Form Save/Cancel actions remain where appropriate. |
| 16 | Navigation | Home, Budgets, Activity, Groceries, Settings. Reports inside Activity; account management and categorized subpages inside Settings. |
| 17 | Sign-in | **Not implemented.** User reconfirmed free Personal Team and no Google OAuth client. Requires provider setup, verified server sessions, per-user vaults and isolation tests. No dummy sign-in buttons. |
| 18 | Privacy/deletion | Existing encrypted vault/Keychain retained; large vault encrypted-chunk storage added; bank wipe/all-local-data deletion with optional backup-first flow, revocation before local deletion when credentials exist, recovery-file cleanup, restore/reconnect gate. Auth-provider account deletion and multiuser separation deferred. |

The user confirmed friends will use real bank accounts later. That stage needs
real per-user authorization and isolated storage before distribution. Fifty
users cannot share this personal bridge token or its vault. No membership or
provider plan has been changed.

## References used while implementing

- Plaid Hosted Link: https://plaid.com/docs/link/hosted-link/
- Link response fields, including current `exit` and legacy `on_exit`:
  https://plaid.com/docs/api/link/
- Transactions Sync and pagination: https://plaid.com/docs/api/products/transactions/
- Restarting a mutated pagination window:
  https://plaid.com/docs/transactions/sync-migration/
- Apple Personal Team and distribution constraints:
  https://developer.apple.com/help/account/basics/about-your-developer-account
- Capability availability: https://developer.apple.com/help/account/reference/supported-capabilities-ios
- Plaid Trial Item capacity: https://plaid.com/docs/account/billing/

No credentials, financial records or live provider diagnostics were supplied
in the archive. No live provider action was taken from this environment.
