"""Isolated draft nodes. Never access the operational navigation graph."""
from typing import Literal
from uuid import UUID
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from backend import database
from backend.parking.calibration import current_plan, read as read_calibration

MAX_BODY_BYTES = 512 * 1024


def needs_revalidation(draft, current_revision):
    return current_revision == 0 or bool(draft and (
        draft['calibration_revision'] != current_revision or
        ('distances_validated_revision' in draft and draft['distances_validated_revision'] != draft['revision'])))


class DraftNode(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    id: UUID
    code: str = Field(min_length=1, max_length=64, strict=True)
    node_type: Literal['building_entrance', 'junction', 'ramp', 'zone_entrance']
    x: float = Field(ge=0, strict=True)
    y: float = Field(ge=0, strict=True)

    @field_validator('code', mode='before')
    @classmethod
    def trim_code(cls, value):
        return value.strip() if isinstance(value, str) else value


class DraftInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    floor_plan_revision: int = Field(ge=1, le=2147483646, strict=True)
    expected_revision: int = Field(ge=0, le=2147483646, strict=True)
    nodes: list[DraftNode] = Field(max_length=1000)

    @model_validator(mode='after')
    def unique_nodes(self):
        if len({node.id for node in self.nodes}) != len(self.nodes):
            raise ValueError('Node IDs must be unique.')
        if len({node.code for node in self.nodes}) != len(self.nodes):
            raise ValueError('Node codes must be unique within this draft.')
        return self


def read(level_id, revision):
    current_plan(level_id, revision)
    rows = database._execute(database.get_supabase().table('parking_floor_plan_node_drafts')
                             .select('*').eq('level_id', level_id).eq('floor_plan_revision', revision)).data
    calibration = read_calibration(level_id, revision)['calibration']
    current_revision = calibration['revision'] if calibration else 0
    draft = rows[0] if rows else None
    return {'floor_plan_revision': revision, 'draft': draft,
            'current_calibration_revision': current_revision,
            'needs_distance_revalidation': needs_revalidation(draft, current_revision)}


def save(level_id, admin_id, data):
    plan = current_plan(level_id, data.floor_plan_revision)
    if any(node.x > plan['width_px'] or node.y > plan['height_px'] for node in data.nodes):
        raise HTTPException(422, 'Draft nodes must be inside the floor-plan image.')
    result = database._execute(database.get_supabase().rpc('save_floor_plan_node_draft', {
        'p_admin_id': admin_id, 'p_level_id': level_id,
        'p_floor_plan_revision': data.floor_plan_revision, 'p_expected_revision': data.expected_revision,
        'p_nodes': [node.model_dump(mode='json') for node in data.nodes],
    })).data
    if not isinstance(result, dict):
        raise database.DatabaseError('Invalid node draft response.')
    if result.get('status') != 'saved':
        status, message = {
            'missing': (404, 'Floor plan not found.'),
            'conflict': (409, 'Image or node draft changed. Reload before saving.'),
            'forbidden': (403, 'Administrator access is required.'),
            'invalid': (422, 'Invalid draft nodes. Check codes, types and image coordinates.'),
        }.get(result.get('status'), (503, 'Draft save could not be confirmed. Reload before retrying.'))
        raise HTTPException(status, message)
    return {'floor_plan_revision': data.floor_plan_revision, 'draft': result['draft'],
            'current_calibration_revision': result['current_calibration_revision'],
            'needs_distance_revalidation': needs_revalidation(result['draft'], result['current_calibration_revision'])}
