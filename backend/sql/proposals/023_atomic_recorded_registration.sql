-- PROPOSAL ONLY. Do not apply to deployed Supabase without approval.
-- Requires the existing 022 functions supplied by the project owner.
-- Existing registration validation is split into fixed diagnostic categories;
-- its predicates and admission/payment behavior are retained. No table, RLS
-- policy, trigger or constraint is changed.
-- Revised for complete multi-vehicle recordings: one receipt set, no
-- continuation permission and no feature-flag-dependent database path.
BEGIN;

DO $preflight$
BEGIN
    IF to_regprocedure('public.begin_anpr_playback(uuid,text,text)') IS NULL
        OR to_regprocedure('public.register_parking_anpr_event(text,text,text,text,timestamptz,numeric,uuid,boolean)') IS NULL THEN
        RAISE EXCEPTION 'Expected ANPR registration contract is not installed';
    END IF;
    IF to_regprocedure('public.register_recorded_parking_anpr_event(text,text,text,text,timestamptz,numeric,uuid,text,boolean)') IS NOT NULL THEN
        RAISE EXCEPTION 'Earlier draft RPC is installed; review compatibility before applying this revised proposal';
    END IF;
    IF to_regprocedure('public.register_recorded_parking_anpr_events(uuid,text,text,jsonb)') IS NOT NULL THEN
        RAISE EXCEPTION 'Earlier batch draft is installed; review its replacement before applying this proposal';
    END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.register_parking_anpr_event(
    p_event_id text, p_plate_number text, p_camera_id text, p_camera_role text,
    p_event_time timestamptz, p_source_time_seconds numeric DEFAULT NULL,
    p_playback_id uuid DEFAULT NULL, p_allow_create boolean DEFAULT true
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO '' SET row_security TO 'off' SET lock_timeout TO '5s'
AS $function$
DECLARE e public.anpr_events%ROWTYPE; started timestamptz; inserted boolean := false;
BEGIN
    PERFORM visionpark_payments.gate();
    IF p_event_id IS NULL OR length(p_event_id) NOT BETWEEN 1 AND 256 THEN
        RAISE EXCEPTION 'Invalid trusted event identity' USING ERRCODE='22023'; END IF;
    IF p_plate_number IS NULL OR p_plate_number !~ '^[A-Z0-9]{1,32}$' THEN
        RAISE EXCEPTION 'Invalid trusted plate format' USING ERRCODE='22023'; END IF;
    IF p_camera_id IS NULL OR length(btrim(p_camera_id)) NOT BETWEEN 1 AND 100 THEN
        RAISE EXCEPTION 'Invalid trusted camera identity' USING ERRCODE='22023'; END IF;
    IF p_camera_role IS NULL OR p_camera_role NOT IN ('entrance','exit') THEN
        RAISE EXCEPTION 'Invalid trusted camera role' USING ERRCODE='22023'; END IF;
    IF p_allow_create IS NULL THEN
        RAISE EXCEPTION 'Invalid trusted creation permission' USING ERRCODE='22023'; END IF;
    IF p_event_time IS NULL OR NOT isfinite(p_event_time) THEN
        RAISE EXCEPTION 'Invalid trusted event timestamp' USING ERRCODE='22023'; END IF;
    IF p_event_time > clock_timestamp() THEN
        RAISE EXCEPTION 'Recognition timestamp is ahead of database clock' USING ERRCODE='22023'; END IF;
    IF p_source_time_seconds IS NOT NULL AND (p_source_time_seconds < 0
        OR round(p_source_time_seconds,3) > 999999999.999
        OR p_source_time_seconds::text IN ('NaN','Infinity','-Infinity')) THEN
        RAISE EXCEPTION 'Invalid trusted recording offset' USING ERRCODE='22023'; END IF;
    IF p_playback_id IS NOT NULL THEN
        SELECT started_at INTO started FROM public.anpr_playbacks
            WHERE playback_id=p_playback_id AND camera_role=p_camera_role;
        IF NOT FOUND THEN RAISE EXCEPTION 'Register playback first' USING ERRCODE='22023'; END IF;
    END IF;
    SELECT * INTO e FROM public.anpr_events WHERE event_id=p_event_id FOR UPDATE;
    IF NOT FOUND THEN
        IF NOT p_allow_create THEN RETURN jsonb_build_object('status','unrecorded_replay'); END IF;
        IF started IS NOT NULL AND p_event_time < started THEN
            RAISE EXCEPTION 'Confirmation precedes playback start' USING ERRCODE='22023'; END IF;
        INSERT INTO public.anpr_events(event_id,plate_number,camera_id,camera_role,
            event_time,source_time_seconds,playback_id,processing_result)
        VALUES(p_event_id,p_plate_number,p_camera_id,p_camera_role,p_event_time,
            p_source_time_seconds,p_playback_id,
            '{"contract":"visionpark-anpr-v1","stage":"registered"}')
        ON CONFLICT(event_id) DO NOTHING;
        inserted := FOUND;
        SELECT * INTO e FROM public.anpr_events WHERE event_id=p_event_id FOR UPDATE;
    END IF;
    IF (e.plate_number,e.camera_id,e.camera_role,e.playback_id) IS DISTINCT FROM
        (p_plate_number,p_camera_id,p_camera_role,p_playback_id)
        OR e.processing_result->>'contract' IS DISTINCT FROM 'visionpark-anpr-v1' THEN
        RETURN jsonb_build_object('status','event_conflict'); END IF;
    RETURN jsonb_build_object('status','registered','event',to_jsonb(e),'recovered',NOT inserted);
END;
$function$;

CREATE OR REPLACE FUNCTION public.register_recorded_parking_anpr_events(
    p_playback_id uuid,
    p_camera_role text,
    p_source_fingerprint text,
    p_events jsonb,
    p_action text DEFAULT 'start'
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
SET row_security TO 'off'
SET lock_timeout TO '5s'
AS $function$
DECLARE
    playback jsonb;
    result jsonb;
    item jsonb;
    saved jsonb;
    requested_count integer;
    stored_fingerprint text;
    existing boolean;
BEGIN
    PERFORM visionpark_payments.gate();
    IF p_playback_id IS NULL OR p_camera_role IS NULL
        OR p_camera_role NOT IN ('entrance','exit')
        OR p_action IS NULL OR p_action NOT IN ('start','retry')
        OR p_source_fingerprint IS NULL OR p_source_fingerprint !~ '^[a-f0-9]{64}$'
        OR jsonb_typeof(p_events) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'Invalid recorded recognition context' USING ERRCODE='22023';
    END IF;
    requested_count := jsonb_array_length(p_events);
    IF requested_count NOT BETWEEN 0 AND 1000 THEN
        RAISE EXCEPTION 'Use a bounded recording recognition set' USING ERRCODE='22023';
    END IF;
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(p_events) AS r(item)
        WHERE jsonb_typeof(r.item) IS DISTINCT FROM 'object'
            OR jsonb_typeof(r.item->'event_id') IS DISTINCT FROM 'string'
            OR jsonb_typeof(r.item->'plate_number') IS DISTINCT FROM 'string'
            OR jsonb_typeof(r.item->'camera_id') IS DISTINCT FROM 'string'
            OR (r.item->'source_time_seconds' IS NOT NULL
                AND jsonb_typeof(r.item->'source_time_seconds') NOT IN ('number','null')))
        OR (SELECT count(DISTINCT r.item->>'event_id') FROM jsonb_array_elements(p_events) AS r(item)) <> requested_count
        OR (SELECT count(DISTINCT r.item->>'plate_number') FROM jsonb_array_elements(p_events) AS r(item)) <> requested_count THEN
        RAISE EXCEPTION 'Invalid or duplicate recorded recognition identities' USING ERRCODE='22023';
    END IF;

    -- Serialize a complete recording receipt. All event inserts and a new
    -- playback commit together, or roll back together. No admission occurs here.
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        p_playback_id::text || ':' || p_camera_role, 0));
    SELECT source_fingerprint INTO stored_fingerprint FROM public.anpr_playbacks
        WHERE playback_id=p_playback_id AND camera_role=p_camera_role FOR UPDATE;
    existing := FOUND;
    IF existing AND stored_fingerprint IS DISTINCT FROM p_source_fingerprint THEN
        RETURN jsonb_build_object('status','playback_conflict');
    END IF;
    IF p_action='retry' AND NOT existing THEN
        RETURN jsonb_build_object('status','playback_not_found');
    END IF;
    IF p_action='start' AND existing THEN
        RETURN jsonb_build_object('status','playback_exists');
    END IF;
    IF p_action='start' AND requested_count=0 THEN
        RETURN jsonb_build_object('status','no_recognition','events','[]'::jsonb);
    END IF;
    IF p_action='start' THEN
        playback := public.begin_anpr_playback(
            p_playback_id, p_camera_role, p_source_fingerprint);
        IF playback->>'status' = 'playback_conflict' THEN RETURN playback; END IF;
        IF playback->>'status' = 'recovered' THEN
            -- Fail closed if a legacy writer created this key concurrently.
            RETURN jsonb_build_object('status','playback_exists');
        END IF;
        IF playback->>'status' IS DISTINCT FROM 'created' THEN
            RAISE EXCEPTION 'Invalid playback result' USING ERRCODE='22023';
        END IF;
        FOR item IN SELECT value FROM jsonb_array_elements(p_events)
            WITH ORDINALITY AS batch(value, position) ORDER BY batch.position LOOP
            -- SQL acceptance time is authoritative for session/billing time.
            -- The original registration predicates and payment gate still run.
            result := public.register_parking_anpr_event(
                item->>'event_id', item->>'plate_number', item->>'camera_id',
                p_camera_role, pg_catalog.clock_timestamp(),
                (item->>'source_time_seconds')::numeric, p_playback_id, true);
            IF result->>'status' IS DISTINCT FROM 'registered' THEN
                RAISE EXCEPTION 'Initial recorded event was not registered' USING ERRCODE='22023';
            END IF;
        END LOOP;
    END IF;

    SELECT coalesce(jsonb_agg(to_jsonb(e) ORDER BY e.event_time,e.event_id), '[]'::jsonb)
        INTO saved FROM (
            SELECT * FROM public.anpr_events
            WHERE playback_id=p_playback_id AND camera_role=p_camera_role
            ORDER BY event_id FOR UPDATE
        ) AS e;
    IF jsonb_array_length(saved)=0 THEN
        -- Historical empty playbacks have no saved recognition to recover.
        -- Never treat them as permission to recognise a new visit now.
        RETURN jsonb_build_object('status','unrecorded_replay');
    END IF;
    IF EXISTS(SELECT 1 FROM jsonb_array_elements(saved) AS r(item)
        WHERE r.item->'processing_result'->>'contract' IS DISTINCT FROM 'visionpark-anpr-v1') THEN
        RETURN jsonb_build_object('status','event_conflict');
    END IF;
    -- A retry's OCR output is NOT a new registration request. Recover the first
    -- saved set in full, including plates a later OCR pass missed or misread.
    RETURN jsonb_build_object('status','registered','events',saved,
                             'recovered',p_action='retry');
