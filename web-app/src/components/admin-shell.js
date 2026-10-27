"use client";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { AUTH_GENERATION, logoutAdministrator } from '../lib/auth-client.mjs';
import styles from "./admin-shell.module.css";

const navigation = [
  ["/overview", "Overview"], ["/analytics", "Analytics"],
  ["/approvals", "Approvals"], ["/vehicles", "Vehicles"], ["/tenants", "Tenants"],
  ["/sessions", "Sessions"], ["/parking-structure", "Parking Structure"],
  ["/parking-rates", "Parking Rates"], ["/payments", "Payments"],
];

const navigationIcons = {
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

export default function AdminShell({ children }) {
  const pathname = usePathname();
  const [menuOpen, setMenuOpen] = useState(false);
  const [signingOut, setSigningOut] = useState(false);
  const [signOutError, setSignOutError] = useState('');
  useEffect(() => {
    const sync = event => {
      if (event.key === AUTH_GENERATION && event.oldValue !== null) window.location.reload();
    };
    window.addEventListener('storage', sync);
    return () => window.removeEventListener('storage', sync);
  }, []);
  async function signOut(event) {
    event.preventDefault();
    if (signingOut) return;
    setSigningOut(true);
    setSignOutError('');
    try {
      const response = await logoutAdministrator();
      if (!response.ok) throw new Error('Unable to sign out. Reload the page and try again.');
      window.location.replace(response.url || '/login');
    } catch (error) {
      setSignOutError(error.message || 'Unable to sign out. Please try again.');
      setSigningOut(false);
    }
  }
  const title = navigation.find(([href]) => href === pathname)?.[1] ?? "Administration";
  return (
    <div className={styles.shell}>
      <a className={styles.skipLink} href="#main-content">Skip to Content</a>
      <aside className={styles.sidebar}>
        <div className={styles.brandRow}>
          <a className={styles.brand} href="/overview" aria-label="VisionPark Overview">
            <span className={styles.brandMark} aria-hidden="true">V</span>
            <span>VisionPark<small>Administration</small></span>
          </a>
          <button className={styles.menuButton} type="button" aria-expanded={menuOpen} aria-controls="admin-navigation" onClick={() => setMenuOpen(!menuOpen)}>
            {menuOpen ? "Close Menu" : "Menu"}
          </button>
        </div>
        <nav id="admin-navigation" aria-label="Administration" className={`${styles.navigation} ${menuOpen ? styles.navigationOpen : ""}`}>
          <p className={styles.navLabel}>Workspace</p>
          {navigation.map(([href, label]) => (
            <a key={href} href={href} className={`${styles.navLink} ${pathname === href ? styles.active : ""}`} aria-current={pathname === href ? "page" : undefined}>
              <svg className={styles.navIcon} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">
                <path d={navigationIcons[href]} />
              </svg>
              {label}
            </a>
          ))}
        </nav>
      </aside>
      <div className={styles.workspace}>
        <header className={styles.header}>
          <div><p className={styles.eyebrow}>VisionPark Admin</p><p className={styles.pageTitle}>{title}</p></div>
          <form action="/api/auth/logout" method="post" onSubmit={signOut}>
            <button className={styles.signOut} type="submit" disabled={signingOut}>{signingOut ? 'Signing out…' : 'Sign Out'}</button>
            {signOutError && <p role="alert">{signOutError}</p>}
          </form>
        </header>
        <main id="main-content" tabIndex={-1} className={styles.main}>
          {children}
        </main>
      </div>
    </div>
  );
}
