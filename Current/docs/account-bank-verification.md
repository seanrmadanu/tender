# Accounts and signed-in Plaid update — October 24, 2026

## Cause and changes

The logged-in screen was intentionally a placeholder because the previous Worker authorized a shared personal vault. The new account path verifies Firebase identity and routes every bank operation into a separate account vault. It preserves the personal namespace and encrypted state.

The Accounts screen removes the “No bank connection needed” section. Two separate rows offer Plaid import or manual entry, separated by “or”. The manual sheet explains maintenance responsibility and offers Go Back, Continue and Add Account via Plaid. The initial Accounts page includes cash-on-hand entry and explicit Add/Update Cash. Balances use existing exact-cent parsing and snapshot logic.

## Verification

- Simulator target build: passed.
- Financial core: 39 tests passed.
- Backend: 32 tests passed, including Cloudflare runtime tests with mocked Firebase and Plaid.
- Authentication tests reject modified signatures, wrong project/issuer, expired/future claims, unknown keys, unsupported algorithms, disabled/revoked users and unavailable auth services.
- Account-vault tests cover another user's sessions, owner-header spoofing, repair IDs, balances, activity, deletion and separation from the personal token/vault.
- Worker deployment dry run: passed with both vault bindings and additive migration.
- UI: account persistence, explanation dismissal/continuation, switching to Plaid, cash persistence and updating without duplicate cash all passed in focused simulator tests. The final dark-mode screenshot check is recorded with the test artifacts.

## Rollout status

Deployed on October 25, 2026 after explicit user approval. Cloudflare version: `78b37504-cc34-4845-8c6f-94cd6b7b12ce`. Both personal and account vault bindings are present; the account-vault migration is additive. Existing bank links and local ledgers were not reset or imported.

Live smoke checks passed: `/health` returned HTTP 200 with `configured: true` and `accountAuthConfigured: true`; missing credentials on personal/account endpoints, an unauthorized hosted-link request with a spoofed owner header, and a fake Firebase token with an unknown signing key all returned HTTP 401. The final check also exercises fetching Google's real public signing certificates. These checks do not establish successful real-user Firebase lookup or Plaid linking.

Rebuild/install the updated iPhone app and verify a real signed-in Plaid connection on the phone. Deploy and smoke evidence: `build/account-bank-update/deploy-oct25.log` and `live-smoke-oct25.json`.

Screenshots: [Accounts](../build/account-bank-update/accounts.png), [manual explanation](../build/account-bank-update/manual-explanation.png), [cash update](../build/account-bank-update/cash-saved.png).

Commands and result artifacts are local under Current/build/account-bank-update. No real Firebase login or bank linking was performed by these tests. The Worker is published; rebuilding/installing on iPhone and a real-user bank connection test remain.
