# Verification — October 21, 2026

The main project in `Money app/` now contains the V2 continuation plus the current fixes. Version folders remain as historical snapshots. The pre-integration root source is preserved under ignored `build/before-v2-integration/`.

## Verified on this Mac

- **18 Swift core tests passed.** Exact-cent arithmetic, shopping/reserves, monthly and leap-year recurrences, complete backup validation, legacy decoding, empty defaults, multiple bank snapshots without duplicate cash, matching a manual account, rejection of Sandbox/unknown balances, and selective sample cleanup preserving real entries and attachment references.
- **10 Node backend tests passed using a mocked Plaid provider.** Authentication, encrypted storage, login repair/account-selection update mode, malformed input, persistence/restart, throttling, disconnect retry, multiple banks/accounts, institution labels, and partial bank failures. These do not prove live Plaid connectivity.
- **6 iPhone 17 simulator UI tests passed** on iOS 26.2. Expense persistence, multiple manual-account persistence, grocery observations with a store, prices entered during item creation and through the top Save Price button without a store, price history after relaunch, navigation/shopping/reports, and clearing an old sample ledger through Settings.
- Native app and test builds succeeded. The packaged simulator app contains `Frameworks/LinkKit.framework/LinkKit`, and simulator launches succeeded with the V2 runpath settings.
- Reviewed screenshots of the empty personal ledger and saved grocery-price form. Ivory paper/engraving is preserved; the saved-price confirmation is visible with the keyboard dismissed.
- Local Plaid setup assistant checked with temporary test configuration: owner-only file permissions, key preservation on reruns, and separate data paths when switching environments. No real Plaid credentials used.

Evidence: `build/oct21-core-tests.log`, `build/oct21-backend-tests.log`, `build/oct21-final.log`, and screenshots under `build/oct21-final-attachments/`. The passing simulator result bundle is `/private/tmp/Tender-oct21-final.xcresult`.

One earlier UI run saved prices correctly but asserted the wrong accessibility label for combined price-history rows. The test now checks the actual combined label. An intermediate build exposed duplicate Swift source basenames; the core cleanup file was renamed before the passing build.

## Setup state

The user has created a Plaid account. The main project's ignored `backend/.env` contains generated bridge access/encryption keys and the existing Apple team/bundle settings, with file permissions 0600. Plaid client ID, secret, and HTTPS redirect are still blank. No backend was deployed, no provider call was made, and no real bank was linked. Run `Set up Plaid.command` locally after choosing the HTTPS host, then follow [bank setup](bank-connect.md).

New installations start empty with zero allocations. Existing device ledgers are preserved; use **Settings → Remove Sample Data…** to select real records to keep. The old version had no record-level sample provenance, so automatic deletion would risk user data. Cleanup writes a recovery JSON and retains attachments locally.

## Still needs physical-device/account verification

- Signed iPhone launch, Keychain, configured Associated Domains and a full bank OAuth return.
- Live bank coverage and balance retrieval under the user's approved Trial access.
- Real camera/OCR, local notification delivery, Back Tap, and iCloud backup/restore with attachments.
- VoiceOver, largest Dynamic Type, and appearance/layout coverage beyond the inspected screens.

## Scope

Plaid retrieves reviewed available-balance snapshots for USD depository accounts. It does not import transactions or model credit-card debt. Sandbox snapshots remain display-only. Summaries and budget arithmetic are deterministic. iCloud exports are manual snapshots; assistants need chosen exports shared with them. No TestFlight/App Store release or paid service activation was performed.
