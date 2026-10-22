import { syncItem, safeDiagnostic } from './transactions.mjs';
import { randomBytes, createCipheriv, createDecipheriv, timingSafeEqual, randomUUID } from 'node:crypto';

export function cents(value) {
  if (typeof value !== 'number' || !Number.isFinite(value) || Math.abs(value) > 999999999.99) return null;
  return Math.round(value * 100);
}
export function normalizeAccounts(payload, fetchedAt) {
  return (payload.accounts ?? []).filter(a => a.type === 'depository').map(a => ({
    id: a.account_id, name: a.name, mask: a.mask ?? null,
    currency: a.balances.iso_currency_code ?? null,
    availableCents: a.balances.iso_currency_code === 'USD' ? cents(a.balances.available) : null,
    currentCents: a.balances.iso_currency_code === 'USD' ? cents(a.balances.current) : null,
    retrievedAt: fetchedAt,
  }));
}
export function encrypt(value, key) {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(value), 'utf8'), cipher.final()]);
  return JSON.stringify({ version: 1, iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64'), data: ciphertext.toString('base64') });
}
export function decrypt(text, key) {
  const payload = JSON.parse(text);
  if (payload.version !== 1) throw new Error('Unsupported bank storage version');
  const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(payload.iv, 'base64'));
  decipher.setAuthTag(Buffer.from(payload.tag, 'base64'));
  return JSON.parse(Buffer.concat([decipher.update(Buffer.from(payload.data, 'base64')), decipher.final()]));
}
async function body(req) {
  const chunks = []; let length = 0;
  for await (const chunk of (req.body ?? [])) { length += chunk.length; if (length > 32768) throw new Error('Request too large'); chunks.push(chunk); }
  const parsed = JSON.parse(Buffer.concat(chunks).toString() || '{}');
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new SyntaxError('Expected a JSON object');
  return parsed;
}
function authorized(req, token) {
  const supplied = Buffer.from(req.headers.get('authorization') ?? '');
  const expected = Buffer.from(`Bearer ${token}`);
  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
}
export async function createBridge(config, storage, request = fetch) {
  let state = await storage.load() ?? { environment: config.env, items: [], sessions: [] };
  if (state.environment && state.environment !== config.env) throw new Error('Bank storage environment mismatch');
  state.sessions ??= [];
  let busy = false;
  async function persist(next) {
    next = { ...next, environment: config.env };
    await storage.save(next);
    state = next;
  }
  async function plaid(endpoint, values) {
    const response = await request(`https://${config.env}.plaid.com${endpoint}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ client_id: config.clientID, secret: config.secret, ...values }),
      signal: AbortSignal.timeout(30000), redirect: 'manual',
    });
    if (response.status >= 300 && response.status < 400) throw new Error('Provider redirect refused');
    const result = await response.json();
    if (!response.ok || result.error_code) {
      const error = new Error('Bank provider request failed');
      error.providerCode = result.error_code ?? 'PROVIDER_ERROR'; throw error;
    }
    return result;
  }
  return async req => {
    const send = (status, value) => Response.json(value, { status, headers: { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } });
    const route = new URL(req.url).pathname;
    if (req.method === 'GET' && route === '/health') return send(200, { service: 'Tender Bank Bridge', environment: config.env });
    if (req.method === 'GET' && route === '/.well-known/apple-app-site-association') {
      if (!config.team) return send(503, { error: 'Apple signing team not configured' });
      return send(200, { applinks: { details: [{ appIDs: [`${config.team}.${config.bundle}`], components: [{ '/': '/plaid/*' }] }] } });
    }
    if (req.method === 'GET' && route === '/bank-complete') return new Response('<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>Tender · Return to app</title><main style="max-width:34rem;margin:15vh auto;padding:24px;font:18px system-ui;color:#173d30;background:#faf8ee"><h1>Return to Tender</h1><p>Your browser session has ended. Open Tender and tap <strong>Check Connection</strong> to verify the result and review your balances.</p><p>You can close this tab.</p></main>', { headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'", 'Referrer-Policy': 'no-referrer' } });
    if (!authorized(req, config.apiToken)) return send(401, { error: 'Authentication required' });
    if (busy) return send(409, { error: 'A bank request is already running. Try again shortly.' });
    busy = true;
    try {
      if (req.method === 'GET' && route === '/v1/status') return send(200, { environment: config.env, connectionCount: state.items.length, oauthConfigured: config.linkMode === 'browser' || Boolean(config.team && config.redirect), linkMode: config.linkMode ?? 'native' });
      if (req.method === 'POST' && route === '/v1/link-token') {
        if (config.linkMode === 'browser') return send(400, { error: 'Use browser bank connection on this bridge.' });
        const input = await body(req);
        const updating = input.itemID !== undefined;
        const item = updating ? state.items.find(i => i.id === input.itemID) : null;
        if (updating && !item) return send(404, { error: 'Bank connection not found. Reload your connections.' });
        const result = await plaid('/link/token/create', {
          client_name: 'Tender', country_codes: config.countries ?? ['US'], language: 'en',
          user: { client_user_id: config.user }, ...(config.redirect ? { redirect_uri: config.redirect } : {}),
          ...(updating ? { access_token: item.token, update: { account_selection_enabled: true } } : {
            products: ['transactions'],
            account_filters: { depository: { account_subtypes: ['checking', 'savings', 'cash management', 'money market'] } },
          }),
        });
        return send(200, { linkToken: result.link_token, environment: config.env });
      }
      if (req.method === 'GET' && route === '/v1/hosted-link') {
        const session = state.sessions.find(s => !s.done && s.retainUntil > Date.now());
        return send(200, { session: session ? { id: session.id, url: session.url, expiresAt: new Date(session.expires).toISOString() } : null });
      }
      if (req.method === 'POST' && route === '/v1/hosted-link') {
        const input = await body(req);
        const pending = state.sessions.find(s => !s.done && s.expires > Date.now());
        if (pending) {
          if ((input.itemID ?? null) !== pending.itemID) return send(409, { error: 'Finish or resume the existing browser session before starting a different bank connection.' });
          return send(200, { id: pending.id, url: pending.url, expiresAt: new Date(pending.expires).toISOString() });
        }
        const updating = input.itemID !== undefined;
        const item = updating ? state.items.find(i => i.id === input.itemID) : null;
        if (updating && !item) return send(404, { error: 'Bank connection not found. Reload your connections.' });
        const result = await plaid('/link/token/create', {
          client_name: 'Tender', country_codes: config.countries ?? ['US'], language: 'en',
          user: { client_user_id: config.user },
          // This URL opens in the external browser, never an embedded webview.
          // Plaid handles web OAuth; no native associated-domain entitlement needed.
          hosted_link: { is_mobile_app: false, url_lifetime_seconds: 1800,
            completion_redirect_uri: new URL('/bank-complete', config.publicURL).href },
          ...(updating ? { access_token: item.token, update: { account_selection_enabled: true } } : {
            products: ['transactions'],
            account_filters: { depository: { account_subtypes: ['checking', 'savings', 'cash management', 'money market'] } },
          }),
        });
        const url = new URL(result.hosted_link_url);
        if (url.protocol !== 'https:' || url.hostname !== 'secure.plaid.com' || url.username || url.password) throw new Error('Invalid Hosted Link URL');
        const session = { id: randomUUID(), token: result.link_token, url: url.href,
          expires: Date.now() + 1800000, retainUntil: Date.now() + 7 * 3600000,
          itemID: item?.id ?? null, completed: [], done: false };
        await persist({ ...state, sessions: [...state.sessions.filter(s => s.retainUntil > Date.now()).slice(-19), session] });
        return send(200, { id: session.id, url: session.url, expiresAt: new Date(session.expires).toISOString() });
      }
      if (req.method === 'POST' && route === '/v1/hosted-link/finish') {
        const input = await body(req);
        let session = state.sessions.find(s => s.id === input.sessionID);
        if (!session || session.retainUntil < Date.now()) return send(404, { error: 'This browser session expired. Check your existing connections before starting another.' });
        if (session.done) return send(200, { status: 'connected' });
        if (session.exchanging) return send(409, { error: 'A previous token exchange was interrupted. Review the connection in Plaid before starting another; trial slots are not restored.' });
        if (Date.now() - (session.lastChecked ?? 0) < 3000) return send(200, { status: 'pending' });
        const saveSession = async changes => {
          session = { ...session, ...changes };
          await persist({ ...state, sessions: state.sessions.map(s => s.id === session.id ? session : s) });
        };
        await saveSession({ lastChecked: Date.now() });
        const result = await plaid('/link/token/get', { link_token: session.token });
        const flows = result.link_sessions ?? [];
        const diagnostic = safeDiagnostic(flows.at(-1));
        if (session.itemID) {
          if (flows.some(flow => flow.on_success != null)) {
            await saveSession({ done: true, token: null, url: null });
            return send(200, { status: 'connected' });
          }
        } else {
          const additions = flows.flatMap(flow => flow.results?.item_add_results ?? []);
          for (const addition of additions) {
            const publicToken = addition.public_token;
            if (typeof publicToken !== 'string' || !publicToken.startsWith(`public-${config.env}-`)) throw new Error('Invalid provider token');
            if (session.completed.includes(publicToken)) continue;
            // Persist intent before exchanging a one-use token. A crash cannot cause
            // a silent re-exchange or an unreviewed second bank connection.
            await saveSession({ exchanging: true });
            const linked = await plaid('/item/public_token/exchange', { public_token: publicToken });
            const name = typeof addition.institution?.name === 'string' ? addition.institution.name.slice(0, 100) : null;
            const nextSession = { ...session, exchanging: false, completed: [...session.completed, publicToken] };
            try {
              await persist({ ...state, items: [...state.items.filter(i => i.id !== linked.item_id), { ...state.items.find(i => i.id === linked.item_id), id: linked.item_id, token: linked.access_token, name }],
                sessions: state.sessions.map(s => s.id === session.id ? nextSession : s) });
              session = nextSession;
            } catch {
              try { await plaid('/item/remove', { access_token: linked.access_token }); } catch { /* Keep recovery marker. */ }
              throw new Error('Could not save bank link');
            }
          }
          if (session.completed.length) {
            await saveSession({ done: true, token: null, url: null, completed: [] });
            return send(200, { status: 'connected' });
          }
        }
        return send(200, { status: diagnostic.code ? 'failed' : Date.now() > session.expires ? 'expired' : flows.some(f => f.finished_at && (f.exit || f.on_exit)) ? 'cancelled' : 'pending', diagnostic });
      }
      if (req.method === 'GET' && route === '/v1/connections') {
        return send(200, { connections: state.items.map((item, index) => ({ id: item.id, name: item.name || `Bank connection ${index + 1}` })) });
      }
      if (req.method === 'POST' && route === '/v1/exchange') {
        const input = await body(req);
        if (typeof input.publicToken !== 'string' || !input.publicToken.startsWith(`public-${config.env}-`)) return send(400, { error: 'Invalid public token' });
        const result = await plaid('/item/public_token/exchange', { public_token: input.publicToken });
        // Institution names are display labels only, never authorization inputs.
        const name = typeof input.institutionName === 'string' ? input.institutionName.trim().slice(0, 100) : null;
        const next = { ...state, items: [...state.items.filter(i => i.id !== result.item_id), { ...state.items.find(i => i.id === result.item_id), id: result.item_id, token: result.access_token, name }] };
        try { await persist(next); }
        catch { // Do not orphan a live Item that this server cannot later disconnect.
          try { await plaid('/item/remove', { access_token: result.access_token }); } catch { /* Caller sees a recovery error; no secrets are logged. */ }
          return send(500, { error: 'Bank link could not be stored. Review connected apps in Plaid before retrying; trial slots are not restored.' });
        }
        return send(200, { linked: true });
      }
      if ((req.method === 'GET' && route === '/v1/accounts') || (req.method === 'POST' && route === '/v1/balances/refresh')) {
        const fresh = req.method === 'POST';
        if (fresh && Date.now() - (state.lastRefresh ?? 0) < 60000) return send(429, { error: 'Wait one minute before refreshing balances again.' });
        const accounts = []; const errors = [];
        // Independent banks run concurrently so one slow login cannot exhaust the
        // phone's timeout before the other accounts have even been requested.
        const results = await Promise.all(state.items.map(async item => {
          try {
            const result = await plaid(fresh ? '/accounts/balance/get' : '/accounts/get', { access_token: item.token });
            return { accounts: normalizeAccounts(result, new Date().toISOString()).map(account => ({ ...account, institutionName: item.name ?? null })) };
          } catch (error) {
            const label = item.name || 'A bank';
            return { error: error.providerCode === 'ITEM_LOGIN_REQUIRED' ? `${label} needs login repair. Choose Load Existing Connections, then Repair Login. Existing balances have not been changed.` : `${label} could not return balances. Existing balances have not been changed.` };
          }
        }));
        for (const result of results) {
          if (result.accounts) accounts.push(...result.accounts);
          if (result.error) errors.push(result.error);
        }
        if (fresh) await persist({ ...state, lastRefresh: Date.now() });
        return send(200, { accounts, errors, cached: !fresh, environment: config.env });
      }
      if ((req.method === 'GET' && route === '/v1/transactions') || (req.method === 'POST' && route === '/v1/transactions/sync')) {
        const errors = [];
        if (req.method === 'POST' && Date.now() - (state.lastTransactionCheck ?? 0) >= 60000) {
          // Persist throttle before calling Plaid; failures must not cause a hot retry loop.
          await persist({ ...state, lastTransactionCheck: Date.now() });
          const items = await Promise.all(state.items.map(async item => {
            try { return await syncItem(item, config.env, plaid); }
            catch (error) {
              errors.push({ itemID: item.id, message: error.providerCode === 'ITEM_LOGIN_REQUIRED'
                ? 'Bank login needs repair. Previous activity is retained.'
                : 'Bank activity could not update. Previous activity is retained.' });
              return item;
            }
          }));
          await persist({ ...state, items });
        }
        return send(200, { environment: config.env, errors,
          items: state.items.map(i => ({ id: i.id, checkedAt: i.transactionsCheckedAt ?? null,
            transactions: i.transactions ?? [] })) });
      }
      if (req.method === 'DELETE' && route === '/v1/connections') {
        const remaining = [];
        for (const item of state.items) { try { await plaid('/item/remove', { access_token: item.token }); } catch { remaining.push(item); } }
        await persist({ ...state, items: remaining, sessions: [] });
        return send(remaining.length ? 502 : 200, remaining.length ? { error: 'Some bank connections could not be revoked. Try again.' } : { disconnected: true });
      }
      return send(404, { error: 'Not found' });
    } catch (error) {
      // Never log request bodies, auth headers, provider responses, or tokens.
      const badRequest = error instanceof SyntaxError || error.message === 'Request too large';
      return send(badRequest ? 400 : 502, { error: badRequest ? 'Invalid request body.' : error.providerCode === 'INVALID_LINK_CUSTOMIZATION' ? 'Check Plaid Link configuration in the provider dashboard.' : 'The bank service request failed. Check the server configuration and try again.' });
    } finally { busy = false; }
  };
}
