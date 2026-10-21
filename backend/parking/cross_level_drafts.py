"""Calibrated horizontal ramp traces. No operational graph access."""
from uuid import UUID
import math
from pydantic import BaseModel, ConfigDict, Field, model_validator
from fastapi import HTTPException
from backend import database

MAX_BODY_BYTES = 32 * 1024
MAX_REVISION = 2147483646


class TracePoint(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    x: float = Field(ge=0, strict=True)
    y: float = Field(ge=0, strict=True)


def trace_distance(points, scale, width, height):
    """Validate original-image geometry; SQL repeats this under revision locks."""
    if not 2 <= len(points) <= 200 or not all(math.isfinite(v) and v > 0 for v in (scale, width, height)):
        raise ValueError('Use a calibrated image and 2–200 distinct trace points.')
    coords = [(point['x'], point['y']) for point in points]
    if any(type(v) not in (int, float) or not math.isfinite(v) for pair in coords for v in pair):
        raise ValueError('Trace coordinates must be finite numbers.')
    if len(set(coords)) != len(coords) or any(not (0 <= x <= width and 0 <= y <= height) for x, y in coords):
        raise ValueError('Use distinct trace points within the reference image.')
    distance = scale * sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(coords, coords[1:]))
    if not math.isfinite(distance) or distance <= 0:
        raise ValueError('Trace length must be positive and finite.')
    return distance


class EdgeChange(BaseModel):
    model_config = ConfigDict(extra='forbid', allow_inf_nan=False)
    id: UUID
    expected_revision: int = Field(ge=0, le=MAX_REVISION, strict=True)
    from_level_id: UUID
    from_floor_plan_revision: int = Field(ge=1, le=MAX_REVISION, strict=True)
    from_draft_revision: int = Field(ge=1, le=MAX_REVISION, strict=True)
    from_node_id: UUID
    to_level_id: UUID
    to_floor_plan_revision: int = Field(ge=1, le=MAX_REVISION, strict=True)
    to_draft_revision: int = Field(ge=1, le=MAX_REVISION, strict=True)
    to_node_id: UUID
    reference_level_id: UUID
    reference_floor_plan_revision: int = Field(ge=1, le=MAX_REVISION, strict=True)
    reference_calibration_revision: int = Field(ge=1, le=MAX_REVISION, strict=True)
    trace_points: list[TracePoint] = Field(min_length=2, max_length=200)

    @model_validator(mode='after')
    def distinct_endpoints(self):
        if self.from_level_id == self.to_level_id or self.from_node_id == self.to_node_id:
            raise ValueError('Choose distinct ramp nodes on different levels.')
        if len({(point.x, point.y) for point in self.trace_points}) != len(self.trace_points):
            raise ValueError('Trace points must be distinct.')
        return self


class EdgeDelete(BaseModel):
    model_config = ConfigDict(extra='forbid')
    id: UUID
    expected_revision: int = Field(ge=1, le=MAX_REVISION, strict=True)


class RampBatch(BaseModel):
    model_config = ConfigDict(extra='forbid')
    upserts: list[EdgeChange] = Field(max_length=2)
    deletes: list[EdgeDelete] = Field(max_length=2)
    confirm_measurement: bool = Field(strict=True)

    @model_validator(mode='after')
    def valid_batch(self):
        changes = self.upserts + self.deletes
        if not changes or len({edge.id for edge in changes}) != len(changes):
            raise ValueError('Use a nonempty batch with unique edge IDs.')
        pairs = {(edge.from_level_id, edge.from_floor_plan_revision, edge.from_node_id,
                  edge.to_level_id, edge.to_floor_plan_revision, edge.to_node_id) for edge in self.upserts}
        if len(pairs) != len(self.upserts):
            raise ValueError('Directed connections must be unique.')
        if self.upserts and not self.confirm_measurement:
            raise ValueError('Confirm the current endpoints and traced ramp paths.')
        return self


