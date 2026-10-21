"""Same-level draft connections only; SQL calculates and acknowledges all weights atomically."""
import math
from uuid import UUID
from pydantic import BaseModel, ConfigDict, Field, model_validator
from fastapi import HTTPException
from backend import database

MAX_BODY_BYTES = 512 * 1024
MAX_EDGES = 2000


class DraftEdge(BaseModel):
    model_config = ConfigDict(extra='forbid')
    id: UUID
    from_node_id: UUID
    to_node_id: UUID


class EdgeInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    floor_plan_revision: int = Field(ge=1, le=2147483646, strict=True)
    expected_revision: int = Field(ge=1, le=2147483646, strict=True)
    expected_calibration_revision: int = Field(ge=1, le=2147483646, strict=True)
    edges: list[DraftEdge] = Field(max_length=MAX_EDGES)

    @model_validator(mode='after')
    def valid_connections(self):
        if any(edge.from_node_id == edge.to_node_id for edge in self.edges):
            raise ValueError('Self-loops are not allowed.')
        if len({edge.id for edge in self.edges}) != len(self.edges):
            raise ValueError('Edge IDs must be unique.')
        if len({(edge.from_node_id, edge.to_node_id) for edge in self.edges}) != len(self.edges):
            raise ValueError('Directed connections must be unique.')
        return self


def calculate_edges(edges, nodes, scale, calibration_revision):
    """Validate a database snapshot for responses/tests; the SQL RPC is the write authority."""
    if not math.isfinite(scale) or scale <= 0:
        raise ValueError('A positive finite calibration scale is required.')
    by_id = {str(UUID(node['id'])): node for node in nodes}
    calculated = []
    for edge in edges:
        start, end = by_id.get(str(edge.from_node_id)), by_id.get(str(edge.to_node_id))
        if start is None or end is None or edge.from_node_id == edge.to_node_id:
            raise ValueError('Connection must reference two existing nodes in this draft.')
        distance = math.hypot(end['x'] - start['x'], end['y'] - start['y']) * scale
        if not math.isfinite(distance) or distance <= 0:
            raise ValueError('Connection must have a positive finite distance.')
        calculated.append(edge.model_dump(mode='json') | {'distance_meters': distance, 'calibration_revision': calibration_revision})
    return calculated


def _result(result, expected_status):
    if not isinstance(result, dict):
        raise database.DatabaseError('Invalid graph draft response.')
    if result.get('status') != expected_status:
        status, message = {
            'missing': (404, 'Floor plan not found.'),
            'nodes_required': (422, 'Save draft nodes before connecting them.'),
            'calibration_required': (422, 'Calibrate this floor plan before saving connections.'),
            'conflict': (409, 'Image, nodes, edges or calibration changed. Reload before saving.'),
            'forbidden': (403, 'Administrator access is required.'),
            'invalid': (422, 'Use unique connections between distinct saved nodes with positive calibrated distances.'),
        }.get(result.get('status'), (503, 'Connection save could not be confirmed. Reload before retrying.'))
        raise HTTPException(status, message)
    try:
        response = {key: result[key] for key in ('floor_plan_revision', 'draft', 'calibration', 'current_calibration_revision', 'needs_distance_revalidation')}
        draft, calibration = response['draft'], response['calibration']
        if draft and not response['needs_distance_revalidation']:
            inputs = [DraftEdge(**{key: edge[key] for key in ('id', 'from_node_id', 'to_node_id')}) for edge in draft['edges']]
            calculated = calculate_edges(inputs, draft['nodes'], calibration['metres_per_pixel'], calibration['revision'])
            if any(edge['calibration_revision'] != expected['calibration_revision'] or
                   not math.isclose(edge['distance_meters'], expected['distance_meters'], rel_tol=1e-9, abs_tol=1e-12)
                   for edge, expected in zip(draft['edges'], calculated)):
                raise ValueError('Invalid calculated distances.')
        return response
    except (KeyError, TypeError, ValueError, OverflowError):
        raise database.DatabaseError('Invalid graph draft response.') from None


def read(level_id, admin_id, revision):
    result = database._execute(database.get_supabase().rpc('read_floor_plan_graph_draft', {
        'p_admin_id': admin_id, 'p_level_id': level_id, 'p_floor_plan_revision': revision,
    })).data
    return _result(result, 'read')


def save(level_id, admin_id, data):
    params = {'p_admin_id': admin_id, 'p_level_id': level_id}
    params.update({f'p_{key}': value for key, value in data.model_dump(mode='json').items()})
    return _result(database._execute(database.get_supabase().rpc('save_floor_plan_graph_draft', params)).data, 'saved')
