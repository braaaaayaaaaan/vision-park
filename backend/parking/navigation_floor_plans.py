"""Fail-closed image metadata for the levels on an owned session's route."""
from io import BytesIO
import logging
import math

from fastapi import HTTPException
from PIL import Image
from pydantic import BaseModel, Field

from backend import database
from backend.parking import floor_plans

logger = logging.getLogger(__name__)

# JSONB receipt numbers and operational float8 coordinates can serialize with
# different precision. Allow only rounding noise, never a visible pixel shift.
COORDINATE_ABS_TOLERANCE_PX = 1e-8


def compatible_coordinate(current, published):
    return (type(current) in (int, float) and type(published) in (int, float)
            and math.isfinite(current) and math.isfinite(published)
            and math.isclose(current, published, rel_tol=0,
                             abs_tol=COORDINATE_ABS_TOLERANCE_PX))


def omitted(reason, revision, level_id=None):
    # Fixed reason codes only: never log receipts, storage keys or exceptions.
    logger.warning('Navigation floor plan omitted: reason=%s publication_revision=%s level_id=%s',
                   reason, revision, level_id)


class MapFloorPlan(BaseModel):
    width_px: int = Field(gt=0)
    height_px: int = Field(gt=0)
    revision: int = Field(gt=0)
    publication_revision: int = Field(gt=0)
    image_path: str


def compatible_plan(plan, published):
    return bool(isinstance(plan, dict) and isinstance(published, dict) and all(
        type(published.get(key)) is int and type(plan.get(key)) is int
        and published[key] > 0 and plan[key] == published[key]
        for key in ('revision', 'width_px', 'height_px'))
        and plan['width_px'] * plan['height_px'] <= floor_plans.MAX_PIXELS)


def published_image_bytes(level_id, descriptor):
    plan = floor_plans.metadata(level_id)
    if not compatible_plan(plan, descriptor.model_dump()):
        raise HTTPException(409, 'The floor plan changed. Refresh navigation.')
    # Download the checked immutable key, not a second lookup of "latest".
    image = floor_plans.storage().download(plan['storage_object_key'])
    if not image or len(image) > floor_plans.MAX_BYTES:
        raise ValueError('Invalid stored image size')
    with Image.open(BytesIO(image), formats=['PNG']) as decoded:
        if decoded.size != (descriptor.width_px, descriptor.height_px):
            raise ValueError('Stored image dimensions changed')
        decoded.verify()
    return image


def published_floor_plans(publication, session_id, nodes, route_ids):
    """Never infer alignment from the latest administrator draft alone.

    Receipts contain revision/dimensions, not retained image objects. Replaced
    images therefore become unavailable until the replacement is published.
    Image access is restricted to floors actually traversed by this route.
    """
    if not publication['revision']:
        omitted('no_publication', 0)
        return {}
    try:
        receipt = database.get_published_navigation_draft(publication['revision'])
        if not isinstance(receipt, dict):
            omitted('missing_or_invalid_receipt', publication['revision'])
            return {}
        published_levels = {level['id']: level for level in receipt['levels']}
        route_ids = set(route_ids)
        route_levels = {node['level_id'] for node in nodes if node['id'] in route_ids}
        plans = {}
        for level_id in route_levels:
            published = published_levels.get(level_id, {})
            plan = floor_plans.metadata(level_id)
            if not compatible_plan(plan, published.get('floor_plan')):
                reason = ('missing_published_level' if not published else
                          'missing_current_image_metadata' if plan is None else
                          'missing_published_image_metadata' if published.get('floor_plan') is None else
                          'image_revision_dimensions_or_metadata_mismatch')
                omitted(reason, publication['revision'], level_id)
                continue
            draft_nodes = {node['id']: node for node in published['draft']['nodes']}
            local_nodes = [node for node in nodes if node['level_id'] == level_id]
            if any(node['id'] not in draft_nodes
                   or node['node_type'] != draft_nodes[node['id']]['node_type']
                   or any(not compatible_coordinate(node[operational], draft_nodes[node['id']][draft])
                          for operational, draft in (('x_position', 'x'), ('y_position', 'y')))
                   for node in local_nodes):
                omitted('published_node_geometry_or_type_mismatch', publication['revision'], level_id)
                continue
            plans[level_id] = MapFloorPlan(
                width_px=plan['width_px'], height_px=plan['height_px'], revision=plan['revision'],
                publication_revision=publication['revision'],
                image_path=f"parking/sessions/{session_id}/route/levels/{level_id}/floor-plan"
                           f"?publication_revision={publication['revision']}&floor_plan_revision={plan['revision']}")
        return plans
    except (database.DatabaseError, KeyError, TypeError, ValueError) as error:
        omitted('metadata_read_failed' if isinstance(error, database.DatabaseError)
                else 'malformed_publication_metadata', publication['revision'])
        # Image metadata must not remove otherwise valid routing/confirmation.
        return {}
