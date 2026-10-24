"""Read-only draft graph validation. Never loads the operational routing graph."""
import heapq
import logging
import math
import re
import time
import traceback
from datetime import datetime
from uuid import UUID
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field, model_validator
from backend import database
from backend.parking import calibration, cross_level_drafts, node_drafts, zone_drafts
from backend.parking.edge_drafts import DraftEdge

MAX_BODY_BYTES = 8192
logger = logging.getLogger(__name__)


def log_failure(stage, error, started):
    # _execute deliberately sanitizes database exceptions. Keep a diagnostic
    # code/type/location on the server, never exception bodies, SQL or tokens.
    cause = error.__context__ or error
    code = str(getattr(cause, 'code', ''))
    code = code if re.fullmatch(r'(?:[A-Z0-9]{5}|PGRST[0-9]{3})', code) else 'none'
    frames = traceback.extract_tb(error.__traceback__)
    location = f'{frames[-1].name}:{frames[-1].lineno}' if frames else 'unknown'
    logger.error('Stage5C validation failed stage=%s error_type=%s database_code=%s location=%s elapsed_ms=%d',
                 stage, type(cause).__name__, code, location, (time.monotonic()-started)*1000)


class ValidationScope(BaseModel):
    model_config = ConfigDict(extra='forbid')
    level_ids: list[UUID] = Field(min_length=1, max_length=64)

    @model_validator(mode='after')
    def unique_levels(self):
        if len(set(self.level_ids)) != len(self.level_ids):
            raise ValueError('Select each level once.')
        return self


def positive(value):
    return type(value) in (int, float) and math.isfinite(value) and value > 0


def revision(value):
    return type(value) is int and 0 < value <= 2147483647


def routes_from(nodes, edges, source):
    """Directed Dijkstra with one predecessor per node; reconstruct zone paths only.

    Keeps large drafts from materialising paths for every intermediate junction.
    Uses only validated positive weights supplied by this module.
    """
    adjacency = {node_id: [] for node_id in nodes}
    for start, end, distance in edges:
        adjacency[start].append((end, distance))
    distances, previous, pending = {source: 0.0}, {}, [(0.0, source)]
    while pending:
        distance, current = heapq.heappop(pending)
        if distance != distances[current]:
            continue
        for end, weight in sorted(adjacency[current]):
            candidate = distance + weight
            if math.isfinite(candidate) and candidate < distances.get(end, math.inf):
                distances[end], previous[end] = candidate, current
                heapq.heappush(pending, (candidate, end))
    return distances, previous


