# Tender bank setup

Updated October 21, 2026. The current app is the **main project** at `Money app/Current/Tender.xcodeproj`. Its baseline includes the changes from `Money app/Archives/v2`; historical versions remain unchanged. The active continuation is now labeled v3 in `Current/VERSION.txt`.

## Current deployment

- Bridge: https://tender-bank-bridge.tender-bank-bridge.workers.dev
- Cloudflare Worker: `tender-bank-bridge`, using SQLite-backed `BankVault` Durable Object storage.
- Cloudflare dashboard verified **Free · $0 · Current plan**. No domain purchase or paid plan is needed for this deployment.
- Plaid dashboard verified free US/Canada Trial with 0/10 connections used before setup. Chase and Capital One are the requested banks; actual authorization and account coverage must be verified in Plaid Link.
- Apple signing: free Personal Team. The app opens Hosted Link in the **external browser**, then verifies completion when you return and tap **Check Connection**.
- Public HTTPS health check succeeds. Private Plaid credentials and real bank authorization are separate remaining steps; deployment alone does not prove bank connectivity.

Workers and SQLite Durable Objects have free-tier limits. On the Free plan, exceeding a limit causes requests to fail instead of automatically enabling paid usage. Keep the account on Free. Plaid Trial allows up to 10 Production Items; deleting a connection does not restore its Trial slot. Do not upgrade Plaid or Cloudflare without reviewing their pricing. [Cloudflare Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [Durable Objects pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/), [Plaid billing](https://plaid.com/docs/account/billing/).

## Finish private configuration

1. In the Money app folder (or Current subfolder), double-click **Set up Cloudflare Plaid.command**. It opens a local Terminal helper. If Finder cannot launch it, run `python3 scripts/configure-cloudflare.py` from this folder in Terminal with Node 22+ available on PATH.
2. Keep **production** and **US**. From your Plaid Dashboard's Production keys, enter the Client ID and secret into the hidden prompts. They will not appear while typing. Do not enter bank passwords, one-time codes, or keys into chat.
3. The helper keeps an owner-only, Git-ignored `backend/.env`, preserving existing bridge/encryption keys. It uploads four secrets to **your Tender Cloudflare Worker**: `PLAID_CLIENT_ID`, `PLAID_SECRET`, `TENDER_API_TOKEN`, and `TENDER_ENCRYPTION_KEY`. Secrets go through stdin to Cloudflare's official CLI, not command-line arguments or temporary JSON files. Worker source and the iPhone app contain no Plaid secret.
4. The helper tests the authenticated bridge and copies **only the bridge access token** to your Mac clipboard. In Tender: **Accounts → Connect with Plaid → Connection Setup**. The deployed HTTPS address is prefilled. Paste the bridge token, then **Save Connection Settings → Test Connection**. On another device, transfer this token privately. Never put the Plaid secret in the app.
5. Choose **Connect a Bank**. Complete the Plaid/bank login yourself in the browser. Return to Tender and tap **Check Connection**. A browser redirect is not treated as proof of success: the backend verifies Plaid's session result and saves the bank link.
6. Review each checking/savings snapshot and select **Add This Account…**. If you already entered that account manually, select it to avoid counting the same cash twice. Connect the other bank with **Add Another Bank**.

If a browser session was interrupted, reopening Bank Connect restores the pending session from the backend. **Resume Bank Login** reuses its URL while valid; **Check Connection** retrieves its result. New Hosted Links last 30 minutes; completion metadata remains available for a limited period. Do not repeatedly create new connections to fix a problem.

The helper requires the existing Wrangler login. If it expired, run `cd backend && npx wrangler login --scopes account:read user:read workers_scripts:write` and review Cloudflare's authorization screen. Keep the access/encryption keys backed up securely. Losing or replacing the encryption key prevents access to stored bank tokens. Do not delete the Worker, its Durable Object namespace, or its storage to troubleshoot a bank login.

## Why browser login

Plaid's native iOS SDK uses an HTTPS Universal Link with Associated Domains. This deployment uses Plaid's documented browser-hosted flow so the free Personal Team can remain in use. `hosted_link.is_mobile_app` is **false** because the URL opens in the external browser, not `ASWebAuthenticationSession` or an embedded webview. No email/SMS delivery is requested. Plaid handles web authentication; the completion page asks you to return to Tender. [Hosted Link](https://plaid.com/docs/link/hosted-link/), [Link API](https://plaid.com/docs/api/link/).

Native LinkKit remains available for a separately configured `TENDER_LINK_MODE=native` backend. That mode requires `PLAID_REDIRECT_URI`, a registered HTTPS redirect, `APPLE_TEAM_ID`, a matching bundle identifier, an AASA file and Associated Domains signing. A custom URL scheme is not a substitute for the native OAuth Universal Link. [Plaid iOS](https://plaid.com/docs/link/ios/).

## Multiple accounts and manual accounts

**Accounts → Add Manual Account** needs only a nickname and balance. Open an account to add a purchase using that account or update its recorded balance. New purchases deduct from the selected balance. For an old purchase already reflected in your balance, disable **Deduct from current balance**. The app can be used manually without any Plaid connection.

In Plaid Dashboard → Customize → Link, enable multiple-account selection if necessary. For an existing bank, **Load Existing Connections → Repair Login** also enables additional account selection. It reuses the existing Item and access token. Each saved bank is fetched independently; a failed bank does not hide successful results from another. Stable provider account IDs ensure repeat snapshots update existing ledger accounts instead of duplicating cash. [Account Select](https://plaid.com/docs/link/customization/#account-select), [Update mode](https://plaid.com/docs/link/update-mode/).

Only depository accounts are returned. USD **available** balances can enter the ledger; unknown balances, credit limits, foreign currencies and Sandbox values cannot become spendable cash. Cached and fresh snapshots are labeled. No transactions are imported automatically: the Transactions product initializes the connection, while purchases are still entered manually. Review pending purchases when applying a bank snapshot. [Balance](https://plaid.com/docs/balance/).

## Backend behavior and maintenance

`backend/bridge.mjs` is shared by the Node and Cloudflare adapters. `server.mjs` uses an encrypted atomic local file. `worker.mjs` stores an AES-256-GCM encrypted vault in a SQLite-backed Durable Object, separated by Plaid environment. No request bodies, bank tokens or provider payloads are logged. Requests are serialized within the personal vault; bank reads run concurrently; fresh refreshes are limited to once per minute with the limit persisted across restarts. Interrupted one-use token exchange fails closed rather than silently repeating it.

Authenticated endpoints: `GET /v1/status`, `GET/POST /v1/hosted-link`, `POST /v1/hosted-link/finish`, `GET /v1/connections`, `GET /v1/accounts`, `POST /v1/balances/refresh`, `DELETE /v1/connections`. Native mode additionally uses `POST /v1/link-token` and `POST /v1/exchange`. `/health` and `/bank-complete` are public; no financial data is present on those pages. The bearer token makes this a **single-user personal backend**, not a multi-user service.

From `backend/`: `npm ci`, `npm test`, then `npm run deploy` to publish verified changes. Wrangler is pinned through the lockfile. Keep secrets out of `wrangler.jsonc` and source control. The account ID pins deployment to the intended Cloudflare account. Redeploying code preserves the Durable Object vault. Rolling back the Worker should preserve the same binding, class and storage format; never roll back by deleting storage.

Node-only hosting remains supported through `Set up Plaid.command` and `npm start`. Sandbox and Production require separate encrypted files. For a local browser-mode test, configure `TENDER_LINK_MODE=browser` and an HTTPS `TENDER_PUBLIC_URL`; a physical iPhone cannot use the Mac's localhost address. Sandbox snapshots remain excluded from the personal ledger.
