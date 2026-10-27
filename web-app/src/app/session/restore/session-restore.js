'use client';
import { useEffect, useState } from 'react';
import { refreshAdministrator } from '../../../lib/auth-client.mjs';

export default function SessionRestore({ destination }) {
  const [error, setError] = useState('');
  useEffect(() => {
    let active = true;
    refreshAdministrator().then(response => {
      if (!active) return;
      if (response.ok) window.location.replace(destination);
      else window.location.replace(`/login?reason=${response.status === 403 ? 'denied' : response.status === 401 ? 'expired' : 'unavailable'}`);
    }).catch(failure => { if (active) setError(failure.message || 'Unable to restore your session. Please sign in again.'); });
    return () => { active = false; };
  }, [destination]);
  return <main style={{ padding: '2rem' }} aria-live="polite">
    <p>{error || 'Restoring your session…'}</p>
    {error && <a href="/login?reason=expired">Return to Sign In</a>}
    <noscript>Session restoration requires JavaScript. Return to the sign-in page to continue.</noscript>
  </main>;
}
