'use client';
import { useEffect, useState } from 'react';
import { fetchSessions, formatTimestamp, sessionLabels } from '../sessions/sessions-client.mjs';
import { PAGE_SIZE, todaySessionsQuery } from './overview-utils.mjs';
import styles from './overview.module.css';

export default function TodaySessions() {
  const [offset, setOffset] = useState(0);
  const [revision, setRevision] = useState(0);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  useEffect(() => {
    const controller = new AbortController();
    fetchSessions(todaySessionsQuery(offset), controller.signal).then(result => {
      if (!controller.signal.aborted) { setData(result); setLoading(false); }
    }).catch(failure => {
      if (!controller.signal.aborted) { setError(failure.message || 'Unable to load today’s sessions.'); setLoading(false); }
    });
    return () => controller.abort();
  }, [offset, revision]);
  function reload(nextOffset = offset) {
    setLoading(true); setData(null); setError(''); setOffset(nextOffset); setRevision(value => value + 1);
  }
  return <section className={styles.panel} aria-labelledby="today-sessions-title" aria-busy={loading}>
    <div className={styles.sectionHeading}><h2 id="today-sessions-title">Today's Parking Sessions</h2><a href="/sessions">View Sessions</a></div>
    {loading ? <p className={styles.empty} role="status">Loading Today's Sessions…</p> : error ?
      <div className={styles.empty}><p className={styles.error} role="alert">{error}</p><button className={styles.refresh} onClick={() => reload()}>Try Again</button></div> :
      data?.sessions.length === 0 ? <div className={styles.empty}><p>{offset ? 'No sessions on this page. The list may have changed.' : 'No parking sessions entered today.'}</p>{offset > 0 && <button className={styles.refresh} onClick={() => reload(0)}>First Page</button>}</div> :
      <div className={styles.tableScroll} tabIndex={0} aria-label="Scrollable Today's Parking Sessions"><table className={styles.table}>
        <thead><tr>{['Entry Time (MYT)', 'Vehicle Plate', 'Level', 'Zone', 'Current Status'].map(label => <th scope="col" key={label}>{label}</th>)}</tr></thead>
        <tbody>{data?.sessions.map(row => <tr key={row.id}>
          <td>{row.entry_time ? <time dateTime={row.entry_time}>{formatTimestamp(row.entry_time)}</time> : 'Not Available'}</td>
          <td>{row.plate_number ?? 'Not Available'}</td>
          <td>{row.level_name ?? 'Not Available'}</td>
          <td>{row.zone_name ?? 'Not Available'}</td>
          <td><span className={styles.badge}>{sessionLabels[row.status]}</span></td>
        </tr>)}</tbody>
      </table></div>}
    <nav className={styles.pagination} aria-label="Today's Sessions Pagination">
      <span aria-live="polite">Page {Math.floor(offset / PAGE_SIZE) + 1}{data ? ` · ${data.total} Sessions` : ''}</span>
      <div className={styles.paginationActions}>
        <button className={styles.refresh} disabled={loading || offset === 0} onClick={() => reload(Math.max(0, offset - PAGE_SIZE))}>Previous</button>
        <button className={styles.refresh} disabled={loading || !data || offset + PAGE_SIZE >= data.total} onClick={() => reload(offset + PAGE_SIZE)}>Next</button>
      </div>
    </nav>
  </section>;
}
