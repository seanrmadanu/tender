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

# Tender v3 — iPhone feature and workflow checklist

Created October 21, 2026. App: `Current/Tender.xcodeproj`. Tick items only after testing on your iPhone. Source reviewed for this checklist; unchecked items are not claimed as verified.

**Already confirmed by you:** Plaid connected and balances are visible. This is user-reported live evidence; the specific banks/accounts and snapshot application steps still need checking below.

**Your chosen approach:** use your existing connected account and real records. No test account or invented purchases are required. Manual-account cases below are optional. Recording a purchase only changes Tender records; it does not charge or pay your bank.

## Before testing

- [ ] PRE-01 — Overview → slider/settings icon → **Export Backup with Bills & Photos**. Save a dated copy to Files/iCloud Drive and confirm the file exists.
- [ ] PRE-02 — Use your existing connected account, real categories/budgets, and actual purchases. For purchases already reflected in the applied bank balance, turn **Deduct from current balance OFF**. Only deduct an actual purchase that is not yet included in that snapshot.
- [ ] PRE-03 — Note starting account balances, monthly spending, and recurring reserve. Record each real expense once. Skip reset/disconnect and any case that would require inventing or deleting valid financial history.

## 1. Bank connection and multiple accounts

- [ ] BANK-01 — Open Manage accounts → **Connect with Plaid → Test Connection**. Production bridge is reached without re-entering secrets.
- [ ] BANK-02 — **Load Existing Connections** lists the bank(s) you connected. Bank/account names and masked account details are distinguishable.
- [ ] BANK-03 — Compare the returned balance with the bank's own **available balance** for the same account. Allow for pending charges and snapshot timing; report unexplained differences.
- [ ] BANK-04 — If balances only appear inside Bank Connect, choose **Add This Account… → Apply** for each wanted account. They should then appear in Overview/Manage accounts. Viewing a returned balance alone does not add it to the ledger.
- [ ] BANK-05 — If that same account already exists manually, select it under **Apply to** instead of creating a second account. The count should stay the same and the existing account should become linked.
- [ ] BANK-06 — **Load Cached Balances** shows the cached warning. Merely loading or opening a snapshot should not silently change ledger balances; applying it should.
- [ ] BANK-07 — **Refresh Bank Balances**, then **Update This Account… → Apply**. Existing accounts update without duplicate cash or account rows. Rapid repeat refreshes may be throttled; wait at least a minute before retrying.
- [ ] BANK-08 — If Chase or Capital One is still missing and you want both, use **Add Another Bank** once for the missing bank. The first connection/accounts remain. Do not reconnect an already-linked bank just to test it.
- [ ] BANK-09 — If an existing bank actually needs repair, use **Repair Login**. It should preserve the existing account mapping. Skip this case if no repair is needed.
- [ ] BANK-10 — Force-close Tender, reopen, then load existing connections. Saved bridge settings and linked accounts remain.
- [ ] BANK-11 — Temporarily enable Airplane Mode and try loading balances. An error should be understandable, existing ledger balances should remain, and retry should work after restoring internet.
- [ ] BANK-12 — If an unfinished browser login exists, reopen Tender and use **Resume Bank Login / Check Connection**. It should resume/check that session rather than require a duplicate connection. Skip if no pending session exists.

## 2. Your connected account and purchases (manual accounts optional)

- [ ] ACC-01 — Optional manual-account feature: skip unless you actually want an unconnected cash/account balance. It requires no bank login or account number and is labeled Manual account.
- [ ] ACC-02 — Optional: a genuine manual account with a $0 balance should be accepted. No extra account is required for this checklist.
- [ ] ACC-03 — Open your connected account → **Add Purchase**. Paid from should already be that account. Enter a real unrecorded purchase, select its category, and set deduction according to PRE-02. Only that account should change when deduction is on; other accounts stay unchanged.
- [ ] ACC-04 — Force-close/reopen. Your connected accounts, purchases, and recorded balances remain.
- [ ] ACC-05 — Refresh/review/apply an updated bank balance for the same account. Existing purchase history remains. Applying replaces its balance snapshot rather than recording an expense.
- [ ] ACC-06 — If an incorrect expense genuinely needs removal after applying a newer bank snapshot, deleting it should not increase the new balance. Skip if there is no incorrect record to remove.

