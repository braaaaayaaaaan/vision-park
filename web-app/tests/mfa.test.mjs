import assert from 'node:assert/strict';
import { afterEach, beforeEach, test } from 'node:test';
import { registerHooks, createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import * as auth from '../src/lib/auth.mjs';
import { administratorMfaState, performAdministratorMfa } from '../src/lib/mfa.mjs';
import { createAuthCoordinator, createAuthenticatedFetch, AUTH_GENERATION } from '../src/lib/auth-client.mjs';

registerHooks({ resolve(specifier, context, next) { return next(specifier === 'next/server' ? 'next/server.js' : specifier, context); } });
const { NextRequest } = await import('next/server.js');
const loginRoute = await import('../src/app/api/auth/login/route.js');
const mfaRoute = await import('../src/app/api/auth/mfa/route.js');
const refreshRoute = await import('../src/app/api/auth/refresh/route.js');
const { proxy } = await import('../src/proxy.js');
const require = createRequire(import.meta.url);
const ID = '11111111-1111-4111-8111-111111111111';
const FACTOR = '33333333-3333-4333-8333-333333333333';
const CHALLENGE = '44444444-4444-4444-8444-444444444444';
const profile = (ready = false, factors = []) => ({ id: ID, role: 'admin', approval_status: 'approved', is_active: true,
  aal: ready ? 'aal2' : 'aal1', mfa_verified: ready, totp_factors: factors });
const factor = status => ({ id: FACTOR, status, friendly_name: 'Test Authenticator' });
const session = { access_token: 'upgraded-test-token', refresh_token: 'rotated-test-refresh', expires_in: 3600 };
const originalFetch = globalThis.fetch;
const originalEnv = { ...process.env };
let current, calls, wrongCode, backendDown;

beforeEach(() => {
  current = profile(); calls = []; wrongCode = false; backendDown = false;
  process.env.SUPABASE_URL = 'https://supabase.example.invalid';
  process.env.SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_offline_fixture';
  process.env.BACKEND_BASE_URL = 'http://127.0.0.1:8000';
  globalThis.fetch = async (url, options = {}) => {
    const parsed = new URL(url); const path = parsed.pathname;
    calls.push({ path, method: options.method || 'GET', body: options.body ? JSON.parse(options.body) : null });
    if (parsed.origin === 'http://127.0.0.1:8000' && path === '/auth/me') return Response.json(current, { status: backendDown ? 503 : 200 });
    assert.equal(parsed.origin, 'https://supabase.example.invalid', 'Unexpected network destination');
    if (path === '/auth/v1/token') return Response.json({ ...session, access_token: 'password-test-token' });
    if (path === '/auth/v1/factors' && options.method === 'POST') {
      current.totp_factors = [factor('unverified')];
      return Response.json({ id: FACTOR, totp: { secret: 'JBSWY3DPEHPK3PXP', qr_code: '<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg"></svg>' } });
    }
    if (path.endsWith('/challenge')) return Response.json({ id: CHALLENGE });
    if (path.endsWith('/verify')) {
      if (wrongCode) return Response.json({ code: 'mfa_verification_failed', msg: 'SENSITIVE_UPSTREAM_SENTINEL' }, { status: 422 });
      current = profile(true, [factor('verified')]);
      return Response.json(session);
    }
    if (path === `/auth/v1/factors/${FACTOR}` && options.method === 'DELETE') { current.totp_factors = []; return Response.json({ id: FACTOR }); }
    throw new Error('Unexpected mocked request');
  };
});
afterEach(() => { globalThis.fetch = originalFetch; process.env = { ...originalEnv }; });

function request(path, body, { origin = 'http://localhost:3000', token = 'password-test-token' } = {}) {
  return new NextRequest('http://localhost:3000' + path, { method: body ? 'POST' : 'GET',
    headers: { origin, host: 'localhost:3000', cookie: `vp-access=${token}; vp-refresh=test-refresh`, 'content-type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {}) });
}

test('password login sets HTTP-only intermediate cookies and selects MFA', async () => {
  const response = await loginRoute.POST(request('/api/auth/login', { email: 'admin@example.invalid', password: 'test-password' }));
  assert.equal(response.status, 200);
  assert.equal((await response.json()).next, '/mfa');
  assert.equal(response.cookies.get('vp-access').httpOnly, true);
  assert.equal(response.cookies.get('vp-refresh').httpOnly, true);
});

test('enrollment is native and an interrupted setup never enrolls twice', async () => {
  const response = await mfaRoute.POST(request('/api/auth/mfa', { action: 'enroll' }));
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.enrollment.id, FACTOR);
  assert.match(body.enrollment.qr, /^data:image\/svg\+xml;base64,/);
  assert.equal(calls.find(call => call.path === '/auth/v1/factors').body.factor_type, 'totp');
  const duplicate = await mfaRoute.POST(request('/api/auth/mfa', { action: 'enroll' }));
  assert.equal(duplicate.status, 409);
  assert.equal(calls.filter(call => call.path === '/auth/v1/factors').length, 1);
});

test('restarting setup can delete only the selected unverified factor', async () => {
  current.totp_factors = [factor('unverified')];
  assert.equal((await mfaRoute.POST(request('/api/auth/mfa', { action: 'restart', factorId: FACTOR }))).status, 200);
  assert.equal(calls.filter(call => call.method === 'DELETE').length, 1);
  current.totp_factors = [factor('verified')];
  calls = [];
  assert.equal((await mfaRoute.POST(request('/api/auth/mfa', { action: 'restart', factorId: FACTOR }))).status, 409);
  assert.equal(calls.filter(call => call.method === 'DELETE').length, 0);
});

test('native verification rotates cookies; JSON never exposes session tokens', async () => {
  current.totp_factors = [factor('verified')];
  const response = await mfaRoute.POST(request('/api/auth/mfa', { action: 'verify', factorId: FACTOR, code: '123456' }));
  assert.equal(response.status, 200);
  assert.equal(response.cookies.get('vp-access').value, session.access_token);
  assert.equal(response.cookies.get('vp-refresh').value, session.refresh_token);
  assert.equal(response.cookies.get('vp-access').httpOnly, true);
  assert.equal(response.headers.get('X-VisionPark-Session-Changed'), '1');
  assert.deepEqual(await response.json(), { ok: true, next: '/overview' });
});

test('wrong/expired native code responses stay gated and sanitize messages', async () => {
  current.totp_factors = [factor('verified')]; wrongCode = true;
  const response = await mfaRoute.POST(request('/api/auth/mfa', { action: 'verify', factorId: FACTOR, code: '000000' }));
  assert.equal(response.status, 400);
  const text = await response.text();
  assert.match(text, /mfa_code/); assert.doesNotMatch(text, /SENSITIVE_UPSTREAM_SENTINEL/);
  assert.equal(current.mfa_verified, false);
  assert.equal(response.cookies.getAll().length, 0);
});

test('cross-origin, foreign-factor and malformed-code requests fail before mutations', async () => {
  current.totp_factors = [factor('verified')];
  assert.equal((await mfaRoute.POST(request('/api/auth/mfa', { action: 'enroll' }, { origin: 'https://attacker.invalid' }))).status, 403);
  assert.equal((await mfaRoute.POST(request('/api/auth/mfa', { action: 'verify', factorId: CHALLENGE, code: '123456' }))).status, 409);
  assert.equal((await mfaRoute.POST(request('/api/auth/mfa', { action: 'verify', factorId: FACTOR, code: '12345' }))).status, 400);
  assert.equal(calls.filter(call => call.method === 'POST').length, 0);
});

test('aal1 refresh preserves cookies while reporting MFA; valid aal2 restores normally', async () => {
  const first = await refreshRoute.POST(request('/api/auth/refresh', {}));
  assert.equal((await first.json()).mfa_required, true);
  current = profile(true, [factor('verified')]);
  const second = await refreshRoute.POST(request('/api/auth/refresh', {}));
  assert.equal((await second.json()).mfa_required, false);
  assert.equal(calls.filter(call => call.path === '/auth/v1/token').length, 0);
});

test('every protected page redirect handles aal1, aal2 and wrong roles', async () => {
  for (const path of ['/overview', '/payments', '/parking-structure', '/cameras', '/vehicles', '/analytics', '/approvals', '/sessions', '/tenants', '/parking-rates']) {
    const response = await proxy(request(path));
    assert.equal(new URL(response.headers.get('location')).pathname, '/mfa');
  }
  assert.equal((await proxy(request('/mfa'))).status, 200);
  current = profile(true, [factor('verified')]);
  assert.equal((await proxy(request('/overview'))).status, 200);
  current.role = 'driver';
  assert.match((await proxy(request('/overview'))).headers.get('location'), /login\?reason=denied/);
});

test('rendering boundary independently rejects aal1 even if Proxy is skipped', async () => {
  const source = readFileSync(new URL('../src/app/(admin)/layout.js', import.meta.url), 'utf8');
  const { transformSync } = require('next/dist/build/swc');
  const { code } = transformSync(source, { filename: 'layout.js', jsc: { parser: { syntax: 'ecmascript', jsx: true }, transform: { react: { runtime: 'automatic' } } }, module: { type: 'commonjs' } });
  const compiled = { exports: {} };
  vm.runInNewContext(code, { module: compiled, exports: compiled.exports, require: specifier => {
    if (specifier === '@/lib/auth.mjs') return auth;
    if (specifier === 'next/headers') return { cookies: async () => ({ get: () => ({ value: 'password-test-token' }) }) };
    if (specifier === 'next/navigation') return { redirect: destination => { throw new Error('REDIRECT:' + destination); } };
    if (specifier === '@/components/admin-shell') return { default: () => null };
    return require(specifier);
  } });
  await assert.rejects(compiled.exports.default({ children: null }), /REDIRECT:\/mfa/);
  current = profile(true, [factor('verified')]);
  assert.ok(await compiled.exports.default({ children: null }));
});

test('a backend outage after native verification retains rotation but grants nothing', async () => {
  let reads = 0;
  await assert.rejects(performAdministratorMfa('old', { action: 'verify', factorId: FACTOR, code: '123456' }, {
    identity: async () => profile(false, [factor('verified')]),
    native: async path => path.endsWith('/challenge') ? { id: CHALLENGE } : session,
    complete: async () => { reads++; throw new auth.AuthError('unavailable'); },
  }), error => error.status === 503 && error.session === session);
  assert.equal(reads, 1);
});

test('coordinator serializes MFA with refresh/logout and invalidates stale queued sessions', async () => {
  const data = new Map([[AUTH_GENERATION, 'initial']]); let requests = 0;
  const coordinator = createAuthCoordinator({ storage: { getItem: key => data.get(key), setItem: (key, value) => data.set(key, value) },
    locks: { request: async (name, options, callback) => { assert.equal(options.mode, 'exclusive'); return callback(); } },
    fetch: async () => { requests++; return Response.json({ ok: true }, { headers: { 'X-VisionPark-Session-Changed': '1' } }); }, randomId: () => 'after-mfa' });
  await coordinator.mfa({ action: 'verify', factorId: FACTOR, code: '123456' });
  assert.equal(data.get(AUTH_GENERATION), 'after-mfa');
  await assert.rejects(coordinator.refresh('initial'), error => error.sessionChanged === true);
  assert.equal(requests, 1);
});

test('MFA-required refresh never replays a protected write', async () => {
  let writes = 0;
  const requestProtected = createAuthenticatedFetch({ generation: () => 'same', refresh: async () => Response.json({ ok: true, mfa_required: true }) }, async () => { writes++; return new Response(null, { status: 401 }); });
  const response = await requestProtected('/api/payments/tariffs', { method: 'POST', body: '{}' });
  assert.equal(response.status, 403); assert.equal(writes, 1);
});

test('restoration never treats an unenrolled aal1 state as completed MFA', () => {
  assert.equal(administratorMfaState(profile()).ready, false);
  assert.throws(() => administratorMfaState({ ...profile(), totp_factors: undefined }), error => error.status === 503);
});
