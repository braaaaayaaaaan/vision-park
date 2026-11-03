import { metrics } from '../../../lib/tenant-contracts.mjs';
import common from '../vehicles/vehicles.module.css';
import shared from '../approvals/approvals.module.css';
import styles from './tenants.module.css';
import MetricIcon from '../../../components/metric-icon';
import overview from '../overview/overview.module.css';

export function TenantStatus({ active }) {
  return <span className={active ? shared.badge : common.inactive}>{active ? 'Active' : 'Inactive'}</span>;
}
export function TenantSummary({ data, loading }) {
  return <section className={`${overview.kpis} ${overview.alignedKpis}`} aria-label="Tenant Summary" aria-busy={loading}>
    {metrics.map(([key, label]) => <article className={`${overview.kpi} ${overview.overviewStat}`} key={key}>
      <div className={overview.statHeader}><MetricIcon name={key === 'total_companies' ? 'companies' : key === 'approved_drivers' ? 'approved' : key === 'pending_approvals' ? 'pending' : 'drivers'} large solid /><h2>{label}</h2></div>
      <strong className={loading ? common.skeletonNumber : ''}>{loading ? <span className={shared.srOnly}>Loading {label}</span> : data ? data[key].toLocaleString('en-MY') : '—'}</strong>
      <p>{key === 'total_companies' ? 'Active and inactive companies' : key === 'registered_drivers' ? 'All driver registration statuses' : key === 'approved_drivers' ? 'Approved driver accounts' : 'Awaiting a registration decision'}</p>
    </article>)}
  </section>;
}
export function TenantTable({ companies, onDetails }) {
  return <div className={shared.tableScroll}><table className={`${shared.table} ${styles.table}`}>
    <caption className={shared.srOnly}>Companies and Driver Registrations</caption>
    <thead><tr>{['Company', 'Registered Drivers', 'Approved Drivers', 'Pending Approvals', 'Authorised Zones', 'Status', 'Actions'].map(label => <th scope="col" key={label}>{label}</th>)}</tr></thead>
    <tbody>{companies.map(company => <tr key={company.id}>
      <th scope="row"><button className={styles.nameButton} onClick={event => onDetails(company.id, event.currentTarget)}>{company.name}</button></th>
      <td>{company.registered_drivers}</td><td>{company.approved_drivers}</td><td>{company.pending_approvals}</td><td>{company.zone_count}</td>
      <td><TenantStatus active={company.is_active} /></td>
      <td><button className={shared.secondary} aria-label={`View ${company.name}`} onClick={event => onDetails(company.id, event.currentTarget)}>View Details</button></td>
    </tr>)}</tbody>
  </table></div>;
}
export function DriverStats({ company }) {
  return <section className={styles.driverStats} aria-label="Company Driver Statistics"><h3>Driver Statistics</h3>
    <dl className={styles.stats}>{[['registered_drivers', 'Registered'], ['approved_drivers', 'Approved'], ['pending_approvals', 'Pending'], ['rejected_drivers', 'Rejected']].map(([key, label]) =>
      <div key={key}><dt>{label}</dt><dd>{company[key]}</dd></div>)}</dl>
  </section>;
}

export function ZoneList({ zones, zoneIds, inactive = false }) {
  const allowed = zones.filter(zone => zoneIds.includes(zone.id));
  const levels = [...new Set(allowed.map(zone => zone.level_id))];
  return <section className={styles.zoneSection}><h3>Authorised Parking Levels and Zones</h3>
    <p className={common.muted}>Operates based on a &quot;First Come, First Serve (FCFS)&quot; basis. Authorised companies share each zone&apos;s capacity.</p>
    {inactive && <p className={styles.notice}>This company is inactive. Saved permissions take effect after reactivation.</p>}
    {!allowed.length ? <p className={styles.notice}>No parking zones are authorised. Drivers cannot receive a parking allocation until access is granted.</p> :
      levels.map(level => <div key={level} className={styles.level}><h4>{allowed.find(zone => zone.level_id === level).level_name}</h4>
        <ul>{allowed.filter(zone => zone.level_id === level)
          .sort((left, right) => left.name.localeCompare(right.name, 'en-MY', { sensitivity: 'base', numeric: true }) || left.id.localeCompare(right.id))
          .map(zone => <li key={zone.id}><strong>{zone.name}</strong>
          <span className={common.muted}>{zone.total_capacity} Shared Spaces · {zone.operational_status === 'open' && zone.level_active ? 'Open' : 'Currently Unavailable'}</span>
          <details className={styles.zoneDetails}>
            <summary aria-label={`View More Details for ${zone.name}`}>View More Details</summary>
            <dl className={styles.zoneMetadata}><div><dt>Zone Code</dt><dd><code>{zone.code}</code></dd></div></dl>
          </details>
        </li>)}</ul>
      </div>)}
  </section>;
}
