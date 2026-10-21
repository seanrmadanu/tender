import test from 'node:test';
import assert from 'node:assert/strict';
import { randomBytes } from 'node:crypto';
import { createBridge, encrypt, decrypt } from './bridge.mjs';
import { configFromEnv } from './config.mjs';

async function harness(provider, initial, failSave = () => false) {
  const config = { env: 'production', clientID: 'test-id', secret: 'test-secret', apiToken: 'a'.repeat(40), key: randomBytes(32), user: 'personal', linkMode: 'browser', publicURL: 'https://tender.example' };
  let sealed = initial ? encrypt(initial, config.key) : null;
  const calls = [];
  const storage = {
    async load() { return sealed ? decrypt(sealed, config.key) : null; },
    async save(value) { if (failSave(value)) throw new Error('disk full'); sealed = encrypt(value, config.key); },
  };
  const fetcher = async (url, options) => {
    assert.equal(new URL(url).origin, 'https://production.plaid.com');
    assert.equal(options.redirect, 'manual');
    const endpoint = new URL(url).pathname; const body = JSON.parse(options.body);
    calls.push({ endpoint, body });
    const data = await provider(endpoint, body);
    return { ok: !data.error_code, json: async () => data };
  };
  let handler = await createBridge(config, storage, fetcher);
  return {
    calls, config,
    read: () => decrypt(sealed, config.key),
    restart: async () => { handler = await createBridge(config, storage, fetcher); },
    api: async (route, method = 'GET', value, token = config.apiToken) => {
      const response = await handler(new Request('https://tender.example' + route, { method, headers: { Authorization: `Bearer ${token}` }, ...(value === undefined ? {} : { body: JSON.stringify(value) }) }));
      return { status: response.status, body: await response.json() };
    },
  };
}
const creation = { link_token: 'link-production-private', hosted_link_url: 'https://secure.plaid.com/hl/private-test' };
const success = { link_sessions: [{ finished_at: '2026-10-21T12:00:00Z', results: { item_add_results: [{ public_token: 'public-production-once', institution: { name: 'My Bank' } }] } }] };
const exchange = { item_id: 'my-bank-item', access_token: 'access-production-private' };
const provider = async endpoint => endpoint === '/link/token/create' ? creation : endpoint === '/link/token/get' ? success : endpoint === '/item/public_token/exchange' ? exchange : {};

