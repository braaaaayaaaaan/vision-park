import { NextResponse } from 'next/server';
import { loadOverview } from '@/lib/overview-api.mjs';
import { setSessionCookies, clearSessionCookies } from '@/lib/auth.mjs';

export async function GET(request) {
  const result = await loadOverview(request);
  const response = NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });
  if (result.clear) clearSessionCookies(response);
  else if (result.session) setSessionCookies(response, result.session);
  return response;
}
