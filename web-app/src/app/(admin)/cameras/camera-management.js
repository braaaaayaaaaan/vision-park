'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import RefreshButton from '../../../components/refresh-button';
import MetricIcon from '../../../components/metric-icon';
import useConfirmation from '../../../components/use-confirmation';
import useResource from '../vehicles/use-vehicle-resource';
import { formatMalaysiaDateTime } from '../../../lib/date-format.mjs';
import { outcomeLabels, reasonLabels } from '../../../lib/cameras-contracts.mjs';
import { browserRuns, fetchCameras, fetchActivity, fetchEvent, fetchPlayback } from './cameras-client.mjs';
import styles from './cameras.module.css';

const label = value => outcomeLabels[value] ?? value?.replaceAll('_', ' ') ?? 'Not available';
function Badge({ value, children }) {
  return <span className={styles.badge} data-state={value}>{children ?? label(value)}</span>;
}
export function Results({ result }) {
  if (!result) return null;
  return <section className={styles.results} aria-label="Latest Processing Results">
    <div className={styles.sectionHeading}><h3>Latest Results</h3><span>{result.results.length} vehicle{result.results.length === 1 ? '' : 's'}</span></div>
    {result.status === 'no_recognition' && <p>No confirmed plates were recognised. No parking allocation or exit was created.</p>}
    {result.status && result.status !== 'no_recognition' && <p>{label(result.status)}</p>}
    <ul className={styles.resultList}>{result.results.map((row, index) => <li key={`${row.event.plate_number}:${index}`}>
      <div className={styles.resultHeading}><strong className={styles.plate}>{row.event.plate_number}</strong><Badge value={row.status} /></div>
      <p>{row.allocation ? `${row.allocation.level_name ?? 'Level unavailable'} · ${row.allocation.zone_name ?? 'Zone unavailable'}` :
        reasonLabels[row.code] || reasonLabels[row.status] || (row.status === 'completed' || row.status === 'payment_succeeded' ? 'Completed Exit Settlement.' : row.code ? label(row.code) : '')}</p>
      <small><span className={styles.capitalise}>{row.event.camera_role}</span> · Accepted: {formatMalaysiaDateTime(row.accepted_event_time, { seconds: true })} MYT</small>
    </li>)}</ul>
    {typeof result.duration_seconds === 'number' && <p className={styles.note}>Request completed in {result.duration_seconds.toFixed(1)} seconds{result.recovered ? ' · Recovered existing recognition set' : ''}.</p>}
  </section>;
}

