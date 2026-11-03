import { NextResponse } from 'next/server';
import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, requireSameOrigin, revokeSession } from '../../../../lib/auth.mjs';
import { readLimitedBody } from '../../../../lib/parking-structure-api.mjs';
import { RECOVERY_ACCESS, RECOVERY_REFRESH, RECOVERY_VERIFIER, RECOVERY_WAIT, recoveryCookie, clearRecovery,
  setRecoverySession, requestPasswordReset, exchangeRecovery, recoveryIdentity, recoveryState, verifyRecoveryMfa,
  resetPassword, changePassword } from '../../../../lib/password.mjs';

const headers = { 'Cache-Control': 'private, no-store', Pragma: 'no-cache', 'Referrer-Policy': 'no-referrer' };
const json = (body, status = 200) => NextResponse.json(body, { status, headers });
const value = (request, name) => request.cookies.get(name)?.value;
const cooldown = request => Math.max(0, Math.min(60, Math.ceil((Number(value(request, RECOVERY_WAIT)) - Date.now()) / 1000))) || 0;
const signedOut = request => { if (value(request, ACCESS_COOKIE) || value(request, REFRESH_COOKIE)) throw new AuthError('reset_signedin', 409); };
function failure(error) {
  const safe = error instanceof AuthError ? error : new AuthError('unavailable');
  const response = json({ error: safe.message, code: safe.code }, safe.status);
  if (safe.session) setRecoverySession(response, safe.session);
  return response;
}

export async function GET(request) {
  try {
    if (new URL(request.url).searchParams.get('intent') === 'request') {
      return json({ stage: 'link', pending: Boolean(value(request, RECOVERY_VERIFIER)), cooldown: cooldown(request) });
    }
    const token = value(request, RECOVERY_ACCESS);
    const state = token ? recoveryState(await recoveryIdentity(token)) : { stage: 'link' };
    return json({ ...state, pending: Boolean(value(request, RECOVERY_VERIFIER)), cooldown: cooldown(request) });
  } catch (error) { return failure(error); }
}
export async function POST(request) {
  let consumeLink = false;
  let consumeRecovery = false;
  try {
    requireSameOrigin(request);
    if (request.headers.get('content-type')?.split(';')[0] !== 'application/json') throw new AuthError('input', 400);
    let input;
    try { input = JSON.parse((await readLimitedBody(request.body, 8192)).toString()); }
    catch { throw new AuthError('input', 400); }
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new AuthError('input', 400);
    const token = value(request, RECOVERY_ACCESS);
    if (input.action === 'change') {
      await changePassword(value(request, ACCESS_COOKIE), input.currentPassword, input.password);
      return json({ ok: true, stage: 'updated' });
    }
    if (input.action === 'cancel') {
      await revokeSession(token, value(request, RECOVERY_REFRESH));
      const response = json({ ok: true }); clearRecovery(response); return response;
    }
    signedOut(request);
    if (input.action === 'request') {
      if (cooldown(request)) throw new AuthError('rate', 429);
      if (value(request, RECOVERY_VERIFIER) && input.startOver !== true) throw new AuthError('reset_pending', 409);
      const reset = await requestPasswordReset(input.email, `${request.headers.get('origin')}/reset-password`);
      const response = json({ ok: true, stage: 'sent', cooldown: 60 });
      await revokeSession(token, value(request, RECOVERY_REFRESH));
      clearRecovery(response);
      recoveryCookie(response, RECOVERY_VERIFIER, reset.verifier, 3600);
      recoveryCookie(response, RECOVERY_WAIT, String(Date.now() + 60000), 60);
      // Delivery cannot be inferred from Auth's response. Retain the verifier
      // even after a timeout: an email might still arrive. No automatic resend.
      await reset.send().catch(() => {});
      return response;
    }
    if (input.action === 'exchange') {
      consumeLink = true;
      const { session, state } = await exchangeRecovery(input.code, value(request, RECOVERY_VERIFIER));
      const response = json(state);
      recoveryCookie(response, RECOVERY_VERIFIER, '', 0);
      setRecoverySession(response, session);
      return response;
    }
    if (input.action === 'verify') {
      const { session, state } = await verifyRecoveryMfa(token, { action: 'verify', factorId: input.factorId, code: input.code });
      const response = json(state); setRecoverySession(response, session); return response;
    }
    if (input.action === 'reset') {
      consumeRecovery = true;
      await resetPassword(token, input.password);
      await revokeSession(token, value(request, RECOVERY_REFRESH));
      const response = json({ ok: true, stage: 'updated' }); clearRecovery(response); return response;
    }
    throw new AuthError('input', 400);
  } catch (error) {
    const response = failure(error);
    if (consumeLink) recoveryCookie(response, RECOVERY_VERIFIER, '', 0);
    if (consumeRecovery) {
      await revokeSession(value(request, RECOVERY_ACCESS), value(request, RECOVERY_REFRESH));
      clearRecovery(response);
    }
    return response;
  }
}
