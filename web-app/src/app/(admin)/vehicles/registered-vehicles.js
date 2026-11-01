'use client';
import RefreshButton from '../../../components/refresh-button';
import { useCallback, useState } from 'react';
import { driversQuery, vehiclesQuery, fetchDrivers, fetchVehicles, fetchVehicleSummary } from './vehicles-client.mjs';
import useVehicleResource from './use-vehicle-resource';
import VehicleDecisionDialog from './vehicle-decision-dialog';
import DriverDetailsDrawer from './driver-details-drawer';
import BulkVehicleApprovalDialog from './bulk-vehicle-approval-dialog';
import VehicleRecordsTable from './vehicle-records-table';
import { DriverIdentity, RegistrationUsage, VehicleSummaryCards, VehiclePagination, RecordsState, statusLabels } from './vehicles-ui';
import styles from './vehicles.module.css';
import shared from '../approvals/approvals.module.css';

const initial = { search: '', plate: '', status: '', tenant_id: '' };
const loadCompanies = signal => fetchVehicles('limit=1&offset=0', signal);

export default function RegisteredVehicles() {
  const [view, setView] = useState('drivers');
  const [draft, setDraft] = useState(initial), [applied, setApplied] = useState(initial);
  const [offsets, setOffsets] = useState({ drivers: 0, vehicles: 0 });
  const [revision, setRevision] = useState(0), [companyRevision, setCompanyRevision] = useState(0);
  const [selection, setSelection] = useState(null), [drawer, setDrawer] = useState(null);
  const [notice, setNotice] = useState(''), [inputError, setInputError] = useState('');
  const [checked, setChecked] = useState({ scope: null, ids: [] }), [bulkSelection, setBulkSelection] = useState(null);
  const [bulkResults, setBulkResults] = useState(null);
  const offset = offsets[view];
  const query = view === 'drivers' ? driversQuery(applied, offset) : vehiclesQuery(applied, offset);
  const load = useCallback(signal => view === 'drivers' ? fetchDrivers(query, signal) : fetchVehicles(query, signal), [view, query]);
  const scope = `${view}|${query}|${revision}`;
  const records = useVehicleResource(scope, load);
  const loadSummary = useCallback(signal => fetchVehicleSummary(applied.tenant_id, signal), [applied.tenant_id]);
  const summary = useVehicleResource(`summary|${applied.tenant_id}|${revision}`, loadSummary);
  const pendingCount = summary.data?.pending_approval;
  const showPendingCount = Number.isSafeInteger(pendingCount) && pendingCount > 0;
  const pendingDescription = `${pendingCount} vehicle registration${pendingCount === 1 ? '' : 's'} awaiting approval or rejection`;
  const companyResource = useVehicleResource(`companies|${companyRevision}`, loadCompanies);
  const companies = (companyResource.data ?? companyResource.previous)?.companies ?? [];
  const data = records.data, locked = Boolean(selection || bulkSelection);
  const eligible = view === 'vehicles' ? (data?.vehicles ?? []).filter(vehicle => vehicle.registration_status === 'pending') : [];
  const selectedVehicles = eligible.filter(vehicle => checked.scope === scope && checked.ids.includes(vehicle.id));
  const rows = view === 'drivers' ? data?.drivers : data?.vehicles;
  const filtered = Boolean(applied.tenant_id || applied.status || (view === 'drivers' ? applied.search : applied.plate).trim());
  function resetChecked() { setChecked({ scope: null, ids: [] }); }
  function changePage(next) { resetChecked(); setOffsets(old => ({ ...old, [view]: next })); }
  function reload() { resetChecked(); setRevision(value => value + 1); }
  function selectVehicle(id, selected) {
    if (locked || records.loading || !eligible.some(vehicle => vehicle.id === id)) return;
    setChecked(previous => {
      const ids = previous.scope === scope ? previous.ids : [];
      return { scope, ids: selected ? [...new Set([...ids, id])] : ids.filter(value => value !== id) };
    });
  }
  function selectAll(selected) {
    if (!locked && !records.loading) setChecked({ scope, ids: selected ? eligible.map(vehicle => vehicle.id) : [] });
  }
  function apply(event) {
    event.preventDefault();
    try {
      driversQuery({ ...draft, search: view === 'drivers' ? draft.search : '' });
      if (view === 'vehicles') vehiclesQuery(draft);
      const searchKey = view === 'drivers' ? 'search' : 'plate';
      setInputError(''); setNotice(''); resetChecked(); setBulkResults(null);
      setApplied({ ...applied, tenant_id: draft.tenant_id, status: draft.status, [searchKey]: draft[searchKey] });
      setOffsets({ drivers: 0, vehicles: 0 });
    } catch (error) { setInputError(error.message); }
  }
  function clear() { resetChecked(); setBulkResults(null); setDraft(initial); setApplied(initial); setOffsets({ drivers: 0, vehicles: 0 }); setInputError(''); setNotice(''); }
  function chooseView(next) { resetChecked(); setView(next); setInputError(''); setOffsets(old => ({ ...old, [next]: 0 })); }
  function decide(vehicle, action) { setNotice(''); setBulkResults(null); setSelection({ vehicle, action }); }
  return <div className={styles.page}>
    <header className={styles.heading}><div><h1>Registered Vehicles</h1><p>Review driver registration usage and manage individual vehicles.</p></div>
      <RefreshButton loading={records.loading} disabled={locked} onClick={() => { setNotice(''); reload(); setCompanyRevision(value => value + 1); }} /></header>
    <VehicleSummaryCards resource={summary} tenantName={applied.tenant_id ? companies.find(company => company.id === applied.tenant_id)?.name || 'Selected Company' : null} onRetry={reload} />
    {notice && <p className={shared.success} role="status">{notice}</p>}
    {bulkResults && <div className={styles.bulkFeedback} data-partial={bulkResults.some(result => result.outcome !== 'approved')}
      role={bulkResults.some(result => result.outcome !== 'approved') ? 'alert' : 'status'}>
      <p><strong>{bulkResults.filter(result => result.outcome === 'approved').length} of {bulkResults.length} selected vehicles approved.</strong></p>
      {bulkResults.some(result => result.outcome !== 'approved') && <ul aria-label="Vehicles Requiring Review">
        {bulkResults.filter(result => result.outcome !== 'approved').map(result => <li key={result.id}><strong>{result.plate_number}</strong>: {result.message}</li>)}
      </ul>}
    </div>}
    <section className={styles.workspace} aria-label="Registration Management">
      <div className={styles.toolbar}>
        <div className={styles.viewControl} role="group" aria-label="Registration View">
          <button aria-pressed={view === 'drivers'} disabled={locked} onClick={() => chooseView('drivers')}>By Drivers</button>
          <button aria-label="All Vehicles" aria-describedby={showPendingCount ? 'pending-vehicle-registrations' : undefined}
            aria-pressed={view === 'vehicles'} disabled={locked} onClick={() => chooseView('vehicles')}>
            All Vehicles
            {showPendingCount && <span id="pending-vehicle-registrations" className={styles.viewBadge} aria-label={pendingDescription} title={pendingDescription}>
              {pendingCount > 99 ? '99+' : pendingCount}
            </span>}
          </button>
        </div>
        <form className={styles.filters} onSubmit={apply}>
          <label>{view === 'drivers' ? 'Search by Driver Name' : 'Search by Number Plate'}<input type="search"
            maxLength={view === 'drivers' ? 150 : 32} placeholder={view === 'drivers' ? 'Enter Driver Name' : 'Enter Number Plate'}
            value={view === 'drivers' ? draft.search : draft.plate} disabled={locked}
            onChange={event => setDraft(old => ({ ...old, [view === 'drivers' ? 'search' : 'plate']: event.target.value }))} /></label>
          <label>Company<select value={draft.tenant_id} disabled={locked || (companyResource.loading && !companies.length)}
            onChange={event => setDraft(old => ({ ...old, tenant_id: event.target.value }))}>
            <option value="">All Companies</option>{companies.map(company => <option key={company.id} value={company.id}>{company.name}</option>)}
          </select></label>
          <label>Registration Status<select value={draft.status} disabled={locked} onChange={event => setDraft(old => ({ ...old, status: event.target.value }))}>
            <option value="">All Statuses</option>{Object.entries(statusLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select></label>
          <div className={styles.filterActions}><button className={shared.primary} disabled={locked}>Apply Filters</button>
            <button type="button" className={shared.secondary} disabled={locked} onClick={clear}>Clear Filters</button></div>
        </form>
        {inputError && <p className={shared.error} role="alert">{inputError}</p>}
        {companyResource.error && <div className={styles.metadataError}><p role="alert">Company choices are unavailable.</p><button className={shared.secondary} onClick={() => setCompanyRevision(value => value + 1)}>Retry Companies</button></div>}
        <p className={styles.filterNote}>{view === 'drivers' ? 'Usage includes approved and pending registrations. Rejected records do not take up a slot.' : 'Only pending registrations can be approved or rejected.'}</p>
      </div>
      <div aria-busy={records.loading} aria-label={view === 'drivers' ? 'Driver Records' : 'Vehicle Records'}>
        {records.loading || records.error ? <RecordsState loading={records.loading} error={records.error} onRetry={reload} message={view === 'drivers' ? 'Loading driver registrations…' : 'Loading vehicle registrations…'} />
          : !rows?.length ? <RecordsState title={offset > 0 ? 'No Records on This Page' : filtered ? 'No Matching Registrations' : view === 'drivers' ? 'No Driver Accounts' : 'No Registered Vehicles'}
            message={offset > 0 ? 'The records may have changed. Return to the first page.' : filtered ? 'Adjust or clear the filters to find registrations.' : 'Registration records will appear here when available.'}
            onFirstPage={offset > 0 ? () => changePage(0) : null} />
            : view === 'drivers' ? <div className={shared.tableScroll} tabIndex={0} aria-label="Scrollable Driver Records Table">
              <table className={`${shared.table} ${styles.driverTable}`}>
                <caption className={shared.srOnly}>Driver Vehicle Registrations</caption>
                <thead><tr><th scope="col">Driver</th><th scope="col">Registration Usage</th><th scope="col">Details</th></tr></thead>
                <tbody>{data.drivers.map(driver => <tr key={driver.id}>
                  <td><DriverIdentity driver={driver} /></td>
                  <td><RegistrationUsage counts={driver.vehicle_counts} /></td>
                  <td><button className={`${shared.secondary} ${styles.detailsButton}`} disabled={locked} onClick={event => setDrawer({ id: driver.id, trigger: event.currentTarget })} aria-label={`View Driver Details for ${driver.full_name || 'unnamed driver'}`}>View Details</button></td>
                </tr>)}</tbody>
              </table>
            </div> : <VehicleRecordsTable vehicles={data.vehicles} selectedIds={selectedVehicles.map(vehicle => vehicle.id)} locked={locked}
              onSelect={selectVehicle} onSelectAll={selectAll} onDecision={decide}
              onApproveSelected={() => { if (!locked && selectedVehicles.length) { setNotice(''); setBulkResults(null); setBulkSelection(selectedVehicles); } }} />}
      </div>
      <VehiclePagination data={data} offset={offset} loading={records.loading} disabled={locked} onPage={changePage} noun={view === 'drivers' ? 'Drivers' : 'Vehicles'} />
    </section>
    {drawer && <DriverDetailsDrawer key={drawer.id} driverId={drawer.id} trigger={drawer.trigger} revision={revision} locked={locked} onClose={() => { if (!locked) setDrawer(null); }} onDecision={decide} />}
    {selection && <VehicleDecisionDialog {...selection} onDismiss={(refresh = false) => { setSelection(null); if (refresh) reload(); }}
      onSuccess={result => { setNotice(`${result.plate_number}: ${statusLabels[result.registration_status]}.`); setSelection(null); reload(); }} />}
    {bulkSelection && <BulkVehicleApprovalDialog vehicles={bulkSelection}
      onDismiss={(refresh = false) => { setBulkSelection(null); if (refresh) reload(); }}
      onComplete={results => { setBulkResults(results); setBulkSelection(null); reload(); }} />}
  </div>;
}