## 3. Expenses, validation, and search

Use your existing connected account and actual expenses. Keep the deduction rule in PRE-02 in mind; transaction imports/reconciliation are not automatic.

- [ ] EXP-01 — Overview → Add expense. Save the actual merchant, amount, account, category, date, and note for an unrecorded real purchase. Activity matches; balance deduction follows PRE-02.
- [ ] EXP-02 — Save a historical expense with **Deduct from current balance OFF**. It appears in spending reports for its date, but current cash does not change.
- [ ] EXP-03 — Cancel an unsaved expense. No expense or deduction appears.
- [ ] EXP-04 — Try blank merchant, missing category/account, zero, letters, or 1.234 without saving fictional records. Save should be disabled or show validation. Cancel afterward; valid real purchases should retain exact cents.
- [ ] EXP-05 — Search Activity using merchant/note text, select a category, toggle **This month only**, and toggle **With bills attached**. Results match all active filters; clearing filters reveals the records again.
- [ ] EXP-06 — Open an expense and **Save Category** with another category. Spending moves between categories; total spending and account cash stay unchanged.
- [ ] EXP-07 — Only delete an incorrect or duplicate expense. A deduction reverses once if no newer snapshot has replaced it; deleting a history-only expense does not change cash. Skip if no correction is needed.
- [ ] EXP-08 — For a transaction already reflected in a newly applied bank balance, record it with deduction OFF. This avoids counting the same bank deduction twice; Tender does not reconcile this automatically.

## 4. Categories and monthly budgets

- [ ] BUD-01 — Add/edit a real category with your intended monthly allocation and icon. Name, icon, and limit persist after relaunch. Setting a budget does not change cash.
- [ ] BUD-02 — Change an allocation only if desired. Remaining budget recalculates and existing expenses stay assigned. Cancel an edit to leave it unchanged.
- [ ] BUD-03 — Check remaining = monthly allocation minus this month's recorded category expenses. Example only: $50 minus $12.34 = $37.66; use your actual values without inserting these numbers.
- [ ] BUD-04 — If real spending already exceeds a category allocation, negative remaining/over-budget status should be readable. Otherwise check the warning in Shopping Mode without recording fictional spending.
- [ ] BUD-05 — **Review [category] expenses & bills** opens the appropriate category records. Prior-month expenses should not reduce this month's remaining allocation.

## 5. Shopping Mode and Triple Back Tap

- [ ] SHOP-01 — Open the shopping bag button on Overview. Enter an amount and category; see both **Category after purchase** and **Cash after purchase & bills**.
- [ ] SHOP-02 — Compare a small amount with one exceeding the selected category's remaining budget. The result changes appropriately. A positive result requires sufficient combined recorded cash after reserves too.
- [ ] SHOP-03 — Merely checking an amount or closing Shopping Mode creates no expense, deduction, or cash reservation.
- [ ] SHOP-04 — For a real purchase you have made but not recorded, tap Record This Purchase. Amount/category carry over; choose your connected account and use the deduction rule in PRE-02. Save once. Cancel if you have not made the purchase.
- [ ] SHOP-05 — In Shortcuts, create a shortcut using Tender → **Open Shopping Mode**, or **Open URLs** with `tender://shopping`. Running it opens Shopping Mode.
- [ ] SHOP-06 — iPhone Settings → Accessibility → Touch → Back Tap → **Triple Tap** → select that shortcut. Triple-tap while using another app; Tender opens Shopping Mode. The gesture must be assigned manually in iOS.

## 6. Recurring payments, subscriptions, and reminders

