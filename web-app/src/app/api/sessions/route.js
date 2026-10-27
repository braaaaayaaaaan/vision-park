import { NextResponse } from 'next/server';
import { loadSessions } from '@/lib/sessions-api.mjs';
export async function GET(request) {
  const result = await loadSessions(request);
  const response = NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });

  return response;
}
