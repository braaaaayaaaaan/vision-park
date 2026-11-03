import PasswordPanel from '../../components/password-panel';
export const metadata = { title: 'Forgot Password', robots: { index: false, follow: false }, referrer: 'no-referrer' };
export default function ForgotPasswordPage() { return <PasswordPanel mode="forgot" />; }
