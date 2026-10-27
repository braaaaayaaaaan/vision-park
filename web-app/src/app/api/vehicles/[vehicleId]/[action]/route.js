import { NextResponse } from 'next/server';
import { decideVehicle } from '@/lib/vehicles-api.mjs';

export async function POST(request, context) {
  const { vehicleId, action } = await context.params;
  const result = await decideVehicle(request, vehicleId, action);
  const response = NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });

  return response;
}
