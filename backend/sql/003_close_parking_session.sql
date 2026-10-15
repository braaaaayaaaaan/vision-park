-- Apply manually. Adds a function only; does not modify existing records.
-- Existing constraints allow completed with exit_time and optional confirmation.
BEGIN;
CREATE FUNCTION public.close_parking_session(p_session_id uuid, p_vehicle_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_session public.parking_sessions%ROWTYPE;
    v_exit_time timestamptz;
BEGIN
    SELECT * INTO v_session FROM public.parking_sessions
        WHERE id = p_session_id AND vehicle_id = p_vehicle_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'session_not_found');
    END IF;
    IF v_session.status IS NULL OR v_session.status NOT IN ('allocated', 'occupied', 'completed') THEN
        RETURN jsonb_build_object('status', 'invalid_session_status');
    END IF;
    IF v_session.status = 'completed' THEN
        IF v_session.exit_time IS NULL THEN
            RETURN jsonb_build_object('status', 'invalid_session_state');
        END IF;
    ELSE
        IF v_session.exit_time IS NOT NULL
            OR (v_session.status = 'allocated' AND v_session.parking_confirmed_at IS NOT NULL)
            OR (v_session.status = 'occupied' AND v_session.parking_confirmed_at IS NULL) THEN
            RETURN jsonb_build_object('status', 'invalid_session_state');
        END IF;
        v_exit_time := clock_timestamp();
        -- Do not invent future exit times for inconsistent/future-dated records.
        IF v_exit_time < v_session.entry_time
            OR v_exit_time < v_session.parking_confirmed_at THEN
            RETURN jsonb_build_object('status', 'invalid_session_state');
        END IF;
        UPDATE public.parking_sessions SET status = 'completed', exit_time = v_exit_time
            WHERE id = v_session.id RETURNING * INTO v_session;
    END IF;
    -- Completed retries do not update timestamps or any capacity field.
    RETURN jsonb_build_object(
        'status', 'completed', 'parking_session_id', v_session.id,
        'vehicle_id', v_session.vehicle_id, 'zone_id', v_session.zone_id,
        'exit_time', v_session.exit_time);
END;
$$;
REVOKE ALL ON FUNCTION public.close_parking_session(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.close_parking_session(uuid, uuid) TO service_role;
COMMIT;
