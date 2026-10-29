'use client';
import RefreshButton from '../../../components/refresh-button';
import { useCallback, useState } from 'react';
import useResource from '../vehicles/use-vehicle-resource';
import { RecordsState } from '../vehicles/vehicles-ui';
import { fetchTransactions, fetchPaymentSummary, transactionQuery } from './payments-client.mjs';
import { attemptLabels, methodLabels, myr } from '../../../lib/payment-contracts.mjs';
import { malaysiaToday } from '../analytics/analytics-client.mjs';
import { PaymentMode, PaymentBadge, PaymentSummaryCards, paymentTime } from './payment-ui';
import TransactionDetails from './transaction-details';
import common from '../vehicles/vehicles.module.css';
import shared from '../approvals/approvals.module.css';
import styles from './payments.module.css';

export const initialPaymentFilters = { reference: '', status: '', method: '', driver_id: '', start_date: '', end_date: '' };
export function PaymentTable({ transactions, onDetails }) {
  return <div className={shared.tableScroll}><table className={`${shared.table} ${styles.paymentTable}`}><thead><tr>{['Vehicle Plate', 'Company', 'Amount', 'Payment Method', 'Payment Status', 'Transaction Reference', 'Requested (MYT)', 'Actions'].map(label => <th scope="col" key={label}>{label}</th>)}</tr></thead>
    <tbody>{transactions.map(({ attempt: a, charge: c }) => <tr key={a.id}>
      <td><strong>{c.session.current_vehicle?.plate_number ?? 'Not Available'}</strong></td><td>{c.current_driver?.tenant?.name || 'Not Provided'}</td><td className={styles.amount}>{myr(a.amount_sen)}</td><td>{methodLabels[a.method]}</td><td><PaymentBadge status={a.status} /></td>
      <td className={styles.reference}>{a.provider_reference}</td><td>{paymentTime(a.created_at)}</td><td><button className={shared.secondary} aria-label={`View Payment ${a.provider_reference}`} onClick={event => onDetails(a.id, event.currentTarget)}>View Details</button></td>
    </tr>)}</tbody>
  </table></div>;
}
export default function Payments() {
  const [draft, setDraft] = useState(initialPaymentFilters), [applied, setApplied] = useState(initialPaymentFilters), [offset, setOffset] = useState(0);
  const [revision, setRevision] = useState(0), [error, setError] = useState(''), [selected, setSelected] = useState(null);
  const query = transactionQuery(applied, offset);
  const load = useCallback(signal => fetchTransactions(query, signal), [query]);
  const resource = useResource(`payments:${query}:${revision}`, load, 15000), data = resource.data;
  const summaryQuery = new URLSearchParams(applied.start_date ? { start_date: applied.start_date, end_date: applied.end_date } : {}).toString();
  const loadSummary = useCallback(signal => fetchPaymentSummary(summaryQuery, signal), [summaryQuery]);
  const summary = useResource(`payments-summary:${summaryQuery}:${revision}`, loadSummary, 15000);
  function apply(event) {
    event.preventDefault(); try { transactionQuery(draft); setError(''); setApplied({ ...draft }); setOffset(0); setRevision(value => value + 1); } catch (cause) { setError(cause.message); }
  }
  const field = (key, value) => setDraft(old => ({ ...old, [key]: value }));
  const refresh = () => setRevision(value => value + 1);
  return <div className={`${common.page} ${styles.page}`}>
    <header className={common.heading}><h1>Payments</h1><RefreshButton loading={resource.loading} onClick={refresh} /></header>
    <section className={styles.summarySection} aria-labelledby="payment-summary-title" aria-busy={summary.loading}>
      <div className={styles.summaryHeading}><h2 id="payment-summary-title">Payment Summary</h2><span>{applied.start_date ? `${applied.start_date} to ${applied.end_date} · MYT` : 'Last 7 Days · MYT'}</span></div>
      {summary.loading ? <p className={styles.muted} role="status">Loading payment summary…</p> : summary.error ? <div className={styles.summaryError}><p role="alert">Payment summary is unavailable.</p><button className={shared.secondary} onClick={refresh}>Retry Summary</button></div> : <PaymentSummaryCards data={summary.data} />}
    </section>
    <PaymentMode data={data ?? summary.data} disclosure={!selected} />
    <section className={common.workspace} aria-label="Payment Transactions" aria-busy={resource.loading}>
      <div className={common.toolbar}><div className={styles.summaryHeading}><h2>Payment Transactions</h2>{data && <span>{data.total.toLocaleString('en-MY')} Transactions</span>}</div><form className={`${common.filters} ${styles.filters}`} onSubmit={apply}>
        <label className={styles.searchField}>Transaction or Receipt Reference<input type="search" maxLength={100} value={draft.reference} onChange={event => field('reference', event.target.value)} placeholder="Search by Reference" /></label>
        <label>Payment Status<select value={draft.status} onChange={event => field('status', event.target.value)}><option value="">All Statuses</option>{Object.entries(attemptLabels).map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select></label>
        <label>Payment Method<select value={draft.method} onChange={event => field('method', event.target.value)}><option value="">All Methods</option>{Object.entries(methodLabels).map(([value, label]) => <option value={value} key={value}>{label}</option>)}</select></label>
        <label>Driver ID (Optional)<input value={draft.driver_id} maxLength={36} onChange={event => field('driver_id', event.target.value)} placeholder="Enter Driver ID" /></label>
        <label>Start Date<input type="date" min="1982-01-01" max={malaysiaToday()} value={draft.start_date} onChange={event => field('start_date', event.target.value)} /></label>
        <label>End Date<input type="date" min={draft.start_date || '1982-01-01'} max={malaysiaToday()} value={draft.end_date} onChange={event => field('end_date', event.target.value)} /></label>
        <div className={common.filterActions}><button className={shared.primary} disabled={resource.loading}>Apply Filters</button><button className={shared.secondary} type="button" disabled={resource.loading} onClick={() => { setDraft(initialPaymentFilters); setApplied(initialPaymentFilters); setOffset(0); setError(''); refresh(); }}>Clear Filters</button></div>
      </form><p className={styles.muted}>Dates filter payment requests in Malaysia time.</p>{error && <p role="alert" className={shared.error}>{error}</p>}</div>
      {resource.loading || resource.error ? <RecordsState loading={resource.loading} error={resource.error} message="Loading payment transactions…" onRetry={refresh} /> : !data.transactions.length ?
        <RecordsState title={offset ? 'No Payments on This Page' : 'No Payments Found'} message="Change the filters or return to the first page." onFirstPage={offset ? () => setOffset(0) : null} /> :
        <PaymentTable transactions={data.transactions} onDetails={(id, trigger) => setSelected({ id, trigger })} />}
      <nav className={common.pagination} aria-label="Payment Pagination"><span>{data ? `${data.total} matching transactions · Page ${offset / 25 + 1}` : 'Checking payment transactions…'}</span><div className={shared.actions}>
        <button className={shared.secondary} disabled={resource.loading || !offset} onClick={() => setOffset(value => value - 25)}>Previous</button><button className={shared.secondary} disabled={resource.loading || !data?.has_more} onClick={() => setOffset(value => value + 25)}>Next</button></div></nav>
    </section>
    {selected && <TransactionDetails key={selected.id} attemptId={selected.id} trigger={selected.trigger} onClose={() => setSelected(null)} />}
  </div>;
}
