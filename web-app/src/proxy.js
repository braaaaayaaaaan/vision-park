import { NextResponse } from 'next/server';
import { ACCESS_COOKIE, REFRESH_COOKIE, restoreSession, setSessionCookies, clearSessionCookies } from './lib/auth.mjs';

export async function proxy(request) {
  const login = request.nextUrl.pathname === '/login';
  let response;
  try {
    const { session } = await restoreSession(request.cookies.get(ACCESS_COOKIE)?.value, request.cookies.get(REFRESH_COOKIE)?.value);
    if (session) {
      request.cookies.set(ACCESS_COOKIE, session.access_token);
      request.cookies.set(REFRESH_COOKIE, session.refresh_token);
    }
    response = login && !request.nextUrl.searchParams.has('reason')
      ? NextResponse.redirect(new URL('/overview', request.url))
      : NextResponse.next({ request: { headers: request.headers } });
    if (session) setSessionCookies(response, session);
  } catch (error) {
    const reason = ['expired', 'denied'].includes(error.code) ? error.code : 'unavailable';
    response = login ? NextResponse.next() : NextResponse.redirect(new URL(`/login?reason=${reason}`, request.url));
    if (error.status === 401 || error.status === 403) clearSessionCookies(response);
    if (error.session) setSessionCookies(response, error.session);
  }
  response.headers.set('Cache-Control', 'private, no-store');
  return response;
}

export const config = {
  matcher: ['/login', '/overview/:path*', '/analytics/:path*', '/approvals/:path*', '/vehicles/:path*', '/tenants/:path*', '/sessions/:path*', '/parking-structure/:path*'],
};
