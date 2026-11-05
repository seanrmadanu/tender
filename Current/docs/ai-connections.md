# ChatGPT and Claude connections

**Expanded access:** November 2, 2026. Build 0.1.0 (10).

**Verified status:** All 73 backend tests, all 98 Swift core tests and three focused simulator screen tests pass. The expanded AI Worker is deployed (version `e7256c7f-20c7-40a6-9474-07a34500013c`). The actual connected ChatGPT account passed a read-only context check with private account fields omitted. Its tool catalog was refreshed in the browser; a new chat loads new bindings. Signed build 10 is now installed and confirmed by read-only iPhone app metadata. After the user unlocked the iPhone, build10 launched successfully. Physical-screen appearance and a live write/sync smoke test remain unverified. No real ledger write was used for verification.

AI-requested changes save immediately. There is no special Undo flow: purchases and fixed expenses use Tender’s normal edit, delete and Archive controls. A source badge identifies the AI that created an item; for an originally manual item, it identifies its latest AI edit. Editing an item does not erase its original source. Recent AI changes also list their provider in Settings.

## Connect an account

1. Sign in to Tender, then open Settings → AI Connections.
2. Choose Enable cloud connections and review the sharing explanation. This uploads the signed-in account’s ledger to its private Tender cloud storage. Adding the settings screen alone does not upload anything.
3. Add the address below as a custom MCP server in ChatGPT’s web Plugins settings, or as a custom connector in Claude’s Connectors settings. Availability depends on the AI account/workspace.
4. Start authorization in the AI product. Its Tender approval page can open the iPhone app. On a computer, copy its connection code into Tender → AI Connections → Review connection.
5. Check the client domain, return destination, signed-in Tender account and requested read/write access. Approve in Tender, then return to the original browser window to finish. ChatGPT and Claude require separate approvals.
6. Enable that connection in the conversation and ask for a supported change. The connection does not monitor unrelated conversations. Host tool-approval prompts may still apply.

Server address: `https://tender-ai-connections.tender-bank-bridge.workers.dev/mcp`

## Supported actions

| Tool | Behavior |
| --- | --- |
| tender_context | Read saved balances, accounts, envelopes, fixed reserves, time zone, time and revision. |
| tender_find_purchases | Find bank/manual purchases by merchant, account and dates; up to 100 newest matches. |
| tender_record_purchase | Record an explicitly requested manual USD purchase; ask whether the balance already includes it. |
| tender_categorize_transaction | Assign a posted USD bank purchase to an envelope or fixed expense, matching an existing manual receipt where applicable. |
| tender_transaction_note | Replace the selected bank transaction’s note while preserving receipt references. |
| tender_fixed_expense | Add/update a monthly reserve; does not pay a bill or move money. |
| tender_monthly_allocations | Set the monthly total and all envelope amounts within the available funding cap. |

Additional app tools:

| Tool | Behavior |
| --- | --- |
| tender_app_data | Read profile/preferences, groceries/prices, recurring subscriptions, envelopes, reserves, accounts, Archive and receipt line items, with pagination. |
| tender_report | Read spending totals, category allocations/comparisons, daily totals and unassigned spending for a date range. |
| tender_shopping_check | Compare a proposed cost with its envelope and available funds after fixed reserves. |
| tender_save_settings | Change profile name, primary card or reminder preference. |
| tender_open_screen | Queue a one-time phone screen handoff, including profile/photos, accounts, backup, privacy and other app areas. |
| tender_save_envelope | Create/edit an envelope within the existing total and funding cap. |
| tender_edit_purchase | Correct a manual purchase, retaining receipts/source and applying only a current snapshot adjustment. |
| tender_save_grocery | Create/edit grocery quantities, units, store, planned date and reminders. Checking an item does not charge money. |
| tender_grocery_price | Add an observed unit price to grocery history without creating a purchase. |
| tender_save_recurring | Track/edit subscriptions and bills; does not pay or cancel an external subscription. |
| tender_save_offline_account | Create/update a cash/offline account and manual balance. Cannot modify linked bank balances or connections. |
| tender_archive_item | Archive/restore ordinary items and offline accounts, preserving related history and snapshot rules. |

There are 19 total tools. The user explicitly reserved reset and delete-all for themselves. Camera/photos, OS permissions, sign-in, bank linking, complete backup/restore and privacy deletion remain user actions on the phone. Screen requests expire after 24 hours and are consumed once per account/device; they do not execute sensitive actions.

