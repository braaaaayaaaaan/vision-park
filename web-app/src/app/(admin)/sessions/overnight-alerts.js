'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import useConfirmation from '../../../components/use-confirmation';
import { reminderMessage } from '../../../lib/parking-reminder-contracts.mjs';
import { fetchParkingReminders, sendParkingReminder } from './parking-reminder-client.mjs';
import useResource from '../vehicles/use-vehicle-resource';
import RefreshButton from '../../../components/refresh-button';
import OverviewNotice from '../overview/overview-notice';
import SuccessNotice from '../../../components/success-notice';
import { analyticsQuery, malaysiaToday } from '../analytics/analytics-client.mjs';
import { fetchOvernightAlerts } from './overnight-client.mjs';
import { formatAssignedZone, formatDuration, formatTimestamp } from './sessions-client.mjs';
import { SessionStatusBadge } from './session-ui';
import shared from '../approvals/approvals.module.css';
import styles from './overnight-alerts.module.css';
import { startVisiblePolling } from '../../../lib/visible-polling.mjs';

function useCurrentAlerts(key, load) {
  const [state, setState] = useState({ key: null, data: null, error: '' });
  useEffect(() => startVisiblePolling({ load,
    success: data => setState({ key, data, error: '' }),
    // Do not keep claiming a vehicle is currently present after a failed check.
    failure: error => setState({ key, data: null, error: error.message || 'Current overnight stays could not be checked. Please retry.' }),
  }), [key, load]);
  return state.key === key ? { ...state, loading: false } : { data: null, error: '', loading: true };
}

function lastWeek() {
  const end_date = malaysiaToday();
  return { start_date: new Date(Date.parse(end_date) - 6 * 86400000).toISOString().slice(0, 10), end_date };
}

function useDriverReminders(data, enabled) {
  const ids = enabled ? data?.alerts.map(alert => alert.session.id).join(',') || '' : '';
  const [revision, setRevision] = useState(0), [notice, setNotice] = useState('');
  const requests = useRef({});
  const load = useCallback(async signal => ({ ...(ids ? await fetchParkingReminders(ids.split(','), signal) : { reminders: [] }), checkedAt: Date.now() }), [ids]);
  const resource = useCurrentAlerts(`parking-reminders:${ids}:${revision}`, load);
  const { requestConfirmation, confirmationDialog } = useConfirmation();
  function remind(row) {
    requests.current[row.id] ??= crypto.randomUUID();
    requestConfirmation({ title: 'Send Parking Status Reminder', confirmLabel: 'Send Reminder', pendingLabel: 'Sending reminder…',
      description: `Send an in-app reminder to the driver of ${row.plate_number || 'this vehicle'}?`,
      children: <p>{reminderMessage}</p>,
    }, async () => {
      await sendParkingReminder({ session_id: row.id, request_id: requests.current[row.id] });
      delete requests.current[row.id];
      setNotice(`Reminder saved for Vehicle:${row.plate_number || 'this vehicle'}.`);
      setRevision(value => value + 1);
    });
  }
  function detailContext(row) {
    return { reminder: resource.data?.reminders.find(item => item.session_id === row.id), reminderCheckedAt: resource.data?.checkedAt };
  }
  function actions(row, detailsButton) {
    const reminder = resource.data?.reminders.find(item => item.session_id === row.id);
    const cooling = reminder && resource.data.checkedAt < Date.parse(reminder.sent_at) + 15 * 60000;
    return <div className={styles.reminderActions}>
      <div className={styles.rowActions}>
      <button type="button" className={shared.primary} disabled={!resource.data || cooling} onClick={() => remind(row)} aria-label={`Send reminder for ${row.plate_number || row.id}`}>
        <svg aria-hidden="true" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9 M10 21h4" /></svg> Send Reminder
      </button>
      {detailsButton}
      </div>
      {reminder && <small className={reminder.response ? styles.driverResponse : undefined}>
        {reminder.response === 'still_parked' ? 'Confirmed: Currently Parked' : reminder.response === 'already_left' ? 'Already left — Review Session' : 'Awaiting Driver Response'}
      </small>}
    </div>;
  }
  return { actions, detailContext, content: <>
    {notice && <SuccessNotice>{notice}</SuccessNotice>}
    {resource.loading && <p className={styles.checked} role="status">Checking driver reminders…</p>}
    {resource.error && <div className={styles.retryRow}><p className={shared.error} role="alert">{resource.error}</p><RefreshButton label="Retry Driver Reminders" onClick={() => setRevision(value => value + 1)} /></div>}
    {confirmationDialog}
  </> };
}

