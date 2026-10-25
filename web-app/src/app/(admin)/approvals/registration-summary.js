import shared from './approvals.module.css';
import styles from './registration-approvals.module.css';
import vehicles from '../vehicles/vehicles.module.css';

const number = value => new Intl.NumberFormat('en').format(value);
export default function RegistrationSummary({ resource, locked, onRetry }) {
  const data = resource.data;
  const metrics = [
    ['total_registrations', 'Driver Registrations', 'All driver registration statuses'],
    ['pending_approvals', 'Pending Approvals', 'Awaiting an administrator decision'],
    ['approved_accounts', 'Approved Accounts', 'Drivers with approved registrations'],
    ['represented_companies', 'Companies Represented', 'Companies associated with registered drivers'],
  ];
  const represented = data?.companies.filter(company => company.total > 0) ?? [];
  return <section aria-label="Driver Registration Summary" aria-busy={resource.loading}>
    <p className={vehicles.summaryScope}>All Companies</p>
    <div className={vehicles.metrics}>{metrics.map(([key, label, description]) => <article key={key} className={vehicles.metric}>
      <h2>{label}</h2><strong className={resource.loading ? vehicles.skeletonNumber : undefined}>
        {resource.loading ? <span className={shared.srOnly}>Loading {label}</span> : data ? number(data[key]) : '—'}
      </strong><p>{description}</p>
    </article>)}</div>
    {resource.error && <div className={vehicles.summaryError}><p className={shared.error} role="alert">{resource.error}</p>
      <button className={shared.secondary} disabled={locked} onClick={onRetry}>Retry Summary</button></div>}
    {data && <details className={styles.companyBreakdown}>
      <summary>Company Breakdown <span className={vehicles.muted}>{number(data.total_registrations)} Driver Registrations</span></summary>
      <div className={styles.breakdownContent}>
        <p className={vehicles.muted}>Approved drivers use their assigned company. Counts include every page.</p>
        {!data.total_registrations ? <p>No driver registrations yet.</p> : <div className={styles.breakdownScroll} tabIndex={0} aria-label="Scrollable Company Registration Breakdown">
          <table className={`${shared.table} ${styles.breakdownTable}`}>
            <caption className={shared.srOnly}>Full Driver Registration Counts by Company</caption>
            <thead><tr><th scope="col">Company</th><th scope="col">Drivers</th><th scope="col">Pending</th><th scope="col">Approved</th></tr></thead>
            <tbody>{represented.map(company => <tr key={company.id}><th scope="row">{company.name}</th>
              <td>{number(company.total)}</td><td>{number(company.pending)}</td><td>{number(company.approved)}</td></tr>)}
              {data.unassigned_drivers > 0 && <tr><th scope="row">Unassigned</th><td>{number(data.unassigned_drivers)}</td>
                <td>{number(data.pending_approvals - represented.reduce((sum, company) => sum + company.pending, 0))}</td>
                <td>{number(data.approved_accounts - represented.reduce((sum, company) => sum + company.approved, 0))}</td></tr>}
            </tbody>
          </table>
        </div>}
      </div>
    </details>}
  </section>;
}
