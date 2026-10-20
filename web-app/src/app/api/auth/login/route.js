import { NextResponse } from 'next/server';
import { AuthError, exchangeToken, verifyAdministrator, revokeSession, requireSameOrigin, setSessionCookies, clearSessionCookies } from '../../../../lib/auth.mjs';

export async function POST(request) {
  let session;
  try {
    requireSameOrigin(request);
    let input;
    try { input = await request.json(); } catch { throw new AuthError('input', 400); }
    const { email, password } = input ?? {};
    if (typeof email !== 'string' || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim()) || email.length > 254 ||
        typeof password !== 'string' || !password || password.length > 4096) throw new AuthError('input', 400);
    session = await exchangeToken('password', { email: email.trim(), password });
    await verifyAdministrator(session.access_token);
    const response = NextResponse.json({ ok: true }, { headers: { 'Cache-Control': 'no-store' } });
    setSessionCookies(response, session);
    return response;
  } catch (error) {
    if (session) await revokeSession(session.access_token, session.refresh_token);
    const safe = error instanceof AuthError ? error : new AuthError('unavailable');
    const response = NextResponse.json({ error: safe.message }, { status: safe.status, headers: { 'Cache-Control': 'no-store' } });
    if (safe.code !== 'origin') clearSessionCookies(response);
    return response;
  }
}