def validate_snapshot(snapshot):
    """Pure validator: all current rows originate from one database snapshot."""
    levels = snapshot['levels']
    issues, contexts, all_nodes, duplicates, sources = [], {}, {}, set(), []
    same_edges, edge_count, mapped_count, zone_results = [], 0, 0, []

    def issue(code, message, level_id=None, zone_id=None, edge_id=None, severity='error'):
        try:
            edge_id = str(UUID(edge_id)) if edge_id else None
        except (ValueError, TypeError, AttributeError):
            edge_id = None
        issues.append(dict(code=code, severity=severity, level_id=level_id, zone_id=zone_id, edge_id=edge_id, message=message))

    for level in levels:
        level_id, plan, cal, draft = level['id'], level['floor_plan'], level['calibration'], level['draft']
        ctx = contexts[level_id] = dict(level=level, plan=plan, cal=cal, draft=draft, nodes={}, scale=None, current=False)
        valid_plan = bool(plan and revision(plan.get('revision')) and all(type(plan.get(k)) is int and plan[k] > 0 for k in ('width_px', 'height_px')))
        if not valid_plan:
            issue('floor_plan', 'Upload a current floor plan with valid original image dimensions.', level_id)
        try:
            if not valid_plan or not cal or cal['level_id'] != level_id or cal['floor_plan_revision'] != plan['revision'] or not revision(cal['revision']):
                raise ValueError()
            measured = calibration.CalibrationInput(**{key: cal[key] for key in ('floor_plan_revision', 'start_x', 'start_y', 'end_x', 'end_y', 'known_distance_m')}, expected_revision=0)
            scale = calibration.calculate(measured, plan['width_px'], plan['height_px'])
            if not positive(cal['metres_per_pixel']) or not math.isclose(scale, cal['metres_per_pixel'], rel_tol=1e-9, abs_tol=1e-12):
                raise ValueError()
            ctx['scale'] = cal['metres_per_pixel']
        except (KeyError, TypeError, ValueError, OverflowError, HTTPException):
            issue('calibration', 'Save a valid calibration for the current floor-plan image. Check its reference points and distance.', level_id)
        if not draft:
            issue('node_draft', 'Save draft navigation nodes for the current image.', level_id)
            continue
        ctx['current'] = bool(valid_plan and draft.get('level_id') == level_id and draft.get('floor_plan_revision') == plan['revision'] and revision(draft.get('revision')))
        if not ctx['current']:
            issue('draft_revision', 'Reload and save navigation data against the current level and image revision.', level_id)
        codes = set()
        for raw in draft['nodes']:
            try:
                node = node_drafts.DraftNode.model_validate(raw).model_dump(mode='json')
                if node['code'] != raw['code'] or node['code'] in codes or not valid_plan or node['x'] > plan['width_px'] or node['y'] > plan['height_px']:
                    raise ValueError()
                codes.add(node['code'])
            except (KeyError, TypeError, ValueError, OverflowError):
                issue('node_invalid', 'Correct node codes, types and finite coordinates inside this image; codes must be unique within the level.', level_id)
                continue
            if node['id'] in all_nodes:
                duplicates.add(node['id'])
                issue('node_duplicate', f"Node {node['code']} reuses an ID elsewhere in the selected graph. Recreate it with a unique ID.", level_id)
            all_nodes[node['id']] = node | {'level_id': level_id}
            ctx['nodes'][node['id']] = node
            if node['node_type'] == 'building_entrance':
                sources.append(node['id'])
        edge_count += len(draft['edges'])
        validated = bool(ctx['current'] and ctx['scale'] and draft.get('calibration_revision') == (cal or {}).get('revision') and draft.get('distances_validated_revision') == draft['revision'])
        if draft['edges'] and not validated:
            issue('same_level_stale', 'Open Add Edges and revalidate/save distances against the current draft and calibration.', level_id)
        pairs, ids = set(), set()
        for edge in draft['edges']:
            try:
                identity = DraftEdge(**{key: edge[key] for key in ('id', 'from_node_id', 'to_node_id')}).model_dump(mode='json')
                start, end = identity['from_node_id'], identity['to_node_id']
                a, b = ctx['nodes'].get(start), ctx['nodes'].get(end)
                pair = (start, end)
                if not a or not b or start == end or pair in pairs or identity['id'] in ids or not positive(edge['distance_meters']):
                    raise ValueError()
                pairs.add(pair); ids.add(identity['id'])
                expected = math.hypot(b['x'] - a['x'], b['y'] - a['y']) * (ctx['scale'] or 0)
                if not validated or edge.get('calibration_revision') != (cal or {}).get('revision') or not positive(expected) or not math.isclose(expected, edge['distance_meters'], rel_tol=1e-9, abs_tol=1e-12):
                    raise ValueError()
                same_edges.append((start, end, edge['distance_meters']))
            except (KeyError, TypeError, ValueError, OverflowError):
                issue('same_level_edge', 'Correct dangling/duplicate directed edges and revalidate positive calibrated distances in Add Edges.', level_id, edge_id=edge.get('id') if isinstance(edge, dict) else None)

    for node_id in duplicates:
        all_nodes.pop(node_id, None)
    source = sources[0] if len(sources) == 1 and sources[0] in all_nodes else None
    if not source:
        issue('building_entrance', 'Configure exactly one valid Building Entrance across the selected levels.')
    graph_edges = [edge for edge in same_edges if edge[0] in all_nodes and edge[1] in all_nodes]
    pairs, ramp_ids = set(), set()
    for edge in snapshot['ramps']:
        edge_count += 1
        try:
            start_ctx, end_ctx, ref = [contexts[edge[key]] for key in ('from_level_id', 'to_level_id', 'reference_level_id')]
            start, end = edge['from_node_id'], edge['to_node_id']
            if start_ctx is end_ctx or start == end or edge['id'] in ramp_ids or (start, end) in pairs or edge.get('deleted_at') is not None or not positive(edge['distance_meters']):
                raise ValueError()
            ramp_ids.add(edge['id']); pairs.add((start, end))
            state = dict(edge)
            for side, ctx in [('from', start_ctx), ('to', end_ctx)]:
                state[f'current_{side}'] = dict(floor_plan_revision=(ctx['plan'] or {}).get('revision'), draft_revision=(ctx['draft'] or {}).get('revision'), node=ctx['nodes'].get(edge[f'{side}_node_id']))
            state['current_reference'] = dict(floor_plan_revision=(ref['plan'] or {}).get('revision'), calibration_revision=(ref['cal'] or {}).get('revision') if ref['scale'] else None,
                metres_per_pixel=ref['scale'], width_px=(ref['plan'] or {}).get('width_px'), height_px=(ref['plan'] or {}).get('height_px'))
            reasons = cross_level_drafts.review_reasons(state)
            state.update(requires_review=bool(reasons), review_reasons=reasons)
            cross_level_drafts.validate_state(state)
            if reasons or edge.get('requires_review') or not start_ctx['current'] or not end_ctx['current'] or start not in all_nodes or end not in all_nodes:
                raise ValueError()
            # One directed ramp is one graph weight; trace points are measurement
            # geometry, not extra edges. Reverse lanes must exist independently.
            graph_edges.append((start, end, edge['distance_meters']))
        except (KeyError, TypeError, ValueError, OverflowError):
            issue('ramp_review', 'Review/reconfirm this ramp: endpoints, image/draft revisions and its calibrated trace must all be current. No reverse direction is assumed.', edge.get('from_level_id'), edge_id=edge.get('id'))

    used_zones, used_entrances = set(), set()
    for level in levels:
        level_id, ctx = level['id'], contexts[level['id']]
        zones = {}
        for raw in level['zones']:
            try:
                row = zone_drafts.ZoneRecord.model_validate(raw).model_dump(mode='json')
                if row['level_id'] != level_id or row['id'] in used_zones or row['code'] in {z['code'] for z in zones.values()}:
                    raise ValueError()
                zones[row['id']] = row; used_zones.add(row['id'])
            except (TypeError, ValueError):
                issue('zone_invalid', 'Correct unique same-level zone codes/names, nonnegative integer capacities and intended status in Parking Zones.', level_id, raw.get('id'))
        mapped, invalid_zones = {}, set()
        for link in level['mappings']:
            zone_id, node_id = link.get('zone_id'), link.get('node_id')
            node = ctx['nodes'].get(node_id)
            if zone_id not in zones or zone_id in mapped or node_id in used_entrances or link.get('level_id') != level_id or not ctx['current'] or link.get('floor_plan_revision') != (ctx['plan'] or {}).get('revision') or node_id not in all_nodes or not node or node['node_type'] != 'zone_entrance':
                issue('mapping_invalid', 'Unlink or reassign this zone to one current Zone Entrance on the same level, then Save Draft.', level_id, zone_id)
                invalid_zones.add(zone_id)
            used_entrances.add(node_id); mapped[zone_id] = node_id
        mapped_count += len([zone_id for zone_id in mapped if zone_id in zones and zone_id not in invalid_zones])
        for zone_id, row in zones.items():
            usable = row['total_capacity'] - row['unavailable_capacity']
            eligible = row['operational_status'] == 'open' and usable > 0
            node_id = mapped.get(zone_id)
            state = 'needs_review' if zone_id in invalid_zones else 'linked' if node_id else 'unlinked'
            if not node_id:
                issue('mapping_missing', 'Select this zone on a Zone Entrance in Add Nodes and Save Draft.', level_id, zone_id, severity='error' if eligible else 'warning')
            if not eligible:
                issue('zone_excluded', 'Closed, maintenance or zero-usable-capacity zones are excluded from allocation destinations.', level_id, zone_id, severity='warning')
            zone_results.append(dict(zone_id=zone_id, level_id=level_id, code=row['code'], name=row['name'], revision=row['revision'],
                total_capacity=row['total_capacity'], unavailable_capacity=row['unavailable_capacity'], usable_capacity=usable,
                intended_status=row['operational_status'], allocation_candidate=eligible, entrance_node_id=node_id, mapping_state=state,
                reachability='not_applicable' if not eligible else 'not_checked', distance_meters=None, node_ids=None,
                message='Excluded from allocation' if not eligible else 'Correct the entrance mapping and building entrance before routing.'))

    if not used_zones:
        issue('zones_missing', 'Configure at least one valid draft parking zone in the selected levels.')
    if not any(zone['allocation_candidate'] for zone in zone_results):
        issue('no_allocation_destinations', 'No open zone with positive usable capacity is configured; structural readiness does not make parking available.', severity='warning')
    distances, previous = routes_from(all_nodes, graph_edges, source) if source else ({}, {})
    path_budget = 100000
    for zone in zone_results:
        if not zone['allocation_candidate'] or zone['mapping_state'] != 'linked' or not source:
            continue
        destination = zone['entrance_node_id']
        if destination not in distances:
            zone.update(reachability='unreachable', message='No directed route using current validated edges. Connect driving lanes and ramps or resolve reported edge issues.')
            issue('zone_unreachable', zone['message'], zone['level_id'], zone['zone_id'])
            continue
        path = [destination]
        while path[-1] != source:
            path.append(previous[path[-1]])
        path.reverse()
        zone.update(reachability='reachable', distance_meters=distances[destination], node_ids=path if len(path) <= path_budget else None,
            message='Reachable using current validated directed edges.' if len(path) <= path_budget else 'Reachable; route node list omitted because the report size limit was reached.')
        path_budget -= min(path_budget, len(path))
    ready = not any(item['severity'] == 'error' for item in issues)
    return dict(report_version=1, snapshot_at=snapshot['snapshot_at'], readiness='ready' if ready else 'needs_attention',
        allocation_ready=ready and any(zone['allocation_candidate'] for zone in zone_results), building_entrance_id=source,
        summary=dict(levels=len(levels), nodes=sum(len((level['draft'] or {}).get('nodes', [])) for level in levels), directed_edges=edge_count,
                     routable_edges=len(graph_edges), mapped_zones=mapped_count, zones=len(zone_results), errors=sum(i['severity']=='error' for i in issues), warnings=sum(i['severity']=='warning' for i in issues)),
        levels=[dict(id=level['id'], name=level['name'], level_number=level['level_number'], metadata_revision=level['metadata_revision'],
            floor_plan_revision=(level['floor_plan'] or {}).get('revision'), calibration_revision=(level['calibration'] or {}).get('revision'),
            draft_revision=(level['draft'] or {}).get('revision'), distances_validated_revision=(level['draft'] or {}).get('distances_validated_revision'),
            zone_revisions=[dict(id=z['id'], revision=z['revision']) for z in level['zones']],
            mappings=[{key: m.get(key) for key in ('zone_id', 'node_id', 'floor_plan_revision', 'updated_at')} for m in level['mappings']]) for level in levels],
        ramp_revisions=[dict(id=edge['id'], revision=edge['revision']) for edge in snapshot['ramps']], zones=zone_results, issues=issues,
        checked=['Current Images And Calibration Geometry', 'Unique Nodes And One Building Entrance', 'Directed Same-Level Distances And Revalidation',
                 'Current Directed Ramp Endpoints And Traced Measurements', 'Zone Capacities, Statuses And One-To-One Mappings', 'Directed Dijkstra Reachability For Allocation Candidates'],
        notice='Draft validation only. Revalidate after any edit. No publication, activation or operational availability check was performed.')


