import { createHash } from 'node:crypto';
import { appData, applyAppChange, spendingEntries } from './assistant-app.mjs';
import { safeText, makeRedactor, safeAccount, transactionReference, resolveTransaction } from './assistant-privacy.mjs';

export class LedgerFault extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}
const fail = (message, status) => { throw new LedgerFault(message, status); };
const uuid = v => typeof v === 'string' && /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i.test(v);
const cents = (v, positive = false) => Number.isSafeInteger(v) && v >= (positive ? 1 : 0) && v <= 99_999_999_999;
const text = (v, max = 80) => typeof v === 'string' && v.trim().length > 0 && v.length <= max && !/[\u0000-\u001f\u007f]/.test(v);
const canonical = v => JSON.stringify(v, (_, x) => x && typeof x === 'object' && !Array.isArray(x) ? Object.fromEntries(Object.keys(x).sort().map(k => [k, x[k]])) : x);
const hash = v => createHash('sha256').update(canonical(v)).digest('hex');
const stamp = date => date.toISOString().replace(/\.\d{3}Z$/, 'Z');
const active = a => a.isArchived !== true;
function bankDate(date, zone) {
  const target = Date.parse(date + 'T00:00:00Z'); let candidate = target;
  const formatter = new Intl.DateTimeFormat('en-US', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hourCycle: 'h23' });
  for (let i = 0; i < 3; i++) {
    const p = Object.fromEntries(formatter.formatToParts(candidate).map(p => [p.type, p.value]));
    const offset = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second) - candidate;
    candidate = target - offset;
  }
  return stamp(new Date(candidate));
}
const monthKey = (date, zone) => new Intl.DateTimeFormat('en-CA', { timeZone: zone, year: 'numeric', month: '2-digit' }).format(new Date(date));
export function funding(ledger, now = new Date(), zone = 'UTC') {
  const paid = new Map(), month = monthKey(now, zone);
  for (const e of ledger.expenses) if (e.fixedExpenseID && monthKey(e.date, zone) === month) paid.set(e.fixedExpenseID, (paid.get(e.fixedExpenseID) ?? 0) + e.amount);
  const reserve = (ledger.fixedExpenses ?? []).filter(f => !f.archivedAt).reduce((s, f) => s + Math.max(0, f.amount - (paid.get(f.id) ?? 0)), 0);
  const balance = ledger.accounts.filter(active).reduce((s, a) => s + a.available, 0);
  return { balance, reserve, available: Math.max(0, balance - reserve) };
}
export function validateLedger(l, previous, now = new Date(), zone = 'UTC') {
  function safe(value, depth = 0) {
    if (depth > 40) fail('Ledger nesting is too deep.');
    if (value && typeof value === 'object') for (const key of Object.keys(value)) {
      if (['__proto__', 'prototype', 'constructor'].includes(key)) fail('Invalid ledger key.');
      safe(value[key], depth + 1);
    }
  }
  safe(l);
  if (!l || l.schemaVersion !== 1 || l.isDemo === true || !Array.isArray(l.accounts) || !Array.isArray(l.categories) || !Array.isArray(l.expenses)) fail('Use a personal Tender ledger.');
  if (Buffer.byteLength(JSON.stringify(l)) > 8_000_000) fail('This ledger exceeds the current 8 MB cloud limit.', 413);
  for (const [key, limit] of [['accounts', 1000], ['categories', 1000], ['expenses', 100000], ['fixedExpenses', 1000]]) {
    const list = l[key] ?? [];
    if (!Array.isArray(list) || list.length > limit || list.some(x => !x || !uuid(x.id)) || new Set(list.map(x => x.id.toLowerCase())).size !== list.length) fail('Invalid ledger records.');
  }
  if (l.accounts.some(a => !text(a.name) || !Number.isSafeInteger(a.available) || Math.abs(a.available) > 99_999_999_999)) fail('Invalid account balance.');
  if (l.categories.some(c => !text(c.name) || !cents(c.limit))) fail('Invalid envelope.');
  if ((l.fixedExpenses ?? []).some(f => !text(f.name) || !cents(f.amount, true))) fail('Invalid fixed expense.');
  if (l.profileName != null && !text(l.profileName)) fail('Invalid profile name.');
  if (l.appPreferences != null && typeof l.appPreferences.remindersEnabled !== 'boolean') fail('Invalid reminder preference.');
  if (l.assistantScreenRequest != null && (!uuid(l.assistantScreenRequest.id) || !['home', 'budgets', 'groceries', 'activity', 'profile', 'accounts', 'updates', 'archive', 'backup', 'privacy', 'ai_connections', 'shopping', 'add_purchase'].includes(l.assistantScreenRequest.screen) || (l.assistantScreenRequest.createdAt != null && !Number.isFinite(Date.parse(l.assistantScreenRequest.createdAt))))) fail('Invalid screen request.');
  for (const [key, limit] of [['recurring', 1000], ['groceries', 10000]]) {
    if (!Array.isArray(l[key]) || l[key].length > limit || l[key].some(x => !x || !uuid(x.id)) || new Set(l[key].map(x => x.id)).size !== l[key].length) fail('Invalid app items.');
  }
  if (l.recurring.some(b => !text(b.name) || !Number.isSafeInteger(b.amount) || b.amount < 0 || b.amount > 99_999_999_999 || (b.amount === 0 && !(b.renewalAmountUnknown && b.trialEndsAt)) || !l.categories.some(c => c.id === b.categoryID) || !Number.isFinite(Date.parse(b.nextDue)) || !['Weekly', 'Monthly', 'Yearly'].includes(b.cycle) || typeof b.remind !== 'boolean')) fail('Invalid recurring payment.');
  if (l.groceries.some(g => !text(g.name) || !Number.isInteger(g.quantity) || g.quantity < 1 || g.quantity > 999 || typeof g.checked !== 'boolean' || !Array.isArray(g.observations) || g.observations.length > 10000 || g.observations.some(p => !uuid(p.id) || !cents(p.price, true) || !Number.isFinite(Date.parse(p.date))))) fail('Invalid grocery item.');
  const accounts = new Set(l.accounts.map(a => a.id)), categories = new Set(l.categories.map(c => c.id));
  if (l.expenses.some(e => !text(e.merchant, 200) || !cents(e.amount, true) || !accounts.has(e.accountID) || !categories.has(e.categoryID) || !Number.isFinite(Date.parse(e.date)) || Date.parse(e.date) > +now || typeof e.note !== 'string' || e.note.length > 10000)) fail('Invalid purchase.');
  const imported = l.expenses.map(e => e.bankTransactionID).filter(Boolean);
  if (new Set(imported).size !== imported.length) fail('An imported purchase is duplicated.');
  if (!Array.isArray(l.bankActivity ?? []) || (l.bankActivity ?? []).some(i => !Array.isArray(i.transactions))) fail('Invalid bank activity.');
  const transactions = (l.bankActivity ?? []).flatMap(i => i.transactions);
  if (transactions.length > 100000 || new Set(transactions.map(t => t.id)).size !== transactions.length || transactions.some(t => typeof t.id !== 'string' || !t.id.length || t.id.length > 500 || typeof t.accountKey !== 'string' || typeof t.merchant !== 'string' || t.merchant.length > 500 || !Number.isSafeInteger(t.amountCents) || Math.abs(t.amountCents) > 99_999_999_999 || !/^\d{4}-\d{2}-\d{2}$/.test(t.date) || !Number.isFinite(Date.parse(t.date)) || new Date(t.date).toISOString().slice(0, 10) !== t.date || typeof t.pending !== 'boolean' || typeof t.isTransfer !== 'boolean')) fail('Invalid bank activity.');
  const allocated = l.categories.reduce((s, c) => s + c.limit, 0), budget = l.monthlyAllocation ?? allocated;
  if (!Number.isSafeInteger(budget) || budget < 0 || budget > 9_999_999_999_900) fail('Invalid monthly allocation.');
  // Old plans may become overfunded after spending; only allocation edits must
  // meet today's cap. Never reject the whole saved ledger for an old plan.
  const oldAmounts = previous?.categories.map(c => [c.id, c.limit]) ?? [];
  const oldLimits = new Map(oldAmounts);
  const changed = previous && (budget !== (previous.monthlyAllocation ?? previous.categories.reduce((s, c) => s + c.limit, 0)) || l.categories.some(c => oldLimits.has(c.id) ? c.limit !== oldLimits.get(c.id) : c.limit > 0));
  if (changed && (budget > funding(l, now, zone).available || allocated > budget)) fail('Allocation exceeds the balance after fixed expenses.', 422);
  return l;
}
export function stripUnverifiedOrigins(ledger, previous) {
  const next = structuredClone(ledger);
  // Plaid replaces a pending transaction ID with a posted ID. Carry only the
  // server's existing attribution across that bank-supplied relationship.
  const previousDetails = { ...(previous?.bankTransactionDetails ?? {}) };
  for (const tx of (next.bankActivity ?? []).flatMap(item => item.transactions)) {
    if (tx.pendingID && !previousDetails[tx.id] && previousDetails[tx.pendingID]) previousDetails[tx.id] = previousDetails[tx.pendingID];
  }
  const known = new Map();
  function collect(value) {
    if (!value || typeof value !== 'object') return;
    if (uuid(value.id) && (value.assistantOrigin || value.assistantLastEdit)) known.set(value.id.toUpperCase(), value);
    for (const item of Object.values(value)) collect(item);
  }
  collect(previous);
  function walk(value, old) {
    if (!value || typeof value !== 'object') return;
    if (Array.isArray(value)) {
      const byID = new Map((Array.isArray(old) ? old : []).filter(v => v?.id).map(v => [v.id, v]));
      value.forEach(v => walk(v, byID.get(v?.id))); return;
    }
    const original = uuid(value.id) ? known.get(value.id.toUpperCase()) ?? old : old;
    for (const field of ['assistantOrigin', 'assistantLastEdit']) {
      delete value[field]; if (original?.[field]) value[field] = structuredClone(original[field]);
    }
    for (const [key, item] of Object.entries(value)) if (!['assistantOrigin', 'assistantLastEdit'].includes(key)) walk(item, value === next && key === 'bankTransactionDetails' ? previousDetails : old?.[key]);
  }
  walk(next, previous); return next;
}
export function newCloudState(owner) { return { owner, revision: 0, epoch: 0, connected: false, ledger: null, events: [], requests: {}, connections: {}, timeZone: 'UTC' }; }
export function publishLedger(state, input, now = new Date()) {
  if (input.expectedRevision !== state.revision) fail('Your phone and cloud changed at the same time. Sync and resolve the conflict.', 409);
  try { new Intl.DateTimeFormat('en-US', { timeZone: input.timeZone }).format(now); } catch { fail('Invalid time zone.'); }
  const uploaded = structuredClone(input.ledger);
  // Build 9 cannot encode these fields. Preserve them across old-client
  // syncs; current clients declare support and may deliberately clear them.
  if (input.appAccessVersion !== 1) for (const key of ['appPreferences', 'assistantScreenRequest']) {
    if (!Object.hasOwn(uploaded, key) && state.ledger?.[key] !== undefined) uploaded[key] = structuredClone(state.ledger[key]);
  }
  validateLedger(uploaded, state.ledger, now, input.timeZone);
  const next = stripUnverifiedOrigins(uploaded, state.ledger);
  validateLedger(next, state.ledger, now, input.timeZone);
  state.ledger = next; state.timeZone = input.timeZone; state.connected = true; state.revision++;
  return state;
}
function account(ledger, id) { return ledger.accounts.find(a => a.id === id && active(a)) ?? fail('Choose an active account.'); }
function category(ledger, id) { return ledger.categories.find(c => c.id === id) ?? fail('Choose an existing envelope.'); }
function fixed(ledger, id) { if (id == null) return; return (ledger.fixedExpenses ?? []).find(f => f.id === id && !f.archivedAt) ?? fail('Choose an active fixed expense.'); }
function bankPurchase(ledger, id) {
  const tx = resolveTransaction(ledger, id);
  if (!tx || tx.pending || tx.isTransfer || tx.currency !== 'USD' || !cents(tx.amountCents, true)) fail('Choose a posted USD bank purchase.');
  const a = ledger.accounts.find(a => a.bankAccountKey === tx.accountKey && active(a)) ?? fail('Bank account is unavailable.');
  return { tx, account: a };
}
export function applyAssistantChange(state, command, source, now = new Date()) {
  if (!state.connected || !state.ledger) fail('Open Tender and enable AI Connections first.', 403);
  if (!['chatgpt', 'claude', 'assistant'].includes(source)) fail('Invalid connection source.', 403);
  if (!uuid(command.requestID) || !Number.isFinite(Date.parse(command.issuedAt)) || Math.abs(+now - Date.parse(command.issuedAt)) > 86400000) fail('This request expired. Create a new request.');
  const digest = hash(command), saved = state.requests[command.requestID];
  if (saved) { if (saved.hash !== digest || saved.source !== source) fail('Request ID was reused for a different change.', 409); return { ...saved.result, repeated: true }; }
  if (command.expectedRevision !== state.revision) fail('The ledger changed. Read the current context and try again.', 409);
  if (Object.values(state.requests).filter(r => +now - r.savedAt < 2 * 86400000).length >= 5000) fail('The connection has reached its change limit. Try later.', 429);
  const l = structuredClone(state.ledger), args = command.arguments ?? {}, entityID = command.requestID.toUpperCase();
  const origin = { provider: source, actionID: command.requestID, createdAt: stamp(now) };
  let entity, label;
  switch (command.kind) {
    case 'record_purchase': {
      const a = account(l, args.accountID); category(l, args.categoryID); fixed(l, args.fixedExpenseID);
      if (!cents(args.amountCents, true) || !text(args.merchant, 200) || !Number.isFinite(Date.parse(args.date)) || Date.parse(args.date) > +now) fail('Provide a positive USD amount, merchant and past purchase date.');
      // A same-account/amount purchase near the date must be resolved explicitly
      // rather than silently creating another entry for an imported debit.
      const similar = l.expenses.some(e => e.accountID === a.id && e.amount === args.amountCents && Math.abs(Date.parse(e.date) - Date.parse(args.date)) < 4 * 86400000)
        || (l.bankActivity ?? []).flatMap(i => i.transactions).some(t => t.accountKey === a.bankAccountKey && t.amountCents === args.amountCents && Math.abs(Date.parse(t.date) - Date.parse(args.date)) < 4 * 86400000);
      if (similar && args.confirmDistinct !== true) fail('A possible matching purchase exists. Find and categorize it, or ask the user whether this is a separate purchase.', 409);
      if (typeof args.deductFromBalance !== 'boolean') fail('Specify whether this purchase is already reflected in the account balance.');
      entity = { id: entityID, merchant: args.merchant.trim(), amount: args.amountCents, categoryID: args.categoryID, accountID: a.id, date: stamp(new Date(args.date)), note: args.note ?? '', assistantOrigin: origin };
      if (args.fixedExpenseID) entity.fixedExpenseID = args.fixedExpenseID;
      if (args.deductFromBalance) { a.available -= args.amountCents; a.updated = stamp(now); entity.balanceAppliedAt = stamp(now); if (a.balanceRevision) entity.balanceRevision = a.balanceRevision; }
      l.expenses.push(entity); label = 'Purchase recorded'; break;
    }
    case 'categorize_transaction': {
      const { tx, account: a } = bankPurchase(l, args.transactionID); category(l, args.categoryID); fixed(l, args.fixedExpenseID);
      entity = l.expenses.find(e => e.bankTransactionID === tx.id);
      if (!entity && args.matchExpenseID) {
        entity = l.expenses.find(e => e.id === args.matchExpenseID && !e.bankTransactionID && e.accountID === a.id && e.amount === tx.amountCents && Math.abs(Date.parse(e.date) - Date.parse(tx.date)) < 4 * 86400000);
        if (!entity) fail('That manual receipt cannot match this bank purchase.');
        entity.bankTransactionID = tx.id;
      }
      if (!entity) {
        const candidates = l.expenses.some(e => e.accountID === a.id && !e.bankTransactionID && e.amount === tx.amountCents && Math.abs(Date.parse(e.date) - Date.parse(tx.date)) < 4 * 86400000);
        if (candidates && args.confirmDistinct !== true) fail('Resolve the possible manual receipt match before categorizing.', 409);
        // Bank amounts already include the debit. Never deduct a second time.
        entity = { id: entityID, merchant: tx.merchant, amount: tx.amountCents, accountID: a.id, date: bankDate(tx.date, state.timeZone), note: '', bankTransactionID: tx.id, importedFromBank: true, assistantOrigin: origin };
        l.expenses.push(entity);
      }
      entity.categoryID = args.categoryID; entity.fixedExpenseID = args.fixedExpenseID ?? null; entity.assistantLastEdit = origin; label = 'Transaction categorized'; break;
    }
    case 'transaction_note': {
      if (typeof args.note !== 'string' || args.note.length > 10000) fail('Keep notes under 10,000 characters.');
      const tx = resolveTransaction(l, args.transactionID);
      if (!tx || !l.accounts.some(a => active(a) && a.bankAccountKey === tx.accountKey)) fail('Transaction is unavailable.');
      l.bankTransactionDetails ??= {}; entity = l.bankTransactionDetails[tx.id] ??= { note: '', attachments: [] };
      entity.note = args.note; entity.assistantLastEdit = origin; label = 'Transaction note updated'; break;
    }
    case 'fixed_expense': {
      if (!text(args.name) || !cents(args.amountCents, true)) fail('Provide a name and a positive monthly amount.');
      l.fixedExpenses ??= [];
      entity = args.fixedExpenseID ? fixed(l, args.fixedExpenseID) : null;
      if (!entity) {
        if (l.fixedExpenses.some(f => !f.archivedAt && f.name.trim().toLowerCase() === args.name.trim().toLowerCase())) fail('A fixed expense with this name already exists. Update it instead.', 409);
        entity = { id: entityID, name: args.name.trim(), amount: args.amountCents, assistantOrigin: origin }; l.fixedExpenses.push(entity);
      } else { entity.name = args.name.trim(); entity.amount = args.amountCents; entity.assistantLastEdit = origin; }
      label = 'Fixed expense saved'; break;
    }
    case 'monthly_allocations': {
      if (!cents(args.totalCents) || !args.allocations || Array.isArray(args.allocations) || Object.keys(args.allocations).length !== l.categories.length) fail('Provide the monthly total and every envelope allocation.');
      for (const c of l.categories) { if (!Object.hasOwn(args.allocations, c.id) || !cents(args.allocations[c.id])) fail('Invalid envelope allocations.'); c.limit = args.allocations[c.id]; c.assistantLastEdit = origin; }
      l.monthlyAllocation = args.totalCents; label = 'Monthly allocations saved'; break;
    }
    default: ({ entity, label } = applyAppChange(l, command.kind, args, origin, now, entityID, { fail, cents, text, account, category }));
  }
  validateLedger(l, state.ledger, now, state.timeZone);
  // Atomic staging: even requests with out-of-range resulting balances never
  // mutate the persisted ledger or consume an idempotency key on failure.
  const revision = state.revision + 1;
  const result = { status: 'saved', revision, actionID: command.requestID, entityID: entity?.id ?? null, message: label, source, funding: funding(l, now, state.timeZone) };
  state.ledger = l; state.revision = revision;
  state.events = [...state.events, { id: command.requestID, provider: source, createdAt: stamp(now), kind: command.kind, title: label, entityID: entity?.id ?? null }].slice(-500);
  state.requests = Object.fromEntries(Object.entries(state.requests).filter(([, r]) => +now - r.savedAt < 2 * 86400000));
  state.requests[command.requestID] = { hash: digest, source, savedAt: +now, result };
  return result;
}
export function assistantContext(state, now = new Date()) {
  if (!state.connected || !state.ledger) fail('Open Tender and enable AI Connections first.', 403);
  const l = state.ledger, clean = makeRedactor(state.ledger);
  return { revision: state.revision, timeZone: state.timeZone, currency: 'USD', now: stamp(now), funding: funding(l, now, state.timeZone),
    balancesAreSavedSnapshots: true, accounts: l.accounts.filter(active).map(a => safeAccount(a, l, clean)),
    envelopes: l.categories.map(c => ({ id: c.id, name: clean(c.name), allocationCents: c.limit })), monthlyAllocationCents: l.monthlyAllocation ?? l.categories.reduce((s, c) => s + c.limit, 0),
    fixedExpenses: (l.fixedExpenses ?? []).filter(f => !f.archivedAt).map(f => ({ id: f.id, name: clean(f.name), monthlyCents: f.amount })),
    settings: appData(l, { section: 'settings' }, fail), appSections: ['groceries', 'recurring', 'envelopes', 'fixed_expenses', 'accounts', 'archive', 'receipt', 'report', 'shopping', 'settings'] };
}
export function wipeCloudBankRecords(state) {
  if (state.ledger) {
    const l = structuredClone(state.ledger), ids = new Set(l.accounts.filter(a => a.bankAccountKey).map(a => a.id));
    const expenses = new Set(l.expenses.filter(e => ids.has(e.accountID)).map(e => e.id));
    l.accounts = l.accounts.filter(a => !ids.has(a.id)); l.expenses = l.expenses.filter(e => !ids.has(e.accountID));
    if (l.archivedItems?.expenses) l.archivedItems.expenses = l.archivedItems.expenses.filter(e => !ids.has(e.expense.accountID));
    if (l.archivedCards) l.archivedCards = l.archivedCards.filter(c => !ids.has(c.id));
    if (ids.has(l.primaryAccountID)) delete l.primaryAccountID;
    delete l.bankActivity; delete l.bankTransactionDetails; delete l.bankSync;
    for (const item of l.groceries ?? []) if (expenses.has(item.expenseID)) { delete item.expenseID; delete item.purchasedAt; item.checked = false; item.remind = false; }
    state.ledger = l;
  }
  state.connected = false; state.epoch++; state.revision++; state.connections = {}; state.requests = {}; state.events = [];
}
export function findPurchases(state, query = {}) {
  assistantContext(state);
  for (const day of [query.from, query.to].filter(v => v !== undefined)) if (!/^\d{4}-\d{2}-\d{2}$/.test(day) || !Number.isFinite(Date.parse(day)) || new Date(day).toISOString().slice(0, 10) !== day) fail('Invalid date range.');
  const l = state.ledger, lower = query.from ? Date.parse(bankDate(query.from, state.timeZone)) : -Infinity;
  // Advance the calendar date, then resolve local midnight. Adding 24 hours to
  // a local timestamp would be wrong across daylight-saving transitions.
  const upper = query.to ? Date.parse(bankDate(new Date(Date.parse(query.to) + 86400000).toISOString().slice(0, 10), state.timeZone)) : Infinity;
  if (Number.isNaN(lower) || Number.isNaN(upper) || lower > upper) fail('Invalid date range.');
  const accountIDs = new Set(l.accounts.filter(active).map(a => a.id));
  const accounts = new Map(l.accounts.filter(active).filter(a => a.bankAccountKey).map(a => [a.bankAccountKey, a.id]));
  const matches = (merchant, accountID, date) => accountIDs.has(accountID) && (!query.accountID || query.accountID === accountID) && (!query.merchant || merchant.toLowerCase().includes(query.merchant.toLowerCase())) && Date.parse(date) >= lower && Date.parse(date) < upper;
  const clean = makeRedactor(l);
  const manual = l.expenses.filter(e => matches(e.merchant, e.accountID, e.date)).map(e => ({ expenseID: e.id, bankTransactionID: e.bankTransactionID ? transactionReference(e.bankTransactionID) : null, accountID: e.accountID, merchant: clean(e.merchant), amountCents: e.amount, date: e.date, categoryID: e.categoryID, fixedExpenseID: e.fixedExpenseID ?? null, note: clean(e.note) }));
  const bank = (l.bankActivity ?? []).flatMap(i => i.transactions).filter(t => matches(t.merchant, accounts.get(t.accountKey), bankDate(t.date, state.timeZone))).map(t => ({ bankTransactionID: transactionReference(t.id), accountID: accounts.get(t.accountKey), merchant: clean(t.merchant), amountCents: t.amountCents, currency: t.currency, date: t.date, pending: t.pending, isTransfer: t.isTransfer, note: clean(l.bankTransactionDetails?.[t.id]?.note) }));
  return { revision: state.revision, purchases: [...bank, ...manual].sort((a, b) => Date.parse(b.date) - Date.parse(a.date)).slice(0, 100), limit: 100, manualAndBankMatchesMayBothAppear: true };
}

