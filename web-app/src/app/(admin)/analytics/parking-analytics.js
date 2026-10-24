"use client";
import { useEffect, useState } from 'react';
import { analyticsQuery, fetchAnalytics } from './analytics-client.mjs';
import { formatMalaysiaDate, formatMalaysiaDateTime } from '../../../lib/date-format.mjs';
import HourlyChart from '../overview/hourly-chart';
import AnalyticsChart from './analytics-chart';
import UtilisationCharts from './utilisation-charts';
import styles from '../overview/overview.module.css';
import filtersStyle from './analytics.module.css';

const movementsSeries = [{ key: 'entries', label: 'Entries', colour: 'var(--chart-primary)' }, { key: 'exits', label: 'Exits', colour: 'var(--chart-comparative)' }];
const durationSeries = [{ key: 'count', label: 'Completed Sessions', colour: 'var(--chart-supporting)' }];
const number = (value) => value.toLocaleString('en-MY');
const hour = (value) => value === null ? 'N/A' : `${String(value.hour).padStart(2, '0')}:00–${String((value.hour + 1) % 24).padStart(2, '0')}:00`;
const duration = (seconds) => seconds === null ? 'N/A' : seconds < 60 ? `${Math.round(seconds)} sec` : `${(seconds / 60).toLocaleString('en-MY', { maximumFractionDigits: 1 })} min`;

export default function ParkingAnalytics() {
  const [draft, setDraft] = useState({ preset: '7', start_date: '', end_date: '', level_id: '' });
  const [applied, setApplied] = useState(draft);
  const [request, setRequest] = useState({ query: '', version: 0 });
  const [data, setData] = useState(null);
  const [levels, setLevels] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [filterError, setFilterError] = useState('');
  useEffect(() => {
    const controller = new AbortController();
    fetchAnalytics(request.query, controller.signal).then((result) => {
      if (!controller.signal.aborted) { setData(result); setLevels(result.levels); setLoading(false); }
    }).catch((failure) => { if (!controller.signal.aborted) { setError(failure.message || 'Unable to load parking analytics.'); setLoading(false); } });
    return () => controller.abort();
  }, [request]);
  function load(filters) {
    try {
      const query = analyticsQuery(filters);
      setFilterError(''); setError(''); setData(null); setLoading(true); setApplied(filters);
      setRequest((value) => ({ query, version: value.version + 1 }));
    } catch (failure) { setFilterError(failure.message); }
  }
  function field(key, value) { setDraft((current) => ({ ...current, [key]: value })); }
  const lastRefreshed = data ? formatMalaysiaDateTime(data.generated_at) : '—';
  return <div className={styles.page}>
    <div className={styles.heading}><div><h1>Parking Analytics</h1><p className={styles.muted}>{data ? `${formatMalaysiaDate(data.start_date)} to ${formatMalaysiaDate(data.end_date)} · Malaysia time · ${data.level_id ? data.levels.find((item) => item.id === data.level_id)?.name : 'All levels'}` : 'Historical vehicle movements and parking durations'}</p><p className={styles.muted}>Last refreshed: {lastRefreshed}{data ? ' MYT' : ''}</p></div><button className={styles.refresh} disabled={loading} onClick={() => load(applied)}>Refresh</button></div>
    <form className={styles.panel} onSubmit={(event) => { event.preventDefault(); load(draft); }}>
      <div className={filtersStyle.filters}>
        <label>Reporting Period<select value={draft.preset} disabled={loading} onChange={(event) => field('preset', event.target.value)}><option value="1">Today</option><option value="7">Last 7 Days</option><option value="30">Last 30 Days</option><option value="custom">Custom Date Range</option></select></label>
        {draft.preset === 'custom' && <><label>Start Date<input type="date" required value={draft.start_date} disabled={loading} onChange={(event) => field('start_date', event.target.value)} /></label><label>End Date<input type="date" required value={draft.end_date} disabled={loading} onChange={(event) => field('end_date', event.target.value)} /></label></>}
        <label>Parking Level<select value={draft.level_id} disabled={loading} onChange={(event) => field('level_id', event.target.value)}><option value="">All Levels</option>{levels.map((level) => <option key={level.id} value={level.id}>{level.name}{level.is_active ? '' : ' (Inactive)'}</option>)}</select></label>
        <button className={styles.refresh} disabled={loading} type="submit">Apply Filters</button>
      </div>
      {filterError && <p className={styles.error} role="alert">{filterError}</p>}
    </form>
    {loading ? <div className={styles.panel} role="status">Loading parking analytics…</div> : error ? <div className={styles.panel}><p className={styles.error} role="alert">{error}</p><button className={styles.refresh} onClick={() => load(applied)}>Try Again</button></div> : data && <>
      <h2 className={filtersStyle.sectionTitle}>Parking Movements and Durations</h2>
      <div className={styles.kpis}>
        <Kpi title="Total entries" value={number(data.summary.total_entries)} detail="Entry timestamps in range" />
        <Kpi title="Total exits" value={number(data.summary.total_exits)} detail="Exit timestamps in range" />
        <Kpi title="Average parking duration" value={duration(data.summary.average_duration_seconds)} detail={`${number(data.durations.valid_completed_sessions)} valid completed sessions`} />
        <Kpi title="Peak entry hour" value={hour(data.summary.peak_entry_hour)} detail={data.summary.peak_entry_hour ? `${number(data.summary.peak_entry_hour.count)} entries · hourly total` : 'No entries in range'} />
      </div>
      <AnalyticsChart id="entry-exit-trends" title="Vehicle entry and exit trends" description={data.granularity === 'hour' ? 'Hourly totals for the selected Malaysia calendar day.' : 'Daily totals by following the Malaysia calendar date.'} rows={data.movements.map(row => ({ ...row, period: data.granularity === 'hour' ? row.period : formatMalaysiaDate(row.period) }))} series={movementsSeries} unit="Vehicles" axis={data.granularity === 'hour' ? 'Hour of Day (MYT)' : 'Calendar Date (DD-MM-YYYY)'} />
      <HourlyChart hours={data.hourly_pattern} title="Hourly traffic pattern" description="Totals for each Malaysia-local hour across the selected period, not hourly averages." emptyMessage="No entries or exits in this selection" />
      <AnalyticsChart id="duration-distribution" title="Parking duration distribution" description="Completed sessions with valid timestamps and an exit in the reporting period." rows={data.durations.distribution.map((bucket) => ({ ...bucket, period: bucket.label }))} series={durationSeries} unit="Completed Sessions" axis="Parking Duration" />
      <UtilisationCharts data={data} />
    </>}
  </div>;
}
function Kpi({ title, value, detail }) { return <section className={styles.kpi}><h2>{title}</h2><strong style={{ fontSize: 'clamp(22px, 2vw, 30px)', overflowWrap: 'anywhere' }}>{value}</strong><p>{detail}</p></section>; }
