import { NextResponse } from 'next/server';
import { handlePayments } from '@/lib/payments-api.mjs';

async function handle(request, context) {
  const { path = [] } = await context.params;
  const result = await handlePayments(request, path);
  return NextResponse.json(result.body, { status: result.status, headers: { 'Cache-Control': 'private, no-store' } });
}
export const GET = handle;
export const POST = handle;
