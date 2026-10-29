import LoginForm from './login-form';
import BrandMark from '../../components/brand-mark';
import { messages } from '@/lib/auth.mjs';
import styles from './page.module.css';

export const metadata = { title: 'Login' };

export default async function LoginPage({ searchParams }) {
  const { reason } = await searchParams;
  const message = reason === 'signout'
    ? 'Signed out of this browser. The authentication service could not confirm remote session revocation.'
    : ['expired', 'denied', 'unavailable'].includes(reason) ? messages[reason] : '';
  return (
    <div className={styles.page}>
      <header className={styles.topBar}>
        <div className={styles.brand}>
          <span className={styles.brandMark} aria-hidden="true">
            <BrandMark inverse className={styles.brandImage} />
          </span>
          <span>VisionPark</span>
        </div>
      </header>
      <main className={styles.main}>
        <div className={styles.content}>
          <section className={styles.panel} aria-labelledby="login-title">
            <header className={styles.intro}>
              <h1 id="login-title">Welcome Back</h1>
              <p className={styles.description}>Sign in to your administrator account.</p>
            </header>
            <LoginForm message={message} />
          </section>
        </div>
      </main>
    </div>
  );
}
