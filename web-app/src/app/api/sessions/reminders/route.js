import { NextResponse } from 'next/server';
import { handleParkingReminders } from '../../../../lib/parking-reminder-api.mjs';

async function handle(request) {
  const result = await handleParkingReminders(request);
  return NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });
}
export const GET = handle;
export const POST = handle;
