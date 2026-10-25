import { NextResponse } from 'next/server';
import { handleTenants } from '@/lib/tenants-api.mjs';
import { setSessionCookies, clearSessionCookies } from '@/lib/auth.mjs';

async function handle(request, context) {
  const { path = [] } = await context.params;
  const result = await handleTenants(request, path);
  const response = NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });
  if (result.clear) clearSessionCookies(response);
  else if (result.session) setSessionCookies(response, result.session);
  return response;
}
export const GET = handle;
export const POST = handle;
export const PUT = handle;
