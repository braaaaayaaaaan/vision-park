export async function fetchOverview(signal) {
  const response = await fetch('/api/overview', { cache: 'no-store', signal });
  if ([401, 403].includes(response.status)) {
    window.location.replace(`/login?reason=${response.status === 401 ? 'expired' : 'denied'}`);
    throw new Error('Administrator access could not be verified. Returning to sign in.');
  }
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || 'Unable to load the parking overview.');
  return data;
}
