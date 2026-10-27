'use client';
import { useEffect, useRef, useState } from 'react';
import styles from '../overview/overview.module.css';
import shared from '../approvals/approvals.module.css';
import local from './analytics.module.css';
import { formatMalaysiaDate, formatMalaysiaDateTime } from '../../../lib/date-format.mjs';

const hourFormat = new Intl.DateTimeFormat('en-GB', { timeZone: 'Asia/Kuala_Lumpur', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });

function OccupancyChart({ history }) {
  const points = history.points;
  const maximum = Math.max(2, Math.ceil(Math.max(0, ...points.map((point) => point.occupied)) / 2) * 2);
  const width = 760, left = 48, right = 730, bottom = 220, top = 40;
  const x = (index) => left + index / Math.max(1, points.length - 1) * (right - left);
  const y = (value) => bottom - value / maximum * (bottom - top);
  const label = (value) => history.checkpoint === 'hour_start' ? hourFormat.format(new Date(value)) : formatMalaysiaDate(value);
  const stride = Math.max(1, Math.ceil(points.length / 6));
  return <section className={styles.panel} aria-labelledby="historical-occupancy-title">
    <h2 id="historical-occupancy-title">Historical Parking Occupancy</h2>
    <p className={styles.muted}>Session-derived confirmed occupancy, not sensor-verified physical occupancy. {history.checkpoint === 'hour_start' ? 'Hourly checkpoints at the start of each elapsed hour.' : 'End-of-day checkpoints. Today uses the latest refresh.'}</p>
    {points.length === 0 ? <p className={styles.empty}>No reporting checkpoints available</p> : <>
      {points.every((point) => point.occupied === 0) && <p className={styles.empty}>No eligible confirmed sessions at these checkpoints</p>}
      <div className={styles.chartScroll}><svg className={local.lineChart} viewBox={`0 0 ${width} 290`} aria-label="Historical Confirmed Occupancy Line Chart">
        <text x={left} y={18} className={local.axisText}>Confirmed occupied sessions</text>
        {[0, maximum / 2, maximum].map((value) => <g key={value}><line x1={left} x2={right} y1={y(value)} y2={y(value)} className={local.gridLine} /><text x={left - 10} y={y(value) + 4} textAnchor="end" className={local.axisText}>{value}</text></g>)}
        <polyline points={points.map((point, index) => `${x(index)},${y(point.occupied)}`).join(' ')} className={local.occupancyLine} />
        {points.map((point, index) => <g key={point.timestamp} tabIndex={0} className={local.point} role="img" aria-label={`${formatMalaysiaDateTime(point.timestamp, { seconds: true })} MYT: ${point.occupied} confirmed occupied sessions`}>
          <title>{formatMalaysiaDateTime(point.timestamp, { seconds: true })} MYT · {point.occupied} confirmed occupied sessions</title>
          <circle cx={x(index)} cy={y(point.occupied)} r={6} />
          {(index % stride === 0 || index === points.length - 1) && <text x={x(index)} y={244} textAnchor={index === 0 ? 'start' : index === points.length - 1 ? 'end' : 'middle'} className={local.axisText}>{label(point.timestamp)}</text>}
          <g className={local.lineTooltip} transform={`translate(${Math.min(right - 280, Math.max(left, x(index) - 140))},55)`}>
            <rect width={280} height={56} rx={6} /><text x={12} y={22}>{formatMalaysiaDateTime(point.timestamp, { seconds: true })} MYT</text><text x={12} y={42}>{point.occupied} confirmed occupied sessions</text>
          </g>
        </g>)}
        <text x={width / 2} y={278} textAnchor="middle" className={local.axisText}>{history.checkpoint === 'hour_start' ? 'Reporting time (MYT)' : 'Reporting date (Malaysia)'}</text>
      </svg></div>
    </>}
  </section>;
}

function ComparisonChart({ rows, unit, empty, colour = 'var(--chart-comparative)' }) {
  const maximum = Math.max(1, ...rows.map((row) => row.count));
  return rows.length === 0 ? <p className={styles.empty}>{empty}</p> : <>
    {rows.every((row) => row.count === 0) && <p className={styles.empty}>No activity in this selection</p>}
    <p className={local.comparisonUnit}>{unit}</p>
    <ul className={local.comparisons} style={{ '--series-colour': colour }}>{rows.map((row) => <li key={row.id}>
      <div className={local.comparisonLabel}><span>{row.name}</span><strong>{row.count.toLocaleString('en-MY')}</strong></div>
      <div className={local.comparisonTrack} role="img" aria-label={`${row.name}: ${row.count} ${unit}`} title={`${row.name}: ${row.count} ${unit}`}><span style={{ width: `${row.count / maximum * 100}%` }} /></div>
    </li>)}</ul>
  </>;
}

