'use client';
import RefreshButton from '../../../components/refresh-button';
import { useCallback, useState } from 'react';
import useResource from '../vehicles/use-vehicle-resource';
import { fetchSessions, fetchSessionSummary, sessionSummaryQuery, formatAssignedZone, formatTimestamp, sessionLabels, sessionsQuery } from './sessions-client.mjs';
import { malaysiaToday } from '../analytics/analytics-client.mjs';
import SessionDetails from './session-details';
import styles from '../approvals/approvals.module.css';
import filtersStyle from '../analytics/analytics.module.css';
import local from './sessions.module.css';
import { SessionSummary, SessionStatusBadge } from './session-ui';
import OvernightAlerts from './overnight-alerts';

const initial = { plate: '', status: '', level_id: '', start_date: '', end_date: '' };
export default function ParkingSessions() {
  const [draft, setDraft] = useState(initial);
  const [applied, setApplied] = useState(initial);
  const [offset, setOffset] = useState(0);
  const [revision, setRevision] = useState(0);
  const [inputError, setInputError] = useState('');
  const [selection, setSelection] = useState(null);
  const query = sessionsQuery(applied, offset);
  const load = useCallback(signal => fetchSessions(query, signal), [query]);
  const resource = useResource(`sessions:${query}:${revision}`, load, 15000);
  const summaryQuery = sessionSummaryQuery(applied);
  const loadSummary = useCallback(signal => fetchSessionSummary(summaryQuery, signal), [summaryQuery]);
  const summary = useResource(`session-summary:${summaryQuery}:${revision}`, loadSummary, 15000);
  const { data, loading, error } = resource;
  const levels = (data ?? resource.previous)?.levels ?? [];
  const selectedSession = selection && (data?.sessions.find(row => row.id === selection.id) ?? selection);
  function reload(nextOffset = offset, filters = applied) {
    setApplied(filters); setOffset(nextOffset); setRevision(value => value + 1);
  }
  function apply(event) {
    event.preventDefault();
    try { sessionsQuery(draft); setInputError(''); reload(0, { ...draft }); }
    catch (failure) { setInputError(failure.message); }
  }
  function clear() { setDraft(initial); setInputError(''); reload(0, initial); }
  const filtered = Object.values(applied).some(value => value.trim());
  const unavailable = loading || Boolean(selection);
  return <div className={styles.page}>
    <div className={styles.heading}><div><h1>Parking Sessions</h1><p>Inspect active, completed, and cancelled parking sessions across the building.</p></div>
      <RefreshButton loading={loading} disabled={unavailable} onClick={() => reload()} /></div>
    <SessionSummary resource={summary} onRetry={() => setRevision(value => value + 1)} />
    <OvernightAlerts revision={revision} onViewSession={(row, overnight) => setSelection({ ...row, overnight })} />
    <form className={filtersStyle.filters} onSubmit={apply}>
      <label>Number Plate Search<input type="search" maxLength={32} value={draft.plate} onChange={event => setDraft({ ...draft, plate: event.target.value })} placeholder="Enter Number Plate" /></label>
      <label>Session Status<select value={draft.status} onChange={event => setDraft({ ...draft, status: event.target.value })}><option value="">All Statuses</option>{Object.entries(sessionLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
      <label>Parking Level<select value={draft.level_id} onChange={event => setDraft({ ...draft, level_id: event.target.value })}><option value="">All Levels</option>{levels.map(level => <option key={level.id} value={level.id}>{level.name}</option>)}</select></label>
      <label>Start Date<input type="date" min="1982-01-01" max={malaysiaToday()} value={draft.start_date} onChange={event => setDraft({ ...draft, start_date: event.target.value })} /></label>
      <label>End Date<input type="date" min={draft.start_date || '1982-01-01'} max={malaysiaToday()} value={draft.end_date} onChange={event => setDraft({ ...draft, end_date: event.target.value })} /></label>
      <button className={styles.primary} disabled={unavailable}>Apply Filters</button><button type="button" className={styles.secondary} disabled={unavailable} onClick={clear}>Clear Filters</button>
    </form>
    {inputError && <p className={styles.error} role="alert">{inputError}</p>}
    <section className={styles.card} aria-label="Parking Session Records" aria-busy={loading}>
      {loading ? <div className={styles.state} role="status">{revision ? 'Refreshing parking sessions…' : 'Loading parking sessions…'}</div> : error ?
        <div className={styles.state}><p className={styles.error} role="alert">{error}</p><button className={styles.secondary} onClick={() => reload()}>Try Again</button></div> : data?.sessions.length === 0 ?
          <div className={styles.state}><h2>{offset > 0 ? 'No Sessions on This Page' : filtered ? 'No Matching Sessions' : 'No Parking Sessions'}</h2><p>{offset > 0 ? 'The list may have changed. Return to the first page.' : filtered ? 'Adjust or clear the filters to find session records.' : 'Session records will appear here when available.'}</p>{offset > 0 && <button className={styles.secondary} onClick={() => reload(0)}>First Page</button>}</div> :
          <div className={styles.tableScroll} tabIndex={0} aria-label="Scrollable Parking Sessions Table"><table className={`${styles.table} ${local.table}`}><caption className={styles.srOnly}>Parking Sessions — Times in Malaysia Time</caption>
            <thead><tr>{['Number Plate', 'Parking Level', 'Assigned Zone', 'Status', 'Entry Time (MYT)', 'Exit Time (MYT)', 'Details'].map(label => <th scope="col" key={label}>{label}</th>)}</tr></thead>
            <tbody>{data?.sessions.map(session => <tr key={session.id}><td><strong>{session.plate_number || 'Not available'}</strong></td><td>{session.level_name || 'Not Available'}</td><td className={local.zoneCell}>{formatAssignedZone(session.zone_name, session.level_name)}</td><td><SessionStatusBadge status={session.status} /></td>
              <td>{session.entry_time ? <time dateTime={session.entry_time} title={formatTimestamp(session.entry_time)}>{formatTimestamp(session.entry_time)}</time> : 'Not Available'}</td><td>{session.exit_time ? <time dateTime={session.exit_time} title={formatTimestamp(session.exit_time)}>{formatTimestamp(session.exit_time)}</time> : 'Not Available'}</td>
              <td className={local.detailsCell}><button className={styles.secondary} onClick={() => setSelection(session)} aria-label={`View details for ${session.plate_number || session.id}`}>View Details</button></td></tr>)}</tbody>
          </table></div>}
      <nav className={styles.pagination} aria-label="Sessions Pagination"><span>Page {Math.floor(offset / 25) + 1}{data ? ` · ${data.total} Matching Records${data.sessions.length ? ` · Showing ${offset + 1}–${offset + data.sessions.length}` : ''}` : ''}</span>
        <div className={styles.actions}><button className={styles.secondary} disabled={unavailable || offset === 0} onClick={() => reload(Math.max(0, offset - 25))}>Previous</button><button className={styles.secondary} disabled={unavailable || !data || offset + 25 >= data.total} onClick={() => reload(offset + 25)}>Next</button></div></nav>
    </section>
    {selectedSession && <SessionDetails session={selectedSession} overnight={selection.overnight} isListed={Boolean(data?.sessions.some(row => row.id === selectedSession.id))} onClose={() => setSelection(null)} />}
  </div>;
}
