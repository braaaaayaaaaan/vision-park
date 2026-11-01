import { NextResponse } from 'next/server';
import { cameraRequest } from '@/lib/cameras-api.mjs';

export const runtime = 'nodejs';
export const maxDuration = 180;
async function handle(request, context) {
  const { path = [] } = await context.params;
  const result = await cameraRequest(request, path);
  const headers = { ...result.headers, 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' };
  return result.media ? new NextResponse(result.stream, { status: result.status, headers }) :
    NextResponse.json(result.body, { status: result.status, headers });
}
export const GET = handle;
export const HEAD = handle;
export const POST = handle;
