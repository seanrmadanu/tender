# Budget funding and monthly payment review

Budgets shows each active account balance, unpaid fixed expenses, and the amount available for envelopes. The maximum allocation is `max(0, total active account balances - unpaid fixed reserves)`. This includes cash and offline accounts. Balances are saved snapshots: keep offline balances current and heed bank freshness warnings.

Fixed expenses are monthly planning reserves for rent, utilities and other commitments. Creating or editing one does not move money, schedule a payment or create an expense. A linked purchase reduces its reserve in that purchase's calendar month, down to zero. The full reserve starts again each month. Fixed payments appear in Activity, but do not spend envelope allocations. For example, a $500 balance with $200 unpaid rent allows a $300 budget; recording a $200 rent payment against that balance releases the $200 reserve, leaving the same $300 capacity.

In Budgets, tap Edit and the pencil beside Total monthly allocation. Set a total no greater than the available amount, then distribute it among any number of envelopes. The envelopes' sum cannot exceed the total. Use available amount fills the total from the current calculation. Save commits everything together; Cancel leaves the saved plan unchanged. Category edits enforce the same limits. Existing saved plans remain readable if later spending or reserves put them over capacity; the warning asks the user to adjust them, rather than silently changing allocations or rejecting their backup.

Review monthly payments lists saved posted payments for the selected month. Each entry opens individual review for its envelope or fixed expense. Bank category suggestions are optional; Apply suggested categories commits the displayed suggestions without deducting the bank balance. Unknown categories and uncertain receipt matches remain for individual review. Changing months reviews only the data already imported; it does not promise the bank's complete historical records.

Activity uses one combined spending view for its total, daily chart, calendar, categories and export. It includes posted positive USD bank purchases and manually recorded expenses, excludes pending bank entries, credits and transfers, and shows unassigned imported spending separately. Explicitly linked bank receipts count once. A unique exact same-account, same-day, same-amount and normalized-merchant match is also counted once pending confirmation; the review screen lets the user confirm a receipt match or record a distinct purchase. Ambiguous matches are never silently combined.

Deleting a fixed expense archives its reserve while keeping the payments. Restore it in Settings → Archive → Fixed expenses. Optional saved fields preserve older ledgers and complete backups. No backend migration is required.

Signup names come from provider metadata for Google, or the full name supplied as part of email account creation. Settings still allows a preferred profile name to be edited later. Financial-core and synthetic UI tests do not verify real Firebase signup or live Plaid data.

## Verification on November 1, 2026

All 87 core tests and five relevant simulator UI checks passed across the focused result bundles. Coverage includes the funding cap, fixed payments, archive/backup round trips, monthly review, imported spending, duplicate receipt handling, persistent allocation edits, cash-card controls and signup-name propagation. The signup check uses a completely local account-service fixture and a signed simulator app; its DEBUG-only fixture uses ordinary secure entry because the simulator's automatic strong-password cover intercepts synthetic typing. Normal signup continues to offer Apple strong-password support. Live Firebase/Plaid verification is separate.

Build 0.1.0 (8) was installed and launched on the paired iPhone. Mirroring timed out, so this confirms launch rather than physical-screen appearance or bank freshness.
