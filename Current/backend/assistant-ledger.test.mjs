import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { newCloudState, publishLedger, applyAssistantChange, funding, findPurchases, stripUnverifiedOrigins, wipeCloudBankRecords } from './assistant-ledger.mjs';

const fixture = JSON.parse(await readFile(new URL('../shared/assistant-funding.json', import.meta.url)));
const now = new Date(fixture.now), accountID = fixture.ledger.accounts[0].id, categoryID = fixture.ledger.categories[0].id;
function state() { const s = newCloudState('owner'); publishLedger(s, { expectedRevision: 0, timeZone: fixture.timeZone, ledger: structuredClone(fixture.ledger) }, now); return s; }
function command(s, kind, args, extra = {}) { return { requestID: randomUUID(), issuedAt: fixture.now, expectedRevision: s.revision, kind, arguments: args, ...extra }; }
function purchase(extra = {}) { return { merchant: 'Lunch', amountCents: 1200, accountID, categoryID, date: fixture.now, deductFromBalance: false, ...extra }; }

test('shared financial fixture caps allocations at balance minus fixed reserves and rejects atomically', () => {
  const s = state(); assert.equal(funding(s.ledger, now, s.timeZone).available, fixture.expectedAvailableCents);
  const allocations = Object.fromEntries(s.ledger.categories.map(c => [c.id, 0])); allocations[categoryID] = 30000;
  applyAssistantChange(s, command(s, 'monthly_allocations', { totalCents: 30000, allocations }), 'chatgpt', now);
  const before = structuredClone(s);
  assert.throws(() => applyAssistantChange(s, command(s, 'monthly_allocations', { totalCents: 30001, allocations }), 'chatgpt', now));
  assert.deepEqual(s, before);
});
test('immediate purchase save is idempotent, source-bound and preserves bank balance when already reflected', () => {
  const s = state(), cmd = command(s, 'record_purchase', purchase());
  const result = applyAssistantChange(s, cmd, 'chatgpt', now);
  assert.equal(result.status, 'saved'); assert.equal(s.ledger.expenses.length, 1); assert.equal(s.ledger.accounts[0].available, 50000);
  assert.equal(s.ledger.expenses[0].assistantOrigin.provider, 'chatgpt');
  assert.equal(applyAssistantChange(s, cmd, 'chatgpt', now).repeated, true); assert.equal(s.ledger.expenses.length, 1);
  assert.throws(() => applyAssistantChange(s, cmd, 'claude', now));
  assert.throws(() => applyAssistantChange(s, { ...cmd, arguments: purchase({ amountCents: 1400 }) }, 'chatgpt', now));
});
test('stale revisions and expired replay requests never mutate ledger', () => {
  const s = state(), before = structuredClone(s);
  assert.throws(() => applyAssistantChange(s, command(s, 'record_purchase', purchase(), { expectedRevision: 0 }), 'claude', now));
  assert.throws(() => applyAssistantChange(s, command(s, 'record_purchase', purchase(), { issuedAt: '2020-01-01T00:00:00Z' }), 'claude', now));
  assert.deepEqual(s, before);
});
test('categorizing a bank debit saves one expense without a second deduction', () => {
  const s = state();
  applyAssistantChange(s, command(s, 'categorize_transaction', { transactionID: 'production:bank:coffee', categoryID }), 'claude', now);
  applyAssistantChange(s, command(s, 'categorize_transaction', { transactionID: 'production:bank:coffee', categoryID: s.ledger.categories[1].id }), 'chatgpt', now);
  assert.equal(s.ledger.expenses.length, 1); assert.equal(s.ledger.accounts[0].available, 50000);
  assert.equal(s.ledger.expenses[0].assistantOrigin.provider, 'claude'); assert.equal(s.ledger.expenses[0].assistantLastEdit.provider, 'chatgpt');
});
test('possible bank/manual duplicates need explicit resolution', () => {
  const s = state();
  assert.throws(() => applyAssistantChange(s, command(s, 'record_purchase', purchase({ amountCents: 1000 })), 'chatgpt', now), /matching purchase/);
  applyAssistantChange(s, command(s, 'record_purchase', purchase({ amountCents: 1000, confirmDistinct: true })), 'chatgpt', now);
  assert.throws(() => applyAssistantChange(s, command(s, 'categorize_transaction', { transactionID: 'production:bank:coffee', categoryID }), 'claude', now), /receipt match/);
  const id = s.ledger.expenses[0].id;
  applyAssistantChange(s, command(s, 'categorize_transaction', { transactionID: 'production:bank:coffee', categoryID, matchExpenseID: id }), 'claude', now);
  assert.equal(s.ledger.expenses.length, 1); assert.equal(s.ledger.expenses[0].id, id);
});
test('cash deductions and fixed payments release reserves once', () => {
  const s = state();
  applyAssistantChange(s, command(s, 'record_purchase', purchase({ merchant: 'Rent', amountCents: 20000, fixedExpenseID: s.ledger.fixedExpenses[0].id, deductFromBalance: true })), 'claude', now);
  assert.equal(s.ledger.accounts[0].available, 30000); assert.equal(funding(s.ledger, now, s.timeZone).reserve, 0);
  assert.equal(funding(s.ledger, now, s.timeZone).available, 30000);
});
test('source cannot be forged by phone uploads, and archive/edits retain verified origin', () => {
  const s = state(); applyAssistantChange(s, command(s, 'record_purchase', purchase()), 'chatgpt', now);
  const upload = structuredClone(s.ledger), expense = upload.expenses.pop();
  expense.assistantOrigin.provider = 'claude';
  upload.archivedItems = { expenses: [{ expense, reversedBalance: false, groceryLinks: [] }], envelopes: [], recurring: [], groceries: [] };
  upload.categories[0].assistantLastEdit = { provider: 'claude', actionID: randomUUID(), createdAt: fixture.now };
  const clean = stripUnverifiedOrigins(upload, s.ledger);
  assert.equal(clean.archivedItems.expenses[0].expense.assistantOrigin.provider, 'chatgpt');
  assert.equal(clean.categories[0].assistantLastEdit, undefined);
});
test('notes preserve receipt attachments and return only the requested financial projection', () => {
  const s = state(); s.ledger.bankTransactionDetails = { 'production:bank:coffee': { note: 'old', attachments: ['private-photo.jpg'] } };
  applyAssistantChange(s, command(s, 'transaction_note', { transactionID: 'production:bank:coffee', note: 'Work lunch' }), 'claude', now);
  assert.deepEqual(s.ledger.bankTransactionDetails['production:bank:coffee'].attachments, ['private-photo.jpg']);
  const result = findPurchases(s, { merchant: 'coffee' }); assert.equal(result.purchases[0].note, 'Work lunch');
  assert.equal(JSON.stringify(result).includes('private-photo'), false);
});
test('no payments or arbitrary operations are exposed, and pending/credits cannot be categorized', () => {
  const s = state(), before = structuredClone(s);
  assert.throws(() => applyAssistantChange(s, command(s, 'wire_money', {}), 'claude', now));
  s.ledger.bankActivity[0].transactions[0].pending = true;
  assert.throws(() => applyAssistantChange(s, command(s, 'categorize_transaction', { transactionID: 'production:bank:coffee', categoryID }), 'claude', now));
  assert.equal(s.ledger.expenses.length, 0); assert.equal(s.revision, before.revision);
});
test('bank categorization keeps the bank date in the user time zone at a month boundary', () => {
  const s = state(), tx = s.ledger.bankActivity[0].transactions[0];
  tx.date = '2026-11-01';
  applyAssistantChange(s, command(s, 'categorize_transaction', { transactionID: tx.id, categoryID }), 'claude', now);
  assert.equal(s.ledger.expenses[0].date, '2026-11-01T07:00:00Z');
});
test('verified note attribution follows a pending bank purchase to its posted ID', () => {
  const s = state(), tx = s.ledger.bankActivity[0].transactions[0];
  applyAssistantChange(s, command(s, 'transaction_note', { transactionID: tx.id, note: 'Work lunch' }), 'claude', now);
  const upload = structuredClone(s.ledger), posted = upload.bankActivity[0].transactions[0];
  posted.pendingID = tx.id; posted.id = 'production:bank:posted-coffee';
  upload.bankTransactionDetails[posted.id] = upload.bankTransactionDetails[tx.id]; delete upload.bankTransactionDetails[tx.id];
  upload.bankTransactionDetails[posted.id].assistantLastEdit.provider = 'chatgpt';
  publishLedger(s, { expectedRevision: s.revision, timeZone: fixture.timeZone, ledger: upload }, now);
  assert.equal(s.ledger.bankTransactionDetails[posted.id].assistantLastEdit.provider, 'claude');
});
test('bank privacy wipe preserves offline accounts and blocks prior AI access', () => {
  const s = state(), manualID = randomUUID().toUpperCase();
  s.ledger.accounts.push({ ...s.ledger.accounts[0], id: manualID, name: 'Cash', bankAccountKey: undefined, isCash: true });
  applyAssistantChange(s, command(s, 'record_purchase', purchase({ accountID: manualID })), 'chatgpt', now);
  wipeCloudBankRecords(s);
  assert.equal(s.connected, false); assert.equal(s.epoch, 1);
  assert.equal(s.ledger.accounts.length, 1); assert.equal(s.ledger.accounts[0].id, manualID);
  assert.equal(s.ledger.expenses.length, 1); assert.equal(s.ledger.bankActivity, undefined);
  assert.throws(() => applyAssistantChange(s, command(s, 'record_purchase', purchase({ accountID: manualID })), 'chatgpt', now));
});
test('date filters include the complete local day for bank and manual purchases over daylight saving', () => {
  const s = state();
  const evening = '2026-11-02T07:30:00Z', tomorrow = new Date('2026-11-02T20:00:00Z');
  applyAssistantChange(s, { ...command(s, 'record_purchase', purchase({ date: evening })), issuedAt: tomorrow.toISOString() }, 'chatgpt', tomorrow);
  const results = findPurchases(s, { from: '2026-11-01', to: '2026-11-01' }).purchases;
  assert.equal(results.length, 2); assert.equal(findPurchases(s, { from: '2026-11-02' }).purchases.length, 0);
  assert.throws(() => findPurchases(s, { from: '2026-02-30' }), /Invalid date range/);
});
