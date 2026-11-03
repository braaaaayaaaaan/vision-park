import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { registerHooks } from 'node:module';
import { beforeEach, afterEach, test } from 'node:test';
import { RECOVERY_ACCESS, RECOVERY_REFRESH, RECOVERY_VERIFIER, RECOVERY_WAIT, passwordValidation } from '../src/lib/password.mjs';
import { createAuthCoordinator } from '../src/lib/auth-client.mjs';

registerHooks({ resolve(specifier, context, next) { return next(specifier === 'next/server' ? 'next/server.js' : specifier, context); } });
const { NextRequest } = await import('next/server.js');
const route = await import('../src/app/api/auth/password/route.js');
const { proxy } = await import('../src/proxy.js');
const ID = '11111111-1111-4111-8111-111111111111';
const SID = '22222222-2222-4222-8222-222222222222';
const FACTOR = '33333333-3333-4333-8333-333333333333';
const CHALLENGE = '44444444-4444-4444-8444-444444444444';
const OLD = 'CurrentPassword1!', NEW = 'NewPassword2!';
const originalFetch = globalThis.fetch, originalEnv = { ...process.env };
let calls, issued, known, approved, role, factors, consumed, challenge, mailStatus, badCode, otherSession, backendStatus, wrongTemporary, loseUpdate, failAfterMfa;
function token(ready = false, purpose = 'recovery', sid = SID, id = ID) {
  const payload = { sub: id, session_id: sid, amr: [{ method: purpose }], aal: ready ? 'aal2' : 'aal1' };
  const value = `${Buffer.from('{"alg":"ES256"}').toString('base64url')}.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.offline-fixture`;
  known.set(value, { id, ready });
  return value;
}
function credentials(ready = false, purpose = 'recovery', sid = SID, id = ID) {
  return { access_token: token(ready, purpose, sid, id), refresh_token: 'fixture-refresh', expires_in: 3600,
    user: { id, email: 'admin@example.invalid', email_confirmed_at: '2026-01-01T00:00:00Z' } };
}
beforeEach(() => {
  calls = []; known = new Map(); approved = true; role = 'admin'; factors = true; consumed = false;
  issued = null; challenge = null; mailStatus = 200; badCode = false; otherSession = false; backendStatus = 200; wrongTemporary = false;
  loseUpdate = false; failAfterMfa = false;
  process.env.SUPABASE_URL = 'https://auth.example.invalid';
  process.env.SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_fixture';
  process.env.BACKEND_BASE_URL = 'http://127.0.0.1:8000';
  globalThis.fetch = async (url, options = {}) => {
    const parsed = new URL(url);
    const body = options.body ? JSON.parse(options.body) : null;
    const authorization = options.headers?.Authorization?.replace('Bearer ', '');
    calls.push({ path: parsed.pathname, query: parsed.searchParams, method: options.method || 'GET', body, authorization });
    if (parsed.origin === 'http://127.0.0.1:8000') {
      assert.equal(parsed.pathname, '/auth/me');
      const identity = known.get(authorization);
      if (!identity || backendStatus !== 200) return Response.json({}, { status: identity ? backendStatus : 401 });
      return Response.json({ id: identity.id, role, approval_status: approved ? 'approved' : 'pending', is_active: true,
        aal: identity.ready ? 'aal2' : 'aal1', mfa_verified: identity.ready,
        totp_factors: factors ? [{ id: FACTOR, status: 'verified', friendly_name: 'My Authenticator' }] : [] });
    }
    assert.equal(parsed.origin, 'https://auth.example.invalid', 'Unexpected network destination');
    if (parsed.pathname === '/auth/v1/recover') {
      challenge = body.code_challenge;
      assert.equal(body.code_challenge_method, 's256');
      assert.equal(parsed.searchParams.get('redirect_to'), 'http://localhost:3000/reset-password');
      return Response.json(mailStatus === 200 ? {} : { msg: 'SENSITIVE_MAIL_SENTINEL' }, { status: mailStatus });
    }
    if (parsed.pathname === '/auth/v1/token') {
      if (parsed.searchParams.get('grant_type') === 'pkce') {
        if (consumed || body.auth_code !== 'email-code' || createHash('sha256').update(body.code_verifier).digest('base64url') !== challenge) return Response.json({}, { status: 400 });
        consumed = true; issued = credentials(); return Response.json(issued);
      }
      assert.equal(parsed.searchParams.get('grant_type'), 'password');
      if (body.password !== OLD) return Response.json({ msg: 'SENSITIVE_PASSWORD_SENTINEL' }, { status: 400 });
      return Response.json(credentials(false, 'password', CHALLENGE, wrongTemporary ? CHALLENGE : ID));
    }
    if (parsed.pathname.endsWith('/challenge')) return Response.json({ id: CHALLENGE });
    if (parsed.pathname.endsWith('/verify')) {
      if (badCode) return Response.json({ msg: 'SENSITIVE_MFA_SENTINEL' }, { status: 422 });
      issued = credentials(true, 'recovery', otherSession ? CHALLENGE : SID);
      if (failAfterMfa) backendStatus = 503;
      return Response.json(issued);
    }
    if (parsed.pathname === '/auth/v1/user') {
      assert(known.has(authorization));
      if (options.method === 'PUT' && loseUpdate) throw new Error('SENSITIVE_NETWORK_SENTINEL');
      return Response.json({ id: ID, email: 'admin@example.invalid', email_confirmed_at: '2026-01-01T00:00:00Z' });
    }
    if (parsed.pathname === '/auth/v1/logout') return new Response(null, { status: 204 });
    throw new Error('Unexpected native endpoint');
  };
});
afterEach(() => { globalThis.fetch = originalFetch; process.env = { ...originalEnv }; });
function request(body, cookies = {}, origin = 'http://localhost:3000') {
  return new NextRequest('http://localhost:3000/api/auth/password', { method: body ? 'POST' : 'GET',
    headers: { origin, host: 'localhost:3000', 'content-type': 'application/json', cookie: Object.entries(cookies).map(([k, v]) => `${k}=${v}`).join('; ') },
    ...(body ? { body: JSON.stringify(body) } : {}) });
}
function cookies(response, previous = {}) {
  const result = { ...previous };
  for (const item of response.cookies.getAll()) { if (item.maxAge === 0) delete result[item.name]; else result[item.name] = item.value; }
  return result;
}
async function start() {
  const response = await route.POST(request({ action: 'request', email: 'admin@example.invalid' }));
  assert.equal(response.status, 200); return cookies(response);
}
async function exchange() {
  const jar = await start();
  const response = await route.POST(request({ action: 'exchange', code: 'email-code' }, jar));
  assert.equal(response.status, 200); return cookies(response, jar);
}
async function verified() {
  const jar = await exchange();
  const response = await route.POST(request({ action: 'verify', factorId: FACTOR, code: '123456' }, jar));
  assert.equal(response.status, 200); return cookies(response, jar);
}
const writes = () => calls.filter(call => call.path === '/auth/v1/user' && call.method === 'PUT');

