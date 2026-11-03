import { createHash, randomBytes } from 'node:crypto';
import { AuthError, exchangeToken, passwordAuthRequest, revokeSession, verifyAdministrator, verifyAdministratorIdentity } from './auth.mjs';
import { administratorMfaState, performAdministratorMfa } from './mfa.mjs';

export const RECOVERY_ACCESS = 'vp-recovery-access';
export const RECOVERY_REFRESH = 'vp-recovery-refresh';
export const RECOVERY_VERIFIER = 'vp-recovery-verifier';
export const RECOVERY_WAIT = 'vp-recovery-wait';
const cookieOptions = () => ({ httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax', path: '/' });
export const recoveryCookie = (response, name, value, maxAge) => response.cookies.set(name, value, { ...cookieOptions(), maxAge });
export function clearRecovery(response) {
  for (const name of [RECOVERY_ACCESS, RECOVERY_REFRESH, RECOVERY_VERIFIER]) recoveryCookie(response, name, '', 0);
}
export function setRecoverySession(response, session) {
  recoveryCookie(response, RECOVERY_ACCESS, session.access_token, Math.min(900, Math.floor(session.expires_in)));
  // Used only to revoke this isolated session, never to enter the application.
  recoveryCookie(response, RECOVERY_REFRESH, session.refresh_token, 900);
}
export function passwordValidation(password) {
  return typeof password === 'string' && [...password].length >= 8 && [...password].length <= 128 &&
    new TextEncoder().encode(password).length <= 72 && /[A-Z]/.test(password) && /[a-z]/.test(password) &&
    /[0-9]/.test(password) && /[!"#$%&'()*+,\-./:;<=>?@[\]\\^_`{|}~]/.test(password);
}
export async function requestPasswordReset(email, redirectTo) {
  if (typeof email !== 'string' || email.length > 254 || !/^[^\s@<>]+@[^\s@<>.]+(?:\.[^\s@<>.]+)+$/.test(email.trim())) throw new AuthError('input', 400);
  const verifier = randomBytes(48).toString('base64url');
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  return { verifier, send: () => passwordAuthRequest('recover', null, 'POST', {
    email: email.trim(), code_challenge: challenge, code_challenge_method: 's256',
  }, redirectTo) };
}

export async function recoveryIdentity(token) {
  // FastAPI first verifies THIS JWT's signature, expiry, issuer, audience and
  // subject, plus current confirmed identity/role/approval. Decoding afterwards
  // only narrows that authority to Supabase's signed recovery AMR/session.
  const profile = await verifyAdministratorIdentity(token);
  let claims;
  try { claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString()); } catch { throw new AuthError('reset_link', 401); }
  if (claims.sub !== profile.id || !/^[0-9a-f-]{36}$/i.test(claims.session_id) ||
      !Array.isArray(claims.amr) || !claims.amr.some(item => item.method === 'recovery')) throw new AuthError('reset_link', 401);
  return { ...profile, recoverySessionId: claims.session_id };
}
export async function exchangeRecovery(code, verifier) {
  if (typeof code !== 'string' || !code || code.length > 2048 || typeof verifier !== 'string' || !/^[A-Za-z0-9_-]{64}$/.test(verifier)) throw new AuthError('reset_link', 401);
  let session;
  try {
    session = await exchangeToken('pkce', { auth_code: code, code_verifier: verifier });
    const profile = await recoveryIdentity(session.access_token);
    return { session, state: recoveryState(profile) };
  } catch (error) {
    if (session) await revokeSession(session.access_token, session.refresh_token);
    throw error;
  }
}
export function recoveryState(profile) {
  const state = administratorMfaState(profile);
  return { stage: state.factors.length && !state.ready ? 'mfa' : 'ready', factors: state.factors };
}
export async function verifyRecoveryMfa(token, input) {
  const before = await recoveryIdentity(token);
  const state = administratorMfaState(before);
  if (input.action !== 'verify' || !state.factors.some(factor => factor.id === input.factorId)) throw new AuthError('mfa_input', 400);
  let result;
  try {
    result = await performAdministratorMfa(token, input, {
      identity: recoveryIdentity,
      complete: async upgraded => {
        const after = await recoveryIdentity(upgraded);
        if (after.recoverySessionId !== before.recoverySessionId || after.id !== before.id || !administratorMfaState(after).ready) throw new AuthError('reset_link', 401);
        return after;
      },
    });
  } catch (error) {
    // A definitive identity/session rejection must not install the rejected
    // credentials. Only a temporary verification outage retains rotation.
    if (error.session && error.status !== 503) {
      await revokeSession(error.session.access_token, error.session.refresh_token);
      delete error.session;
    }
    throw error;
  }
  return { session: result.session, state: { stage: 'ready', factors: state.factors } };
}
export async function resetPassword(token, password) {
  if (!passwordValidation(password)) throw new AuthError('password_input', 400);
  const profile = await recoveryIdentity(token);
  if (recoveryState(profile).stage !== 'ready') throw new AuthError('mfa', 403);
  const user = await passwordAuthRequest('user', token, 'PUT', { password });
  if (user.id !== profile.id) throw new AuthError('password_update');
}
export async function changePassword(token, currentPassword, password) {
  if (!passwordValidation(password)) throw new AuthError('password_input', 400);
  if (typeof currentPassword !== 'string' || !currentPassword || currentPassword.length > 4096) throw new AuthError('input', 400);
  if (password === currentPassword) throw new AuthError('password_same', 400);
  const profile = await verifyAdministrator(token);
  const user = await passwordAuthRequest('user', token, 'GET');
  if (user.id !== profile.id || typeof user.email !== 'string' || !user.email_confirmed_at) throw new AuthError('expired', 401);
  let checked;
  try {
    try { checked = await exchangeToken('password', { email: user.email, password: currentPassword }); }
    catch (error) { if (error.code === 'credentials') throw new AuthError('password_current', 400); throw error; }
    if (checked.user?.id !== profile.id || !checked.user?.email_confirmed_at) throw new AuthError('denied', 403);
    await verifyAdministrator(token);
    const updated = await passwordAuthRequest('user', token, 'PUT', { password, current_password: currentPassword });
    if (updated.id !== profile.id) throw new AuthError('password_update');
  } finally {
    // The temporary aal1 password check never replaces the main aal2 cookies.
    if (checked) await revokeSession(checked.access_token, checked.refresh_token);
  }
}
