'use client';
import { useEffect, useRef, useState } from 'react';
import ConfirmationDialog from '../../../components/confirmation-dialog';
import { reviewRequest } from './approvals-client';
import { decideSelectedRegistrations } from './bulk-registration-decisions.mjs';
import shared from './approvals.module.css';
import styles from './registration-approvals.module.css';

export default function BulkRegistrationDialog({ applicants, action, onDismiss, onComplete }) {
  const approve = action === 'approve';
  const [companies, setCompanies] = useState([]), [assignments, setAssignments] = useState({});
  const [loading, setLoading] = useState(approve), [companyError, setCompanyError] = useState(''), [attempt, setAttempt] = useState(0);
  const [pending, setPending] = useState(false), [progress, setProgress] = useState(0), [error, setError] = useState('');
  const inFlight = useRef(false), mounted = useRef(false), controller = useRef(null);
  useEffect(() => {
    mounted.current = true; controller.current = new AbortController();
    return () => { mounted.current = false; controller.current.abort(); };
  }, []);
  useEffect(() => {
    if (!approve) return;
    const request = new AbortController();
    reviewRequest('/companies', { signal: request.signal }).then(data => {
      if (request.signal.aborted) return;
      setCompanies(data.companies);
      setAssignments(Object.fromEntries(applicants.map(row => [row.id,
        row.requested_company?.is_active === true && data.companies.some(company => company.id === row.requested_tenant_id) ? row.requested_tenant_id : ''])));
      setLoading(false);
    }).catch(failure => {
      if (!request.signal.aborted) { setCompanyError(failure.message || 'Unable to load companies.'); setLoading(false); }
    });
    return () => request.abort();
  }, [approve, applicants, attempt]);
  const validAssignments = !approve || applicants.every(row => companies.some(company => company.id === assignments[row.id]));
  async function submit() {
    if (inFlight.current || !validAssignments || loading || companyError || error) return false;
    inFlight.current = true; setPending(true);
    try {
      const results = await decideSelectedRegistrations(applicants, action, { assignments, signal: controller.current?.signal,
        onProgress: value => { if (mounted.current) setProgress(value); } });
      if (mounted.current) onComplete(results);
    } catch {
      if (mounted.current) { setError('The decisions could not be confirmed. Close and refresh before selecting again.'); setPending(false); }
    }
    return false;
  }
  return <ConfirmationDialog id="bulk-registration" title={approve ? 'Approve Selected Applicants' : 'Reject Selected Applicants'}
    variant={approve ? 'default' : 'destructive'}
    description={`${approve ? 'Approve' : 'Reject'} ${applicants.length} selected pending ${applicants.length === 1 ? 'applicant' : 'applicants'} on this page? Review the names${approve ? ' and company assignments' : ''} before confirming.`}
    confirmLabel={approve ? 'Confirm Approvals' : 'Confirm Rejection(s)'} cancelLabel={error ? 'Close and Refresh' : 'Cancel'}
    pending={pending} pendingLabel={`${approve ? 'Approving' : 'Rejecting'} applicants… ${progress} of ${applicants.length} processed.`}
    disabled={loading || Boolean(companyError) || Boolean(error) || !validAssignments} error={error} onConfirm={submit}
    onCancel={() => { if (!inFlight.current || error) onDismiss(Boolean(error)); }}>
    <p>Only selected applicants are affected. Each decision is checked individually and cannot be reversed here.</p>
    {approve && (loading ? <p role="status">Loading available companies…</p> : companyError ?
      <div><p className={shared.error} role="alert">{companyError}</p><button type="button" className={shared.secondary}
        onClick={() => { setLoading(true); setCompanyError(''); setAttempt(value => value + 1); }}>Retry Companies</button></div> :
      companies.length === 0 && <p>No companies are currently available. Approval is unavailable.</p>)}
    <ul className={styles.batchApplicants}>{applicants.map(row => <li key={row.id}>
      <strong>{row.full_name || 'Name not provided'}</strong><small>{row.id}</small>
      <p>Requested company: {row.requested_company?.name || 'Not provided'}{row.requested_company?.is_active === false ? ' (inactive)' : ''}</p>
      {approve && !loading && !companyError && <label className={styles.batchCompany}>Assigned Company
        <select aria-label={`Assigned Company for ${row.full_name || row.id}`} value={assignments[row.id] || ''} disabled={pending || Boolean(error)} required
          onChange={event => setAssignments(old => ({ ...old, [row.id]: event.target.value }))}>
          <option value="">Select a company</option>{companies.map(company => <option key={company.id} value={company.id}>{company.name}</option>)}
        </select>
      </label>}
    </li>)}</ul>
  </ConfirmationDialog>;
}
