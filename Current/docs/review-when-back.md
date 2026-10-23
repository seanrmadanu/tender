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

## v4.3 decisions to revisit — optional subscription mail

No answers were requested while you were away. Implemented defaults:

- Optional Gmail alongside bank estimates; connect multiple addresses independently (up to 20).
- Review before accepting cancellations/trials/renewals; explicit date confirmation; manually choose matching subscription across addresses.
- Email parsing on phone, credentials in device-only Keychain; no email upload to Cloudflare or AI service.
- Foreground checks only: existing bank 5-minute cooldown; Gmail 15 minutes. No promise of background monitoring.
- Last-year/500-message scan per mailbox; English/USD inference, ambiguous fields manually corrected.
- Trial reminder 3 days before, recurring 1 day before, 9 AM; opt-in.
- Cancelled entries excluded from costs/reminders while purchase history remains. Later merchant-matched charges are flagged for review.
- Loading view has no artificial timer and does not wait for network.

Remaining choices/setup for your return:

1. Configure Google iOS OAuth client and add your test email addresses. Steps in gmail-subscriptions.md; no secrets in chat.
2. Before wider release, complete Google restricted-scope/privacy requirements. Decide whether to retain on-device-only processing.
3. Decide whether additional email providers, notifications while Tender is closed, incremental inbox history, or higher scan limits are needed.
4. Verify deployed bank transaction support; if missing, separately inspect the existing Worker/transaction configuration. No new paid Plaid product was enabled.
5. Test recognition against your actual subscription emails; generic English heuristics can miss messages and confuse promotional copy with account notices. Sender names are not proof.

Manual paste/review and the loading page can be tried before Google setup. Compilation passed only; functional testing remains yours.

## Login-first development checkpoint

User requested login first on install and a Settings reset. Implemented the login entry UI and confirmed reset route. Authentication remains blocked on provider configuration and backend ownership/session work, not just Google Client ID. Recommended Firebase with existing Google project; no service was configured or billing enabled. See account-login.md. Current cannot advance past welcome until real auth is added; prior usable personal version is 37f14da. No user data was erased.

## v4.5 follow-up

- Email/password account flow now implemented. Enable its provider in Firebase if not done.
- Supplied Firebase plist has no Google CLIENT_ID/REVERSED_CLIENT_ID; enable Google in tender-84bd7 Authentication and download updated plist.
- Apple and phone still need external provider/capability setup.
- No login inherits the personal bank vault. Worker UID authorization/migration remains a separate implementation task. Manual accounts work after login.
- Full reset signs out and clears all local account directories; it does not delete the online Firebase user.
- User owns live authentication, account-switching and reset testing; only compilation/static checks performed. See firebase-auth.md.
