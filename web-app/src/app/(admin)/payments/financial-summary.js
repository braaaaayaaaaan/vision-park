'use client';
import { useCallback, useState } from 'react';
import useResource from '../vehicles/use-vehicle-resource';
import { fetchPaymentSummary } from './payments-client.mjs';
import { myr } from '../../../lib/payment-contracts.mjs';
import { PaymentMode, paymentTime } from './payment-ui';
import overview from '../overview/overview.module.css';
import shared from '../approvals/approvals.module.css';
import styles from './payments.module.css';
import MetricIcon from '../../../components/metric-icon';
import OverviewNotice from '../overview/overview-notice';

export function FinancialSummaryView({ data, chart = false }) {
  const t = data.totals;
  const methods = [{ label: 'Wallet Parking Revenue', value: t.wallet_parking_revenue_sen, colour: 'var(--chart-primary)' },
    { label: 'Card Revenue', value: t.mock_card_parking_revenue_sen, colour: 'var(--chart-comparative)' }];
  const maximum = Math.max(1, ...methods.map(row => row.value));
  return <div className={styles.stack}>
    <PaymentMode data={data} />
    <p className={styles.muted}>Last checked: {paymentTime(data.server_time)}</p>
    <div className={`${overview.kpis} ${overview.alignedKpis}`}>
      {[
        ['Parking Revenue', myr(t.parking_revenue_sen), `${t.successful_payments.toLocaleString('en-MY')} successful payments, ${t.zero_fee_payments} with no charge`, 'payments'],
        ['Wallet Top-Ups', myr(t.wallet_top_ups_sen), `${t.wallet_top_up_count.toLocaleString('en-MY')} top-ups`, 'wallet'],
        ['Current Unpaid Charges', myr(t.unpaid_quoted_sen), `${t.unpaid_quoted_charges.toLocaleString('en-MY')} quoted charges across all dates`, 'pending'],
        ['Sessions Awaiting Quotation', t.unquoted_sessions.toLocaleString('en-MY'), 'Current session(s) without a quoted fee', 'sessions'],
      ].map(([title, value, detail, icon]) => <section className={`${overview.kpi} ${overview.overviewStat}`} key={title}>
        <div className={overview.statHeader}><MetricIcon name={icon} large solid /><h3>{title}</h3></div>
        <strong>{value}</strong><p>{detail}</p>
      </section>)}
    </div>
    {chart && <section className={styles.panel} aria-labelledby="payment-method-revenue-title"><h3 id="payment-method-revenue-title">Revenue by Payment Method</h3>
      <p className={styles.muted}>Successful payments only, excluding wallet top-ups.</p>
      {!t.parking_revenue_sen && <OverviewNotice><p>No parking revenue for this period</p></OverviewNotice>}
      <div className={styles.distribution}>{methods.map(row => <div key={row.label} className={styles.distributionRow}>
        <div className={styles.row}><span>{row.label}</span><strong>{myr(row.value)}</strong></div>
        <div className={styles.track} role="img" aria-label={`${row.label}: ${myr(row.value)}`}><span style={{ width: `${row.value / maximum * 100}%`, background: row.colour }} /></div>
      </div>)}</div>
    </section>}
  </div>;
}
export default function FinancialSummary({ query = '', revision = 0, chart = false, live = false }) {
  const [retry, setRetry] = useState(0);
  // Parking level filters deliberately do not apply to building-wide finance.
  const input = new URLSearchParams(query), dates = new URLSearchParams();
  for (const key of ['start_date', 'end_date']) if (input.has(key)) dates.set(key, input.get(key));
  const dateQuery = dates.toString();
  const load = useCallback(signal => fetchPaymentSummary(dateQuery, signal), [dateQuery]);
  const resource = useResource(`finance:${dateQuery}:${revision}:${retry}`, load, live ? 60000 : 0);
  return <section className={styles.stack} aria-labelledby="financial-summary-title" aria-busy={resource.loading}>
    <div><h2 id="financial-summary-title">Payment Summary</h2><p className={styles.muted}>Applicable for all parking levels.{live ? ' Updates every minute, refresh checks immediately.' : ''}</p></div>
    {resource.loading ? <p className={styles.panel} role="status">Loading financial summary…</p> : resource.error ? <div className={styles.panel}>
      <p className={shared.error} role="alert">Unable to load payment summary. Parking reports are still available.</p><button className={shared.secondary} onClick={() => setRetry(value => value + 1)}>Retry Payment Summary</button>
    </div> : <FinancialSummaryView data={resource.data} chart={chart} />}
  </section>;
}
