'use client';
import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { mutateAdministratorPassword } from '../lib/auth-client.mjs';
import styles from '../app/login/page.module.css';
import extra from './password-form.module.css';

const policy = 'Use at least 8 characters, including an uppercase letter, a lowercase letter, a number and a special character. Maximum 72 bytes.';
function PasswordField({ name, label, pending, current = false }) {
  const [visible, setVisible] = useState(false);
  return <div className={styles.field}>
    <label htmlFor={name}>{label}</label>
    <div className={styles.passwordField}>
      <input id={name} name={name} type={visible ? 'text' : 'password'} autoComplete={current ? 'current-password' : 'new-password'}
        required maxLength={current ? 4096 : 128} disabled={pending} aria-describedby={current ? undefined : 'password-policy'} />
      <button className={styles.visibility} type="button" aria-controls={name} aria-label={`${visible ? 'Hide' : 'Show'} ${label.toLowerCase()}`}
        aria-pressed={visible} disabled={pending} onClick={() => setVisible(value => !value)}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" aria-hidden="true">
          <path d="M3 12s3.5-7 9-7 9 7 9 7-3.5 7-9 7-9-7-9-7Z" /><circle cx="12" cy="12" r="3" />{visible && <path d="m3 3 18 18" />}
        </svg>
      </button>
    </div>
  </div>;
}
async function mutation(input) {
  const response = await mutateAdministratorPassword(input);
  const body = await response.json();
  if (!response.ok) throw new Error(body.error || 'Unable to continue. Please try again.');
  return body;
}

