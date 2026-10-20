# Recorded exit ANPR

`POST /anpr/exit` processes `data/videos/exit.mp4` using the existing
`ANPRPipeline`, camera ID `recorded-exit`, and role `exit`. No request body,
session ID, vehicle ID, or entrance node is required. The existing
`PARKING_ALLOCATION_ENABLED` flag and `X-Allocation-Token` guard apply before
model creation. Start from the repository root as before:

```powershell
uvicorn backend.main:app --reload
```

`ExitEventHandler` accepts a configured set of exit camera IDs. It resolves the
plate with `get_vehicle()`, finds the active session with `get_active_session()`,
checks the returned vehicle/status, and invokes `close_parking()` with that exact
session/vehicle pair. It does not check current registration, user, or tenant
eligibility. It never allocates or routes a vehicle.

The existing closure service and RPC 003 remain unchanged: allocated or occupied
sessions become completed, database time supplies `exit_time`, confirmation time
is preserved, and repeated closure of the same pair preserves the original exit
time. Completed sessions stop counting toward capacity; no counter is incremented.

## Results and failures

HTTP 200 returns `{"results": [...]}`. Each item preserves the recognition event:

| Status | Meaning |
| --- | --- |
| `completed` | Includes the existing service result under `closure`. |
| `duplicate` | `duplicate_event` or `duplicate_vehicle`; no additional closure. |
| `ignored` | `not_exit`. |
| `rejected` | `unmapped_camera`, `invalid_event`, `unknown_vehicle`, `no_active_session`, or a closure service rejection code. |
| `error` | `database_unavailable`; the write outcome may be uncertain. |

Resolved vehicle/session IDs are retained and returned when available, including
on closure errors and subsequent duplicate detections. Expected per-event errors
do not stop other vehicles. No automatic retry occurs. A model/capture/processing
exception returns HTTP 503 with `detail.code = anpr_processing_failed` and partial
`detail.results`. Earlier closures may already have committed. Raw exception text
is not exposed. The recording generator is closed on completion or failure; the
existing pipeline releases capture in its `finally` block.

## Duplicate scope and demonstration safety

One handler is created per request. A lock serialises its deliveries. Event IDs,
attempted plates and resolved vehicles are remembered before further I/O; a
resolved session pair is pinned before closure. A failed attempt is also
suppressed for the remainder of that run. Different tracks cannot trigger a new
active-session lookup for the same vehicle after an ambiguous closure failure.
To reconcile such a failure, inspect the returned exact pair. If necessary,
explicitly retry that pair through the existing manual closure endpoint, whose
RPC is idempotent. Do not replay a video as a retry mechanism.

This is NOT cross-request, cross-session, or cross-restart replay protection.
Replaying an old exit recording after re-entry can close a newer session. Fresh
recognition UUIDs do not establish a new real-world exit. Run one controlled
entrance/confirmation/exit sequence at a time, without simultaneous entrance or
exit replays, and inspect results before starting another demonstration. Use a
fresh intended sequence after re-entry, not an old exit request retry.

Recognition events are not persisted to `anpr_events`. Recording offsets are not
used as real-world exit timestamps. SQL deployment, schema constraints and real
video accuracy require separate verification; mocked tests do not prove them.

## Manual verification (writes require approval)

1. Use approved test records and confirm RPC 003 is already installed. Identify
   every plate in the exit clip and ensure its active session belongs to the
   intended demonstration. Avoid shared/live parking sessions.
2. With the development guard configured, open `/docs`, authorise with the
   separate allocation token, and inspect the intended active session in Supabase.
   Record its ID, vehicle ID, zone ID, status, and `parking_confirmed_at`. Record
   the zone's current allocated/occupied session count. Do not publish credentials.
3. Execute `POST /anpr/exit` once with no body. Inspect every result, including
   rejections/errors. A successful result has `status: completed`, the expected
   session/vehicle IDs, and a timezone-aware exit time under `closure`.
4. Inspect that same Supabase session: status must be completed, exit time populated,
   confirmation time unchanged, vehicle/zone unchanged. Test both an allocated
   departure and an occupied departure using separate approved sequences.
5. Run the read-only queries below with the actual IDs. With no concurrent activity,
   the zone's active count drops by one for each successfully completed session.
   Total/unavailable capacity fields remain unchanged. The released place follows
   from the existing formula, not an additional database update.
6. If verifying idempotency, repeat the manual closure endpoint for the same exact
   session/vehicle pair and check that exit time and active count do not change.
   Do not allocate a new session and replay an old exit clip to test duplicates.

```sql
SELECT id, vehicle_id, zone_id, status, entry_time, parking_confirmed_at, exit_time
FROM public.parking_sessions
WHERE id = '<session-uuid>';

SELECT z.id, z.total_capacity, z.unavailable_capacity,
       count(s.id) AS active_sessions,
       z.total_capacity - z.unavailable_capacity - count(s.id) AS available_capacity
FROM public.parking_zones z
LEFT JOIN public.parking_sessions s
  ON s.zone_id = z.id AND s.status IN ('allocated', 'occupied')
WHERE z.id = '<zone-uuid>'
GROUP BY z.id, z.total_capacity, z.unavailable_capacity;
```

Automated verification uses mocked database/inference boundaries:

```powershell
.\venv\Scripts\python.exe -B -m unittest discover -s tests/unit -v
```
