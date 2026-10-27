'use client';
import { useCallback, useRef, useState } from 'react';
import ConfirmationDialog from '../../../components/confirmation-dialog';
import useResource from '../vehicles/use-vehicle-resource';
import { fetchTariffs, publishTariff } from '../payments/payments-client.mjs';
import { tariffForm, myr } from '../../../lib/payment-contracts.mjs';
import { PaymentFields, paymentTime } from '../payments/payment-ui';
import shared from '../approvals/approvals.module.css';
import styles from '../payments/payments.module.css';

export default function RateEditor({ onClose, onSaved }) {
  const [revision, setRevision] = useState(0);
  const load = useCallback(signal => fetchTariffs(0, signal), []);
  const resource = useResource(`rate-editor:${revision}`, load);
  return <section className={`${styles.panel} ${styles.editor}`} aria-labelledby="rate-editor-title">
    <h2 id="rate-editor-title">Publish New Parking Rates</h2>
    {resource.loading ? <p role="status">Reading the latest tariff version…</p> : resource.error ? <><p role="alert" className={shared.error}>{resource.error}</p><button className={shared.secondary} onClick={() => setRevision(value => value + 1)}>Try Again</button><button className={shared.secondary} onClick={onClose}>Close</button></> :
      <RateForm key={revision} latest={resource.data.tariffs[0]?.version_number ?? 0} onClose={onClose} onSaved={onSaved} onReload={() => setRevision(value => value + 1)} />}
  </section>;
}
export function RateForm({ latest, onClose, onSaved, onReload }) {
  const [draft, setDraft] = useState({ initial_duration_minutes: '60', initial_fee: '', hourly_fee: '', rounding_minutes: '60', grace_minutes: '0', maximum_fee: '', effective_from: '' });
  const [review, setReview] = useState(null), [error, setError] = useState(''), [busy, setBusy] = useState(false), [reloadRequired, setReloadRequired] = useState(false);
  const inFlight = useRef(false);
  const field = (key, value) => setDraft(old => ({ ...old, [key]: value }));
  function prepare(event) {
    event.preventDefault(); if (inFlight.current || reloadRequired) return;
    try { setReview(tariffForm(draft, latest)); setError(''); } catch (cause) { setError(cause.message); }
  }
  async function publish() {
    if (inFlight.current || reloadRequired) return false;
    inFlight.current = true; setBusy(true);
    try { const result = await publishTariff(review); onSaved(result.tariff); return true; }
    catch (cause) {
      setError(cause.message); setReview(null);
      // A lost response may have committed. Re-read versions, never replay it.
      if (!cause.status || [409, 503].includes(cause.status) || cause.sessionChanged) setReloadRequired(true);
      return false;
    } finally { inFlight.current = false; setBusy(false); }
  }
  return <>
    <p className={styles.muted}>Version {latest + 1}</p>
    <form className={styles.form} onSubmit={prepare} aria-busy={busy}>
      <fieldset disabled={busy || reloadRequired} className={styles.formGroup}>
        <legend>Parking Charges</legend><div className={styles.formGrid}>
        <label>Initial Duration (Minutes)<input type="number" min="1" max="1440" step="1" required value={draft.initial_duration_minutes} onChange={event => field('initial_duration_minutes', event.target.value)} /></label>
        <label>Initial Fee (MYR)<input type="text" inputMode="decimal" required maxLength={11} placeholder="0.00" value={draft.initial_fee} onChange={event => field('initial_fee', event.target.value)} /></label>
        <label>Subsequent Hourly Rate (MYR)<input type="text" inputMode="decimal" required maxLength={11} placeholder="0.00" value={draft.hourly_fee} onChange={event => field('hourly_fee', event.target.value)} /></label>
        <label>Billing Increment<select value={draft.rounding_minutes} onChange={event => field('rounding_minutes', event.target.value)}>{[1, 15, 30, 60].map(value => <option key={value} value={value}>{value} {value === 1 ? 'Minute' : 'Minutes'}</option>)}</select></label>
        </div>
      </fieldset>
      <fieldset disabled={busy || reloadRequired} className={styles.formGroup}>
        <legend>Limits</legend><div className={styles.formGrid}>
        <label>Grace Period (Minutes)<input type="number" min="0" max="1440" step="1" required value={draft.grace_minutes} onChange={event => field('grace_minutes', event.target.value)} /></label>
        <label>Maximum Fee (MYR, Optional)<input type="text" inputMode="decimal" maxLength={11} placeholder="No Maximum" value={draft.maximum_fee} onChange={event => field('maximum_fee', event.target.value)} /></label>
        </div>
      </fieldset>
      <fieldset disabled={busy || reloadRequired} className={styles.formGroup}>
        <legend>Schedule</legend><div className={styles.formGrid}>
        <label>Effective From (MYT, Optional)<input type="datetime-local" value={draft.effective_from} onChange={event => field('effective_from', event.target.value)} /></label>
        </div>
      </fieldset>
      <p className={styles.muted}>Leave the effective time blank to apply immediately. All times are in MYT.</p>
      {error && <p role="alert" className={shared.error}>{error}</p>}
      {reloadRequired && <p className={styles.notice}>Reload versions to check whether your rates were published.</p>}
      <div className={shared.actions}><button className={shared.secondary} type="button" disabled={busy} onClick={onClose}>Cancel</button>
        {reloadRequired ? <button className={shared.secondary} type="button" onClick={onReload}>Reload Versions</button> : <button className={shared.primary} disabled={busy}>Review New Rates</button>}</div>
    </form>
    {review && <ConfirmationDialog title="Publish New Parking Rates?" description="These rates cannot be edited or deleted after publication. Existing sessions keep their assigned rates."
      confirmLabel="Publish Rates" pendingLabel="Publishing…" onConfirm={publish} onCancel={() => setReview(null)}>
      <PaymentFields fields={[
        ['New Version', String(review.expected_version + 1)], ['Initial Duration', `${review.initial_duration_minutes} Min`], ['Initial Fee', myr(review.initial_charge_sen)],
        ['Subsequent Hourly Rate', myr(review.subsequent_hourly_rate_sen)], ['Billing Increment', `${review.rounding_minutes} Min`], ['Grace Period', `${review.grace_minutes} Min`],
        ['Maximum Fee', review.maximum_charge_sen === null ? 'No Maximum' : myr(review.maximum_charge_sen)], ['Effective From', review.effective_from ? paymentTime(review.effective_from) : 'On Publication'],
      ]} />
    </ConfirmationDialog>}
  </>;
}
