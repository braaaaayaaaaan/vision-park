"""Small Supabase boundary. Importing this module does not connect to the database."""

import os
from datetime import datetime, timezone
from uuid import uuid4
from pathlib import Path
from threading import Lock

from dotenv import load_dotenv
from httpx import HTTPError
from postgrest.exceptions import APIError
from supabase import Client, create_client

ROOT_ENV = Path(__file__).resolve().parents[1] / ".env"
load_dotenv(ROOT_ENV, override=False)
_client: Client | None = None
_client_lock = Lock()
ACTIVE_STATUSES = ("allocated", "occupied")


def get_history_vehicles(user_id: str) -> list[dict]:
    return _all_rows(lambda: get_supabase().table("vehicles")
                     .select("id,user_id,plate_number").eq("user_id", user_id))


def get_driver_history(user_id, start, end, snapshot, vehicle_id, limit, last_exit=None, last_id=None):
    """Bounded keyset pages; completed rows sort by exit, then UUID, null exits last.

    The frozen upper bound keeps newly closed sessions out of subsequent pages.
    Missing entry timestamps cannot belong to an entry-date window.
    """
    fields = ("id,user_id,vehicle_id,zone_id,status,entry_time,parking_confirmed_at,exit_time,"
              "vehicle:vehicles!vehicle_id!inner(id,user_id,plate_number),"
              "zone:parking_zones!zone_id(id,name,level:parking_levels!level_id(id,name))")

    def query(*, head=False):
        q = get_supabase().table("parking_sessions").select(fields, count="exact", head=head)
        q = (q.eq("user_id", user_id).eq("vehicle.user_id", user_id).eq("status", "completed")
             .gte("entry_time", start).lt("entry_time", end).lte("entry_time", snapshot)
             .or_(f"exit_time.lte.{snapshot},exit_time.is.null"))
        return q.eq("vehicle_id", vehicle_id) if vehicle_id else q

    total = _execute(query(head=True)).count
    q = query()
    if last_id:
        if last_exit:
            q = q.or_(f"exit_time.lt.{last_exit},and(exit_time.eq.{last_exit},id.lt.{last_id}),exit_time.is.null")
        else:
            q = q.is_("exit_time", "null").lt("id", last_id)
    rows = _execute(q.order("exit_time", desc=True, nullsfirst=False)
                    .order("id", desc=True).limit(limit)).data
    return rows, total


class DatabaseError(RuntimeError):
    """Safe message for callers; never include SDK errors containing credentials."""


class DuplicateVehicleError(DatabaseError):
    pass


class VehicleRemovalConflict(DatabaseError):
    pass


def get_owned_vehicle(user_id: str, vehicle_id: str) -> dict | None:
    rows = _execute(get_supabase().table("vehicles").select("id,user_id,plate_number,registration_status")
                    .eq("id", vehicle_id).eq("user_id", user_id).limit(1)).data
    return rows[0] if rows else None


def vehicle_has_records(vehicle_id: str) -> bool:
    for table in ("parking_sessions", "anpr_events"):
        if _execute(get_supabase().table(table).select("id").eq("vehicle_id", vehicle_id).limit(1)).data:
            return True
    return False


def remove_driver_vehicle(user_id: str, vehicle_id: str) -> bool:
    # Existing NO ACTION FKs are the final authority if a reference is inserted
    # concurrently. Never delete dependent session/ANPR records.
    try:
        rows = get_supabase().table("vehicles").delete().eq("id", vehicle_id).eq("user_id", user_id).execute().data
    except APIError as error:
        if error.code == "23503":
            raise VehicleRemovalConflict("This vehicle has parking or ANPR records and cannot be removed.") from None
        raise DatabaseError("Vehicle removal could not be verified.") from None
    except HTTPError:
        raise DatabaseError("Vehicle removal could not be verified. Refresh before retrying.") from None
    return bool(rows)


def get_driver_vehicles(user_id: str) -> list[dict]:
    return _all_rows(lambda: get_supabase().table("vehicles").select(
        "id,user_id,plate_number,registration_status,"
        "sessions:parking_sessions!vehicle_id(id,vehicle_id,zone_id,user_id,status,entry_time,parking_confirmed_at,exit_time)"
    ).eq("user_id", user_id).eq("sessions.user_id", user_id)
        .in_("sessions.status", ACTIVE_STATUSES))


