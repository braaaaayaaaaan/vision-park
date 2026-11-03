import BrandMark from './brand-mark';
import PasswordForm from './password-form';
import styles from '../app/login/page.module.css';

export default function PasswordPanel({ mode }) {
  return <div className={styles.page}>
    <header className={styles.topBar}><div className={styles.brand}>
      <span className={styles.brandMark} aria-hidden="true"><BrandMark inverse className={styles.brandImage} /></span>
      <span>VisionPark</span>
    </div></header>
    <main className={styles.main}><div className={styles.content}>
      <section className={styles.panel}><PasswordForm mode={mode} /></section>
    </div></main>
  </div>;
}
