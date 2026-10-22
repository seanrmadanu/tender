## v4.1.7 — Shopping name wrapping and keyboard dismissal, October 22, 2026

Shopping Mode uses a vertical name field with three reserved lines (72-point
minimum). Long names wrap and then scroll within that area instead of growing
the card with their length. Removed PRICE PER ITEM caption to reuse its space;
price retains its accessibility label. The three-line region scales with system
text size for accessibility. Existing banknote styling and quantity wheel retained.

Added a keyboard-down button above both text and decimal keyboards, and a Done
submit action on the name field. Both fields now bind directly to an explicit
name/price focus state rather than nested TenderField focus states. Full field
hit regions retained. Opening the scanner/photo picker and saving the cart clear
focus; interactive scroll dismissal remains available through PaperScreen.

Validation: simulator-target compilation passed (build only), evidence in
Current/build/oct22-shopping-text-build.log. No UI tests or device installation;
user will check wrapping, layout and keyboard behavior on iPhone. Previous
checkpoint: 1bc1f24. Price OCR and product recognition unchanged in this revision.

---

## v4.1.6 — Simple scanned product names, October 22, 2026

Added a small local vocabulary of common product words. A single recognized
product kind anywhere in eligible OCR lines takes priority over incidental
text: TUBES followed by GREEK YOGURT becomes Yogurt. Cabernet becomes Wine,
and kitchen faucet becomes Faucet. Whole-word matching avoids Tea in TEAPOT;
multiple recognized kinds retain the existing descriptive fallback (e.g.
CHICKEN PASTA). Unknown products also retain that fallback. Names stay editable.
No internet lookup was added. This cannot recover product text OCR failed to
recognize and is not a general product catalog or guaranteed label detector.

Five focused shelf-parser code tests passed, including synthetic TUBES/YOGURT,
spelling variation, split ICE/CREAM, compound products and unchanged price guards.
Evidence: Current/build/oct22-simple-product-names.log. No UI/device tests or
phone install; user will test actual scans. Prior checkpoint: b0b32d0.

---

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
