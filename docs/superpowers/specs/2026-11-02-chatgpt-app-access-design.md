# ChatGPT access across Tender

User direction: expand the current ChatGPT connection beyond budgeting, with immediate saving and source badges. AI may use bank name and balances but must not retrieve/use/expose private bank identifiers or credentials. Reset and delete-all are user-operated. The user explicitly chose “Just build it,” skipping remaining design approvals.

Extend the existing Firebase-scoped Cloudflare ledger service with typed read/write tools for purchases, groceries/prices, recurring subscriptions, envelopes, fixed expenses, offline/cash accounts, profile/name, reminder preferences, Archive/restore, spending reports and shopping checks. Add phone screen handoff for camera/photos, backup/restore, sign-in, privacy and bank connection settings; these require the device and never execute sensitive operations remotely. Do not introduce payment or bank-login tools.

All AI-visible data uses explicit field projections. Linked accounts expose an opaque Tender ID, bank name and saved balance; not masks, account/card/routing numbers, Plaid IDs, item IDs, tokens or bankDetails. Bank transaction references are opaque aliases. Scrub known bank identifiers and number patterns from merchant/note/profile/receipt text. Receipt line items are available, image bytes stay device-local. Reports/exported analysis are redacted projections, never raw ledger dumps.

Writes retain owner/scopes, expected revision, idempotency, duplicate matching, budget caps and immutable source attribution. Archive is reversible and matches Swift snapshot-aware balance correction; imported bank balances cannot be edited by the AI. Cross-device edits use existing three-way conflict handling.

Approaches: extend the existing typed cloud tools (chosen by instruction to build), versus phone screen automation (requires an open phone and cannot supply reliable closed-app saving). Unrestricted ledger/database editing cannot enforce the requested bank-data boundary and is excluded.

Builder calls: existing native SwiftUI and Cloudflare stack; read-only imported bank amounts; file/camera/OS permissions and security operations remain user actions via phone handoff. No real personal ledger mutations in tests. Existing dirty feature checkout is preserved; do not commit unrelated prior work or create a clean checkout missing that work.
