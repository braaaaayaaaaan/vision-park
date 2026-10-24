'use client';
import { assignZone, entranceReview } from './zone-entrance-utils.mjs';
import styles from './node-editor.module.css';
import map from './calibration.module.css';

const reviewDescriptions = { 'Image Replaced': 'Image replaced', 'Node Missing': 'Node missing', 'Node Type Changed': 'Node type changed' };

export default function ZoneEntranceFields({ node, nodes, plan, zones, links, disabled, onChange }) {
  const selected = Object.entries(links).find(([, link]) => link.node_id === node?.id && link.floor_plan_revision === plan.revision)?.[0] ?? '';
  const zone = zones.find(zone => zone.id === selected);
  const reviews = Object.entries(links).map(([zoneId, link]) => ({ zoneId, link, reasons: entranceReview(link, nodes, plan.revision) })).filter(item => item.reasons.length);
  const entrance = node?.node_type === 'zone_entrance';
  const linkState = Object.values(links).some(link => link.node_id === node?.id && entranceReview(link, nodes, plan.revision).length) ? 'needs_review' : selected ? 'linked' : 'unlinked';
  if (!entrance && reviews.length === 0) return null;
  return <section className={styles.zoneMapping} aria-label="Draft Zone Entrance Mapping">
    <div className={map.heading}><h3>Zone Entrance Mapping</h3><a href="#parking-zones">Manage Parking Zones</a></div>
    {entrance && <>
      <div className={styles.linkStatus} data-state={linkState} role="status">
        <div className={styles.linkStatusHeading}><span>Zone link</span><strong><span className={styles.linkDot} aria-hidden="true" />{{ linked: 'Linked', unlinked: 'Unlinked', needs_review: 'Needs Review' }[linkState]}</strong></div>
        {linkState !== 'linked' && <p className={styles.linkGuidance}>{linkState === 'needs_review' ? 'Review the zone association below.' : zones.length ? 'Choose a draft zone to link this entrance.' : 'Create a parking zone to link this entrance.'}</p>}
        <p className={styles.linkSaveNote}>Save link changes with <strong>Save Draft</strong>.</p>
      </div>
      <label className={styles.field}>Draft Zone<select value={selected} disabled={disabled} onChange={event => onChange(assignZone(links, node.id, event.target.value, plan.revision))}>
        <option value="">Unlinked</option>
        {zones.map(zone => {
          const link = links[zone.id], other = link && link.node_id !== node.id && entranceReview(link, nodes, plan.revision).length === 0;
          const target = other && nodes.find(node => node.id === link.node_id);
          return <option key={zone.id} value={zone.id} disabled={Boolean(other)}>{zone.code} — {zone.name}{other ? ` — linked to ${target?.code ?? 'another entrance'}` : link && entranceReview(link, nodes, plan.revision).length ? ' — needs review' : ''}</option>;
        })}
      </select></label>
      <p className={map.note}>{zones.length ? 'Zones linked to another entrance are unavailable until that association is removed.' : 'No draft zones on this level. Configure an existing zone in parking zones above first.'}</p>
      {zone && <section className={styles.zoneInfo} aria-label="Selected Draft Zone Information">
        <dl className={styles.zoneIdentity}>
          <div><dt>Zone</dt><dd>{zone.code}</dd></div>
          <div className={styles.zoneStatus} data-status={zone.operational_status}><dt>Intended Status</dt><dd>{{ open: 'Open', closed: 'Closed', maintenance: 'Maintenance' }[zone.operational_status]}</dd></div>
        </dl>
        <dl className={styles.zoneUsable}><dt>Configured Usable Capacity</dt><dd>{(zone.total_capacity - zone.unavailable_capacity).toLocaleString('en-MY')}<span> spaces</span></dd></dl>
        <dl className={styles.zoneBreakdown}>
          <div><dt>Total Capacity</dt><dd>{zone.total_capacity.toLocaleString('en-MY')}</dd></div>
          <div><dt>Unavailable Capacity</dt><dd>{zone.unavailable_capacity.toLocaleString('en-MY')}</dd></div>
        </dl>
      </section>}
    </>}
    {reviews.length > 0 && <div className={styles.warning} role="status"><strong>Needs Review</strong>
      {reviews.map(({ zoneId, link, reasons }) => <div key={zoneId} className={styles.reviewRow}>
        <span>{zones.find(zone => zone.id === zoneId)?.code ?? 'Draft zone'} · Image {link.floor_plan_revision} · {reasons.map(reason => reviewDescriptions[reason] ?? reason).join(', ')}</span>
        <button type="button" className={map.button} disabled={disabled} onClick={() => onChange(Object.fromEntries(Object.entries(links).filter(([id]) => id !== zoneId)))}>Unlink Zone</button>
      </div>)}
      <p>Unlink or select this zone on a current zone entrance, then Save Draft. No zone or node is deleted.</p>
    </div>}
  </section>;
}
