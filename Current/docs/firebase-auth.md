# Firebase authentication — October 23, 2026

## Implemented

The supplied GoogleService-Info.plist is bundled for project tender-84bd7 and bundle com.sean.tender. Firebase's documented HTTPS REST API provides email/password registration, sign-in and password reset. Passwords are transient form state; only Firebase session/refresh tokens and minimal account identity are stored in device-only Keychain under com.sean.tender.auth. No Firebase SDK is installed.

Launch reads the previously verified identity from device-only Keychain and opens its saved local ledger without waiting for Firebase. An expired token does not prevent offline access to that local data. Before bank requests, expiring tokens are renewed and the returned UID/account status are verified; concurrent renewal callers share one request. The Worker independently verifies authorization for every bank request. A locally displayed screen never authorizes remote access. Failed Keychain restoration preserves the ledger and shows sign-in. Sign Out removes the session, drops the mounted ledger view and clears notifications. Email verification is not currently enforced; never authorize bank migration or ownership based on email text.

Every user has a separate local path: Documents/TenderAccounts/SHA256(project + UID). Gmail credential account keys include that same scope. Existing Documents/Tender and old Gmail credentials are not imported into a new login. Explicit backup imports are still possible. Local data is not synced to Firebase/cloud and there is no cross-device ledger recovery unless the user exports a backup.

Continue with Google implements a native browser OAuth code flow with PKCE, state and nonce/client checks, then exchanges Google's identity token with Firebase. Firebase validates the identity token; decoded claims alone never unlock a ledger. It requests openid/email/profile only, separately from optional Gmail permissions.

## Google configuration integrated — v4.5.1

The updated user-supplied Firebase plist now contains CLIENT_ID and REVERSED_CLIENT_ID for project tender-84bd7. Its matching callback scheme is registered in Tender's Info.plist alongside the existing Gmail and shopping schemes. Continue with Google can now start the implemented OAuth-to-Firebase flow after rebuilding/installing this version.

User screenshots show Email/Password enabled and the Google provider's updated-configuration download prompt. Live provider sign-in remains untested. Use Email/Password, not the separate Email link (passwordless) option, which this app does not implement. The earlier TenderGoogleClientID remains dedicated to Gmail authorization in the separate Google project; Gmail Test users/consent are independent.

Apple and phone remain marked as setup-dependent. Apple developer/provider configuration and phone app verification/delivery/billing must be completed before enabling them. No paid services or external account changes were made.

## Account bank integration — October 24, 2026

Signed-in requests now use Firebase ID tokens at `/v2/*`. The Worker verifies the RS256 signature using Google's published certificates, checks project/issuer/time/UID claims, and looks up the account with Firebase on every request to reject deleted, disabled or revoked sessions. The app refreshes expiring tokens before bank requests and rejects results after a user switch.

`AccountBankVault` stores each verified project/UID in a separate Durable Object, keyed by the SHA256 scope used by the local ledger. Caller-supplied owner headers are replaced at the Worker boundary. Link sessions, repair, token exchange, balances, transactions and disconnect all stay within that vault. The original `/v1/*` personal vault remains separate; old personal links are never automatically imported or claimed by email.

Accounts now offers Import Bank Account via Plaid and Add Info Manually. Plaid starts the existing secure hosted browser flow. Manual entry first explains the responsibility to maintain balances/purchases, with Continue, Add Account via Plaid and Go Back. Cash on hand can be saved on the initial Accounts page; updating it replaces the existing cash wallet balance instead of adding duplicate cash. Bank update preferences are also scoped per user.

Deployed October 25, 2026 as Cloudflare version `78b37504-cc34-4845-8c6f-94cd6b7b12ce`; live health and unauthorized-request smoke checks passed. Real-user sign-in/bank linking remains unverified. Deployment includes the updated Worker and its new `ACCOUNT_BANK_VAULT` migration, plus the public Firebase project/API configuration in `backend/wrangler.jsonc`. Existing Plaid/encryption secrets stay unchanged. The local Node personal bridge still implements only `/v1`; account requests use the configured Cloudflare endpoint. A new iPhone app build is required. Live sign-in/Plaid success must be tested on that build; mocked tests and compilation do not establish it.

References: [Firebase ID-token verification](https://firebase.google.com/docs/auth/admin/verify-id-tokens), [session revocation](https://firebase.google.com/docs/auth/admin/manage-sessions), and [account lookup](https://docs.cloud.google.com/identity-platform/docs/use-rest-api).

## Full Reset App

Settings → Reset App offers a backup and confirmation. If old personal bridge credentials exist, existing remote disconnection is attempted first; failure aborts reset. Missing credentials show the existing warning that remote access cannot be verified. A successful full reset erases all local Tender/TenderAccounts directories, all Gmail and bank credentials, Firebase session credentials, app preferences/cookies/cache and notifications. The root clears the in-memory login and returns to Welcome. Exported backups, Firebase's online user account, Google grants and OS browser/device accounts are not deleted. Sign in again to start a fresh local ledger. No reset or live account operation was executed during implementation.

## Verification

Compilation only, per user instruction. No live sign-up/email/password-reset/OAuth/reset/UI/device tests, installations or deployment. Test provider enablement, auth restoration and cross-account isolation on the device before relying on this build. Source docs: https://firebase.google.com/docs/reference/rest/auth and https://developers.google.com/identity/sign-in/ios/start-integrating .
