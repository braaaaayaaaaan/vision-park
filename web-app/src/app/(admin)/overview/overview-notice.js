import styles from './overview.module.css';

export default function OverviewNotice({ children, className = '' }) {
  return <div className={`${styles.notice} ${className}`} role="status">
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden="true" focusable="false">
      <circle cx="12" cy="12" r="9" /><path d="M12 7v6 M12 17h.01" />
    </svg>
    <div className={styles.noticeContent}>{children}</div>
  </div>;
}
