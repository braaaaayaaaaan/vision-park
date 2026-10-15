"""Eligibility and nearest-zone selection followed by an atomic reservation RPC."""

from backend import database as db
from backend.routing.dijkstra import shortest_routes


class AllocationError(ValueError):
    def __init__(self, code: str, message: str, status_code: int = 409):
        super().__init__(message)
        self.code = code
        self.status_code = status_code


def rank_zones(tenant_id: str, permissions: list[dict], zones: list[dict],
               levels: list[dict], active_counts: dict[str, int],
               nodes: list[dict], edges: list[dict], entrance_node_id: str) -> list[dict]:
    """Pure decision logic over a snapshot. This does not reserve capacity."""
    node_by_id = {node["id"]: node for node in nodes}
    entrance = node_by_id.get(entrance_node_id)
    if entrance is None or entrance["node_type"] != "building_entrance":
        raise AllocationError("invalid_entrance", "Select an existing building entrance node.", 422)
    allowed_ids = {row["zone_id"] for row in permissions if row["tenant_id"] == tenant_id}
    if not allowed_ids:
        raise AllocationError("no_authorised_zones", "The tenant has no authorised zones.", 403)
    active_levels = {level["id"]: level for level in levels if level["is_active"]}
    operational = [zone for zone in zones if zone["id"] in allowed_ids
                   and zone["operational_status"] == "open" and zone["level_id"] in active_levels]
    if not operational:
        raise AllocationError("no_operational_zones", "No authorised zones are operational.")
    available = [zone for zone in operational if
                 zone["total_capacity"] - zone["unavailable_capacity"] - active_counts[zone["id"]] > 0]
    if not available:
        raise AllocationError("zones_full", "All operational authorised zones are full.")
    try:
        routes = shortest_routes(nodes, edges, entrance_node_id)
    except ValueError:
        raise AllocationError("invalid_graph", "The active driving graph contains invalid data.") from None
    candidates = []
    for zone in available:
        destination = node_by_id.get(zone["entrance_node_id"])
        if (destination is None or destination["node_type"] != "zone_entrance"
                or destination["level_id"] != zone["level_id"]):
            raise AllocationError("invalid_zone_entrance", "An eligible zone needs a valid entrance node on its level.")
        route = routes.get(destination["id"])
        if route is not None:
            candidates.append({"zone": zone, "level": active_levels[zone["level_id"]], "route": route})
    if not candidates:
        raise AllocationError("no_reachable_zones", "No available authorised zone is reachable from this entrance.")
    return sorted(candidates, key=lambda item: (item["route"].distance_meters, item["zone"]["id"]))


def allocate_parking(plate_number: str, entrance_node_id: str) -> dict:
    """Called explicitly by the protected endpoint; not connected to ANPR yet."""
    vehicle = db.get_vehicle(plate_number)
    if vehicle is None:
        raise AllocationError("unknown_vehicle", "The plate is not registered.", 404)
    if vehicle["registration_status"] != "approved":
        raise AllocationError("registration_not_approved", "Vehicle registration is not approved.", 403)
    user = db.get_user(vehicle["user_id"])
    if user is None or not user["is_active"]:
        raise AllocationError("inactive_user", "The associated user is missing or inactive.", 403)
    tenant = db.get_tenant(user["tenant_id"]) if user["tenant_id"] else None
    if tenant is None or not tenant["is_active"]:
        raise AllocationError("inactive_tenant", "The associated tenant is missing or inactive.", 403)
    if db.get_active_session(vehicle["id"]) is not None:
        raise AllocationError("existing_active_session", "The vehicle already has an active parking session.")

    permissions = db.get_permissions(tenant["id"])
    if not permissions:
        raise AllocationError("no_authorised_zones", "The tenant has no authorised zones.", 403)
    allowed = {row["zone_id"] for row in permissions}
    zones = [zone for zone in db.get_zones() if zone["id"] in allowed]
    levels = db.get_levels()
    active_counts = {zone["id"]: db.count_active_sessions(zone["id"]) for zone in zones}
    nodes, edges = db.get_graph()
    candidates = rank_zones(tenant["id"], permissions, zones, levels, active_counts,
                            nodes, edges, entrance_node_id)

    for candidate in candidates:
        zone, level, route = candidate["zone"], candidate["level"], candidate["route"]
        reservation = db.reserve_zone(vehicle["id"], zone["id"])
        status = reservation["status"]
        if status == "allocated":
            if not reservation.get("session_id"):
                raise db.DatabaseError("Reservation response is missing the session ID; check active sessions before retrying.")
            return {
                "plate_number": vehicle["plate_number"],
                "zone_id": zone["id"], "zone_name": zone["name"],
                "level_id": level["id"], "level_name": level["name"],
                "level_number": level["level_number"],
                "distance_meters": float(route.distance_meters),
                "route_node_ids": route.node_ids,
                "parking_session_id": reservation["session_id"], "status": "allocated",
            }
        if status in {"zone_full", "zone_unavailable", "zone_not_authorised"}:
            continue  # Capacity/permissions may have changed since the read snapshot.
        messages = {
            "unknown_vehicle": ("The plate is no longer registered.", 404),
            "registration_not_approved": ("Vehicle registration is no longer approved.", 403),
            "inactive_user": ("The associated user is inactive.", 403),
            "inactive_tenant": ("The associated tenant is inactive.", 403),
            "existing_active_session": ("The vehicle already has an active parking session.", 409),
        }
        if status in messages:
            message, http_status = messages[status]
            raise AllocationError(status, message, http_status)
        raise db.DatabaseError("Reservation RPC returned an unknown status; check active sessions before retrying.")
    raise AllocationError("zones_unavailable", "The candidate zones became full or unavailable; request a fresh allocation.")
