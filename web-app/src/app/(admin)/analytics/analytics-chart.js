import styles from '../overview/overview.module.css';
import OverviewNotice from '../overview/overview-notice';

// Same native grouped-bar approach as Overview, for dates and duration categories.
export default function AnalyticsChart({ id, title, description, rows, series, unit, axis }) {
  const maximum = Math.max(1, ...rows.flatMap((row) => series.map(({ key }) => row[key])));
  const ceiling = Math.max(2, Math.ceil(maximum / 2) * 2);
  return <section className={styles.panel} aria-labelledby={id}>
    <div className={styles.sectionHeading}><h2 id={id}>{title}</h2><div className={styles.legend}>{series.map((item) => <span key={item.key}><i className={styles.entryKey} style={{ background: item.colour }} />{item.label}</span>)}</div></div>
    <p className={styles.muted}>{description}</p>
    {rows.every((row) => series.every((item) => row[item.key] === 0)) && <OverviewNotice><p>No records in this selection</p></OverviewNotice>}
    <div className={styles.chartScroll}><div className={styles.chart} style={{ minWidth: Math.max(650, rows.length * (rows[0]?.period.includes(':') ? 44 : 100)) }}>
      <p className={styles.axisTitle}>{unit}</p>
      <div className={styles.plot}><div className={styles.yAxis} aria-hidden="true"><span>{ceiling}</span><span>{ceiling / 2}</span><span>0</span></div>
        <div className={styles.bars} style={{ gridTemplateColumns: `repeat(${rows.length}, minmax(0, 1fr))` }}>
          {rows.map((row) => <button type="button" className={styles.hour} key={row.period} aria-label={`${row.period}: ${series.map((item) => `${row[item.key]} ${item.label}`).join(', ')}`}>
            <span className={styles.barPair} aria-hidden="true">{series.map((item) => <span key={item.key} className={styles.entryBar} style={{ height: `${row[item.key] / ceiling * 100}%`, background: item.colour }} />)}</span>
            <span className={styles.hourLabel}>{row.period}</span><span className={styles.tooltip} aria-hidden="true">{row.period}{series.map((item) => <span key={item.key}><br />{item.label}: {row[item.key]}</span>)}</span>
          </button>)}
        </div>
      </div><p className={styles.xTitle}>{axis}</p>
    </div></div>
  </section>;
}
