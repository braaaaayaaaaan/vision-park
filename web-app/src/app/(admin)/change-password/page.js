import PasswordForm from '../../../components/password-form';
import styles from '../../../components/password-form.module.css';
export const metadata = { title: 'Change Password' };
export default function ChangePasswordPage() { return <section className={styles.changeCard}><PasswordForm mode="change" /></section>; }
