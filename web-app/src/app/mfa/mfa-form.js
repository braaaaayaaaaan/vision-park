'use client';
import { useEffect, useRef, useState } from 'react';
import BrandMark from '../../components/brand-mark';
import accountStyles from '../../components/admin-shell.module.css';
import { AUTH_GENERATION, mutateAdministratorMfa, refreshAdministrator, logoutAdministrator } from '../../lib/auth-client.mjs';
import styles from '../login/page.module.css';
import mfaStyles from './page.module.css';

export default function MfaForm() {
  const [state, setState] = useState(null);
  const [enrollment, setEnrollment] = useState(null);
  const [factorId, setFactorId] = useState('');
  const [code, setCode] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const working = useRef(false);
  const active = useRef(true);

  async function load() {
    let response = await fetch('/api/auth/mfa', { credentials: 'same-origin', cache: 'no-store' });
    if (response.status === 401) {
      const refreshed = await refreshAdministrator();
      if (!refreshed.ok) { window.location.replace('/login?reason=expired'); return; }
      response = await fetch('/api/auth/mfa', { credentials: 'same-origin', cache: 'no-store' });
    }
    const result = await response.json();
    if (!response.ok) throw new Error(result.error || 'Unable to check authenticator setup.');
    if (!active.current) return;
    if (result.ready) { window.location.replace('/overview'); return; }
    setState(result);
    setFactorId(result.factors[0]?.id || '');
  }

  useEffect(() => {
    active.current = true;
    Promise.resolve().then(() => { if (active.current) return load(); }).catch(() => { if (active.current) setError('Unable to check authenticator setup. Retry when connected.'); });
    const changed = event => { if (event.key === AUTH_GENERATION) { setEnrollment(null); setCode(''); window.location.reload(); } };
    window.addEventListener('storage', changed);
    return () => { active.current = false; window.removeEventListener('storage', changed); };
    // Loading only reads status; React remounts never enroll a factor.
  }, []);

  async function act(action, selected = factorId) {
    if (working.current) return;
    working.current = true;
    setBusy(true); setError('');
    try {
      const response = await mutateAdministratorMfa({ action, ...(selected ? { factorId: selected } : {}), ...(action === 'verify' ? { code } : {}) });
      const result = await response.json();
      if (!active.current) return;
      setCode('');
      if (!response.ok) {
        setError(result.error || 'Verification could not be confirmed. Check the current code and retry.');
        if (response.status === 401) window.location.replace('/session/restore');
        // Inspect after uncertain enrollment, never repeat the mutation.
        if (action !== 'verify') { setEnrollment(null); await load(); }
        return;
      }
      if (action === 'verify') { setEnrollment(null); window.location.replace('/overview'); }
      else { setEnrollment(result.enrollment); setFactorId(result.enrollment.id); }
    } catch {
      if (active.current) {
        setCode('');
        setError('The result could not be confirmed. Check your connection and current setup before retrying.');
        if (action !== 'verify') { setEnrollment(null); await load().catch(() => {}); }
      }
    } finally { working.current = false; if (active.current) setBusy(false); }
  }

  async function signOut() {
    if (working.current) return;
    working.current = true; setBusy(true); setEnrollment(null); setCode('');
    try { await logoutAdministrator(); window.location.replace('/login'); }
    catch { setError('Unable to sign out. Please retry.'); working.current = false; setBusy(false); }
  }

  const verifying = enrollment || state?.factors.length > 0;
  return <div className={styles.page}>
    <header className={styles.topBar}><div className={styles.brand}><span className={styles.brandMark}><BrandMark inverse className={styles.brandImage} /></span><span>VisionPark</span></div></header>
    <main className={styles.main}><div className={styles.content}><section className={styles.panel} aria-labelledby="mfa-title">
      <header className={styles.intro}><h1 id="mfa-title">{verifying ? 'Verify Your Authenticator' : 'Set Up Your Authenticator'}</h1>
        <p className={`${styles.description} ${mfaStyles.subtitle}`}>Two-step verification is required for <span className={mfaStyles.accessLabel}>administrator access.</span></p></header>
      {!state && <p role="status">Checking your account…</p>}
      {enrollment && <div className={mfaStyles.enrollment}>
        <div className={mfaStyles.qrFrame}>
          {/* Supabase supplies the SVG. Never send its secret to a QR service. */}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className={mfaStyles.qrImage} src={enrollment.qr} width="220" height="220" alt="Scan with your authenticator app" />
        </div>
        <div className={mfaStyles.setupDetails}>
          <p id="mfa-setup-key-label" className={mfaStyles.setupInstructions}>Scan this code, or manually enter this setup key:</p>
          <code className={mfaStyles.setupKey} aria-labelledby="mfa-setup-key-label">{enrollment.secret}</code>
        </div>
        <p className={mfaStyles.setupNote}>Keep this key private. Setup is complete only after verification.</p>
      </div>}
      {state && !verifying && <div className={styles.form}>
        <p className={mfaStyles.guidance}>{state.pending.length ? 'An earlier setup was interrupted. Restart it to receive a new setup key.' : 'Add VisionPark to an authenticator app such as Google Authenticator or Microsoft Authenticator.'}</p>
        <button className={styles.submit} disabled={busy} onClick={() => act(state.pending.length ? 'restart' : 'enroll', state.pending[0]?.id)}>{state.pending.length ? 'Restart Setup' : 'Begin Setup'}</button>
      </div>}
      {verifying && <form className={styles.form} onSubmit={event => { event.preventDefault(); act('verify'); }} aria-busy={busy}>
        {!enrollment && state.factors.length > 1 && <label className={styles.field}>Authenticator<select value={factorId} disabled={busy} onChange={event => setFactorId(event.target.value)}>{state.factors.map(factor => <option key={factor.id} value={factor.id}>{factor.friendly_name || 'Authenticator'}</option>)}</select></label>}
        <div className={styles.field}><label htmlFor="mfa-code">Six-Digit Code</label><input id="mfa-code" value={code} onChange={event => setCode(event.target.value.replace(/[^0-9]/g, '').slice(0, 6))} inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required disabled={busy} /></div>
        <button className={styles.submit} disabled={busy || code.length !== 6}>{busy ? 'Verifying…' : 'Verify and Continue'}</button>
      </form>}
      {error && <p className={styles.error} role="alert">{error}</p>}
      {!state && <button disabled={busy} onClick={() => load().catch(() => setError('Unable to check your setup. Please retry.'))}>Retry</button>}
      <footer className={mfaStyles.footer}>
        <p className={mfaStyles.guidance}>Lost your authenticator? Contact your VisionPark operator for identity-verified recovery.</p>
        <button className={`${accountStyles.signOut} ${mfaStyles.signOut}`} type="button" disabled={busy} onClick={signOut}>Sign Out</button>
      </footer>
    </section></div></main>
  </div>;
}
