import { pick, makeRedactor, safeAccount, resolveTransaction } from './assistant-privacy.mjs';
const stamp = date => date.toISOString().replace(/\.\d{3}Z$/, 'Z');
export function appData(l, query, fail) {
  const clean = makeRedactor(l);
  const section = query.section ?? 'settings', offset = query.offset ?? 0, limit = query.limit ?? 50;
  if (!Number.isInteger(offset) || offset < 0 || !Number.isInteger(limit) || limit < 1 || limit > 100) fail('Use an offset and a limit from 1–100.');
  let rows;
  const named = (o, fields) => ({ ...pick(o, fields), name: clean(o.name) });
  switch (section) {
    case 'settings': return { profile: { name: clean(l.profileName), photoSet: Boolean(l.profilePhoto) }, primaryAccountID: l.primaryAccountID ?? null, remindersEnabled: l.appPreferences?.remindersEnabled ?? true, deviceActions: ['camera', 'photo_upload', 'notification_permission', 'backup_restore', 'bank_linking', 'sign_in', 'privacy_deletion'], bankAccess: 'Bank name and saved balance only. No bank credentials, account/card/routing numbers or payments.' };
    case 'accounts': rows = l.accounts.filter(a => !a.isArchived).map(a => safeAccount(a, l, clean)); break;
    case 'envelopes': rows = l.categories.map(c => ({ ...named(c, ['id', 'limit', 'assistantLastEdit']), symbol: clean(c.symbol) })); break;
    case 'fixed_expenses': rows = (l.fixedExpenses ?? []).map(f => named(f, ['id', 'amount', 'archivedAt', 'assistantOrigin', 'assistantLastEdit'])); break;
    case 'groceries': rows = (l.groceries ?? []).map(g => ({ ...named(g, ['id', 'quantity', 'checked', 'plannedAt', 'remind', 'purchasedAt', 'expenseID', 'assistantOrigin', 'assistantLastEdit']), unit: clean(g.unit), storeName: clean(g.storeName), observations: g.observations.map(p => ({ ...pick(p, ['id', 'price', 'date']), store: clean(p.store) })) })); break;
    case 'recurring': rows = (l.recurring ?? []).map(b => named(b, ['id', 'amount', 'categoryID', 'nextDue', 'cycle', 'remind', 'cancelledAt', 'trialEndsAt', 'renewalAmountUnknown', 'assistantOrigin', 'assistantLastEdit'])); break;
    case 'archive': rows = [
      ...(l.archivedItems?.envelopes ?? []).map(x => ({ kind: 'envelope', ...named(x.category, ['id']) })),
      ...(l.archivedItems?.expenses ?? []).map(x => ({ kind: 'purchase', id: x.expense.id, name: clean(x.expense.merchant), amountCents: x.expense.amount })),
      ...(l.archivedItems?.recurring ?? []).map(x => ({ kind: 'recurring', ...named(x, ['id']) })),
      ...(l.archivedItems?.groceries ?? []).map(x => ({ kind: 'grocery', ...named(x, ['id']) })),
      ...(l.fixedExpenses ?? []).filter(x => x.archivedAt).map(x => ({ kind: 'fixed_expense', ...named(x, ['id']) })),
      ...l.accounts.filter(a => a.isArchived).map(a => ({ kind: 'account', ...safeAccount(a, l, clean) })),
    ]; break;
    case 'receipt': {
      const e = [...l.expenses, ...(l.archivedItems?.expenses ?? []).map(x => x.expense), ...(l.archivedCards ?? []).flatMap(c => c.expenses)].find(x => x.id === query.itemID), t = resolveTransaction(l, query.itemID);
      const archivedDetail = (l.archivedCards ?? []).flatMap(c => Object.entries(c.details ?? {})).find(([id]) => id === query.itemID)?.[1];
      return { found: Boolean(e || t), hasAttachment: Boolean(e?.attachment || (t && l.bankTransactionDetails?.[t.id]?.attachments?.length) || archivedDetail?.attachments?.length), items: (e?.receipt?.items ?? []).map(i => ({ ...pick(i, ['quantity', 'total']), name: clean(i.name) })) };
    }
    default: fail('Choose a supported app section.');
  }
  return { section, total: rows.length, offset, items: rows.slice(offset, offset + limit), nextOffset: offset + limit < rows.length ? offset + limit : null };
}
export function applyAppChange(l, kind, args, origin, now, entityID, h) {
  const { fail, cents, text, account, category } = h;
  const name = (v, max = 80) => { if (!text(v, max)) fail('Provide a valid name.'); return v.trim(); };
  const date = v => { if (!Number.isFinite(Date.parse(v))) fail('Provide a valid date.'); return stamp(new Date(v)); };
  const existing = (list, id) => list.find(x => x.id === id) ?? fail('This item is unavailable.');
  const touch = e => { e.assistantLastEdit = origin; return e; };
  const fallback = () => { let c = l.categories.find(c => c.name === 'Uncategorized'); if (!c) { c = { id: crypto.randomUUID().toUpperCase(), name: 'Uncategorized', symbol: 'tag', limit: 0 }; l.categories.push(c); } return c.id; };
  let entity, label;
  switch (kind) {
    case 'save_settings':
      if (args.profileName !== undefined) l.profileName = name(args.profileName);
      if (args.primaryAccountID !== undefined) { const a = account(l, args.primaryAccountID); if (a.isCash) fail('Choose a non-cash primary card.'); l.primaryAccountID = a.id; }
      if (args.remindersEnabled !== undefined) { if (typeof args.remindersEnabled !== 'boolean') fail('Choose a reminder setting.'); l.appPreferences = { remindersEnabled: args.remindersEnabled, assistantLastEdit: origin }; }
      label = 'Settings updated'; break;
    case 'open_screen':
      if (!['home', 'budgets', 'groceries', 'activity', 'profile', 'accounts', 'updates', 'archive', 'backup', 'privacy', 'ai_connections', 'shopping', 'add_purchase'].includes(args.screen)) fail('Choose a Tender screen.');
      l.assistantScreenRequest = { id: entityID, screen: args.screen, createdAt: stamp(now) }; label = 'Screen ready on next phone sync'; break;
    case 'save_envelope': {
      if (!cents(args.allocationCents)) fail('Provide a valid allocation.');
      entity = args.envelopeID ? existing(l.categories, args.envelopeID) : null;
      const values = { name: name(args.name), symbol: name(args.symbol), limit: args.allocationCents };
      if (l.categories.some(c => c.id !== entity?.id && c.name.toLowerCase() === values.name.toLowerCase())) fail('An envelope with this name exists.', 409);
      if (entity) Object.assign(touch(entity), values); else { entity = { id: entityID, ...values, assistantLastEdit: origin }; l.categories.push(entity); }
      label = 'Envelope saved'; break;
    }
    case 'edit_purchase': {
      entity = existing(l.expenses, args.expenseID);
      if (entity.importedFromBank || entity.bankTransactionID) fail('Bank amounts follow the bank. Use categorization or transaction notes.');
      const a = account(l, entity.accountID); category(l, args.categoryID);
      if (!cents(args.amountCents, true) || Date.parse(args.date) > +now || typeof args.note !== 'string' || args.note.length > 10000) fail('Provide a positive amount, past date and valid note.');
      if (entity.balanceAppliedAt && entity.balanceRevision === a.balanceRevision) { a.available += entity.amount - args.amountCents; a.updated = stamp(now); }
      Object.assign(touch(entity), { merchant: name(args.merchant, 200), amount: args.amountCents, categoryID: args.categoryID, date: date(args.date), note: args.note }); label = 'Purchase updated'; break;
    }
    case 'save_grocery': {
      l.groceries ??= [];
      if (!Number.isInteger(args.quantity) || args.quantity < 1 || args.quantity > 999) fail('Quantity must be 1–999.');
      entity = args.groceryID ? existing(l.groceries, args.groceryID) : null;
      const values = { name: name(args.name), quantity: args.quantity, unit: name(args.unit, 40) };
      if (entity) Object.assign(touch(entity), values); else { entity = { id: entityID, ...values, checked: false, observations: [], assistantOrigin: origin }; l.groceries.push(entity); }
      if (args.checked !== undefined) { if (entity.expenseID) fail('Edit the linked purchase before changing its grocery status.'); entity.checked = args.checked; }
      if (args.storeName !== undefined) entity.storeName = name(args.storeName);
      if (args.plannedAt !== undefined) entity.plannedAt = args.plannedAt === null ? null : date(args.plannedAt);
      if (args.remind !== undefined) entity.remind = args.remind;
      label = 'Grocery saved'; break;
    }
    case 'grocery_price':
      entity = existing(l.groceries ?? [], args.groceryID);
      if (!cents(args.priceCents, true)) fail('Provide a positive unit price.');
      entity.observations.push({ id: entityID, price: args.priceCents, store: name(args.storeName), date: date(args.date) }); touch(entity); label = 'Grocery price recorded'; break;
    case 'save_recurring': {
      l.recurring ??= []; category(l, args.categoryID);
      if (!cents(args.amountCents, true) || !['Weekly', 'Monthly', 'Yearly'].includes(args.cycle)) fail('Provide a valid recurring amount and cycle.');
      entity = args.recurringID ? existing(l.recurring, args.recurringID) : null;
      const values = { name: name(args.name), amount: args.amountCents, categoryID: args.categoryID, nextDue: date(args.nextDue), cycle: args.cycle, remind: args.remind };
      if (entity) { if (entity.nextDue !== values.nextDue) entity.recurrenceAnchor = values.nextDue; Object.assign(touch(entity), values); }
      else { entity = { id: entityID, ...values, recurrenceAnchor: values.nextDue, assistantOrigin: origin }; l.recurring.push(entity); }
      label = 'Recurring payment saved'; break;
    }
    case 'save_offline_account': {
      entity = args.accountID ? account(l, args.accountID) : null;
      if (entity?.bankAccountKey) fail('AI cannot edit a linked bank balance or connection.');
      if (!Number.isSafeInteger(args.balanceCents) || Math.abs(args.balanceCents) > 99_999_999_999) fail('Provide a valid balance.');
      const values = { name: name(args.name), available: args.balanceCents, updated: stamp(now), snapshotAt: stamp(now), balanceRevision: crypto.randomUUID().toUpperCase() };
      if (entity) Object.assign(touch(entity), values);
      else { if (args.isCash && l.accounts.some(a => !a.isArchived && a.isCash)) fail('Update the existing cash wallet.', 409); entity = { id: entityID, ...values, isCash: args.isCash, source: 'Manual', assistantOrigin: origin }; l.accounts.push(entity); }
      label = 'Offline balance saved'; break;
    }
    case 'archive_item': {
      const a = l.archivedItems ??= { envelopes: [], expenses: [], recurring: [], groceries: [] }, { itemKind, itemID, action } = args;
      if (!['archive', 'restore'].includes(action)) fail('Choose archive or restore.');
      const restore = action === 'restore';
      if (itemKind === 'fixed_expense') { entity = existing(l.fixedExpenses ?? [], itemID); if (restore) delete entity.archivedAt; else entity.archivedAt = stamp(now); touch(entity); }
      else if (itemKind === 'account') {
        entity = existing(l.accounts, itemID); if (entity.bankAccountKey) fail('Manage linked bank cards in Tender.');
        l.archivedCards ??= [];
        if (!restore) {
          if (entity.isArchived) fail('Account is already archived.', 409);
          const expenses = l.expenses.filter(e => e.accountID === itemID), ids = new Set(expenses.map(e => e.id));
          const groceries = l.groceries.filter(g => ids.has(g.expenseID));
          l.archivedCards.push({ id: itemID, expenses, groceries, recurring: [], bankItems: [], details: {} });
          l.expenses = l.expenses.filter(e => !ids.has(e.id)); l.groceries = l.groceries.filter(g => !ids.has(g.expenseID));
          if (l.primaryAccountID === itemID) delete l.primaryAccountID;
        } else {
          if (!entity.isArchived) fail('Account is already active.', 409);
          const history = l.archivedCards.find(c => c.id === itemID);
          if (history) {
            for (const e of history.expenses) {
              if (l.expenses.some(x => x.id === e.id || (e.bankTransactionID && x.bankTransactionID === e.bankTransactionID))) fail('A saved purchase already exists.', 409);
              if (!l.categories.some(c => c.id === e.categoryID)) e.categoryID = fallback(); l.expenses.push(e);
            }
            for (const b of history.recurring) if (!l.recurring.some(x => x.id === b.id)) { if (!l.categories.some(c => c.id === b.categoryID)) b.categoryID = fallback(); l.recurring.push(b); }
            for (const g of history.groceries) if (!l.groceries.some(x => x.id === g.id)) l.groceries.push(g);
            // Offline accounts must never carry imported bank records.
            if (history.bankItems?.some(i => i.transactions.length) || Object.keys(history.details ?? {}).length) fail('Restore this historical linked account inside Tender.');
            l.archivedCards = l.archivedCards.filter(c => c.id !== itemID);
          }
        }
        entity.isArchived = !restore; touch(entity);
      }
      else if (itemKind === 'purchase') {
        if (!restore) {
          entity = existing(l.expenses, itemID); const acct = existing(l.accounts, entity.accountID), reversedBalance = Boolean(entity.balanceAppliedAt && entity.balanceRevision === acct.balanceRevision);
          a.expenses.push({ expense: structuredClone(entity), reversedBalance, groceryLinks: structuredClone(l.groceries.filter(g => g.expenseID === itemID)) });
          l.expenses = l.expenses.filter(e => e.id !== itemID); if (reversedBalance) { acct.available += entity.amount; acct.updated = stamp(now); }
          for (const g of l.groceries.filter(g => g.expenseID === itemID)) { delete g.expenseID; delete g.purchasedAt; g.checked = false; }
        } else {
          const saved = a.expenses.find(e => e.expense.id === itemID) ?? fail('Archived purchase is unavailable.'); entity = saved.expense;
          const acct = account(l, entity.accountID);
          if (l.expenses.some(e => e.id === itemID || (entity.bankTransactionID && e.bankTransactionID === entity.bankTransactionID))) fail('Purchase already exists.', 409);
          if (!l.categories.some(c => c.id === entity.categoryID)) entity.categoryID = fallback();
          if (saved.reversedBalance && entity.balanceRevision === acct.balanceRevision) { acct.available -= entity.amount; acct.updated = stamp(now); } else delete entity.balanceAppliedAt;
          for (const link of saved.groceryLinks) { const g = l.groceries.find(g => g.id === link.id && !g.expenseID); if (g) Object.assign(g, pick(link, ['expenseID', 'purchasedAt', 'checked'])); }
          l.expenses.push(touch(entity)); a.expenses = a.expenses.filter(e => e.expense.id !== itemID);
        }
      } else if (itemKind === 'envelope') {
        if (!restore) {
          entity = existing(l.categories, itemID);
          const expenseIDs = l.expenses.filter(e => e.categoryID === itemID).map(e => e.id), recurringIDs = l.recurring.filter(b => b.categoryID === itemID).map(b => b.id);
          l.categories = l.categories.filter(c => c.id !== itemID);
          const fallbackID = expenseIDs.length || recurringIDs.length ? fallback() : null;
          for (const e of l.expenses) if (expenseIDs.includes(e.id)) e.categoryID = fallbackID;
          for (const b of l.recurring) if (recurringIDs.includes(b.id)) b.categoryID = fallbackID;
          a.envelopes.push({ category: entity, expenseIDs, recurringIDs, fallbackID });
        } else {
          const saved = a.envelopes.find(e => e.category.id === itemID) ?? fail('Archived envelope is unavailable.'); entity = saved.category;
          if (l.categories.some(c => c.id === itemID)) fail('Envelope already exists.', 409);
          l.categories.push(touch(entity));
          for (const e of l.expenses) if (saved.expenseIDs.includes(e.id) && e.categoryID === saved.fallbackID) e.categoryID = itemID;
          for (const b of l.recurring) if (saved.recurringIDs.includes(b.id) && b.categoryID === saved.fallbackID) b.categoryID = itemID;
          a.envelopes = a.envelopes.filter(e => e.category.id !== itemID);
        }
      } else {
        const key = { grocery: 'groceries', recurring: 'recurring' }[itemKind]; if (!key) fail('Choose a supported archive category.');
        entity = existing(restore ? a[key] : l[key], itemID);
        if (restore) {
          if (l[key].some(x => x.id === itemID)) fail('Item already exists.', 409);
          if (key === 'recurring' && !l.categories.some(c => c.id === entity.categoryID)) entity.categoryID = fallback();
          if (key === 'groceries' && entity.expenseID && !l.expenses.some(e => e.id === entity.expenseID)) { delete entity.expenseID; delete entity.purchasedAt; entity.checked = false; }
          l[key].push(touch(entity)); a[key] = a[key].filter(x => x.id !== itemID);
        } else { a[key].push(entity); l[key] = l[key].filter(x => x.id !== itemID); }
      }
      label = restore ? 'Item restored' : 'Item moved to Archive'; break;
    }
    default: fail('This action is not supported.');
  }
  return { entity, label };
}

