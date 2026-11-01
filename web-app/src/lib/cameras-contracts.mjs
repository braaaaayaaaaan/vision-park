export const roles = ['entrance', 'exit'];
export const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const hash = value => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value);
const text = value => typeof value === 'string' && value.trim().length > 0;
const fail = () => { throw new Error('Camera information could not be verified. Keep the original processing identity.'); };
export const outcomeLabels = {
  allocated: 'Allocated', completed: 'Exit Completed', payment_required: 'Payment Required',
  payment_pending: 'Pending Payment', payment_succeeded: 'Successful Payment', rejected: 'Rejected',
  error: 'Outcome Unconfirmed', registered: 'Registered', pending: 'Pending Processing',
  processed: 'Processed', unmatched: 'Unmatched', unclassified: 'Outcome Not Recorded',
};
export const reasonLabels = {
  unknown_vehicle: 'The plate is not registered.', registration_not_approved: 'Vehicle registration is not approved.',
  existing_active_session: 'The vehicle already has an active session.', no_active_session: 'No active session was found.',
  payment_required: 'Payment is required by the driver before exiting the parking building.', payment_pending: 'Payment is pending; exit is not confirmed.',
  inactive_user: 'The vehicle owner is inactive.', inactive_tenant: 'The associated company is inactive.',
  no_authorised_zones: 'The company has no authorised zones.', zones_full: 'Eligible parking zones are full.',
  no_operational_zones: 'No authorised zones are operational.', zones_unavailable: 'Eligible zones are unavailable.',
  no_reachable_zones: 'No available zone is reachable.', configuration_changed: 'Parking Structure changed. Review this run.',
  database_unavailable: 'The outcome is unconfirmed. Inspect and retry the same run.',
  invalid_event: 'The recognition did not meet the event requirements.', stale_event: 'A newer parking stay exists.',
};
export function validateContext(value, role) {
  if (!value || !uuid(value.playback_id) || !roles.includes(role) || !hash(value.recording_identity) ||
      !Number.isSafeInteger(value.publication_revision) || value.publication_revision < 0 ||
      (role === 'entrance' ? !uuid(value.entrance_node_id) || value.publication_revision < 1 :
        value.entrance_node_id !== null || value.publication_revision !== 0)) fail();
  return value;
}
export function validateCameras(value) {
  if (!value || !Array.isArray(value.cameras) || value.cameras.length !== 2 ||
      new Set(value.cameras.map(camera => camera.role)).size !== 2 || value.cameras.some(camera =>
        !roles.includes(camera.role) || !text(camera.name) || !text(camera.filename) ||
        !/^[\w.-]+\.mp4$/i.test(camera.filename) || typeof camera.available !== 'boolean' ||
        !(camera.recording_identity === null || hash(camera.recording_identity)))) fail();
  if (value.active_run && (!roles.includes(value.active_run.role) || !text(value.active_run.playback_id))) fail();
  return value;
}
export function validateEvent(event) {
  if (!event || !uuid(event.id) || !text(event.event_id) || !roles.includes(event.camera_role) ||
      !/^[A-Z0-9]{1,32}$/.test(event.plate_number) || !Number.isFinite(Date.parse(event.accepted_event_time)) ||
      !text(event.outcome) || !(event.session_id === null || uuid(event.session_id)) ||
      !(event.playback_id === null || uuid(event.playback_id))) fail();
  return event;
}
export function validateActivity(value) {
  if (!value || !Array.isArray(value.events) || !Number.isSafeInteger(value.total) || value.total < 0 ||
      !Number.isSafeInteger(value.limit) || value.limit < 1 || !Number.isSafeInteger(value.offset) || value.offset < 0) fail();
  value.events.forEach(validateEvent);
  return value;
}
export function validatePlayback(value) {
  if (!value || typeof value.saved !== 'boolean' || !Array.isArray(value.events)) fail();
  value.events.forEach(validateEvent);
  return value;
}
export function validateProcessing(value, playbackId) {
  if (!value || value.playback_id !== playbackId || !Array.isArray(value.results) || value.results.some(row =>
    !row || !text(row.status) || !row.event || !roles.includes(row.event.camera_role) ||
    !/^[A-Z0-9]{1,32}$/.test(row.event.plate_number))) fail();
  return value;
}
