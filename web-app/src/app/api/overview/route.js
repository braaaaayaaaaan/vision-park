import { NextResponse } from 'next/server';
import { loadOverview } from '@/lib/overview-api.mjs';

export async function GET(request) {
  const result = await loadOverview(request);
  const response = NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });

  return response;
}
