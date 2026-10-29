'use client';
import { useCallback, useState } from 'react';
import useResource from '../vehicles/use-vehicle-resource';
import { findSessionPayment } from '../payments/payments-client.mjs';
import { TransactionFields } from '../payments/payment-ui';
import shared from '../approvals/approvals.module.css';
import styles from '../payments/payments.module.css';
import local from './sessions.module.css';
import { SessionCardHeading } from './session-ui';

export default function SessionPayment({ sessionId }) {
  const [offset, setOffset] = useState(0), [revision, setRevision] = useState(0);
  const load = useCallback(signal => findSessionPayment(sessionId, offset, signal), [sessionId, offset]);
  const resource = useResource(`session-payment:${sessionId}:${offset}:${revision}`, load, 15000), data = resource.data;
  return <section className={`${local.detailCard} ${styles.sessionPayment}`} aria-labelledby="session-payment-title" aria-busy={resource.loading}>
    <SessionCardHeading id="session-payment-title" icon="payments">Payment Information</SessionCardHeading>
    {resource.loading ? <p role="status">Checking payments…</p> : resource.error ? <><p className={styles.muted}>Unable to confirm payment status. Try again.</p><button className={shared.secondary} onClick={() => setRevision(value => value + 1)}>Retry Payment Lookup</button></> : data.transaction ? <TransactionFields transaction={data.transaction} /> : <>
      {data.hasMore ? <><p>More records remain. Check older payments to confirm the status.</p><button className={shared.secondary} disabled={data.nextOffset > 1000000} onClick={() => setOffset(data.nextOffset)}>Check Older Payment Records</button></> : <><strong>Payment Not Recorded</strong><p className={styles.muted}>No transaction found. A charge may still be outstanding.</p></>}
    </>}
  </section>;
}
