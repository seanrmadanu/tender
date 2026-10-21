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
