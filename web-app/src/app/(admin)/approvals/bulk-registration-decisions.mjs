import { reviewRequest } from './approvals-client.js';

const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);

// Keep the existing pending-only, authenticated decision endpoint for each user.
// An uncertain write is never retried; stop before processing the next applicant.
export async function decideSelectedRegistrations(applicants, action, { assignments = {}, signal, onProgress } = {}) {
  if (!['approve', 'reject'].includes(action) || !Array.isArray(applicants) || !applicants.length || applicants.length > 10 ||
      applicants.some(row => !uuid(row?.id) || row.approval_status !== 'pending') ||
      new Set(applicants.map(row => row.id)).size !== applicants.length ||
      (action === 'approve' && applicants.some(row => !uuid(assignments[row.id])))) {
    throw new Error('Select pending applicants from the current page and assign an available company to each approval.');
  }
  const targets = applicants.map(row => ({ ...row })), results = [];
  const status = action === 'approve' ? 'approved' : 'rejected';
  const tenants = { ...assignments };
  for (const applicant of targets) {
    if (signal?.aborted) break;
    let stop = false;
    try {
      const tenant = action === 'approve' ? tenants[applicant.id] : null;
      const result = await reviewRequest(`/${applicant.id}/${action}`, { method: 'POST',
        headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(action === 'approve' ? { tenant_id: tenant } : {}),
      });
      if (result?.id !== applicant.id || result.approval_status !== status ||
          result.is_active !== (action === 'approve') || result.tenant_id !== tenant) throw new Error('Unconfirmed decision.');
      results.push({ ...applicant, outcome: status });
    } catch (error) {
      const definite = [400, 401, 403, 404, 409, 422, 429].includes(error.status);
      results.push({ ...applicant, outcome: definite ? 'failed' : 'unconfirmed', message: definite ? error.message :
        'This decision could not be confirmed. Review the refreshed registration status before trying again.' });
      stop = !definite || [401, 403, 429].includes(error.status);
    }
    onProgress?.(results.length);
    if (stop) break;
  }
  return [...results, ...targets.slice(results.length).map(row => ({ ...row, outcome: 'not_attempted',
    message: 'Not attempted because processing stopped. Review the refreshed list before selecting again.' }))];
}