- [ ] REC-01 — Activity → Recurring → +. Add a real subscription with its true amount, category, cycle, and next due date. Saving its schedule changes planning totals but does not deduct cash or record an expense.
- [ ] REC-02 — Review/edit real subscription details as needed. Weekly/monthly/yearly schedules should match the obligations you actually have; cancel edits you do not want.
- [ ] REC-03 — Mark Paid & Advance Due Date always creates a deducted expense. Use it once only for an actual payment not already recorded/reflected in the applied balance. If already reflected, add its history with deduction OFF and manually edit the next due date instead; automatic reconciliation is not implemented.
- [ ] REC-04 — For any real monthly renewal near month-end, verify its next due date stays anchored to the intended day through shorter months as payments occur. Do not advance unpaid real subscriptions merely to exercise this case.
- [ ] REC-05 — Enable **Remind me one day before at 9 AM** and grant notifications. Choose a due date whose preceding-day 9 AM is still in the future. Verify delivery at that scheduled time, subject to iOS notification/Focus settings. Example: due October 23 → reminder October 22 at 9 AM local time.
- [ ] REC-06 — If notification access is denied, enabling a reminder should explain the problem instead of silently claiming success. Restore permission in iPhone Settings before retrying.
- [ ] REC-07 — If you actually want to disable a reminder or remove a canceled subscription, do so. Its pending reminder should stop; previously paid expense history remains.
- [ ] REC-08 — A bill due within the next 30 days affects the reserve/Shopping Mode cash estimate. It should not deduct the account's recorded balance until marked paid.

## 7. Groceries and saving prices

- [ ] GROC-01 — Add an item you actually buy, using its real quantity/unit and observed price. Store can be empty. The saved observation and estimate should appear.
- [ ] GROC-02 — At the next price observation, enter its real price and tap top Save Price with store/photo optional. See Price saved, keyboard dismissal, and both observations in history. Two observations should average correctly.
- [ ] GROC-03 — Force-close/reopen. All saved grocery observations and the calculated estimate remain. This directly checks the original price-saving bug.
- [ ] GROC-04 — Set the quantity you actually need. Its basket contribution equals estimated unit price × quantity. Check it off to exclude it, uncheck to include it. Neither action records spending or deducts bank cash.
- [ ] GROC-05 — Add an item without a price. The list accepts it and warns that unpriced items are excluded from the estimate.
- [ ] GROC-06 — Add a price with a store name. History shows that store, price, and date. Try zero, letters, or more than two decimal places; invalid values should not save.
- [ ] GROC-07 — Start an unsaved price and tap **Close**. **Keep Editing** retains the draft; **Discard** closes without adding an observation.
- [ ] GROC-08 — Photograph a shelf label or choose a photo. Text appears for review; enter the actual price yourself, then save. **View Price Photo** opens the saved image after relaunch. OCR is assistance, not automatic price extraction.
- [ ] GROC-09 — As you collect more than five actual observations, the estimate should use the most recent five. Delete an item only when you actually want to remove it and its history.

## 8. Bills, receipts, and cost review

- [ ] BILL-01 — Add an unrecorded real expense using Photograph Bill. Review OCR notes and enter merchant/amount/category yourself. Apply PRE-02 so an already-reflected receipt does not reduce cash twice.
- [ ] BILL-02 — Use Choose Bill Photo or Attach PDF or Image for real receipts you are recording. Do not duplicate an expense just to attach another copy. View Attached Bill should reopen the correct file after relaunch.
- [ ] BILL-03 — Remove an attachment before saving; the resulting expense has no bill. Cancel a photo/file picker; you can continue editing normally.
- [ ] BILL-04 — Use Activity's attached-bill filter and Budgets/Reports category review to find and compare costs. Existing observations are rule-based; no automatic AI cost analysis is expected.
- [ ] BILL-05 — If camera access is denied, the app remains usable through photo library/file import/manual entry. If OCR cannot read a photo, saving its attachment and manually entering details still works.

## 9. Charts, heatmap, weekly/monthly summaries

- [ ] REPORT-01 — Reports → **Monthly**. Total spent equals recorded expenses for that month; account balances/budget allocations alone are not spending.
- [ ] REPORT-02 — Use Previous month / Next month. Record older real expenses with deduction OFF if needed; they should appear only in their matching period. Navigating beyond the current month is disabled.
- [ ] REPORT-03 — Tap a spending day on the heatmap. The selected date/total matches that day's recorded expenses. A zero-spend day shows zero; higher-spend days use darker ink.
- [ ] REPORT-04 — **Where it went** category totals add up to the period's total. Tapping a category opens matching expense/bill records.
- [ ] REPORT-05 — Switch to **Last 7 days**. It covers today and the six preceding calendar days; expenses outside that range are excluded.
- [ ] REPORT-06 — **Export This Summary**, plus Settings → **Export Weekly Summary / Export Monthly Summary**. Open the text files in Files and compare amounts/periods with their corresponding views. Summaries are on-demand exports, not scheduled notification digests.

