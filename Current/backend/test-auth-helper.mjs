import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { sign, createHash } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

function makeTestCredentials() {
  const directory = mkdtempSync(join(tmpdir(), 'tender-auth-test-'));
  const keyPath = join(directory, 'key.pem');
  try {
    const cert = execFileSync('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
      '-subj', '/CN=Tender local tests only', '-keyout', keyPath,
    ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    return { key: readFileSync(keyPath), cert };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

const { key, cert } = makeTestCredentials();
export const authEnv = { FIREBASE_PROJECT_ID: 'test-project', FIREBASE_API_KEY: 'public-test-key' };
export function jwt(uid = 'alice', overrides = {}, header = {}) {
  const seconds = Math.floor(Date.now() / 1000);
  const parts = [{ alg: 'RS256', kid: 'test-key', ...header }, { sub: uid, aud: authEnv.FIREBASE_PROJECT_ID, iss: `https://securetoken.google.com/${authEnv.FIREBASE_PROJECT_ID}`, iat: seconds - 10, exp: seconds + 3600, auth_time: seconds - 10, ...overrides }].map(value => Buffer.from(JSON.stringify(value)).toString('base64url'));
  return parts.join('.') + '.' + sign('RSA-SHA256', Buffer.from(parts.join('.')), key).toString('base64url');
}
export const owner = uid => createHash('sha256').update(`${authEnv.FIREBASE_PROJECT_ID}:${uid}`).digest('hex');
export function authReply(request, user = {}) {
  const url = new URL(request.url ?? request);
  if (url.hostname === 'www.googleapis.com') return { body: { 'test-key': cert }, headers: { 'Cache-Control': 'public, max-age=3600' } };
  if (url.hostname === 'identitytoolkit.googleapis.com') return { body: { users: [{ localId: 'alice', validSince: '0', ...user }] } };
  return null;
}
