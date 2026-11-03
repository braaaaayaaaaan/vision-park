import { AuthError, mfaAuthRequest, validatedSession, verifyAdministrator, verifyAdministratorIdentity } from './auth.mjs';

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function administratorMfaState(profile) {
  if (!Array.isArray(profile.totp_factors)) throw new AuthError('unavailable');
  const factors = profile.totp_factors.map(factor => {
    if (!uuid.test(factor.id) || !['verified', 'unverified'].includes(factor.status)) throw new AuthError('unavailable');
    return { id: factor.id, status: factor.status, friendly_name: typeof factor.friendly_name === 'string' ? factor.friendly_name : 'Authenticator' };
  });
  return { ready: profile.aal === 'aal2' && profile.mfa_verified === true,
    factors: factors.filter(factor => factor.status === 'verified'),
    pending: factors.filter(factor => factor.status === 'unverified') };
}

// Injectable transport boundaries keep tests offline; Supabase alone generates
// secrets, validates codes and signs the upgraded session.
export async function performAdministratorMfa(token, input, dependencies = {}) {
  const identity = dependencies.identity ?? verifyAdministratorIdentity;
  const native = dependencies.native ?? mfaAuthRequest;
  const complete = dependencies.complete ?? verifyAdministrator;
  const profile = await identity(token);
  const state = administratorMfaState(profile);
  if (!input || typeof input !== 'object' || Array.isArray(input) ||
      Object.keys(input).some(key => !['action', 'factorId', 'code'].includes(key)) ||
      !['enroll', 'restart', 'verify'].includes(input.action)) throw new AuthError('mfa_input', 400);
  if (input.action === 'verify') {
    if (typeof input.code !== 'string' || !/^[0-9]{6}$/.test(input.code) || !uuid.test(input.factorId)) throw new AuthError('mfa_input', 400);
    if (![...state.factors, ...state.pending].some(factor => factor.id === input.factorId)) throw new AuthError('mfa_setup', 409);
    const challenge = await native(`factors/${input.factorId}/challenge`, token, 'POST', {});
    if (!uuid.test(challenge?.id)) throw new AuthError('unavailable');
    const session = validatedSession(await native(`factors/${input.factorId}/verify`, token, 'POST', { challenge_id: challenge.id, code: input.code }));
    try {
      const verified = await complete(session.access_token);
      if (verified.id !== profile.id) throw new AuthError('denied', 403);
      return { body: { ok: true, next: '/overview' }, session };
    } catch (error) {
      // Native verification already rotated tokens. Preserve them even if the
      // profile service fails, while still denying entry to protected content.
      const safe = error instanceof AuthError ? error : new AuthError('unavailable');
      safe.session = session;
      throw safe;
    }
  }
  if (state.factors.length) throw new AuthError('mfa_setup', 409);
  if (input.action === 'restart') {
    if (!uuid.test(input.factorId) || !state.pending.some(factor => factor.id === input.factorId)) throw new AuthError('mfa_setup', 409);
    await native(`factors/${input.factorId}`, token, 'DELETE');
  } else if (state.pending.length) {
    // A lost response/reload must never automatically create another factor.
    throw new AuthError('mfa_setup', 409);
  }
  const factor = await native('factors', token, 'POST', { factor_type: 'totp', issuer: 'VisionPark', friendly_name: `VisionPark ${crypto.randomUUID()}` });
  if (!uuid.test(factor?.id) || typeof factor.totp?.secret !== 'string' ||
      !/^[A-Z2-7]+=*$/.test(factor.totp.secret) || typeof factor.totp.qr_code !== 'string' || !/<svg(?:\s|>)/.test(factor.totp.qr_code)) throw new AuthError('unavailable');
  return { body: { ok: true, enrollment: { id: factor.id, secret: factor.totp.secret,
    qr: `data:image/svg+xml;base64,${Buffer.from(factor.totp.qr_code).toString('base64')}` } }, session: null };
}
