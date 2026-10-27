import { attemptLabels, methodLabels, myr } from '../../../lib/payment-contracts.mjs';
import { formatMalaysiaDateTime } from '../../../lib/date-format.mjs';
import styles from './payments.module.css';

export function PaymentMode({ data, disclosure = false }) {
  const inactive = data?.payment_mode === 'inactive';
  if (!disclosure && !inactive) return null;
  return <p className={styles.modeNotice}>{disclosure}{inactive && <span>Parking payments are not activated.</span>}</p>;
}

export function PaymentIcon({ kind = 'rates' }) {
  const paths = {
    rates: 'M6 3h12v18l-3-2-3 2-3-2-3 2V3Z M9 7h6 M9 11h6 M9 15h3',
    wallet: 'M3 6h17v14H3V6Z M3 6V4h14 M15 11h5v5h-5v-5Z',
    payment: 'M3 5h18v14H3V5Z M3 9h18 M7 15h4',
    pending: 'M12 8v5l3 2 M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z',
  };
  return <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d={paths[kind] ?? paths.rates} /></svg>;
}

export function CurrentRate({ tariff }) {
  return <section className={styles.currentRate} aria-labelledby="current-rate-title">
    <div className={styles.rateLead}>
      <div className={styles.row}><span className={styles.heroIcon}><PaymentIcon /></span><span className={styles.version}>Version {tariff.version_number}</span></div>
      <h2 id="current-rate-title">Current Rate</h2>
      <strong className={styles.heroAmount}>{myr(tariff.initial_charge_sen)}</strong>
      <p>First {tariff.initial_duration_minutes} Minutes</p>
      <small>Effective {paymentTime(tariff.effective_from)}</small>
    </div>
    <dl className={styles.rateTerms}>{[
      ['Subsequent Hourly Rate', myr(tariff.subsequent_hourly_rate_sen)],
      ['Billing Increment', `${tariff.rounding_minutes} Min`], ['Grace Period', `${tariff.grace_minutes} Min`],
      ['Maximum Fee', tariff.maximum_charge_sen === null ? 'No Maximum' : myr(tariff.maximum_charge_sen)],
    ].map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl>
  </section>;
}

export function PaymentSummaryCards({ data }) {
  const t = data.totals;
  return <div className={styles.summaryCards}>{[
    ['Parking Revenue', myr(t.parking_revenue_sen), 'Successful payments only', 'payment'],
    ['Successful Payments', t.successful_payments.toLocaleString('en-MY'), `${t.zero_fee_payments.toLocaleString('en-MY')} with no charge`, 'rates'],
    ['Outstanding Payments', myr(t.unpaid_quoted_sen), `${t.unpaid_quoted_charges.toLocaleString('en-MY')} quoted charges across all dates`, 'pending'],
    ['Wallet Top-Ups', myr(t.wallet_top_ups_sen), 'Excluded from parking revenue', 'wallet'],
  ].map(([label, value, detail, icon], index) => <section key={label} className={`${styles.summaryCard} ${index === 0 ? styles.featuredSummary : ''}`}>
    <div className={styles.summaryLabel}><h3>{label}</h3><span className={styles.summaryIcon}><PaymentIcon kind={icon} /></span></div>
    <strong className={styles.summaryValue}>{value}</strong><p>{detail}</p>
  </section>)}</div>;
}
export function PaymentBadge({ status }) {
  return <span className={styles.badge} data-status={status} title={status === 'processing' ? 'Payment is processing. It is not confirmed yet.' : undefined}>{attemptLabels[status] ?? status}</span>;
}
export function PaymentFields({ fields }) {
  return <dl className={styles.fields}>{fields.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value ?? 'Not Available'}</dd></div>)}</dl>;
}
export const paymentTime = value => value ? `${formatMalaysiaDateTime(value, { seconds: true })} MYT` : 'Not Available';
export function TariffFields({ tariff }) {
  return <PaymentFields fields={[
    ['Version', `Version ${tariff.version_number}`], ['Effective From', paymentTime(tariff.effective_from)],
    ['Initial Duration', `${tariff.initial_duration_minutes} Min`], ['Initial Fee', myr(tariff.initial_charge_sen)],
    ['Subsequent Hourly Rate', myr(tariff.subsequent_hourly_rate_sen)], ['Billing Increment', `${tariff.rounding_minutes} Min`],
    ['Grace Period', `${tariff.grace_minutes} Min`], ['Maximum Fee', tariff.maximum_charge_sen === null ? 'No Maximum' : myr(tariff.maximum_charge_sen)],
  ]} />;
}
export function TransactionFields({ transaction, grouped = false }) {
  const { attempt: a, charge: c } = transaction;
  const fields = [
    ['Vehicle Plate', c.session.current_vehicle?.plate_number ?? 'Not Available', 'parking'], ['Company', 'Not Available', 'parking'],
    ['Driver', c.current_driver?.full_name ?? 'Not Available', 'parking'], ['Amount', myr(a.amount_sen), 'overview'],
    ['Payment Method', methodLabels[a.method], 'overview'], ['Payment Status', <PaymentBadge key="status" status={a.status} />, 'overview'],
    ['Charge Status', c.status === 'paid' ? 'Paid' : c.status === 'pending' ? 'Pending Payment' : 'Not Yet Quoted', 'payment'],
    ['Current Quoted Charge', c.amount_sen === null ? 'Not Yet Quoted' : myr(c.amount_sen), 'quote'],
    ['Transaction Reference', a.provider_reference, 'payment'], ['Receipt Number', a.receipt_number, 'payment'],
    ['Payment Requested', paymentTime(a.created_at), 'payment'], ['Payment and Exit Time', paymentTime(a.settled_at), 'payment'],
    ['First Exit Detection', paymentTime(c.first_exit_detected_at), 'parking'], ['Current Quotation Valid Until', paymentTime(c.quote_expires_at), 'quote'],
    ['Attempt Quote Revision', String(a.quote_revision), 'quote'], ['Current Quote Revision', String(c.quote_revision), 'quote'], ['Parking Session', c.session_id, 'parking'],
  ];
  if (!grouped) return <PaymentFields fields={fields} />;
  return <div className={styles.detailSections}>{[['Payment Record', 'payment'], ['Vehicle and Parking', 'parking'], ['Quotation', 'quote']].map(([label, key]) => <section key={key}>
    <h3>{label}</h3>{key === 'parking' && <p className={styles.muted}>Vehicle and driver details reflect current records.</p>}
    <PaymentFields fields={fields.filter(field => field[2] === key)} />
  </section>)}</div>;
}