export default function PasswordForm({ mode }) {
  const change = mode === 'change';
  const forgot = mode === 'forgot';
  const [state, setState] = useState({ stage: change ? 'ready' : 'loading', factors: [], cooldown: 0, pending: false });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const initialization = useRef(null);
  useEffect(() => {
    if (change) return;
    let active = true;
    if (!initialization.current) {
      const params = new URLSearchParams(window.location.search);
      const code = params.getAll('code');
      const callbackError = params.has('error') || params.has('error_code') || window.location.hash;
      // Keep callback codes out of subsequent browser history and referrers.
      if (!forgot) window.history.replaceState(null, '', '/reset-password');
      initialization.current = (async () => {
        if (!forgot && (callbackError || code.length > 1)) throw new Error('This reset link is invalid or expired. Request a new link.');
        if (!forgot && code.length === 1) return mutation({ action: 'exchange', code: code[0] });
        const response = await fetch(`/api/auth/password${forgot ? '?intent=request' : ''}`, { credentials: 'same-origin', cache: 'no-store' });
        const body = await response.json();
        if (!response.ok) throw new Error(body.error || 'Unable to check your reset request.');
        return forgot ? { ...body, stage: body.pending ? 'sent' : 'request' } : body;
      })();
    }
    initialization.current.then(body => { if (active) setState(body); }).catch(failure => {
      if (active) { setError(failure.message); setState({ stage: 'failure' }); }
    });
    return () => { active = false; };
  }, [change, forgot]);
  useEffect(() => {
    if (!state.cooldown) return;
    const timer = setInterval(() => setState(value => ({ ...value, cooldown: Math.max(0, (value.cooldown || 0) - 1) })), 1000);
    return () => clearInterval(timer);
  }, [state.cooldown]);

  async function submit(event) {
    event.preventDefault();
    if (busy) return;
    const form = event.currentTarget;
    const fields = new FormData(form);
    const action = forgot ? 'request' : state.stage === 'mfa' ? 'verify' : change ? 'change' : 'reset';
    const password = fields.get('password');
    if (['reset', 'change'].includes(action)) {
      if (password !== fields.get('confirmation')) { setError('Passwords must match.'); return; }
      if ([...password].length < 8 || new TextEncoder().encode(password).length > 72 ||
          !/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password) || !/[!"#$%&'()*+,\-./:;<=>?@[\]\\^_`{|}~]/.test(password)) {
        setError(policy); return;
      }
      if (change && password === fields.get('currentPassword')) { setError('Choose a different new password.'); return; }
    }
    setBusy(true); setError('');
    try {
      const result = await mutation({ action, ...(action === 'request' ? { email: fields.get('email'), startOver: state.pending === true }
        : action === 'verify' ? { factorId: fields.get('factorId'), code: fields.get('code') }
        : { password, ...(change ? { currentPassword: fields.get('currentPassword') } : {}) }) });
      form.reset();
      setState({ ...result, pending: action === 'request', factors: result.factors || [] });
    } catch (failure) {
      if (action === 'reset' || action === 'change') form.reset();
      setError(failure.message || 'The request could not be confirmed. Check before trying again.');
      if (action === 'reset') setState({ stage: 'failure' });
    } finally { setBusy(false); }
  }
  async function leave() {
    if (busy) return;
    setBusy(true); setError('');
    try { await mutation({ action: 'cancel' }); window.location.replace('/login'); }
    catch (failure) { setError(failure.message); setBusy(false); }
  }
  const updated = state.stage === 'updated';
  const title = updated ? 'Password Updated' : change ? 'Change Password' : forgot ? state.stage === 'sent' ? 'Check Your Email' : 'Forgot Password'
    : state.stage === 'mfa' ? 'Verify Your Authenticator' : 'Create New Password';
  const description = updated ? change ? 'Your password has been updated.' : 'Sign in with your new password.'
    : change ? 'Confirm your current password, then choose a new one.'
    : forgot ? state.stage === 'sent' ? 'If this address is eligible, a reset link may arrive.' : 'Request a reset link for your administrator account.'
    : state.stage === 'mfa' ? 'Verify your existing authenticator before resetting your password.' : 'Choose a new password for your VisionPark account.';
  return <>
    <header className={styles.intro}><div className={extra.icon} aria-hidden="true">
      <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"><rect x="5" y="10" width="14" height="11" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3" /></svg>
    </div><h1>{title}</h1><p className={styles.description}>{description}</p></header>
    <div className={extra.stack} aria-busy={busy || state.stage === 'loading'}>
      {error && <p className={styles.error} role="alert">{error}</p>}
      {state.stage === 'loading' && <p className={styles.status} role="status">Checking your reset request…</p>}
      {forgot && state.stage === 'sent' && <>
        <div className={extra.notice}>Check your inbox and spam. Open the link in this browser, where you requested it. A password reset keeps your authenticator enabled.</div>
        <button className={styles.submit} type="button" disabled={busy || state.cooldown > 0}
          onClick={() => setState(value => ({ ...value, pending: true, stage: 'request' }))}>Start Over</button>
      </>}
      {forgot && state.stage === 'request' && <form className={styles.form} onSubmit={submit}>
        <div className={styles.field}><label htmlFor="reset-email">Email</label><input id="reset-email" name="email" type="email" autoComplete="email" autoCapitalize="none" spellCheck={false} required maxLength={254} placeholder="you@email.com" disabled={busy} /></div>
        {state.pending && <p className={extra.notice}>Starting over discards the previous request in this browser. Earlier links will stop working here.</p>}
        <button className={styles.submit} disabled={busy || state.cooldown > 0}>{busy ? 'Sending…' : 'Send Reset Link'}</button>
      </form>}
      {state.cooldown > 0 && <p className={extra.notice} role="status">Retry available in {state.cooldown}s. Email limits may require a longer wait.</p>}
      {!forgot && state.stage === 'mfa' && <form className={styles.form} onSubmit={submit}>
        {state.factors.length === 1 ? <input type="hidden" name="factorId" value={state.factors[0].id} /> : <div className={styles.field}><label htmlFor="factorId">Authenticator</label><select id="factorId" name="factorId" disabled={busy}>{state.factors.map(factor => <option key={factor.id} value={factor.id}>{factor.friendly_name || 'Authenticator'}</option>)}</select></div>}
        <div className={styles.field}><label htmlFor="reset-code">Six-Digit Code</label><input id="reset-code" name="code" inputMode="numeric" autoComplete="one-time-code" pattern="[0-9]{6}" maxLength={6} required disabled={busy} /></div>
        <button className={styles.submit} disabled={busy}>{busy ? 'Verifying…' : 'Verify and Continue'}</button>
        <p className={extra.help}>Lost your authenticator? Contact your VisionPark operator for identity-verified recovery.</p>
      </form>}
      {!forgot && state.stage === 'ready' && <form className={styles.form} onSubmit={submit}>
        {change && <PasswordField name="currentPassword" label="Current Password" current pending={busy} />}
        <PasswordField name="password" label="New Password" pending={busy} />
        <PasswordField name="confirmation" label="Confirm Password" pending={busy} />
        <p id="password-policy" className={extra.help}>{policy}</p>
        <button className={styles.submit} disabled={busy}>{busy ? 'Updating…' : 'Update Password'}</button>
      </form>}
      {!change && !forgot && ['link', 'failure'].includes(state.stage) && <Link className={extra.outline} href="/forgot-password">Request New Link</Link>}
      {forgot && state.stage === 'failure' && <button className={extra.outline} type="button" onClick={() => window.location.reload()}>Try Again</button>}
      {change ? <Link className={extra.outline} href="/overview">{updated ? 'Back to Overview' : 'Cancel'}</Link>
        : <button className={extra.outline} type="button" disabled={busy} onClick={leave}>Back to Sign In</button>}
    </div>
  </>;
}
