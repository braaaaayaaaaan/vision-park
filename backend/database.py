"""Small Supabase boundary. Importing this module does not connect to the database."""

import os
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


class DatabaseError(RuntimeError):
    """Safe message for callers; never include SDK errors containing credentials."""


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


def count_active_sessions(zone_id: str) -> int:
    response = _execute(get_supabase().table("parking_sessions").select(
        "id", count="exact", head=True
    ).eq("zone_id", zone_id).in_("status", ACTIVE_STATUSES))
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
