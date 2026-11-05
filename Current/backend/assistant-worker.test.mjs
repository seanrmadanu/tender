import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { randomBytes, createHash } from 'node:crypto';
import { build } from 'esbuild';
import { Miniflare, convertV4MiniflareOptions, Response as WorkerResponse, Log, LogLevel } from 'miniflare';
import { authEnv, jwt, authReply } from './test-auth-helper.mjs';

test('OAuth + native approval + MCP save isolate users, enforce scopes, preserve attribution, and revoke immediately', async () => {
  const bundled = await build({ entryPoints: [path.resolve(import.meta.dirname, 'assistant-worker.mjs')], bundle: true, write: false, format: 'esm', platform: 'browser', target: 'es2022', conditions: ['workerd', 'worker', 'browser'], external: ['node:*', 'cloudflare:*'], logLevel: 'silent' });
  const base = 'https://tender-ai.example';
  const mf = new Miniflare(convertV4MiniflareOptions({
    name: 'tender-ai-test', modules: [{ type: 'ESModule', path: path.resolve(import.meta.dirname, 'assistant-test-bundle.mjs'), contents: bundled.outputFiles[0].text }],
    compatibilityDate: '2026-10-01', compatibilityFlags: ['nodejs_compat', 'global_fetch_strictly_public'], cf: false, telemetry: { enabled: false }, log: new Log(LogLevel.ERROR),
    bindings: { ...authEnv, TENDER_AI_PUBLIC_URL: base, AI_ENCRYPTION_KEY: randomBytes(32).toString('base64'), AI_TEST_DIAGNOSTICS: 'synthetic-only' }, kvNamespaces: ['OAUTH_KV'],
    durableObjects: { AI_LEDGER: { className: 'AssistantLedgerVault', useSQLite: true }, AI_AUTH: { className: 'AssistantAuthorization', useSQLite: true } },
    outboundService: async request => {
      if (new URL(request.url).hostname === 'chatgpt.com') return new WorkerResponse(JSON.stringify({ client_id: request.url, client_name: 'ChatGPT <script>test</script>', redirect_uris: ['https://chatgpt.com/tender-test-callback'], token_endpoint_auth_method: 'none', grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'] }), { headers: { 'Content-Type': 'application/json' } });
      let reply = authReply(request);
      if (new URL(request.url).hostname === 'identitytoolkit.googleapis.com') {
        const input = await request.clone().json();
        const uid = JSON.parse(Buffer.from(input.idToken.split('.')[1], 'base64url')).sub;
        reply = authReply(request, { localId: uid });
      }
      assert.ok(['www.googleapis.com', 'identitytoolkit.googleapis.com'].includes(new URL(request.url).hostname), 'No real AI/bank traffic');
      return new WorkerResponse(JSON.stringify(reply.body), { status: reply.status ?? 200, headers: reply.headers });
    },
  }));
  async function call(route, { uid, method = 'GET', body, headers = {}, status = 200 } = {}) {
    const r = await mf.dispatchFetch(base + route, { method, headers: { ...(uid ? { Authorization: 'Bearer ' + jwt(uid) } : {}), ...(body ? { 'Content-Type': 'application/json' } : {}), ...headers }, ...(body === undefined ? {} : { body: typeof body === 'string' ? body : JSON.stringify(body) }) });
    assert.equal(r.status, status, await r.clone().text()); return r;
  }
  let nextID = 0;
  async function mcp(token, name, args = {}, status = 200) {
    const r = await call('/mcp', { method: 'POST', status, headers: { Authorization: 'Bearer ' + token, Accept: 'application/json, text/event-stream' }, body: { jsonrpc: '2.0', id: ++nextID, method: name === 'list' ? 'tools/list' : 'tools/call', params: name === 'list' ? {} : { name, arguments: args } } });
    const value = await r.json(); return value.result ?? value;
  }
  async function connect(scope = 'ledger.read ledger.write', client = { client_id: 'https://chatgpt.com/oauth/client.json', redirect_uris: ['https://chatgpt.com/tender-test-callback'] }) {
    const verifier = randomBytes(32).toString('base64url'), challenge = createHash('sha256').update(verifier).digest('base64url');
    const query = new URLSearchParams({ client_id: client.client_id, redirect_uri: client.redirect_uris[0], response_type: 'code', scope, resource: base + '/mcp', state: 'test-state', code_challenge: challenge, code_challenge_method: 'S256' });
    const page = await call('/authorize?' + query), html = await page.text();
    assert.equal(html.includes('<script>test</script>'), false);
    const input = JSON.parse(/const args=(.*?);let busy/.exec(html)[1]);
    const cookie = page.headers.getSetCookie().map(c => c.split(';')[0]).join('; ');
    await call('/v3/authorize/' + input.id, { uid: 'bob', method: 'POST', status: 409 });
    await call('/v3/authorize/' + input.id, { uid: 'alice', method: 'POST' });
    await call('/oauth/poll', { method: 'POST', body: input, headers: { Origin: 'https://evil.example', Cookie: cookie }, status: 403 });
    const completed = await (await call('/oauth/poll', { method: 'POST', body: input, headers: { Origin: base, Cookie: cookie } })).json();
    const redirect = new URL(completed.redirectTo); assert.equal(redirect.searchParams.get('state'), 'test-state');
    const form = new URLSearchParams({ grant_type: 'authorization_code', code: redirect.searchParams.get('code'), client_id: client.client_id, redirect_uri: client.redirect_uris[0], code_verifier: verifier, resource: base + '/mcp' });
    const r = await call('/oauth/token', { method: 'POST', body: form.toString(), headers: { 'Content-Type': 'application/x-www-form-urlencoded' } });
    return (await r.json()).access_token;
  }
  try {
    await call('/v3/ledger', { status: 401 });
    await call('/oauth/register', { method: 'POST', body: 'x'.repeat(64001), status: 413 });
    const fixture = JSON.parse(await readFile(new URL('../shared/assistant-funding.json', import.meta.url)));
    const snapshot = await (await call('/v3/ledger', { uid: 'alice', method: 'PUT', body: { expectedRevision: 0, timeZone: fixture.timeZone, ledger: fixture.ledger } })).json();
    assert.equal(snapshot.revision, 1);
    assert.equal((await (await call('/v3/ledger', { uid: 'bob', headers: { 'X-Tender-Verified-Owner': 'alice' } })).json()).ledger, null);
    const token = await connect();
    const list = await mcp(token, 'list'); assert.ok(list.tools.some(t => t.name === 'tender_app_data')); assert.ok(list.tools.some(t => t.name === 'tender_save_settings')); assert.ok(list.tools.some(t => t.name === 'tender_archive_item'));
    assert.equal(list.tools.some(t => /undo|delete|transfer/i.test(t.name)), false);
    const appRead = await mcp(token, 'tender_app_data', { section: 'settings' });
    assert.equal(appRead.isError, undefined); assert.equal(appRead.structuredContent.remindersEnabled, true);
    const initial = (await mcp(token, 'tender_context')).structuredContent;
    const settings = await mcp(token, 'tender_save_settings', { requestID: crypto.randomUUID(), issuedAt: initial.now, expectedRevision: initial.revision, profileName: 'Taylor', remindersEnabled: false });
    assert.equal(settings.structuredContent.status, 'saved');
    const settingsRead = (await mcp(token, 'tender_app_data', { section: 'settings' })).structuredContent;
    assert.equal(settingsRead.profile.name, 'Taylor'); assert.equal(settingsRead.remindersEnabled, false);
    const blocked = await mcp(token, 'tender_save_settings', { requestID: crypto.randomUUID(), issuedAt: initial.now, expectedRevision: settings.structuredContent.revision, bankDetails: { token: 'not-allowed' } });
    assert.equal(blocked.isError, true);
    const context = (await mcp(token, 'tender_context')).structuredContent;
    assert.equal(context.accounts[0].availableCents, 50000); assert.equal(context.funding.available, 30000);
    const request = { requestID: crypto.randomUUID(), issuedAt: context.now, expectedRevision: context.revision, accountID: context.accounts[0].id, categoryID: context.envelopes[0].id, amountCents: 1200, merchant: 'AI lunch', date: context.now, deductFromBalance: false };
    const saved = await mcp(token, 'tender_record_purchase', request);
    assert.equal(saved.structuredContent.status, 'saved'); assert.equal(saved.structuredContent.source, 'chatgpt');
    assert.equal((await mcp(token, 'tender_record_purchase', request)).structuredContent.repeated, true);
    const phone = await (await call('/v3/ledger', { uid: 'alice' })).json();
    assert.equal(phone.ledger.expenses.length, 1); assert.equal(phone.ledger.expenses[0].assistantOrigin.provider, 'chatgpt');
    assert.equal(phone.ledger.accounts[0].available, 50000);
    const forged = await mcp(token, 'tender_record_purchase', { ...request, provider: 'claude' }); assert.equal(forged.isError, true);
    const grants = (await (await call('/v3/connections', { uid: 'alice' })).json()).connections;
    assert.equal(grants.length, 1);
    await call('/v3/connections/' + encodeURIComponent(grants[0].id), { uid: 'bob', method: 'DELETE', status: 404 });
    await call('/v3/connections/' + encodeURIComponent(grants[0].id), { uid: 'alice', method: 'DELETE' });
    assert.equal((await mcp(token, 'tender_context', {}, 401)).error, 'invalid_token');
    const impostor = await (await call('/oauth/register', { method: 'POST', body: { client_name: 'ChatGPT', redirect_uris: ['https://chatgpt.com/tender-test-callback'], token_endpoint_auth_method: 'none', grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'] }, status: 201 })).json();
    const genericToken = await connect('ledger.read ledger.write', impostor);
    const genericContext = (await mcp(genericToken, 'tender_context')).structuredContent;
    const genericSave = await mcp(genericToken, 'tender_record_purchase', { ...request, requestID: crypto.randomUUID(), expectedRevision: genericContext.revision, issuedAt: genericContext.now, date: genericContext.now, merchant: 'Separate dinner', amountCents: 1900 });
    assert.equal(genericSave.structuredContent.source, 'assistant', 'A self-asserted brand and redirect cannot impersonate ChatGPT');
    const readOnly = await connect('ledger.read');
    assert.equal((await mcp(readOnly, 'tender_record_purchase', request)).isError, true);
    assert.equal((await mcp(readOnly, 'tender_save_settings', { requestID: crypto.randomUUID(), issuedAt: request.issuedAt, expectedRevision: 1, profileName: 'Forbidden' })).isError, true);
    assert.equal((await mcp(readOnly, 'tender_app_data', { section: 'settings' })).structuredContent.profile.name, 'Taylor');
    await call('/v3/disconnect', { uid: 'alice', method: 'POST' });
    assert.equal((await mcp(readOnly, 'tender_context')).isError, true);
  } finally { await mf.dispose(); }
});
