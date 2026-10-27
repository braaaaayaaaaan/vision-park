import { NextResponse } from 'next/server';
import { loadVehicles } from '@/lib/vehicles-api.mjs';
export async function GET(request) {
  const result = await loadVehicles(request);
  const response = NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });

  return response;
}
