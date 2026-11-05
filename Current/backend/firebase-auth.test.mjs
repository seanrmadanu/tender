import test from 'node:test';
import assert from 'node:assert/strict';
import { createFirebaseVerifier, AuthError, AuthUnavailable } from './firebase-auth.mjs';
import { authEnv, jwt, owner, authReply } from './test-auth-helper.mjs';

test('Firebase verifier checks signatures, claims, live account status, and revocation', async () => {
  let user = {}; let certFetches = 0;
  const verify = createFirebaseVerifier(async (url, options) => {
    const reply = authReply(url, user); assert.ok(reply);
    if (new URL(url).hostname === 'www.googleapis.com') certFetches++;
    else assert.ok(JSON.parse(options.body).idToken);
    return Response.json(reply.body, { headers: reply.headers });
  });
  assert.equal(await verify(jwt(), authEnv), owner('alice'));
  for (const claims of [{ aud: 'attacker' }, { iss: 'https://attacker' }, { exp: 0 }, { sub: '' }, { iat: 9999999999 }, { auth_time: 9999999999 }, { firebase: { tenant: 'other' } }]) await assert.rejects(verify(jwt('alice', claims), authEnv), AuthError);
  for (const header of [{ alg: 'none' }, { alg: 'HS256' }, { kid: 'unknown' }, { crit: ['other'] }]) await assert.rejects(verify(jwt('alice', {}, header), authEnv), AuthError);
  const token = jwt(); const parts = token.split('.');
  parts[1] = Buffer.from(JSON.stringify({ ...JSON.parse(Buffer.from(parts[1], 'base64url')), sub: 'bob' })).toString('base64url');
  await assert.rejects(verify(parts.join('.'), authEnv), AuthError);
  user = { disabled: true }; await assert.rejects(verify(jwt(), authEnv), AuthError);
  user = { validSince: String(Math.floor(Date.now() / 1000)) }; await assert.rejects(verify(jwt(), authEnv), AuthError);
  user = { localId: 'bob' }; await assert.rejects(verify(jwt(), authEnv), AuthError);
  assert.equal(certFetches, 1);
  await assert.rejects(verify(jwt(), {}), AuthUnavailable);
  const offline = createFirebaseVerifier(async () => { throw new Error('offline'); });
  await assert.rejects(offline(jwt(), authEnv), AuthUnavailable);
});
