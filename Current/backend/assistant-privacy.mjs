import { createHash } from 'node:crypto';
export const transactionReference = id => 'txn_' + createHash('sha256').update(id).digest('hex').slice(0, 32);
export const resolveTransaction = (l, reference) => (l.bankActivity ?? []).flatMap(i => i.transactions).find(t => t.id === reference || transactionReference(t.id) === reference);
export function makeRedactor(ledger) {
  const privateValues = new Set();
  const add = value => {
    if (!['string', 'number'].includes(typeof value)) return;
    const s = String(value); if (s.length < 4) return;
    privateValues.add(s); privateValues.add(s.split(':').at(-1));
    if (/\s/.test(s)) for (const part of s.split(/\s+/)) if (part.length >= 4) privateValues.add(part);
  };
  for (const a of ledger.accounts) {
    add(a.bankAccountKey);
    for (const [key, value] of Object.entries(a.bankDetails ?? {})) if (/mask|number|routing|token|itemID/i.test(key)) add(value);
  }
  const bankItems = [...(ledger.bankActivity ?? []), ...(ledger.archivedCards ?? []).flatMap(c => c.bankItems ?? [])];
  for (const item of bankItems) { add(item.id); for (const t of item.transactions) { add(t.id); add(t.pendingID); add(t.accountKey); } }
  for (const e of [...ledger.expenses, ...(ledger.archivedItems?.expenses ?? []).map(x => x.expense), ...(ledger.archivedCards ?? []).flatMap(x => x.expenses)]) add(e.bankTransactionID);
  for (const id of Object.keys(ledger.bankTransactionDetails ?? {})) add(id);
  return value => String(value ?? '')
    .replace(/\b(?:access[_ -]?token|refresh[_ -]?token|api[_ -]?key|password|passcode|pin|cvv|cvc|iban|routing(?:\s+number)?|(?:bank\s+)?account\s+number|card\s+number)\b\s*(?::|=|\s)\s*[^;,\n]+/gi, '[private credential]')
    .replace(/[A-Za-z0-9:_-]{4,}/g, token => privateValues.has(token) ? '[private]' : token)
    .replace(/(?:\d[ -]?){8,19}\d/g, '[private number]')
    .replace(/(?:[•·*xX]{2,}|ending(?: in)?\s*)\s*\d{4}\b/gi, '[private]');
}
export const safeText = (value, ledger) => makeRedactor(ledger)(value);
export function safeAccount(account, ledger, clean = makeRedactor(ledger)) {
  const name = account.bankAccountKey ? account.bankDetails?.institutionName || 'Linked bank' : account.name;
  return { id: account.id, name: clean(name), availableCents: account.available, bankLinked: Boolean(account.bankAccountKey), isCash: account.isCash === true, updatedAt: account.updated };
}
export const pick = (o, fields) => Object.fromEntries(fields.filter(k => o[k] !== undefined).map(k => [k, o[k]]));
