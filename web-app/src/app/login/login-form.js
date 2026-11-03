"use client";
import { useState } from 'react';
import Link from 'next/link';
import { loginAdministrator } from '../../lib/auth-client.mjs';
import styles from './page.module.css';

export default function LoginForm({ message }) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState(message);
  const [passwordVisible, setPasswordVisible] = useState(false);

  async function signIn(event) {
    event.preventDefault();
    if (pending) return;
    const form = event.currentTarget;
    const data = new FormData(form);
    setPending(true);
    setError('');
    setPasswordVisible(false);
    try {
      const response = await loginAdministrator({ email: data.get('email'), password: data.get('password') });
      form.elements.password.value = '';
      if (!response.ok) {
        const result = await response.json();
        setError(result.error || 'Unable to sign in. Please try again.');
        setPending(false);
        return;
      }
      // A full navigation discards any previously cached administrator UI.
      const result = await response.json();
      window.location.replace(result.next === '/mfa' ? '/mfa' : '/overview');
    } catch (failure) {
      form.elements.password.value = '';
      setError(failure.message || 'Unable to connect. Check your connection and try again.');
      setPending(false);
    }
  }

  return (
    <form className={styles.form} onSubmit={signIn} aria-busy={pending}>
      <div className={styles.field}>
        <label htmlFor="email">Email</label>
        <input id="email" name="email" type="email" inputMode="email" autoComplete="username" autoCapitalize="none" spellCheck={false} placeholder="you@email.com" maxLength={254} required disabled={pending} aria-describedby={error ? 'login-error' : undefined} />
      </div>
      <div className={styles.field}>
        <label htmlFor="password">Password</label>
        <div className={styles.passwordField}>
          <input id="password" name="password" type={passwordVisible ? 'text' : 'password'} autoComplete="current-password" placeholder="Enter your password" maxLength={4096} required disabled={pending} aria-describedby={error ? 'login-error' : undefined} />
          <button className={styles.visibility} type="button" aria-controls="password" aria-label={passwordVisible ? 'Hide password' : 'Show password'} aria-pressed={passwordVisible} disabled={pending} onClick={() => setPasswordVisible(value => !value)}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
              {passwordVisible ? <><path d="m3 3 18 18M10.6 10.6a2 2 0 0 0 2.8 2.8M9.9 5.3A10.9 10.9 0 0 1 12 5c5.5 0 9 7 9 7a16.8 16.8 0 0 1-3 3.9M6.6 6.6A19.4 19.4 0 0 0 3 12s3.5 7 9 7a10.3 10.3 0 0 0 5.4-1.6" /></> : <><path d="M3 12s3.5-7 9-7 9 7 9 7-3.5 7-9 7-9-7-9-7Z" /><circle cx="12" cy="12" r="3" /></>}
            </svg>
          </button>
        </div>
      </div>
      <Link className={styles.forgot} href="/forgot-password">Forgot Password?</Link>
      {error && <p id="login-error" className={styles.error} role="alert">{error}</p>}
      <button className={styles.submit} type="submit" disabled={pending}>{pending ? 'Signing in…' : 'Sign In'}</button>
      <p className={styles.status} role="status">{pending ? 'Verifying administrator access…' : ''}</p>
    </form>
  );
}