test('reset requests use native PKCE and identical responses for unknown accounts/mail restrictions', async () => {
  for (const status of [200, 400, 422, 429, 500]) {
    mailStatus = status;
    const response = await route.POST(request({ action: 'request', email: 'unknown@example.invalid' }));
    assert.deepEqual(await response.json(), { ok: true, stage: 'sent', cooldown: 60 });
    assert.equal(response.cookies.get(RECOVERY_VERIFIER).httpOnly, true);
    assert.equal(response.cookies.get('vp-access'), undefined);
    assert.equal(response.cookies.get('vp-refresh'), undefined);
  }
});
test('pending requests require explicit start over, enforce cooldown, and replace only on request', async () => {
  const jar = await start();
  assert.equal((await route.POST(request({ action: 'request', email: 'admin@example.invalid', startOver: true }, jar))).status, 429);
  delete jar[RECOVERY_WAIT];
  assert.equal((await route.POST(request({ action: 'request', email: 'admin@example.invalid' }, jar))).status, 409);
  const next = await route.POST(request({ action: 'request', email: 'admin@example.invalid', startOver: true }, jar));
  assert.equal(next.status, 200); assert.notEqual(next.cookies.get(RECOVERY_VERIFIER).value, jar[RECOVERY_VERIFIER]);
});
test('recovery exchange is device-bound, one-use and separate from application cookies', async () => {
  const jar = await start();
  assert.equal((await route.POST(request({ action: 'exchange', code: 'email-code' }))).status, 401);
  const response = await route.POST(request({ action: 'exchange', code: 'email-code' }, jar));
  assert.equal(response.status, 200); assert.equal((await response.clone().json()).stage, 'mfa');
  assert.doesNotMatch(await response.text(), /access_token|refresh_token|fixture-refresh|offline-fixture/);
  for (const name of [RECOVERY_ACCESS, RECOVERY_REFRESH]) assert.equal(response.cookies.get(name).httpOnly, true);
  assert.equal(response.cookies.get('vp-access'), undefined);
  assert.equal((await route.POST(request({ action: 'exchange', code: 'email-code' }, jar))).status, 401);
});
test('recovery sessions restore only the recovery screen and cannot restore administrator access', async () => {
  const jar = await exchange();
  assert.equal((await (await route.GET(request(null, jar))).json()).stage, 'mfa');
  const response = await proxy(new NextRequest('http://localhost:3000/change-password', { headers: { cookie: Object.entries(jar).map(([k, v]) => `${k}=${v}`).join('; ') } }));
  assert.match(response.headers.get('location'), /\/login\?reason=expired$/);
});
test('normal aal2 login tokens cannot be substituted for recovery and roles remain enforced', async () => {
  const ordinary = credentials(true, 'password');
  assert.equal((await route.POST(request({ action: 'reset', password: NEW }, { [RECOVERY_ACCESS]: ordinary.access_token }))).status, 401);
  const jar = await exchange();
  for (const restriction of ['pending', 'driver']) {
    approved = restriction !== 'pending'; role = restriction === 'driver' ? 'driver' : 'admin';
    assert.equal((await route.GET(request(null, jar))).status, 403);
  }
  assert.equal(writes().length, 0);
});
test('existing MFA is required before reset; recovery cannot enroll or verify a foreign factor', async () => {
  const jar = await exchange();
  for (const body of [{ action: 'enroll' }, { action: 'verify', factorId: CHALLENGE, code: '123456' }]) assert.equal((await route.POST(request(body, jar))).status, 400);
  assert.equal((await route.POST(request({ action: 'reset', password: NEW }, jar))).status, 403);
  assert.equal(writes().length, 0);
});
test('wrong/expired codes are sanitized; a successful native code upgrades only the recovery session', async () => {
  const jar = await exchange(); badCode = true;
  const rejected = await route.POST(request({ action: 'verify', factorId: FACTOR, code: '000000' }, jar));
  assert.equal(rejected.status, 400); assert.doesNotMatch(await rejected.text(), /SENSITIVE/);
  badCode = false;
  const response = await route.POST(request({ action: 'verify', factorId: FACTOR, code: '123456' }, jar));
  assert.equal((await response.json()).stage, 'ready');
  assert.equal(response.cookies.get(RECOVERY_ACCESS).value, issued.access_token);
  assert.equal(response.cookies.get('vp-access'), undefined);
});
test('an unrelated aal2 session is rejected during recovery MFA', async () => {
  const jar = await exchange(); otherSession = true;
  const response = await route.POST(request({ action: 'verify', factorId: FACTOR, code: '123456' }, jar));
  assert.equal(response.status, 401);
  assert.equal(response.cookies.get(RECOVERY_ACCESS), undefined);
  assert.equal(writes().length, 0);
});
test('native reset uses verified recovery aal2, clears recovery cookies and requires fresh sign in', async () => {
  const jar = await verified();
  const response = await route.POST(request({ action: 'reset', password: NEW }, jar));
  assert.equal((await response.json()).stage, 'updated');
  assert.equal(writes().length, 1); assert.equal(writes()[0].authorization, jar[RECOVERY_ACCESS]);
  assert.equal(response.cookies.get(RECOVERY_ACCESS).maxAge, 0);
  assert.equal(response.cookies.get('vp-access'), undefined);
});
test('accounts without an enrolled factor can reset passwords but still require MFA on later login', async () => {
  factors = false; const jar = await exchange();
  assert.equal((await (await route.GET(request(null, jar))).json()).stage, 'ready');
  assert.equal((await route.POST(request({ action: 'reset', password: NEW }, jar))).status, 200);
});
test('change requires approved admin aal2, checks current password, and writes with original aal2', async () => {
  const intermediate = credentials(false, 'password');
  assert.equal((await route.POST(request({ action: 'change', currentPassword: OLD, password: NEW }, { 'vp-access': intermediate.access_token }))).status, 403);
  assert.equal(calls.some(call => call.path === '/auth/v1/token'), false);
  const main = credentials(true, 'password');
  const jar = { 'vp-access': main.access_token, 'vp-refresh': 'main-refresh' };
  const wrong = await route.POST(request({ action: 'change', currentPassword: 'wrong', password: NEW }, jar));
  assert.equal(wrong.status, 400); assert.match((await wrong.json()).error, /Current password/);
  const response = await route.POST(request({ action: 'change', currentPassword: OLD, password: NEW }, jar));
  assert.equal(response.status, 200); assert.equal(writes().length, 1);
  assert.equal(writes()[0].authorization, main.access_token);
  assert.equal(writes()[0].body.current_password, OLD);
  assert.equal(response.cookies.getAll().length, 0);
});
test('wrong reauthentication identity, expired sessions and outages cannot mutate passwords', async () => {
  const main = credentials(true, 'password'); wrongTemporary = true;
  assert.equal((await route.POST(request({ action: 'change', currentPassword: OLD, password: NEW }, { 'vp-access': main.access_token }))).status, 403);
  wrongTemporary = false;
  for (const status of [401, 503]) {
    backendStatus = status;
    assert.equal((await route.POST(request({ action: 'change', currentPassword: OLD, password: NEW }, { 'vp-access': main.access_token }))).status, status);
  }
  assert.equal(writes().length, 0);
});
test('CSRF, signed-in recovery and weak/oversized passwords fail before writes', async () => {
  assert.equal((await route.POST(request({ action: 'request', email: 'admin@example.invalid' }, {}, 'https://evil.invalid'))).status, 403);
  assert.equal(calls.length, 0);
  assert.equal((await route.POST(request({ action: 'exchange', code: 'email-code' }, { 'vp-access': 'existing' }))).status, 409);
  for (const value of ['short', 'a'.repeat(70) + 'A1!', 'Aa1!' + '😀'.repeat(18)]) assert.equal(passwordValidation(value), false);
  assert.equal(passwordValidation(NEW), true); assert.equal(writes().length, 0);
});
test('password writes serialize with session changes and are never retried by the coordinator', async () => {
  let count = 0;
  const storage = new Map();
  const auth = createAuthCoordinator({ locks: { request: async (_key, _options, execute) => execute() },
    storage: { getItem: key => storage.get(key), setItem: (key, value) => storage.set(key, value) }, randomId: () => 'new-generation',
    fetch: async () => { count++; throw new Error('Lost response'); } });
  await assert.rejects(auth.password({ action: 'change', currentPassword: OLD, password: NEW }), /Lost response/);
  assert.equal(count, 1);
});

