"use client";
import { useEffect, useRef, useState } from 'react';
import ConfirmationDialog from '../../../components/confirmation-dialog';
import { reviewRequest } from './approvals-client';
import styles from './approvals.module.css';

export default function ApprovalDialog({ applicant, action, onDismiss, onSuccess }) {
  const approve = action === 'approve';
  const [companies, setCompanies] = useState([]);
  const [tenant, setTenant] = useState('');
  const [loading, setLoading] = useState(approve);
  const [companyError, setCompanyError] = useState('');
  const [attempt, setAttempt] = useState(0);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');
  const [uncertain, setUncertain] = useState(false);
  const inFlight = useRef(false);

  useEffect(() => {
    if (!approve) return;
    const controller = new AbortController();
    reviewRequest('/companies', { signal: controller.signal }).then((data) => {
      if (controller.signal.aborted) return;
      setCompanies(data.companies);
      const requested = applicant.requested_tenant_id;
      setTenant(applicant.requested_company?.is_active === true && data.companies.some((company) => company.id === requested) ? requested : '');
      setLoading(false);
    }).catch((failure) => {
      if (!controller.signal.aborted) { setCompanyError(failure.message || 'Unable to load companies. Please try again.'); setLoading(false); }
    });
    return () => controller.abort();
  }, [approve, applicant, attempt]);

  async function submit(event) {
    event.preventDefault();
    if (inFlight.current || uncertain) return;
    if (approve && !companies.some((company) => company.id === tenant)) { setError('Select an available company.'); return; }
    inFlight.current = true;
    setSubmitting(true);
    setError('');
    try {
      const result = await reviewRequest(`/${applicant.id}/${action}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(approve ? { tenant_id: tenant } : {}),
      });
      onSuccess(result);
    } catch (failure) {
      setError(failure.message || 'The result could not be confirmed. Refresh the list before retrying.');
      setUncertain(true);
      setSubmitting(false);
      inFlight.current = false;
    }
  }

  return (
    <ConfirmationDialog id="decision" title={approve ? 'Approve Application' : 'Reject Application'} variant={approve ? 'default' : 'destructive'}
      description={approve ? 'Assign a company and confirm approval for this driver.' : 'Confirm that you want to reject this driver application.'}
      onConfirm={submit} onCancel={() => { if (!inFlight.current) onDismiss(uncertain); }} pending={submitting} error={error}
      pendingLabel="Submitting…" cancelLabel={uncertain ? 'Close and Refresh' : 'Cancel'} confirmLabel={approve ? 'Confirm Approval' : 'Confirm Rejection'}
      disabled={uncertain || (approve && (loading || Boolean(companyError) || !tenant))}>
        <dl className={`${styles.applicant} ${styles.applicantDetails}`}>
          <div><dt>Driver Name</dt><dd className={styles.applicantName}>{applicant.full_name || 'Name not provided'}</dd></div>
          <div><dt>Driver ID</dt><dd className={styles.applicantId}>{applicant.id}</dd></div>
          <div><dt>Requested Company</dt><dd>{applicant.requested_company?.name || 'Not provided'}</dd></div>
        </dl>
        {approve && <div className={styles.companyField}>
          {loading ? <p role="status">Loading available companies…</p> : companyError ? <div><p className={styles.error} role="alert">{companyError}</p><button type="button" className={styles.secondary} onClick={() => { setLoading(true); setCompanyError(''); setAttempt((value) => value + 1); }}>Retry Companies</button></div> : <>
            <label htmlFor="assigned-company">Assigned Company</label>
            <select id="assigned-company" value={tenant} onChange={(event) => { setTenant(event.target.value); setError(''); }} disabled={submitting || uncertain} required>
              <option value="">Select a company</option>
              {companies.map((company) => <option value={company.id} key={company.id}>{company.name}</option>)}
            </select>
            {companies.length === 0 && <p>No companies are currently available. Approval is unavailable.</p>}
          </>}
        </div>}
    </ConfirmationDialog>
  );
}
