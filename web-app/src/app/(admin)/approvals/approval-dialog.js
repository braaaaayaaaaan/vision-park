"use client";
import { useEffect, useRef, useState } from 'react';
import { reviewRequest } from './approvals-client';
import styles from './approvals.module.css';

export default function ApprovalDialog({ applicant, action, onDismiss, onSuccess }) {
  const dialog = useRef(null);
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
    const element = dialog.current;
    element.showModal();
    return () => element.close();
  }, []);

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
    <dialog ref={dialog} className={styles.dialog} aria-labelledby="decision-title" aria-describedby="decision-description" onCancel={(event) => { event.preventDefault(); if (!inFlight.current) onDismiss(uncertain); }}>
      <form onSubmit={submit} aria-busy={submitting}>
        <h2 id="decision-title">{approve ? 'Approve Application' : 'Reject Application'}</h2>
        <p id="decision-description">{approve ? 'Assign a company and confirm approval for this driver.' : 'Confirm that you want to reject this driver application.'}</p>
        <div className={styles.applicant}><strong>{applicant.full_name || 'Name Not Provided'}</strong><small>{applicant.id}</small><p>Requested Company: {applicant.requested_company?.name || 'Not Provided'}</p></div>
        {approve && <div className={styles.companyField}>
          {loading ? <p role="status">Loading Available Companies…</p> : companyError ? <div><p className={styles.error} role="alert">{companyError}</p><button type="button" className={styles.secondary} onClick={() => { setLoading(true); setCompanyError(''); setAttempt((value) => value + 1); }}>Retry Companies</button></div> : <>
            <label htmlFor="assigned-company">Assigned Company</label>
            <select id="assigned-company" value={tenant} onChange={(event) => { setTenant(event.target.value); setError(''); }} disabled={submitting || uncertain} required>
              <option value="">Select A Company</option>
              {companies.map((company) => <option value={company.id} key={company.id}>{company.name}</option>)}
            </select>
            {companies.length === 0 && <p>No companies are currently available. Approval is unavailable.</p>}
          </>}
        </div>}
        {error && <p className={styles.error} role="alert">{error}</p>}
        {submitting && <p role="status">Waiting For Backend Confirmation…</p>}
        <div className={styles.dialogActions}>
          <button type="button" className={styles.secondary} disabled={submitting} onClick={() => onDismiss(uncertain)}>{uncertain ? 'Close And Refresh' : 'Cancel'}</button>
          <button type="submit" className={approve ? styles.primary : styles.reject} disabled={submitting || uncertain || (approve && (loading || Boolean(companyError) || !tenant))}>
            {submitting ? 'Submitting…' : approve ? 'Confirm Approval' : 'Confirm Rejection'}
          </button>
        </div>
      </form>
    </dialog>
  );
}
