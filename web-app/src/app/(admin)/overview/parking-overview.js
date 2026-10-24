"use client";
import { useEffect, useState } from 'react';
import HourlyChart from './hourly-chart';
import TodaySessions from './today-sessions';
import { occupancyBand, occupancyBands, occupancyPercentage } from './overview-utils.mjs';
import { fetchOverview } from './overview-client';
import { formatMalaysiaDate, formatMalaysiaDateTime } from '../../../lib/date-format.mjs';
import styles from './overview.module.css';

const number = (value) => value.toLocaleString('en-MY');
const percent = (value) => value === null ? 'N/A' : `${value.toLocaleString('en-MY', { maximumFractionDigits: 1 })}%`;
const localTime = (value) => value ? formatMalaysiaDateTime(value) : '—';

export default function ParkingOverview() {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    const controller = new AbortController();
    fetchOverview(controller.signal).then((result) => {
      if (!controller.signal.aborted) { setData(result); setLoading(false); }
    }).catch((failure) => {
      if (!controller.signal.aborted) { setError(failure.message || 'Unable to load the parking overview.'); setLoading(false); }
    });
    return () => controller.abort();
  }, [revision]);
  function refresh() { setLoading(true); setData(null); setError(''); setRevision((value) => value + 1); }

  return <div className={styles.page}>
    <div className={styles.heading}>
      <div><h1>Today&apos;s Parking Overview</h1><p className={styles.muted}>{data ? formatMalaysiaDate(data.reporting_date) : 'Malaysia reporting day'}</p><p className={styles.muted}>Last refreshed: {data ? `${localTime(data.generated_at)} MYT` : '—'}</p></div>
      <button className={styles.refresh} onClick={refresh} disabled={loading}>{loading ? 'Refreshing…' : 'Refresh'}</button>
    </div>
    {loading ? <div className={styles.panel} role="status" aria-live="polite">Loading parking overview…</div> : error ? <div className={styles.panel}><p className={styles.error} role="alert">{error}</p><button className={styles.refresh} onClick={refresh}>Try Again</button></div> : data && <>
      <div className={styles.kpis}>
        <Kpi title="Occupancy rate" value={percent(occupancyPercentage(data.totals))} detail={`${number(data.totals.occupied)} occupied out of ${number(data.totals.usable_capacity)} spaces`} />
        <Kpi title="Available spaces" value={number(data.totals.available)} detail={`${number(data.totals.reserved)} allocated spaces`} />
        <Kpi title="Today's entries" value={number(data.today_entries)} detail="Recorded entry timestamps" />
        <Kpi title="Today's exits" value={number(data.today_exits)} detail="Recorded exit timestamps" />
      </div>
      <HourlyChart hours={data.hourly} />
      <section className={styles.panel} aria-labelledby="levels-title">
        <h2 id="levels-title">Occupancy by Level</h2>
        <ul className={styles.occupancyLegend} aria-label="Occupancy Colour Legend" role="list">
          {occupancyBands.map(band => <li className={styles.occupancyLegendCard} key={band.label} style={{ '--legend-colour': band.colour }}>
            <span className={styles.occupancyLegendIndicator} aria-hidden="true" />
            <div><strong className={styles.occupancyLegendLabel}>{band.label}</strong><span className={styles.occupancyLegendRange}>{band.threshold}</span></div>
          </li>)}
        </ul>
        {data.levels.length === 0 ? <p className={styles.empty}>No active parking levels</p> : <div className={styles.levels}>{data.levels.map((level) => {
          const percentage = occupancyPercentage(level);
          const { colour, label } = occupancyBand(percentage);
          return <div className={styles.level} key={level.id}>
            <div className={styles.sectionHeading}><h3>{level.name}</h3><strong>{percent(percentage)}</strong></div>
            <div className={styles.track} role="img" aria-label={`${level.name}: ${percent(percentage)} confirmed occupancy, ${label}`}><span style={{ width: `${Math.min(100, percentage ?? 0)}%`, backgroundColor: colour }} /></div>
            <div className={styles.levelDetails}><span>{number(level.occupied)} Occupied</span><span>{number(level.reserved)} Allocated</span><span>{number(level.available)} Available</span><span>{number(level.usable_capacity)} Usable</span></div>
            {level.usable_capacity === 0 && <p className={styles.muted}>No usable capacity</p>}
          </div>;
        })}</div>}
      </section>
      <TodaySessions />
    </>}
  </div>;
}

function Kpi({ title, value, detail }) {
  return <section className={styles.kpi}><h2>{title}</h2><strong>{value}</strong><p>{detail}</p></section>;
}
