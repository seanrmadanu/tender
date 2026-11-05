# ChatGPT App Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand ChatGPT across Tender while excluding private bank data and user-operated reset/delete-all.
**Architecture:** Typed tools extend the existing owner-scoped cloud ledger. Central safe projections/transaction aliases enforce the read boundary, and staged domain mutations keep all writes atomic. Optional Codable phone settings and screen requests preserve older ledgers.
**Tech Stack:** Node ESM, Zod, MCP SDK, Cloudflare OAuth/Durable Objects, SwiftUI/Codable, XCTest.
**Spec:** docs/superpowers/specs/2026-11-02-chatgpt-app-access-design.md

## Global Constraints
- Immediate save and source badges; no special Undo.
- Bank name and balance may be read; bank numbers, masks, provider IDs, credentials and payment tools excluded.
- Reset and delete-all stay user-operated.
- Preserve real user data and all pre-existing uncommitted work; no real ledger write tests.
- Keep existing account isolation, revision/idempotency checks and budgeting cap.

## Review Focus
- Secrets hidden inside free-text notes/receipt fields must not leak through any read tool.
- Replayed archive/restore must not double-charge balances.
- Unknown settings and forged provenance cannot be uploaded through new tools.
- Old ledgers must decode with new optional fields; device-only photos must be preserved.
- Reconnect/refresh must expose new tools without losing existing grants.

### Task 1: Broader domain tools and private-bank projection
Files: Current/backend/assistant-app.mjs, assistant-ledger.mjs, assistant-mcp.mjs, assistant-worker.mjs; tests assistant-app.test.mjs and assistant-worker.test.mjs.
Interfaces: appData(ledger, query), applyAppChange(ledger, kind, args, origin, now, entityID, helpers); all pass through existing applyAssistantChange and authenticated DO dispatch.
- [x] Write tests asserting bank identifiers omitted, settings/grocery/recurring/purchase/archive operations save and remain atomic, reports deduplicate spending, and unsupported security operations fail.
- [x] Run Node tests; verify failures identify missing operations/privacy enforcement.
- [x] Implement safe projections and validated staged mutations, wire schemas/DO reads. Never return raw ledger or bank identifiers.
- [x] Run full backend suite, including authenticated owner/scope/new-tool integration and privacy projection across MCP results. Expected: all pass.

### Task 2: Phone settings, navigation and attribution
Files: Core/Ledger.swift, Core/AssistantOrigin.swift, Services/CloudLedgerSync.swift, Services/LedgerStore.swift, Views/RootView.swift, Settings.swift, AIConnectionsView.swift, Groceries.swift, RecurringAndAccounts.swift; Tests/AssistantAppAccessTests.swift and UITests/TenderUITests.swift.
Interfaces: optional AppPreferences and AssistantScreenRequest fields; one-time screen handling uses request UUID scoped to ledger; existing AssistantBadge handles new model origins.
- [x] Add failing core tests for settings roundtrip/merge, legacy defaults and navigation request validation; UI test reminders/profile/grocery handoff.
- [x] Add backward-compatible fields, apply reminder preferences, screen routing and badges; update permission/privacy copy.
- [x] Verify full Swift core suite and focused simulator UI. Expected: all pass with legacy ledger/photo preservation.

### Task 3: Review and delivery
Files: docs/ai-connections.md, Current/README.md, Tender-change-log.log, version build 10.
- [x] Fresh code review against this spec, particularly privacy and archive balance rules; address important findings with regression tests.
- [x] Run npm test, swift test, focused UI, dependency audit, signed iPhone build and git diff --check.
- [x] Deploy only wrangler.ai.jsonc, preserving secret/KV/grants and bank Worker; probe public health/auth discovery.
- [x] Install/launch build 10 preserving personal data; document exact evidence and remaining limits. Explain ChatGPT plugin tool refresh if cached.
