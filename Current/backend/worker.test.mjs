import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import path from 'node:path';
import { tmpdir } from 'node:os';
import { Miniflare, convertV4MiniflareOptions, Response as WorkerResponse, Log, LogLevel } from 'miniflare';

test('Cloudflare runtime authenticates, persists encrypted links, and recovers browser completion after restart', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'tender-worker-test-'));
  const key = randomBytes(32).toString('base64');
  const apiToken = 'local-test-only-'.repeat(4);
  const calls = [];
  const modules = await Promise.all(['worker.mjs', 'bridge.mjs', 'config.mjs', 'transactions.mjs', 'vault-storage.mjs'].map(async name => ({ type: 'ESModule', path: path.resolve(import.meta.dirname, name), contents: await readFile(new URL(name, import.meta.url), 'utf8') })));
  const options = convertV4MiniflareOptions({
    name: 'tender-test', modules, compatibilityDate: '2026-10-01', compatibilityFlags: ['nodejs_compat'],
    resourcePersistencePath: directory, cf: false, telemetry: { enabled: false }, log: new Log(LogLevel.ERROR),
    bindings: { PLAID_ENV: 'production', PLAID_CLIENT_ID: 'test', PLAID_SECRET: 'test', TENDER_API_TOKEN: apiToken, TENDER_ENCRYPTION_KEY: key, TENDER_LINK_MODE: 'browser', TENDER_PUBLIC_URL: 'https://tender.example' },
    durableObjects: { BANK_VAULT: { className: 'BankVault', useSQLite: true } },
    outboundService: async request => {
      assert.equal(new URL(request.url).origin, 'https://production.plaid.com');
      const endpoint = new URL(request.url).pathname;
      calls.push(endpoint);
      const body = endpoint === '/link/token/create'
        ? { link_token: 'link-production-test', hosted_link_url: 'https://secure.plaid.com/hl/test' }
        : endpoint === '/link/token/get'
        ? { link_sessions: [{ results: { item_add_results: [{ public_token: 'public-production-test', institution: { name: 'Runtime Bank' } }] } }] }
        : endpoint === '/item/public_token/exchange'
        ? { item_id: 'runtime-item', access_token: 'private-runtime-token' }
        : { accounts: [{ account_id: 'runtime-checking', name: 'Checking', type: 'depository', balances: { available: 50, current: 50, iso_currency_code: 'USD' } }] };
      return new WorkerResponse(JSON.stringify(body), { headers: { 'Content-Type': 'application/json' } });
    },
  });
  let mf = new Miniflare(options);
  const call = async (route, method = 'GET', body) => {
    const response = await mf.dispatchFetch('https://tender.example' + route, { method, headers: { Authorization: `Bearer ${apiToken}` }, ...(body ? { body: JSON.stringify(body) } : {}) });
    assert.equal(response.status, 200, await response.clone().text());
    return response.json();
  };
  try {
    assert.equal((await mf.dispatchFetch('https://tender.example/v1/status')).status, 401);
    assert.equal((await call('/v1/status')).linkMode, 'browser');
    const started = await call('/v1/hosted-link', 'POST', {});
    await mf.dispose(); mf = new Miniflare(options);
    assert.equal((await call('/v1/hosted-link')).session.id, started.id);
    assert.equal((await call('/v1/hosted-link/finish', 'POST', { sessionID: started.id })).status, 'connected');
    await mf.dispose(); mf = new Miniflare(options);
    assert.equal((await call('/v1/connections')).connections[0].name, 'Runtime Bank');
    assert.equal((await call('/v1/accounts')).accounts[0].availableCents, 5000);
    assert.equal((await call('/v1/hosted-link/finish', 'POST', { sessionID: started.id })).status, 'connected');
    assert.equal(calls.filter(c => c === '/item/public_token/exchange').length, 1);
  } finally { await mf.dispose(); await rm(directory, { recursive: true, force: true }); }
});
