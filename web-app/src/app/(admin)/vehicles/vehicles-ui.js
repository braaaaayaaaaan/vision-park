import styles from './vehicles.module.css';
import shared from '../approvals/approvals.module.css';

export const statusLabels = { approved: 'Approved', pending: 'Pending', rejected: 'Rejected' };
const number = value => new Intl.NumberFormat('en').format(value);

export function StatusBadge({ status, children }) {
  return <span className={styles.badge} data-status={status}>{children ?? statusLabels[status]}</span>;
}
export function RegistrationUsage({ counts }) {
  const usage = counts.counted >= counts.limit ? 'full' : counts.counted / counts.limit >= 0.6 ? 'warning' : 'available';
  return <div className={styles.usage} data-limit={counts.limit_reached} data-usage={usage}>
    <div className={styles.usageLabel}><strong>{counts.counted}/{counts.limit} Vehicles</strong>
      {counts.limit_reached && <span className={styles.limit}>Limit Reached</span>}</div>
    <div className={styles.usageSlots} role="meter" aria-label="Registration slots used"
      aria-valuemin={0} aria-valuemax={counts.limit} aria-valuenow={Math.min(counts.counted, counts.limit)}
      aria-valuetext={`${counts.counted} of ${counts.limit} registration slots used`}>
      {Array.from({ length: counts.limit }, (_, index) => <span key={index} aria-hidden="true" data-filled={index < counts.counted} />)}
    </div>
  </div>;
}
export function DriverIdentity({ driver }) {
  return <div className={styles.identity}>
    <strong>{driver.full_name || 'Name Unavailable'}</strong>
    <span className={styles.muted}>{driver.company_name || (driver.tenant_id ? 'Company Unavailable' : 'No Company Assigned')}</span>
    <div className={styles.badges}><StatusBadge status={driver.approval_status}>{statusLabels[driver.approval_status]} Account</StatusBadge>
      {!driver.is_active && <span className={styles.inactive}>Inactive</span>}</div>
  </div>;
}
export function DecisionActions({ vehicle, disabled, onDecision }) {
  if (vehicle.registration_status !== 'pending') return null;
  return <div className={shared.actions}>
    <button className={shared.approve} disabled={disabled} onClick={() => onDecision(vehicle, 'approve')} aria-label={`Approve ${vehicle.plate_number}`}>Approve</button>
    <button className={shared.reject} disabled={disabled} onClick={() => onDecision(vehicle, 'reject')} aria-label={`Reject ${vehicle.plate_number}`}>Reject</button>
  </div>;
}
export function VehiclePagination({ data, offset, loading, disabled, onPage, noun = 'Records' }) {
  const size = data?.limit ?? 25;
  const shown = data?.drivers?.length ?? data?.vehicles?.length ?? 0;
  return <nav className={styles.pagination} aria-label={`${noun} Pagination`}>
    <span>{data ? `${number(data.total)} ${noun.toLowerCase()}${shown ? ` · ${number(offset + 1)}–${number(offset + shown)}` : ''}` : 'Loading records…'} · Page {Math.floor(offset / size) + 1}</span>
    <div className={shared.actions}>
      <button className={shared.secondary} disabled={loading || disabled || offset === 0} onClick={() => onPage(Math.max(0, offset - size))}>Previous</button>
      <button className={shared.secondary} disabled={loading || disabled || !data || offset + size >= data.total} onClick={() => onPage(offset + size)}>Next</button>
    </div>
  </nav>;
}
export function RecordsState({ loading, error, title, message, onRetry, onFirstPage }) {
  return <div className={styles.state}>
    {loading ? <><p role="status">{message || 'Loading registrations…'}</p><div className={styles.skeletonRows} aria-hidden="true"><span /><span /><span /></div></>
      : error ? <><p className={shared.error} role="alert">{error}</p><button className={shared.secondary} onClick={onRetry}>Try Again</button></>
        : <><h2>{title}</h2><p>{message}</p>{onFirstPage && <button className={shared.secondary} onClick={onFirstPage}>First Page</button>}</>}
  </div>;
}
export function VehicleSummaryCards({ resource, tenantName, onRetry }) {
  const metrics = [
    ['registered_vehicles', 'Registered Vehicles', 'Includes rejected registrations'],
    ['approved_vehicles', 'Approved Vehicles', 'Approved registrations'],
    ['pending_approval', 'Pending Approval', 'Awaiting a vehicle decision'],
    ['drivers_at_limit', 'Drivers at Limit', 'Five or more counted registrations'],
  ];
  return <section aria-label="Vehicle Registration Summary" aria-busy={resource.loading}>
    <div className={styles.summaryScope}>{resource.data?.scope.company_name || tenantName || 'All Companies'} <span>· All Registration Statuses</span></div>
    <div className={styles.metrics}>{metrics.map(([key, label, description]) => <article className={styles.metric} key={key}>
      <h2>{label}</h2><strong className={resource.loading ? styles.skeletonNumber : ''}>{resource.loading ? <span className={shared.srOnly}>Loading {label}</span> : resource.data ? number(resource.data[key]) : '—'}</strong>
      <p>{description}</p>
    </article>)}</div>
    {resource.error && <div className={styles.summaryError}><p className={shared.error} role="alert">{resource.error}</p>
      <button className={shared.secondary} onClick={onRetry}>Retry Summary</button></div>}
  </section>;
}
