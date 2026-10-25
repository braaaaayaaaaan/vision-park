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


def get_admin_parking_sessions(limit, offset, plate, status, level_id, start, end):
    vehicle = 'vehicle:vehicles!vehicle_id!inner' if plate else 'vehicle:vehicles!vehicle_id'
    zone = 'zone:parking_zones!zone_id!inner' if level_id else 'zone:parking_zones!zone_id'
    query = get_supabase().table('parking_sessions').select(
        'id,vehicle_id,zone_id,status,entry_time,parking_confirmed_at,exit_time,'
        f'{vehicle}(plate_number,owner:users!user_id(full_name,tenant:tenants!tenant_id(name))),'
        f'{zone}(name,level_id,level:parking_levels!level_id(name))', count='exact')
    if plate:
        query = query.ilike('vehicle.plate_number', f'%{plate}%')
    if status:
        query = query.eq('status', status)
    if level_id:
        query = query.eq('zone.level_id', level_id)
    if start is not None:
        query = query.gte('entry_time', start).lt('entry_time', end)
    query = query.order('entry_time', desc=True, nullsfirst=False).order('id', desc=True)
    try:
        result = _execute(query.range(offset, offset + limit - 1))
    except DatabaseError:
        if offset == 0:
            raise
        first = _execute(query.range(0, 0))
        if isinstance(first.count, int) and offset >= first.count:
            return [], first.count
        raise
    return result.data, result.count


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


class RegistrationCompanyUnavailable(DatabaseError):
    """Atomic registration completion found no active requested company."""


class DuplicateVehicleError(DatabaseError):
    pass


class VehicleLimitReached(DatabaseError):
    pass


class VehicleRegistrationForbidden(DatabaseError):
    pass


class RejectedVehicleRetention(DatabaseError):
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
        if error.code == "PVR01":
            raise RejectedVehicleRetention("Rejected registrations are retained for audit.") from None
        if error.code == "23503":
            raise VehicleRemovalConflict("This vehicle has parking or ANPR records and cannot be removed.") from None
        raise DatabaseError("Vehicle removal could not be verified.") from None
    except HTTPError:
        raise DatabaseError("Vehicle removal could not be verified. Refresh before retrying.") from None
    return bool(rows)


def decide_vehicle_registration(admin_id: str, vehicle_id: str, decision: str, rejection_reason: str | None = None) -> dict:
    result = _execute(get_supabase().rpc('decide_vehicle_registration', {
        'p_admin_id': admin_id, 'p_vehicle_id': vehicle_id, 'p_decision': decision,
        'p_rejection_reason': rejection_reason,
    })).data
    if not isinstance(result, dict) or 'status' not in result:
        raise DatabaseError('Vehicle decision RPC returned an invalid response.')
    return result


def get_admin_vehicles(limit, offset, plate, status, tenant_id):
    owner = 'owner:users!user_id!inner' if tenant_id else 'owner:users!user_id'
    query = get_supabase().table('vehicles').select(
        f'id,user_id,plate_number,registration_status,rejection_reason,{owner}(full_name,tenant_id,tenant:tenants!tenant_id(id,name))',
        count='exact')
    if plate:
        query = query.ilike('plate_number', f'%{plate}%')
    if status:
        query = query.eq('registration_status', status)
    if tenant_id:
        query = query.eq('owner.tenant_id', tenant_id)
    query = query.order('plate_number').order('id')
    try:
        result = _execute(query.range(offset, offset + limit - 1))
    except DatabaseError:
        if offset == 0:
            raise
        # PostgREST can reject a range beyond the matching total. Verify the
        # filtered count with a first-row request before treating it as empty.
        first = _execute(query.range(0, 0))
        if isinstance(first.count, int) and offset >= first.count:
            return [], first.count
        raise
    return result.data, result.count


def get_vehicle_companies():
    return _all_rows(lambda: get_supabase().table('tenants').select('id,name'))


def get_admin_vehicle_drivers(admin_id, limit, offset, search, tenant_id, status):
    return _execute(get_supabase().rpc('read_admin_vehicle_drivers', {
        'p_admin_id': admin_id, 'p_limit': limit, 'p_offset': offset,
        'p_search': search, 'p_tenant_id': tenant_id, 'p_status': status,
    })).data


def get_admin_vehicle_driver_details(admin_id, driver_id, limit, offset, status):
    return _execute(get_supabase().rpc('read_admin_vehicle_driver_details', {
        'p_admin_id': admin_id, 'p_driver_id': driver_id, 'p_limit': limit,
        'p_offset': offset, 'p_status': status,
    })).data