function ZoneBreakdown({ data, onClose }) {
  const dialog = useRef(null);
  useEffect(() => {
    const element = dialog.current;
    element.showModal();
    return () => element.close();
  }, []);
  return <dialog ref={dialog} className={`${shared.dialog} ${local.zoneDialog}`} aria-labelledby="zone-breakdown-title" aria-describedby="zone-breakdown-description"
    onCancel={event => { event.preventDefault(); onClose(); }}>
    <div className={local.zoneDialogContent}>
      <header>
        <h2 id="zone-breakdown-title">Zone Breakdown</h2>
        <p className={styles.muted}>{formatMalaysiaDate(data.start_date)} to {formatMalaysiaDate(data.end_date)} · Malaysia time</p>
        <p id="zone-breakdown-description" className={styles.muted}>Parking assignments by zone within each level. Counts represent demand, not occupancy or capacity utilisation.</p>
      </header>
      <div className={local.zoneCards}>
        {data.parking_demand.levels.map(level => <section key={level.id} className={local.zoneCard} aria-label={`${level.name} zone breakdown`}>
          <div className={local.zoneCardHeading}><h3>{level.name}</h3><span>{level.assignments.toLocaleString('en-MY')} Assignments</span></div>
          <ComparisonChart rows={level.zones.map(zone => ({ ...zone, count: zone.assignments }))} unit="Parking Assignments" empty="No zones available" colour="var(--chart-supporting)" />
        </section>)}
      </div>
      {data.parking_demand.unmapped_assignments > 0 && <p className={styles.muted}>{data.parking_demand.unmapped_assignments.toLocaleString('en-MY')} assignments could not be mapped to an existing level/zone and are omitted.</p>}
      <div className={shared.dialogActions}><button type="button" className={shared.secondary} onClick={onClose}>Close</button></div>
    </div>
  </dialog>;
}

export default function UtilisationCharts({ data }) {
  const [showZones, setShowZones] = useState(false);
  if (!data.historical_occupancy || !data.parking_demand || !data.tenant_activity) return <p className={styles.muted}>Historical occupancy and demand analytics are unavailable from this backend version.</p>;
  const demand = data.parking_demand;
  const selected = data.level_id !== null;
  const rows = selected ? (demand.levels[0]?.zones ?? []).map((zone) => ({ ...zone, count: zone.assignments })) : demand.levels.map((level) => ({ ...level, count: level.assignments }));
  return <>
    <h2 className={local.sectionTitle}>Historical Occupancy and Parking Demand</h2>
    <OccupancyChart history={data.historical_occupancy} />
    <div className={local.comparisonGrid}>
      <section className={styles.panel} aria-labelledby="parking-demand-title">
        <h2 id="parking-demand-title">Parking Demand by Level and Zone</h2>
        <p className={styles.muted}>{selected ? `Zones in ${demand.levels[0]?.name ?? 'Selected level'}` : 'Assignments by parking level'}.</p>
        <ComparisonChart rows={rows} unit="Parking Assignments" empty="No parking areas available" colour={selected ? 'var(--chart-supporting)' : 'var(--chart-comparative)'} />
        {!selected && demand.levels.length > 0 && <div className={local.zoneDetails}><button type="button" className={shared.secondary} aria-haspopup="dialog" onClick={() => setShowZones(true)}>View Zone Breakdown</button></div>}
        {demand.unmapped_assignments > 0 && <p className={styles.footnote}>{demand.unmapped_assignments} assignments could not be mapped to an existing level/zone and are omitted from these comparisons.</p>}
      </section>
      <section className={styles.panel} aria-labelledby="tenant-activity-title">
        <h2 id="tenant-activity-title">Parking Activity by Tenant</h2>
        <p className={styles.muted}>Companies are ordered by session count.</p>
        <ComparisonChart rows={data.tenant_activity.tenants.map((tenant) => ({ ...tenant, count: tenant.sessions }))} unit="Parking Sessions" empty="No tenant records available" colour="var(--chart-additional)" />
      </section>
    </div>
    {showZones && <ZoneBreakdown data={data} onClose={() => setShowZones(false)} />}
  </>;
}
