import { createHash, verify, X509Certificate } from 'node:crypto';

const certificatesURL = 'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';
export class AuthError extends Error {}
export class AuthUnavailable extends Error {}
// Only public signing certificates are cached. Account status is checked on every
// request so deletion, disablement, and session revocation fail closed.
export function createFirebaseVerifier(request = fetch, now = () => Date.now()) {
  let certificates = {}; let expires = 0; let pending;
  async function loadCertificates() {
    if (now() < expires) return certificates;
    pending ??= (async () => {
      const response = await request(certificatesURL, { redirect: 'manual', signal: AbortSignal.timeout(10000) });
      if (!response.ok) throw new AuthUnavailable();
      const result = await response.json();
      if (!result || typeof result !== 'object' || Array.isArray(result)) throw new AuthUnavailable();
      const maxAge = Number(/max-age=(\d+)/.exec(response.headers.get('cache-control') ?? '')?.[1] ?? 0);
      certificates = result; expires = now() + Math.min(maxAge, 21600) * 1000;
      return certificates;
    })();
    try { return await pending; } finally { pending = null; }
  }
  return async (token, env) => {
    if (!env.FIREBASE_PROJECT_ID || !env.FIREBASE_API_KEY) throw new AuthUnavailable();
    let header, claims, parts;
    try {
      if (typeof token !== 'string' || token.length > 16384) throw new Error();
      parts = token.split('.');
      if (parts.length !== 3 || parts.some(p => !/^[A-Za-z0-9_-]+$/.test(p))) throw new Error();
      header = JSON.parse(Buffer.from(parts[0], 'base64url'));
      claims = JSON.parse(Buffer.from(parts[1], 'base64url'));
      const seconds = Math.floor(now() / 1000);
      if (header.alg !== 'RS256' || typeof header.kid !== 'string' || header.crit !== undefined ||
          claims.aud !== env.FIREBASE_PROJECT_ID || claims.iss !== `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}` ||
          typeof claims.sub !== 'string' || !claims.sub.length || claims.sub.length > 128 ||
          !Number.isInteger(claims.exp) || claims.exp <= seconds ||
          !Number.isInteger(claims.iat) || claims.iat > seconds ||
          !Number.isInteger(claims.auth_time) || claims.auth_time > seconds || claims.auth_time < 0 ||
          claims.exp <= claims.iat || claims.auth_time > claims.iat || claims.firebase?.tenant) throw new Error();
    } catch { throw new AuthError(); }
    let certs;
    try { certs = await loadCertificates(); } catch { throw new AuthUnavailable(); }
    try {
      const pem = Object.hasOwn(certs, header.kid) ? certs[header.kid] : null;
      if (!pem || !verify('RSA-SHA256', Buffer.from(parts.slice(0, 2).join('.')), new X509Certificate(pem).publicKey, Buffer.from(parts[2], 'base64url'))) throw new Error();
    } catch { throw new AuthError(); }
    let response, account;
    try {
      response = await request(`https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(env.FIREBASE_API_KEY)}`, {
        method: 'POST', redirect: 'manual', signal: AbortSignal.timeout(10000),
        headers: { 'Content-Type': 'application/json', 'X-Ios-Bundle-Identifier': env.APPLE_BUNDLE_ID ?? 'com.sean.tender' },
        body: JSON.stringify({ idToken: token }),
      });
      account = await response.json();
    } catch { throw new AuthUnavailable(); }
    if (response.status === 429 || response.status >= 500) throw new AuthUnavailable();
    const user = account.users?.[0];
    if (!response.ok || !user || user.localId !== claims.sub || user.disabled === true ||
        !/^\d+$/.test(user.validSince ?? '') || claims.auth_time < Number(user.validSince)) throw new AuthError();
    return createHash('sha256').update(`${env.FIREBASE_PROJECT_ID}:${claims.sub}`).digest('hex');
  };
}
