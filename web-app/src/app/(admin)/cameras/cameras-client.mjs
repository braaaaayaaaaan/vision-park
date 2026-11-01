import { authenticatedFetch, AUTH_GENERATION } from '../../../lib/auth-client.mjs';
import { validateContext, validateCameras, validateActivity, validateEvent, validatePlayback, validateProcessing } from '../../../lib/cameras-contracts.mjs';

export async function cameraFetch(path = '', options = {}) {
  const response = await authenticatedFetch(`/api/cameras${path}`, { credentials: 'same-origin', cache: 'no-store', ...options });
  const data = await response.json().catch(() => null);
  if (!response.ok) throw Object.assign(new Error(data?.error || 'Camera information is unavailable. Refresh and try again.'), {
    code: data?.code, results: data?.results, status: response.status,
  });
  return data;
}
export const fetchCameras = signal => cameraFetch('', { signal }).then(validateCameras);
export const fetchActivity = (query, signal) => cameraFetch(`/activity?${query}`, { signal }).then(validateActivity);
export const fetchEvent = (id, signal) => cameraFetch(`/events/${id}`, { signal }).then(validateEvent);
export const fetchPlayback = (run, signal) => cameraFetch(`/playbacks/${run.playback_id}?role=${run.role}`, { signal }).then(validatePlayback);

export function createRunController({ storage, locks, send, randomId, generation = () => '' }) {
  const key = role => `visionpark-camera-run:${generation()}:${role}`;
  function restore(role) {
    try {
      const stored = JSON.parse(storage.getItem(key(role)));
      validateContext(stored, role);
      return stored.role === role ? stored : null;
    } catch { return null; }
  }
  async function execute(camera, action, previous, onPrepared) {
    if (!locks?.request) throw new Error('Use a current browser over HTTPS or localhost to coordinate processing safely.');
    const owner = generation();
    return locks.request('visionpark-recorded-processing', { mode: 'exclusive', ifAvailable: true }, async lock => {
      if (!lock) throw new Error('Another tab is processing a recording. Inspect its outcome before retrying.');
      if (owner !== generation()) throw new Error('Your administrator session changed. Reload before processing.');
      const run = action === 'retry' ? previous : {
        playback_id: randomId(), role: camera.role, recording_identity: camera.recording_identity,
        ...camera.start_context,
      };
      validateContext(run, camera.role);
      if (run.role !== camera.role) throw new Error('The original camera role is required.');
      // Fail before submitting if recovery metadata cannot be retained. No JWTs,
      // recognised plates, payment data or filesystem paths are stored here.
      storage.setItem(key(camera.role), JSON.stringify(run));
      onPrepared(run);
      const { role, playback_id, recording_identity, entrance_node_id, publication_revision } = run;
      const value = await send(`/${role}/process`, { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ playback_id, action, recording_identity, entrance_node_id, publication_revision }),
        signal: AbortSignal.timeout(170000) });
      return validateProcessing(value, playback_id);
    });
  }
  return { restore, execute };
}
export function browserRuns() {
  return createRunController({ storage: window.localStorage, locks: navigator.locks, send: cameraFetch,
    randomId: () => crypto.randomUUID(), generation: () => window.localStorage.getItem(AUTH_GENERATION) ?? '' });
}
