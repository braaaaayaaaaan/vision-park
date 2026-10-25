"""Administrator tenant management over the existing shared-zone relationships."""
from uuid import UUID

from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field, StrictBool, field_validator

from backend import database

MAX_BODY_BYTES = 128 * 1024


class TenantInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    id: UUID
    name: str = Field(min_length=1, max_length=120)
    is_active: StrictBool
    zone_ids: list[UUID] = Field(max_length=2000)
    expected_revision: str | None = Field(default=None, pattern=r'^[a-f0-9]{32}$')
    confirm_access_change: StrictBool = False

    @field_validator('name')
    @classmethod
    def readable_name(cls, value):
        value = ' '.join(value.split())
        if not value or any(ord(char) < 32 or ord(char) == 127 for char in value):
            raise ValueError('Enter a readable company name.')
        return value

    @field_validator('zone_ids')
    @classmethod
    def distinct_zones(cls, values):
        if len(values) != len(set(values)):
            raise ValueError('Select each zone once.')
        return values


ERRORS = {
    'forbidden': (403, 'Administrator access is required.'),
    'not_found': (404, 'Company not found. Refresh the list.'),
    'stale': (409, 'This company or its access changed. Close and reopen the details before saving.'),
    'duplicate_name': (409, 'A company with this name already exists, including inactive companies.'),
    'active_sessions': (409, 'Active parking sessions depend on this access. Wait for them to end before deactivating or removing access.'),
    'confirmation_required': (422, 'Confirm the effect on driver access before saving.'),
    'invalid': (422, 'Use a readable name, distinct existing zones and the current revision.'),
    'inactive': (422, 'Activate the company before granting additional parking access.'),
    'tenant_limit': (409, 'The 1,000-company publication limit has been reached. Existing companies can still be edited.'),
    'permission_limit': (409, 'The 20,000 zone-permission publication limit would be exceeded. Remove permissions before granting more access.'),
    'code_conflict': (409, 'The generated company code is already in use. Refresh and register the company again.'),
}


def result(payload, expected):
    if not isinstance(payload, dict):
        raise database.DatabaseError('Tenant management returned an invalid response.')
    status = payload.get('status')
    if status in ERRORS:
        code, message = ERRORS[status]
        raise HTTPException(code, detail={'code': status, 'message': message})
    if status != expected:
        raise database.DatabaseError('Tenant management returned an invalid status.')
    return {key: value for key, value in payload.items() if key != 'status'}


def read(admin_id, tenant_id=None, search='', status='all', sort='name_asc', limit=25, offset=0):
    return result(database.read_admin_tenants(admin_id, tenant_id, search.strip(), status, sort, limit, offset), 'read')


def save(admin_id, change, creating=False):
    if creating != (change.expected_revision is None):
        raise HTTPException(422, 'Use the current revision when editing a company.')
    return result(database.save_admin_tenant(admin_id, change.model_dump(mode='json')), 'saved')
