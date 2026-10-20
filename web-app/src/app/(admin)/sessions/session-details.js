'use client';
import { useEffect, useRef } from 'react';
import { formatDuration, formatTimestamp, sessionLabels } from './sessions-client.mjs';
import styles from '../approvals/approvals.module.css';
import local from './sessions.module.css';

export default function SessionDetails({ session, onClose }) {
  const dialog = useRef(null);
  useEffect(() => {
    const element = dialog.current;
    element.showModal();
    return () => element.close();
  }, []);
  const fields = [
    ['Session ID', session.id], ['Vehicle ID', session.vehicle_id], ['Vehicle Plate', session.plate_number],
    ['Registered Owner', session.owner_name], ['Company', session.tenant_name], ['Parking Level', session.level_name],
    ['Assigned Zone', session.zone_name], ['Current Session Status', sessionLabels[session.status]],
    ['Entry Time', formatTimestamp(session.entry_time)], ['Parking Confirmation Time', formatTimestamp(session.parking_confirmed_at)],
    ['Exit Time', formatTimestamp(session.exit_time)], ['Parking Duration', formatDuration(session.duration_seconds)],
  ];
  return <dialog ref={dialog} className={styles.dialog} aria-labelledby="session-details-title" aria-describedby="session-details-description" onCancel={event => { event.preventDefault(); onClose(); }}>
    <div className={local.details}><h2 id="session-details-title">Parking Session Details</h2>
      <dl className={local.fields}>{fields.map(([label, value]) => <div key={label}><dt>{label}</dt><dd>{value || 'Not Available'}</dd></div>)}</dl>
      <p className={local.note}>Duration is entry to exit for completed sessions with valid timestamps.</p>
      <div className={styles.dialogActions}><button className={styles.secondary} onClick={onClose}>Close</button></div>
    </div>
  </dialog>;
}
