-- MANUAL REVIEW/APPLICATION ONLY. Adds a function; no existing records changed.
BEGIN;

CREATE FUNCTION public.decide_vehicle_registration(
    p_admin_id uuid, p_vehicle_id uuid, p_decision text
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_admin public.users%ROWTYPE;
    v_vehicle public.vehicles%ROWTYPE;
BEGIN
    IF p_decision IS NULL OR p_decision NOT IN ('approved', 'rejected') THEN
        RETURN jsonb_build_object('status', 'invalid_decision');
    END IF;

    -- Actor comes from the verified JWT through the service-role backend.
    -- Hold administrator permissions stable for the entire transaction.
    SELECT * INTO v_admin FROM public.users WHERE id = p_admin_id FOR SHARE;
    IF NOT FOUND OR v_admin.role IS DISTINCT FROM 'admin'
        OR v_admin.approval_status IS DISTINCT FROM 'approved'
        OR v_admin.is_active IS DISTINCT FROM true THEN
        RETURN jsonb_build_object('status', 'forbidden');
    END IF;

    -- Competing decisions and reservation use this same vehicle row lock.
    SELECT * INTO v_vehicle FROM public.vehicles WHERE id = p_vehicle_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'not_found');
    END IF;
    IF v_vehicle.registration_status IS DISTINCT FROM 'pending' THEN
        RETURN jsonb_build_object('status', 'conflict');
    END IF;

    -- Assignment uses the column's own type (text/check or a PostgreSQL enum).
    v_vehicle.registration_status := p_decision;
    UPDATE public.vehicles
        SET registration_status = v_vehicle.registration_status, updated_at = clock_timestamp()
        WHERE id = p_vehicle_id AND registration_status = 'pending'
        RETURNING * INTO v_vehicle;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'conflict');
    END IF;
    RETURN jsonb_build_object('status', v_vehicle.registration_status,
        'id', v_vehicle.id, 'plate_number', v_vehicle.plate_number,
        'registration_status', v_vehicle.registration_status);
END;
$$;

REVOKE ALL ON FUNCTION public.decide_vehicle_registration(uuid, uuid, text)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.decide_vehicle_registration(uuid, uuid, text)
    TO service_role;
COMMIT;
