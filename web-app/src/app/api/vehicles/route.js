import { NextResponse } from 'next/server';
import { loadVehicles } from '@/lib/vehicles-api.mjs';
import { setSessionCookies, clearSessionCookies } from '@/lib/auth.mjs';
export async function GET(request) {
  const result = await loadVehicles(request);
  const response = NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });
  if (result.clear) clearSessionCookies(response);
  else if (result.session) setSessionCookies(response, result.session);
  return response;
}
