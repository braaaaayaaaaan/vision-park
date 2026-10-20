import LoginForm from './login-form';
import { messages } from '@/lib/auth.mjs';
import styles from './page.module.css';

export const metadata = { title: 'Login' };

export default async function LoginPage({ searchParams }) {
  const { reason } = await searchParams;
  const message = reason === 'signout'
    ? 'Signed out of this browser. The authentication service could not confirm remote session revocation.'
    : ['expired', 'denied', 'unavailable'].includes(reason) ? messages[reason] : '';
  return (
    <main className={styles.page}>
      <div className={styles.content}>
        <p className={styles.brand}>VisionPark</p>
        <section className={styles.panel}>
          <h1>Admin Login</h1>
          <LoginForm message={message} />
        </section>
      </div>
    </main>
  );
}
