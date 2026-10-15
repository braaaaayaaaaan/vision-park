-- REVIEW ONLY: this file is not executed by the application.
-- Adds one function to the existing VisionPark V1 schema; no tables/data changed.
-- All application allocations must use this function. Direct privileged INSERTs
-- and administrative capacity changes can bypass this reservation protocol.
BEGIN;

CREATE FUNCTION public.reserve_parking_zone(p_vehicle_id uuid, p_zone_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_vehicle public.vehicles%ROWTYPE;
    v_user public.users%ROWTYPE;
    v_tenant public.tenants%ROWTYPE;
    v_zone public.parking_zones%ROWTYPE;
    v_level public.parking_levels%ROWTYPE;
    v_node public.parking_graph_nodes%ROWTYPE;
    v_active bigint;
    v_session_id uuid;
    v_error_schema text;
    v_error_table text;
    v_error_constraint text;
BEGIN
    -- Serialise competing requests for this vehicle, including different zones.
    SELECT * INTO v_vehicle FROM public.vehicles WHERE id = p_vehicle_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'unknown_vehicle');
    END IF;
    IF v_vehicle.registration_status <> 'approved' THEN
        RETURN jsonb_build_object('status', 'registration_not_approved');
    END IF;

    SELECT * INTO v_user FROM public.users WHERE id = v_vehicle.user_id FOR SHARE;
    IF NOT FOUND OR NOT v_user.is_active THEN
        RETURN jsonb_build_object('status', 'inactive_user');
    END IF;
    SELECT * INTO v_tenant FROM public.tenants WHERE id = v_user.tenant_id FOR SHARE;
    IF NOT FOUND OR NOT v_tenant.is_active THEN
        RETURN jsonb_build_object('status', 'inactive_tenant');
    END IF;
    IF EXISTS (SELECT 1 FROM public.parking_sessions
               WHERE vehicle_id = p_vehicle_id AND status IN ('allocated', 'occupied')) THEN
        RETURN jsonb_build_object('status', 'existing_active_session');
    END IF;

    -- Every reservation for this zone takes this same lock BEFORE counting.
    SELECT * INTO v_zone FROM public.parking_zones WHERE id = p_zone_id FOR UPDATE;
    IF NOT FOUND OR v_zone.operational_status <> 'open' THEN
        RETURN jsonb_build_object('status', 'zone_unavailable');
    END IF;
    SELECT * INTO v_level FROM public.parking_levels WHERE id = v_zone.level_id FOR SHARE;
    IF NOT FOUND OR NOT v_level.is_active THEN
        RETURN jsonb_build_object('status', 'zone_unavailable');
    END IF;
    SELECT * INTO v_node FROM public.parking_graph_nodes WHERE id = v_zone.entrance_node_id FOR SHARE;
    IF NOT FOUND OR v_node.node_type <> 'zone_entrance'
        OR v_node.level_id IS DISTINCT FROM v_zone.level_id THEN
        RETURN jsonb_build_object('status', 'zone_unavailable');
    END IF;
    PERFORM 1 FROM public.tenant_parking_zones
        WHERE tenant_id = v_tenant.id AND zone_id = p_zone_id FOR SHARE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'zone_not_authorised');
    END IF;

    -- A separate statement after acquiring the lock sees preceding commits at
    -- PostgreSQL's default READ COMMITTED isolation. A session counts once.
    SELECT count(*) INTO v_active FROM public.parking_sessions
        WHERE zone_id = p_zone_id AND status IN ('allocated', 'occupied');
    IF v_zone.total_capacity - v_zone.unavailable_capacity - v_active <= 0 THEN
        RETURN jsonb_build_object('status', 'zone_full');
    END IF;

    INSERT INTO public.parking_sessions (vehicle_id, user_id, zone_id, entry_time, status)
        VALUES (v_vehicle.id, v_user.id, v_zone.id, clock_timestamp(), 'allocated')
        RETURNING id INTO v_session_id;
    RETURN jsonb_build_object('status', 'allocated', 'session_id', v_session_id);
EXCEPTION WHEN unique_violation THEN
    GET STACKED DIAGNOSTICS
        v_error_schema = SCHEMA_NAME,
        v_error_table = TABLE_NAME,
        v_error_constraint = CONSTRAINT_NAME;
    -- Only this partial unique index means the vehicle already has a session.
    IF v_error_schema = 'public'
        AND v_error_table = 'parking_sessions'
        AND v_error_constraint = 'parking_sessions_one_active_per_vehicle' THEN
        RETURN jsonb_build_object('status', 'existing_active_session');
    END IF;
    RAISE; -- Preserve unrelated uniqueness errors instead of mislabelling them.
END;
$$;

-- Only the trusted backend service role may invoke this write operation.
REVOKE ALL ON FUNCTION public.reserve_parking_zone(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reserve_parking_zone(uuid, uuid) TO service_role;

COMMIT;
