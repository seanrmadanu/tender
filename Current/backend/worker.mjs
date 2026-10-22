import { timingSafeEqual } from 'node:crypto';
import { createBridge } from './bridge.mjs';
import { vaultStorage } from './vault-storage.mjs';
import { configFromEnv } from './config.mjs';

// One personal vault per environment. SQLite-backed Durable Object storage is
// persistent; encryption keys and provider credentials are Worker secrets.
export class BankVault {
  constructor(ctx, env) {
    this.ready = ctx.blockConcurrencyWhile(async () => {
      const config = configFromEnv(env);
      this.handler = await createBridge(config, vaultStorage(ctx.storage, config.key));
    });
  }
  async fetch(request) { await this.ready; return this.handler(request); }
}
export default {
  async fetch(request, env) {
    const route = new URL(request.url).pathname;
    let configured = true;
    try { configFromEnv(env); } catch { configured = false; }
    if (request.method === 'GET' && route === '/health') return Response.json({ service: 'Tender Bank Bridge', environment: env.PLAID_ENV, configured }, { headers: { 'Cache-Control': 'no-store' } });
    if (!configured) return Response.json({ error: 'Finish private bridge configuration.' }, { status: 503 });
    if (route !== '/bank-complete' && route !== '/.well-known/apple-app-site-association') {
      const expected = Buffer.from(`Bearer ${env.TENDER_API_TOKEN}`);
      const supplied = Buffer.from(request.headers.get('authorization') ?? '');
      if (expected.length !== supplied.length || !timingSafeEqual(expected, supplied)) return Response.json({ error: 'Authentication required' }, { status: 401, headers: { 'Cache-Control': 'no-store' } });
    }
    try { return await env.BANK_VAULT.get(env.BANK_VAULT.idFromName(env.PLAID_ENV)).fetch(request); }
    catch { return Response.json({ error: 'Bank storage is unavailable. Existing links have not been reset.' }, { status: 503 }); }
  },
};
