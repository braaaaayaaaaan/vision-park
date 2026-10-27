import { NextResponse } from 'next/server';
import { handleTenants } from '@/lib/tenants-api.mjs';

async function handle(request, context) {
  const { path = [] } = await context.params;
  const result = await handleTenants(request, path);
  const response = NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });

  return response;
}
export const GET = handle;
export const POST = handle;
export const PUT = handle;