def review_reasons(edge):
    reasons = []
    for side, label in [('from', 'source'), ('to', 'destination')]:
        current = edge[f'current_{side}']
        if current['floor_plan_revision'] != edge[f'{side}_floor_plan_revision']:
            reasons.append(f'{label}_image_replaced')
        if current['draft_revision'] != edge[f'{side}_draft_revision']:
            reasons.append(f'{label}_draft_changed')
        if current['node'] is None:
            reasons.append(f'{label}_node_missing')
        elif current['node']['node_type'] != 'ramp':
            reasons.append(f'{label}_not_ramp')
        return_node = current['node']
        if return_node and UUID(return_node['id']) != UUID(edge[f'{side}_node_id']):
            raise ValueError('Mismatched endpoint state.')
    reference = edge['current_reference']
    if reference['floor_plan_revision'] != edge['reference_floor_plan_revision']:
        reasons.append('reference_image_replaced')
    if reference['calibration_revision'] is None:
        reasons.append('reference_calibration_missing')
    elif reference['calibration_revision'] != edge['reference_calibration_revision']:
        reasons.append('reference_calibration_changed')
    return reasons


def validate_state(edge):
    reasons = review_reasons(edge)
    if edge['requires_review'] is not bool(reasons) or edge['review_reasons'] != reasons:
        raise ValueError('Invalid review state.')
    if edge['distance_source'] != 'traced_horizontal' or not math.isfinite(edge['distance_meters']) or edge['distance_meters'] <= 0:
        raise ValueError('Invalid traced distance.')
    # Historical geometry uses the saved image dimensions and scale. Current
    # calibration is deliberately separate so stale measurements remain visible.
    distance = trace_distance(edge['trace_points'], edge['reference_metres_per_pixel'], edge['reference_width_px'], edge['reference_height_px'])
    if not math.isclose(distance, edge['distance_meters'], rel_tol=1e-10):
        raise ValueError('Invalid trace measurement.')
    current = edge['current_reference']
    if not reasons and (current['metres_per_pixel'] != edge['reference_metres_per_pixel'] or
                        current['width_px'] != edge['reference_width_px'] or current['height_px'] != edge['reference_height_px']):
        raise ValueError('Mismatched reference snapshot.')
    if edge.get('reverse_edge') is not None:
        validate_state(edge['reverse_edge'])


def result(value, status):
    if not isinstance(value, dict):
        raise database.DatabaseError('Invalid cross-level draft response.')
    if value.get('status') != status:
        code, message = {
            'forbidden': (403, 'Approved administrator access is required.'),
            'conflict': (409, 'Ramp connections, endpoint drafts or reference calibration changed. Refresh and review before saving.'),
            'invalid': (422, 'Use current ramp nodes, a calibrated reference image and distinct in-bounds trace points. Confirm both paths before saving.'),
        }.get(value.get('status'), (503, 'Ramp save could not be confirmed. Refresh before retrying.'))
        raise HTTPException(code, message)
    keys = ('edges', 'total', 'limit', 'offset') if status == 'read' else ('edges', 'deleted_ids')
    try:
        for edge in value['edges']:
            validate_state(edge)
        return {key: value[key] for key in keys}
    except (KeyError, TypeError, ValueError, OverflowError):
        raise database.DatabaseError('Invalid cross-level draft response.') from None


def read(admin_id, level_id=None, limit=10, offset=0):
    return result(database._execute(database.get_supabase().rpc('read_cross_level_draft_edges', {
        'p_admin_id': admin_id, 'p_level_id': level_id, 'p_limit': limit, 'p_offset': offset,
    })).data, 'read')


def save(admin_id, batch):
    saved = result(database._execute(database.get_supabase().rpc('save_cross_level_draft_edges', {
        'p_admin_id': admin_id, 'p_upserts': [edge.model_dump(mode='json') for edge in batch.upserts],
        'p_deletes': [edge.model_dump(mode='json') for edge in batch.deletes],
        'p_confirm_measurement': batch.confirm_measurement,
    })).data, 'saved')
    expected = {str(edge.id): edge for edge in batch.upserts}
    try:
        if len(saved['edges']) != len(expected) or {edge['id'] for edge in saved['edges']} != set(expected) or set(saved['deleted_ids']) != {str(edge.id) for edge in batch.deletes}:
            raise ValueError('Incomplete batch response.')
        for edge in saved['edges']:
            supplied = expected[edge['id']].model_dump(mode='json')
            if edge['requires_review'] or edge['revision'] != supplied['expected_revision'] + 1 or any(edge[key] != value for key, value in supplied.items() if key != 'expected_revision'):
                raise ValueError('Mismatched batch response.')
    except (KeyError, TypeError, ValueError):
        raise database.DatabaseError('Ramp save could not be confirmed.') from None
    return saved