END;
$function$;

REVOKE ALL ON FUNCTION public.register_recorded_parking_anpr_events(
    uuid,text,text,jsonb,text
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.register_recorded_parking_anpr_events(
    uuid,text,text,jsonb,text
) TO service_role;

-- These are trusted backend writes too. Keeping PUBLIC's default EXECUTE would
-- expose a second registration path outside the recorded-run API contract.
REVOKE ALL ON FUNCTION public.begin_anpr_playback(uuid,text,text),
    public.register_parking_anpr_event(text,text,text,text,timestamptz,numeric,uuid,boolean)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.begin_anpr_playback(uuid,text,text),
    public.register_parking_anpr_event(text,text,text,text,timestamptz,numeric,uuid,boolean)
    TO service_role;

DO $ownership$
DECLARE routine regprocedure;
BEGIN
    IF (SELECT proowner FROM pg_proc WHERE oid='public.register_recorded_parking_anpr_events(uuid,text,text,jsonb,text)'::regprocedure)
        IS DISTINCT FROM
       (SELECT proowner FROM pg_proc WHERE oid='public.register_parking_anpr_event(text,text,text,text,timestamptz,numeric,uuid,boolean)'::regprocedure) THEN
        RAISE EXCEPTION 'Recorded RPC must have the reviewed registration owner';
    END IF;
    FOREACH routine IN ARRAY ARRAY[
        'public.begin_anpr_playback(uuid,text,text)'::regprocedure,
        'public.register_parking_anpr_event(text,text,text,text,timestamptz,numeric,uuid,boolean)'::regprocedure,
        'public.register_recorded_parking_anpr_events(uuid,text,text,jsonb,text)'::regprocedure
    ] LOOP
        IF EXISTS(SELECT 1 FROM pg_proc AS p,
            LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) AS privilege
            WHERE p.oid=routine AND privilege.privilege_type='EXECUTE'
                AND privilege.grantee NOT IN (p.proowner, 'service_role'::regrole::oid)) THEN
            RAISE EXCEPTION 'Unexpected registration EXECUTE grant; review permissions before deployment';
        END IF;
    END LOOP;
END;
$ownership$;

COMMIT;
