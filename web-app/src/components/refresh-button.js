'use client';
import styles from './refresh-button.module.css';

export default function RefreshButton({ onClick, loading = false, disabled = false, label = 'Refresh' }) {
  return <button type="button" className={styles.button} onClick={onClick} disabled={disabled || loading} aria-label={label} aria-busy={loading}>
    <span className={styles.icon} aria-hidden="true"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
      <path d="M20 7v5h-5 M4 17v-5h5 M6.1 6.1A8 8 0 0 1 19.7 9 M4.3 15a8 8 0 0 0 13.6 2.9" />
    </svg></span>
    <span>{loading ? 'Refreshing…' : label}</span>
  </button>;
}
