'use client';
import { useEffect, useState } from 'react';
import { fetchVehicles, vehiclesQuery } from './vehicles-client.mjs';
import VehicleDecisionDialog from './vehicle-decision-dialog';
import styles from '../approvals/approvals.module.css';
import filtersStyle from '../analytics/analytics.module.css';

const initial = { plate: '', status: '', tenant_id: '' };
const labels = { approved: 'Approved', pending: 'Pending', rejected: 'Rejected' };
export default function RegisteredVehicles() {
  const [draft, setDraft] = useState(initial);
  const [applied, setApplied] = useState(initial);
  const [offset, setOffset] = useState(0);
  const [revision, setRevision] = useState(0);
  const [data, setData] = useState(null);
  const [companies, setCompanies] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [inputError, setInputError] = useState('');
  const [selection, setSelection] = useState(null);
  const [notice, setNotice] = useState('');
  useEffect(() => {
    const controller = new AbortController();
    fetchVehicles(vehiclesQuery(applied, offset), controller.signal).then(result => {
      if (!controller.signal.aborted) { setData(result); setCompanies(result.companies); setLoading(false); }
    }).catch(failure => {
      if (!controller.signal.aborted) { setError(failure.message); setLoading(false); }
    });
    return () => controller.abort();
  }, [applied, offset, revision]);
  function reload(nextOffset = offset, filters = applied) {
    setData(null); setError(''); setLoading(true); setApplied(filters); setOffset(nextOffset); setRevision(value => value + 1);
  }
  function apply(event) {
    event.preventDefault();
    try { vehiclesQuery(draft); setInputError(''); reload(0, { ...draft }); }
    catch (failure) { setInputError(failure.message); }
  }
  const filtered = Boolean(applied.plate.trim() || applied.status || applied.tenant_id);
  return <div className={styles.page}>
    <div className={styles.heading}><div><h1>Registered Vehicles</h1><p>View vehicle registrations, registered owners and their current company associations.</p></div>
      <button className={styles.secondary} disabled={loading || Boolean(selection)} onClick={() => { setNotice(''); reload(); }}>{loading && revision > 0 ? 'Refreshing…' : 'Refresh'}</button></div>
    <form className={filtersStyle.filters} onSubmit={apply}>
      <label>Search By Number Plate<input type="search" maxLength={32} value={draft.plate} onChange={event => setDraft({ ...draft, plate: event.target.value })} placeholder="Enter Full Or Partial Plate" /></label>
      <label>Vehicle Status<select value={draft.status} onChange={event => setDraft({ ...draft, status: event.target.value })}><option value="">All Statuses</option>{Object.entries(labels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></label>
      <label>Company<select value={draft.tenant_id} onChange={event => setDraft({ ...draft, tenant_id: event.target.value })}><option value="">All Companies</option>{companies.map(company => <option key={company.id} value={company.id}>{company.name}</option>)}</select></label>
      <button className={styles.primary} disabled={loading || Boolean(selection)}>Apply Filters</button>
    </form>
    {inputError && <p className={styles.error} role="alert">{inputError}</p>}
    {notice && <p className={styles.success} role="status">{notice}</p>}
    <section className={styles.card} aria-label="Vehicle Records" aria-busy={loading}>
      {loading ? <div className={styles.state} role="status">{revision ? 'Refreshing Vehicle Records…' : 'Loading Vehicle Records…'}</div> : error ?
        <div className={styles.state}><p className={styles.error} role="alert">{error}</p><button className={styles.secondary} onClick={() => reload()}>Try Again</button></div> : data?.vehicles.length === 0 ?
          <div className={styles.state}><h2>{offset > 0 ? 'No Vehicles On This Page' : filtered ? 'No Matching Vehicles' : 'No Registered Vehicles'}</h2><p>{offset > 0 ? 'The list may have changed. Return to the first page.' : filtered ? 'Adjust the filters to find vehicle records.' : 'Vehicle registrations will appear here when available.'}</p>{offset > 0 && <button className={styles.secondary} onClick={() => reload(0)}>First Page</button>}</div> :
          <div className={styles.tableScroll} tabIndex={0} aria-label="Scrollable Vehicle Records Table"><table className={styles.table}><caption className={styles.srOnly}>Registered Vehicles</caption>
            <thead><tr><th scope="col">Number Plate</th><th scope="col">Registered Owner</th><th scope="col">Company</th><th scope="col">Vehicle Status</th><th scope="col">Actions</th></tr></thead>
            <tbody>{data?.vehicles.map(vehicle => <tr key={vehicle.id}><td><strong>{vehicle.plate_number}</strong></td><td>{vehicle.owner_name || 'Not Available'}</td><td>{vehicle.tenant_name || 'Not Available'}</td><td><span className={styles.badge}>{labels[vehicle.registration_status]}</span></td><td>{vehicle.registration_status === 'pending' ? <div className={styles.actions}>
              <button className={styles.primary} disabled={Boolean(selection)} onClick={() => { setNotice(''); setSelection({ vehicle, action: 'approve' }); }} aria-label={`Approve ${vehicle.plate_number}`}>Approve</button>
              <button className={styles.secondary} disabled={Boolean(selection)} onClick={() => { setNotice(''); setSelection({ vehicle, action: 'reject' }); }} aria-label={`Reject ${vehicle.plate_number}`}>Reject</button>
            </div> : '—'}</td></tr>)}</tbody>
          </table></div>}
      <nav className={styles.pagination} aria-label="Vehicles Pagination"><span>Page {Math.floor(offset / 25) + 1}{data ? ` · ${data.total} Matching Records${data.vehicles.length ? ` · Showing ${offset + 1}–${offset + data.vehicles.length}` : ''}` : ''}</span>
        <div className={styles.actions}><button className={styles.secondary} disabled={loading || offset === 0 || Boolean(selection)} onClick={() => reload(Math.max(0, offset - 25))}>Previous</button><button className={styles.secondary} disabled={loading || !data || offset + 25 >= data.total || Boolean(selection)} onClick={() => reload(offset + 25)}>Next</button></div></nav>
    </section>
    {selection && <VehicleDecisionDialog {...selection} onDismiss={(refresh = false) => { setSelection(null); if (refresh) reload(); }} onSuccess={result => {
      setNotice(`${result.plate_number}: ${labels[result.registration_status]}.`);
      setSelection(null);
      reload();
    }} />}
  </div>;
}
