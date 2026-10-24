"use client";
import { useState } from 'react';
import styles from './page.module.css';

export default function LoginForm({ message }) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState(message);

  async function signIn(event) {
    event.preventDefault();
    if (pending) return;
    const form = event.currentTarget;
    const data = new FormData(form);
    setPending(true);
    setError('');
    try {
      const response = await fetch('/api/auth/login', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: data.get('email'), password: data.get('password') }),
      });
      form.elements.password.value = '';
      if (!response.ok) {
        const result = await response.json();
        setError(result.error || 'Unable to sign in. Please try again.');
        setPending(false);
        return;
      }
      // A full navigation discards any previously cached administrator UI.
      window.location.replace('/overview');
    } catch {
      form.elements.password.value = '';
      setError('Unable to connect. Check your connection and try again.');
      setPending(false);
    }
  }

  return (
    <form className={styles.form} onSubmit={signIn} aria-busy={pending}>
      <label htmlFor="email">Email</label>
      <input id="email" name="email" type="email" autoComplete="username" maxLength={254} required disabled={pending} />
      <label htmlFor="password">Password</label>
      <input id="password" name="password" type="password" autoComplete="current-password" maxLength={4096} required disabled={pending} />
      {error && <p className={styles.error} role="alert">{error}</p>}
      <button type="submit" disabled={pending}>{pending ? 'Signing in…' : 'Sign In'}</button>
      <p className={styles.status} role="status">{pending ? 'Verifying administrator access…' : ''}</p>
    </form>
  );
}
