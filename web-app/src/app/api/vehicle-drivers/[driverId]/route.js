import { NextResponse } from 'next/server';
import { loadVehicleRead } from '@/lib/vehicles-api.mjs';
import { setSessionCookies, clearSessionCookies } from '@/lib/auth.mjs';

export async function GET(request, context) {
  const { driverId } = await context.params;
  const result = await loadVehicleRead(request, 'details', driverId);
  const response = NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });
  if (result.clear) clearSessionCookies(response);
  else if (result.session) setSessionCookies(response, result.session);
  return response;
}
