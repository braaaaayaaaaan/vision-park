import { NextResponse } from 'next/server';
import { loadAnalytics } from '@/lib/analytics-api.mjs';
export async function GET(request) {
  const result = await loadAnalytics(request);
  const response = NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });

  return response;
}
