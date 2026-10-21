"""Administrator-only level metadata and unused-level deletion; no activity changes."""
from datetime import datetime
import re
from uuid import UUID
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator
from backend import database

MAX_BODY_BYTES = 32 * 1024
MIN_NUMBER, MAX_NUMBER = -2147483648, 2147483647
TIMESTAMP = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$')


class LevelInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    level_number: int = Field(ge=MIN_NUMBER, le=MAX_NUMBER, strict=True)
    name: str = Field(min_length=1, max_length=100, strict=True)

    @field_validator('name', mode='before')
    @classmethod
    def trimmed_name(cls, value):
        if not isinstance(value, str) or any(ord(c) < 32 or 127 <= ord(c) <= 159 for c in value):
            raise ValueError('Use a readable level name without control characters.')
        return value.strip()


class LevelSnapshot(BaseModel):
    model_config = ConfigDict(extra='forbid')
    level_number: int = Field(ge=MIN_NUMBER, le=MAX_NUMBER, strict=True)
    name: str = Field(min_length=1, strict=True)
    is_active: bool = Field(strict=True)
    updated_at: str = Field(strict=True)
    metadata_revision: int = Field(ge=1, le=MAX_NUMBER, strict=True)

    @field_validator('updated_at')
    @classmethod
    def exact_timestamp(cls, value):
        if not TIMESTAMP.fullmatch(value):
            raise ValueError('Use the exact timestamp returned by the server.')
        datetime.fromisoformat(value.replace('Z', '+00:00'))
        return value  # Never round through milliseconds or a floating-point epoch.


class LevelPatch(LevelInput):
    expected: LevelSnapshot


class LevelBulk(BaseModel):
    model_config = ConfigDict(extra='forbid')
    levels: list[LevelInput] = Field(min_length=1, max_length=50)


class LevelDelete(BaseModel):
    model_config = ConfigDict(extra='forbid')
    expected_metadata_revision: int = Field(ge=1, le=MAX_NUMBER, strict=True)


class LevelRecord(LevelSnapshot):
    id: UUID


def rpc_result(value, status):
    if not isinstance(value, dict):
        raise database.DatabaseError('Invalid level response.')
    if value.get('status') != status:
        code, message = {
            'forbidden': (403, 'Approved administrator access is required.'),
            'duplicate_number': (409, 'A level number is already in use. Refresh and choose unique numbers; nothing was saved.'),
            'stale': (409, 'This level has already been changed. Please refresh and review before trying again.'),
            'missing': (404, 'Parking level not found. Refresh the level list.'),
            'active': (409, 'Active levels cannot be deleted. No changes were made.'),
            'has_dependencies': (409, 'This level has zones, navigation or other associated records and cannot be deleted. No changes were made.'),
            'invalid': (422, 'Use unique integer level numbers and nonempty names of at most 100 characters.'),
        }.get(value.get('status'), (503, 'Level save could not be confirmed. Refresh before retrying.'))
        raise HTTPException(code, {'code': value.get('status'), 'message': message})
    return value


def create(admin_id, inputs):
    if len({item.level_number for item in inputs}) != len(inputs):
        raise HTTPException(409, 'Use unique level numbers within the batch; nothing was saved.')
    data = rpc_result(database._execute(database.get_supabase().rpc('create_parking_levels', {
        'p_admin_id': admin_id, 'p_levels': [item.model_dump() for item in inputs],
    })).data, 'created')
    try:
        records = [LevelRecord.model_validate(item) for item in data['levels']]
        desired = {item.level_number: item.name for item in inputs}
        if len(records) != len(inputs) or len({item.id for item in records}) != len(records) or {
            item.level_number: item.name for item in records} != desired or any(item.is_active or item.metadata_revision != 1 for item in records):
            raise ValueError('Incomplete or unexpected created levels.')
        return {'levels': [item.model_dump(mode='json') for item in records]}
    except (ValueError, KeyError, TypeError):
        raise database.DatabaseError('Level creation could not be confirmed.') from None


def update(admin_id, level_id, change):
    data = rpc_result(database._execute(database.get_supabase().rpc('update_parking_level_metadata', {
        'p_admin_id': admin_id, 'p_level_id': level_id, 'p_level_number': change.level_number,
        'p_name': change.name, 'p_expected': change.expected.model_dump(),
    })).data, 'updated')
    try:
        record = LevelRecord.model_validate(data['level'])
        changed = record.name != change.expected.name or record.level_number != change.expected.level_number
        if str(record.id) != level_id or record.name != change.name or record.level_number != change.level_number or record.is_active != change.expected.is_active or (
            record.metadata_revision != change.expected.metadata_revision + int(changed)):
            raise ValueError('Unexpected saved level.')
        return {'level': record.model_dump(mode='json')}
    except (ValueError, KeyError, TypeError):
        raise database.DatabaseError('Level edit could not be confirmed.') from None


def delete(admin_id, level_id, change):
    data = rpc_result(database._execute(database.get_supabase().rpc('delete_unused_parking_level', {
        'p_admin_id': admin_id, 'p_level_id': level_id,
        'p_expected_metadata_revision': change.expected_metadata_revision,
    })).data, 'deleted')
    if data.get('deleted_level_id') != level_id:
        raise database.DatabaseError('Level deletion could not be confirmed.')
    return {'deleted_level_id': level_id}
