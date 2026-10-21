# Verification and handoff

Updated October 20, 2026. The edited iOS source is ready for a Mac build check; it is not a verified release or an installable iPhone binary.

## Confirmed in this continuation

- Node 24.19.0 ran all **8 backend tests successfully** using a mocked Plaid provider. Coverage includes balance/currency normalization, authenticated encryption, caller authentication, login repair using the saved Item, malformed requests, new-link initialization, persistence across restart, cached versus fresh endpoints, refresh throttling, and failed-disconnect retry.
- The source review confirmed that `Backup.swift` is included automatically by the Xcode project's synchronized `Tender` group and by the core Swift package's directory target.
- The source archive contains the app, Xcode project and scheme, pinned package resolution, core/UI tests, backend and blank environment template, documentation, and icon. Build caches, credentials, and personal bank data are excluded.
- Plaid's published update-mode and Trial documentation was rechecked. See source links in [bank-connect.md](bank-connect.md). No live provider calls were made.

## Not executed here

This environment has neither `swift` nor `xcodebuild`, so it cannot compile Swift, run the simulator, execute core/UI tests, or inspect the updated rendered app.

The Swift core suite now contains **14 tests**. Five added regressions cover monthly dates across February, yearly leap-day dates, duplicate bank-account keys, complete attachment backup validation/round trips, and legacy-ledger decoding. These tests are supplied but **have not been run on this revision**.

The inherited verification notes reported a successful initial simulator build and launch, nine core tests passing, an Overview visual inspection, and computed contrast ratios. Those reports describe the earlier source; no original test result bundle was supplied in this clean source tree. They do not verify the changes in this revision.

## Mac validation checklist

Use the commands in [README.md](../README.md), then:

1. Resolve LinkKit 7.2.2, build the Tender scheme, and run the 14 core tests. Run the existing three UI tests with an available iPhone simulator destination.
2. Inspect Overview, Budgets, Activity, Reports, Groceries, and forms in light/dark appearance. Check large Dynamic Type, narrow layouts, VoiceOver labels, and Reduce Motion. Financial values should remain readable over the decorative engraving.
3. Record an expense and relaunch. Verify its deduction, category total, and persistence. Replace its account balance, delete the older expense, and check that deletion does not inflate the newer balance snapshot.
4. Attach one receipt and one grocery-price photo. Export **Backup with Bills & Photos**; restore it into an empty test ledger and open both attachments. Export and restore the legacy ledger-only format too. Confirm missing images produce a clear message.
5. Restore a malformed backup and an archive missing a required attachment. The current ledger must remain intact. Check that an oversized/missing attachment blocks complete export.
6. Test category and attachment filters in Activity and category links from Budgets/Reports. Check previous-month summary end dates and weekly/monthly toggles.
7. Mark a January 31 monthly bill paid through February and March. Its next renewal should return to the 31st. Verify shopping estimates against category and upcoming-bill reserves.
8. With a configured sandbox bridge, link a test account and apply its balance twice. The second application should update the same ledger account. Replacing a matching manual account should keep a single cash balance.
9. Force a sandbox Item into `ITEM_LOGIN_REQUIRED` using Plaid's documented reset-login endpoint. Run **Load Existing Connections → Repair Login**, then retrieve balances. The saved Item count should remain unchanged. Test cancellation and a failed disconnect too.

The backend test command needs no Plaid account and makes no real network calls to Plaid. The sandbox integration checks above do require provider credentials and configuration.

## Physical iPhone checks still pending

- Camera capture and shelf-label recognition with real images.
- Delivery of a scheduled local payment notification. Reminders cover the next due occurrence; the app schedules at most 60 nearest future reminders.
- App Shortcut activation through Triple Back Tap.
- Saving and restoring a complete backup through a signed-in iCloud Drive account.
- Keychain behavior and a signed Universal Link/OAuth return through Plaid.
- Live bank coverage and balance accuracy after Trial approval and hosting setup.

## Scope boundaries

- Expenses and categories are entered/selected manually. Plaid retrieves reviewed balance snapshots; it does not import or automatically categorize transactions.
- Bill OCR captures text for review; cost observations and summaries are deterministic, not an automatic AI bill audit.
- Weekly/monthly summaries are available in the app and through exports. Scheduled summary notifications are not implemented.
- iCloud Drive export is a user-triggered snapshot, not automatic multi-device synchronization. Assistants need the selected export to be shared with them.
- The app has not been distributed through TestFlight or the App Store. Live bank connectivity remains unverified.
