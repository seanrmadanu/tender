import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { randomBytes } from 'node:crypto';
import { Miniflare, convertV4MiniflareOptions, Response as WorkerResponse, Log, LogLevel } from 'miniflare';
import { authEnv, jwt, owner, authReply } from './test-auth-helper.mjs';

test('signed-in bank vaults isolate linking, repair, sessions, balances, activity and deletion in Cloudflare runtime', async () => {
  const modules = await Promise.all(['worker.mjs', 'bridge.mjs', 'config.mjs', 'transactions.mjs', 'vault-storage.mjs', 'firebase-auth.mjs'].map(async name => ({ type: 'ESModule', path: path.resolve(import.meta.dirname, name), contents: await readFile(new URL(name, import.meta.url), 'utf8') })));
  const plaidCalls = []; let disabled = false;
  const mf = new Miniflare(convertV4MiniflareOptions({
    name: 'tender-account-test', modules, compatibilityDate: '2026-10-01', compatibilityFlags: ['nodejs_compat'],
    cf: false, telemetry: { enabled: false }, log: new Log(LogLevel.ERROR),
    bindings: { ...authEnv, PLAID_ENV: 'production', PLAID_CLIENT_ID: 'test', PLAID_SECRET: 'test', TENDER_API_TOKEN: 'personal-test-token-'.repeat(3), TENDER_ENCRYPTION_KEY: randomBytes(32).toString('base64'), TENDER_LINK_MODE: 'browser', TENDER_PUBLIC_URL: 'https://tender.example' },
    durableObjects: { BANK_VAULT: { className: 'BankVault', useSQLite: true }, ACCOUNT_BANK_VAULT: { className: 'AccountBankVault', useSQLite: true } },
    outboundService: async request => {
      const url = new URL(request.url);
      if (url.hostname === 'www.googleapis.com') {
        const reply = authReply(request); return new WorkerResponse(JSON.stringify(reply.body), { headers: reply.headers });
      }
      const body = await request.json();
      if (url.hostname === 'identitytoolkit.googleapis.com') {
        const claims = JSON.parse(Buffer.from(body.idToken.split('.')[1], 'base64url'));
        return new WorkerResponse(JSON.stringify({ users: [{ localId: claims.sub, validSince: '0', disabled }] }));
      }
      assert.equal(url.origin, 'https://production.plaid.com');
      plaidCalls.push({ path: url.pathname, body });
      const reply = url.pathname === '/link/token/create' ? { link_token: 'link-production-' + body.user.client_user_id, hosted_link_url: 'https://secure.plaid.com/hl/test' }
        : url.pathname === '/link/token/get' ? { link_sessions: [{ results: { item_add_results: [{ public_token: 'public-production-alice' }] } }] }
        : url.pathname === '/item/public_token/exchange' ? { item_id: body.public_token, access_token: 'access-' + body.public_token }
        : ['/accounts/get', '/accounts/balance/get'].includes(url.pathname) ? { accounts: [{ account_id: 'checking', type: 'depository', name: 'Checking', balances: { iso_currency_code: 'USD', available: 100, current: 100 } }] }
        : url.pathname === '/transactions/sync' ? { added: [], modified: [], removed: [], next_cursor: 'one', has_more: false }
        : {};
      return new WorkerResponse(JSON.stringify(reply));
    },
  }));
  async function call(uid, route, method = 'GET', body, status = 200, extra = {}) {
    const response = await mf.dispatchFetch('https://tender.example' + route, { method, headers: { Authorization: 'Bearer ' + jwt(uid), ...extra }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    assert.equal(response.status, status, await response.clone().text()); return response.json();
  }
  try {
    assert.equal((await (await mf.dispatchFetch('https://tender.example/health')).json()).accountAuthConfigured, true);
    assert.equal((await mf.dispatchFetch('https://tender.example/v2/status')).status, 401);
    const fakePersonal = await mf.dispatchFetch('https://tender.example/v2/status', { headers: { Authorization: 'Bearer ' + 'personal-test-token-'.repeat(3) } });
    assert.equal(fakePersonal.status, 401);
    const session = await call('alice', '/v2/hosted-link', 'POST', {});
    assert.equal(plaidCalls.at(-1).body.user.client_user_id, owner('alice'));
    assert.equal((await call('bob', '/v2/hosted-link', 'GET', undefined, 200, { 'X-Tender-Verified-Owner': owner('alice') })).session, null);
    await call('bob', '/v2/hosted-link/finish', 'POST', { sessionID: session.id }, 404);
    await call('alice', '/v2/hosted-link/finish', 'POST', { sessionID: session.id });
    const alice = (await call('alice', '/v2/connections')).connections;
    assert.equal(alice.length, 1);
    assert.equal((await call('bob', '/v2/connections')).connections.length, 0);
    assert.equal((await call('alice', '/v2/accounts')).accounts[0].availableCents, 10000);
    assert.equal((await call('bob', '/v2/accounts')).accounts.length, 0);
    assert.equal((await call('alice', '/v2/sync', 'POST')).accounts[0].availableCents, 10000);
    assert.deepEqual((await call('bob', '/v2/sync', 'POST')).accounts, []);
    await call('bob', '/v2/hosted-link', 'POST', { itemID: alice[0].id }, 404);
    assert.equal((await call('alice', '/v2/transactions/sync', 'POST')).items.length, 1);
    assert.equal((await call('bob', '/v2/transactions')).items.length, 0);
    await call('bob', '/v2/connections', 'DELETE');
    assert.equal((await call('alice', '/v2/connections')).connections.length, 1);
    const legacy = await mf.dispatchFetch('https://tender.example/v1/connections', { headers: { Authorization: 'Bearer ' + 'personal-test-token-'.repeat(3) } });
    assert.deepEqual((await legacy.json()).connections, []);
    assert.equal((await mf.dispatchFetch('https://tender.example/v1/connections', { headers: { Authorization: 'Bearer ' + jwt() } })).status, 401);
    disabled = true; const count = plaidCalls.length;
    await call('alice', '/v2/accounts', 'GET', undefined, 401);
    assert.equal(plaidCalls.length, count);
  } finally { await mf.dispose(); }
});
