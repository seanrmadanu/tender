import OAuthProvider, { AuthorizationError } from '@cloudflare/workers-oauth-provider';
import { randomBytes, createHash } from 'node:crypto';
import { createFirebaseVerifier, AuthError } from './firebase-auth.mjs';
import { encryptedLedgerStorage } from './assistant-storage.mjs';
import { newCloudState, publishLedger, applyAssistantChange, assistantContext, findPurchases, readAppSection, wipeCloudBankRecords, LedgerFault } from './assistant-ledger.mjs';
import { handleMcp } from './assistant-mcp.mjs';

const verifyFirebase = createFirebaseVerifier();
const scopes = ['ledger.read', 'ledger.write'];
const authorizationScopes = [...scopes, 'offline_access'];
const json = (body, status = 200) => Response.json(body, { status, headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } });
const ticketPattern = /^[a-f0-9]{64}$/;
const ownerPattern = /^[a-f0-9]{64}$/;
const digest = value => createHash('sha256').update(value).digest('hex');
const escape = value => String(value).replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);
async function boundedRequest(request, limit) {
  if (!request.body) return request;
  if (Number(request.headers.get('content-length')) > limit) throw new LedgerFault('Request is too large.', 413);
  const reader = request.body.getReader(), chunks = []; let count = 0;
  while (true) { const part = await reader.read(); if (part.done) break; count += part.value.length; if (count > limit) { await reader.cancel(); throw new LedgerFault('Request is too large.', 413); } chunks.push(part.value); }
  return new Request(request, { body: Buffer.concat(chunks) });
}
async function body(request, limit = 9_000_000) {
  if (Number(request.headers.get('content-length')) > limit) throw new LedgerFault('Request is too large.', 413);
  if (!request.body) return {};
  const reader = request.body.getReader(), chunks = []; let count = 0;
  while (true) { const part = await reader.read(); if (part.done) break; count += part.value.length; if (count > limit) { await reader.cancel(); throw new LedgerFault('Request is too large.', 413); } chunks.push(part.value); }
  try { return JSON.parse(Buffer.concat(chunks).toString()); } catch { throw new LedgerFault('Invalid JSON.'); }
}
async function ledgerCall(env, owner, operation, value = {}) {
  return env.AI_LEDGER.get(env.AI_LEDGER.idFromName(owner)).fetch('https://ledger.internal/' + operation, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Tender-Verified-Owner': owner }, body: JSON.stringify(value) });
}
async function ticketCall(env, id, operation, value = {}) {
  return env.AI_AUTH.get(env.AI_AUTH.idFromName(id)).fetch('https://approval.internal/' + operation, { method: 'POST', body: JSON.stringify(value) });
}
export class AssistantLedgerVault {
  constructor(ctx, env) { this.ctx = ctx; this.env = env; }
  async fetch(request) {
    return this.ctx.blockConcurrencyWhile(async () => {
      const owner = request.headers.get('X-Tender-Verified-Owner');
      if (!ownerPattern.test(owner ?? '')) return json({ error: 'Authentication required.' }, 401);
      try {
        const storage = encryptedLedgerStorage(this.ctx.storage, this.env.AI_ENCRYPTION_KEY, owner);
        const state = await storage.load() ?? newCloudState(owner);
        if (state.owner !== owner) return json({ error: 'Account mismatch.' }, 403);
        const data = await body(request), route = new URL(request.url).pathname;
        const result = () => ({ revision: state.revision, epoch: state.epoch, connected: state.connected, ledger: state.ledger, events: state.events });
        if (route === '/snapshot') return json(result());
        if (route === '/connections') return json({ connections: state.connected ? Object.entries(state.connections ?? {}).filter(([, c]) => !c.revoked && c.expires > Date.now()).map(([id, c]) => ({ id, provider: c.provider })) : [] });
        if (route === '/grant') {
          if (!state.connected || !ticketPattern.test(data.connectionID ?? '') || !['chatgpt', 'claude', 'assistant'].includes(data.provider)) return json({ error: 'Cloud connection is unavailable.' }, 403);
          state.connections ??= {}; state.connections[data.connectionID] ??= { provider: data.provider, expires: Date.now() + 30 * 86400000, revoked: false };
          await storage.save(state); return json({ epoch: state.epoch });
        }
        if (route === '/revoke') {
          if (state.connections?.[data.connectionID]) state.connections[data.connectionID].revoked = true;
          await storage.save(state); return json({ disconnected: true });
        }
        if (route === '/publish') { publishLedger(state, data); await storage.save(state); return json(result()); }
        if (route === '/wipe-bank') { wipeCloudBankRecords(state); await storage.save(state); return json(result()); }
        if (route === '/disconnect' || route === '/erase') {
          state.connected = false; state.epoch++; state.revision++;
          state.connections = {};
          if (route === '/erase') { state.ledger = null; state.events = []; state.requests = {}; }
          await storage.save(state); return json(result());
        }
        const connection = state.connections?.[data.connectionID];
        if (!state.connected || data.epoch !== state.epoch || !connection || connection.revoked || connection.provider !== data.source || connection.expires <= Date.now()) return json({ error: 'This connection was disconnected or expired. Reconnect in Tender.' }, 403);
        if (route === '/context') return json(assistantContext(state));
        if (route === '/find') return json(findPurchases(state, data.query));
        if (route === '/app') return json(readAppSection(state, data.query));
        if (route === '/change') { const response = applyAssistantChange(state, data.command, data.source); await storage.save(state); return json(response); }
        return json({ error: 'Unknown ledger operation.' }, 404);
      } catch (error) {
        if (this.env.AI_TEST_DIAGNOSTICS === 'synthetic-only' && !(error instanceof LedgerFault)) throw error;
        return json({ error: error instanceof LedgerFault ? error.message : 'Cloud ledger is unavailable. Saved information is preserved.' }, error instanceof LedgerFault ? error.status : 503);
      }
    });
  }
}
export class AssistantAuthorization {
  constructor(ctx) { this.ctx = ctx; }
  async fetch(request) {
    return this.ctx.blockConcurrencyWhile(async () => {
      const data = await body(request, 32000), route = new URL(request.url).pathname;
      if (route === '/limit') {
        const hour = Math.floor(Date.now() / 3600000), current = await this.ctx.storage.get('limit');
        const count = current?.hour === hour ? current.count : 0;
        if (count >= 100) return json({ error: 'Try connecting later.' }, 429);
        await this.ctx.storage.put('limit', { hour, count: count + 1 }); await this.ctx.storage.setAlarm(Date.now() + 3600000); return json({ ok: true });
      }
      if (route === '/create') {
        if (await this.ctx.storage.get('request')) return json({ error: 'Request already exists.' }, 409);
        await this.ctx.storage.put('request', data); await this.ctx.storage.setAlarm(data.expires); return json({ ok: true });
      }
      const saved = await this.ctx.storage.get('request');
      if (!saved || saved.expires < Date.now()) return json({ error: 'Connection request expired. Start again in the AI app.' }, 410);
      if (route === '/describe') return json({ id: saved.id, provider: saved.provider, clientName: saved.details.clientName, clientDomain: saved.details.clientDomain ?? null, redirectHost: saved.details.redirectHost, scopes: saved.scope, expiresAt: new Date(saved.expires).toISOString(), approved: Boolean(saved.owner) });
      if (route === '/approve') {
        if (saved.owner && saved.owner !== data.owner) return json({ error: 'Request was already approved.' }, 409);
        saved.owner = data.owner; saved.epoch = data.epoch; saved.connectionID = data.connectionID;
        await this.ctx.storage.put('request', saved); return json({ approved: true });
      }
      if (route === '/poll' || route === '/take') {
        if (digest(String(data.proof ?? '')) !== saved.proofHash) return json({ error: 'Invalid browser session.' }, 403);
        if (!saved.owner) return json({ status: 'pending' }, 202);
        if (saved.used) return json({ error: 'Connection request was already used.' }, 410);
        if (route === '/take') { saved.used = true; await this.ctx.storage.put('request', saved); }
        return json({ status: 'approved', owner: saved.owner, epoch: saved.epoch, provider: saved.provider, connectionID: saved.connectionID, scope: saved.scope });
      }
      return json({ error: 'Unknown authorization operation.' }, 404);
    });
  }
  async alarm() { await this.ctx.storage.deleteAll(); }
}
function providerFor(request) {
  // Never trust a registered client's self-asserted name or a tool argument.
  // DCR clients can claim somebody else's redirect address. Brand attribution
  // requires a provider-hosted Client ID Metadata Document validated by OAuth.
  let identity;
  try { identity = new URL(request.clientId); } catch { return 'assistant'; }
  if (identity.protocol !== 'https:') return 'assistant';
  const host = identity.hostname;
  if (['chatgpt.com', 'chat.openai.com'].includes(host)) return 'chatgpt';
  if (host === 'claude.ai') return 'claude';
  return 'assistant';
}
function consentHTML(details, id, proof, handle, nonce) {
  const native = 'tender://ai-connect?request=' + id;
  return `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Connect Tender</title>
  <style nonce="${nonce}">body{font:17px system-ui;background:#f5f3e9;color:#173f35;max-width:540px;margin:8vh auto;padding:24px}main{background:#fffdf5;border:1px solid #c9cdbc;border-radius:24px;padding:28px}a,button{display:inline-block;border:0;border-radius:12px;padding:14px;background:#173f35;color:white;font:inherit;text-decoration:none;cursor:pointer}code{display:block;overflow-wrap:anywhere;padding:14px;background:#f5f3e9;font-size:13px}p{line-height:1.5}small{color:#59685b}</style>
  <main><h1>Connect Tender</h1><p><strong>${escape(details.clientName)}</strong> wants to ${details.scope.includes('ledger.write') ? 'read and update' : 'read'} your Tender ledger.</p>
  <p>Access returns to <strong>${escape(details.redirectHost)}</strong>.</p>${details.clientDomain ? `<p>Published identity: ${escape(details.clientDomain)}</p>` : '<p><small>The client name is self-reported. Check the return address above.</small></p>'}
  <p>Open Tender on your iPhone to review this connection and approve sharing. Changes save immediately and carry a source badge. You can edit or delete them in Tender.</p>
  <a href="${native}">Open Tender</a><p>Connecting from a computer? Copy this connection code into Settings → AI Connections on your iPhone:</p><code>${id}</code>
  <p id="status">Waiting for your approval in Tender…</p><button id="continue">Continue after approving</button><form action="/oauth/deny" method="post"><input type="hidden" name="handle" value="${escape(handle)}"><button>Cancel</button></form></main>
  <script nonce="${nonce}">const args=${JSON.stringify({ id, proof, handle }).replace(/</g, '\\u003c')};let busy=false;async function poll(){if(busy)return;busy=true;try{const r=await fetch('/oauth/poll',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(args)});const d=await r.json();if(d.redirectTo){location.replace(d.redirectTo);return}if(!r.ok&&r.status!==202){document.getElementById('status').textContent=d.error||'Start this connection again.';clearInterval(timer)}}catch{document.getElementById('status').textContent='Connection interrupted. Press Continue to retry.'}finally{busy=false}}document.getElementById('continue').onclick=poll;const timer=setInterval(poll,2500);</script></html>`;
}
async function firebaseOwner(request, env) {
  const value = request.headers.get('Authorization') ?? '';
  if (!value.startsWith('Bearer ')) throw new AuthError();
  return verifyFirebase(value.slice(7), env);
}
function makeProvider(base) {
  return new OAuthProvider({
    apiRoute: '/mcp', apiHandler: { fetch: handleMcp }, authorizeEndpoint: '/authorize', tokenEndpoint: '/oauth/token', clientRegistrationEndpoint: '/oauth/register',
    accessTokenTTL: 900, refreshTokenTTL: 86400 * 30, clientRegistrationTTL: 86400 * 30,
    clientIdMetadataDocumentEnabled: true, scopesSupported: authorizationScopes, requiredScopes: scopes,
    resourceMetadata: { resource: base + '/mcp', authorization_servers: [base], resource_name: 'Tender' },
    defaultHandler: {
      async fetch(request, env) {
        const url = new URL(request.url), path = url.pathname;
        if (path === '/authorize' && request.method === 'GET') {
          try {
            const parsed = await env.OAUTH_PROVIDER.parseAuthRequest(request);
            if (!parsed.scope.includes('ledger.read') || parsed.scope.some(s => !authorizationScopes.includes(s))) return json({ error: 'Choose ledger.read and optionally ledger.write.' }, 400);
            const details = await env.OAUTH_PROVIDER.describeConsent(parsed), consent = await env.OAUTH_PROVIDER.beginConsent(parsed);
            const id = randomBytes(32).toString('hex'), proof = randomBytes(32).toString('hex'), nonce = randomBytes(24).toString('base64');
            await ticketCall(env, id, 'create', { id, proofHash: digest(proof), details, provider: providerFor(parsed), scope: parsed.scope, expires: Date.now() + 600000 });
            const headers = consent.headers;
            headers.set('Content-Type', 'text/html; charset=utf-8'); headers.set('Referrer-Policy', 'no-referrer'); headers.set('Cache-Control', 'no-store');
            headers.set('Content-Security-Policy', `default-src 'none'; style-src 'nonce-${nonce}'; script-src 'nonce-${nonce}'; connect-src 'self'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'`);
            return new Response(consentHTML(details, id, proof, consent.handle, nonce), { headers });
          } catch (error) { return json({ error: error instanceof AuthorizationError ? error.description : 'Could not verify this connection request. Start again from your AI app.' }, 400); }
        }
        if (path === '/oauth/poll' && request.method === 'POST') {
          if (request.headers.get('Origin') !== base) return json({ error: 'Open the original sign-in page.' }, 403);
          const input = await body(request, 16000);
          if (!ticketPattern.test(input.id ?? '')) return json({ error: 'Invalid connection code.' }, 400);
          const pending = await ticketCall(env, input.id, 'poll', { proof: input.proof });
          if (pending.status !== 200) return pending;
          const value = await pending.json();
          try {
            const consent = await env.OAUTH_PROVIDER.approveConsent(request, input.handle, { scope: value.scope });
            const taken = await ticketCall(env, input.id, 'take', { proof: input.proof });
            if (!taken.ok) return taken;
            const { redirectTo } = await env.OAUTH_PROVIDER.completeAuthorization({ request: consent.request, userId: value.owner, scope: value.scope, metadata: { provider: value.provider, epoch: value.epoch, connectionID: value.connectionID }, props: { owner: value.owner, epoch: value.epoch, provider: value.provider, connectionID: value.connectionID } });
            consent.headers.set('Content-Type', 'application/json'); consent.headers.set('Cache-Control', 'no-store');
            return new Response(JSON.stringify({ redirectTo }), { headers: consent.headers });
          } catch { return json({ error: 'This sign-in window expired or was already used. Start again.' }, 400); }
        }
        if (path === '/oauth/deny' && request.method === 'POST') {
          if (request.headers.get('Origin') !== base) return json({ error: 'Open the original sign-in page.' }, 403);
          try { const form = await request.formData(); const denied = await env.OAUTH_PROVIDER.denyConsent(request, String(form.get('handle'))); return new Response(null, { status: 302, headers: denied.headers }); }
          catch { return json({ error: 'Connection request expired.' }, 400); }
        }
        if (path.startsWith('/v3/')) {
          let owner;
          try { owner = await firebaseOwner(request, env); } catch (error) { return json({ error: error instanceof AuthError ? 'Sign in again to connect Tender.' : 'Account verification is unavailable.' }, error instanceof AuthError ? 401 : 503); }
          if (path === '/v3/ledger' && request.method === 'GET') return ledgerCall(env, owner, 'snapshot');
          if (path === '/v3/ledger' && request.method === 'PUT') return ledgerCall(env, owner, 'publish', await body(request));
          if (path === '/v3/disconnect' && request.method === 'POST') return ledgerCall(env, owner, 'disconnect');
          if (path === '/v3/wipe-bank' && request.method === 'POST') return ledgerCall(env, owner, 'wipe-bank');
          if (path === '/v3/ledger' && request.method === 'DELETE') return ledgerCall(env, owner, 'erase');
          if (path === '/v3/connections' && request.method === 'GET') {
            const grants = await env.OAUTH_PROVIDER.listUserGrants(owner);
            const active = (await (await ledgerCall(env, owner, 'connections')).json()).connections;
            return json({ connections: grants.items.filter(g => active.some(c => c.id === g.metadata?.connectionID)).map(g => ({ id: g.id, provider: g.metadata?.provider ?? 'assistant', scopes: g.scope })) });
          }
          if (path.startsWith('/v3/connections/') && request.method === 'DELETE') {
            const id = decodeURIComponent(path.slice('/v3/connections/'.length));
            const grants = await env.OAUTH_PROVIDER.listUserGrants(owner);
            const grant = grants.items.find(g => g.id === id);
            if (!grant) return json({ error: 'Connection not found.' }, 404);
            await ledgerCall(env, owner, 'revoke', { connectionID: grant.metadata?.connectionID });
            await env.OAUTH_PROVIDER.revokeGrant(id, owner); return json({ disconnected: true });
          }
          if (path.startsWith('/v3/authorize/')) {
            const id = path.slice('/v3/authorize/'.length);
            if (!ticketPattern.test(id)) return json({ error: 'Invalid connection code.' }, 400);
            if (request.method === 'GET') return ticketCall(env, id, 'describe');
            if (request.method === 'POST') {
              const snapshot = await (await ledgerCall(env, owner, 'snapshot')).json();
              if (!snapshot.connected) return json({ error: 'Enable cloud connections in Tender first.' }, 409);
              const info = await ticketCall(env, id, 'describe');
              if (!info.ok) return info;
              const details = await info.json();
              const granted = await ledgerCall(env, owner, 'grant', { connectionID: id, provider: details.provider });
              if (!granted.ok) return granted;
              return ticketCall(env, id, 'approve', { owner, epoch: snapshot.epoch, connectionID: id });
            }
          }
          return json({ error: 'Unknown account operation.' }, 404);
        }
        return json({ error: 'Authentication required.' }, 401);
      },
    },
  });
}
const providers = new Map();
export default {
  async fetch(request, env, ctx) {
    const configured = Boolean(env.AI_ENCRYPTION_KEY && env.AI_LEDGER && env.AI_AUTH && env.OAUTH_KV && env.FIREBASE_PROJECT_ID && env.FIREBASE_API_KEY && env.TENDER_AI_PUBLIC_URL);
    const path = new URL(request.url).pathname;
    if (path === '/health') return json({ service: 'Tender AI Connections', configured, version: 1 });
    if (!configured) return json({ error: 'AI Connections setup is not complete yet.' }, 503);
    const base = env.TENDER_AI_PUBLIC_URL;
    if (new URL(request.url).origin !== base) return json({ error: 'Use the configured Tender connection address.' }, 400);
    if (['/authorize', '/oauth/register', '/oauth/token'].includes(path)) {
      const ip = request.headers.get('CF-Connecting-IP') ?? 'unavailable';
      const limited = await ticketCall(env, 'rate-' + digest(ip), 'limit');
      if (!limited.ok) return limited;
    }
    try {
      if (request.method === 'POST' && !path.startsWith('/v3/')) request = await boundedRequest(request, 64000);
      if (!providers.has(base)) providers.set(base, makeProvider(base));
      return await providers.get(base).fetch(request, env, ctx);
    } catch (error) {
      if (env.AI_TEST_DIAGNOSTICS === 'synthetic-only' && !(error instanceof LedgerFault)) throw error;
      return json({ error: error instanceof LedgerFault ? error.message : 'Tender connection is temporarily unavailable. Try again.' }, error instanceof LedgerFault ? error.status : 503);
    }
  },
};