def get_admin_vehicle_summary(admin_id, tenant_id):
    return _execute(get_supabase().rpc('read_admin_vehicle_summary', {
        'p_admin_id': admin_id, 'p_tenant_id': tenant_id,
    })).data


def get_driver_vehicles(user_id: str) -> list[dict]:
    return _all_rows(lambda: get_supabase().table("vehicles").select(
        "id,user_id,plate_number,registration_status,rejection_reason,"
        "sessions:parking_sessions!vehicle_id(id,vehicle_id,zone_id,user_id,status,entry_time,parking_confirmed_at,exit_time,"
        "zone:parking_zones!zone_id(name,level:parking_levels!level_id(name)))"
    ).eq("user_id", user_id).eq("sessions.user_id", user_id)
        .in_("sessions.status", ACTIVE_STATUSES))


def register_driver_vehicle(user_id: str, plate_number: str) -> dict:
    # No direct-insert fallback: missing RPC deployment must fail closed.
    result = _execute(get_supabase().rpc("register_driver_vehicle", {
        "p_driver_id": user_id, "p_plate_number": plate_number,
    })).data
    if not isinstance(result, dict):
        raise DatabaseError("Vehicle registration could not be verified.")
    if result.get("status") == "vehicle_limit_reached":
        raise VehicleLimitReached("The five-vehicle registration limit has been reached.")
    if result.get("status") == "duplicate_plate":
        raise DuplicateVehicleError("This plate is already registered.")
    if result.get("status") == "forbidden":
        raise VehicleRegistrationForbidden("Driver eligibility could not be confirmed.")
    row = result.get("vehicle")
    if (result.get("status") != "registered" or not isinstance(row, dict)
            or row.get("user_id") != user_id or row.get("plate_number") != plate_number
            or row.get("registration_status") != "pending"):
        raise DatabaseError("Vehicle registration could not be verified.")
    return row


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


def get_overview_sessions(start: str, end: str) -> list[dict]:
    """One paginated set for active capacity and either movement timestamp today."""
    filters = (f"status.in.(allocated,occupied),"
               f"and(entry_time.gte.{start},entry_time.lt.{end}),"
               f"and(exit_time.gte.{start},exit_time.lt.{end})")
    return _all_rows(lambda: get_supabase().table("parking_sessions")
        .select("id,zone_id,status,entry_time,exit_time")
        .in_("status", ["allocated", "occupied", "completed"]).or_(filters))


def get_analytics_sessions(start: str, end: str, level_id: str | None = None) -> list[dict]:
    """Read either movement or a confirmed interval overlapping the range."""
    relation = "zone:parking_zones!zone_id!inner(level_id)" if level_id else "zone:parking_zones!zone_id(level_id)"
    def query():
        result = (get_supabase().table("parking_sessions")
            .select(f"id,zone_id,user_id,status,entry_time,parking_confirmed_at,exit_time,{relation},user:users!user_id(tenant_id)")
            .in_("status", ["allocated", "occupied", "completed"])
            .or_(f"and(entry_time.gte.{start},entry_time.lt.{end}),and(exit_time.gte.{start},exit_time.lt.{end}),"
                 f"and(parking_confirmed_at.lt.{end},or(exit_time.is.null,exit_time.gt.{start}))"))
        return result.eq("zone.level_id", level_id) if level_id else result
    return _all_rows(query)


def get_analytics_tenants() -> list[dict]:
    """Include inactive companies so history and zero-activity groups remain visible."""
    return _all_rows(lambda: get_supabase().table("tenants").select("id,name,is_active"))


def get_overview_recent_sessions(snapshot: str) -> list[dict]:
    """Latest five non-cancelled sessions by entry; left joins preserve missing labels."""
    return _execute(get_supabase().table("parking_sessions").select(
        "id,status,entry_time,exit_time,vehicle:vehicles!vehicle_id(plate_number),"
        "zone:parking_zones!zone_id(name,level:parking_levels!level_id(name))")
        .in_("status", ["allocated", "occupied", "completed"]).lte("entry_time", snapshot)
        .order("entry_time", desc=True).order("id", desc=True).limit(5)).data


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


