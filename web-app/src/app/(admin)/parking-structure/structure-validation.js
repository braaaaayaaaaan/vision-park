'use client';
import { authenticatedFetch } from '../../../lib/auth-client.mjs';
import { useEffect, useRef, useState } from 'react';
import shared from './parking-structure.module.css';
import map from './calibration.module.css';
import styles from './structure-validation.module.css';
import PublicationPreview from './publication-preview';
import { formatMalaysiaDateTime } from '../../../lib/date-format.mjs';

const checkDescriptions = {
  'Current Images And Calibration Geometry': ['Floor Plans', 'Images and scale calibration'],
  'Unique Nodes And One Building Entrance': ['Navigation Nodes', 'Unique nodes and one building entrance'],
  'Directed Same-Level Distances And Revalidation': ['Driving Connections', 'Travel directions and calibrated distances'],
  'Current Directed Ramp Endpoints And Traced Measurements': ['Ramps', 'Cross-level connections and measurements'],
  'Zone Capacities, Statuses And One-To-One Mappings': ['Parking Zones', 'Capacity, status, and entrance links'],
  'Directed Dijkstra Reachability For Allocation Candidates': ['Navigation Routes', 'Routes from the building entrance to eligible zones'],
};

const checkIcons = {
  'Floor Plans': 'M4 3h16v18H4z M4 9h9v6h7 M13 3v6 M9 15v6',
  'Navigation Nodes': 'M10 5h4 M6 8v8 M10 19h4 M18 8v8 M3 2h6v6H3z M15 2h6v6h-6z M3 16h6v6H3z M15 16h6v6h-6z',
  'Driving Connections': 'M4 8h16 M16 4l4 4-4 4 M20 16H4 M8 12l-4 4 4 4',
  'Ramps': 'M3 19h5L16 5h5 M3 15h3L14 1h7 M12 12l3 2 M9 17l3 2',
  'Parking Zones': 'M5 3h14v18H5z M10 17V7h3a3 3 0 0 1 0 6h-3',
  'Navigation Routes': 'M5 7v8a4 4 0 0 0 4 4h6 M8 4a3 3 0 1 1-6 0 3 3 0 0 1 6 0 M22 19a3 3 0 1 1-6 0 3 3 0 0 1 6 0 M11 7h8 M16 4l3 3-3 3',
};