test('an unconfirmed native password write is not replayed and clears only the isolated recovery session', async () => {
  const jar = await verified(); loseUpdate = true;
  const response = await route.POST(request({ action: 'reset', password: NEW }, jar));
  assert.equal(response.status, 503); assert.equal(writes().length, 1);
  assert.match((await response.json()).error, /could not be confirmed/);
  assert.equal(response.cookies.get(RECOVERY_ACCESS).maxAge, 0);
  assert.equal(response.cookies.get('vp-access'), undefined);
});
test('temporary profile outage after MFA preserves rotated recovery credentials without granting access', async () => {
  const jar = await exchange(); failAfterMfa = true;
  const response = await route.POST(request({ action: 'verify', factorId: FACTOR, code: '123456' }, jar));
  assert.equal(response.status, 503);
  assert.equal(response.cookies.get(RECOVERY_ACCESS).value, issued.access_token);
  assert.equal(response.cookies.get('vp-access'), undefined);
  const restored = cookies(response, jar);
  assert.equal((await route.GET(request(null, restored))).status, 503);
  backendStatus = 200;
  assert.equal((await (await route.GET(request(null, restored))).json()).stage, 'ready');
});
test('production recovery cookies are secure and stale recovery sessions do not block a new request screen', async () => {
  process.env.NODE_ENV = 'production';
  const jar = await start();
  const response = await route.POST(request({ action: 'exchange', code: 'email-code' }, jar));
  for (const name of [RECOVERY_ACCESS, RECOVERY_REFRESH]) {
    const cookie = response.cookies.get(name);
    assert.equal(cookie.secure, true); assert.equal(cookie.httpOnly, true); assert.equal(cookie.sameSite, 'lax');
    assert(cookie.maxAge <= 900);
  }
  const state = await route.GET(new NextRequest('http://localhost:3000/api/auth/password?intent=request', { headers: { cookie: `${RECOVERY_ACCESS}=expired` } }));
  assert.equal(state.status, 200); assert.equal((await state.json()).stage, 'link');
});
