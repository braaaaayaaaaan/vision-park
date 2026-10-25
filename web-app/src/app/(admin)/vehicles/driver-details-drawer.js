'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { detailsQuery, fetchDriverDetails } from './vehicles-client.mjs';
import useVehicleResource from './use-vehicle-resource';
import { DriverIdentity, RegistrationUsage, StatusBadge, DecisionActions, VehiclePagination, RecordsState, statusLabels } from './vehicles-ui';
import styles from './vehicles.module.css';
import shared from '../approvals/approvals.module.css';

function registrationDate(value) {
  return value ? new Intl.DateTimeFormat('en-MY', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'Asia/Kuala_Lumpur' }).format(new Date(value)) : null;
}

export default function DriverDetailsDrawer({ driverId, trigger, revision, locked, onClose, onDecision }) {
  const [status, setStatus] = useState(''), [offset, setOffset] = useState(0), [retry, setRetry] = useState(0);
  const dialog = useRef(null), closeButton = useRef(null);
  const query = detailsQuery(status, offset);
  const load = useCallback(signal => fetchDriverDetails(driverId, query, signal), [driverId, query]);
  const resource = useVehicleResource(`${driverId}|${query}|${revision}|${retry}`, load);
  const data = resource.data;
  useEffect(() => {
    const element = dialog.current, origin = trigger ?? document.activeElement;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    element.showModal(); closeButton.current?.focus({ preventScroll: true });
    return () => {
      element.close(); document.body.style.overflow = overflow;
      if (origin?.isConnected) origin.focus({ preventScroll: true });
    };
  }, [trigger]);
  useEffect(() => {
    if (!locked && dialog.current?.open && !dialog.current.contains(document.activeElement)) closeButton.current?.focus({ preventScroll: true });
  }, [locked, revision]);
  const content = <dialog ref={dialog} className={styles.drawer} data-driver-drawer="true" aria-modal="true"
    aria-labelledby="driver-details-title" onCancel={event => { event.preventDefault(); event.stopPropagation(); if (!locked) onClose(); }}>
    <header className={styles.drawerHeader}><div><span className={styles.eyebrow}>Registered Vehicles</span><h2 id="driver-details-title">Driver Details</h2></div>
      <button ref={closeButton} className={styles.close} disabled={locked} onClick={onClose} aria-label="Close Driver Details">×</button></header>
    <div className={styles.drawerBody}>
      {data && <>
        <DriverIdentity driver={data.driver} />
        {data.driver.email && <p className={styles.muted}>{data.driver.email}</p>}
        <section className={styles.drawerUsage} aria-label="Driver Registration Usage"><RegistrationUsage counts={data.driver.vehicle_counts} />
          <dl className={styles.counts}>{['approved', 'pending', 'rejected'].map(key => <div key={key}><dt>{statusLabels[key]}</dt><dd>{data.driver.vehicle_counts[key]}</dd></div>)}</dl>
          <p className={styles.muted}>Rejected registrations do not take up a registration slot.</p>
        </section>
      </>}
      <div className={styles.drawerListHeading}><h3>Vehicle Registrations</h3><label className={shared.srOnly} htmlFor="drawer-status">Filter Vehicle Registrations</label>
        <select id="drawer-status" value={status} disabled={locked} onChange={event => { setStatus(event.target.value); setOffset(0); }}>
          <option value="">All Statuses</option>{Object.entries(statusLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
        </select></div>
      {resource.loading || resource.error ? <RecordsState loading={resource.loading} error={resource.error} message="Loading driver details…" onRetry={() => setRetry(value => value + 1)} />
        : !data?.vehicles.length ? <RecordsState title={offset > 0 ? 'No Registrations on This Page' : status ? 'No Matching Registrations' : 'No Registered Vehicles'}
          message={offset > 0 ? 'The records may have changed. Return to the first page.' : 'Choose another status or check again later.'} onFirstPage={offset > 0 ? () => setOffset(0) : null} />
          : <ul className={styles.drawerVehicles}>{data.vehicles.map(vehicle => <li key={vehicle.id}>
            <div className={styles.vehicleHeading}><strong className={styles.plate}>{vehicle.plate_number}</strong><StatusBadge status={vehicle.registration_status} /></div>
            <p className={styles.muted}>{vehicle.created_at ? <>Registered <time dateTime={vehicle.created_at}>{registrationDate(vehicle.created_at)}</time></> : 'Registration date unavailable.'}</p>
            {vehicle.registration_status === 'rejected' && <div className={styles.rejectionReason}>
              <strong>Rejection Reason</strong><p>{vehicle.rejection_reason || 'No rejection reason was provided.'}</p>
            </div>}
            <DecisionActions vehicle={vehicle} disabled={locked} onDecision={(record, action) => onDecision({ ...record,
              owner_name: data.driver.full_name, tenant_name: data.driver.company_name }, action)} />
          </li>)}</ul>}
      <VehiclePagination data={data} offset={offset} loading={resource.loading} disabled={locked} onPage={setOffset} noun="Registrations" />
    </div>
  </dialog>;
  return typeof document === 'undefined' ? content : createPortal(content, document.fullscreenElement ?? document.body);
}
