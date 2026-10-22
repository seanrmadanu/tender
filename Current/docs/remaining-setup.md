# Remaining work after the 18-item audit

October 21, 2026. User confirmed a free Personal Team and no Google OAuth setup.
No paid enrollment, new provider account, live bank call, or deployment was made.

## #1, #17 and online portion of #18: consumer accounts

The personal bank bridge is a single encrypted vault behind an owner token.
Hiding that token or shipping it in the app would not create separate accounts.
The personal build reuses saved Keychain setup, but first-time consumers still
need a real authentication system before bank onboarding can be token-free.

Next setup and implementation steps:
1. Create a Google Cloud OAuth consent configuration and an **iOS OAuth client**
   for the existing bundle ID `com.sean.tender`, plus the server audience/client
   configuration needed to verify identity. Keep secrets outside Git and chat.
2. Add Google Sign-In, validate the ID token on the backend (issuer, audience,
   expiration and signature), and issue revocable Tender sessions.
3. Route every bank request to a vault derived from the authenticated user,
   never a client-supplied user ID. Keep the existing personal vault separate
   until an explicit owner migration is reviewed.
4. Test user A/B isolation, token expiry/revocation, account switching, logout,
   per-user Item removal, and deletion of sessions and server data. Implement
   provider revocation/deletion as appropriate before offering Delete Account.
5. Add Apple sign-in after compatible Apple membership/capabilities are ready.
   The free Personal Team configuration is preserved here.

Official setup: [Google iOS sign-in](https://developers.google.com/identity/sign-in/ios/start-integrating),
[server verification](https://developers.google.com/identity/sign-in/ios/backend-auth),
[Apple capability setup](https://developer.apple.com/documentation/xcode/configuring-sign-in-with-apple).

## #13: native iCloud

Complete backup and restore through Files → iCloud Drive are implemented.
Automatic container access/sync is not. Compatible Apple capability provisioning
is required; then add a ubiquity container, coordinated file access, conflict
handling and two-device restore tests. Simply enabling an entitlement is not a
complete sync implementation. See [Apple capability availability](https://developer.apple.com/help/account/reference/supported-capabilities-ios).

## #2: Capital One

Safe Hosted Link diagnostics exist in the imported app/backend source. They do
not establish the cause of the reported generic browser error. After reviewing
and deploying the backend update, reproduce the flow on the phone and inspect
only code/type/request ID/Link session ID from Share Diagnostic. Check supported
account type, provider institution status and OAuth configuration. Preserve the
working bank connection and use Repair Login for an existing Item.

## Local implementation versus live rollout

The bank transaction sync and richer diagnostics require deploying the updated
Worker. Its encrypted-chunk adapter can read the old vault; after the first new
write, the old backend reader cannot read chunks. Preserve all existing secrets,
DO identity and the new storage adapter for rollback. App-only rollback remains
separate. No deployment was performed by the import/audit work.

Physical-device verification still needed: real receipt/shelf OCR, microphone
permissions and speech recognition, notification delivery, iCloud Files backup
and restore, live transaction reconciliation, Capital One, and privacy deletion
on a deliberately disposable record set. Do not wipe real records to prove a
screen works.
