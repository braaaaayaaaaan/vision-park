import styles from './success-notice.module.css';

export default function SuccessNotice({ children }) {
  return <div className={styles.notice} role="status" aria-live="polite" aria-atomic="true">
    <span className={styles.icon} aria-hidden="true">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" focusable="false">
        <path d="m5 12 4 4L19 6" />
      </svg>
    </span>
    <p className={styles.message}>{children}</p>
  </div>;
}
