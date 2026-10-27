import { NextResponse } from 'next/server';
import { loadVehicleRead } from '@/lib/vehicles-api.mjs';

export async function GET(request, context) {
  const { driverId } = await context.params;
  const result = await loadVehicleRead(request, 'details', driverId);
  const response = NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });

  return response;
}
