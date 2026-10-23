# Firebase authentication — October 23, 2026

## Implemented

The supplied GoogleService-Info.plist is bundled for project tender-84bd7 and bundle com.sean.tender. Firebase's documented HTTPS REST API provides email/password registration, sign-in and password reset. Passwords are transient form state; only Firebase session/refresh tokens and minimal account identity are stored in device-only Keychain under com.sean.tender.auth. No Firebase SDK is installed.

Launch restores a saved session by exchanging its refresh token and looking up the account with Firebase before opening a ledger. Failed restoration leaves the ledger closed and preserves data. Sign Out removes the session, drops the mounted ledger view and clears notifications. Session validation happens at entry; future online bank requests must validate/refresh their own authorization rather than treating a locally displayed screen as server authorization. Email verification is not currently enforced; never authorize bank migration or ownership based on email text.

Every user has a separate local path: Documents/TenderAccounts/SHA256(project + UID). Gmail credential account keys include that same scope. Existing Documents/Tender and old Gmail credentials are not imported into a new login. Explicit backup imports are still possible. Local data is not synced to Firebase/cloud and there is no cross-device ledger recovery unless the user exports a backup.

Continue with Google implements a native browser OAuth code flow with PKCE, state and nonce/client checks, then exchanges Google's identity token with Firebase. Firebase validates the identity token; decoded claims alone never unlock a ledger. It requests openid/email/profile only, separately from optional Gmail permissions.

## Google setup still required

The uploaded plist contains API_KEY, PROJECT_ID, GOOGLE_APP_ID and BUNDLE_ID, but **no CLIENT_ID or REVERSED_CLIENT_ID**. Google account sign-in cannot run with this file. Do not substitute the earlier OAuth client from tender-512506 for the Firebase project's client without explicitly configuring provider trust.

In Firebase console → tender-84bd7 → Authentication → Sign-in method, enable Email/Password and Google, set Google's support email, and save. Download the updated iOS GoogleService-Info.plist from Project Settings. Supply that file so its CLIENT_ID and matching reversed URL scheme can be integrated. Provider enablement has not been inspected or changed by the assistant. The earlier TenderGoogleClientID remains dedicated to Gmail authorization in the separate Google project; Gmail Test users/consent are independent.

Apple and phone remain marked as setup-dependent. Apple developer/provider configuration and phone app verification/delivery/billing must be completed before enabling them. No paid services or external account changes were made.

## Bank integration boundary

Account-based bank access is disabled in this build. The existing Cloudflare Worker has one personal vault and token; it does not validate Firebase user identity or route vaults by verified UID. The account screen and automatic bank refresh cannot access that personal bridge. Manual accounts, cash, groceries and local ledger features are available after valid Firebase sign-in. Existing personal bank data remains in the old local ledger and remote vault.

Next backend work: validate Firebase ID-token signature/issuer/audience/expiry, bind every bank vault/operation to its verified UID, handle sessions/revocation, and make any migration of the personal vault deliberate. No Worker was deployed in this revision.

## Full Reset App

Settings → Reset App offers a backup and confirmation. If old personal bridge credentials exist, existing remote disconnection is attempted first; failure aborts reset. Missing credentials show the existing warning that remote access cannot be verified. A successful full reset erases all local Tender/TenderAccounts directories, all Gmail and bank credentials, Firebase session credentials, app preferences/cookies/cache and notifications. The root clears the in-memory login and returns to Welcome. Exported backups, Firebase's online user account, Google grants and OS browser/device accounts are not deleted. Sign in again to start a fresh local ledger. No reset or live account operation was executed during implementation.

## Verification

Compilation only, per user instruction. No live sign-up/email/password-reset/OAuth/reset/UI/device tests, installations or deployment. Test provider enablement, auth restoration and cross-account isolation on the device before relying on this build. Source docs: https://firebase.google.com/docs/reference/rest/auth and https://developers.google.com/identity/sign-in/ios/start-integrating .
