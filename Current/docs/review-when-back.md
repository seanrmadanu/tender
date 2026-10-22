# Decisions to review when you return

October 22, 2026 · v4.2 · Active project: Current/Tender.xcodeproj
These are saved follow-ups, not blockers. No further answers requested now.

| Topic / question for later | Default implemented now |
| --- | --- |
| What happens to purchases when their category is deleted? | Keep expenses and recurring bills, reassign them to Uncategorized with a zero budget if a fallback must be created. Existing Uncategorized allocation is retained. |
| Should removing a wallet card revoke the bank connection? | Remove it from the active wallet and available cash; keep account identity, receipts and purchases. Restore under Settings → Accounts. Plaid connection management remains separate. |
| How confident should recurring detection be? | Two similarly priced charges at weekly/monthly/yearly intervals produce an Early hint. Nothing becomes a recurring bill until reviewed and saved. Three-plus charges remain suggestions, not certainty. |
| Which bank subscriptions are missing? | User confirmed no bank subscriptions appear. The new screen explains missing history versus no matching patterns, exposes bank update errors, and offers Refresh bank history. Live bank verification is left to user. |
| Does the deployed backend provide transaction history? | Unverified this turn. Previous handoff says transaction backend changes were local, not deployed. If bank activity is empty or refresh errors, inspect/deploy the compatible Worker and verify Plaid transaction availability in a separate follow-up. Do not assume local compilation fixes server history. No paid recurring add-on enabled. |
| Should grocery header show category budget or basket estimate? | Planned total for the selected day's unpurchased items, excluding unknown prices and tax. It is labeled Planned total so it isn't mistaken for a spending limit. |
| How do dates behave? | Today / N days ago / In N days, plus calendar date. Double-tap returns to today. Accessible Return to Today action available. Left = earlier, right = later. |
| Which date does dictation use? | Current selected day unless a spoken date changes it. A spoken time without a day uses the selected day. Explicit future time can enable the one-hour reminder. |
| What happens during speech pauses? | Retain completed utterances; append later utterances and recognition tasks. Continue until stop, cancellation or error. Error retains words and permits resuming. Needs iPhone microphone validation. |
| Should account cards overlap at large text sizes? | Edit view stacks with overlap normally; accessibility text sizes use separated cards so controls remain reachable. |

## Suggested checks you own

- Budgets → Edit → select one to edit, or several to delete; verify old purchases remain.
- Home → swipe cards / tap dots → Edit → remove a card; verify Activity history and Settings restore.
- Groceries → move two days backward/forward, double-tap date; create an item on that day.
- Dictate an item, pause, continue, stop; verify name/store/time before saving.
- Activity → Recurring → Refresh bank history. If no suggestions, check the history/status message.

No UI, microphone, notification, live bank or physical-device tests were run in this revision, per your request. Simulator-target build only passed.
