import styles from '../overview/overview.module.css';
import local from './analytics.module.css';

const timeFormat = new Intl.DateTimeFormat('en-MY', { timeZone: 'Asia/Kuala_Lumpur', dateStyle: 'medium', timeStyle: 'medium' });
const dateFormat = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kuala_Lumpur', year: 'numeric', month: '2-digit', day: '2-digit' });
const hourFormat = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kuala_Lumpur', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });

function OccupancyChart({ history }) {
  const points = history.points;
  const maximum = Math.max(2, Math.ceil(Math.max(0, ...points.map((point) => point.occupied)) / 2) * 2);
  const width = 760, left = 48, right = 730, bottom = 220, top = 40;
  const x = (index) => left + index / Math.max(1, points.length - 1) * (right - left);
  const y = (value) => bottom - value / maximum * (bottom - top);
  const label = (value) => (history.checkpoint === 'hour_start' ? hourFormat : dateFormat).format(new Date(value));
  const stride = Math.max(1, Math.ceil(points.length / 6));
  return <section className={styles.panel} aria-labelledby="historical-occupancy-title">
    <h2 id="historical-occupancy-title">Historical Parking Occupancy</h2>
    <p className={styles.muted}>Session-derived confirmed occupancy, not sensor-verified physical occupancy. {history.checkpoint === 'hour_start' ? 'Hourly checkpoints at the start of each elapsed hour.' : 'End-of-day checkpoints; today uses the refresh time.'} Malaysia Time.</p>
    {points.length === 0 ? <p className={styles.empty}>No Reporting Checkpoints Available</p> : <>
      {points.every((point) => point.occupied === 0) && <p className={styles.empty}>No Eligible Confirmed Sessions At These Checkpoints</p>}
      <div className={styles.chartScroll}><svg className={local.lineChart} viewBox={`0 0 ${width} 290`} aria-label="Historical Confirmed Occupancy Line Chart">
        <text x={left} y={18} className={local.axisText}>Confirmed Occupied Sessions</text>
        {[0, maximum / 2, maximum].map((value) => <g key={value}><line x1={left} x2={right} y1={y(value)} y2={y(value)} className={local.gridLine} /><text x={left - 10} y={y(value) + 4} textAnchor="end" className={local.axisText}>{value}</text></g>)}
        <polyline points={points.map((point, index) => `${x(index)},${y(point.occupied)}`).join(' ')} className={local.occupancyLine} />
        {points.map((point, index) => <g key={point.timestamp} tabIndex={0} className={local.point} role="img" aria-label={`${timeFormat.format(new Date(point.timestamp))} MYT: ${point.occupied} Confirmed Occupied Sessions`}>
          <title>{timeFormat.format(new Date(point.timestamp))} MYT · {point.occupied} Confirmed Occupied Sessions · {point.timestamp}</title>
          <circle cx={x(index)} cy={y(point.occupied)} r={6} />
          {(index % stride === 0 || index === points.length - 1) && <text x={x(index)} y={244} textAnchor={index === 0 ? 'start' : index === points.length - 1 ? 'end' : 'middle'} className={local.axisText}>{label(point.timestamp)}</text>}
          <g className={local.lineTooltip} transform={`translate(${Math.min(right - 280, Math.max(left, x(index) - 140))},55)`}>
            <rect width={280} height={56} rx={6} /><text x={12} y={22}>{timeFormat.format(new Date(point.timestamp))} MYT</text><text x={12} y={42}>{point.occupied} Confirmed Occupied Sessions</text>
          </g>
        </g>)}
        <text x={width / 2} y={278} textAnchor="middle" className={local.axisText}>{history.checkpoint === 'hour_start' ? 'Reporting Time (MYT)' : 'Reporting Date (Malaysia)'}</text>
      </svg></div>
    </>}
  </section>;
}

function ComparisonChart({ rows, unit, empty }) {
  const maximum = Math.max(1, ...rows.map((row) => row.count));
  return rows.length === 0 ? <p className={styles.empty}>{empty}</p> : <>
    {rows.every((row) => row.count === 0) && <p className={styles.empty}>No Activity In This Selection</p>}
    <p className={local.comparisonUnit}>{unit}</p>
    <ul className={local.comparisons}>{rows.map((row) => <li key={row.id}>
      <div className={local.comparisonLabel}><span>{row.name}</span><strong>{row.count.toLocaleString('en-MY')}</strong></div>
      <div className={local.comparisonTrack} role="img" aria-label={`${row.name}: ${row.count} ${unit}`} title={`${row.name}: ${row.count} ${unit}`}><span style={{ width: `${row.count / maximum * 100}%` }} /></div>
    </li>)}</ul>
  </>;
}

export default function UtilisationCharts({ data }) {
  if (!data.historical_occupancy || !data.parking_demand || !data.tenant_activity) return <p className={styles.muted}>Historical occupancy and demand analytics are unavailable from this backend version.</p>;
  const demand = data.parking_demand;
  const selected = data.level_id !== null;
  const rows = selected ? (demand.levels[0]?.zones ?? []).map((zone) => ({ ...zone, count: zone.assignments })) : demand.levels.map((level) => ({ ...level, count: level.assignments }));
  return <>
    <h2 className={local.sectionTitle}>Historical Occupancy and Parking Demand</h2>
    <OccupancyChart history={data.historical_occupancy} />
    <section className={styles.panel} aria-labelledby="parking-demand-title">
      <h2 id="parking-demand-title">Parking Demand By Level & Zone</h2>
      <p className={styles.muted}>{selected ? `Zones In ${demand.levels[0]?.name ?? 'Selected Level'}` : 'Assignments By Parking Level'}. Non-cancelled sessions entering within the selected dates; counts are not occupancy or capacity utilisation.</p>
      <ComparisonChart rows={rows} unit="Parking Assignments" empty="No Parking Areas Available" />
      {!selected && demand.levels.length > 0 && <details className={local.zoneDetails}><summary>View Zone Breakdown</summary>{demand.levels.map((level) => <div key={level.id} className={local.zoneGroup}><h3>{level.name}</h3><ComparisonChart rows={level.zones.map((zone) => ({ ...zone, count: zone.assignments }))} unit="Parking Assignments" empty="No Zones Available" /></div>)}</details>}
      {demand.unmapped_assignments > 0 && <p className={styles.footnote}>{demand.unmapped_assignments} assignments could not be mapped to an existing level/zone and are omitted from these comparisons.</p>}
    </section>
    <section className={styles.panel} aria-labelledby="tenant-activity-title">
      <h2 id="tenant-activity-title">Parking Activity By Tenant</h2>
      <p className={styles.muted}>Non-cancelled sessions entering within the selected dates and level. Companies are ordered by session count.</p>
      <ComparisonChart rows={data.tenant_activity.tenants.map((tenant) => ({ ...tenant, count: tenant.sessions }))} unit="Parking Sessions" empty="No Tenant Records Available" />
    </section>
  </>;
}
