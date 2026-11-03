import { NextResponse } from 'next/server';
import { ACCESS_COOKIE, AuthError, requireSameOrigin, setSessionCookies, verifyAdministratorIdentity } from '../../../../lib/auth.mjs';
import { administratorMfaState, performAdministratorMfa } from '../../../../lib/mfa.mjs';
import { readLimitedBody } from '../../../../lib/parking-structure-api.mjs';

const headers = { 'Cache-Control': 'private, no-store', Pragma: 'no-cache' };

function failure(error) {
  const safe = error instanceof AuthError ? error : new AuthError('unavailable');
  const response = NextResponse.json({ error: safe.message, code: safe.code }, { status: safe.status, headers });
  if (error.session) {
    setSessionCookies(response, error.session);
    response.headers.set('X-VisionPark-Session-Changed', '1');
  }
  return response;
}

export async function GET(request) {
  try {
    return NextResponse.json(administratorMfaState(await verifyAdministratorIdentity(request.cookies.get(ACCESS_COOKIE)?.value)), { headers });
  } catch (error) { return failure(error); }
}

export async function POST(request) {
  try {
    requireSameOrigin(request);
    if (request.headers.get('content-type')?.split(';')[0] !== 'application/json') throw new AuthError('mfa_input', 400);
    let input;
    try { input = JSON.parse((await readLimitedBody(request.body, 2048)).toString()); }
    catch { throw new AuthError('mfa_input', 400); }
    const { body, session } = await performAdministratorMfa(request.cookies.get(ACCESS_COOKIE)?.value, input);
    const response = NextResponse.json(body, { headers });
    if (session) {
      setSessionCookies(response, session);
      response.headers.set('X-VisionPark-Session-Changed', '1');
    }
    return response;
  } catch (error) { return failure(error); }
}
