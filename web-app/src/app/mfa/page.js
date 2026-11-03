import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { ACCESS_COOKIE, verifyAdministratorIdentity } from '../../lib/auth.mjs';
import MfaForm from './mfa-form';

export const metadata = { title: 'Authenticator Verification', robots: { index: false, follow: false } };

export default async function MfaPage() {
  let profile;
  try { profile = await verifyAdministratorIdentity((await cookies()).get(ACCESS_COOKIE)?.value); }
  catch (error) { redirect(`/login?reason=${error.status === 403 ? 'denied' : error.status === 401 ? 'expired' : 'unavailable'}`); }
  if (profile.mfa_verified === true && profile.aal === 'aal2') redirect('/overview');
  return <MfaForm />;
}
