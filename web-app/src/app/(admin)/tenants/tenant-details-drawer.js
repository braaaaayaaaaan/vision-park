'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import useResource from '../vehicles/use-vehicle-resource';
import { RecordsState } from '../vehicles/vehicles-ui';
import { fetchTenant } from './tenants-client.mjs';
import { DriverStats, TenantStatus, ZoneList } from './tenants-ui';
import TenantEditor from './tenant-editor';
import common from '../vehicles/vehicles.module.css';
import shared from '../approvals/approvals.module.css';
import styles from './tenants.module.css';

export default function TenantDetailsDrawer({ tenantId, trigger, revision, onClose, onSaved }) {
  const [retry, setRetry] = useState(0), [editing, setEditing] = useState(false);
  const dialog = useRef(null), closeButton = useRef(null);
  const load = useCallback(signal => fetchTenant(tenantId, signal), [tenantId]);
  const resource = useResource(`${tenantId}|${revision}|${retry}`, load);
  const data = resource.data;
  useEffect(() => {
    const element = dialog.current, origin = trigger ?? document.activeElement, overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden'; element.showModal(); closeButton.current?.focus();
    return () => { element.close(); document.body.style.overflow = overflow; if (origin?.isConnected) origin.focus({ preventScroll: true }); };
  }, [trigger]);
  const content = <dialog ref={dialog} className={common.drawer} aria-modal="true" aria-labelledby="tenant-details-title"
    onCancel={event => { event.preventDefault(); event.stopPropagation(); if (!editing) onClose(); }}>
    <header className={common.drawerHeader}><div><span className={common.eyebrow}>Tenants</span><h2 id="tenant-details-title">Company Details</h2></div>
      <button ref={closeButton} className={common.close} disabled={editing} onClick={onClose} aria-label="Close Company Details">×</button></header>
    <div className={common.drawerBody}>
      {resource.loading || resource.error ? <RecordsState loading={resource.loading} error={resource.error} message="Loading company details…" onRetry={() => setRetry(value => value + 1)} /> : data && <>
        <div className={styles.detailsHeading}><h3>{data.tenant.name}</h3><TenantStatus active={data.tenant.is_active} /></div>
        <dl className={styles.info}><div><dt>Company ID</dt><dd>{data.tenant.id}</dd></div><div><dt>Active Parking Sessions</dt><dd className={styles.sessionCount}>{data.tenant.active_sessions}</dd></div></dl>
        <div className={shared.actions}><button className={shared.primary} onClick={() => setEditing(true)}>Edit Company and Access</button>
          <button className={shared.secondary} onClick={() => setRetry(value => value + 1)}>Refresh Details</button></div>
        <DriverStats company={data.tenant} />
        <ZoneList zones={data.zones} zoneIds={data.tenant.zone_ids} inactive={!data.tenant.is_active} />
      </>}
    </div>
    {editing && data && <TenantEditor company={data.tenant} zones={data.zones} onClose={() => setEditing(false)} onSaved={company => { setEditing(false); onSaved(company); }} />}
  </dialog>;
  return typeof document === 'undefined' ? content : createPortal(content, document.body);
}
