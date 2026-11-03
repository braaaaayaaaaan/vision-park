"use client";
import BrandMark from "./brand-mark";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { AUTH_GENERATION, logoutAdministrator } from '../lib/auth-client.mjs';
import { formatMalaysiaDateTime } from '../lib/date-format.mjs';
import useSidebarWidth from './use-sidebar-width';
import usePendingApprovals from './use-pending-approvals';
import useApprovalSounds from './use-approval-sounds';
import useConfirmation from './use-confirmation';
import styles from "./admin-shell.module.css";

const navigation = [
  ["/overview", "Overview"], ["/analytics", "Analytics"],
  ["/approvals", "Approvals"], ["/vehicles", "Vehicles"], ["/tenants", "Tenants"],
  ["/sessions", "Sessions"], ["/cameras", "Camera Management"], ["/parking-structure", "Parking Structure"],
  ["/parking-rates", "Parking Rates"], ["/payments", "Payments"],
];

const navigationIcons = {
  "/cameras": "M3 6h13v12H3z M16 10l5-3v10l-5-3 M6 10h6 M6 14h3",
  "/parking-rates": "M4 4h16v16H4z M8 8h8 M8 12h4 M8 16h8",
  "/payments": "M3 5h18v14H3z M3 9h18 M7 15h4",
  "/tenants": "M3 21V7h10v14 M13 3h8v18 M1 21h22 M6 11h4 M6 15h4 M16 7h2 M16 11h2 M16 15h2",
  "/overview": "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z",
  "/analytics": "M3 3v18h18 M7 16v-5 M12 16V7 M17 16V4",
  "/approvals": "M9 4H5v17h14V4h-4 M9 3h6v4H9z M8 14l3 3 5-6",
  "/vehicles": "M5 10l2-6h10l2 6 M3 10h18v8H3z M5 18v3 M19 18v3 M6 14h2 M16 14h2",
  "/sessions": "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0 M12 7v5l3 2",
  "/parking-structure": "M4 21V3h16v18 M2 21h20 M8 7h2 M14 7h2 M8 11h2 M14 11h2 M9 21v-6h6v6",
};

function MalaysiaClock() {
  const [now, setNow] = useState(null);
  useEffect(() => {
    const first = setTimeout(() => setNow(new Date()), 0);
    const timer = setInterval(() => setNow(new Date()), 30000);
    return () => { clearTimeout(first); clearInterval(timer); };
  }, []);
  return <div className={styles.clock}>
    <svg className={styles.clockIcon} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" aria-hidden="true" focusable="false"><path d={navigationIcons['/sessions']} /></svg>
    <div><p className={styles.clockLabel}>Malaysia Time</p><time dateTime={now?.toISOString()}>{now ? `${formatMalaysiaDateTime(now)} MYT` : 'MYT (UTC+08:00)'}</time></div>
  </div>;
}

