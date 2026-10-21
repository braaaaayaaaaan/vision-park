"""Image-revision-specific calibration; never writes navigation graph data."""
import math
from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field
from backend import database
from backend.parking.floor_plans import metadata


class CalibrationInput(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    floor_plan_revision: int = Field(ge=1, le=2147483646, strict=True)
    expected_revision: int = Field(ge=0, le=2147483646, strict=True)
    start_x: float = Field(ge=0, strict=True)
    start_y: float = Field(ge=0, strict=True)
    end_x: float = Field(ge=0, strict=True)
    end_y: float = Field(ge=0, strict=True)
    known_distance_m: float = Field(gt=0, strict=True)


def calculate(measurement, width, height):
    if not (0 <= measurement.start_x <= width and 0 <= measurement.end_x <= width
            and 0 <= measurement.start_y <= height and 0 <= measurement.end_y <= height):
        raise HTTPException(422, 'Reference points must be inside the image.')
    distance = math.hypot(measurement.end_x - measurement.start_x, measurement.end_y - measurement.start_y)
    if not math.isfinite(distance) or distance <= 0:
        raise HTTPException(422, 'Choose two distinct reference points.')
    scale = measurement.known_distance_m / distance
    if not math.isfinite(scale) or scale <= 0:
        raise HTTPException(422, 'The reference measurement cannot produce a valid scale.')
    return scale


def current_plan(level_id, revision):
    plan = metadata(level_id)
    if not plan:
        raise HTTPException(404, 'Upload a floor plan before calibrating.')
    if plan['revision'] != revision:
        raise HTTPException(409, 'Floor plan changed. Refresh before calibrating.')
    return plan


def read(level_id, revision):
    current_plan(level_id, revision)
    rows = database._execute(database.get_supabase().table('parking_floor_plan_calibrations')
                             .select('*').eq('level_id', level_id).eq('floor_plan_revision', revision)).data
    # Detect replacement between the independent reads; old-revision rows never
    # masquerade as calibration for a new image.
    current_plan(level_id, revision)
    return {'floor_plan_revision': revision, 'calibration': rows[0] if rows else None}


def save(level_id, admin_id, measurement):
    plan = current_plan(level_id, measurement.floor_plan_revision)
    calculate(measurement, plan['width_px'], plan['height_px'])
    params = {'p_admin_id': admin_id, 'p_level_id': level_id}
    params.update({f'p_{key}': value for key, value in measurement.model_dump().items()})
    result = database._execute(database.get_supabase().rpc('save_floor_plan_calibration', params)).data
    if not isinstance(result, dict):
        raise database.DatabaseError('Invalid calibration response.')
    if result.get('status') != 'saved':
        status, message = {
            'conflict': (409, 'Image or calibration changed. Refresh before saving.'),
            'missing': (404, 'Floor plan not found.'),
            'forbidden': (403, 'Administrator access is required.'),
            'invalid': (422, 'Invalid reference points or physical distance.'),
        }.get(result.get('status'), (503, 'Calibration save could not be confirmed. Refresh before retrying.'))
        raise HTTPException(status, message)
    return {'floor_plan_revision': measurement.floor_plan_revision, 'calibration': result['calibration']}
