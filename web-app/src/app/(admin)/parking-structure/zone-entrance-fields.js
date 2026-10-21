'use client';
import { assignZone, entranceReview } from './zone-entrance-utils.mjs';
import styles from './node-editor.module.css';
import map from './calibration.module.css';

export default function ZoneEntranceFields({ node, nodes, plan, zones, links, disabled, onChange }) {
  const selected = Object.entries(links).find(([, link]) => link.node_id === node?.id && link.floor_plan_revision === plan.revision)?.[0] ?? '';
  const zone = zones.find(zone => zone.id === selected);
  const reviews = Object.entries(links).map(([zoneId, link]) => ({ zoneId, link, reasons: entranceReview(link, nodes, plan.revision) })).filter(item => item.reasons.length);
  const entrance = node?.node_type === 'zone_entrance';
  if (!entrance && reviews.length === 0) return null;
  return <section className={styles.zoneMapping} aria-label="Draft Zone Entrance Mapping">
    <div className={map.heading}><h3>Zone Entrance Mapping</h3><a href="#parking-zones">Manage Parking Zones</a></div>
    {entrance && <>
      <p className={map.note} role="status">{Object.values(links).some(link => link.node_id === node.id && entranceReview(link, nodes, plan.revision).length) ? 'Needs Review' : selected ? 'Linked' : 'Unlinked'} · Changes Are Saved With Save Draft.</p>
      <label className={styles.field}>Draft Zone<select value={selected} disabled={disabled} onChange={event => onChange(assignZone(links, node.id, event.target.value, plan.revision))}>
        <option value="">Unlinked</option>
        {zones.map(zone => {
          const link = links[zone.id], other = link && link.node_id !== node.id && entranceReview(link, nodes, plan.revision).length === 0;
          const target = other && nodes.find(node => node.id === link.node_id);
          return <option key={zone.id} value={zone.id} disabled={Boolean(other)}>{zone.code} — {zone.name}{other ? ` — Linked To ${target?.code ?? 'Another Entrance'}` : link && entranceReview(link, nodes, plan.revision).length ? ' — Needs Review' : ''}</option>;
        })}
      </select></label>
      <p className={map.note}>{zones.length ? 'Zones linked to another entrance are unavailable until that association is removed.' : 'No draft zones on this level. Configure an existing zone in parking zones above first.'}</p>
      {zone && <dl className={map.summary} aria-label="Selected Draft Zone Information">
        <div className={map.summaryCard}><dt>Zone</dt><dd>{zone.code}</dd></div>
        <div className={map.summaryCard}><dt>Total Capacity</dt><dd>{zone.total_capacity.toLocaleString('en-MY')}</dd></div>
        <div className={map.summaryCard}><dt>Unavailable Capacity</dt><dd>{zone.unavailable_capacity.toLocaleString('en-MY')}</dd></div>
        <div className={map.summaryCard}><dt>Configured Usable Capacity</dt><dd>{(zone.total_capacity - zone.unavailable_capacity).toLocaleString('en-MY')}</dd></div>
        <div className={map.summaryCard}><dt>Intended Status</dt><dd>{{ open: 'Open', closed: 'Closed', maintenance: 'Maintenance' }[zone.operational_status]}</dd></div>
      </dl>}
    </>}
    {reviews.length > 0 && <div className={styles.warning} role="status"><strong>Needs Review</strong>
      {reviews.map(({ zoneId, link, reasons }) => <div key={zoneId} className={styles.reviewRow}>
        <span>{zones.find(zone => zone.id === zoneId)?.code ?? 'Draft Zone'} · Image {link.floor_plan_revision} · {reasons.join(', ')}</span>
        <button type="button" className={map.button} disabled={disabled} onClick={() => onChange(Object.fromEntries(Object.entries(links).filter(([id]) => id !== zoneId)))}>Unlink Zone</button>
      </div>)}
      <p>Unlink Or Select This Zone On A Current Zone Entrance, Then Save Draft. No Zone Or Node Is Deleted.</p>
    </div>}
  </section>;
}