No tool transfers money, reveals bank credentials, uploads receipt images, permanently deletes records or replaces the full ledger. Balances are saved snapshots; the AI service does not independently refresh Plaid while the phone is closed. Duplicate-looking purchases require resolution, and bank categorization never deducts the balance twice. Pending purchases, credits and transfers cannot be categorized as posted spending.

## Sync and recovery

A dedicated Worker (`wrangler.ai.jsonc`) is separate from the existing bank bridge. Firebase’s verified UID defines ownership. The encrypted ledger Durable Object serializes per-account writes; revision checks reject stale requests. Idempotency IDs return the original result for unchanged retries instead of creating duplicate purchases.

The phone keeps its protected local ledger. Local changes are saved immediately and synced after a short debounce. Startup retrieves cloud changes before the forced bank refresh, and foreground sync runs on activation and every 30 seconds. Background UI delivery is not guaranteed by iOS. The server can save an authorized AI change while the phone is closed.

Three-way merging preserves independent changes. Conflicting edits, deletions or ordering changes pause sync for explicit review. Initial opt-in and conflict resolution save protected recovery copies. A concurrent phone edit made during a network request is merged again before replacing local storage. Ledger data is written before advancing the local sync base, so an interrupted save cannot silently discard unsynced edits. Receipt and profile-photo bytes stay local; their ledger metadata may be synced. Current cloud ledger limit: 8 MB.

## Bank-data boundary

AI reads use field allowlists rather than raw ledger serialization. Linked accounts expose an opaque Tender record ID, institution name and saved balance with basic freshness/type metadata. Card/account/routing numbers, masks, provider account/transaction/item IDs, bankDetails and credentials are excluded. Bank transactions use stable opaque aliases that resolve only within the authenticated user’s ledger. The bank connection vault is separate and is never exposed to these tools.

Merchant, profile, note, grocery, recurring and receipt-item text is scrubbed for known active/archived bank identifiers, credential labels and long number patterns. Receipt payment fields and file paths/bytes are not returned. This is not a claim that arbitrary unlabelled secrets typed by a user can always be recognized. The structured bank credential/identifier boundary is enforced separately from free-text redaction.

## Identity and source badges

OAuth 2.1/PKCE and resource/scopes are handled by the maintained Cloudflare Workers OAuth provider. Native approval uses a short-lived, browser-bound authorization request, a one-time completion proof and verified Firebase identity. Tender does not collect the AI product’s password. Access tokens last 15 minutes; refresh grants and ledger connection registrations expire after 30 days. Disconnecting a grant blocks it immediately in the ledger service as well as revoking the OAuth grant. Disconnect all increments the account epoch. Privacy deletion clears cloud bank data or the complete cloud ledger and disables prior AI access.

A model cannot supply its source or owner. ChatGPT/Claude attribution requires a provider-hosted Client ID Metadata Document validated by the OAuth library. A dynamically registered client’s name and redirect host are not proof of its brand; unverified clients receive a generic AI badge. Native consent displays the actual client domain and return host. Phone uploads cannot forge or replace verified source fields. Attribution follows archive/restore and pending-to-posted transaction transitions.

Badge assets are unmodified official application icons converted from the locally installed ChatGPT and Claude macOS app icon resources (`/Applications/ChatGPT.app/Contents/Resources/electron.icns` and `/Applications/Claude.app/Contents/Resources/electron.icns`). They identify the source; they do not imply endorsement. No bank card artwork is added by this feature.

## Operations

From `Current/backend`, install the locked dependencies and run `npm test`. Build the deployment package with `npx wrangler deploy --dry-run --config wrangler.ai.jsonc`. Publish only this configuration to deploy the AI service; the existing bank Worker configuration is separate. The new Worker owns its OAuth KV namespace and two SQLite Durable Object classes.

Required configuration: TENDER_AI_PUBLIC_URL, FIREBASE_PROJECT_ID, FIREBASE_API_KEY, APPLE_BUNDLE_ID, AI_LEDGER, AI_AUTH, OAUTH_KV and the secret AI_ENCRYPTION_KEY. The encryption key is 32 random bytes encoded as base64. Provision it privately once; never overwrite an existing key without an explicit data migration and recovery plan. Ledger storage uses AES-256-GCM with the owner hash as associated data. Financial payload logging and Worker observability are disabled. The service fails closed when configuration or storage is unavailable.

OAuth grants are independent delegated credentials. Native private endpoints check live Firebase account status. Disabling a Firebase user in the Firebase console is not yet wired to proactively revoke previously issued AI grants; use Tender’s Disconnect or privacy deletion to revoke them. Public release needs an account-lifecycle revocation review.

