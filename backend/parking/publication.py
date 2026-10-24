"""Validated preview and revision-checked atomic operational publication."""
import hashlib
import json
import logging
import re
from uuid import UUID
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field, model_validator
from backend import database
from backend.parking import structure_validation
from backend.routing.dijkstra import shortest_routes

MAX_BODY_BYTES = 64 * 1024
logger=logging.getLogger(__name__)


def execute_rpc(name,params):
    try:
        return database._execute(database.get_supabase().rpc(name,params)).data
    except database.DatabaseError as error:
        cause=error.__context__
        code=getattr(cause,'code',None)
        safe_code=code if isinstance(code,str) and re.fullmatch(r'[A-Z0-9]{5,12}',code) else 'unknown'
        logger.error('Stage6 RPC failed rpc=%s database_code=%s error_type=%s',name,safe_code,type(cause or error).__name__)
        raise


class TenantChoice(BaseModel):
    model_config = ConfigDict(extra='forbid')
    zone_id: UUID
    tenant_ids: list[UUID] = Field(max_length=100)

    @model_validator(mode='after')
    def unique_tenants(self):
        if len(set(self.tenant_ids)) != len(self.tenant_ids):
            raise ValueError('Select each tenant once.')
        return self


class PreviewInput(structure_validation.ValidationScope):
    tenant_permissions: list[TenantChoice] = Field(default_factory=list, max_length=1000)

    @model_validator(mode='after')
    def unique_zones(self):
        if len({row.zone_id for row in self.tenant_permissions}) != len(self.tenant_permissions):
            raise ValueError('Select each zone once.')
        return self


class PublishInput(PreviewInput):
    expected_fingerprint: str = Field(pattern=r'^[a-f0-9]{64}$')
    confirm: bool = Field(strict=True)


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()).hexdigest()


