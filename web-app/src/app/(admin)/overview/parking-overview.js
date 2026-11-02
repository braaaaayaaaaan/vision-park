"use client";
import RefreshButton from '../../../components/refresh-button';
import { useCallback, useState } from 'react';
import useResource from '../vehicles/use-vehicle-resource';
import HourlyChart from './hourly-chart';
import TodaySessions from './today-sessions';
import { occupancyBand, occupancyBands, occupancyPercentage } from './overview-utils.mjs';
import { fetchOverview } from './overview-client';
import { formatMalaysiaDate, formatMalaysiaDateTime } from '../../../lib/date-format.mjs';
import styles from './overview.module.css';
import FinancialSummary from '../payments/financial-summary';
import { todayPaymentQuery } from '../../../lib/payment-contracts.mjs';
import MetricIcon from '../../../components/metric-icon';
import OvernightAlerts from '../sessions/overnight-alerts';
import OverviewNotice from './overview-notice';

const number = (value) => value.toLocaleString('en-MY');
const percent = (value) => value === null ? 'N/A' : `${value.toLocaleString('en-MY', { maximumFractionDigits: 1 })}%`;
const localTime = (value) => value ? formatMalaysiaDateTime(value) : '—';

export default function ParkingOverview() {
  const [revision, setRevision] = useState(0);
  const load = useCallback(signal => fetchOverview(signal), []);
  const { data, loading, error } = useResource(`overview:${revision}`, load, 15000);
  function refresh() { setRevision(value => value + 1); }
  const occupancy = data ? occupancyPercentage(data.totals) : null;
  const occupancyStatus = occupancyBand(occupancy).label;

  return <div className={styles.page}>
    <div className={styles.heading}>
      <div><h1>Today&apos;s Parking Overview</h1><p className={styles.muted}>{data ? formatMalaysiaDate(data.reporting_date) : 'Malaysia reporting day'}</p><p className={styles.muted}>Last Refreshed: {data ? `${localTime(data.generated_at)} MYT` : '—'}</p></div>
      <RefreshButton onClick={refresh} loading={loading} />
    </div>
    {loading ? <div className={styles.panel} role="status" aria-live="polite">Loading parking overview…</div> : error ? <div className={styles.panel}><p className={styles.error} role="alert">{error}</p><button className={styles.refresh} onClick={refresh}>Try Again</button></div> : data &&
      <div className={styles.kpis}>
        <Kpi icon="occupancy" accent={occupancyStatus === 'Full' ? 'red' : occupancyStatus === 'Nearly Full' ? 'amber' : 'blue'} title="Occupancy Rate" value={percent(occupancy)} detail={`${number(data.totals.occupied)} occupied out of ${number(data.totals.usable_capacity)} spaces`} />
        <Kpi icon="parking" accent="green" title="Available Spaces" value={number(data.totals.available)} detail={`${number(data.totals.reserved)} allocated spaces`} />
        <Kpi icon="entry" title="Today's Entries" value={number(data.today_entries)} detail="Recorded entry timestamps" />
        <Kpi icon="exit" accent="green" title="Today's Exits" value={number(data.today_exits)} detail="Recorded exit timestamps" />
      </div>
    }
    <OvernightAlerts compact revision={revision} />
    {!loading && !error && data && <>
      <HourlyChart hours={data.hourly} />
      <section className={styles.panel} aria-labelledby="levels-title">
        <h2 id="levels-title">Occupancy by Level</h2>
        <ul className={styles.occupancyLegend} aria-label="Occupancy Colour Legend" role="list">
          {occupancyBands.map(band => <li className={styles.occupancyLegendCard} key={band.label} style={{ '--legend-colour': band.colour }}>
            <span className={styles.occupancyLegendIndicator} aria-hidden="true" />
            <div><strong className={styles.occupancyLegendLabel}>{band.label}</strong><span className={styles.occupancyLegendRange}>{band.threshold}</span></div>
          </li>)}
        </ul>
        {data.levels.length === 0 ? <OverviewNotice><p>No active parking levels</p></OverviewNotice> : <div className={styles.levels}>{data.levels.map((level) => {
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
    <FinancialSummary query={data ? `start_date=${data.reporting_date}&end_date=${data.reporting_date}` : todayPaymentQuery()} revision={revision} live />
  </div>;
}

function Kpi({ icon, accent = 'blue', title, value, detail }) {
  return <section className={`${styles.kpi} ${styles.overviewStat}`} data-metric={icon} data-accent={accent}>
    <div className={styles.statHeader}><MetricIcon name={icon} large solid /><h2>{title}</h2></div>
    <strong>{value}</strong>
    <p>{detail}</p>
  </section>;
}
