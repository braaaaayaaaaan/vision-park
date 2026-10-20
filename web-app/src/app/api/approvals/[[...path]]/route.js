import { NextResponse } from 'next/server';
import { handleApprovals } from '@/lib/approvals-api.mjs';
import { setSessionCookies, clearSessionCookies } from '@/lib/auth.mjs';

async function handle(request, context) {
  const { path = [] } = await context.params;
  const result = await handleApprovals(request, path);
  const response = NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });
  if (result.clear) clearSessionCookies(response);
  else if (result.session) setSessionCookies(response, result.session);
  return response;
}
export const GET = handle;
export const POST = handle;
