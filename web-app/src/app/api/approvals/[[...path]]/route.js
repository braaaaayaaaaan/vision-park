import { NextResponse } from 'next/server';
import { handleApprovals } from '@/lib/approvals-api.mjs';

async function handle(request, context) {
  const { path = [] } = await context.params;
  const result = await handleApprovals(request, path);
  const response = NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });

  return response;
}
export const GET = handle;
export const POST = handle;
