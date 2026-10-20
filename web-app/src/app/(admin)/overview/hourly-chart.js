import styles from './overview.module.css';

export default function HourlyChart({ hours, title = 'Hourly Vehicle Movements', description = 'Recorded session entries and exits · Malaysia Time', emptyMessage = 'No Entries Or Exits Recorded Today' }) {
  const maximum = Math.max(1, ...hours.flatMap((hour) => [hour.entries, hour.exits]));
  const ceiling = Math.max(2, Math.ceil(maximum / 2) * 2);
  const empty = hours.every((hour) => hour.entries === 0 && hour.exits === 0);
  return (
    <section className={styles.panel} aria-labelledby="movements-title">
      <div className={styles.sectionHeading}><h2 id="movements-title">{title}</h2><div className={styles.legend}><span><i className={styles.entryKey} />Entries</span><span><i className={styles.exitKey} />Exits</span></div></div>
      <p className={styles.muted}>{description}</p>
      {empty && <p className={styles.empty}>{emptyMessage}</p>}
      <div className={styles.chartScroll}>
        <div className={styles.chart}>
          <p className={styles.axisTitle}>Vehicles</p>
          <div className={styles.plot}>
            <div className={styles.yAxis} aria-hidden="true"><span>{ceiling}</span><span>{ceiling / 2}</span><span>0</span></div>
            <div className={styles.bars}>
              {hours.map((hour) => {
                const label = `${String(hour.hour).padStart(2, '0')}:00`;
                return <button type="button" className={styles.hour} key={hour.hour} aria-label={`${label}: ${hour.entries} entries, ${hour.exits} exits`}>
                  <span className={styles.barPair} aria-hidden="true"><span className={styles.entryBar} style={{ height: `${hour.entries / ceiling * 100}%` }} /><span className={styles.exitBar} style={{ height: `${hour.exits / ceiling * 100}%` }} /></span>
                  <span className={styles.hourLabel}>{String(hour.hour).padStart(2, '0')}</span>
                  <span className={styles.tooltip} aria-hidden="true">{label}<br />Entries: {hour.entries}<br />Exits: {hour.exits}</span>
                </button>;
              })}
            </div>
          </div>
          <p className={styles.xTitle}>Hour Of Day (00–23)</p>
        </div>
      </div>
    </section>
  );
}
