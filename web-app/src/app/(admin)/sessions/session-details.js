'use client';
import { useCallback, useEffect, useRef } from 'react';
import { fetchSessionSnapshot, formatAssignedZone, formatDuration, formatTimestamp } from './sessions-client.mjs';
import useResource from '../vehicles/use-vehicle-resource';
import styles from '../approvals/approvals.module.css';
import local from './sessions.module.css';
import SessionPayment from './session-payment';
import { SessionStatusBadge, SessionCardHeading } from './session-ui';
import MetricIcon from '../../../components/metric-icon';

function DetailFields({ fields }) {
  return <dl className={local.fields}>{fields.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value || 'Not available'}</dd></div>)}</dl>;
}

function OvernightDetails({ alert }) {
  const reminder = alert.reminder;
  const nextReminder = reminder && Date.parse(reminder.sent_at) + 15 * 60000;
  const response = reminder?.response === 'still_parked' ? 'Driver confirmed: still parked' : reminder?.response === 'already_left' ? 'Driver reports: already left — review session' : 'Awaiting driver response';
  return <>
    <section className={`${local.detailCard} ${local.activityCard}`} aria-labelledby="session-overnight-title">
      <SessionCardHeading id="session-overnight-title" icon="sessions">Overnight Stay</SessionCardHeading>
      <DetailFields fields={[
        ['Session Driver', alert.driver_name], ['Driver Company', alert.driver_company_name],
        ['First Midnight (MYT)', formatTimestamp(alert.first_midnight)], ['Midnights Crossed', String(alert.midnights_crossed)],
      ]} />
    </section>
    {alert.kind === 'current' && <section className={`${local.detailCard} ${local.activityCard}`} aria-labelledby="session-reminder-title">
      <SessionCardHeading id="session-reminder-title" icon="pending">Driver Reminder</SessionCardHeading>
      {reminder ? <>
        <p className={local.reminderMessage}>{reminder.message}</p>
        <DetailFields fields={[
          ['Reminder Sent', formatTimestamp(reminder.sent_at)], ['Driver Response', response],
          ...(reminder.responded_at ? [['Response Time', formatTimestamp(reminder.responded_at)]] : []),
          ...(alert.reminderCheckedAt < nextReminder ? [['Next Reminder Available', formatTimestamp(new Date(nextReminder).toISOString())]] : []),
        ]} />
      </> : <p className={local.note}>{alert.reminderCheckedAt ? 'No reminder recorded at the last check.' : 'Reminder details could not be checked. Close this dialog and retry driver reminders.'}</p>}
      {alert.reminderCheckedAt && <p className={local.note}>Reminder details as checked at {formatTimestamp(new Date(alert.reminderCheckedAt).toISOString())}.</p>}
    </section>}
  </>;
}

export default function SessionDetails({ session: snapshot, overnight, isListed = true, onClose }) {
  const load = useCallback(signal => isListed ? Promise.resolve(snapshot) : fetchSessionSnapshot(snapshot, signal), [snapshot, isListed]);
  const resource = useResource(`session-detail:${snapshot.id}`, load, isListed ? 0 : 15000);
  const session = isListed ? snapshot : resource.data ?? snapshot;
  const dialog = useRef(null), close = useRef(null);
  useEffect(() => {
    const element = dialog.current, origin = document.activeElement, overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    element.showModal(); close.current?.focus();
    return () => { element.close(); document.body.style.overflow = overflow; if (origin?.isConnected) origin.focus({ preventScroll: true }); };
  }, []);
  const activity = [
    ['Entry Time', formatTimestamp(session.entry_time)], ['Parking Confirmation Time', formatTimestamp(session.parking_confirmed_at)],
    ['Exit Time', formatTimestamp(session.exit_time)], ['Parking Duration', formatDuration(session.duration_seconds)],
  ];
  return <dialog ref={dialog} className={`${styles.dialog} ${local.sessionDialog}`} aria-modal="true" aria-labelledby="session-details-title" aria-describedby="session-details-description" onCancel={event => { event.preventDefault(); event.stopPropagation(); onClose(); }}>
    <div className={local.details}>
      <header className={local.dialogHeading}>
        <div><h2 id="session-details-title">Parking Session Details</h2><p id="session-details-description" className={local.note}>All times in Malaysia time (MYT).</p></div>
        <button ref={close} type="button" className={local.closeButton} onClick={onClose} aria-label="Close Session Details">
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" aria-hidden="true" focusable="false"><path d="m6 6 12 12 M18 6 6 18" /></svg>
        </button>
      </header>
      <div className={local.sessionSummary}>
        <div className={local.sessionIdentity}><MetricIcon name="vehicles" large solid /><div><p className={local.plateLabel}>Vehicle Plate</p><strong className={local.plate}>{session.plate_number || 'Plate not available'}</strong></div></div>
        <SessionStatusBadge status={session.status} />
      </div>
      <div className={local.detailCards}>
        <section className={local.detailCard} aria-labelledby="session-vehicle-title">
          <SessionCardHeading id="session-vehicle-title" icon="vehicles">Vehicle</SessionCardHeading>
          <DetailFields fields={[['Registered Owner', session.owner_name], ['Company', session.tenant_name]]} />
        </section>
        <section className={local.detailCard} aria-labelledby="session-location-title">
          <SessionCardHeading id="session-location-title" icon="parking">Parking Location</SessionCardHeading>
          <DetailFields fields={[['Parking Level', session.level_name], ['Assigned Zone', formatAssignedZone(session.zone_name, session.level_name)]]} />
        </section>
        <section className={`${local.detailCard} ${local.activityCard}`} aria-labelledby="session-activity-title">
          <SessionCardHeading id="session-activity-title" icon="sessions">Activity</SessionCardHeading>
          <DetailFields fields={activity} />
          {session.duration_seconds !== null && <p className={local.note}>Duration from entry to exit.</p>}
        </section>
        {overnight && <OvernightDetails alert={overnight} />}
      </div>
      <SessionPayment key={session.id} sessionId={session.id} />
      <details className={local.reference}><summary>Session Reference</summary>
        <DetailFields fields={[
          ['Session ID', session.id],
          ...(session.vehicle_id ? [['Vehicle ID', session.vehicle_id]] : []),
        ]} />
      </details>
      <div className={styles.dialogActions}><button className={styles.secondary} onClick={onClose}>Close</button></div>
    </div>
  </dialog>;
}
