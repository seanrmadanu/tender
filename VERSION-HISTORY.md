# Active: v4.1.5 — Shelf-label product names

October 22, 2026. Reject isolated OCR characters, known surrounding page text,
and package-size-only lines when selecting a product name. Join up to three
consecutive uppercase title lines. Prior checkpoint: `4470db1`.
38/38 core checks passed before the model-switch pause; no additional simulator
or device tests. User will test real scans. See Current/docs/verification.md.

---

# Active: v4.1.4 — Shelf label parsing fix

Nutrition fractions no longer trigger multi-buy ambiguity or become item names.
37/37 core tests passed; full-image/device scan pending. Previous checkpoint:
`9fdd514`. See Current/docs/verification.md and the latest Git commit.

---

# Active: v4.1.3 — Quantity wheel

October 22, 2026. Replaced Shopping Mode quantity buttons with an inline native
scrolling picker, matching the requested Timer-style interaction. Range 1–99;
cart/purchase behavior preserved. 2/2 simulator UI tests passed.
Pre-change checkpoint: `f9fa895`. See latest Git commit.

---

# Active: v4.1.2 — Shopping Mode quick cart

October 22, 2026. Added quantity beside unit price and a top-right scanner icon.
Add to Cart now saves directly without the Shopping Item form. Quantity totals,
optional metadata, duplicate prevention and linked purchases verified locally.
Pre-change checkpoint: `73765ed`. See latest Git commit and verification.md.

---

# Active: v4.1.1 — Startup follow-up

October 22, 2026. Local ledger loading/migration moved off the main actor,
unchanged startup rewrites removed, startup Keychain read moved off main, and
a loading state prevents premature edits. Core 36/36 and selected UI 3/3 passed.
Pre-fix checkpoint: `4b08b5e`. Physical iPhone launch timing remains unverified.
See the latest Git commit and Current/docs/verification.md.

---

# Active: v4.1 — V3 import, feature audit, original design restoration

October 21, 2026. The supplied folder is named V3; its ZIP describes its source
as v4. `Current/` now contains that feature update and our follow-up fixes.

Local branch: `codex/integrate-v3-2026-10-21`.

| Checkpoint | Purpose |
| --- | --- |
| `354b234` | Original Current before importing V3; recoverable source ZIP also saved. |
| `d180ba4` | Verified ZIP import and build/test-selector fixes. |
| `cc23baa` | First feature-audit fixes: grocery planning, parsers, receipt state and linked bank purchases. |
| Latest design-restoration commit | Original banknote heading, card surface/border and readable dark-mode buttons; see Git log. |

To inspect an old version without changing Current, use `git show <commit>:<path>`
or create a separate worktree. The source snapshot contains no credentials or
build caches; private deployment settings are retained in Current only.

---

# v4 — Personal feature testing source (October 21, 2026)

Implements the personal-stage requests listed in Current/docs/feature-status.md.
29 mock backend tests passed; Mac/iPhone validation remains required.
Original v3 source remains in the input handoff ZIP/version history.

---

# Tender source versions

Organized October 21, 2026. These are source-history labels, separate from the installed app's version number.

| Version | Location | Status and contents |
| --- | --- | --- |
| v1 | `Archives/v1/` | Earlier project, previously `version/v1/Money app 2`. Preserved as historical source. |
| v2 | `Archives/v2/` | Other-chat continuation, previously `version/V2/Money app`. Its design, reports, backup, recurrence, and bank improvements were integrated into the active app. |
| v3 | Git `354b234` and `Archives/snapshots/2026-10-21-before-v3-import.zip` | Preserved pre-import continuation: integrated V2, empty personal ledger and approved one-time reset, grocery saving fixes, manual and multiple bank accounts, Cloudflare backend, browser Plaid login, and private setup helpers. |

Open **Current/Tender.xcodeproj** for current work. There is one active working copy; future edits belong in Current. The separate Merged folder is excluded from Git and left untouched. Earlier original ZIP downloads are preserved as `Archives/v1-original.zip` and `Archives/v2-original.zip`.

During reorganization, both extracted historical project trees were checked byte-for-byte before and after moving. Current source, private configuration, dependencies, build evidence, signing settings, and application identity were preserved. Root launchers open or configure the current project. No bank storage reset or paid-plan change was performed.

See `Tender-change-log.log` for the chronological record and `Tender-Handoff.md` for current setup, tests, and remaining work. For a future archived version, copy source without credentials, bank data, build output, or dependency caches; label it clearly and update this index.
