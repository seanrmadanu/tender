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

# Tender — latest requested changes (planning backlog)

Captured October 21, 2026. **These requests are not implemented in this archive.** The user explicitly asked for a planning session, not feature code. Creating this handoff ZIP does not authorize starting implementation. Review and clarify the plan with the user before making feature changes.

## Confirmed current state and preferences

- Active app is v3 under `Current/`, with V2 changes already integrated. Historical projects are not needed for this handoff.
- User reports successful Plaid connection and visible balances. Capital One specifically fails during external-browser login with a generic “something went wrong” message. Do not mark the failure fixed or assume its cause.
- User wants to use their connected account and actual records, without a test account. Avoid seeding fictional balances, purchases, or grocery observations in their personal ledger.
- Prioritize **Apple and Google sign-in**. User confirmed they are **still on the free Apple Personal Team**. Native iCloud and Apple sign-in capability feasibility must be checked against that constraint; do not enable entitlements that break the current signing setup or enroll in paid services automatically.
- Keep ivory paper/green engraved banknote styling with readable text and controls.
- Continue recording changes in `Tender-change-log.log` and updating `Tender-Handoff.md`.

## Requested product changes

1. **Easy bank onboarding:** Remove the need for ordinary users to type a bridge ID/token, understand hosting, or create their own Plaid developer account. Design a secure consumer-facing setup; do not solve this by embedding provider secrets or the shared administrative bearer token in the app.
2. **Capital One connection:** Diagnose the generic Plaid error when opening the external-browser flow. Inspect safe provider error/session metadata and institution availability/configuration before choosing a fix. Preserve working connections and Trial slots.
3. **Wallet-style accounts:** Replace the prominent combined-balance card with swipeable account cards inspired by Apple Wallet. Each account has its own balance and useful details. Exact scrolling/stacking presentation still needs agreement.
4. **Bank transactions on Home:** Import/display expenses and other relevant activity from connected banks, not just balances. Show bank activity on Home. Define treatment of pending/posted transactions, refunds/transfers, manual receipt matches and duplicates before coding financial totals.
5. **Automatic freshness:** Refresh bank data automatically and make last-updated/stale/offline status clear. Do not present cached snapshots as guaranteed real-time balances or introduce paid refresh behavior without agreement.
6. **Receipt-assisted expense entry:** Scan receipts and prefill merchant, amount, date, items, quantities/count, prices and payment details where recognized. Replace a raw OCR notes dump with useful structured information. Preserve the original image so the user can view the actual receipt. Recognition must be reviewable before saving.
7. **Cash payments:** Add cash as a payment method. Decide how the cash source is represented and how it affects balances, rather than silently treating cash as a bank deduction.
8. **Shelf-label scanning:** Read item description/name, price and useful package/unit information from a price label; support quantity. Reduce manual typing while allowing review/correction.
9. **Purchase versus cart:** Provide both **Record Purchase** and **Add to Cart**. Add to Cart places an item in Groceries as a plan; it must not record spending or deduct cash until a purchase is recorded.
10. **Date-based groceries:** Organize past purchases, today's list and future shopping plans by date. User requested swiping left for previous purchases and right for future plans. Define transitions between planned/cart/purchased states and links to expense records to avoid double counting.
11. **Voice shopping plans:** Understand requests like “I want to get ice cream tomorrow when I'm going to Costco at 5 PM.” Capture item, store, date/time; request a reminder one hour before (4 PM in the example). Confirm interpreted details and handle permissions/ambiguous speech. Speech recognition approach and persistence model are not selected yet.
12. **Recurring payment discovery:** Detect recurring subscriptions/bills from bank activity rather than requiring all manual entry. Distinguish suggested repeats from confirmed subscriptions and avoid false positives. Plaid's dedicated recurring endpoint is an add-on; do not silently activate paid access. Local repeat detection from available imported history is an option, not an implemented feature.
13. **Simpler iCloud:** Reduce confusing export choices and explore native iCloud Drive access using the appropriate capability/container. Save/restore app records and attachments. User suggested an iCloud Documents/ubiquity-container approach; current implementation only exports via Files. Free-team signing support and sync/conflict behavior remain design constraints.
14. **Whole-field tapping:** Tapping anywhere in an individual text-input row should focus it, not just tapping the placeholder's exact text area. Retain normal cursor positioning, selection and accessibility behavior.
15. **Reachable Add actions:** Move primary Add buttons from the top-right to the bottom-right above the tab bar. Respect safe areas, keyboard visibility and scrolling content.
16. **Navigation hierarchy:** Replace the Reports tab with Settings; put Reports inside Activity; put account management inside Settings while retaining account cards on Home. Organize Settings into categories/subpages instead of one long list. Proposed tab order inferred from this request: Home/Overview, Budgets, Activity, Groceries, Settings. Confirm wording and Activity subnavigation before implementation.
17. **Sign-up/sign-in:** Prioritize Apple and Google. User also mentioned email and phone as possibilities. Select/configure the auth service, provider client IDs, user-owned data boundaries and backend authorization; a logged-in UI alone is not secure multiuser support. Current backend is one personal encrypted vault with one bearer token.
18. **Privacy, wiping and deletion:** Protect sensitive bank data with encryption and access controls. Offer wipe bank information and delete account. Let the user choose a clean wipe or save data to iCloud before leaving; on return restore chosen data but require fresh bank authorization to retrieve current information. Define precisely what is deleted locally, at the backend, at the auth provider and in optional user-controlled backups. Do not promise deletion of independent backups the app cannot control.

## Feedback not yet resolved

- User marked multiple existing checklist items “works”; this is user feedback, not a complete independent regression run.
- User said numbered items 12 and 13 were unclear and item 18 could wait. Their numbered feedback does not unambiguously map to the expanded 81-case checklist; ask which behaviors those refer to before treating them as missing/broken/deferred features.
- Audience (personal-only first versus multiuser release), hosting/auth provider, production release scope, grocery/voice details, automatic refresh policy and duplicate-reconciliation workflow still need planning decisions. Do not describe the backlog as a decision-complete implementation plan.

## Research already consulted (recheck when implementing)

- Plaid Hosted Link: https://plaid.com/docs/link/hosted-link/
- Plaid OAuth: https://plaid.com/docs/link/oauth/
- Plaid Transactions API and recurring add-on: https://plaid.com/docs/api/products/transactions/
- Plaid pricing/billing: https://plaid.com/docs/account/billing/
- Apple capability/program availability: https://developer.apple.com/help/account/capabilities/capabilities-overview
- Apple CloudKit setup: https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app
- User's supplied iCloud reference: https://medium.com/@elianrichard/elevate-your-ios-swiftui-apps-persistent-storage-using-icloud-cloudkit-262d5d1bfad4

Current browser Hosted Link uses an external browser (`is_mobile_app: false`) for the Personal Team build; do not switch blindly to embedded/mobile settings that require Universal Links. A generic bank-login error does not establish that this configuration caused it. Transactions sync should handle stable IDs, pagination, modified/removed entries and duplicate protection if chosen. None of these changes have been implemented or deployed in this planning session.