export default function StructureValidation({ levels, disabled, publishing=false, onPublishingChange, onPublished }) {
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
  const issuesByZone = new Map((report?.zones ?? []).map(zone => [zone.zone_id, []]));
  const otherIssues = [];
  for (const issue of report?.issues ?? []) {
    const zoneIssues = issuesByZone.get(issue.zone_id);
    if (zoneIssues) zoneIssues.push(issue);
    else otherIssues.push(issue);
  }
  function selection(ids) { setSelected(ids); setReport(null); setError(''); setRequired([]); setStale(false); }
  async function validate() {
    if (disabled || publishing || pending.current || !chosen.length) return;
    pending.current = true; setLoading(true); setError(''); setReport(null); setRequired([]); setStale(false);
    const request = new AbortController(); controller.current = request;
    try {
      const response = await authenticatedFetch('/api/parking-structure/validate', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ level_ids: chosen }), cache: 'no-store', signal: request.signal });
      if ([401, 403].includes(response.status)) { window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`); return; }
      const result = await response.json();
      if (request.signal.aborted) return;
      if (!response.ok) { setError(result.error || 'Validation could not be completed. Retry.'); setRequired(result.required_level_ids ?? []); }
      else setReport(result);
    } catch (failure) {
      if (!request.signal.aborted) setError(failure.message || 'Validation could not be completed. Retry.');
    } finally { pending.current = false; if (!request.signal.aborted) setLoading(false); }
  }
  return <section className={shared.panel} aria-label="Draft Configuration Validation" aria-busy={loading}>
    <div className={map.heading}><h2>Configuration Validation</h2><button className={shared.button} disabled={disabled || publishing || loading || !chosen.length} onClick={validate}>{loading ? 'Validating…' : 'Validate Configuration'}</button></div>
    <p className={shared.note}>Configure the parking structure first before selecting the relevant parking levels.</p>
    <fieldset className={styles.scope} disabled={disabled || publishing || loading}><legend>Included Levels</legend>
      <div className={styles.choices}>{levels.map(level => <label key={level.id}><input type="checkbox" checked={chosen.includes(level.id)} disabled={!chosen.includes(level.id) && chosen.length >= 64}
        onChange={event => selection(event.target.checked ? [...chosen, level.id] : chosen.filter(id => id !== level.id))} />{level.name}{!level.floor_plan ? ' (no floor plan)' : ''}</label>)}</div>
      {!levels.length && <p>No parking levels available.</p>}
      <div className={map.toolbar}><button type="button" className={shared.button} disabled={levels.filter(level => level.floor_plan).length > 64} onClick={() => selection(levels.filter(level => level.floor_plan).map(level => level.id))}>Select Configured Levels</button>
        <button type="button" className={shared.button} onClick={() => selection([])}>Clear Selection</button></div>
      <p className={shared.note}>{chosen.length} Selected</p>
    </fieldset>
    {error && <div className={shared.error} role="alert"><p>{error}</p>{required.length > 0 && <p>Also include: {required.map(levelName).join(', ')}</p>}</div>}
    <PublicationPreview key={JSON.stringify([chosen,stale,report?.snapshot_at])} levelIds={chosen} disabled={disabled||loading||stale} onPublishingChange={onPublishingChange} onPublished={onPublished} />
    {report && <div className={styles.report}>
      <div className={`${styles.result} ${stale ? styles.resultStale : report.readiness === 'ready' ? styles.resultReady : ''}`} role="status">
        <div className={styles.resultMain}>
          <span className={styles.resultIcon} aria-hidden="true"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            {!stale && report.readiness === 'ready' ? <path d="m5 12 4 4L19 6" /> : <><path d="M12 7v6" /><path d="M12 17h.01" /></>}
          </svg></span>
          <div className={styles.resultCopy}>
            <strong>{stale ? 'Require revalidation' : report.readiness === 'ready' ? 'Ready' : 'Needs attention'}</strong>
            <p className={styles.allocationState} data-ready={!stale && report.allocation_ready} data-stale={stale}>{stale ? 'Detected local draft edits, please validate after saving.' : report.allocation_ready ? 'Allocation passes the draft checks' : 'Allocation is not ready'}</p>
          </div>
        </div>
        <div className={styles.snapshot}><span>Snapshot (Malaysia Time)</span><time dateTime={report.snapshot_at}>{formatMalaysiaDateTime(report.snapshot_at, { seconds: true })}</time></div>
      </div>
      <dl className={styles.summaryGrid}>{[['Levels', 'levels'], ['Nodes', 'nodes'], ['Directed Edges', 'directed_edges'], ['Mapped Zones', 'mapped_zones'], ['Errors', 'errors'], ['Warnings', 'warnings']].map(([label, key]) =>
        <div className={map.summaryCard} key={key}><dt>{label}</dt><dd>{report.summary[key]}</dd></div>)}</dl>
      <h3>Zone Reachability</h3>
      <div className={styles.zoneLevels}>{[...report.levels].sort((a, b) => a.level_number - b.level_number).map(checkedLevel => {
        const zones = report.zones.filter(zone => zone.level_id === checkedLevel.id).sort((a, b) => a.code.localeCompare(b.code, 'en-MY', { numeric: true, sensitivity: 'base' }));
        return <section className={styles.zoneLevel} key={checkedLevel.id} aria-label={`${checkedLevel.name} zone reachability`}>
          <div className={styles.zoneLevelHeading}>
            <h4>{checkedLevel.name}</h4>
            <span>{zones.length} {zones.length === 1 ? 'zone' : 'zones'} · {zones.filter(zone => zone.reachability === 'reachable').length} reachable</span>
          </div>
          {zones.length ? <div className={styles.zoneResults}>{zones.map(zone => {
            const issues = issuesByZone.get(zone.zone_id);
            return <article key={zone.zone_id} className={styles.zoneCard} aria-label={`${checkedLevel.name} · Zone ${zone.code}`}>
              <div className={styles.zoneHeading}>
                <div><h5>Zone {zone.code}</h5><p>{zone.usable_capacity.toLocaleString('en-MY')} Usable Spaces</p></div>
                <span className={styles.reachability} data-status={zone.reachability}>{{ reachable: 'Reachable', unreachable: 'Unreachable', not_checked: 'Needs setup', not_applicable: 'Excluded' }[zone.reachability]}</span>
              </div>
              {zone.distance_meters !== null && <p className={styles.distance}>Shortest Route <strong>{zone.distance_meters.toLocaleString('en-MY', { maximumFractionDigits: 2 })} m</strong></p>}
              {issues.length > 0 ? <ul className={styles.zoneActions}>{issues.map((issue, index) => <li key={index} data-severity={issue.severity}>
                <span className={styles.severity}>{issue.severity === 'error' ? 'Action needed' : 'Note'}</span><p>{issue.message}</p>
              </li>)}</ul> : zone.reachability === 'not_checked' ? <p className={styles.zoneHint}>Complete the configuration checks below, then validate again.</p> : zone.reachability !== 'reachable' ? <p className={styles.zoneHint}>{zone.message}</p> : null}
            </article>;
          })}</div> : <p className={styles.zoneEmpty}>{checkedLevel.zone_revisions.length ? 'No valid draft zones could be checked. Review the configuration issues below.' : 'No saved draft zones on this level.'}</p>}
        </section>;
      })}</div>
      {otherIssues.length > 0 && <><h3>Configuration Checks</h3><ul className={styles.issues}>{otherIssues.map((issue, index) =>
        <li key={index} data-severity={issue.severity}><strong>{issue.severity === 'error' ? 'Action needed' : 'Note'}{issue.level_id ? ` · ${levelName(issue.level_id)}` : ''}{issue.zone_id ? ' · Unlisted zone' : ''}</strong>
          <p>{issue.message}</p></li>)}</ul></>}
      <section className={styles.coverage} aria-label="Validation Coverage">
        <div className={styles.coverageHeader}><h3>What Was Checked</h3><p className={styles.coverageNote}>Configuration areas included in this validation are as such:</p></div>
        <ul className={styles.checkCards} role="list">{report.checked.filter(check => report.ramp_revisions.length > 0 || check !== 'Current Directed Ramp Endpoints And Traced Measurements').map(check => {
          const [title, description] = checkDescriptions[check] ?? [check, null];
          return <li key={check}>
            <span className={styles.checkIcon} aria-hidden="true"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"><path d={checkIcons[title] ?? 'M5 3h14v18H5z M9 8h6 M9 12h6 M9 16h4'} /></svg></span>
            <div className={styles.checkCopy}><strong>{title}</strong>{description && <p>{description}</p>}</div>
          </li>;
        })}</ul>
        <div className={styles.coverageScope}><span className={styles.scopeLabel}>Levels Checked</span><ul className={styles.levelChips} aria-label="Levels Checked">{report.levels.map(level => <li key={level.id}>{level.name}</li>)}</ul>
          {report.ramp_revisions.length > 0 && <span>{report.ramp_revisions.length} cross-level connections</span>}</div>
      <details className={styles.technical}><summary>Technical Details</summary>
        <div className={styles.revisionCards}>{report.levels.map(level => <div key={level.id}><h4>{level.name}</h4><dl>
          {[['Floor Plan', level.floor_plan_revision], ['Calibration', level.calibration_revision], ['Node Draft', level.draft_revision], ['Validated Distances', level.distances_validated_revision]].map(([label, revision]) => <div key={label}><dt>{label}</dt><dd>{revision ?? 'Missing'}</dd></div>)}
        </dl></div>)}</div>
        {report.issues.filter(issue => issue.edge_id).map((issue, index) => <p className={styles.route} key={index}>Edge: {issue.edge_id} · {issue.message}</p>)}
      </details>
      </section>
    </div>}
  </section>;
}
