import { NextResponse } from 'next/server';
import { ACCESS_COOKIE, REFRESH_COOKIE, requireSameOrigin, revokeSession, clearSessionCookies } from '../../../../lib/auth.mjs';

export async function POST(request) {
  try { requireSameOrigin(request); } catch {
    return NextResponse.json({ error: 'Reload the page and try again.' }, { status: 403 });
  }
  const revoked = await revokeSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
  // Relative Location preserves the public origin behind a reverse proxy.
  const response = new NextResponse(null, { status: 303, headers: { Location: revoked ? '/login' : '/login?reason=signout' } });
  clearSessionCookies(response);
  response.headers.set('Cache-Control', 'no-store');
  return response;
}
