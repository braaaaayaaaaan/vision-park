'use client';
import { useCallback, useState } from 'react';
import useResource from '../vehicles/use-vehicle-resource';
import { RecordsState } from '../vehicles/vehicles-ui';
import { fetchTenants, listingQuery } from './tenants-client.mjs';
import { TenantSummary, TenantTable } from './tenants-ui';
import TenantEditor from './tenant-editor';
import TenantDetailsDrawer from './tenant-details-drawer';
import common from '../vehicles/vehicles.module.css';
import shared from '../approvals/approvals.module.css';
import styles from './tenants.module.css';
import RefreshButton from '../../../components/refresh-button';

const initial = { search: '', status: 'all', sort: 'name_asc' };
export default function Tenants() {
  const [draft, setDraft] = useState(initial), [applied, setApplied] = useState(initial), [offset, setOffset] = useState(0);
  const [revision, setRevision] = useState(0), [creating, setCreating] = useState(false), [selection, setSelection] = useState(null);
  const [message, setMessage] = useState(''), [filterError, setFilterError] = useState('');
  const query = listingQuery(applied, offset);
  const load = useCallback(signal => fetchTenants(query, signal), [query]);
  const resource = useResource(`${query}|${revision}`, load), data = resource.data;
  function refresh() { setRevision(value => value + 1); }
  function saved(company) {
    setCreating(false); setMessage(`Successfully saved the settings for ${company.name}!`); refresh();
    if (!selection) setSelection({ id: company.id, trigger: null });
  }
  function apply(event) {
    event.preventDefault();
    try { listingQuery(draft); setApplied({ ...draft }); setOffset(0); setFilterError(''); }
    catch (error) { setFilterError(error.message); }
  }
  return <div className={common.page}>
    <header className={`${common.heading} ${styles.heading}`}><div><h1>Tenants</h1><p>Manage the companies in your building, their drivers, and shared parking access.</p></div>
      <RefreshButton loading={resource.loading} onClick={refresh} /></header>
    {message && <p className={shared.success} role="status">{message}</p>}
    <div className={shared.actions}><button className={shared.primary} onClick={() => setCreating(true)}>Register Company</button></div>
    <TenantSummary data={data?.summary} loading={resource.loading} />
    <section className={common.workspace} aria-label="Company Listing" aria-busy={resource.loading}>
      <div className={common.toolbar}><form className={common.filters} onSubmit={apply}>
        <label>Search Companies<input value={draft.search} maxLength={120} placeholder="Search by Company Name" onChange={event => setDraft(old => ({ ...old, search: event.target.value }))} /></label>
        <label>Company Status<select value={draft.status} onChange={event => setDraft(old => ({ ...old, status: event.target.value }))}><option value="all">All Statuses</option><option value="active">Active</option><option value="inactive">Inactive</option></select></label>
        <label>Sort By<select value={draft.sort} onChange={event => setDraft(old => ({ ...old, sort: event.target.value }))}><option value="name_asc">Company Name: A–Z</option><option value="name_desc">Company Name: Z–A</option><option value="drivers_desc">Most Registered Drivers</option><option value="pending_desc">Most Pending Approvals</option></select></label>
        <div className={common.filterActions}><button className={shared.primary} type="submit">Apply Filters</button><button className={shared.secondary} type="button" onClick={() => { setDraft(initial); setApplied(initial); setOffset(0); setFilterError(''); }}>Clear</button></div>
      </form><p className={common.muted}>Summary cards cover all companies and driver registrations. Parking capacity remains shared across authorised companies.</p>
        {filterError && <p className={shared.error} role="alert">{filterError}</p>}</div>
      {resource.loading || resource.error ? <RecordsState loading={resource.loading} error={resource.error} message="Loading companies…" onRetry={refresh} /> :
        !data?.companies.length ? <RecordsState title={offset ? 'No Companies on This Page' : applied.search || applied.status !== 'all' ? 'No Matching Companies' : 'No Companies Yet'}
          message={offset ? 'The list may have changed. Return to the first page.' : 'Register a company or adjust your filters.'} onFirstPage={offset ? () => setOffset(0) : null} /> :
          <TenantTable companies={data.companies} onDetails={(id, trigger) => setSelection({ id, trigger })} />}
      <nav className={common.pagination} aria-label="Company Pagination"><span>{data ? `${data.total} companies · Page ${Math.floor(offset / 25) + 1}` : 'Loading companies…'}</span>
        <div className={shared.actions}><button className={shared.secondary} disabled={resource.loading || !offset} onClick={() => setOffset(value => Math.max(0, value - 25))}>Previous</button>
          <button className={shared.secondary} disabled={resource.loading || !data || offset + 25 >= data.total} onClick={() => setOffset(value => value + 25)}>Next</button></div></nav>
    </section>
    {selection && <TenantDetailsDrawer key={selection.id} tenantId={selection.id} trigger={selection.trigger} revision={revision} onClose={() => setSelection(null)} onSaved={saved} />}
    {creating && <TenantEditor onClose={() => setCreating(false)} onSaved={saved} />}
  </div>;
}
