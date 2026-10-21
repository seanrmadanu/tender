import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createServer, normalizeAccounts, cents, encrypt, decrypt } from './server.mjs';

test('available balances preserve unknown values and exclude credit and foreign cash', () => {
  const accounts = normalizeAccounts({ accounts: [
    { account_id: 'checking', name: 'Checking', type: 'depository', balances: { available: 0.29, current: 10, iso_currency_code: 'USD' } },
    { account_id: 'unknown', name: 'Unknown', type: 'depository', balances: { available: null, current: 20, iso_currency_code: 'USD' } },
    { account_id: 'canada', name: 'CAD', type: 'depository', balances: { available: 50, current: 50, iso_currency_code: 'CAD' } },
    { account_id: 'credit', name: 'Credit limit', type: 'credit', balances: { available: 5000, current: 100, iso_currency_code: 'USD' } },
  ] }, '2026-10-20T12:00:00Z');
  assert.equal(accounts.length, 3);
  assert.equal(accounts[0].availableCents, 29);
  assert.equal(accounts[1].availableCents, null);
  assert.equal(accounts[2].availableCents, null);
  assert.equal(cents(Infinity), null);
});
test('bank token storage is authenticated encryption', () => {
  const key = randomBytes(32); const value = { items: [{ id: 'item', token: 'private-test-token' }] };
  const sealed = encrypt(value, key);
  assert.ok(!sealed.includes('private-test-token'));
  assert.deepEqual(decrypt(sealed, key), value);
  assert.throws(() => decrypt(sealed, randomBytes(32)));
});
test('unauthorized callers cannot trigger provider calls; linked tokens never leave backend', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'tender-bank-test-'));
  let calls = 0;
  const config = { env: 'sandbox', clientID: 'test', secret: 'test', apiToken: 'a'.repeat(40), key: randomBytes(32), dataFile: path.join(directory, 'links.enc'), user: 'test', redirect: 'https://example.com/plaid/oauth' };
  const server = await createServer(config, async url => {
    calls++;
    return { ok: true, json: async () => url.endsWith('/item/public_token/exchange') ? { item_id: 'test-item', access_token: 'secret-access-token' } : { accounts: [] } };
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(base + '/v1/accounts')).status, 401); assert.equal(calls, 0);
    const response = await fetch(base + '/v1/exchange', { method: 'POST', headers: { Authorization: `Bearer ${config.apiToken}` }, body: JSON.stringify({ publicToken: 'public-sandbox-test' }) });
    const text = await response.text(); assert.equal(response.status, 200); assert.ok(!text.includes('secret-access-token'));
    assert.equal(calls, 1);
  } finally { await new Promise(resolve => server.close(resolve)); await rm(directory, { recursive: true, force: true }); }
});

async function bankHarness(t, provider) {
  const directory = await mkdtemp(path.join(tmpdir(), 'tender-bank-test-'));
  const config = { env: 'sandbox', clientID: 'test', secret: 'test', apiToken: 'a'.repeat(40), key: randomBytes(32), dataFile: path.join(directory, 'links.enc'), user: 'test', redirect: 'https://example.com/plaid/oauth' };
  const calls = [];
  const request = async (url, options) => {
    const endpoint = new URL(url).pathname;
    const body = JSON.parse(options.body);
    calls.push({ endpoint, body });
    const payload = await provider(endpoint, body);
    return { ok: !payload.error_code, json: async () => payload };
  };
  let server = await createServer(config, request);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const api = async (route, method = 'GET', value) => {
    const response = await fetch(`http://127.0.0.1:${server.address().port}${route}`, {
      method, headers: { Authorization: `Bearer ${config.apiToken}`, 'Content-Type': 'application/json' },
      ...(value === undefined ? {} : { body: JSON.stringify(value) }),
    });
    return { status: response.status, body: await response.json() };
  };
  t.after(async () => { await new Promise(resolve => server.close(resolve)); await rm(directory, { recursive: true, force: true }); });
  return {
    api, calls,
    restart: async () => {
      await new Promise(resolve => server.close(resolve));
      server = await createServer(config, request);
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    },
  };
}

test('repair login reuses the saved Item without products or another token exchange', async t => {
  const { api, calls } = await bankHarness(t, async endpoint => endpoint === '/item/public_token/exchange'
    ? { item_id: 'existing-item', access_token: 'secret-existing-token' }
    : { link_token: 'link-sandbox-test' });
  await api('/v1/exchange', 'POST', { publicToken: 'public-sandbox-test', institutionName: 'Example Bank' });
  const connections = await api('/v1/connections');
  assert.deepEqual(connections.body.connections, [{ id: 'existing-item', name: 'Example Bank' }]);
  assert.ok(!JSON.stringify(connections).includes('secret-existing-token'));
  const repaired = await api('/v1/link-token', 'POST', { itemID: 'existing-item' });
  assert.equal(repaired.status, 200);
  assert.equal(calls.at(-1).body.access_token, 'secret-existing-token');
  assert.ok(!('products' in calls.at(-1).body));
  assert.equal(calls.at(-1).body.update.account_selection_enabled, true);
  assert.equal(calls.filter(c => c.endpoint === '/item/public_token/exchange').length, 1);
});

test('unknown connection repairs and malformed bodies never reach Plaid', async t => {
  const { api, calls } = await bankHarness(t, async () => { throw new Error('Unexpected provider call'); });
  assert.equal((await api('/v1/link-token', 'POST', { itemID: 'unknown' })).status, 404);
  assert.equal((await api('/v1/link-token', 'POST', null)).status, 400);
  assert.equal((await api('/v1/link-token', 'POST', [])).status, 400);
  assert.equal((await api('/v1/exchange', 'POST', { publicToken: 'public-production-wrong' })).status, 400);
  assert.equal(calls.length, 0);
});

