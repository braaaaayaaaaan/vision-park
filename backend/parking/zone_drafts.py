"""Level-scoped draft capacity only. No operational zone/session/graph writes."""
from typing import Literal
from uuid import UUID
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from backend import database

MAX_BODY_BYTES = 32 * 1024
MAX_INT = 2147483647


class ZoneInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    code: str = Field(min_length=1, max_length=64, strict=True)
    name: str = Field(min_length=1, max_length=100, strict=True)
    total_capacity: int = Field(ge=0, le=MAX_INT, strict=True)
    unavailable_capacity: int = Field(ge=0, le=MAX_INT, strict=True)
    operational_status: Literal['open', 'closed', 'maintenance']

    @field_validator('code', 'name', mode='before')
    @classmethod
    def readable(cls, value):
        if not isinstance(value, str) or any(ord(c) < 32 or 127 <= ord(c) <= 159 for c in value):
            raise ValueError('Use readable zone codes and names.')
        return value.strip()

    @model_validator(mode='after')
    def capacity_bounds(self):
        if self.unavailable_capacity > self.total_capacity:
            raise ValueError('Unavailable capacity cannot exceed total capacity.')
        return self


class ZonePatch(ZoneInput):
    expected_revision: int = Field(ge=1, le=MAX_INT - 1, strict=True)


class ZoneDelete(BaseModel):
    model_config = ConfigDict(extra='forbid')
    expected_revision: int = Field(ge=1, le=MAX_INT, strict=True)


class ZoneRecord(ZoneInput):
    id: UUID
    level_id: UUID
    revision: int = Field(ge=1, le=MAX_INT, strict=True)
    operational_zone_id: UUID | None
    created_at: str
    updated_at: str
    updated_by: UUID


def result(data, expected):
    if not isinstance(data, dict):
        raise database.DatabaseError('Invalid zone draft response.')
    if data.get('status') != expected:
        code, message = {
            'forbidden': (403, 'Approved administrator access is required.'),
            'missing_level': (404, 'Parking level not found. Refresh the level list.'),
            'missing_zone': (404, 'Draft zone not found. Refresh before retrying.'),
            'stale': (409, 'This draft zone changed. Refresh and review before retrying.'),
            'duplicate_code': (409, 'This zone code is already used on this level.'),
            'has_dependencies': (409, 'This draft zone has mapping or publication references and cannot be deleted.'),
            'limit': (409, 'The draft zone or revision limit was reached.'),
            'invalid': (422, 'Check zone codes, names, integer capacities and intended status.'),
        }.get(data.get('status'), (503, 'Draft zone result could not be confirmed. Refresh before retrying.'))
        raise HTTPException(code, {'code': data.get('status'), 'message': message})
    return data


def read(admin_id, level_id):
    data = result(database._execute(database.get_supabase().rpc('read_parking_zone_drafts', {
        'p_admin_id': admin_id, 'p_level_id': level_id,
    })).data, 'read')
    return validate_listing(data, level_id)


def validate_listing(data, level_id):
    try:
        if not isinstance(data['zones'], list):
            raise ValueError('Invalid zone list.')
        rows = [ZoneRecord.model_validate(row) for row in data['zones']]
        if data['level_id'] != level_id or len(rows) > 1000 or len({row.id for row in rows}) != len(rows) or len({row.code for row in rows}) != len(rows) or any(str(row.level_id) != level_id for row in rows):
            raise ValueError('Mismatched zone listing.')
        totals = {'total_count': len(rows), 'total_capacity': sum(row.total_capacity for row in rows),
                  'unavailable_capacity': sum(row.unavailable_capacity for row in rows)}
        if any(type(data.get(key)) is not int or data[key] != value for key, value in totals.items()):
            raise ValueError('Incomplete zone listing.')
        return {'level_id': level_id, 'zones': [row.model_dump(mode='json') for row in rows], **totals}
    except (ValueError, KeyError, TypeError):
        raise database.DatabaseError('Draft zone listing could not be confirmed.') from None


def mutate(admin_id, level_id, action, change, zone_id=None):
    values = None if action == 'delete' else change.model_dump(exclude={'expected_revision'})
    data = result(database._execute(database.get_supabase().rpc('mutate_parking_zone_draft', {
        'p_admin_id': admin_id, 'p_level_id': level_id, 'p_action': action, 'p_zone_id': zone_id,
        'p_expected_revision': 0 if action == 'create' else change.expected_revision, 'p_values': values,
    })).data, {'create': 'created', 'update': 'updated', 'delete': 'deleted'}[action])
    try:
        if action == 'delete':
            if data.get('deleted_zone_id') != zone_id or data.get('level_id') != level_id:
                raise ValueError('Mismatched deletion.')
            return {'level_id': level_id, 'deleted_zone_id': zone_id}
        row = ZoneRecord.model_validate(data['zone'])
        if str(row.level_id) != level_id or (zone_id and str(row.id) != zone_id) or row.revision != (1 if action == 'create' else change.expected_revision + 1) or any(getattr(row, key) != value for key, value in values.items()) or (action == 'create' and row.operational_zone_id is not None):
            raise ValueError('Mismatched saved zone.')
        return {'zone': row.model_dump(mode='json')}
    except (ValueError, KeyError, TypeError):
        raise database.DatabaseError('Draft zone result could not be confirmed.') from None
