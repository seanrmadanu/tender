// Transactions stay separate from the manual ledger. Imports never deduct balances.
export function normalizeTransaction(t, itemID, environment) {
  if (typeof t.transaction_id !== 'string' || typeof t.account_id !== 'string' ||
      !Number.isFinite(t.amount) || Math.abs(t.amount) > 999999999.99 ||
      !/^\d{4}-\d{2}-\d{2}$/.test(t.date)) throw new Error('Invalid transaction payload');
  const category = t.personal_finance_category?.primary ?? 'UNKNOWN';
  return {
    id: `${environment}:${itemID}:${t.transaction_id}`,
    accountKey: `${environment}:${t.account_id}`,
    pendingID: t.pending_transaction_id ? `${environment}:${itemID}:${t.pending_transaction_id}` : null,
    merchant: String(t.merchant_name || t.name || 'Bank activity').slice(0, 200),
    amountCents: Math.round(t.amount * 100), currency: t.iso_currency_code ?? null,
    date: t.date, pending: Boolean(t.pending), category,
    isTransfer: category.startsWith('TRANSFER_') || category === 'LOAN_PAYMENTS',
  };
}
export async function syncItem(item, environment, plaid) {
  // Restart the entire pagination window on mutation. Never commit a partial cursor.
  for (let retry = 0; retry < 3; retry++) {
    let cursor = item.transactionCursor;
    const records = new Map((item.transactions ?? []).map(t => [t.id, t]));
    try {
      for (let page = 0; page < 100; page++) {
        const result = await plaid('/transactions/sync', {
          access_token: item.token, ...(cursor ? { cursor } : {}), count: 500,
        });
        if (!Array.isArray(result.added) || !Array.isArray(result.modified) || !Array.isArray(result.removed) ||
            typeof result.next_cursor !== 'string' || typeof result.has_more !== 'boolean') throw new Error('Invalid sync response');
        for (const removed of result.removed) records.delete(`${environment}:${item.id}:${removed.transaction_id}`);
        for (const value of [...result.added, ...result.modified]) {
          const t = normalizeTransaction(value, item.id, environment);
          if (t.pendingID) records.delete(t.pendingID);
          records.set(t.id, t);
        }
        if (records.size > 10000) throw new Error('Transaction history exceeds personal-build limit');
        if (!result.has_more) return { ...item, transactionCursor: result.next_cursor,
          transactions: [...records.values()], transactionsCheckedAt: new Date().toISOString() };
        if (cursor === result.next_cursor) throw new Error('Cursor did not advance');
        cursor = result.next_cursor;
      }
      throw new Error('Too many transaction pages');
    } catch (error) {
      if (error.providerCode !== 'TRANSACTIONS_SYNC_MUTATION_DURING_PAGINATION' || retry === 2) throw error;
    }
  }
}

export function safeDiagnostic(flow) {
  const exit = flow?.exit ?? flow?.on_exit;
  const error = exit?.error ?? [...(flow?.events ?? [])].reverse().find(e => e.event_name === 'ERROR')?.event_metadata;
  // Explicit allowlist. Never return raw provider events, OAuth URLs, or tokens.
  const clean = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value) ? value : null;
  return { code: clean(error?.error_code), type: clean(error?.error_type),
    requestID: clean(error?.request_id), sessionID: clean(flow?.link_session_id) };
}
