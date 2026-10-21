# Tender source versions

Organized October 21, 2026. These are source-history labels, separate from the installed app's version number.

| Version | Location | Status and contents |
| --- | --- | --- |
| v1 | `Archives/v1/` | Earlier project, previously `version/v1/Money app 2`. Preserved as historical source. |
| v2 | `Archives/v2/` | Other-chat continuation, previously `version/V2/Money app`. Its design, reports, backup, recurrence, and bank improvements were integrated into the active app. |
| v3 | `Current/` | Active continuation: integrated V2, empty personal ledger and approved one-time reset, grocery saving fixes, manual and multiple bank accounts, Cloudflare backend, browser Plaid login, and private setup helpers. |

Open **Current/Tender.xcodeproj** for current work. There is one live v3 working copy; future edits belong there. Earlier original ZIP downloads are preserved as `Archives/v1-original.zip` and `Archives/v2-original.zip`.

During reorganization, both extracted historical project trees were checked byte-for-byte before and after moving. Current source, private configuration, dependencies, build evidence, signing settings, and application identity were preserved. Root launchers open or configure the current project. No bank storage reset or paid-plan change was performed.

See `Tender-change-log.log` for the chronological record and `Tender-Handoff.md` for current setup, tests, and remaining work. For a future archived version, copy source without credentials, bank data, build output, or dependency caches; label it clearly and update this index.