export function CameraCard({ camera, active, onChanged }) {
  const [run, setRun] = useState(null), [busy, setBusy] = useState(false), [error, setError] = useState('');
  const [result, setResult] = useState(null), [revision, setRevision] = useState(0), [uncertain, setUncertain] = useState(false);
  const [mediaFailed, setMediaFailed] = useState(false);
  const [expanded, setExpanded] = useState(true);
  const video = useRef(null);
  const inFlight = useRef(false);
  const { requestConfirmation, confirmationDialog } = useConfirmation({ disabled: () => inFlight.current });
  useEffect(() => {
    const recover = () => { try { const saved = browserRuns().restore(camera.role); setRun(saved); setUncertain(Boolean(saved)); } catch { /* Processing will explain unavailable storage. */ } };
    const timer = setTimeout(recover, 0);
    const sync = event => { if (event.key?.startsWith('visionpark-camera-run:')) recover(); };
    window.addEventListener('storage', sync);
    return () => { clearTimeout(timer); window.removeEventListener('storage', sync); };
  }, [camera.role]);
  const loadSaved = useCallback(signal => run ? fetchPlayback(run, signal) : Promise.resolve(null), [run]);
  const shouldPoll = useCallback(value => Boolean(run && value?.active_run?.playback_id === run.playback_id), [run]);
  const saved = useResource(`camera-run:${run?.playback_id ?? camera.role}:${revision}:${active?.playback_id ?? ''}:${busy}`, loadSaved,
    run ? 15000 : 0, { enabled: expanded, shouldPoll });
  const activeNow = active || saved.data?.active_run;
  const blocked = busy || Boolean(activeNow);
  const knownErrors = result?.results.some(row => row.status === 'error');
  const failedRun = knownErrors || result?.status && result.status !== 'no_recognition';
  const state = busy || activeNow?.role === camera.role ? 'processing' : error || failedRun || uncertain ? 'failed' : result ? 'completed' : 'idle';
  const retryAvailable = Boolean(run && saved.data?.saved && !saved.error && !blocked);
  const startAvailable = camera.available && camera.start_context && !camera.start_problem && !blocked && !uncertain && !knownErrors;
  async function execute(action) {
    if (inFlight.current) return false;
    inFlight.current = true; setBusy(true); setError('');
    let prepared = false;
    try {
      const response = await browserRuns().execute(camera, action, run, context => {
        prepared = true; setRun(context); setUncertain(true); setResult(null);
      });
      setResult(response); setUncertain(false);
    } catch (failure) {
      setError(failure.message);
      if (failure.results) setResult({ results: failure.results });
      if (prepared) setUncertain(true);
    } finally {
      inFlight.current = false; setBusy(false); setRevision(value => value + 1); onChanged();
    }
  }
  function start() {
    requestConfirmation({ title: `Start New ${camera.role === 'entrance' ? 'Entrance' : 'Exit'} Processing?`,
      description: camera.role === 'entrance' ? 'This scans the complete recording as a new visit and can allocate parking for every confirmed vehicle. Retry an existing run to recover an earlier operation.' :
        'This scans the complete recording as a new exit operation. Existing payment and settlement rules apply to each recognised vehicle.',
      confirmLabel: 'Start New Processing', pendingLabel: 'Processing recording…',
    }, () => execute('start'));
  }
  return <><details open className={styles.camera} aria-labelledby={`camera-${camera.role}`} aria-busy={busy} onToggle={event => {
    if (event.target === event.currentTarget) {
      setExpanded(event.currentTarget.open);
      if (!event.currentTarget.open) video.current?.pause();
    }
  }}>
    <summary className={styles.cameraHeading}><div className={styles.titleGroup}><MetricIcon name={camera.role === 'entrance' ? 'entry' : 'exit'} /><div><p className={styles.eyebrow}>Recorded {camera.role}</p><h2 id={`camera-${camera.role}`}>{camera.name}</h2><p className={styles.cameraFilename}>{camera.filename}</p></div></div>
      <span className={styles.cameraSummaryMeta}><Badge value={state}>{({ idle: 'Idle', processing: 'Processing', completed: 'Completed', failed: 'Failed' })[state]}</Badge>
        <span className={styles.cameraChevron}><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="m6 9 6 6 6-6" /></svg></span></span></summary>
    <div className={styles.cameraContent}>
    <div className={styles.cameraMedia}>
    <div className={styles.preview}>{camera.available ? <video ref={video} controls playsInline preload="metadata" aria-label={`${camera.name} recording preview`}
      src={`/api/cameras/${camera.role}/recording`} onError={() => setMediaFailed(true)} onLoadedMetadata={() => setMediaFailed(false)} /> : <p>Recording unavailable</p>}</div>
      <div className={styles.cameraActions}><button className={styles.primary} disabled={!startAvailable} onClick={start}>{busy ? 'Processing…' : 'Start New Processing'}</button>
        <button className={styles.secondary} disabled={!retryAvailable} onClick={() => execute('retry')}>Retry Existing Processing</button></div>
    </div>
    <div className={styles.cameraBody}>
      <section className={styles.operationPanel} aria-label={`${camera.name} processing information`} tabIndex={0}>
      <div className={styles.operationHeading}><h3>Processing Overview</h3><span>{busy || activeNow?.role === camera.role ? 'In progress' : result ? 'Latest run' : run ? 'Saved run' : camera.available && camera.start_context && !camera.start_problem ? 'Ready when you are' : 'Setup needed'}</span></div>
      {mediaFailed && <div><p className={styles.error} role="alert">Preview could not load. Check your connection and retry.</p><button className={styles.textButton} onClick={async () => {
        try { await fetchCameras(); video.current?.load(); } catch (failure) { setError(failure.message); }
      }}>Reload Preview</button></div>}
      {camera.start_problem && <p className={styles.warning}>{camera.start_problem} <a href="/parking-structure">Open Parking Structure</a></p>}
      {activeNow && <p className={styles.note} role="status">{activeNow.role === camera.role ? 'Processing the complete recording. Results appear after recognition and vehicle processing finish.' : 'The other camera is processing. Wait for its outcome before starting.'}</p>}
      {error && <p className={styles.error} role="alert">{error}</p>}
      {uncertain && <p className={styles.warning}>Outcome unconfirmed after interruption. Inspect this run before starting a replacement.</p>}
      <Results result={result} />
      {saved.data?.saved && !result && <section className={styles.results} aria-label="Latest Saved Results"><div className={styles.sectionHeading}><h3>Latest Saved Results</h3><span>{saved.data.events.length} {saved.data.events.length === 1 ? 'vehicle' : 'vehicles'}</span></div>
        <ul className={styles.resultList}>{saved.data.events.map(event => <li key={event.id}><div className={styles.resultHeading}><strong className={styles.plate}>{event.plate_number}</strong><Badge value={event.outcome} /></div>
          <p>{[event.assigned_level, event.assigned_zone].filter(Boolean).join(' · ') || event.reason}</p><small><span className={styles.capitalise}>{event.camera_role}</span> · {formatMalaysiaDateTime(event.accepted_event_time, { seconds: true })} MYT</small></li>)}</ul></section>}
      {!run && !result && !busy && !activeNow && !error && !camera.start_problem && !mediaFailed && <div className={styles.cameraEmpty}>
        <MetricIcon name={camera.role === 'entrance' ? 'allocated' : 'payments'} />
        <h4>{camera.role === 'entrance' ? 'Ready for Arrival Processing' : 'Ready for Exit Processing'}</h4>
        <p>{camera.role === 'entrance' ? 'Recognised plates and assigned parking zones will appear here.' : 'Recognised plates, payment requirements and exit outcomes will appear here.'}</p>
      </div>}
      {run && <details className={styles.recovery}><summary><span>Run Recovery<small>Original Identity and Saved Results</small></span><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true"><path d="m6 9 6 6 6-6" /></svg></summary>
        <div className={styles.recoveryBody}><button className={styles.textButton} disabled={busy} onClick={() => { setRevision(value => value + 1); onChanged(); }}>Inspect Saved Results</button>
        <p className={styles.runId}>{run.playback_id}</p>
        {saved.loading ? <p className={styles.note}>Checking original recognition set…</p> : saved.error ? <p className={styles.error}>{saved.error}</p> :
          <p className={styles.note}>{saved.data?.saved ? 'The original recognition set is saved. Retry uses this identity without another OCR scan.' : 'No saved recognition set was found. Retry is unavailable. This does not prove an interrupted request stopped.'}</p>}
        {uncertain && !blocked && saved.data && <button className={styles.textButton} onClick={() => requestConfirmation({ title: 'Finish Reviewing This Run?',
          description: 'Only continue if the original request has stopped and you have reviewed its saved results. A new scan represents a separate operation; it does not recover this run.',
          confirmLabel: 'Review Complete',
        }, async () => { setUncertain(false); setError(''); })}>Finish Review</button>}
      </div></details>}
      </section>
      <p className={styles.cameraFooter}>Complete Recording Scan <span aria-hidden="true">·</span> {camera.role === 'entrance' ? 'Parking Allocation' : 'Payment-Aware Exit'}</p>
    </div></div>
  </details>{confirmationDialog}</>;
}