export default function AdminShell({ children, administrator }) {
  const pathname = usePathname();
  const sidebar = useSidebarWidth();
  const sounds = useApprovalSounds();
  const pending = usePendingApprovals(sounds.notify);
  const account = useRef(null);
  const accountName = administrator?.name || 'Administrator';
  const [menuOpen, setMenuOpen] = useState(false);
  const [signingOut, setSigningOut] = useState(false);
  const { requestConfirmation, confirmationDialog } = useConfirmation({ disabled: signingOut });
  useEffect(() => {
    const sync = event => {
      if (event.key === AUTH_GENERATION && event.oldValue !== null) window.location.reload();
    };
    window.addEventListener('storage', sync);
    return () => window.removeEventListener('storage', sync);
  }, []);
  useEffect(() => {
    const closeOutside = event => {
      if (account.current?.open && !account.current.contains(event.target)) account.current.open = false;
    };
    const closeOnEscape = event => {
      if (event.key === 'Escape' && account.current?.open) {
        account.current.open = false;
        account.current.querySelector('summary')?.focus();
      }
    };
    document.addEventListener('pointerdown', closeOutside);
    document.addEventListener('keydown', closeOnEscape);
    return () => {
      document.removeEventListener('pointerdown', closeOutside);
      document.removeEventListener('keydown', closeOnEscape);
    };
  }, []);
  function requestSignOut() {
    if (account.current) {
      account.current.open = false;
      account.current.querySelector('summary')?.focus();
    }
    requestConfirmation({
      title: 'Sign Out?',
      variant: 'destructive',
      description: 'Are you sure you want to sign out of VisionPark? You will need to sign in again to access the administrator dashboard.',
      confirmLabel: 'Sign Out',
      pendingLabel: 'Signing out…',
      icon: <svg width="23" height="23" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M10 3H4v18h6 M10 12h11 M16 7l5 5-5 5" /></svg>,
    }, signOut);
  }
  async function signOut() {
    if (signingOut) return false;
    setSigningOut(true);
    try {
      const response = await logoutAdministrator();
      if (!response.ok) throw new Error('Unable to sign out. Reload the page and try again.');
      window.location.replace(response.url || '/login');
    } catch (error) {
      setSigningOut(false);
      throw error;
    }
  }
  return (
    <div className={styles.shell} data-admin-shell data-resizing={sidebar.dragging || undefined} style={{ '--sidebar-width': `${sidebar.width}px` }}>
      <a className={styles.skipLink} href="#main-content">Skip to Content</a>
      <aside className={styles.sidebar}>
        <div className={styles.brandRow}>
          <a className={styles.brand} href="/overview" aria-label="VisionPark Overview">
            <span className={styles.brandMark} aria-hidden="true">
              <BrandMark className={styles.brandImage} inverse />
            </span>
            <span>VisionPark<small>Administration</small></span>
          </a>
          <button className={styles.menuButton} type="button" aria-expanded={menuOpen} aria-controls="admin-navigation" onClick={() => setMenuOpen(!menuOpen)}>
            {menuOpen ? "Close Menu" : "Menu"}
          </button>
        </div>
        <nav id="admin-navigation" aria-label="Administration" className={`${styles.navigation} ${menuOpen ? styles.navigationOpen : ""}`}>
          <p className={styles.navLabel}>Workspace</p>
          {navigation.map(([href, label]) => {
            const count = href === '/approvals' ? pending.accounts : href === '/vehicles' ? pending.vehicles : null;
            const description = href === '/approvals' ? 'pending account approvals' : 'pending vehicle registrations';
            return (
              <a key={href} href={href} className={`${styles.navLink} ${pathname === href ? styles.active : ""}`} aria-current={pathname === href ? "page" : undefined}>
                <svg className={styles.navIcon} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
                  <path d={navigationIcons[href]} />
                </svg>
                <span className={styles.navText}>{label}</span>
                {count > 0 && <span className={styles.navBadge} aria-label={`${count} ${description}`} title={`${count} ${description}`}>
                  {count > 99 ? '99+' : count}
                </span>}
              </a>
            );
          })}
        </nav>
        <div className={styles.resizeHandle} {...sidebar.separator} />
      </aside>
      <div className={styles.workspace}>
        <header className={styles.header}>
          <MalaysiaClock />
          <div className={styles.headerActions}>
          <button type="button" className={styles.soundToggle} data-notification-sound-toggle aria-pressed={sounds.enabled}
            aria-label={sounds.enabled ? 'Mute registration notification sounds' : 'Enable registration notification sounds'}
            title={sounds.error || 'Sound for new driver and vehicle registrations. Checks every 30 seconds while this tab is visible.'} onClick={sounds.toggle}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M11 5 6 9H3v6h3l5 4V5Z" />
              {sounds.enabled ? <path d="M15 8a6 6 0 0 1 0 8 M18 5a10 10 0 0 1 0 14" /> : <path d="m16 9 5 6 m0-6-5 6" />}
            </svg>
            <span>{sounds.enabled ? 'Sounds on' : 'Enable sounds'}</span>
          </button>
          {sounds.error && <span className={styles.soundError} role="status">{sounds.error}</span>}
          <details className={styles.account} ref={account}>
            <summary className={styles.accountTrigger} aria-label="Administrator account">
              <span className={styles.avatar} aria-hidden="true"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"><circle cx="12" cy="8" r="4" /><path d="M4 21v-2a8 8 0 0 1 16 0v2" /></svg></span>
              <span className={styles.accountName}>{accountName}</span>
              <svg className={styles.accountChevron} width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" aria-hidden="true"><path d="m6 9 6 6 6-6" /></svg>
            </summary>
            <div className={styles.accountPanel}>
              <p className={styles.accountLabel}>Signed In As</p><p className={styles.accountIdentity}>{accountName}</p>
              <p className={styles.accountRole}>Administrator</p>
              <a className={styles.changePassword} href="/change-password">Change Password</a>
              <button className={styles.signOut} type="button" aria-haspopup="dialog" onClick={requestSignOut} disabled={signingOut}>{signingOut ? 'Signing out…' : 'Sign Out'}</button>
            </div>
          </details>
          </div>
        </header>
        <main id="main-content" tabIndex={-1} className={styles.main}>
          {children}
        </main>
      </div>
      {confirmationDialog}
    </div>
  );
}
