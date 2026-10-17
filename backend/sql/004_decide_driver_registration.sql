-- MANUAL REVIEW/APPLICATION ONLY. Does not modify records during installation.
-- Review the read-only preflight in ADMIN_REGISTRATIONS.md before applying.
BEGIN;

CREATE FUNCTION public.decide_driver_registration(
    p_admin_id uuid, p_user_id uuid, p_decision text, p_tenant_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    v_admin public.users%ROWTYPE;
    v_user public.users%ROWTYPE;
    v_tenant public.tenants%ROWTYPE;
BEGIN
    IF p_decision IS NULL OR p_decision NOT IN ('approved', 'rejected')
        OR (p_decision = 'approved' AND p_tenant_id IS NULL)
        OR (p_decision = 'rejected' AND p_tenant_id IS NOT NULL) THEN
        RETURN jsonb_build_object('status', 'invalid_decision');
    END IF;

    -- Only the backend service role may execute this RPC. The actor UUID must
    -- come from the verified JWT, never from an HTTP request body.
    -- Hold the actor's permissions stable until the decision commits.
    SELECT * INTO v_admin FROM public.users WHERE id = p_admin_id FOR SHARE;
    IF NOT FOUND OR v_admin.role IS DISTINCT FROM 'admin'
        OR v_admin.approval_status IS DISTINCT FROM 'approved'
        OR v_admin.is_active IS DISTINCT FROM true THEN
        RETURN jsonb_build_object('status', 'forbidden');
    END IF;
    IF p_admin_id = p_user_id THEN
        RETURN jsonb_build_object('status', 'invalid_application');
    END IF;

    -- Competing decisions wait here, then observe the committed new state.
    SELECT * INTO v_user FROM public.users WHERE id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'not_found');
    END IF;
    IF v_user.role IS DISTINCT FROM 'driver' THEN
        RETURN jsonb_build_object('status', 'invalid_application');
    END IF;
    IF v_user.approval_status IS DISTINCT FROM 'pending'
        OR v_user.is_active IS DISTINCT FROM false OR v_user.tenant_id IS NOT NULL THEN
        RETURN jsonb_build_object('status', 'conflict');
    END IF;

    IF p_decision = 'approved' THEN
        IF v_user.full_name IS NULL OR btrim(v_user.full_name) = ''
            OR v_user.requested_tenant_id IS NULL THEN
            RETURN jsonb_build_object('status', 'incomplete_application');
        END IF;
        -- FOR SHARE blocks concurrent deactivation/deletion until commit.
        -- FOR KEY SHARE would not block a change to is_active.
        SELECT * INTO v_tenant FROM public.tenants WHERE id = p_tenant_id FOR SHARE;
        IF NOT FOUND OR v_tenant.is_active IS DISTINCT FROM true THEN
            RETURN jsonb_build_object('status', 'invalid_company');
        END IF;
    END IF;

    UPDATE public.users
        SET approval_status = p_decision,
            is_active = (p_decision = 'approved'),
            tenant_id = CASE WHEN p_decision = 'approved' THEN p_tenant_id ELSE NULL END,
            updated_at = clock_timestamp()
        WHERE id = p_user_id AND role = 'driver' AND approval_status = 'pending'
            AND is_active = false AND tenant_id IS NULL
        RETURNING * INTO v_user;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('status', 'conflict');
    END IF;
    RETURN jsonb_build_object(
        'status', v_user.approval_status, 'id', v_user.id,
        'approval_status', v_user.approval_status, 'is_active', v_user.is_active,
        'tenant_id', v_user.tenant_id);
END;
$$;

REVOKE ALL ON FUNCTION public.decide_driver_registration(uuid, uuid, text, uuid)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.decide_driver_registration(uuid, uuid, text, uuid)
    TO service_role;
COMMIT;
