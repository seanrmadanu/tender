# Bank connection options

Checked against Plaid iOS and billing documentation on October 21, 2026. The user selected **Plaid's free US/Canada Trial**. Tender includes the official native Link SDK and a personal-use backend. The user has created a Plaid account. No real bank is connected. Local bridge access/encryption keys are initialized; Plaid credentials and a host still need configuring.

## Cost constraint

The requested budget is free or approximately $15 per year. Plaid pricing does not include the separate backend host or domain; their total cost has not been established. Use the manual ledger while deciding whether that setup fits the budget.

- **Plaid Trial:** Current documentation says new US/Canada teams can apply for a free Trial plan with up to 10 Production Items, including Balance and Transactions. Deleting an Item does not recover its Trial slot. The free sandbox contains test data. Paid pricing is visible in the Plaid Dashboard and is not guaranteed to fit the budget. [Pricing and billing](https://plaid.com/docs/account/billing/), [Trial eligibility](https://support.plaid.com/hc/en-us/articles/39994173227159-What-is-the-Plaid-Trial-plan).
- **SimpleFIN Bridge:** Advertises $15 per year **plus tax**, or $1.50 per month plus tax, with up to 25 institutions and 25 apps. Check bank coverage before subscribing. [Pricing](https://beta-bridge.simplefin.org/).

## Included Plaid implementation

The app requests a short-lived Link token from the authenticated backend, presents LinkKit 7.2.2, and returns its public token to that backend. The backend exchanges it for an access token and stores it with AES-256-GCM encryption. The app's bridge access token is stored in iOS Keychain as accessible only when unlocked, on this device. API secrets and Plaid access tokens stay on the backend.

The backend returns checking/savings account snapshots with currency, retrieval timestamp, and separate current/available balances. Missing available balances stay unknown. Credit accounts are excluded and non-USD balances cannot become ledger cash. Cached and fresh results are labeled. Applying a result explicitly replaces a selected account snapshot or creates a new account; it does not import transactions. Sandbox values are display-only for testing and cannot enter the ledger. Production values require a personal ledger.

The backend initializes the Transactions product to enable the account connection; automatic transaction ingestion is not implemented. Review requested permissions in Link. Transactions can have recurring charges after upgrading to a paid plan. The user-selected free Trial covers this product under the current terms.

For an expired login, choose **Load Existing Connections → Repair Login**. The backend creates an update-mode Link token using the saved access token, omits new-product initialization, and the app does not exchange a second public token. This follows [Plaid's update-mode guidance](https://plaid.com/docs/link/update-mode/). New connections carry the institution name returned by Link. Older connections may still have generic numbered labels. A deliberately new connection still consumes a Trial slot; repairing a login reuses its existing Item.

## Setup

1. Create a [Plaid developer account](https://dashboard.plaid.com/signup), verify email, and apply for the free Trial if eligible. Accept provider terms yourself. Start with sandbox keys and confirm the integration before using production keys.
2. Double-click **Set up Plaid.command** in the main project folder (or run `python3 scripts/configure-bank.py` there). Select the countries enabled on your Plaid account (US is the default), then paste the client ID and Sandbox secret into its hidden local prompts. The assistant writes `backend/.env` with owner-only permissions; keys never appear in chat or command output. Start with `sandbox`. If Finder blocks the launcher, run the Python command in Terminal.
3. The setup assistant generates `TENDER_API_TOKEN` and a base64 32-byte `TENDER_ENCRYPTION_KEY` only if missing and preserves them on later runs. Back up the encryption key and encrypted data file together through a secure mechanism; losing them can consume Trial slots unnecessarily.
4. Set `PLAID_REDIRECT_URI` to `https://YOUR_DOMAIN/plaid/oauth`, add the exact URI in Plaid's dashboard, and configure `APPLE_TEAM_ID` and `APPLE_BUNDLE_ID`. Use a domain you control.
5. From `backend/`, run `npm start` with Node 22 or newer. No npm dependencies are required. The default listener is `127.0.0.1:8787`. The server must sit behind a trusted HTTPS endpoint for an iPhone; the shared bearer token makes this a **single-user personal backend**, not a multi-user production service.
6. Serve `/.well-known/apple-app-site-association` on that HTTPS host, without redirects. The backend generates it from the configured team and bundle ID. In Xcode, add **Associated Domains** with `applinks:YOUR_DOMAIN`. Match the app bundle ID and signing team. The example entitlement is in this folder and is not enabled until you supply the real domain.
7. In Tender, open the balance card's arrow → **Connect with Plaid → Connection Setup**. Enter the HTTPS bridge address and `TENDER_API_TOKEN` (not a Plaid secret). Save, then select **Test Connection**. A successful test confirms the bridge and app token, not bank access. Next select **Connect a Bank**.
8. Check sandbox connections and balance retrieval. When the Trial and live configuration are ready, use production credentials with a separate `TENDER_DATA_FILE` (for example `./data/bank-links-production.enc`), retaining the sandbox file and its key. Do not point production at a file containing sandbox access tokens. Start a personal ledger before applying any real balance.

Endpoints: `GET /v1/status`, `POST /v1/link-token` (empty body for a new link, or `{"itemID":"saved-item-id"}` for repair), `POST /v1/exchange`, `GET /v1/connections`, `GET /v1/accounts` (cached), `POST /v1/balances/refresh` (fresh), and `DELETE /v1/connections`. All require the app bearer token. Fresh refreshes are limited to one per minute. `/health` and the Universal Link association file are public. Tokens and provider payloads are never logged. The backend uses a 30-second provider timeout and encrypted atomic persistence.

Live OAuth banks need a registered HTTPS redirect URL, Associated Domains, and an apple-app-site-association file. A custom `tender://` scheme cannot replace that OAuth Universal Link. [Plaid iOS integration](https://plaid.com/docs/link/ios/).

`/accounts/get` provides cached balances; fresh balance retrieval uses a different product endpoint. Unknown available balances, stale data, credit limits, and non-USD accounts must not silently become spendable cash. Imported bank balances need reconciliation with local expenses so refreshes do not double count or drop pending spending. [Balance documentation](https://plaid.com/docs/balance/).

Activation still needs confirmation of supported banks and Trial/Production access, backend hosting, a Universal Link domain, and Apple signing configuration. The existing Xcode signing team is retained. The SDK/API code has been prepared, but no real provider call or live bank connection has been verified. A configured bridge is not labeled as a connected bank.

## Multiple accounts

In Plaid Dashboard → Customize → Link, configure Account Select to allow multiple accounts, then publish the customization. See [Plaid Account Select](https://plaid.com/docs/link/customization/#account-select). Connect a bank, select its checking/savings accounts in Plaid, then use **Add This Account…** for each returned snapshot. For a bank you already entered manually, select that existing account in the application sheet. Known provider account IDs always update their existing ledger account.

Use **Add Another Bank** for a different bank login. Use **Load Existing Connections → Repair Login** for an existing login; update mode also enables account selection so you can authorize additional accounts without creating another Item. Previously imported ledger snapshots remain until you change them, including accounts you stop sharing. Balances from all saved bank connections are returned together, with institution names and account masks. Manual accounts are added independently in **Accounts → Add manual account**. Credit cards and non-USD cash are outside the current cash-balance model.

## Local Sandbox check

Configure the registered HTTPS redirect URL first, including for native iOS Sandbox Link. Run `npm start` from `backend/`, then use `http://127.0.0.1:8787` in the iOS Simulator with the local `TENDER_API_TOKEN`. The localhost address refers to the Mac only in the simulator; a physical iPhone needs an HTTPS bridge. OAuth Sandbox testing also needs Universal Links. Do not treat a Sandbox connection as access to real money.

The setup assistant selects a separate encrypted token store for each environment. Existing encryption keys are retained, and newly written stores record their environment so accidental cross-environment loading fails closed. If manually changing environments, also change `TENDER_DATA_FILE`. Never delete token stores to retry a Trial connection.

## SimpleFIN implementation boundary

The user creates a one-time setup token with the provider. The app exchanges it over HTTPS for a read-only access URL and stores that credential in the iOS Keychain. The native app can fetch account snapshots without a separate app backend. Handle provider errors, rejected/reused tokens, absent available balances, unsupported currencies, timestamps, and a manual disconnect. The provider’s update schedule determines freshness; an app refresh is not proof of a live bank balance. [Protocol](https://www.simplefin.org/protocol.html).

SimpleFIN is an unimplemented alternative. No subscription, deployment, or bank connection has been made.