def preview_context(context, change):
    snapshot = context['draft']
    selected = {str(value) for value in change.level_ids}
    if {row['id'] for row in snapshot['levels']} != selected or len(snapshot['levels']) != len(selected):
        raise ValueError('Incomplete preview scope.')
    validation = structure_validation.validate_snapshot(snapshot)
    operational = {row['id']: row for row in context['zones']}
    tenants = {row['id']: row for row in context['tenants']}
    requested = {str(row.zone_id): {str(value) for value in row.tenant_ids} for row in change.tenant_permissions}
    draft_zone_ids = {row['id'] for level in snapshot['levels'] for row in level['zones']}
    if set(requested)-draft_zone_ids or any(tenant not in tenants or not tenants[tenant]['is_active'] for ids in requested.values() for tenant in ids):
        raise HTTPException(422, 'Select current draft zones and active tenants only.')
    blockers = []
    if validation['readiness'] != 'ready':
        blockers.append(dict(code='draft_not_ready', message='Resolve all blocking Configuration Validation issues before publishing.'))
    owned_zones={row['draft_zone_id']:row for row in context['zone_bindings']}
    owned_nodes={row['draft_node_id']:row for row in context['node_bindings']}
    existing_nodes={row['id']:row for row in context['graph']['node_rows']}
    permissions = context['permissions']
    zones, level_changes, targets = [], [], set()
    mappings = {link['zone_id']: link for level in snapshot['levels'] for link in level['mappings']}
    zone_results = {row['zone_id']: row for row in validation['zones']}
    proposed_names=set()
    for level in snapshot['levels']:
        total = unavailable = usable = 0
        for row in level['zones']:
            binding = row['operational_zone_id']
            existing = operational.get(binding)
            if binding:
                if not existing or existing['level_id'] != level['id'] or binding in targets:
                    blockers.append(dict(code='invalid_operational_binding', zone_id=row['id'], message='The explicit operational zone binding is missing, cross-level or reused. Review its stable identity.'))
                targets.add(binding)
            elif row['id'] in operational:
                blockers.append(dict(code='zone_identity_collision',zone_id=row['id'],message='The new zone UUID already belongs to an unrelated operational record. No automatic match is permitted.'))
            owner=owned_zones.get(row['id'])
            if owner and owner['operational_zone_id']!=binding:
                blockers.append(dict(code='binding_changed',zone_id=row['id'],message='A published zone binding cannot be silently retargeted.'))
            original_name=owner['source_name'] if owner else (existing or {}).get('name')
            if existing and existing['historical_sessions'] and row['name']!=original_name:
                blockers.append(dict(code='historical_identity', zone_id=row['id'], message='Renaming this bound operational zone would change labels shown for historical sessions. Preserve its meaning or choose a separately tracked identity.'))
            operational_name=owner['operational_name'] if owner and row['name']==owner['source_name'] else row['name']
            if any(zone['level_id']==level['id'] and zone['name']==operational_name and zone['id']!=binding for zone in operational.values()):
                operational_name=f"{row['name']} [VP:{row['id']}]"
            if (level['id'],operational_name) in proposed_names:
                operational_name=f"{row['name']} [VP:{row['id']}]"
            if (level['id'],operational_name) in proposed_names or any(zone['level_id']==level['id'] and zone['name']==operational_name and zone['id']!=binding for zone in operational.values()):
                blockers.append(dict(code='zone_name_collision',zone_id=row['id'],message='The proposed operational name is already in use. Choose a distinct draft name.'))
            proposed_names.add((level['id'],operational_name))
            entrance=mappings.get(row['id'],{}).get('node_id')
            if entrance and any(zone['entrance_node_id']==entrance and zone['id']!=binding for zone in operational.values()):
                blockers.append(dict(code='entrance_identity_in_use',zone_id=row['id'],message='This entrance is still associated with another operational zone. Preserve its explicit binding or choose a new entrance node.'))
            operational_code=existing['code'] if existing else f"VPZ:{row['id']}"
            if any(zone['code']==operational_code and zone['id']!=binding for zone in operational.values()):
                blockers.append(dict(code='zone_code_collision',zone_id=row['id'],message='The proposed globally unique operational code is already owned by another record.'))
            retained = {permission['tenant_id'] for permission in permissions if permission['zone_id']==binding}
            additional = requested.get(row['id'],set())-retained
            allowed = retained | additional
            usable_capacity = row['total_capacity']-row['unavailable_capacity']
            eligible = row['operational_status']=='open' and usable_capacity>0
            if eligible and not any(tenants.get(tenant,{}).get('is_active') for tenant in allowed):
                blockers.append(dict(code='tenant_permission_required', zone_id=row['id'], message='Explicitly select at least one active tenant for this open destination. No tenant access is granted automatically.'))
            total+=row['total_capacity']; unavailable+=row['unavailable_capacity']
            if eligible: usable+=usable_capacity
            zones.append(dict(draft_zone_id=row['id'], level_id=level['id'], code=row['code'], name=row['name'],
                action='update_bound' if binding else 'create_new', operational_zone_id=binding or row['id'],operational_code=operational_code,operational_name=operational_name,
                total_capacity=row['total_capacity'], unavailable_capacity=row['unavailable_capacity'], usable_capacity=usable_capacity,
                intended_status=row['operational_status'], entrance_draft_node_id=mappings.get(row['id'],{}).get('node_id'),
                retained_tenant_ids=sorted(retained), additional_tenant_ids=sorted(additional),
                validation=zone_results.get(row['id'])))
        level_changes.append(dict(id=level['id'],name=level['name'],total_capacity=total,unavailable_capacity=unavailable,
            usable_destination_capacity=usable, proposed_active=True))
    superseded = [row | {'permission_count':sum(p['zone_id']==row['id'] for p in permissions)} for row in operational.values() if row['id'] not in targets]
    active = sum(row['active_sessions'] for row in operational.values())
    if active:
        blockers.append(dict(code='active_sessions', message=f'{active} allocated or occupied sessions exist. A whole-facility graph cutover must not proceed while any active assignment depends on it.'))
    proposed_nodes = [node | {'level_id':level['id'],'draft_code':node['code'],'code':f"{node['code']} [VP:{node['id']}]"} for level in snapshot['levels'] for node in (level['draft'] or {}).get('nodes',[])]
    for node in proposed_nodes:
        owned=owned_nodes.get(node['id'])
        if node['id'] in existing_nodes and (not owned or owned['operational_node_id']!=node['id'] or owned['level_id']!=node['level_id']):
            blockers.append(dict(code='node_identity_collision',message='A draft node UUID belongs to an unrelated published node or level. Recreate that node with a new UUID.'))
        if any(other['code']==node['code'] and other['id']!=node['id'] for other in existing_nodes.values()):
            blockers.append(dict(code='node_code_collision',message='A namespaced publication node code is already owned by another record.'))
    proposed_edges = [edge | {'kind':'same_level','level_id':level['id']} for level in snapshot['levels'] for edge in (level['draft'] or {}).get('edges',[])]
    proposed_edges += [dict(id=edge['id'],from_node_id=edge['from_node_id'],to_node_id=edge['to_node_id'],distance_meters=edge['distance_meters'],kind='cross_level') for edge in snapshot['ramps']]
    # Staleness fingerprint, NOT an authorization token or proof of atomic commit.
    stable_context = context | {'draft':{key:value for key,value in snapshot.items() if key!='snapshot_at'}}
    fingerprint = digest(dict(context=stable_context,choices=change.model_dump(mode='json')))
    if validation['readiness']=='ready':
        routes=shortest_routes(proposed_nodes,[edge|{'is_active':True} for edge in proposed_edges],validation['building_entrance_id'])
        for result in validation['zones']:
            if result['allocation_candidate'] and (result['entrance_node_id'] not in routes or abs(float(routes[result['entrance_node_id']].distance_meters)-result['distance_meters'])>max(1e-8,result['distance_meters']*1e-9)):
                blockers.append(dict(code='route_mismatch',zone_id=result['zone_id'],message='Operational Dijkstra does not reproduce the validated draft route distance.'))
    can_publish=not blockers
    return dict(preview_version=1,readiness='ready' if can_publish else 'blocked',can_publish=can_publish,publication_status='published' if context['publication_state']['revision'] else 'not_published',
        current_revision=context['publication_state']['revision'],last_publication=context['last_publication'],
        fingerprint=fingerprint,snapshot_at=snapshot['snapshot_at'],validation=validation,blocking_reasons=blockers,
        levels=level_changes,zones=zones,superseded_zones=superseded,
        excluded_levels=[row | {'proposed_active':False} for row in context['levels'] if row['id'] not in selected],
        tenants=context['tenants'],active_sessions=active,
        operational_graph={key:context['graph'][key] for key in ('nodes','edges','active_edges','entrance_ids')},
        proposed_graph=dict(nodes=proposed_nodes,directed_edges=proposed_edges,building_entrance_draft_id=validation['building_entrance_id']),
        schema=dict(status='verified_contract',tables=[row['table'] for row in context['schema']],fingerprint=digest(context['schema'])),
        planned_cutover=['Retain all existing level records','Close superseded zones including unselected levels',
            'Deactivate prior active edges to eliminate dummy shortcuts','Preserve historical sessions and tenant references',
            'Grant only explicitly selected additional tenant permissions'],
        planned_changes_only=True)


