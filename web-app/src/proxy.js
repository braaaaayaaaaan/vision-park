import { NextResponse } from 'next/server';
import { ACCESS_COOKIE, REFRESH_COOKIE, verifyAdministrator } from './lib/auth.mjs';

export async function proxy(request) {
  const login = request.nextUrl.pathname === '/login';
  let response;
  try {
    await verifyAdministrator(request.cookies.get(ACCESS_COOKIE)?.value);
    response = login && !request.nextUrl.searchParams.has('reason')
      ? NextResponse.redirect(new URL('/overview', request.url))
      : NextResponse.next({ request: { headers: request.headers } });
  } catch (error) {
    const reason = ['expired', 'denied'].includes(error.code) ? error.code : 'unavailable';
    if (error.status === 401 && request.cookies.get(REFRESH_COOKIE)?.value && (!login || !request.nextUrl.searchParams.has('reason'))) {
      const destination = new URL('/session/restore', request.url);
      destination.searchParams.set('next', login ? '/overview' : request.nextUrl.pathname + request.nextUrl.search);
      response = NextResponse.redirect(destination);
    } else {
      response = login ? NextResponse.next() : NextResponse.redirect(new URL(`/login?reason=${reason}`, request.url));
    }
  }
  response.headers.set('Cache-Control', 'private, no-store');
  return response;
}

export const config = {
  matcher: ['/login', '/overview/:path*', '/analytics/:path*', '/approvals/:path*', '/vehicles/:path*', '/tenants/:path*', '/sessions/:path*', '/cameras/:path*', '/parking-structure/:path*', '/parking-rates/:path*', '/payments/:path*'],
};