function AlertTable({ data, onViewSession, reminderActions, reminderContext }) {
  return <div className={styles.tableScroll} tabIndex={0} aria-label={`${data.kind === 'current' ? 'Current' : 'Past'} Overnight Stays`}>
    <table className={`${shared.table} ${styles.table}`}>
      <caption className={shared.srOnly}>Overnight Parking Sessions — Malaysia Time</caption>
      <colgroup><col className={styles.vehicleColumn} /><col className={styles.locationColumn} /><col className={styles.durationColumn} /><col className={styles.statusColumn} /><col className={styles.actionsColumn} /></colgroup>
      <thead><tr>{['Vehicle and Driver', 'Parking Location', 'Past Midnight', data.kind === 'current' ? 'Session Status' : 'Exit Time (MYT)', 'Actions'].map(label => <th scope="col" key={label}>{label}</th>)}</tr></thead>
      <tbody>{data.alerts.map(alert => {
        const row = alert.session;
        const detailsButton = <button type="button" className={`${shared.secondary} ${styles.viewSession}`} onClick={() => onViewSession(row, { ...alert, kind: data.kind, ...reminderContext?.(row) })} aria-label={`View overnight session for ${row.plate_number || row.id}`}>View Session</button>;
        return <tr key={row.id}>
          <td><strong className={styles.plate}>{row.plate_number || 'Plate not available'}</strong><small>{alert.driver_name || 'Driver not available'}</small></td>
          <td>{row.level_name || 'Level not available'}<small>{formatAssignedZone(row.zone_name, row.level_name)}</small></td>
          <td><strong>{formatDuration(alert.seconds_after_midnight)}</strong><small>{alert.midnights_crossed} {alert.midnights_crossed === 1 ? 'Midnight' : 'Midnights'} Crossed</small></td>
          <td>{data.kind === 'current' ? <SessionStatusBadge status={row.status} /> : formatTimestamp(row.exit_time)}</td>
          <td className={styles.actionsCell}>{reminderActions ? reminderActions(row, detailsButton) : <div className={styles.rowActions}>{detailsButton}</div>}</td>
        </tr>;
      })}</tbody>
    </table>
  </div>;
}

function AlertPage({ resource, offset, onPage, onRetry, onViewSession, reminderActions, reminderContext }) {
  const { data, loading, error } = resource;
  return <>
    {loading ? <p className={styles.message} role="status">Checking overnight parking stays…</p> : error ?
      <div className={styles.message}><p className={shared.error} role="alert">{error}</p><button type="button" className={shared.secondary} onClick={onRetry}>Retry Overnight Alerts</button></div> : data && <>
        {!data.alerts.length ? <OverviewNotice><p>{offset ? 'No overnight stays on this page. Return to the first page.' : data.kind === 'current' ? 'Currently, there are no active overnight stays' : 'No completed overnight stays were recorded for these exit dates.'}</p></OverviewNotice> : <AlertTable data={data} onViewSession={onViewSession} reminderActions={reminderActions} reminderContext={reminderContext} />}
        <nav className={styles.pagination} aria-label={`${data.kind === 'current' ? 'Current' : 'Past'} Overnight Stays Pagination`}>
          <span>Page {Math.floor(offset / data.limit) + 1} · {data.total} Overnight {data.total === 1 ? 'Stay' : 'Stays'}</span>
          <div className={shared.actions}><button type="button" className={shared.secondary} disabled={!offset} onClick={() => onPage(Math.max(0, offset - data.limit))}>Previous Alerts</button>
            <button type="button" className={shared.secondary} disabled={offset + data.limit >= data.total} onClick={() => onPage(offset + data.limit)}>Next Alerts</button></div>
        </nav>
        <p className={styles.checked}>Last Checked: {formatTimestamp(data.generated_at)}</p>
      </>}
  </>;
}

function PastOvernightStays({ revision, onViewSession }) {
  const [range, setRange] = useState(lastWeek), [draft, setDraft] = useState(range), [offset, setOffset] = useState(0);
  const [preset, setPreset] = useState('7');
  const [retry, setRetry] = useState(0), [inputError, setInputError] = useState('');
  const query = new URLSearchParams({ kind: 'past', limit: '10', offset: String(offset), ...range }).toString();
  const load = useCallback(signal => fetchOvernightAlerts(query, signal), [query]);
  const resource = useResource(`overnight-history:${query}:${revision}:${retry}`, load);
  function selectPreset(value) {
    setPreset(value); setInputError('');
    if (value === '7') setDraft(lastWeek());
  }
  function apply(event) {
    event.preventDefault();
    try {
      const dates = preset === '7' ? lastWeek() : { ...draft };
      analyticsQuery({ ...dates, preset: 'custom' }); setDraft(dates); setRange(dates); setOffset(0); setInputError(''); setRetry(value => value + 1);
    } catch (error) { setInputError(error.message); }
  }
  return <div className={styles.history}>
    <p className={styles.explanation}>Completed sessions after midnight.</p>
    <form className={styles.filters} aria-label="Past Stays Date Filters" aria-describedby="overnight-exit-dates-help" onSubmit={apply}>
      <label className={styles.filterField}><span>Exit Date Range</span><select value={preset} disabled={resource.loading} onChange={event => selectPreset(event.target.value)}>
        <option value="7">Last 7 Days</option><option value="custom">Custom Date Range</option>
      </select></label>
      <label className={styles.filterField}><span>Exit Date From</span><input type="date" min="1982-01-01" max={malaysiaToday()} value={draft.start_date} disabled={preset !== 'custom' || resource.loading} onChange={event => { setDraft(old => ({ ...old, start_date: event.target.value })); setInputError(''); }} required /></label>
      <label className={styles.filterField}><span>Exit Date To</span><input type="date" min={draft.start_date || '1982-01-01'} max={malaysiaToday()} value={draft.end_date} disabled={preset !== 'custom' || resource.loading} onChange={event => { setDraft(old => ({ ...old, end_date: event.target.value })); setInputError(''); }} required /></label>
      <button type="submit" className={`${shared.primary} ${styles.applyFilters}`} disabled={resource.loading}>Apply Filters</button>
    </form>
    <p id="overnight-exit-dates-help" className={styles.filterHelp}>Dates use Malaysia time. Choose Custom Date Range to select up to 90 days.</p>
    {inputError && <p className={shared.error} role="alert">{inputError}</p>}
    <AlertPage resource={resource} offset={offset} onPage={setOffset} onRetry={() => setRetry(value => value + 1)} onViewSession={onViewSession} />
  </div>;
}

