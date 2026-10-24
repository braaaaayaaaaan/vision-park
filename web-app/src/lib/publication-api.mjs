import { ACCESS_COOKIE, REFRESH_COOKIE, AuthError, baseUrl, restoreSession, requireSameOrigin } from './auth.mjs';
import { readLimitedBody } from './parking-structure-api.mjs';
import { validationReport, validScope } from './structure-validation-api.mjs';
import { uuid } from '../app/(admin)/parking-structure/zone-draft-utils.mjs';

export function publicationInput(input, action) {
  const allowed=action==='preview'?['level_ids','tenant_permissions']:['level_ids','tenant_permissions','expected_fingerprint','confirm'];
  if (!input || Object.keys(input).some(key=>!allowed.includes(key)) || !validScope({level_ids:input.level_ids}) ||
    !Array.isArray(input.tenant_permissions) || input.tenant_permissions.length>1000 ||
    input.tenant_permissions.some(row=>!row || Object.keys(row).length!==2 || !uuid(row.zone_id) || !Array.isArray(row.tenant_ids) || row.tenant_ids.length>100 || !row.tenant_ids.every(uuid) || new Set(row.tenant_ids.map(id=>id.toLowerCase())).size!==row.tenant_ids.length) ||
    new Set(input.tenant_permissions.map(row=>row.zone_id.toLowerCase())).size!==input.tenant_permissions.length ||
    action==='publish' && (!/^[a-f0-9]{64}$/.test(input.expected_fingerprint??'') || input.confirm!==true)) throw new AuthError('input',422);
  return {...input,level_ids:input.level_ids.map(id=>id.toLowerCase()),tenant_permissions:input.tenant_permissions.map(row=>({zone_id:row.zone_id.toLowerCase(),tenant_ids:row.tenant_ids.map(id=>id.toLowerCase())}))};
}

export function publicationPreview(data,ids) {
  const bad=()=>{throw new Error('Unconfirmed publication preview.');};
  if (!data || data.preview_version!==1 || !['blocked','ready'].includes(data.readiness) || data.can_publish!==(data.readiness==='ready') || data.planned_changes_only!==true || !['not_published','published'].includes(data.publication_status) ||
    !Number.isSafeInteger(data.current_revision)||data.current_revision<0||
    !/^[a-f0-9]{64}$/.test(data.fingerprint??'') || !Array.isArray(data.blocking_reasons) || data.can_publish!==(data.blocking_reasons.length===0) ||
    data.blocking_reasons.some(row=>typeof row.code!=='string'||typeof row.message!=='string') ||
    !Array.isArray(data.levels)||data.levels.length!==ids.length||data.levels.some(row=>!ids.includes(row.id)||typeof row.name!=='string') ||
    !Array.isArray(data.zones)||!Array.isArray(data.superseded_zones)||!Array.isArray(data.excluded_levels)||!Array.isArray(data.tenants)||!Array.isArray(data.planned_cutover)||
    !Number.isSafeInteger(data.active_sessions)||data.active_sessions<0||
    !data.proposed_graph||!Array.isArray(data.proposed_graph.nodes)||!Array.isArray(data.proposed_graph.directed_edges)||!data.operational_graph||data.schema?.status!=='verified_contract') bad();
  validationReport(data.validation,ids);
  for (const zone of data.zones) if (!uuid(zone.draft_zone_id)||!ids.includes(zone.level_id)||!['create_new','update_bound'].includes(zone.action)||!Array.isArray(zone.retained_tenant_ids)||!Array.isArray(zone.additional_tenant_ids)) bad();
  if (data.tenants.some(tenant=>!uuid(tenant.id)||typeof tenant.name!=='string'||typeof tenant.is_active!=='boolean')) bad();
  return data;
}

export async function publicationRequest(request,path) {
  let session;
  try {
    if (path.length!==2||path[0]!=='publication'||!['preview','publish'].includes(path[1])||request.method!=='POST'||new URL(request.url).search) return {status:404,body:{error:'Not found.'}};
    requireSameOrigin(request);
    session=(await restoreSession(request.cookies.get(ACCESS_COOKIE)?.value,request.cookies.get(REFRESH_COOKIE)?.value)).session;
    if(request.headers.get('content-type')?.split(';')[0].toLowerCase()!=='application/json') throw new AuthError('input',415);
    let input;try{input=JSON.parse((await readLimitedBody(request.body,64*1024)).toString());}catch(error){if(error instanceof AuthError)throw error;throw new AuthError('input',422);}
    input=publicationInput(input,path[1]);
    const response=await fetch(`${baseUrl(process.env.BACKEND_BASE_URL)}/admin/parking/structure/publication/${path[1]}`,{
      method:'POST',headers:{Authorization:`Bearer ${session?.access_token??request.cookies.get(ACCESS_COOKIE)?.value}`,'Content-Type':'application/json'},
      body:JSON.stringify(input),cache:'no-store',redirect:'error',signal:AbortSignal.timeout(60000),
    });
    if([401,403].includes(response.status))throw new AuthError(response.status===401?'expired':'denied',response.status);
    if(!response.ok){
      const value=await response.json().catch(()=>null),code=value?.detail?.code;
      return {status:[404,409,413,415,422].includes(response.status)?response.status:503,session,body:{
        error:code==='stale_preview'?'Configuration changed. Refresh publication preview.':code==='publication_blocked'?'Resolve publication blockers and refresh preview.':
          code==='active_sessions'?'Active parking sessions block publication. Refresh preview after they exit.':
          code==='busy'?'Configuration is busy. Refresh preview and retry.':code==='conflict'?'Publication conflict. Refresh preview and review current data.':
          code==='incomplete_scope'?'Include all ramp endpoint and reference levels.':response.status===422?'Check selected levels and explicit tenant permissions.':
            response.status===413?'Publication preview exceeds its size limit.':'Publication result could not be confirmed. Refresh preview and review the recorded revision.',
        required_level_ids:Array.isArray(value?.detail?.required_level_ids)&&value.detail.required_level_ids.every(uuid)?value.detail.required_level_ids:[],
      }};
    }
    if(path[1]==='publish') {
      const result=await response.json();
      if(!['published','already_published'].includes(result?.status)||!uuid(result.publication_id)||!Number.isSafeInteger(result.revision)||result.revision<1||!result.summary)throw new Error('Unconfirmed publication.');
      return {status:200,session,body:result};
    }
    return {status:200,session,body:publicationPreview(await response.json(),input.level_ids)};
  } catch(error){
    return {status:error instanceof AuthError?error.status:503,session:error.session??session,clear:error instanceof AuthError&&[401,403].includes(error.status),body:{
      error:error instanceof AuthError?error.status===422?'Use selected levels and explicit tenant choices.':error.status===413?'Publication request exceeds 64 KiB.':error.status===415?'Use a JSON publication request.':error.message:'Publication preview could not be confirmed. No publication was confirmed.',
    }};
  }
}
