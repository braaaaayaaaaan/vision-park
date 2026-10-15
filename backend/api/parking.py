"""Explicitly enabled, token-protected development allocation endpoint."""

import os
from secrets import compare_digest
from typing import Annotated, Literal
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Security
from fastapi.security import APIKeyHeader
from pydantic import BaseModel, ConfigDict, Field, field_validator

from backend.database import DatabaseError
from backend.parking.allocation import AllocationError, allocate_parking

router = APIRouter()
allocation_key = APIKeyHeader(name="X-Allocation-Token", auto_error=False)


def require_allocation_access(token: Annotated[str | None, Security(allocation_key)]):
    if os.getenv("PARKING_ALLOCATION_ENABLED", "").lower() != "true":
        raise HTTPException(404, "Development allocation endpoint is disabled.")
    expected = os.getenv("PARKING_ALLOCATION_TOKEN", "")
    if not expected:
        raise HTTPException(503, "Configure a separate PARKING_ALLOCATION_TOKEN on the backend.")
    if token is None or not compare_digest(token.encode(), expected.encode()):
        raise HTTPException(403, "Invalid allocation token.")


class AllocationRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    plate_number: str = Field(min_length=1, max_length=32, pattern=r"^[A-Z0-9]+$")
    entrance_node_id: UUID

    @field_validator("plate_number", mode="before")
    @classmethod
    def normalise_plate(cls, value):
        # Reject punctuation/internal spaces instead of silently changing identity.
        return value.strip().upper() if isinstance(value, str) else value


class AllocationResponse(BaseModel):
    plate_number: str
    zone_id: UUID
    zone_name: str
    level_id: UUID
    level_name: str
    level_number: int
    distance_meters: float = Field(ge=0, allow_inf_nan=False)
    route_node_ids: list[UUID] = Field(min_length=1)
    parking_session_id: UUID
    status: Literal["allocated"]


@router.post("/allocate", response_model=AllocationResponse, status_code=201,
             dependencies=[Depends(require_allocation_access)])
def allocate(request: AllocationRequest):
    """Creates a real session when enabled and the reservation RPC is installed."""
    try:
        return allocate_parking(request.plate_number, str(request.entrance_node_id))
    except AllocationError as error:
        raise HTTPException(error.status_code, {"code": error.code, "message": str(error)}) from None
    except DatabaseError as error:
        raise HTTPException(503, {"code": "database_unavailable", "message": str(error)}) from None