export default function OvernightAlerts({ compact = false, revision = 0, onViewSession }) {
  const [offset, setOffset] = useState(0), [retry, setRetry] = useState(0), [tab, setTab] = useState('current');
  const query = new URLSearchParams({ kind: 'current', limit: compact ? '5' : '10', offset: compact ? '0' : String(offset) }).toString();
  const load = useCallback(signal => fetchOvernightAlerts(query, signal), [query]);
  const resource = useCurrentAlerts(`overnight-current:${query}:${revision}:${retry}`, load);
  const data = resource.data, active = Boolean(data?.total);
  const reminders = useDriverReminders(data, !compact && tab === 'current');
  const id = compact ? 'overview-overnight-alerts' : 'overnight-alerts';
  return <section id={id} className={styles.panel} data-active={active} aria-labelledby={`${id}-title`}>
    <header className={styles.heading}>
      <div className={styles.headingTitle}><span className={styles.icon} aria-hidden="true"><svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3 2 21h20L12 3Z M12 9v5 M12 17h.01" /></svg></span>
        <div><h2 id={`${id}-title`}>Overnight Parking Alerts</h2><p>Representing building-wide alerts.</p></div></div>
      <RefreshButton label="Refresh Overnight Alerts" loading={resource.loading} onClick={() => { setOffset(0); setRetry(value => value + 1); }} />
    </header>
    {data && <OverviewNotice><p>{active ? `${data.total} active ${data.total === 1 ? 'session has' : 'sessions have'} stayed past midnight.` : 'Currently, there are no active overnight stays'}</p></OverviewNotice>}
    {!compact && <div className={styles.tabs} role="group" aria-label="Overnight Alert View">
      <button type="button" aria-label="Current Overnight Stays" aria-pressed={tab === 'current'} onClick={() => setTab('current')}>Current Stays{data ? ` (${data.total})` : ''}</button>
      <button type="button" aria-label="Past Overnight Stays" aria-pressed={tab === 'past'} onClick={() => setTab('past')}>Past Stays</button>
    </div>}
    {!compact && tab === 'past' ? <>
      {resource.error && <p className={shared.error} role="alert">Current-stay alerts could not be checked. Refresh to try again.</p>}
      <PastOvernightStays revision={`${revision}:${retry}`} onViewSession={onViewSession} />
    </> : compact ? <>
      {resource.loading ? <p className={styles.message} role="status">Checking overnight parking stays…</p> : resource.error ? <p className={shared.error} role="alert">{resource.error}</p> : data && <>
        {active && <ul className={styles.preview}>{data.alerts.map(alert => <li key={alert.session.id}>
          <div><strong>{alert.session.plate_number || 'Plate not available'}</strong><span>{alert.driver_name || 'Driver not available'}</span></div>
          <p>{alert.session.level_name || 'Level not available'} · {formatAssignedZone(alert.session.zone_name, alert.session.level_name)} · Entered {formatTimestamp(alert.session.entry_time)}</p>
        </li>)}</ul>}
        <p className={styles.checked}>Last Checked: {formatTimestamp(data.generated_at)}</p>
      </>}
      <a className={styles.link} href="/sessions#overnight-alerts">View Current and Past Overnight Stays</a>
    </> : <>
      <p className={styles.explanation}>Allocated or occupied sessions with a recorded entry before their first midnight and no recorded exit.</p>
      {reminders.content}
      <AlertPage resource={resource} offset={offset} onPage={setOffset} onRetry={() => setRetry(value => value + 1)} onViewSession={onViewSession} reminderActions={reminders.actions} reminderContext={reminders.detailContext} />
    </>}
  </section>;
}