export function EventDrawer({ eventId, onClose }) {
  const dialog = useRef(null), close = useRef(null);
  const load = useCallback(signal => fetchEvent(eventId, signal), [eventId]);
  const resource = useResource(`camera-event:${eventId}`, load, 15000);
  useEffect(() => {
    const element = dialog.current, origin = document.activeElement, overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden'; element.showModal(); close.current?.focus();
    return () => { element.close(); document.body.style.overflow = overflow; if (origin?.isConnected) origin.focus(); };
  }, []);
  const item = resource.data;
  const fields = item ? [
    ['Number Plate', item.plate_number], ['Camera Role', item.camera_role], ['Accepted Event Time (MYT)', formatMalaysiaDateTime(item.accepted_event_time, { seconds: true })],
    ['Recording Offset', item.source_time_seconds == null ? null : `${item.source_time_seconds} seconds`],
    ['Saved Event Outcome', label(item.outcome)], ['Explanation', item.reason], ['Assigned Level', item.assigned_level], ['Assigned Zone', item.assigned_zone],
    ['Playback Identity', item.playback_id], ['Event Identity', item.event_id], ['Parking Session', item.session_id],
  ] : [];
  const session = item?.current_session;
  return <dialog ref={dialog} className={styles.drawer} aria-labelledby="recognition-details-title" onCancel={event => { event.preventDefault(); onClose(); }}>
    <header className={styles.drawerHeading}><div><p className={styles.eyebrow}>Recognition Activity</p><h2 id="recognition-details-title">Recognition Details</h2></div><button ref={close} className={styles.secondary} onClick={onClose} aria-label="Close Recognition Details">Close</button></header>
    <div className={styles.drawerBody}>{resource.loading ? <p role="status">Loading recognition details…</p> : resource.error ? <p className={styles.error} role="alert">{resource.error}</p> : <>
      <dl className={styles.fields}>{fields.map(([name, value]) => <div key={name}><dt>{name}</dt><dd>{value ?? 'Not Recorded'}</dd></div>)}</dl>
      <section className={styles.detailSection}><h3>Current Parking Session</h3><p className={styles.note}>Current state is separate from the original recognition outcome.</p>
        {session ? <dl className={styles.fields}>{[['Status', label(session.status)], ['Current Level', session.zone?.level?.name], ['Current Zone', session.zone?.name], ['Exit Time (MYT)', session.exit_time ? formatMalaysiaDateTime(session.exit_time) : null]].map(([name, value]) => <div key={name}><dt>{name}</dt><dd>{value ?? 'Not Recorded'}</dd></div>)}</dl> : <p>No bound session was recorded.</p>}</section>
      <section className={styles.detailSection}><h3>Current Payment</h3>{item?.current_payment ? <dl className={styles.fields}><div><dt>Status</dt><dd>{label(item.current_payment.status)}</dd></div><div><dt>Quoted Amount</dt><dd>{item.current_payment.amount_sen == null ? 'Not Quoted' : `RM ${(item.current_payment.amount_sen / 100).toFixed(2)}`}</dd></div><div><dt>Paid At (MYT)</dt><dd>{item.current_payment.paid_at ? formatMalaysiaDateTime(item.current_payment.paid_at) : 'Not Paid'}</dd></div></dl> : <p>No payment charge was recorded.</p>}</section>
      <p className={styles.note}>Retry requires this run’s retained recording and original entrance context. Viewing an event does not process it.</p>
    </>}</div>
  </dialog>;
}

