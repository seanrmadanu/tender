import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import * as cloud from './assistant-ledger.mjs';
const fixture = JSON.parse(await readFile(new URL('../shared/assistant-funding.json', import.meta.url)));
const now = new Date(fixture.now), aid = fixture.ledger.accounts[0].id, cid = fixture.ledger.categories[0].id;
function state() {
  const s = cloud.newCloudState('test'); const l = structuredClone(fixture.ledger);
  l.accounts[0].name = 'Chase · College · ··2579';
  l.accounts[0].bankDetails = { institutionName: 'Chase', mask: '2579', itemID: 'private-item-abc', accountNumber: '123456789012', routingNumber: '021000021' };
  cloud.publishLedger(s, { expectedRevision: 0, timeZone: fixture.timeZone, ledger: l }, now); return s;
}
function change(s, kind, args) { const c = { requestID: randomUUID(), issuedAt: fixture.now, expectedRevision: s.revision, kind, arguments: args }; let r; assert.doesNotThrow(() => r = cloud.applyAssistantChange(s, c, 'chatgpt', now)); return r; }
const read = (s, section, extra = {}) => cloud.readAppSection?.(s, { section, ...extra }, now);
const purchase = (s, extra = {}) => change(s, 'record_purchase', { accountID: aid, categoryID: cid, merchant: 'Lunch', amountCents: 1200, date: fixture.now, deductFromBalance: false, ...extra });
test('linked bank context exposes institution and balance without masks or provider identifiers', () => {
  const result = cloud.assistantContext(state(), now);
  assert.equal(result.accounts[0].name, 'Chase'); assert.equal(result.accounts[0].availableCents, 50000);
  for (const value of ['2579', 'private-item-abc', '123456789012', '021000021', 'production:checking', 'bankDetails']) assert.equal(JSON.stringify(result).includes(value), false, value);
});
test('purchase reads redact bank identifiers in free text and give usable opaque bank references', () => {
  const s = state(); s.ledger.bankActivity[0].transactions[0].merchant = 'Coffee 021000021';
  s.ledger.bankTransactionDetails = { 'production:bank:coffee': { note: 'Card ending in 2579, number 123456789012', attachments: ['private.jpg'] } };
  const found = cloud.findPurchases(s).purchases[0];
  assert.match(found.bankTransactionID, /^txn_[a-f0-9]{32}$/);
  for (const value of ['2579', '021000021', '123456789012', 'production:bank:coffee', 'private.jpg']) assert.equal(JSON.stringify(found).includes(value), false, value);
  change(s, 'transaction_note', { transactionID: found.bankTransactionID, note: 'Work purchase' });
  assert.equal(s.ledger.bankTransactionDetails['production:bank:coffee'].note, 'Work purchase');
});
test('settings changes save profile and reminders while preventing linked bank balance edits', () => {
  const s = state(); change(s, 'save_settings', { profileName: 'Taylor', remindersEnabled: false, primaryAccountID: aid });
  assert.equal(s.ledger.profileName, 'Taylor'); assert.equal(s.ledger.appPreferences.remindersEnabled, false);
  assert.equal(read(s, 'settings').profile.name, 'Taylor'); assert.equal(read(s, 'settings').remindersEnabled, false);
  const before = structuredClone(s);
  assert.throws(() => cloud.applyAssistantChange(s, { requestID: randomUUID(), issuedAt: fixture.now, expectedRevision: s.revision, kind: 'save_offline_account', arguments: { accountID: aid, name: 'Fake', balanceCents: 1, isCash: false } }, 'chatgpt', now));
  assert.deepEqual(s, before);
});
test('groceries and prices persist source metadata and do not create purchases', () => {
  const s = state(); const r = change(s, 'save_grocery', { name: 'Milk', quantity: 2, unit: 'bottle', remind: false, storeName: 'Market' });
  change(s, 'grocery_price', { groceryID: r.entityID, priceCents: 350, storeName: 'Market', date: fixture.now });
  const g = read(s, 'groceries').items[0]; assert.equal(g.quantity, 2); assert.equal(g.observations[0].price, 350);
  assert.equal(g.assistantOrigin.provider, 'chatgpt'); assert.equal(s.ledger.expenses.length, 0); assert.equal(s.ledger.accounts[0].available, 50000);
});
test('recurring payments can be created, edited, archived and restored without paying money', () => {
  const s = state(); const values = { name: 'Music', amountCents: 1000, categoryID: cid, nextDue: '2026-12-01T19:00:00Z', cycle: 'Monthly', remind: false };
  const r = change(s, 'save_recurring', values); change(s, 'save_recurring', { ...values, recurringID: r.entityID, amountCents: 1200 });
  assert.equal(read(s, 'recurring').items[0].amount, 1200);
  change(s, 'archive_item', { itemKind: 'recurring', itemID: r.entityID, action: 'archive' }); assert.equal(s.ledger.recurring.length, 0);
  change(s, 'archive_item', { itemKind: 'recurring', itemID: r.entityID, action: 'restore' });
  assert.equal(s.ledger.recurring.length, 1); assert.equal(s.ledger.accounts[0].available, 50000); assert.equal(s.ledger.expenses.length, 0);
});
test('manual purchase edits and archive restore adjust only the current balance snapshot', () => {
  const s = state(); const r = purchase(s, { deductFromBalance: true });
  change(s, 'edit_purchase', { expenseID: r.entityID, merchant: 'Lunch corrected', amountCents: 1500, date: fixture.now, categoryID: cid, note: 'Corrected' });
  assert.equal(s.ledger.accounts[0].available, 48500);
  change(s, 'archive_item', { itemKind: 'purchase', itemID: r.entityID, action: 'archive' }); assert.equal(s.ledger.accounts[0].available, 50000);
  change(s, 'archive_item', { itemKind: 'purchase', itemID: r.entityID, action: 'restore' }); assert.equal(s.ledger.accounts[0].available, 48500);
  s.ledger.accounts[0].available = 42000; s.ledger.accounts[0].balanceRevision = randomUUID();
  change(s, 'edit_purchase', { expenseID: r.entityID, merchant: 'Lunch corrected', amountCents: 1600, date: fixture.now, categoryID: cid, note: '' });
  assert.equal(s.ledger.accounts[0].available, 42000); assert.equal(s.ledger.expenses[0].assistantOrigin.provider, 'chatgpt');
});
test('envelope archive reassigns history and restore preserves assignments and funded allocations', () => {
  const s = state(); purchase(s);
  change(s, 'archive_item', { itemKind: 'envelope', itemID: cid, action: 'archive' });
  assert.equal(s.ledger.categories.find(c => c.id === s.ledger.expenses[0].categoryID).name, 'Uncategorized');
  change(s, 'archive_item', { itemKind: 'envelope', itemID: cid, action: 'restore' }); assert.equal(s.ledger.expenses[0].categoryID, cid);
  const before = structuredClone(s);
  assert.throws(() => cloud.applyAssistantChange(s, { requestID: randomUUID(), issuedAt: fixture.now, expectedRevision: s.revision, kind: 'save_envelope', arguments: { name: 'Too much', symbol: 'tag', allocationCents: 30001 } }, 'chatgpt', now)); assert.deepEqual(s, before);
});
test('offline balances can be changed without modifying bank records', () => {
  const s = state(); const r = change(s, 'save_offline_account', { name: 'Cash', isCash: true, balanceCents: 10000 });
  change(s, 'save_offline_account', { accountID: r.entityID, name: 'Cash', isCash: true, balanceCents: 15000 });
  assert.equal(s.ledger.accounts[1].available, 15000); assert.equal(s.ledger.accounts[0].available, 50000); assert.equal(s.ledger.accounts[1].assistantOrigin.provider, 'chatgpt');
});
test('activity report counts bank and manual spending once, excluding pending, transfers and credits', () => {
  const s = state(); purchase(s);
  change(s, 'categorize_transaction', { transactionID: 'production:bank:coffee', categoryID: cid });
  s.ledger.bankActivity[0].transactions.push({ ...s.ledger.bankActivity[0].transactions[0], id: 'pending', pending: true, amountCents: 9999 });
  const report = read(s, 'report', { from: '2026-11-01', to: '2026-11-01' });
  assert.equal(report.totalCents, 2200); assert.equal(report.purchaseCount, 2); assert.equal(report.categories[0].spentCents, 2200);
});
test('shopping check respects envelope and available balances', () => {
  const s = state(); s.ledger.monthlyAllocation = 10000; s.ledger.categories[0].limit = 10000; purchase(s);
  const r = read(s, 'shopping', { categoryID: cid, amountCents: 9000 }); assert.equal(r.fits, false); assert.equal(r.envelopeAfterCents, -200);
});
test('camera and data-management handoffs navigate without executing deletion or bank login', () => {
  const s = state(); change(s, 'open_screen', { screen: 'profile' }); assert.equal(s.ledger.assistantScreenRequest.screen, 'profile');
  const before = structuredClone(s);
  for (const kind of ['reset_app', 'delete_all', 'bank_login', 'payment', 'raw_ledger', 'set_bank_credentials']) {
    assert.throws(() => cloud.applyAssistantChange(s, { requestID: randomUUID(), issuedAt: fixture.now, expectedRevision: s.revision, kind, arguments: {} }, 'chatgpt', now)); assert.deepEqual(s, before);
  }
});
test('replaying an archive action never refunds a purchase twice', () => {
  const s = state(); const r = purchase(s, { deductFromBalance: true });
  const cmd = { requestID: randomUUID(), issuedAt: fixture.now, expectedRevision: s.revision, kind: 'archive_item', arguments: { itemKind: 'purchase', itemID: r.entityID, action: 'archive' } };
  assert.doesNotThrow(() => cloud.applyAssistantChange(s, cmd, 'chatgpt', now));
  assert.equal(cloud.applyAssistantChange(s, cmd, 'chatgpt', now).repeated, true); assert.equal(s.ledger.accounts[0].available, 50000);
});
test('all app reads protect receipt payment details and free-text bank identifiers', () => {
  const s = state(); s.ledger.categories[0].symbol = '123456789012'; const r = purchase(s, { merchant: 'Lunch 123456789012', note: 'Routing 021000021' });
  s.ledger.expenses[0].receipt = { payment: 'Card 2579', items: [{ name: 'Lunch 021000021', quantity: 1, total: 1200 }] };
  const g = change(s, 'save_grocery', { name: 'Milk 123456789012', quantity: 1, unit: 'bottle', storeName: 'Card 2579' });
  change(s, 'grocery_price', { groceryID: g.entityID, priceCents: 350, storeName: 'Routing 021000021', date: fixture.now });
  change(s, 'archive_item', { itemKind: 'purchase', itemID: r.entityID, action: 'archive' });
  for (const section of ['settings', 'accounts', 'envelopes', 'fixed_expenses', 'groceries', 'recurring', 'archive', 'receipt', 'report']) {
    const result = JSON.stringify(read(s, section, { itemID: r.entityID }));
    for (const forbidden of ['123456789012', '021000021', '2579', 'private-item-abc', 'production:checking', 'bankDetails']) assert.equal(result.includes(forbidden), false, section + ' leaked ' + forbidden);
  }
});
test('removing a zero envelope remains possible when an older budget has become overfunded', () => {
  const s = state(); s.ledger.monthlyAllocation = 10000; s.ledger.categories[0].limit = 10000; s.ledger.accounts[0].available = 0;
  change(s, 'archive_item', { itemKind: 'envelope', itemID: s.ledger.categories[1].id, action: 'archive' });
  assert.equal(s.ledger.categories.length, 1);
});
test('native uploads cannot persist malformed reminders or invalid screen commands', () => {
  const s = state();
  for (const extra of [{ appPreferences: { remindersEnabled: 'yes' } }, { assistantScreenRequest: { id: randomUUID(), screen: 'delete_all' } }]) {
    assert.throws(() => cloud.publishLedger(s, { expectedRevision: s.revision, timeZone: fixture.timeZone, ledger: { ...s.ledger, ...extra } }, now));
  }
});
test('provider IDs and credential-labelled text are excluded from every text projection', () => {
  const s = state(); const note = 'provider transaction production:bank:coffee; provider account checking; access_token access-production-abcd-efgh; password=hunter-example';
  s.ledger.bankTransactionDetails = { 'production:bank:coffee': { note, attachments: [] } };
  const r = purchase(s); s.ledger.expenses[0].receipt = { items: [{ name: note, quantity: 1, total: 1200 }], payment: '123456789012' };
  for (const result of [cloud.findPurchases(s), read(s, 'receipt', { itemID: r.entityID })]) {
    const serialized = JSON.stringify(result);
    for (const value of ['production:bank:coffee', 'checking', 'access-production-abcd-efgh', 'hunter-example', '123456789012']) assert.equal(serialized.includes(value), false, value);
  }
});
test('offline account restore brings native archived history back and removes its archivedCards entry', () => {
  const s = state(), offlineID = randomUUID().toUpperCase(), expenseID = randomUUID().toUpperCase();
  s.ledger.accounts.push({ id: offlineID, name: 'Offline', available: 10000, updated: fixture.now, isArchived: true });
  s.ledger.archivedCards = [{ id: offlineID, expenses: [{ id: expenseID, merchant: 'Market', amount: 1000, categoryID: cid, accountID: offlineID, date: fixture.now, note: '' }], groceries: [], recurring: [], bankItems: [], details: {} }];
  change(s, 'archive_item', { itemKind: 'account', itemID: offlineID, action: 'restore' });
  assert.equal(s.ledger.archivedCards.length, 0); assert.equal(s.ledger.expenses.length, 1); assert.equal(s.ledger.accounts[1].isArchived, false);
  change(s, 'archive_item', { itemKind: 'account', itemID: offlineID, action: 'archive' });
  assert.equal(s.ledger.expenses.length, 0); assert.equal(s.ledger.archivedCards[0].expenses[0].id, expenseID);
});
test('purchase archive keeps grocery snapshots separate from cleared live links', () => {
  const s = state(), p = purchase(s), g = change(s, 'save_grocery', { name: 'Lunch food', quantity: 1, unit: 'each' });
  Object.assign(s.ledger.groceries[0], { expenseID: p.entityID, purchasedAt: fixture.now, checked: true });
  change(s, 'archive_item', { itemKind: 'purchase', itemID: p.entityID, action: 'archive' });
  assert.equal(s.ledger.groceries[0].expenseID, undefined);
  change(s, 'archive_item', { itemKind: 'purchase', itemID: p.entityID, action: 'restore' });
  assert.equal(s.ledger.groceries[0].id, g.entityID); assert.equal(s.ledger.groceries[0].expenseID, p.entityID); assert.equal(s.ledger.groceries[0].checked, true);
});
test('Archive receipt inspection can read saved items without exposing payment or attachment identifiers', () => {
  const s = state(), r = purchase(s);
  s.ledger.expenses[0].receipt = { payment: 'Card 2579', items: [{ name: 'Lunch', quantity: 1, total: 1200 }] }; s.ledger.expenses[0].attachment = 'private-receipt.jpg';
  change(s, 'archive_item', { itemKind: 'purchase', itemID: r.entityID, action: 'archive' });
  const result = read(s, 'receipt', { itemID: r.entityID });
  assert.equal(result.found, true); assert.equal(result.items[0].name, 'Lunch'); assert.equal(result.hasAttachment, true);
  assert.equal(JSON.stringify(result).includes('2579'), false); assert.equal(JSON.stringify(result).includes('private-receipt'), false);
});
test('older phone uploads preserve app settings and handoffs they cannot encode', () => {
  const s = state(); change(s, 'save_settings', { remindersEnabled: false }); change(s, 'open_screen', { screen: 'profile' });
  const legacy = structuredClone(s.ledger); delete legacy.appPreferences; delete legacy.assistantScreenRequest;
  legacy.profileName = 'Phone edit';
  cloud.publishLedger(s, { expectedRevision: s.revision, timeZone: fixture.timeZone, ledger: legacy }, now);
  assert.equal(s.ledger.appPreferences?.remindersEnabled, false); assert.equal(s.ledger.assistantScreenRequest?.screen, 'profile'); assert.equal(s.ledger.profileName, 'Phone edit');
});
test('current phone uploads can explicitly clear optional app settings', () => {
  const s = state(); change(s, 'save_settings', { remindersEnabled: false });
  const current = structuredClone(s.ledger); delete current.appPreferences;
  cloud.publishLedger(s, { expectedRevision: s.revision, timeZone: fixture.timeZone, ledger: current, appAccessVersion: 1 }, now);
  assert.equal(s.ledger.appPreferences, undefined);
});