export function readAppSection(state, query = {}, now = new Date()) {
  assistantContext(state, now);
  const l = state.ledger;
  if (!['report', 'shopping'].includes(query.section)) return { revision: state.revision, ...appData(l, query, fail) };
  // Reuse date validation from the purchase read boundary without its 100-row
  // display limit. Report totals must include the entire requested period.
  findPurchases(state, { from: query.from, to: query.to });
  const month = new Intl.DateTimeFormat('en-CA', { timeZone: state.timeZone, year: 'numeric', month: '2-digit' }).format(now);
  const start = Date.parse(bankDate(query.from ?? month + '-01', state.timeZone));
  const end = query.to ? Date.parse(bankDate(new Date(Date.parse(query.to) + 86400000).toISOString().slice(0, 10), state.timeZone)) : +now + 1;
  const entries = spendingEntries(l, state.timeZone, bankDate).filter(e => Date.parse(e.date) >= start && Date.parse(e.date) < end);
  if (query.section === 'shopping') {
    category(l, query.categoryID); if (!cents(query.amountCents, true)) fail('Provide a positive proposed cost.');
    const spent = entries.filter(e => e.categoryID === query.categoryID && !e.fixedExpenseID).reduce((s, e) => s + e.amount, 0);
    const envelopeAfterCents = category(l, query.categoryID).limit - spent - query.amountCents;
    const cashAfterCents = funding(l, now, state.timeZone).available - query.amountCents;
    return { revision: state.revision, fits: l.accounts.some(active) && envelopeAfterCents >= 0 && cashAfterCents >= 0, envelopeAfterCents, cashAfterCents };
  }
  const clean = makeRedactor(l);
  const categories = l.categories.map(c => ({ id: c.id, name: clean(c.name), spentCents: entries.filter(e => e.categoryID === c.id).reduce((s, e) => s + e.amount, 0), allocationCents: c.limit }));
  const days = new Map(); for (const e of entries) { const day = new Intl.DateTimeFormat('en-CA', { timeZone: state.timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(e.date)); days.set(day, (days.get(day) ?? 0) + e.amount); }
  return { revision: state.revision, from: query.from ?? month + '-01', to: query.to ?? null, totalCents: entries.reduce((s, e) => s + e.amount, 0), purchaseCount: entries.length, unassignedCents: entries.filter(e => !e.categoryID).reduce((s, e) => s + e.amount, 0), categories, days: [...days].sort().map(([date, spentCents]) => ({ date, spentCents })), funding: funding(l, now, state.timeZone) };
}
