'use client';
import { useEffect, useRef } from 'react';
import { DecisionActions, StatusBadge } from './vehicles-ui';
import styles from './vehicles.module.css';
import shared from '../approvals/approvals.module.css';
import checkboxStyles from '../../../components/selection-checkbox.module.css';

function SelectionCheckbox({ mixed = false, title, ...props }) {
  const input = useRef(null);
  useEffect(() => { if (input.current) input.current.indeterminate = mixed; }, [mixed]);
  return <label className={styles.checkboxControl} title={title}>
    <input className={checkboxStyles.checkbox} ref={input} type="checkbox" aria-checked={mixed ? 'mixed' : props.checked} {...props} />
  </label>;
}

export default function VehicleRecordsTable({ vehicles, selectedIds, locked, onSelect, onSelectAll, onApproveSelected, onDecision }) {
  const eligible = vehicles.filter(vehicle => vehicle.registration_status === 'pending');
  const selected = eligible.filter(vehicle => selectedIds.includes(vehicle.id));
  const all = eligible.length > 0 && selected.length === eligible.length;
  return <>
    <div className={styles.bulkToolbar}>
      <p role="status" aria-live="polite">{selected.length} {selected.length === 1 ? 'vehicle' : 'vehicles'} selected <span className={styles.muted}>· Current page only</span></p>
      <button className={shared.primary} disabled={locked || !selected.length} onClick={onApproveSelected}>Approve Selected</button>
    </div>
    <div className={shared.tableScroll} tabIndex={0} aria-label="Scrollable Vehicle Records Table">
      <table className={`${shared.table} ${styles.vehicleTable}`}>
        <caption className={shared.srOnly}>Registered Vehicles</caption>
        <thead><tr>
          <th scope="col" className={styles.selectionCell}><SelectionCheckbox aria-label="Select All Pending Vehicles on This Page"
            checked={all} mixed={selected.length > 0 && !all} disabled={locked || !eligible.length}
            onChange={event => onSelectAll(event.target.checked)} /></th>
          <th scope="col">Number Plate</th><th scope="col">Driver</th><th scope="col">Company</th><th scope="col">Registration Status</th><th scope="col">Actions</th>
        </tr></thead>
        <tbody>{vehicles.map(vehicle => <tr key={vehicle.id} data-selected={selectedIds.includes(vehicle.id)}>
          <td className={styles.selectionCell}><SelectionCheckbox aria-label={`Select ${vehicle.plate_number}`}
            checked={selectedIds.includes(vehicle.id) && vehicle.registration_status === 'pending'}
            disabled={locked || vehicle.registration_status !== 'pending'}
            title={vehicle.registration_status !== 'pending' ? 'Only pending registrations can be selected.' : undefined}
            onChange={event => onSelect(vehicle.id, event.target.checked)} /></td>
          <td><strong className={styles.plate}>{vehicle.plate_number}</strong></td>
          <td>{vehicle.owner_name || 'Owner Unavailable'}</td><td>{vehicle.tenant_name || 'Company Unavailable'}</td>
          <td><StatusBadge status={vehicle.registration_status} /></td>
          <td className={styles.vehicleActions}>{vehicle.registration_status === 'pending'
            ? <DecisionActions vehicle={vehicle} disabled={locked} onDecision={onDecision} />
            : <span className={styles.muted}>—</span>}</td>
        </tr>)}</tbody>
      </table>
    </div>
  </>;
}