test('browser setup does not require a paid Apple native redirect', () => {
  const config = configFromEnv({ PLAID_ENV: 'production', PLAID_CLIENT_ID: 'test', PLAID_SECRET: 'test', TENDER_API_TOKEN: 'a'.repeat(40), TENDER_ENCRYPTION_KEY: randomBytes(32).toString('base64'), TENDER_LINK_MODE: 'browser', TENDER_PUBLIC_URL: 'https://tender.example' });
  assert.equal(config.redirect, undefined);
  assert.equal(config.linkMode, 'browser');
});
test('hosted sessions are authenticated, reused and restored after restart', async () => {
  const h = await harness(provider);
  assert.equal((await h.api('/v1/hosted-link', 'POST', {}, 'bad')).status, 401);
  assert.equal(h.calls.length, 0);
  const started = await h.api('/v1/hosted-link', 'POST', {});
  assert.equal(started.status, 200);
  assert.ok(!JSON.stringify(started).includes('link-production-private'));
  assert.equal(h.calls[0].body.hosted_link.is_mobile_app, false);
  assert.equal(h.calls[0].body.hosted_link.completion_redirect_uri, 'https://tender.example/bank-complete');
  assert.ok(!('redirect_uri' in h.calls[0].body));
  assert.ok(!('delivery_method' in h.calls[0].body.hosted_link));
  assert.equal((await h.api('/v1/hosted-link', 'POST', {})).body.id, started.body.id);
  await h.restart();
  assert.equal((await h.api('/v1/hosted-link')).body.session.id, started.body.id);
  assert.equal(h.calls.length, 1);
});
test('finishing uses stored session ownership and exchanges exactly once across restarts', async () => {
  const h = await harness(provider);
  const started = await h.api('/v1/hosted-link', 'POST', {});
  assert.equal((await h.api('/v1/hosted-link/finish', 'POST', { sessionID: 'unowned' })).status, 404);
  const finished = await h.api('/v1/hosted-link/finish', 'POST', { sessionID: started.body.id });
  assert.deepEqual(finished.body, { status: 'connected' });
  assert.equal(h.read().items[0].token, exchange.access_token);
  await h.restart();
  assert.equal((await h.api('/v1/hosted-link/finish', 'POST', { sessionID: started.body.id })).body.status, 'connected');
  assert.equal(h.calls.filter(c => c.endpoint === '/item/public_token/exchange').length, 1);
  assert.deepEqual((await h.api('/v1/connections')).body.connections, [{ id: 'my-bank-item', name: 'My Bank' }]);
  assert.equal((await h.api('/v1/hosted-link')).body.session, null);
});
test('redirect or unfinished flow alone does not create a linked bank', async () => {
  const h = await harness(async endpoint => endpoint === '/link/token/create' ? creation : { link_sessions: [] });
  const started = await h.api('/v1/hosted-link', 'POST', {});
  assert.equal((await h.api('/v1/hosted-link/finish', 'POST', { sessionID: started.body.id })).body.status, 'pending');
  assert.equal(h.read().items.length, 0);
  assert.equal(h.calls.filter(c => c.endpoint === '/item/public_token/exchange').length, 0);
});
test('browser repair uses original item and never exchanges update-mode tokens', async () => {
  const h = await harness(async endpoint => endpoint === '/link/token/create' ? creation : { link_sessions: [{ on_success: { public_token: 'ignored-update-token' } }] }, { environment: 'production', items: [{ id: 'existing', token: 'saved-private', name: 'My Bank' }], sessions: [] });
  const started = await h.api('/v1/hosted-link', 'POST', { itemID: 'existing' });
  assert.equal(h.calls[0].body.access_token, 'saved-private');
  assert.equal(h.calls[0].body.update.account_selection_enabled, true);
  assert.ok(!('products' in h.calls[0].body));
  assert.equal((await h.api('/v1/hosted-link/finish', 'POST', { sessionID: started.body.id })).body.status, 'connected');
  assert.equal(h.read().items.length, 1);
  assert.equal(h.calls.filter(c => c.endpoint === '/item/public_token/exchange').length, 0);
});
test('failed storage after exchange revokes new item and stops unsafe retries', async () => {
  const h = await harness(provider, null, state => state.items.length > 0);
  const started = await h.api('/v1/hosted-link', 'POST', {});
  assert.equal((await h.api('/v1/hosted-link/finish', 'POST', { sessionID: started.body.id })).status, 502);
  assert.ok(h.calls.some(c => c.endpoint === '/item/remove'));
  await h.restart();
  assert.equal((await h.api('/v1/hosted-link/finish', 'POST', { sessionID: started.body.id })).status, 409);
  assert.equal(h.calls.filter(c => c.endpoint === '/item/public_token/exchange').length, 1);
});
test('untrusted hosted URLs and environment-mismatched storage fail closed', async () => {
  const h = await harness(async () => ({ ...creation, hosted_link_url: 'https://evil.example/login' }));
  assert.equal((await h.api('/v1/hosted-link', 'POST', {})).status, 502);
  await assert.rejects(harness(provider, { environment: 'sandbox', items: [] }), /environment/);
});
test('fresh balance throttling survives a process restart', async () => {
  const h = await harness(provider);
  assert.equal((await h.api('/v1/balances/refresh', 'POST')).status, 200);
  await h.restart();
  assert.equal((await h.api('/v1/balances/refresh', 'POST')).status, 429);
});
