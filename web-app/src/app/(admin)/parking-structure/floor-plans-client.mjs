import { authenticatedFetch } from '../../../lib/auth-client.mjs';
export const initialState = { loading: true, uploading: false, levels: [], error: '', success: '', conflict: false };
export function floorPlanState(state, action) {
  switch (action.type) {
    case 'loading': return { ...state, loading: true, error: '', conflict: false };
    case 'loaded': return { ...state, loading: false, levels: action.levels };
    case 'uploading': return { ...state, uploading: true, error: '', success: '', conflict: false };
    case 'saved': return { ...state, uploading: false, success: 'Successfully saved floor plan!' };
    case 'levels_saved': return { ...state, success: action.message };
    case 'error': return { ...state, loading: false, uploading: false, success: '', error: action.message, conflict: action.status === 409 };
    default: return state;
  }
}
export function selectedLevelId(levels, current) {
  return levels.some(level => level.id === current) ? current : levels[0]?.id || '';
}
export function fileError(file) {
  if (!file) return 'Choose a PNG or JPEG image.';
  if (!['image/png', 'image/jpeg'].includes(file.type)) return 'Use a PNG or JPEG image.';
  if (!file.size || file.size > 10 * 1024 * 1024) return 'Choose a nonempty image of at most 10 MB.';
  return '';
}
export async function floorPlanRequest(path = '', options = {}) {
  const response = await authenticatedFetch(`/api/parking-structure${path}`, { ...options, cache: 'no-store' });
  if ([401, 403].includes(response.status)) {
    window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`);
  }
  const body = await response.json();
  if (!response.ok) {
    const error = new Error(body.error || 'Floor plan request failed. Refresh and retry.');
    error.status = response.status;
    throw error;
  }
  return body;
}