def register_driver_vehicle(user_id: str, plate_number: str) -> dict:
    # Company association is through the verified owner (users.tenant_id).
    # The database's plate uniqueness constraint is authoritative under races.
    try:
        now = datetime.now(timezone.utc).isoformat()
        rows = get_supabase().table("vehicles").insert({
            "id": str(uuid4()), "created_at": now, "updated_at": now,
            "user_id": user_id, "plate_number": plate_number, "registration_status": "pending",
        }).execute().data
    except APIError as error:
        if error.code == "23505":
            raise DuplicateVehicleError("This plate is already registered.") from None
        raise DatabaseError("Vehicle registration could not be saved.") from None
    except HTTPError:
        raise DatabaseError("Registration could not be verified. Refresh your vehicles before retrying.") from None
    if not rows or len(rows) != 1:
        raise DatabaseError("Registration could not be verified. Refresh your vehicles before retrying.")
    return rows[0]


def get_supabase() -> Client:
    global _client
    with _client_lock:
        if _client is None:
            url = os.getenv("SUPABASE_URL", "").strip().rstrip("/")
            # Accept a copied Data API URL; the SDK adds /rest/v1 itself.
            if url.endswith("/rest/v1"):
                url = url[:-len("/rest/v1")]
            key = os.getenv("SUPABASE_KEY", "").strip()
            if not url or not key:
                raise DatabaseError("Set SUPABASE_URL and SUPABASE_KEY in the root .env.")
            try:
                _client = create_client(url, key)
            except Exception:
                raise DatabaseError("Unable to initialise Supabase; check backend configuration.") from None
        return _client


def _execute(query):
    try:
        return query.execute()
    except APIError as error:
        if error.code == "PGRST202":
            raise DatabaseError("Database RPC unavailable. Review and apply the relevant SQL migration first.") from None
        raise DatabaseError("Supabase query failed; check table access, schema and backend credentials.") from None
    except HTTPError:
        raise DatabaseError("Supabase is unreachable; check connectivity and project availability.") from None


def _all_rows(make_query) -> list[dict]:
    # Explicit pagination avoids silently truncating a graph at the API row limit.
    rows = []
    while True:
        # SDK builders mutate their query parameters; start fresh for each page.
        page = _execute(make_query().order("id").range(len(rows), len(rows) + 499)).data
        if not page:
            return rows
        rows.extend(page)


def check_connection() -> bool:
    """Minimal read-only query; False means the query worked but no row was visible."""
    return bool(_execute(get_supabase().table("parking_levels").select("id").limit(1)).data)


def get_vehicle(plate_number: str) -> dict | None:
    rows = _execute(get_supabase().table("vehicles").select(
        "id,user_id,plate_number,registration_status"
    ).eq("plate_number", plate_number).limit(1)).data
    return rows[0] if rows else None


def get_driver_active_sessions(user_id: str) -> list[dict]:
    """Read all active sessions with both recorded and current ownership scoped.

    The inner vehicle join makes the ownership filter apply to session rows,
    rather than merely hiding an embedded vehicle from another driver.
    """
    return _all_rows(lambda: get_supabase().table("parking_sessions").select(
        "id,user_id,vehicle_id,zone_id,status,entry_time,parking_confirmed_at,exit_time,"
        "vehicle:vehicles!vehicle_id!inner(id,user_id,plate_number,registration_status),"
        "zone:parking_zones!zone_id(id,code,name,level_id,"
        "level:parking_levels!level_id(id,name,level_number))"
    ).eq("user_id", user_id).eq("vehicle.user_id", user_id)
        .in_("status", list(ACTIVE_STATUSES)))


def get_driver_session(user_id: str, session_id: str) -> dict | None:
    """Ownership-scoped session read, including terminal states for validation."""
    rows = _execute(get_supabase().table("parking_sessions").select(
        "id,user_id,vehicle_id,zone_id,status,parking_confirmed_at,exit_time,"
        "vehicle:vehicles!vehicle_id!inner(id,user_id)"
    ).eq("id", session_id).eq("user_id", user_id).eq("vehicle.user_id", user_id).limit(1)).data
    return rows[0] if rows else None


def get_user(user_id: str) -> dict | None:
    rows = _execute(get_supabase().table("users").select(
        "id,tenant_id,is_active"
    ).eq("id", user_id).limit(1)).data
    return rows[0] if rows else None


def get_auth_profile(user_id: str) -> dict | None:
    rows = _execute(get_supabase().table("users").select(
        "id,full_name,role,approval_status,is_active,tenant_id"
    ).eq("id", user_id).limit(1)).data
    return rows[0] if rows else None


def get_tenant(tenant_id: str) -> dict | None:
    rows = _execute(get_supabase().table("tenants").select(
        "id,name,is_active"
    ).eq("id", tenant_id).limit(1)).data
    return rows[0] if rows else None


