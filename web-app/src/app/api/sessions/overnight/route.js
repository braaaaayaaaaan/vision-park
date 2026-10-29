import { NextResponse } from 'next/server';
import { loadOvernightAlerts } from '../../../../lib/overnight-api.mjs';

export async function GET(request) {
  const result = await loadOvernightAlerts(request);
  return NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });
}
