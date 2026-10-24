"""Read-only navigation to an existing assignment; never allocates a zone."""
import os
from uuid import UUID

from fastapi import HTTPException
from pydantic import BaseModel, Field

from backend import database
from backend.routing.dijkstra import shortest_routes
from backend.parking.navigation_floor_plans import MapFloorPlan, published_floor_plans


class MapNode(BaseModel):
    id: UUID
    level_id: UUID
    x: float = Field(allow_inf_nan=False)
    y: float = Field(allow_inf_nan=False)
    label: str
    node_type: str


class MapLevel(BaseModel):
    id: UUID
    name: str
    level_number: int
    floor_plan: MapFloorPlan | None = None


class MapEdge(BaseModel):
    from_id: UUID
    to_id: UUID
    distance_meters: float = Field(ge=0, allow_inf_nan=False)


class AssignedRouteResponse(BaseModel):
    session_id: UUID
    vehicle_id: UUID
    zone_id: UUID
    entrance_node_id: UUID
    destination_node_id: UUID
    distance_meters: float = Field(ge=0, allow_inf_nan=False)
    route_node_ids: list[UUID] = Field(min_length=1)
    levels: list[MapLevel]
    nodes: list[MapNode]
    edges: list[MapEdge]


def assigned_route(user_id: str, session_id: str) -> AssignedRouteResponse:
    try:
        session = next((row for row in database.get_driver_active_sessions(user_id)
                        if row["id"] == session_id and row["user_id"] == user_id
                        and row["vehicle"]["user_id"] == user_id
                        and row["vehicle"]["id"] == row["vehicle_id"]), None)
        if session is None:
            raise HTTPException(404, "Active parking session not found.")
        if session["status"] != "allocated":
            raise HTTPException(409, "Route guidance is available only for an allocated session.")
        publication = database.get_publication_state()
        zone = next((row for row in database.get_zones() if row["id"] == session["zone_id"]), None)
        levels = {row["id"]: row for row in database.get_levels() if row["is_active"]}
        if zone is None or zone["operational_status"] != "open" or zone["level_id"] not in levels:
            raise HTTPException(409, "The assigned zone is currently unavailable.")
        source = publication['entrance_node_id'] if publication['revision'] else os.getenv("PARKING_ENTRANCE_NODE_ID", "").strip()
        if not source:
            raise HTTPException(503, "Navigation entrance is not configured.")
        source = str(UUID(source))
        nodes, edges = database.get_graph()
        if publication['revision']:
            # Retired seed nodes remain for referential history, and may have
            # nullable legacy coordinates. Only the active published network
            # belongs in the driver's map; isolated historical nodes do not.
            current_ids={source,zone['entrance_node_id']}
            for edge in edges:
                if edge['is_active']:
                    current_ids.update((edge['from_node_id'],edge['to_node_id']))
            nodes=[node for node in nodes if node['id'] in current_ids]
        # Validate the database graph first, including dangling active edges.
        shortest_routes(nodes, edges, source)
        nodes = [row for row in nodes if row["level_id"] in levels]
        by_id = {row["id"]: row for row in nodes}
        destination = zone["entrance_node_id"]
        if (source not in by_id or by_id[source]["node_type"] != "building_entrance"
                or destination not in by_id or by_id[destination]["node_type"] != "zone_entrance"
                or by_id[destination]["level_id"] != zone["level_id"]):
            raise ValueError("Invalid entrance nodes")
        edges = [row for row in edges if row["is_active"]
                 and row["from_node_id"] in by_id and row["to_node_id"] in by_id]
        route = shortest_routes(nodes, edges, source).get(destination)
        if route is None:
            raise HTTPException(409, "The assigned zone entrance is unreachable from the configured entrance.")
        used_levels = {node["level_id"] for node in nodes}
        plans = published_floor_plans(publication, session_id, nodes, route.node_ids)
        return AssignedRouteResponse(
            session_id=session_id, vehicle_id=session["vehicle_id"], zone_id=zone["id"],
            entrance_node_id=source, destination_node_id=destination,
            distance_meters=float(route.distance_meters), route_node_ids=route.node_ids,
            levels=[MapLevel(**level, floor_plan=plans.get(level['id'])) for level in sorted(levels.values(), key=lambda row: (row["level_number"], row["id"]))
                    if level["id"] in used_levels],
            nodes=[MapNode(id=row["id"], level_id=row["level_id"], x=row["x_position"],
                           y=row["y_position"], label=row["code"], node_type=row["node_type"]) for row in nodes],
            edges=[MapEdge(from_id=row["from_node_id"], to_id=row["to_node_id"],
                           distance_meters=row["distance_meters"]) for row in edges],
        )
    except (database.DatabaseError, KeyError, TypeError, ValueError):
        raise HTTPException(503, "Navigation graph data is unavailable or incomplete. Please try again.") from None