export function spendingEntries(l, zone, bankDate) {
  const active = new Set(l.accounts.filter(a => !a.isArchived).map(a => a.id));
  const byKey = new Map(l.accounts.filter(a => active.has(a.id)).map(a => [a.bankAccountKey, a.id]));
  const excluded = new Set((l.archivedItems?.expenses ?? []).map(x => x.expense.bankTransactionID).filter(Boolean));
  const manual = l.expenses.filter(e => active.has(e.accountID));
  const linked = new Set(manual.map(e => e.bankTransactionID).filter(Boolean));
  const localDay = date => new Intl.DateTimeFormat('en-CA', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date(date));
  const normalized = name => name.toLowerCase().replace(/[^a-z0-9]/g, '');
  const bank = (l.bankActivity ?? []).flatMap(i => i.transactions).filter(t => byKey.has(t.accountKey) && !t.pending && !t.isTransfer && t.currency === 'USD' && t.amountCents > 0 && !excluded.has(t.id) && !linked.has(t.id));
  const match = (e, t) => !e.bankTransactionID && e.accountID === byKey.get(t.accountKey) && e.amount === t.amountCents && localDay(e.date) === t.date && normalized(e.merchant) === normalized(t.merchant);
  return [...manual.map(e => ({ amount: e.amount, date: e.date, categoryID: e.categoryID, fixedExpenseID: e.fixedExpenseID })),
    ...bank.filter(t => { const matches = manual.filter(e => match(e, t)); return !(matches.length === 1 && bank.filter(other => match(matches[0], other)).length === 1); }).map(t => ({ amount: t.amountCents, date: bankDate(t.date, zone) }))];
}