## Verification and limits

The original baseline was 52 backend and 94 Swift core tests. Expanded tests cover new tools, privacy projections, settings, offline account history and grocery/receipt restoration; final counts are in the change log. The new AI source/edit/delete UI test passes; focused monthly-allocation, profile-route and decimal-keyboard regressions also pass. Dependency audit reports zero known vulnerabilities. Evidence is under `Current/build/nov1-ai-*` (UI suite result: `nov1-ai-source-final-ui.xcresult`).

The synthetic Cloudflare runtime test exercises Firebase verification, browser-bound PKCE approval, encrypted storage, tool discovery, immediate writes, idempotency, source authenticity, two-user isolation, insufficient scope, revocation and disconnection. Domain tests cover funding caps, duplicate matching, notes, archive provenance, time-zone boundaries and bank-only privacy cleanup. Shared funding fixtures are checked by both Swift and Node. Core tests also cover conflicts, offline merges, source persistence and snapshot-aware manual expense editing.

The user already enabled and connected ChatGPT; a real read-only context call succeeded after deployment. No personal ledger writes, extra AI grant approvals, bank relinks or real deletions were performed. Broader writes are covered by synthetic runtime tests; a live signed-in iPhone write/sync test remains outstanding. Claude was outside this expansion request.

## Official references

- [OpenAI custom MCP servers](https://developers.openai.com/api/docs/guides/custom-mcp-server)
- [OpenAI MCP authentication](https://developers.openai.com/plugins/build/auth)
- [ChatGPT plugin availability](https://learn.chatgpt.com/docs/plugins)
- [Claude custom connectors](https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp)
- [Cloudflare Workers OAuth provider](https://github.com/cloudflare/workers-oauth-provider)

Client features and account restrictions can change. Verify both target AI products before describing the integration as tested with real accounts.

## Refresh an existing ChatGPT connection

In ChatGPT’s Tender plugin details, refresh the tools to pull the new schemas and descriptions, then start a new chat and select Tender. Existing OAuth grants and the encryption key are preserved; adding ordinary app actions does not require reconnecting the bank. If a client still shows seven tools, it has the earlier tool list cached. Use `tender_context` or `tender_app_data` first; do not create a fake purchase as a connection test.

## Known deferred polish

Reversed/future report intervals can return zero spending instead of an invalid-range error. Archive actions preserve original attribution and have an AI event, but do not stamp a new entity-level last-edit field until restoration. Neither issue changes balances or exposes private bank data.

## Final verification details — November 2

- Backend: 73/73 (`build/nov2-ai-backend-final.log`), including old-phone uploads retaining new settings and explicit current-client field clearing.
- Core: 98/98 in `build/nov2-ai-core-expanded.log` and again after unlock in `build/nov2-ai-core-unlock-retry.log`. The earlier locked-host rerun was 97/98; `LedgerPersistenceTests.testLegacyMigrationPreservesDataAndOnlyRunsOnce` failed with NSCocoaError513/EPERM while replacing a protected file. CUA confirmed the Mac was locked; no file-protection checks were bypassed.
- Screens: all three tests passed in `build/nov2-ai-final-ui.xcresult`: synced profile/reminders/groceries and one-time navigation; normal AI purchase editing/deletion; cloud conflict resolution clearing a real scheduled simulator notification. The notification test first reproduced a pending request remaining at1, then verified removal to0 after the fix.
- Independent review: private-ID/labelled-credential text leaks, offline card history restore, grocery snapshot aliasing and reminder refresh were reproduced and fixed with regressions. Archived receipt inspection was also repaired. Remaining minor items are listed above.
- Deployment and probes: `build/nov2-ai-deploy-final.log`, `build/nov2-ai-public-probes-final.json`. Existing OAuth storage, grants and encryption secret preserved; bank Worker unchanged. Older phone clients retain fields they cannot encode; build10 marks app-settings support explicitly.
- Device: `build/nov2-ai-device-build-final.log` and successful deep/strict codesign. After reconnection, installation succeeded (`build/nov2-ai-device-install-unlocked.json`); read-only installed metadata confirms build10 (`build/nov2-ai-device-version-unlocked.json`). After an initial screen-lock denial, the final launch succeeded (`build/nov2-ai-device-launch-final.json`).
- Workspace: existing dirty feature branch retained to preserve earlier work; no commit, merge or push. Implementation decisions and review dispositions: `build/nov2-ai-access-progress.md`.
