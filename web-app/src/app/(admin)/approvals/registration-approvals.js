"use client";
import RefreshButton from '../../../components/refresh-button';
import { useCallback, useState } from 'react';
import { reviewRequest } from './approvals-client';
import { approvalQuery } from '../../../lib/approval-read-contracts.mjs';
import useReviewResource from '../vehicles/use-vehicle-resource';
import { StatusBadge, InactiveBadge, RecordsState } from '../vehicles/vehicles-ui';
import ApprovalDialog from './approval-dialog';
import BulkRegistrationDialog from './bulk-registration-dialog';
import RegistrationSummary from './registration-summary';
import shared from './approvals.module.css';
import styles from './registration-approvals.module.css';
import vehicles from '../vehicles/vehicles.module.css';
import checkboxStyles from '../../../components/selection-checkbox.module.css';

const pageSize = 10;
const initial = { status: 'pending', tenant_id: '', sort: 'name_asc' };
const statuses = { pending: 'Pending', approved: 'Approved', rejected: 'Rejected' };
const loadSummary = signal => reviewRequest('/summary', { signal });

export default function RegistrationApprovals() {
  const [offset, setOffset] = useState(0), [revision, setRevision] = useState(0);
  const [draft, setDraft] = useState(initial), [applied, setApplied] = useState(initial);
  const [notice, setNotice] = useState(''), [inputError, setInputError] = useState('');
  const [selection, setSelection] = useState(null);
  const [checked, setChecked] = useState([]), [batch, setBatch] = useState(null), [batchResults, setBatchResults] = useState(null);
  const query = approvalQuery({ ...applied, limit: String(pageSize), offset: String(offset) }).toString();
  const load = useCallback(signal => reviewRequest(`?${query}`, { signal }), [query]);
  const records = useReviewResource(`registrations|${query}|${revision}`, load);
  const summary = useReviewResource(`registration-summary|${revision}`, loadSummary);
  const data = records.data, locked = Boolean(selection || batch);
  const companies = (summary.data ?? summary.previous)?.companies ?? [];
  const pendingApplicants = !records.loading && !records.error ? (data?.applications ?? []).filter(row => row.approval_status === 'pending') : [];
  const selectedApplicants = pendingApplicants.filter(row => checked.includes(row.id));
  const allChecked = pendingApplicants.length > 0 && selectedApplicants.length === pendingApplicants.length;
  const mixedChecked = selectedApplicants.length > 0 && !allChecked;

  function refresh(nextOffset = offset) { setChecked([]); setOffset(nextOffset); setRevision(value => value + 1); }
  function changePage(nextOffset) { setChecked([]); setOffset(nextOffset); }
  function apply(event) {
    event.preventDefault();
    try {
      approvalQuery(draft);
      setApplied(draft); setOffset(0); setChecked([]); setInputError(''); setNotice(''); setBatchResults(null);
    } catch (error) { setInputError(error.message); }
  }
  function choose(applicant, action) { setNotice(''); setBatchResults(null); setSelection({ applicant, action }); }
  function chooseBatch(action) {
    if (locked || !selectedApplicants.length) return;
    setNotice(''); setBatchResults(null); setBatch({ applicants: selectedApplicants, action });
  }
  const filtered = Boolean(applied.tenant_id || applied.status !== 'pending');
  return <div className={vehicles.page}>
    <header className={vehicles.heading}>
      <div><h1>Registration Approvals</h1><p>Review driver registrations and assign an approved company.</p></div>
      <RefreshButton onClick={() => { setNotice(''); refresh(); }} loading={records.loading} disabled={locked} />
    </header>
    <RegistrationSummary resource={summary} locked={locked} onRetry={() => refresh()} />
    {notice && <p className={shared.success} role="status">{notice}</p>}
    {batchResults && <section className={styles.batchResults} aria-labelledby="batch-results-title">
      <div className={styles.batchResultsHeading}><h2 id="batch-results-title">Application Decision Results</h2>
        <button type="button" className={shared.secondary} onClick={() => setBatchResults(null)}>Dismiss</button></div>
      <p role="status">{batchResults.filter(row => ['approved', 'rejected'].includes(row.outcome)).length} of {batchResults.length} decisions confirmed.</p>
      <ul className={styles.resultList}>{batchResults.map(row => <li key={row.id}>
        <div><strong>{row.full_name || row.id}</strong><span className={styles.outcome} data-outcome={row.outcome}>
          {{ approved: 'Approved', rejected: 'Rejected', failed: 'Failed', unconfirmed: 'Unconfirmed', not_attempted: 'Not Attempted' }[row.outcome]}</span></div>
        {row.message && <p>{row.message}</p>}
      </li>)}</ul>
    </section>}
    <section className={`${vehicles.workspace} ${styles.workspace}`} aria-label="Driver Registrations">
      <div className={vehicles.toolbar}>
        <form className={vehicles.filters} onSubmit={apply}>
          <label>Company<select value={draft.tenant_id} disabled={locked || (!summary.data && !summary.previous)}
            onChange={event => setDraft(old => ({ ...old, tenant_id: event.target.value }))}>
            <option value="">All Companies</option>{companies.map(company => <option key={company.id} value={company.id}>{company.name}</option>)}
          </select></label>
          <label>Approval Status<select value={draft.status} disabled={locked} onChange={event => setDraft(old => ({ ...old, status: event.target.value }))}>
            <option value="all">All Statuses</option>{Object.entries(statuses).map(([value, label]) => <option key={value} value={value}>{label}</option>)}
          </select></label>
          <label>Sort by Driver Name<select value={draft.sort} disabled={locked} onChange={event => setDraft(old => ({ ...old, sort: event.target.value }))}>
            <option value="name_asc">A–Z</option><option value="name_desc">Z–A</option>
          </select></label>
          <div className={vehicles.filterActions}><button className={shared.primary} disabled={locked}>Apply Filters</button>
            <button type="button" className={shared.secondary} disabled={locked} onClick={() => { setDraft(initial); setApplied(initial); setOffset(0); setChecked([]); setInputError(''); setNotice(''); setBatchResults(null); }}>Clear Filters</button></div>
        </form>
        {inputError && <p className={shared.error} role="alert">{inputError}</p>}
        <p className={vehicles.filterNote}>Only pending applications can be approved or rejected.</p>
      </div>
      <div className={styles.bulkToolbar} role="group" aria-label="Bulk Application Decisions">
        <div><strong>{selectedApplicants.length} Selected</strong><p>Select applicants individually or select all pending applicants on this page.</p></div>
        <div className={shared.actions}>
          <button type="button" className={shared.approve} disabled={locked || !selectedApplicants.length} onClick={() => chooseBatch('approve')}>Approve Selected</button>
          <button type="button" className={shared.reject} disabled={locked || !selectedApplicants.length} onClick={() => chooseBatch('reject')}>Reject Selected</button>
          <button type="button" className={shared.secondary} disabled={locked || !selectedApplicants.length} onClick={() => setChecked([])}>Clear Selection</button>
        </div>
      </div>
      <div aria-busy={records.loading} aria-label="Driver Registration Records">
        {records.loading || records.error ? <RecordsState loading={records.loading} error={records.error}
          message={applied.status === 'pending' ? 'Loading pending applications…' : 'Loading driver registrations…'} onRetry={() => refresh()} />
          : !data?.applications.length ? <RecordsState title={offset > 0 ? 'No Registrations on This Page' : filtered ? 'No Matching Registrations' : 'No Pending Applications'}
            message={offset > 0 ? 'The registrations may have changed. Return to the first page.' : filtered ? 'Adjust or clear the filters to find registrations.' : 'New pending applications will appear here when submitted.'}
            onFirstPage={offset > 0 ? () => changePage(0) : null} />
            : <div className={shared.tableScroll} tabIndex={0} aria-label="Scrollable Applications Table">
              <table className={`${shared.table} ${styles.registrationTable}`}>
                <caption className={shared.srOnly}>Driver Registration Applications</caption>
                <thead><tr><th scope="col"><input className={checkboxStyles.checkbox} type="checkbox" aria-label="Select all pending applicants on this page" checked={allChecked}
                  aria-checked={mixedChecked ? 'mixed' : allChecked} disabled={locked || !pendingApplicants.length}
                  ref={element => { if (element) element.indeterminate = mixedChecked; }}
                  onChange={event => setChecked(event.target.checked ? pendingApplicants.map(row => row.id) : [])} /></th>
                  <th scope="col">Applicant</th><th scope="col">Company</th><th scope="col">Approval Status</th><th scope="col">Actions</th></tr></thead>
                <tbody>{data.applications.map(applicant => {
                  const approved = applicant.approval_status === 'approved';
                  const company = approved ? applicant.company : applicant.requested_company;
                  return <tr key={applicant.id} data-selected={checked.includes(applicant.id) || undefined}>
                    <td><input className={checkboxStyles.checkbox} type="checkbox" aria-label={`Select ${applicant.full_name || applicant.id}`} checked={checked.includes(applicant.id)}
                      disabled={locked || applicant.approval_status !== 'pending'} onChange={event => setChecked(old => event.target.checked ? [...new Set([...old, applicant.id])] : old.filter(id => id !== applicant.id))} /></td>
                    <td><strong>{applicant.full_name || 'Name Not Provided'}</strong><small className={styles.identifier}>{applicant.id}</small></td>
                    <td>{company?.name || 'Not Provided'}<small>{approved ? 'Assigned Company' : 'Requested Company'}{company?.is_active === false ? ' · Inactive' : ''}</small></td>
                    <td><div className={styles.statusBadges}><StatusBadge status={applicant.approval_status} />
                      {approved && !applicant.is_active && <InactiveBadge />}</div></td>
                    <td>{applicant.approval_status === 'pending' ? <div className={`${shared.actions} ${styles.rowActions}`}>
                      <button className={shared.approve} disabled={locked} onClick={() => choose(applicant, 'approve')} aria-label={`Approve ${applicant.full_name || applicant.id}`}>Approve</button>
                      <button className={shared.reject} disabled={locked} onClick={() => choose(applicant, 'reject')} aria-label={`Reject ${applicant.full_name || applicant.id}`}>Reject</button>
                    </div> : <span className={vehicles.muted}>—</span>}</td>
                  </tr>;
                })}</tbody>
              </table>
            </div>}
      </div>
      <nav className={vehicles.pagination} aria-label="Applications Pagination">
        <span>Page {Math.floor(offset / pageSize) + 1}{data?.applications.length ? ` · Showing ${offset + 1}–${offset + data.applications.length}` : ''}</span>
        <div className={shared.actions}>
          <button className={shared.secondary} disabled={records.loading || offset === 0 || locked} onClick={() => changePage(Math.max(0, offset - pageSize))}>Previous</button>
          <button className={shared.secondary} disabled={records.loading || !data?.hasNext || locked} onClick={() => changePage(offset + pageSize)}>Next</button>
        </div>
      </nav>
    </section>
    {selection && <ApprovalDialog {...selection} onDismiss={(reload = false) => { setSelection(null); if (reload) refresh(0); }}
      onSuccess={result => {
        setNotice(result.approval_status === 'approved' ? 'Successfully approved the selected user!' : `${selection.applicant.full_name || 'Application'}: Rejected.`);
        setSelection(null); refresh(0);
      }} />}
    {batch && <BulkRegistrationDialog {...batch} onDismiss={(reload = false) => { setBatch(null); if (reload) refresh(0); }}
      onComplete={results => { setBatchResults(results); setBatch(null); refresh(0); }} />}
  </div>;
}