## 10. Files, iCloud, backups, and sharing with assistants

- [ ] DATA-01 — Settings → **Export Ledger Only (JSON)**. Save to iCloud Drive; inspect the readable record data. It contains attachment filenames, not the image/PDF bytes.
- [ ] DATA-02 — **Export Expenses (CSV)**. Open in Numbers/another spreadsheet viewer. Dates, categories, merchants, notes, and dollar amounts are sensible, including text containing commas/quotes.
- [ ] DATA-03 — After saving real bills and grocery photos, export a new complete backup with a dated name so earlier backups are preserved.
- [ ] DATA-04 — Confirm exported files appear on another device signed into your iCloud Drive. No automatic in-app synchronization is expected.
- [ ] DATA-05 — Optional restore: skip during normal daily use. Only restore a chosen complete backup when you intentionally want to replace the current ledger with that snapshot. Restored records and attachments should match; newer records would be replaced.
- [ ] DATA-06 — Optional: select a non-Tender/invalid JSON as a restore, then confirm only if testing validation. It should show an error and preserve the current ledger. Do not test by editing your only backup.
- [ ] DATA-07 — Share a selected ledger/summary export with Claude or ChatGPT if desired. It should contain enough context for analysis; assistants do not automatically read private iCloud. Do not share `.env` or bridge/provider credentials.

## 11. Daily use, persistence, readability, and recovery

- [ ] UX-01 — Visit all five tabs: Overview, Budgets, Activity, Groceries, Reports. Scrolling/back navigation works and values agree across views.
- [ ] UX-02 — Check every form with the keyboard visible. Save/Cancel/Close remain reachable; amounts, labels, and warnings remain readable over the engraving.
- [ ] UX-03 — Increase iPhone Text Size, rotate the phone, and check light/dark appearance. No essential balance, field, or button should be clipped or unreadable.
- [ ] UX-04 — With VoiceOver, check tab names, account amounts, grocery checkboxes, shopping result, and heatmap date/total labels. Reduce Motion should not prevent navigation.
- [ ] UX-05 — Force-close/reopen, lock/unlock, and optionally restart the phone. Existing ledger records remain. The approved old-ledger reset must not repeat now that you've started using the app.
- [ ] UX-06 — With internet off, record an actual unrecorded purchase using PRE-02, save a real grocery price, and browse reports. Local data persists offline; bank retrieval errors should not clear it.

## Optional destructive cases — skip on your personal ledger

Reset to an Empty Ledger, Remove Sample Data, and Disconnect All Banks are separate recovery/destructive flows. Test their **Cancel** behavior if desired. Only confirm them in a disposable setup or with a deliberate recovery plan. Disconnecting live banks can consume additional Trial slots if you reconnect. No production bank connection needs to be removed to finish this checklist.

## Not implemented yet — do not count these as failing tests

- Automatic bank transaction import, automatic categorization of imported purchases, or reconciliation.
- Transfers, income tracking, multi-currency accounting, or credit-card debt modeling.
- Automatic iCloud app sync or automatic Claude/ChatGPT access/analysis.
- Scheduled weekly/monthly summary notifications (exportable summaries exist).
- Grocery photo automatically selecting the correct price (OCR text review exists).
- General editing/deleting of accounts or categories, or full editing of an existing expense's merchant/amount/date. Existing expense detail supports category changes and deletion.

## Report an issue to the next chat

Copy this template for each failure; hide account numbers/credentials and share only the financial details needed to explain the issue:

```text
Test ID:
App/source version: v3, Current; build/install date:
iPhone model / iOS version:
Steps I took:
Expected:
Actual:
Exact error text:
Does it still happen after reopening? Does internet affect it?
Screenshot/video if useful (hide sensitive information):
```

Keep the completed checklist. There are no fictional records to clean up when using this approach. Do not restore an older backup as routine cleanup; that would discard newer real records.
