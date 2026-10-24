"use client";
import { useEffect, useState } from 'react';
import { reviewRequest } from './approvals-client';
import ApprovalDialog from './approval-dialog';
import styles from './approvals.module.css';

const pageSize = 10;
export default function RegistrationApprovals() {
  const [offset, setOffset] = useState(0);
  const [revision, setRevision] = useState(0);
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [selection, setSelection] = useState(null);

  useEffect(() => {
    const controller = new AbortController();
    reviewRequest(`?limit=${pageSize}&offset=${offset}`, { signal: controller.signal })
      .then((result) => { if (!controller.signal.aborted) { setData(result); setLoading(false); } })
      .catch((failure) => { if (!controller.signal.aborted) { setError(failure.message || 'Unable to load applications. Please try again.'); setLoading(false); } });
    return () => controller.abort();
  }, [offset, revision]);

  function refresh(nextOffset = offset) {
    setLoading(true);
    setData(null);
    setError('');
    setOffset(nextOffset);
    setRevision((value) => value + 1);
  }

  return (
    <div className={styles.page}>
      <div className={styles.heading}>
        <div><h1>Registration Approvals</h1><p>Review pending driver applications and assign an approved company.</p></div>
        <button className={styles.secondary} onClick={() => { setNotice(''); refresh(); }} disabled={loading || Boolean(selection)}>Refresh</button>
      </div>
      <section className={styles.summary} aria-labelledby="pending-summary">
        <h2 id="pending-summary">Pending Applications</h2>
        <p><strong>{loading ? '—' : data ? data.applications.length : '—'}</strong> <span>On this page</span></p>
      </section>
      {notice && <p className={styles.success} role="status">{notice}</p>}
      <section className={styles.card} aria-label="Pending Driver Applications" aria-busy={loading}>
        {loading ? <div className={styles.state} role="status">Loading pending applications…</div> : error ? (
          <div className={styles.state}><p className={styles.error} role="alert">{error}</p><button className={styles.secondary} onClick={() => refresh()}>Try Again</button></div>
        ) : data?.applications.length === 0 ? (
          <div className={styles.state}><h2>{offset === 0 ? 'No Pending Applications' : 'No Applications on This Page'}</h2><p>{offset === 0 ? 'New driver applications will appear here when they are submitted.' : 'The pending list may have changed. Return to the previous page or refresh.'}</p></div>
        ) : (
          <div className={styles.tableScroll} tabIndex={0} aria-label="Scrollable Applications Table">
            <table className={styles.table}>
              <caption className={styles.srOnly}>Pending Driver Applications</caption>
              <thead><tr><th scope="col">Applicant</th><th scope="col">Requested Company</th><th scope="col">Status</th><th scope="col">Actions</th></tr></thead>
              <tbody>{data?.applications.map((applicant) => (
                <tr key={applicant.id}>
                  <td><strong>{applicant.full_name || 'Name not provided'}</strong><small className={styles.identifier}>{applicant.id}</small></td>
                  <td>{applicant.requested_company?.name || 'Not provided'}{applicant.requested_company?.is_active === false && <small className={styles.identifier}>Company inactive</small>}</td>
                  <td><span className={styles.badge}>Pending</span></td>
                  <td><div className={styles.actions}>
                    <button className={styles.approve} onClick={() => { setNotice(''); setSelection({ applicant, action: 'approve' }); }} aria-label={`Approve ${applicant.full_name || applicant.id}`}>Approve</button>
                    <button className={styles.reject} onClick={() => { setNotice(''); setSelection({ applicant, action: 'reject' }); }} aria-label={`Reject ${applicant.full_name || applicant.id}`}>Reject</button>
                  </div></td>
                </tr>
              ))}</tbody>
            </table>
          </div>
        )}
        <nav className={styles.pagination} aria-label="Applications Pagination">
          <span>Page {Math.floor(offset / pageSize) + 1}{data?.applications.length ? ` · Showing ${offset + 1}–${offset + data.applications.length}` : ''}</span>
          <div className={styles.actions}>
            <button className={styles.secondary} disabled={loading || offset === 0 || Boolean(selection)} onClick={() => refresh(Math.max(0, offset - pageSize))}>Previous</button>
            <button className={styles.secondary} disabled={loading || !data?.hasNext || Boolean(selection)} onClick={() => refresh(offset + pageSize)}>Next</button>
          </div>
        </nav>
      </section>
      {selection && <ApprovalDialog {...selection}
        onDismiss={(reload = false) => { setSelection(null); if (reload) refresh(0); }}
        onSuccess={(result) => {
          setNotice(`${selection.applicant.full_name || 'Application'}: ${result.approval_status === 'approved' ? 'Approved' : 'Rejected'}.`);
          setSelection(null);
          refresh(0);
        }} />}
    </div>
  );
}
