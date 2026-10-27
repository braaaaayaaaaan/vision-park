import { NextResponse } from 'next/server';
import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, refreshSession, requireSameOrigin, setSessionCookies } from '../../../../lib/auth.mjs';

// Called only while the application's origin-wide browser Auth lock is held.
export async function POST(request) {
  try {
    requireSameOrigin(request);
    const { session } = await refreshSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    const response = NextResponse.json({ ok: true }, { headers: { 'Cache-Control': 'private, no-store' } });
    if (session) setSessionCookies(response, session);
    return response;
  } catch (error) {
    const safe = error instanceof AuthError ? error : new AuthError('unavailable');
    const response = NextResponse.json({ error: safe.message }, { status: safe.status, headers: { 'Cache-Control': 'private, no-store' } });
    // Persist a rotation even if the backend is temporarily unavailable.
    // Never clear cookies on failure: a later coordinated login may supersede it.
    if (error.session) setSessionCookies(response, error.session);
    return response;
  }
}
