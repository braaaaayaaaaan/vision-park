import { NextResponse } from 'next/server';
import { AuthError, authDiagnostic, exchangeToken, verifyAdministrator, revokeSession, requireSameOrigin, setSessionCookies } from '../../../../lib/auth.mjs';

export async function POST(request) {
  let session;
  let stage = 'request_validation';
  let startedAt = performance.now();
  try {
    requireSameOrigin(request);
    let input;
    try { input = await request.json(); } catch { throw new AuthError('input', 400); }
    const { email, password } = input ?? {};
    if (typeof email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) || email.length > 254 ||
        typeof password !== 'string' || !password || password.length > 4096) throw new AuthError('input', 400);
    stage = 'supabase_password_authentication';
    startedAt = performance.now();
    session = await exchangeToken('password', { email: email.trim(), password });
    authDiagnostic(stage, 'succeeded', { startedAt });
    stage = 'administrator_verification';
    startedAt = performance.now();
    authDiagnostic(stage, 'reached');
    await verifyAdministrator(session.access_token);
    authDiagnostic(stage, 'succeeded', { startedAt });
    const response = NextResponse.json({ ok: true }, { headers: { 'Cache-Control': 'no-store' } });
    setSessionCookies(response, session);
    return response;
  } catch (error) {
    const safe = error instanceof AuthError ? error : new AuthError('unavailable');
    authDiagnostic(stage, 'failed', { appStatus: safe.status, startedAt });
    if (session) await revokeSession(session.access_token, session.refresh_token);
    const response = NextResponse.json({ error: safe.message }, { status: safe.status, headers: { 'Cache-Control': 'no-store' } });
    return response;
  }
}
