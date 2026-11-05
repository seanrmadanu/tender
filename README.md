## Accounts and signed-in Plaid — October 24, 2026

The source now offers Plaid import, an explained manual-entry flow, and cash-on-hand entry on Accounts. Signed-in bank requests use verified Firebase identity and a separate vault per user. The live Worker was deployed on October 25, 2026. Rebuild/install the updated iPhone app, then test signed-in Plaid linking. See [verification and rollout status](Current/docs/account-bank-verification.md).

## Latest local status — October 21, 2026

Work in **Current/Tender.xcodeproj**. V3 was imported with a recoverable pre-import
checkpoint, then audited against all 18 requests. Original banknote styling was
restored; Merged is a separate untouched collaborator copy. Core 32/32 and backend
30/30 passed; all 9 distinct UI cases passed across the suite and focused retest.
See [the 18-item status](Current/docs/feature-status.md),
[verification](Current/docs/verification.md), and
[remaining setup](Current/docs/remaining-setup.md).

Five requests remain partial/setup-dependent: consumer onboarding, Capital One,
native iCloud, Apple/Google sign-in, and online account deletion/isolation.
Bank transaction code is local; its new Worker has not been deployed here.
Checkpoint history is in VERSION-HISTORY.md; detailed changes are appended to
Tender-change-log.log. Earlier notes below are retained as history.

---

## October 21, 2026 — personal feature implementation update

The user authorized implementation in this continuation and then chose to test
the personal app first. Friends will connect real banks later, after separate
sign-ins and bank-data isolation are implemented. The older planning-only
instructions below are historical and superseded for this personal stage.

Current source-history label: **v4 personal testing source**. Open
`Current/Tender.xcodeproj`. Read `Current/docs/personal-test-guide.md` before
installing, and `Current/docs/feature-status.md` for all 18 requested items.

Implemented source includes wallet account cards, bank transaction import and
review/matching, foreground cached-bank checks, structured receipt parsing and
original-image retention, cash wallets, shelf-price suggestions, dated shopping
plans, local speech planning/reminders, recurring suggestions, reorganized
navigation/Settings, larger input targets, backup-first deletion, and restore
reauthorization. Capital One now has safe diagnostics; its actual failure is
not confirmed fixed. Consumer authentication/isolation and native iCloud
containers remain deferred.

29 mocked backend tests passed in this environment. The 29 Swift core tests,
8 updated UI tests, and iOS build were not run because Swift/Xcode are absent.
The Cloudflare runtime test could not run because npm dependency retrieval was
blocked (HTTP 403). No deployment, live bank calls, data deletion or paid-service
change occurred. Source is ready for Mac validation, not a verified release.

The vault adapter now migrates legacy encrypted state into atomic encrypted
chunks to fit transaction history. Preserve the existing keys/vault identity.
Do not downgrade to the old vault reader after migration. The old automatic
legacy-ledger reset was retired so existing entries are preserved.

---

# Tender — start here

The app being developed is **v3 in Current**. Open [Current/Tender.xcodeproj](Current/Tender.xcodeproj) in Xcode, or double-click **Open Current Tender.command**.

```text
Money app/
├── Current/                      ← active v3 app, backend, setup helpers, tests
│   └── Tender.xcodeproj           ← open this project
├── Archives/
│   ├── v1/                       ← historical project
│   ├── v2/                       ← historical project
│   ├── v1-original.zip           ← original downloaded archive
│   └── v2-original.zip           ← original downloaded archive
├── Open Current Tender.command
├── Set up Cloudflare Plaid.command
├── VERSION-HISTORY.md
├── Tender-Handoff.md
└── Tender-change-log.log
```

All new app work belongs in **Current**. Archives are independent historical projects, outside the active Xcode project's directory and build sources. The v3 label describes this continuation; it does not change the app's marketing version or bundle ID.

- [App features, build commands, and iPhone installation](Current/README.md)
- [Version history](VERSION-HISTORY.md)
- [Continuation handoff for another chat](Tender-Handoff.md)
- [iPhone feature and workflow test checklist](Tender-Test-Checklist.md)
- [Latest requested changes — planning backlog](Tender-Requested-Changes.md)
- [Start here for another chat / source ZIP](START-HERE-OTHER-CHAT.md)
- [Chronological change log](Tender-change-log.log)
- [Bank setup](Current/docs/bank-connect.md)

Cloudflare private setup has completed. The user reports successful Plaid connection and visible balances; further account/workflow tests are in the checklist. The root Cloudflare setup launcher forwards to the helper in Current if setup needs to be rerun.

Keep private configuration in `Current/backend/.env`; it remains Git-ignored. Run app/backend commands from `Current/`, or `Current/backend/` as appropriate.

## Contributors

- **Sean Raj Madanu** — project creator and maintainer
- **OpenAI Codex** — AI-assisted development, testing, and documentation
