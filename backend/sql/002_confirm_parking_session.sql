-- Apply manually in Supabase. Adds a function only; no tables or data changed.
BEGIN;

CREATE FUNCTION public.confirm_parking_session(p_session_id uuid, p_vehicle_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_session public.parking_sessions%ROWTYPE;
BEGIN
    -- Serialise confirmations and concurrent updates to this exact session.
    SELECT * INTO v_session FROM public.parking_sessions
        WHERE id = p_session_id AND vehicle_id = p_vehicle_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'session_not_found');
    END IF;
    IF v_session.exit_time IS NOT NULL OR v_session.status IS NULL
        OR v_session.status NOT IN ('allocated', 'occupied') THEN
        RETURN jsonb_build_object('status', 'invalid_session_status');
    END IF;
    -- Reject inconsistent records instead of silently repairing their history.
    IF (v_session.status = 'allocated' AND v_session.parking_confirmed_at IS NOT NULL)
        OR (v_session.status = 'occupied' AND v_session.parking_confirmed_at IS NULL) THEN
        RETURN jsonb_build_object('status', 'invalid_session_state');
    END IF;
    IF v_session.status = 'allocated' THEN
        UPDATE public.parking_sessions
            SET status = 'occupied', parking_confirmed_at = clock_timestamp()
            WHERE id = v_session.id
            RETURNING * INTO v_session;
    END IF;
    -- An already occupied session is a successful no-op, including timestamps.
    RETURN jsonb_build_object(
        'status', 'occupied', 'parking_session_id', v_session.id,
        'vehicle_id', v_session.vehicle_id, 'zone_id', v_session.zone_id,
        'parking_confirmed_at', v_session.parking_confirmed_at);
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_parking_session(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_parking_session(uuid, uuid) TO service_role;
COMMIT;
