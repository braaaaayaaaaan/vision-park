'use client';
import { useEffect, useRef, useState } from 'react';
import shared from './parking-structure.module.css';
import map from './calibration.module.css';
import styles from './structure-validation.module.css';

export default function StructureValidation({ levels, disabled }) {
  const [selected, setSelected] = useState([]), [report, setReport] = useState(null), [loading, setLoading] = useState(false);
  const [error, setError] = useState(''), [required, setRequired] = useState([]);
  const [previousDisabled, setPreviousDisabled] = useState(disabled), [stale, setStale] = useState(false);
  // Retain the point-in-time report, but never keep a Ready label after an
  // editor becomes dirty or starts saving. Revalidation is explicit.
  if (previousDisabled !== disabled) {
    setPreviousDisabled(disabled);
    if (disabled) setStale(true);
  }
  const controller = useRef(null), pending = useRef(false);
  useEffect(() => () => controller.current?.abort(), []);
  const chosen = selected.filter(id => levels.some(level => level.id === id));
  const levelName = id => levels.find(level => level.id === id)?.name ?? id;
  function selection(ids) { setSelected(ids); setReport(null); setError(''); setRequired([]); setStale(false); }
  async function validate() {
    if (disabled || pending.current || !chosen.length) return;
    pending.current = true; setLoading(true); setError(''); setReport(null); setRequired([]); setStale(false);
    const request = new AbortController(); controller.current = request;
    try {
      const response = await fetch('/api/parking-structure/validate', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ level_ids: chosen }), cache: 'no-store', signal: request.signal });
      if ([401, 403].includes(response.status)) { window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`); return; }
      const result = await response.json();
      if (request.signal.aborted) return;
      if (!response.ok) { setError(result.error || 'Validation Could Not Be Completed. Retry.'); setRequired(result.required_level_ids ?? []); }
      else setReport(result);
    } catch (failure) {
      if (!request.signal.aborted) setError(failure.message || 'Validation Could Not Be Completed. Retry.');
    } finally { pending.current = false; if (!request.signal.aborted) setLoading(false); }
  }
  return <section className={shared.panel} aria-label="Draft Configuration Validation" aria-busy={loading}>
    <div className={map.heading}><h2>Configuration Validation</h2><button className={shared.button} disabled={disabled || loading || !chosen.length} onClick={validate}>{loading ? 'Validating…' : 'Validate Configuration'}</button></div>
    <p className={shared.note}>Check saved drafts only. Select all required driving and ramp reference levels. Save or riscard current edits before validating.</p>
    <fieldset className={styles.scope} disabled={disabled || loading}><legend>Included Levels</legend>
      <div className={styles.choices}>{levels.map(level => <label key={level.id}><input type="checkbox" checked={chosen.includes(level.id)} disabled={!chosen.includes(level.id) && chosen.length >= 64}
        onChange={event => selection(event.target.checked ? [...chosen, level.id] : chosen.filter(id => id !== level.id))} />{level.name}{!level.floor_plan ? ' (No Floor Plan)' : ''}</label>)}</div>
      {!levels.length && <p>No Parking Levels Available.</p>}
      <div className={map.toolbar}><button type="button" className={shared.button} disabled={levels.filter(level => level.floor_plan).length > 64} onClick={() => selection(levels.filter(level => level.floor_plan).map(level => level.id))}>Select Configured Levels</button>
        <button type="button" className={shared.button} onClick={() => selection([])}>Clear Selection</button></div>
      <p className={shared.note}>{chosen.length} Selected</p>
    </fieldset>
    {error && <div className={shared.error} role="alert"><p>{error}</p>{required.length > 0 && <p>Also Include: {required.map(levelName).join(', ')}</p>}</div>}
    {report && <div className={styles.report}>
      <div className={styles.result} role="status"><strong>{stale ? 'Revalidation Required' : report.readiness === 'ready' ? 'Ready' : 'Needs Attention'}</strong>
        <span>Snapshot: {new Date(report.snapshot_at).toLocaleString('en-MY', { timeZone: 'Asia/Kuala_Lumpur' })} (Malaysia Time)</span>
        <span>{stale ? 'Local Draft Edits Detected. Validate Again After Saving.' : report.allocation_ready ? 'Allocation Candidates Pass Draft Checks' : 'Allocation Is Not Ready'}</span></div>
      <dl className={styles.summaryGrid}>{[['Levels', 'levels'], ['Nodes', 'nodes'], ['Directed Edges', 'directed_edges'], ['Mapped Zones', 'mapped_zones'], ['Errors', 'errors'], ['Warnings', 'warnings']].map(([label, key]) =>
        <div className={map.summaryCard} key={key}><dt>{label}</dt><dd>{report.summary[key]}</dd></div>)}</dl>
      <h3>Zone Reachability</h3>
      {report.zones.length ? <div className={styles.table}><table><thead><tr><th>Level</th><th>Zone</th><th>Usable Capacity</th><th>Result</th><th>Shortest Distance</th></tr></thead>
        <tbody>{report.zones.map(zone => <tr key={zone.zone_id}><td>{levelName(zone.level_id)}</td><td>{zone.code}</td><td>{zone.usable_capacity}</td><td>
          <strong>{{ reachable: 'Reachable', unreachable: 'Unreachable', not_checked: 'Not Checked', not_applicable: 'Excluded From Allocation' }[zone.reachability]}</strong><p>{zone.message}</p>
          {zone.node_ids && <details><summary>Route Node IDs</summary><p className={styles.route}>{zone.node_ids.join(' → ')}</p></details>}</td>
          <td>{zone.distance_meters === null ? '—' : `${zone.distance_meters.toLocaleString('en-MY', { maximumFractionDigits: 2 })} m`}</td></tr>)}</tbody></table></div> : <p>No Valid Draft Zones To Check.</p>}
      {report.issues.length > 0 && <><h3>Required Corrections And Warnings</h3><ul className={styles.issues}>{report.issues.map((issue, index) =>
        <li key={index}><strong>{issue.severity === 'error' ? 'Error' : 'Warning'}{issue.level_id ? ` · ${levelName(issue.level_id)}` : ''}{issue.zone_id ? ` · Zone ${report.zones.find(zone => zone.zone_id === issue.zone_id)?.code ?? issue.zone_id}` : ''}</strong>
          <p>{issue.message}</p>{issue.edge_id && <small>Edge: {issue.edge_id}</small>}</li>)}</ul></>}
      <details><summary>Checked Scope And Revisions</summary><ul>{report.checked.map(check => <li key={check}>{check}</li>)}</ul>
        {report.levels.map(level => <p key={level.id}>{level.name} · Image {level.floor_plan_revision ?? 'Missing'} · Calibration {level.calibration_revision ?? 'Missing'} · Draft {level.draft_revision ?? 'Missing'} · Validated Distances {level.distances_validated_revision ?? 'Missing'}</p>)}
        <p>{report.ramp_revisions.length} Directed Ramp Revisions Included. Revalidate After Changes.</p>
      </details>
    </div>}
  </section>;
}
