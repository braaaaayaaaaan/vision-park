'use client';
import { useCallback, useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import useResource from '../vehicles/use-vehicle-resource';
import { fetchTransaction } from './payments-client.mjs';
import { PaymentMode, PaymentBadge, TransactionFields, TariffFields } from './payment-ui';
import { methodLabels, myr } from '../../../lib/payment-contracts.mjs';
import shared from '../approvals/approvals.module.css';
import styles from './payments.module.css';

export default function TransactionDetails({ attemptId, onClose, trigger }) {
  const dialog = useRef(null), close = useRef(null);
  const load = useCallback(signal => fetchTransaction(attemptId, signal), [attemptId]);
  const resource = useResource(`transaction:${attemptId}`, load);
  useEffect(() => {
    const element = dialog.current, origin = trigger ?? document.activeElement;
    element.showModal(); close.current?.focus();
    return () => { element.close(); if (origin?.isConnected) origin.focus({ preventScroll: true }); };
  }, [trigger]);
  const content = <dialog ref={dialog} className={`${shared.dialog} ${styles.dialog}`} aria-labelledby="payment-details-title" onCancel={event => { event.preventDefault(); onClose(); }}>
    <div className={styles.stack}><header className={styles.detailHeading}><h2 id="payment-details-title">Payment Details</h2><button ref={close} className={shared.secondary} onClick={onClose} aria-label="Close Payment Details">Close</button></header>
      {resource.loading ? <p role="status">Loading payment transaction…</p> : resource.error ? <p className={shared.error} role="alert">{resource.error} Close and reopen the record to retry.</p> : <>
        <div className={styles.transactionHero}><div><span>Amount</span><strong>{myr(resource.data.attempt.amount_sen)}</strong><p>{methodLabels[resource.data.attempt.method]}</p></div><PaymentBadge status={resource.data.attempt.status} /></div>
        <PaymentMode data={resource.data} disclosure />
        <TransactionFields transaction={resource.data} grouped />
        <section><h3>Assigned Parking Rates</h3><TariffFields tariff={resource.data.charge.tariff} /></section>
      </>}
    </div>
  </dialog>;
  return typeof document === 'undefined' ? content : createPortal(content, document.body);
}
