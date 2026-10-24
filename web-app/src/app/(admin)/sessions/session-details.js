'use client';
import { useEffect, useRef } from 'react';
import { formatAssignedZone, formatDuration, formatTimestamp, sessionLabels } from './sessions-client.mjs';
import styles from '../approvals/approvals.module.css';
import local from './sessions.module.css';

function DetailFields({ fields }) {
  return <dl className={local.fields}>{fields.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value || 'Not available'}</dd></div>)}</dl>;
}

export default function SessionDetails({ session, onClose }) {
  const dialog = useRef(null);
  useEffect(() => {
    const element = dialog.current;
    element.showModal();
    return () => element.close();
  }, []);
  const activity = [
    ['Entry Time', formatTimestamp(session.entry_time)], ['Parking Confirmation Time', formatTimestamp(session.parking_confirmed_at)],
    ['Exit Time', formatTimestamp(session.exit_time)], ['Parking Duration', formatDuration(session.duration_seconds)],
  ];
  return <dialog ref={dialog} className={`${styles.dialog} ${local.sessionDialog}`} aria-labelledby="session-details-title" aria-describedby="session-details-description" onCancel={event => { event.preventDefault(); onClose(); }}>
    <div className={local.details}>
      <header>
        <h2 id="session-details-title">Parking Session Details</h2>
        <div className={local.sessionSummary}><strong className={local.plate}>{session.plate_number || 'Plate not available'}</strong><span className={`${styles.badge} ${local.statusBadge}`}>{sessionLabels[session.status]}</span></div>
        <p id="session-details-description" className={local.note}>All times in Malaysia time (MYT).</p>
      </header>
      <div className={local.detailCards}>
        <section className={local.detailCard} aria-labelledby="session-vehicle-title">
          <h3 id="session-vehicle-title">Vehicle</h3>
          <DetailFields fields={[['Registered Owner', session.owner_name], ['Company', session.tenant_name]]} />
        </section>
        <section className={local.detailCard} aria-labelledby="session-location-title">
          <h3 id="session-location-title">Parking Location</h3>
          <DetailFields fields={[['Parking Level', session.level_name], ['Assigned Zone', formatAssignedZone(session.zone_name, session.level_name)]]} />
        </section>
        <section className={`${local.detailCard} ${local.activityCard}`} aria-labelledby="session-activity-title">
          <h3 id="session-activity-title">Activity</h3>
          <DetailFields fields={activity} />
          {session.duration_seconds !== null && <p className={local.note}>Duration from entry to exit.</p>}
        </section>
      </div>
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
