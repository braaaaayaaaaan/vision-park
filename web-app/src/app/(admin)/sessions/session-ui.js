import MetricIcon from '../../../components/metric-icon';
import { sessionLabels } from './sessions-client.mjs';
import overview from '../overview/overview.module.css';
import shared from '../approvals/approvals.module.css';
import common from '../vehicles/vehicles.module.css';
import local from './sessions.module.css';

export function SessionSummary({ resource, onRetry }) {
  const metrics = [
    ['allocated', 'allocated', 'Assigned and awaiting parking confirmation'],
    ['occupied', 'occupancy', 'Parking confirmed for the session'],
    ['completed', 'completed', 'Completed parking sessions'],
    ['cancelled', 'cancelled', 'Cancelled parking sessions'],
  ];
  return <section className={local.summary} aria-label="Parking Session Summary" aria-busy={resource.loading}>
    <p className={local.note}>Session counts across all pages. Plate, level and date filters apply; all statuses are included.</p>
    <div className={`${overview.kpis} ${overview.alignedKpis}`}>
      {metrics.map(([status, icon, description]) => <article key={status} className={`${overview.kpi} ${overview.overviewStat}`}>
        <div className={overview.statHeader}><MetricIcon name={icon} large solid /><h2>{sessionLabels[status]}</h2></div>
        <strong className={resource.loading ? common.skeletonNumber : undefined}>{resource.loading ? <span className={shared.srOnly}>Loading {sessionLabels[status]}</span> :
          resource.data ? resource.data[status].toLocaleString('en-MY') : '—'}</strong>
        <p>{description}</p>
      </article>)}
    </div>
    {resource.error && <div className={local.summaryError}><p className={shared.error} role="alert">Unable to load session counts. Session records are still available.</p>
      <button type="button" className={shared.secondary} onClick={onRetry}>Retry Session Counts</button></div>}
  </section>;
}

export function SessionStatusBadge({ status }) {
  return <span className={local.statusBadge} data-status={status}><span aria-hidden="true" />{sessionLabels[status]}</span>;
}

export function SessionCardHeading({ id, icon, children }) {
  return <div className={local.detailCardHeading}><MetricIcon name={icon} /><h3 id={id}>{children}</h3></div>;
}
