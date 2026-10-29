'use client';
import RefreshButton from '../../../components/refresh-button';
import { useCallback, useState } from 'react';
import useResource from '../vehicles/use-vehicle-resource';
import { RecordsState } from '../vehicles/vehicles-ui';
import { fetchTariffs } from '../payments/payments-client.mjs';
import { PaymentMode, CurrentRate, paymentTime } from '../payments/payment-ui';
import { myr } from '../../../lib/payment-contracts.mjs';
import RateEditor from './rate-editor';
import common from '../vehicles/vehicles.module.css';
import shared from '../approvals/approvals.module.css';
import styles from '../payments/payments.module.css';

export default function ParkingRates() {
  const [offset, setOffset] = useState(0), [revision, setRevision] = useState(0), [editing, setEditing] = useState(false), [message, setMessage] = useState('');
  const load = useCallback(signal => fetchTariffs(offset, signal), [offset]);
  const resource = useResource(`tariffs:${offset}:${revision}`, load), data = resource.data;
  const refresh = () => setRevision(value => value + 1);
  return <div className={`${common.page} ${styles.page}`}>
    <header className={common.heading}><h1>Parking Rates</h1>
      <RefreshButton loading={resource.loading} onClick={refresh} /></header>
    <div className={shared.actions}><button className={shared.primary} disabled={editing} onClick={() => setEditing(true)}>Publish New Rates</button></div>
    <PaymentMode data={data} />
    {message && <p className={shared.success} role="status">{message}</p>}
    {editing && <RateEditor onClose={() => setEditing(false)} onSaved={tariff => { setEditing(false); setOffset(0); refresh(); setMessage(`Version ${tariff.version_number} published.`); }} />}
    {resource.loading || resource.error ? <RecordsState loading={resource.loading} error={resource.error} message="Loading parking rates…" onRetry={refresh} /> : <>
      {data.effective_tariff ? <CurrentRate tariff={data.effective_tariff} /> : <section className={styles.panel}><h2>Current Rate</h2><p className={styles.muted}>No rates are currently in effect.</p></section>}
      <section className={shared.card} aria-label="Rate History"><div className={styles.sectionHeading}><div><h2>Rate History</h2><p className={styles.muted}>Published rates cannot be changed, existing sessions keep their assigned rates.</p></div><span className={styles.muted}>MYT</span></div>
        {!data.tariffs.length ? <RecordsState title="No Rates Published" message="Publish rates to get started." /> : <div className={shared.tableScroll}><table className={`${shared.table} ${styles.rateTable}`}>
          <thead><tr>{['Version', 'Effective From (MYT)', 'Initial Charge', 'Hourly Rate', 'Billing Increment', 'Grace Period', 'Maximum Fee', 'Published'].map(label => <th scope="col" key={label}>{label}</th>)}</tr></thead>
          <tbody>{data.tariffs.map(row => <tr key={row.id}><td><div className={styles.rateVersion}><strong>Version {row.version_number}</strong><span className={styles.badge}>{data.effective_tariff?.id === row.id ? 'Current' : Date.parse(row.effective_from) > Date.parse(data.server_time) ? 'Scheduled' : 'Historical'}</span></div></td>
            <td>{paymentTime(row.effective_from)}</td><td>{myr(row.initial_charge_sen)}<br /><small>{row.initial_duration_minutes} Min</small></td><td>{myr(row.subsequent_hourly_rate_sen)}</td><td>{row.rounding_minutes} Min</td><td>{row.grace_minutes} Min</td><td>{row.maximum_charge_sen === null ? 'No Maximum' : myr(row.maximum_charge_sen)}</td><td>{paymentTime(row.published_at)}</td></tr>)}</tbody>
        </table></div>}
        <nav className={common.pagination} aria-label="Tariff Pagination"><span>{data.total} versions · Page {offset / 25 + 1}</span><div className={shared.actions}>
          <button className={shared.secondary} disabled={!offset} onClick={() => setOffset(value => value - 25)}>Previous</button><button className={shared.secondary} disabled={!data.has_more} onClick={() => setOffset(value => value + 25)}>Next</button></div></nav>
      </section>
    </>}
  </div>;
}
