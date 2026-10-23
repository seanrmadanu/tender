# Account login foundation — October 23, 2026

## Current state: setup required, NOT working authentication

Normal launch now opens WelcomeLoginView with email, Google, Apple and phone choices. Every choice explains that authentication is not configured. There is no fake sign-in, password collection, fabricated session or guest bypass. The existing personal ledger does not load and bank/Gmail refresh tasks do not run. Existing local files and Keychain entries have not been deleted by this code change.

The app cannot currently advance from this page. This is intentional until real sessions and bank-vault ownership are implemented. Do not distribute as a working login build. The prior usable personal edition is Git checkpoint 37f14da; keep it available until account setup is complete.

## Recommended service and remaining work

Use Firebase Authentication with the existing Google Cloud project tender-512506. No Firebase project was created or service configured by this revision. The existing Google iOS OAuth client authorizes Gmail access; it is not a Firebase configuration or a Tender backend session.

1. In https://console.firebase.google.com/ add Firebase to the existing Tender Google Cloud project. Register the iOS app with bundle ID com.sean.tender and download its GoogleService-Info.plist. Enable Authentication providers (email and Google first). Provider configuration and live sign-in still require account-owner setup.
2. Integrate FirebaseAuth/Core and Google Sign-In SDKs, initialize the app, use real provider credentials, and handle verified sessions, refresh, sign-out, account linking and deletion. Request Gmail permission separately after login; never require mailbox access to sign in.
3. Configure Apple developer capability/provider credentials before enabling Apple. The user last reported a free Personal Team; do not assume native Sign in with Apple capability is available.
4. Phone sign-in needs provider setup, app verification and delivery/billing review before enabling SMS. No paid services or billing were enabled.
5. Validate Firebase ID tokens in the Cloudflare Worker (signature, issuer, audience, expiry and appropriate account state). Route each bank vault by the verified UID, not a request-supplied email or user ID. The current Worker uses one personal vault/token and must not be shared across logins.
6. Store local ledgers, receipts and Gmail credentials per verified UID. Do not assign the existing personal ledger/bridge token to whichever Google address signs in first. Make any owner migration deliberate and recoverable.
7. Replace the temporary showLogin state in TenderApp with the authenticated-session state machine. Mount/load the correct per-user LedgerStore only after authentication. This revision has no path that sets showLogin false.
8. Wire return from auth callbacks, cancellation/errors, session expiry and deep links. Until then shortcuts cannot bypass the welcome page.

Official setup: https://firebase.google.com/docs/auth/ios/start
Phone prerequisites: https://firebase.google.com/docs/auth/ios/phone-auth

## Reset App

Settings → Your data → Reset App opens a dedicated reset screen reusing the existing deletion logic. It offers a confirmation, Save Backup Then Delete, and Cancel. After successful reset it clears preferences, pauses bank access and posts resetToLogin to the application root. The normal login-first route means Settings becomes reachable again only once real authentication is wired.

Reset clears local ledger, photos, recovery copies, Gmail credentials and bank credentials through the existing eraseLocalData path. Saved bank connections are revoked first when bridge credentials are available. Remote revocation failures stop the reset and report an error; missing credentials produce the existing warning that old remote access cannot be verified. Exported Files backups and Google permission grants are not removed. No online Tender account exists to delete yet.

No automatic data wipe runs on upgrade or installation. Replacing an app with Xcode normally retains its sandbox, so showing Welcome is not proof of erasure. The reset action itself must succeed to erase existing local records. No device reset or install was performed this turn.

## Validation

Simulator-target compilation passed in build/oct23-login-reset-final-build.log. No unit/UI/device/live-auth/reset tests were run, per user preference. Manual behavior testing remains with the user. Provider setup, backend user isolation and an authenticated route into Home remain incomplete.

## Full reset follow-up

AppReset now clears Tender auth-service Keychain entries, app preferences, app HTTP/WebKit caches and cookies, and pending/delivered notifications. Existing deletion clears Gmail/bank credentials and financial files; successful reset replaces the in-memory LedgerStore and returns to login. This does not sign out of Safari or device Google/Apple accounts. There is no live Tender login session yet. Integrating a provider SDK requires adding its signOut/cancel/credential cleanup to this coordinator; clearing a reserved Keychain namespace does not substitute for SDK session deletion. Build-only verification passed in build/oct23-full-reset-build.log.
