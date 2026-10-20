import styles from "./page-placeholder.module.css";
export default function PagePlaceholder({ title, children }) {
  return <section className={styles.panel}><span className={styles.accent} aria-hidden="true" /><h1>{title}</h1><p>{children}</p></section>;
}
