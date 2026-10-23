# Gmail subscriptions — v4.3 setup and handoff

Implemented in Current only. Google is **not configured**, so Connect Gmail stays disabled. No account was accessed, no credentials were supplied, and no production service was changed. This connects subscription mailboxes, not a Tender sign-in account.

## Configure the personal build

1. In Google Cloud, create/select a project and enable **Gmail API**.
2. Configure the OAuth consent app. For personal development, keep it in Testing and add each Gmail address you intend to connect as a test user. Request only `https://www.googleapis.com/auth/gmail.readonly`.
3. Create an **iOS OAuth client** using the exact bundle identifier from the Tender target's Signing & Capabilities. Do not create a Web client or place a client secret in the app.
4. In `Current/Tender/Info.plist`, fill the empty `TenderGoogleClientID` with that public client ID.
5. Add another dictionary under `CFBundleURLTypes`, with `CFBundleURLSchemes` containing the reversed client ID. Example: `123-example.apps.googleusercontent.com` becomes `com.googleusercontent.apps.123-example`. Preserve the existing `tender` scheme. The implemented callback is that reversed scheme followed by `:/oauthredirect`.
6. Rebuild/install from Current. Open **Settings → Subscription Emails**, or **Activity → Recurring → Trials & subscription emails**. Connect each address separately, then tap Check Emails. Live OAuth, refresh-token issuance and multiple-account behavior still require device verification.

Google's [iOS API access guide](https://developers.google.com/identity/sign-in/ios/api-access) documents the iOS client, bundle identifier and reversed URL scheme. This implementation uses a native system authentication session with PKCE/state and REST token exchange, rather than adding the Google Sign-In SDK.

## Privacy and release constraints

- `gmail.readonly` is a **restricted**, mailbox-wide permission. A search query is not a permission restriction. The app explains this before opening Google.
- Google requires restricted-scope verification for public use. Server storage/transmission of restricted data can require a security assessment. On-device parsing is a design choice, not a promise of approval or exemption. Review the [official Gmail scope requirements](https://developers.google.com/workspace/gmail/api/auth/scopes) before public release.
- Each address has its own access/refresh tokens in device-only Keychain storage. Tokens are absent from ledger exports and logs. No passwords, client secrets or Cloudflare email-processing service are needed by this implementation.
- Processing runs on the phone. Raw MIME responses are transient; email links and attachments are not opened. Saved data includes mailbox address, subject/short preview, sender-derived service name, received date and extracted candidate fields. Those details are included in explicit ledger exports/backups.
- Disconnect removes that address's local credentials and evidence; confirmed subscriptions/source labels remain. Full deletion clears Gmail credentials and local ledger data. Users can revoke the Google grant in their Google Account. Exported files must be deleted separately.
- Restore deliberately clears connected-mailbox registrations, requiring fresh consent/reconnection. Existing Keychain entries are not imported from backups.

## Behavior and chosen defaults

- Bank history creates **estimates** for review. Ignore hides a candidate; Review ignored suggestions again restores the queue. Balance changes alone cannot detect subscriptions.
- Optional Gmail supports up to 20 connected addresses. It searches the last year, at most 500 matching messages per address per check. Parsed-message identity includes mailbox + message ID; subscriptions with similar names across addresses are not automatically merged.
- Check on foreground entry and approximately every 15 minutes while active; manual Check Emails bypasses the cooldown. Existing bank refresh stays at approximately five minutes while active. Neither is guaranteed background delivery or a live bank balance.
- No Google push receiver, Gmail history cursor or bank webhook service was deployed. Large inboxes beyond the bounded window need a later incremental-sync implementation. Unmatched emails may be fetched again; reviewed evidence is deduplicated.
- English phrase/date/dollar parsing is heuristic, not AI. Currency field is explicitly USD. Unknown/ambiguous values need review. Dates require an explicit confirmation switch; frequencies and prices remain editable. Missing trial prices may be saved as unknown, excluded from cost totals.
- Trials default to an optional reminder three days before at 9 AM; other renewals one day before at 9 AM. Notifications require permission and a future reminder time; only the nearest 60 combined bill/shopping notifications are scheduled.
- Cancellation notices require choosing the existing subscription and confirming. Confirming stops Tender reminders/forecasts; it never cancels with a provider. Cancellation date uses the notice's received date (or today's date if later).
- Matching posted bank charges on later calendar days produce a **possible charge after cancellation** note. Merchant matching can misidentify unrelated purchases; account-specific matching and same-day precision are follow-up work. It does not silently reactivate the subscription.
- User-confirmed records can be cancelled/resumed manually. Old expenses stay intact. Trials without price can be cancelled without entering a fictional amount.
- Paste a subscription notice works without Gmail setup. It saves a short preview plus extracted data, then sends the candidate to the same review queue.

## Loading page

`LedgerLoadingView` uses existing engraved lines, paper/green colors, a serif Tender wordmark and a native progress indicator. No artificial wait or custom motion. Local ledger loading stays detached; bank/mail work starts after Home appears. This is the app's initial loading view, not a way to display UI before iOS launches the process.

## Verification boundary

Simulator-target compilation only. No UI/device/OAuth/email/bank/notification tests, installation, deployment or paid services. User owns functional testing. Public distribution and live Gmail access remain setup-dependent.
