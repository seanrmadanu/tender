import http from 'node:http';
import { randomBytes, createCipheriv, createDecipheriv, timingSafeEqual } from 'node:crypto';
import { readFile, writeFile, mkdir, rename } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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
  const ciphertext = Buffer.concat([cipher.update(JSON.stringify(value)), cipher.final()]);
  return JSON.stringify({ version: 1, iv: iv.toString('base64'), tag: cipher.getAuthTag().toString('base64'), data: ciphertext.toString('base64') });
}
export function decrypt(text, key) {
  const payload = JSON.parse(text);
  if (payload.version !== 1) throw new Error('Unsupported bank storage version');
  const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(payload.iv, 'base64'));
  decipher.setAuthTag(Buffer.from(payload.tag, 'base64'));
  return JSON.parse(Buffer.concat([decipher.update(Buffer.from(payload.data, 'base64')), decipher.final()]));
}
function configFromEnv() {
  const env = process.env;
  const config = {
    env: env.PLAID_ENV ?? 'sandbox', countries: (env.PLAID_COUNTRY_CODES ?? 'US').split(',').map(code => code.trim()), clientID: env.PLAID_CLIENT_ID,
    secret: env.PLAID_SECRET, apiToken: env.TENDER_API_TOKEN,
    key: Buffer.from(env.TENDER_ENCRYPTION_KEY ?? '', 'base64'),
    redirect: env.PLAID_REDIRECT_URI,
    user: env.TENDER_USER_ID ?? 'tender-personal',
    dataFile: path.resolve(env.TENDER_DATA_FILE ?? `./data/bank-links-${env.PLAID_ENV ?? 'sandbox'}.enc`),
    team: env.APPLE_TEAM_ID, bundle: env.APPLE_BUNDLE_ID ?? 'com.sean.tender',
  };
  if (!config.countries.length || config.countries.some(code => !['US', 'CA'].includes(code)) || !['sandbox', 'production'].includes(config.env) || !config.clientID || !config.secret || !config.apiToken || config.apiToken.length < 32 || config.key.length !== 32 || !config.redirect?.startsWith('https://')) {
    throw new Error('Configure Plaid keys, HTTPS redirect, a 32+ character API token, and a base64 32-byte encryption key in .env.');
  }
  return config;
}
async function body(req) {
  const chunks = []; let length = 0;
  for await (const chunk of req) { length += chunk.length; if (length > 32768) throw new Error('Request too large'); chunks.push(chunk); }
  const parsed = JSON.parse(Buffer.concat(chunks).toString() || '{}');
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new SyntaxError('Expected a JSON object');
  return parsed;
}
function authorized(req, token) {
  const supplied = Buffer.from(req.headers.authorization ?? '');
  const expected = Buffer.from(`Bearer ${token}`);
  return supplied.length === expected.length && timingSafeEqual(supplied, expected);
}
export async function createServer(config, request = fetch) {
  let state = { environment: config.env, items: [] };
  try {
    state = decrypt(await readFile(config.dataFile, 'utf8'), config.key);
    if (state.environment && state.environment !== config.env) throw new Error('Wrong environment');
  }
  catch (error) { if (error.code !== 'ENOENT') throw new Error('Cannot unlock bank storage. Preserve the existing file and verify the encryption key.'); }
  let busy = false;
  let lastRefresh = 0;
  async function persist(next) {
    next = { ...next, environment: config.env };
    await mkdir(path.dirname(config.dataFile), { recursive: true, mode: 0o700 });
    const temp = `${config.dataFile}.${randomBytes(8).toString('hex')}.tmp`;
    await writeFile(temp, encrypt(next, config.key), { mode: 0o600 });
    await rename(temp, config.dataFile);
    state = next;
  }
  async function plaid(endpoint, values) {
    const response = await request(`https://${config.env}.plaid.com${endpoint}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ client_id: config.clientID, secret: config.secret, ...values }),
      signal: AbortSignal.timeout(30000), redirect: 'error',
    });
    const result = await response.json();
    if (!response.ok || result.error_code) {
      const error = new Error('Bank provider request failed');
      error.providerCode = result.error_code ?? 'PROVIDER_ERROR'; throw error;
    }
    return result;
  }
  const server = http.createServer(async (req, res) => {
    const send = (status, value) => { res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' }); res.end(JSON.stringify(value)); };
    const route = new URL(req.url, 'http://localhost').pathname;
    if (req.method === 'GET' && route === '/health') return send(200, { service: 'Tender Bank Bridge', environment: config.env });
    if (req.method === 'GET' && route === '/.well-known/apple-app-site-association') {
      if (!config.team) return send(503, { error: 'Apple signing team not configured' });
      return send(200, { applinks: { details: [{ appIDs: [`${config.team}.${config.bundle}`], components: [{ '/': '/plaid/*' }] }] } });
    }
    if (!authorized(req, config.apiToken)) return send(401, { error: 'Authentication required' });
    if (busy) return send(409, { error: 'A bank request is already running. Try again shortly.' });
    busy = true;
    try {
      if (req.method === 'GET' && route === '/v1/status') return send(200, { environment: config.env, connectionCount: state.items.length, oauthConfigured: Boolean(config.team && config.redirect) });
      if (req.method === 'POST' && route === '/v1/link-token') {
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
      if (req.method === 'GET' && route === '/v1/connections') {
        return send(200, { connections: state.items.map((item, index) => ({ id: item.id, name: item.name || `Bank connection ${index + 1}` })) });
      }
      if (req.method === 'POST' && route === '/v1/exchange') {
        const input = await body(req);
        if (typeof input.publicToken !== 'string' || !input.publicToken.startsWith(`public-${config.env}-`)) return send(400, { error: 'Invalid public token' });
        const result = await plaid('/item/public_token/exchange', { public_token: input.publicToken });
        // Institution names are display labels only, never authorization inputs.
        const name = typeof input.institutionName === 'string' ? input.institutionName.trim().slice(0, 100) : null;
        const next = { items: [...state.items.filter(i => i.id !== result.item_id), { id: result.item_id, token: result.access_token, name }] };
        try { await persist(next); }
        catch { // Do not orphan a live Item that this server cannot later disconnect.
          try { await plaid('/item/remove', { access_token: result.access_token }); } catch { /* Caller sees a recovery error; no secrets are logged. */ }
          return send(500, { error: 'Bank link could not be stored. Review connected apps in Plaid before retrying; trial slots are not restored.' });
        }
        return send(200, { linked: true });
      }
      if ((req.method === 'GET' && route === '/v1/accounts') || (req.method === 'POST' && route === '/v1/balances/refresh')) {
        const fresh = req.method === 'POST';
        if (fresh && Date.now() - lastRefresh < 60000) return send(429, { error: 'Wait one minute before refreshing balances again.' });
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
        if (fresh) lastRefresh = Date.now();
        return send(200, { accounts, errors, cached: !fresh, environment: config.env });
      }
      if (req.method === 'DELETE' && route === '/v1/connections') {
        const remaining = [];
        for (const item of state.items) { try { await plaid('/item/remove', { access_token: item.token }); } catch { remaining.push(item); } }
        await persist({ items: remaining });
        return send(remaining.length ? 502 : 200, remaining.length ? { error: 'Some bank connections could not be revoked. Try again.' } : { disconnected: true });
      }
      send(404, { error: 'Not found' });
    } catch (error) {
      // Never log request bodies, auth headers, provider responses, or tokens.
      const badRequest = error instanceof SyntaxError || error.message === 'Request too large';
      send(badRequest ? 400 : 502, { error: badRequest ? 'Invalid request body.' : error.providerCode === 'INVALID_LINK_CUSTOMIZATION' ? 'Check Plaid Link configuration in the provider dashboard.' : 'The bank service request failed. Check the server configuration and try again.' });
    } finally { busy = false; }
  });
  server.requestTimeout = 35000;
  server.headersTimeout = 10000;
  return server;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const server = await createServer(configFromEnv());
    server.listen(Number(process.env.PORT ?? 8787), process.env.TENDER_HOST ?? '127.0.0.1', () => console.log('Tender bank bridge ready. Personal-use authenticated API; place behind HTTPS for an iPhone.'));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