def get_registration_companies() -> list[dict]:
    return _all_rows(lambda: get_supabase().table("tenants").select(
        "id,name"
    ).eq("is_active", True))


def get_pending_driver_registrations(limit: int, offset: int) -> list[dict]:
    return _execute(get_supabase().table("users").select(
        "id,full_name,approval_status,is_active,requested_tenant_id,"
        "requested_company:tenants!requested_tenant_id(id,name,is_active)"
    ).eq("role", "driver").eq("approval_status", "pending")
        .order("id").range(offset, offset + limit - 1)).data


def decide_driver_registration(admin_id: str, user_id: str, decision: str, tenant_id: str | None) -> dict:
    result = _execute(get_supabase().rpc("decide_driver_registration", {
        "p_admin_id": admin_id, "p_user_id": user_id,
        "p_decision": decision, "p_tenant_id": tenant_id,
    })).data
    if not isinstance(result, dict) or "status" not in result:
        raise DatabaseError("Registration decision RPC returned an invalid response.")
    return result


def insert_pending_driver(user_id: str, full_name: str, requested_tenant_id: str):
    # ON CONFLICT DO NOTHING makes concurrent retries safe; never merge into an
    # existing account. In particular, never overwrite an administrator profile.
    _execute(get_supabase().table("users").upsert({
        "id": user_id, "full_name": full_name, "role": "driver",
        "approval_status": "pending", "is_active": False, "tenant_id": None,
        "requested_tenant_id": requested_tenant_id,
    }, on_conflict="id", ignore_duplicates=True))


def get_permissions(tenant_id: str) -> list[dict]:
    return _all_rows(lambda: get_supabase().table("tenant_parking_zones").select(
        "id,tenant_id,zone_id"
    ).eq("tenant_id", tenant_id))


def get_zones() -> list[dict]:
    return _all_rows(lambda: get_supabase().table("parking_zones").select(
        "id,level_id,code,name,total_capacity,unavailable_capacity,operational_status,entrance_node_id"
    ))


def get_levels() -> list[dict]:
    return _all_rows(lambda: get_supabase().table("parking_levels").select(
        "id,level_number,name,is_active"
    ))


def get_graph() -> tuple[list[dict], list[dict]]:
    nodes = _all_rows(lambda: get_supabase().table("parking_graph_nodes").select(
        "id,code,node_type,level_id,x_position,y_position"
    ))
    edges = _all_rows(lambda: get_supabase().table("parking_graph_edges").select(
        "id,from_node_id,to_node_id,distance_meters,is_active"
    ))
    return nodes, edges


def get_active_session(vehicle_id: str) -> dict | None:
    rows = _execute(get_supabase().table("parking_sessions").select(
        "id,vehicle_id,zone_id,status"
    ).eq("vehicle_id", vehicle_id).in_("status", ACTIVE_STATUSES).limit(1)).data
    return rows[0] if rows else None


def count_active_sessions(zone_id: str, *, status: str | None = None) -> int:
    if status is not None and status not in ACTIVE_STATUSES:
        raise ValueError("Only active session statuses can consume capacity.")
    response = _execute(get_supabase().table("parking_sessions").select(
        "id", count="exact", head=True
    ).eq("zone_id", zone_id).in_("status", (status,) if status else ACTIVE_STATUSES))
    if response.count is None:
        raise DatabaseError("Supabase did not return the active session count.")
    return response.count


def reserve_zone(vehicle_id: str, zone_id: str) -> dict:
    # Never fall back to a non-atomic client-side insert if the RPC is missing.
    result = _execute(get_supabase().rpc("reserve_parking_zone", {
        "p_vehicle_id": vehicle_id, "p_zone_id": zone_id,
    })).data
    if not isinstance(result, dict) or "status" not in result:
        raise DatabaseError("Reservation RPC returned an invalid response.")
    return result


def confirm_session(session_id: str, vehicle_id: str) -> dict:
    result = _execute(get_supabase().rpc("confirm_parking_session", {
        "p_session_id": session_id, "p_vehicle_id": vehicle_id,
    })).data
    if not isinstance(result, dict) or "status" not in result:
        raise DatabaseError("Confirmation RPC returned an invalid response.")
    return result


def close_session(session_id: str, vehicle_id: str) -> dict:
    result = _execute(get_supabase().rpc("close_parking_session", {
        "p_session_id": session_id, "p_vehicle_id": vehicle_id,
    })).data
    if not isinstance(result, dict) or "status" not in result:
        raise DatabaseError("Closure RPC returned an invalid response.")
    return result