def validate(admin_id, scope):
    ids = [str(value) for value in scope.level_ids]
    started = time.monotonic()
    try:
        data = database._execute(database.get_supabase().rpc('read_draft_structure_snapshot', {'p_admin_id': admin_id, 'p_level_ids': ids})).data
    except Exception as error:
        log_failure('snapshot_rpc', error, started)
        raise
    if not isinstance(data, dict):
        error = database.DatabaseError('Invalid validation snapshot.')
        log_failure('snapshot_contract', error, started)
        raise error
    if data.get('status') != 'read':
        status, message = {'forbidden': (403, 'Approved administrator access is required.'), 'invalid': (422, 'Select 1–64 distinct parking level IDs.'),
            'missing': (404, 'A selected level no longer exists. Refresh parking levels.'),
            'incomplete_scope': (422, 'Include all connected ramp endpoint and measurement-reference levels before validating.'),
            'limit': (413, 'Validation scope exceeds 5,000 nodes, 10,000 same-level edges, 5,000 ramps or 1,000 zones.')}.get(data.get('status'), (503, 'Validation snapshot is unavailable.'))
        if status == 503:
            log_failure('snapshot_contract', database.DatabaseError('Unexpected snapshot status.'), started)
        raise HTTPException(status, dict(code=data.get('status'), message=message, required_level_ids=data.get('required_level_ids', [])))
    try:
        if len(data['levels']) != len(ids) or {level['id'] for level in data['levels']} != set(ids) or not isinstance(data['ramps'], list):
            raise ValueError('Incomplete snapshot.')
        datetime.fromisoformat(data['snapshot_at'].replace('Z', '+00:00'))
        return validate_snapshot(data)
    except (KeyError, TypeError, ValueError, OverflowError) as error:
        log_failure('snapshot_validation', error, started)
        raise database.DatabaseError('Validation report could not be confirmed.') from None
