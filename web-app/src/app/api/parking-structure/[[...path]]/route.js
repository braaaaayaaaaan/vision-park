import { NextResponse } from 'next/server';
import { structureRequest } from '@/lib/parking-structure-api.mjs';
import { crossLevelRequest } from '@/lib/cross-level-api.mjs';
import { levelManagementRequest } from '@/lib/level-management-api.mjs';
import { zoneDraftRequest } from '@/lib/zone-drafts-api.mjs';
import { nodeZoneRequest } from '@/lib/zone-entrances-api.mjs';
import { structureValidationRequest } from '@/lib/structure-validation-api.mjs';
import { setSessionCookies, clearSessionCookies } from '@/lib/auth.mjs';

async function handle(request, context) {
  const { path = [] } = await context.params;
  const result = path.length === 1 && path[0] === 'validate' ? await structureValidationRequest(request) :
    path[0] === 'levels' && path[2] === 'node-zone-draft' ? await nodeZoneRequest(request, path) :
    path[0] === 'levels' && path[2] === 'zone-drafts' ? await zoneDraftRequest(request, path) :
    ['POST', 'PATCH', 'DELETE'].includes(request.method) ? await levelManagementRequest(request, path) :
    path.length === 1 && path[0] === 'cross-level-draft-edges' ? await crossLevelRequest(request) : await structureRequest(request, path);
  const headers = { 'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff' };
  const response = result.image
    ? new NextResponse(result.image, { status: result.status, headers: { ...headers, 'Content-Type': 'image/png' } })
    : NextResponse.json(result.body, { status: result.status, headers });
  if (result.clear) clearSessionCookies(response);
  else if (result.session) setSessionCookies(response, result.session);
  return response;
}
export const GET = handle;
export const PUT = handle;
export const POST = handle;
export const PATCH = handle;
export const DELETE = handle;