const initialFilters = { role: '', plate: '', result: '', start_date: '', end_date: '' };
export default function CameraManagement() {
  const [revision, setRevision] = useState(0), [draft, setDraft] = useState(initialFilters), [filters, setFilters] = useState(initialFilters);
  const [offset, setOffset] = useState(0), [selection, setSelection] = useState(null);
  const load = useCallback(signal => fetchCameras(signal), []);
  const cameras = useResource(`cameras:${revision}`, load, 15000);
  const params = new URLSearchParams({ limit: '25', offset: String(offset) });
  Object.entries(filters).forEach(([key, value]) => { if (value) params.set(key, value); });
  const query = params.toString();
  const loadActivity = useCallback(signal => fetchActivity(query, signal), [query]);
  const activity = useResource(`recognitions:${query}:${revision}`, loadActivity, 15000);
  const metadata = cameras.data ?? cameras.previous;
  const refresh = () => setRevision(value => value + 1);
  return <div className={styles.page}>
    <header className={styles.pageHeading}><div><p className={styles.eyebrow}>Entrance and Exit Operations</p><h1>Camera Management</h1><p>Preview footage, process recognised vehicles, and inspect ANPR activity.</p></div><RefreshButton loading={cameras.loading || activity.loading} onClick={refresh} /></header>
    <div className={styles.notice}><MetricIcon name="sessions" /><p><strong>Camera Video Workspace</strong><br />Retries becomes available after a run’s original context and recognition set have been saved. Historical events remain available.</p></div>
    {cameras.loading && <div className={styles.state} role="status">Loading cameras…</div>}
    {cameras.error && <div className={styles.state}><p className={styles.error} role="alert">{cameras.error}</p><button className={styles.secondary} onClick={refresh}>Try Again</button></div>}
    <div className={styles.cameraGrid}>{metadata?.cameras.map(camera => <CameraCard key={camera.role} camera={camera} active={metadata.active_run} onChanged={refresh} />)}</div>
    <section className={styles.activity} aria-labelledby="recognition-activity-title"><header className={styles.activityHeading}><div><p className={styles.eyebrow}>Saved ANPR Events</p><h2 id="recognition-activity-title">Recent Recognition Activity</h2><p>Original outcomes and linked parking records. Times shown in MYT.</p></div></header>
      <form className={styles.filters} onSubmit={event => { event.preventDefault(); setFilters({ ...draft }); setOffset(0); }}>
        <label>Camera Role<select value={draft.role} onChange={event => setDraft({ ...draft, role: event.target.value })}><option value="">All Roles</option><option value="entrance">Entrance</option><option value="exit">Exit</option></select></label>
        <label>Number Plate<input type="search" pattern="[A-Za-z0-9]*" maxLength={32} placeholder="Search Plate" value={draft.plate} onChange={event => setDraft({ ...draft, plate: event.target.value.toUpperCase() })} /></label>
        <label>Saved Result<select value={draft.result} onChange={event => setDraft({ ...draft, result: event.target.value })}><option value="">All Results</option>{Object.entries(outcomeLabels).filter(([value]) => value !== 'unclassified' && value !== 'error').map(([value, title]) => <option key={value} value={value}>{title}</option>)}</select></label>
        <label>Start Date<input type="date" value={draft.start_date} max={draft.end_date || undefined} onChange={event => setDraft({ ...draft, start_date: event.target.value })} /></label>
        <label>End Date<input type="date" value={draft.end_date} min={draft.start_date || undefined} onChange={event => setDraft({ ...draft, end_date: event.target.value })} /></label>
        <div className={styles.actions}><button className={styles.primary}>Apply Filters</button><button type="button" className={styles.secondary} onClick={() => { setDraft(initialFilters); setFilters(initialFilters); setOffset(0); }}>Clear</button></div>
      </form>
      {activity.loading ? <div className={styles.state} role="status">Loading recognition activity…</div> : activity.error ? <div className={styles.state}><p className={styles.error} role="alert">{activity.error}</p><button className={styles.secondary} onClick={refresh}>Try Again</button></div> : !activity.data?.events.length ? <div className={styles.state}><h3>No Recognition Events</h3><p>Saved events appear after a complete recognition set is registered. Adjust filters to inspect earlier activity.</p></div> :
        <div className={styles.tableScroll} tabIndex={0} aria-label="Scrollable recognition activity"><table><caption className={styles.srOnly}>Persisted recognition events, times in Malaysia time</caption><thead><tr>{['Number Plate', 'Role', 'Accepted Time (MYT)', 'Saved Outcome', 'Assignment', 'Details'].map(title => <th scope="col" key={title}>{title}</th>)}</tr></thead><tbody>{activity.data.events.map(event => <tr key={event.id}>
          <td><strong className={styles.plate}>{event.plate_number}</strong></td><td className={styles.capitalise}>{event.camera_role}</td><td>{formatMalaysiaDateTime(event.accepted_event_time, { seconds: true })}</td><td><Badge value={event.outcome} /></td><td>{[event.assigned_level, event.assigned_zone].filter(Boolean).join(' · ') || 'Not Recorded'}</td><td><button className={styles.textButton} onClick={() => setSelection(event.id)} aria-label={`View recognition details for ${event.plate_number}`}>View Details</button></td>
        </tr>)}</tbody></table></div>}
      {activity.data && <footer className={styles.pagination}><p>{activity.data.total} saved event{activity.data.total === 1 ? '' : 's'} · Page {Math.floor(offset / 25) + 1}</p><div className={styles.actions}><button className={styles.secondary} disabled={!offset || activity.loading} onClick={() => setOffset(Math.max(0, offset - 25))}>Previous</button><button className={styles.secondary} disabled={offset + 25 >= activity.data.total || activity.loading} onClick={() => setOffset(offset + 25)}>Next</button></div></footer>}
    </section>{selection && <EventDrawer key={selection} eventId={selection} onClose={() => setSelection(null)} />}
  </div>;
}