def read_admin_tenants(admin_id, tenant_id, search, status, sort, limit, offset):
    return _execute(get_supabase().rpc('read_admin_tenants', {
        'p_admin_id': admin_id, 'p_tenant_id': tenant_id, 'p_search': search,
        'p_status': status, 'p_sort': sort, 'p_limit': limit, 'p_offset': offset,
    })).data


def save_admin_tenant(admin_id, change):
    return _execute(get_supabase().rpc('save_admin_tenant', {
        'p_admin_id': admin_id, 'p_change': change,
    })).data


def get_registration_companies() -> list[dict]:
    return _all_rows(lambda: get_supabase().table("tenants").select(
        "id,name"
    ).eq("is_active", True))


def get_driver_registrations(limit: int, offset: int, status='pending', tenant_id=None, sort='name_asc') -> list[dict]:
    query = get_supabase().table("users").select(
        "id,full_name,approval_status,is_active,requested_tenant_id,tenant_id,"
        "requested_company:tenants!requested_tenant_id(id,name,is_active),"
        "company:tenants!tenant_id(id,name,is_active)", count='exact'
    ).eq("role", "driver")
    if status != 'all':
        query = query.eq('approval_status', status)
    if tenant_id:
        # Approved membership is authoritative; other statuses retain their request.
        query = query.or_(f'and(approval_status.eq.approved,tenant_id.eq.{tenant_id}),'
                          f'and(approval_status.neq.approved,requested_tenant_id.eq.{tenant_id})')
    query = query.order('full_name', desc=sort == 'name_desc', nullsfirst=False).order('id')
    try:
        return _execute(query.range(offset, offset + limit - 1)).data
    except DatabaseError:
        if offset > 0:
            first = _execute(query.range(0, 0))
            if isinstance(first.count, int) and offset >= first.count:
                return []
        raise


def get_driver_registration_summary_rows() -> list[dict]:
    return _all_rows(lambda: get_supabase().table('users').select(
        'id,approval_status,tenant_id,requested_tenant_id').eq('role', 'driver'))


def decide_driver_registration(admin_id: str, user_id: str, decision: str, tenant_id: str | None) -> dict:
    result = _execute(get_supabase().rpc("decide_driver_registration", {
        "p_admin_id": admin_id, "p_user_id": user_id,
        "p_decision": decision, "p_tenant_id": tenant_id,
    })).data
    if not isinstance(result, dict) or "status" not in result:
        raise DatabaseError("Registration decision RPC returned an invalid response.")
    return result


def insert_pending_driver(user_id: str, full_name: str, requested_tenant_id: str):
    # The RPC locks/checks tenant activity and inserts in one transaction. No
    # fallback to separate REST operations: missing setup must fail closed.
    result = _execute(get_supabase().rpc('complete_pending_driver_registration', {
        'p_user_id': user_id, 'p_full_name': full_name, 'p_requested_tenant_id': requested_tenant_id,
    })).data
    if isinstance(result, dict) and result.get('status') == 'invalid_company':
        raise RegistrationCompanyUnavailable('Select an available company.')
    if not isinstance(result, dict) or result.get('status') != 'profile_available' or result.get('id') != user_id:
        raise DatabaseError('Registration completion returned an unconfirmed result.')
    return result


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
        "id,level_number,name,is_active,updated_at,metadata_revision"
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


def get_published_navigation_draft(revision: int) -> dict | None:
    """Read the immutable receipt for this exact operational revision."""
    rows = _execute(get_supabase().table('parking_configuration_publications')
                    .select('validated_draft').eq('revision', revision).limit(1)).data
    return rows[0]['validated_draft'] if rows else None


def get_publication_state() -> dict:
    result = _execute(get_supabase().rpc('read_parking_publication_state', {})).data
    if not isinstance(result, dict) or type(result.get('revision')) is not int or not 0 <= result['revision'] <= 9007199254740990 or (
            result['revision'] > 0 and (not isinstance(result.get('entrance_node_id'), str) or not isinstance(result.get('entrance_aliases'), list))):
        raise DatabaseError('Operational publication state is unavailable.')
    return result


def reserve_zone(vehicle_id: str, zone_id: str, expected_revision: int | None = None) -> dict:
    # Never fall back to a non-atomic client-side insert if the RPC is missing.
    params = {"p_vehicle_id": vehicle_id, "p_zone_id": zone_id}
    if expected_revision is not None:
        params['p_expected_revision'] = expected_revision
    result = _execute(get_supabase().rpc('reserve_parking_zone_at_revision' if expected_revision is not None else 'reserve_parking_zone', params)).data
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
