"""Atomic draft nodes and zone links; no operational graph or capacity writes."""
from typing import Literal
from uuid import UUID
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field, model_validator
from backend import database
from backend.parking import node_drafts, zone_drafts

MAX_BODY_BYTES = 768 * 1024


class ZoneChange(BaseModel):
    model_config = ConfigDict(extra='forbid')
    zone_id: UUID
    node_id: UUID | None
    expected_zone_revision: int = Field(ge=1, le=2147483646, strict=True)


class NodeZoneInput(node_drafts.DraftInput):
    zone_changes: list[ZoneChange] = Field(max_length=1000)

    @model_validator(mode='after')
    def unique_zones(self):
        if len({change.zone_id for change in self.zone_changes}) != len(self.zone_changes):
            raise ValueError('Each zone may be changed once per save.')
        return self


class EntranceRecord(BaseModel):
    model_config = ConfigDict(extra='forbid')
    zone_id: UUID
    node_id: UUID
    floor_plan_revision: int = Field(ge=1, le=2147483647, strict=True)
    state: Literal['linked', 'needs_review']
    review_reasons: list[Literal['image_replaced', 'node_missing', 'node_type_changed']]


def result(data, expected, level_id, image_revision):
    if not isinstance(data, dict):
        raise database.DatabaseError('Invalid node-zone response.')
    if data.get('status') != expected:
        code, message = {
            'forbidden': (403, 'Approved administrator access is required.'),
            'missing': (404, 'Floor plan or level not found.'),
            'missing_level': (404, 'Parking level not found.'),
            'missing_zone': (404, 'A selected draft zone no longer exists on this level.'),
            'conflict': (409, 'Image or node draft changed. Reload before saving.'),
            'stale_zone': (409, 'A draft zone or association changed. Reload before saving.'),
            'duplicate_assignment': (409, 'Each draft zone and entrance may have only one association.'),
            'invalid': (422, 'Use current Zone Entrance nodes, same-level draft zones and valid revisions.'),
        }.get(data.get('status'), (503, 'Node and zone-link save could not be confirmed. Reload before retrying.'))
        raise HTTPException(code, {'code': data.get('status'), 'message': message})
    try:
        if data['floor_plan_revision'] != image_revision or not isinstance(data['zone_entrances'], list):
            raise ValueError('Mismatched image response.')
        zones = zone_drafts.validate_listing(data['zone_configuration'], level_id)
        links = [EntranceRecord.model_validate(row) for row in data['zone_entrances']]
        zone_ids = {zone['id'] for zone in zones['zones']}
        if len({row.zone_id for row in links}) != len(links) or len({row.node_id for row in links}) != len(links) or any(
                str(row.zone_id) not in zone_ids for row in links):
            raise ValueError('Invalid zone link response.')
        draft = data['draft']
        if draft is not None and (draft['level_id'] != level_id or draft['floor_plan_revision'] != image_revision):
            raise ValueError('Mismatched node draft.')
        nodes = {node['id']: node for node in draft['nodes']} if draft else {}
        for row in links:
            node = nodes.get(str(row.node_id))
            reasons = ['image_replaced'] if row.floor_plan_revision != image_revision else (
                ['node_missing'] if node is None else ['node_type_changed'] if node['node_type'] != 'zone_entrance' else [])
            if row.review_reasons != reasons or row.state != ('needs_review' if reasons else 'linked'):
                raise ValueError('Incorrect zone-link review state.')
        return {key: data[key] for key in ('floor_plan_revision', 'draft', 'current_calibration_revision', 'needs_distance_revalidation')} | {
            'zone_configuration': zones, 'zone_entrances': [row.model_dump(mode='json') for row in links]}
    except (ValueError, KeyError, TypeError):
        raise database.DatabaseError('Node and zone-link result could not be confirmed.') from None


def read(admin_id, level_id, image_revision):
    data = database._execute(database.get_supabase().rpc('read_node_zone_draft', {
        'p_admin_id': admin_id, 'p_level_id': level_id, 'p_floor_plan_revision': image_revision,
    })).data
    return result(data, 'read', level_id, image_revision)


def save(admin_id, level_id, change):
    data = database._execute(database.get_supabase().rpc('save_node_zone_draft', {
        'p_admin_id': admin_id, 'p_level_id': level_id, 'p_floor_plan_revision': change.floor_plan_revision,
        'p_expected_revision': change.expected_revision, 'p_nodes': [node.model_dump(mode='json') for node in change.nodes],
        'p_zone_changes': [link.model_dump(mode='json') for link in change.zone_changes],
    })).data
    saved = result(data, 'saved', level_id, change.floor_plan_revision)
    draft = saved['draft']
    if not draft or draft['revision'] not in (change.expected_revision, change.expected_revision + 1) or draft['nodes'] != [node.model_dump(mode='json') for node in change.nodes]:
        raise database.DatabaseError('Node save could not be confirmed.')
    zones = {zone['id']: zone for zone in saved['zone_configuration']['zones']}
    links = {link['zone_id']: link for link in saved['zone_entrances']}
    for item in change.zone_changes:
        zone, link = zones.get(str(item.zone_id)), links.get(str(item.zone_id))
        if not zone or zone['revision'] != item.expected_zone_revision + 1 or (
                bool(link) if item.node_id is None else not link or link['node_id'] != str(item.node_id) or link['state'] != 'linked'):
            raise database.DatabaseError('Zone-link save could not be confirmed.')
    return saved
