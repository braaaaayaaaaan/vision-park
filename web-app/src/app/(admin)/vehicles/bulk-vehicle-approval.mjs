import { submitVehicleDecision } from './vehicles-client.mjs';

// Each vehicle keeps the existing authenticated, pending-only decision workflow.
// Never retry an uncertain write, and stop sending new requests if the view closes.
export async function approveSelectedVehicles(vehicles, { signal, onProgress } = {}) {
  if (!Array.isArray(vehicles) || !vehicles.length || vehicles.length > 25 ||
      vehicles.some(vehicle => !vehicle?.id || vehicle.registration_status !== 'pending')) {
    throw new Error('Select pending vehicles from the current page.');
  }
  const targets = [...new Map(vehicles.map(vehicle => [vehicle.id, vehicle])).values()];
  const results = [];
  for (const vehicle of targets) {
    if (signal?.aborted) break;
    let stop = false;
    try {
      const result = await submitVehicleDecision(vehicle.id, 'approve');
      if (result?.id !== vehicle.id || result.registration_status !== 'approved') throw new Error('Unconfirmed approval.');
      results.push({ ...vehicle, outcome: 'approved' });
    } catch (error) {
      const definiteFailure = [400, 401, 403, 404, 409, 422].includes(error.status);
      results.push({ ...vehicle, outcome: definiteFailure ? 'failed' : 'unconfirmed',
        message: definiteFailure ? error.message : 'Approval could not be confirmed. Review the refreshed status before trying again.' });
      stop = !definiteFailure || [401, 403].includes(error.status);
    }
    onProgress?.(results.length);
    if (stop) break;
  }
  for (const vehicle of targets.slice(results.length)) {
    results.push({ ...vehicle, outcome: 'not_attempted', message: 'Not attempted because the approval process stopped. Review the refreshed list before selecting again.' });
  }
  return results;
}