def read_context(admin_id, change):
    data=execute_rpc('read_parking_publication_preview',{
        'p_admin_id':admin_id,'p_level_ids':[str(value) for value in change.level_ids]})
    if not isinstance(data,dict):
        raise database.DatabaseError('Invalid publication preview response.')
    if data.get('status')!='read':
        status,message={'forbidden':(403,'Approved administrator access is required.'),'missing':(404,'A selected level is missing.'),
            'invalid':(422,'Select distinct valid levels.'),'incomplete_scope':(422,'Include all ramp endpoint and reference levels.'),
            'limit':(413,'Publication preview scope exceeds its size limits.')}.get(data.get('status'),(503,'Publication preview is unavailable.'))
        raise HTTPException(status,dict(code=data.get('status'),message=message,required_level_ids=data.get('required_level_ids',[])))
    try:
        return data,preview_context(data,change)
    except (KeyError,TypeError,ValueError,OverflowError):
        raise database.DatabaseError('Publication preview could not be confirmed.') from None


def preview(admin_id,change):
    return read_context(admin_id,change)[1]


def publish(admin_id, change):
    if not change.confirm:
        raise HTTPException(422,'Explicit publication confirmation is required.')
    scope=PreviewInput(**change.model_dump(exclude={'expected_fingerprint','confirm'}))
    context,current=read_context(admin_id,scope)
    receipt=context['last_publication']
    if receipt and receipt['preview_fingerprint']==change.expected_fingerprint:
        if receipt['summary'].get('level_ids')!=[str(value) for value in scope.level_ids] or receipt['summary'].get('tenant_permissions')!=[row.model_dump(mode='json') for row in scope.tenant_permissions]:
            raise HTTPException(409,dict(code='stale_preview',message='The publication request differs from the recorded preview.'))
        return dict(status='already_published',publication_id=receipt['id'],revision=receipt['revision'],summary=receipt['summary'])
    if current['fingerprint']!=change.expected_fingerprint:
        raise HTTPException(409,dict(code='stale_preview',message='Drafts, operational records, permissions or schema changed. Refresh the publication preview.'))
    if not current['can_publish']:
        raise HTTPException(409,dict(code='publication_blocked',message='Resolve publication blockers before proceeding.',blocking_reasons=current['blocking_reasons']))
    # This proof is server-generated, never accepted from the browser. SQL locks
    # writers and compares the complete snapshot again before the first write.
    result=execute_rpc('publish_parking_configuration',{
        'p_admin_id':admin_id,'p_expected_context':context,'p_preview_fingerprint':current['fingerprint'],
        'p_tenant_permissions':[row.model_dump(mode='json') for row in scope.tenant_permissions],
        'p_zone_names':{row['draft_zone_id']:row['operational_name'] for row in current['zones']},
        'p_summary':dict(level_ids=[str(value) for value in scope.level_ids],tenant_permissions=[row.model_dump(mode='json') for row in scope.tenant_permissions],
                         levels=len(current['levels']),zones=len(current['zones']),nodes=len(current['proposed_graph']['nodes']),
                         directed_edges=len(current['proposed_graph']['directed_edges']),entrance_node_id=current['validation']['building_entrance_id']),
    })
    if not isinstance(result,dict) or result.get('status') not in ('published','already_published'):
        code=result.get('status') if isinstance(result,dict) else 'unconfirmed'
        status=409 if code in ('stale_preview','active_sessions','conflict','busy') else 403 if code=='forbidden' else 503
        raise HTTPException(status,dict(code=code,message='Publication was not confirmed. Refresh preview and review current state before retrying.'))
    try:
        valid_id=str(UUID(result['publication_id']))==result['publication_id']
    except (ValueError,KeyError,TypeError,AttributeError):
        valid_id=False
    if type(result.get('revision')) is not int or not 1<=result['revision']<=9007199254740990 or not valid_id or not isinstance(result.get('summary'),dict):
        raise database.DatabaseError('Publication result could not be confirmed.')
    return result
