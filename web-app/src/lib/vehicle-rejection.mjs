export const rejectionReasonLimit = 500;

export function normalizeRejectionReason(value) {
  if (typeof value !== 'string') throw new Error('Enter a rejection reason.');
  const reason = value.replace(/\r\n?/g, '\n').replace(/^[\s\u0085\u001c-\u001f]+|[\s\u0085\u001c-\u001f]+$/g, '');
  if (!reason) throw new Error('Enter a rejection reason.');
  if ([...reason].length > rejectionReasonLimit) throw new Error('Use 500 characters or fewer for the rejection reason.');
  if (/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(reason)) throw new Error('Use plain text without control characters for the rejection reason.');
  return reason;
}

export function validStoredRejectionReason(value, status) {
  if (value == null) return true; // Older rejected records may have no reason.
  try { return status === 'rejected' && normalizeRejectionReason(value) === value; }
  catch { return false; }
}