test('new links request transactions but do not attach an existing access token', async t => {
  const { api, calls } = await bankHarness(t, async () => ({ link_token: 'link-sandbox-new' }));
  assert.equal((await api('/v1/link-token', 'POST')).status, 200);
  assert.deepEqual(calls[0].body.products, ['transactions']);
  assert.deepEqual(calls[0].body.country_codes, ['US']);
  assert.ok(!('access_token' in calls[0].body));
});

test('saved connections survive restart; cached and fresh balances use different endpoints', async t => {
  const { api, calls, restart } = await bankHarness(t, async endpoint => endpoint === '/item/public_token/exchange'
    ? { item_id: 'item', access_token: 'persisted-token' }
    : { accounts: [{ account_id: 'checking', name: 'Checking', type: 'depository', balances: { available: 123.45, current: 140, iso_currency_code: 'USD' } }] });
  await api('/v1/exchange', 'POST', { publicToken: 'public-sandbox-test' });
  await restart();
  assert.equal((await api('/v1/connections')).body.connections.length, 1);
  const cached = await api('/v1/accounts');
  assert.equal(cached.body.cached, true);
  assert.equal(cached.body.accounts[0].availableCents, 12345);
  assert.equal(calls.at(-1).endpoint, '/accounts/get');
  const fresh = await api('/v1/balances/refresh', 'POST');
  assert.equal(fresh.body.cached, false);
  assert.equal(calls.at(-1).endpoint, '/accounts/balance/get');
  const count = calls.length;
  assert.equal((await api('/v1/balances/refresh', 'POST')).status, 429);
  assert.equal(calls.length, count);
});

test('failed disconnects remain available for repair and retry', async t => {
  let allowRemoval = false;
  const { api } = await bankHarness(t, async endpoint => {
    if (endpoint === '/item/public_token/exchange') return { item_id: 'item', access_token: 'token' };
    if (endpoint === '/item/remove') return allowRemoval ? {} : { error_code: 'INTERNAL_SERVER_ERROR' };
    return {};
  });
  await api('/v1/exchange', 'POST', { publicToken: 'public-sandbox-test' });
  assert.equal((await api('/v1/connections', 'DELETE')).status, 502);
  assert.equal((await api('/v1/connections')).body.connections.length, 1);
  allowRemoval = true;
  assert.equal((await api('/v1/connections', 'DELETE')).status, 200);
  assert.equal((await api('/v1/connections')).body.connections.length, 0);
});


test('multiple banks and their accounts survive restart and remain separate', async t => {
  const { api, restart } = await bankHarness(t, async (endpoint, body) => {
    if (endpoint === '/item/public_token/exchange') {
      const id = body.public_token.endsWith('one') ? 'one' : 'two';
      return { item_id: id, access_token: 'private-' + id };
    }
    if (endpoint === '/accounts/get') {
      const bank = body.access_token.endsWith('one') ? 'one' : 'two';
      return { accounts: (bank === 'one' ? ['checking', 'savings'] : ['checking']).map((type, index) => ({
        account_id: bank + '-' + type, name: type, type: 'depository', mask: '1234',
        balances: { available: 10 + index, current: 20, iso_currency_code: 'USD' },
      })) };
    }
    return {};
  });
  await api('/v1/exchange', 'POST', { publicToken: 'public-sandbox-one', institutionName: 'Bank One' });
  await api('/v1/exchange', 'POST', { publicToken: 'public-sandbox-two', institutionName: 'Bank Two' });
  await restart();
  const status = await api('/v1/status');
  assert.equal(status.body.connectionCount, 2);
  const connections = await api('/v1/connections');
  assert.deepEqual(connections.body.connections.map(x => x.name), ['Bank One', 'Bank Two']);
  const accounts = await api('/v1/accounts');
  assert.equal(accounts.body.accounts.length, 3);
  assert.equal(new Set(accounts.body.accounts.map(x => x.id)).size, 3);
  assert.deepEqual(accounts.body.accounts.map(x => x.institutionName), ['Bank One', 'Bank One', 'Bank Two']);
  assert.ok(!JSON.stringify(accounts).includes('private-'));
});


test('one expired bank login does not hide accounts from another bank', async t => {
  const { api } = await bankHarness(t, async (endpoint, body) => {
    if (endpoint === '/item/public_token/exchange') {
      const id = body.public_token.endsWith('expired') ? 'expired' : 'working';
      return { item_id: id, access_token: id };
    }
    if (body.access_token === 'expired') return { error_code: 'ITEM_LOGIN_REQUIRED' };
    return { accounts: [{ account_id: 'working-checking', name: 'Checking', type: 'depository', balances: { available: 10, current: 10, iso_currency_code: 'USD' } }] };
  });
  await api('/v1/exchange', 'POST', { publicToken: 'public-sandbox-expired', institutionName: 'Expired Bank' });
  await api('/v1/exchange', 'POST', { publicToken: 'public-sandbox-working', institutionName: 'Working Bank' });
  const response = await api('/v1/accounts');
  assert.equal(response.status, 200);
  assert.equal(response.body.accounts.length, 1);
  assert.equal(response.body.accounts[0].institutionName, 'Working Bank');
  assert.equal(response.body.errors.length, 1);
  assert.match(response.body.errors[0], /Expired Bank needs login repair/);
});
