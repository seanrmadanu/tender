import { timingSafeEqual } from 'node:crypto';
import { createBridge } from './bridge.mjs';
import { vaultStorage } from './vault-storage.mjs';
import { configFromEnv } from './config.mjs';
import { createFirebaseVerifier, AuthError } from './firebase-auth.mjs';
const verifyFirebase = createFirebaseVerifier();

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
// A separate namespace prevents a signed-in account from ever opening the
// existing personal vault. The owner is derived by the Worker from a verified JWT.
export class AccountBankVault {
  constructor(ctx, env) { this.ctx = ctx; this.env = env; }
  async fetch(request) {
    const owner = request.headers.get('X-Tender-Verified-Owner');
    if (!/^[a-f0-9]{64}$/.test(owner ?? '')) return new Response(null, { status: 401 });
    this.ready ??= this.ctx.blockConcurrencyWhile(async () => {
      const savedOwner = await this.ctx.storage.get('owner');
      if (savedOwner && savedOwner !== owner) throw new Error('Vault owner mismatch');
      await this.ctx.storage.put('owner', owner);
      this.owner = owner;
      const config = { ...configFromEnv(this.env), user: owner };
      this.handler = await createBridge(config, vaultStorage(this.ctx.storage, config.key));
    });
    await this.ready;
    if (this.owner !== owner) return new Response(null, { status: 403 });
    return this.handler(request);
  }
}
export default {
  async fetch(request, env) {
    const route = new URL(request.url).pathname;
    let configured = true;
    try { configFromEnv(env); } catch { configured = false; }
    if (request.method === 'GET' && route === '/health') return Response.json({ service: 'Tender Bank Bridge', environment: env.PLAID_ENV, configured, accountAuthConfigured: Boolean(env.FIREBASE_PROJECT_ID && env.FIREBASE_API_KEY && env.ACCOUNT_BANK_VAULT) }, { headers: { 'Cache-Control': 'no-store' } });
    if (!configured) return Response.json({ error: 'Finish private bridge configuration.' }, { status: 503 });
    if (route.startsWith('/v2/')) {
      let owner;
      try {
        const authorization = request.headers.get('authorization') ?? '';
        if (!authorization.startsWith('Bearer ')) throw new AuthError();
        owner = await verifyFirebase(authorization.slice(7), env);
      } catch (error) {
        return Response.json({ error: error instanceof AuthError ? 'Sign in again to connect your bank.' : 'Account bank service setup is unavailable. Try again later.' },
          { status: error instanceof AuthError ? 401 : 503, headers: { 'Cache-Control': 'no-store' } });
      }
      const url = new URL(request.url); url.pathname = route.replace('/v2/', '/v1/');
      const forwarded = new Request(url, request);
      // Replace all caller-supplied routing/auth metadata at the trust boundary.
      forwarded.headers.set('X-Tender-Verified-Owner', owner);
      forwarded.headers.set('Authorization', `Bearer ${env.TENDER_API_TOKEN}`);
      try { return await env.ACCOUNT_BANK_VAULT.get(env.ACCOUNT_BANK_VAULT.idFromName(`${env.PLAID_ENV}:${owner}`)).fetch(forwarded); }
      catch { return Response.json({ error: 'Account bank storage is unavailable. Your links are preserved.' }, { status: 503, headers: { 'Cache-Control': 'no-store' } }); }
    }
    if (route !== '/bank-complete' && route !== '/.well-known/apple-app-site-association') {
      const expected = Buffer.from(`Bearer ${env.TENDER_API_TOKEN}`);
      const supplied = Buffer.from(request.headers.get('authorization') ?? '');
      if (expected.length !== supplied.length || !timingSafeEqual(expected, supplied)) return Response.json({ error: 'Authentication required' }, { status: 401, headers: { 'Cache-Control': 'no-store' } });
    }
    try { return await env.BANK_VAULT.get(env.BANK_VAULT.idFromName(env.PLAID_ENV)).fetch(request); }
    catch { return Response.json({ error: 'Bank storage is unavailable. Existing links have not been reset.' }, { status: 503 }); }
  },
};
