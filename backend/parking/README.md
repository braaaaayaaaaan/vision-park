# Supabase, routing and zone allocation

## Start the application

From the repository root, activate the existing virtual environment and run the
unchanged command:

```powershell
uvicorn backend.main:app --reload
```

No new packages are required. `backend/main.py` remains the entry point. Neither
database queries nor ANPR inference run during startup. Existing ANPR imports
still load their Python libraries; the recognition pipeline is unchanged.

`backend/database.py` loads the root `.env` relative to its own file, independent
of the current working directory. Existing process environment settings take
precedence. It lazily creates and reuses one Supabase SDK client per process.
Restart after changing credentials. A copied URL ending in `/rest/v1` is accepted:
the suffix is removed in memory because the SDK appends it. `.env` is not edited.

Required existing backend variables: `SUPABASE_URL`, `SUPABASE_KEY`. For this
schema's RLS configuration and reservation RPC, use a trusted backend key with
the `service_role` database role, never a frontend/public key. Never expose this
key through Next.js or use it as the endpoint's allocation token.

## Components

- `backend/database.py`: direct reads for vehicles, users, tenants, permissions,
  zones, levels, graph and active sessions, plus the reservation RPC call.
  Collection reads are paginated; active session counts use exact counts rather
  than fetching a potentially truncated list. Errors do not echo SDK responses
  or credentials. Missing credentials affect database functionality only.
- `backend/routing/dijkstra.py`: `shortest_routes(nodes, edges, source_id)` uses
  `heapq` and decimal distances. It returns a `Route` per reachable node, including
  the source with distance zero. Unreachable nodes are absent. Active edges are
  directed; inactive edges are ignored. Invalid active edge weights/references
  are rejected. The algorithm allows nonnegative weights; the database schema
  imposes the stricter positive-distance constraint. It has no database imports.
- `backend/parking/allocation.py`: `rank_zones(...)` is pure snapshot-based
  selection. `allocate_parking(...)` loads records, checks registration and
  active user/tenant, rejects an existing active session, ranks eligible zones,
  then invokes the atomic reservation RPC. Distance ties use zone ID; equal
  shortest paths use stable node ordering.
- `backend/api/parking.py`: validated and protected development write endpoint.
- `backend/sql/001_reserve_parking_zone.sql`: pending, review-only migration.

Eligibility requires tenant permission, `operational_status = 'open'`, an active
parking level, and a zone entrance node of type `zone_entrance` on that same level.
Missing or inconsistent entrance mapping reports a configuration conflict rather
than silently recommending a route. The supplied source must have node type
`building_entrance`. Coordinates are metadata: weights come from
`distance_meters`, not straight-line coordinate distance.

Capacity is `total_capacity - unavailable_capacity - active_sessions`, where
each session with status `allocated` OR `occupied` counts exactly once. No bays
are selected or represented. Zone candidates with no capacity or no directed
route from the entrance are excluded.

## Review required before live allocations

The supplied V1 schema has no atomic allocation operation. The migration adds
only `public.reserve_parking_zone(p_vehicle_id uuid, p_zone_id uuid)`; it does not
recreate tables or alter existing records. It has NOT been applied automatically.

The function runs in the RPC transaction, locks the vehicle and then the zone,
rechecks registration, user/tenant activity, zone/level status, entrance mapping,
permission and active-session count, then inserts one `allocated` session.
It uses the database clock for `entry_time`; it does not infer a recorded-video
timestamp. User ID is derived from the registered vehicle, never supplied by an
API caller. The existing one-active-session-per-vehicle index remains in force.

The zone lock serialises competing reservations. The count occurs in a separate
statement after the lock, using PostgreSQL's default READ COMMITTED isolation.
The function is VOLATILE and SECURITY INVOKER, with execution restricted to
`service_role`; public, anon and authenticated execution are revoked. No RLS
policy is loosened. Review and apply the file through the Supabase SQL Editor
only when ready. A missing RPC produces HTTP 503; there is no unsafe insert
fallback. This migration intentionally uses CREATE FUNCTION, so it will not
silently overwrite a function already installed under the same signature.

All allocation writers must use this RPC. Direct privileged inserts, zone
transfers, reactivation of historical sessions, or administrative capacity
reductions can bypass this protocol and require their own matching locking and
validation if implemented later.

When the RPC reports a full, unavailable or no-longer-authorised candidate, Python
tries the next closest candidate from the snapshot. A duplicate active session
stops allocation. Network errors are not retried against another zone: a lost
response might follow a committed insert. Inspect active sessions before retrying;
the vehicle uniqueness constraint prevents a second active session.

## API usage

Existing endpoints remain `GET /` and `GET /anpr/test`. The latter runs real ANPR
inference. FastAPI documentation remains at `/docs` and `/openapi.json`.

New endpoint: `POST /parking/allocate`. It is disabled by default (HTTP 404) and
requires both of these optional backend settings to be deliberately configured:

```dotenv
PARKING_ALLOCATION_ENABLED=true
PARKING_ALLOCATION_TOKEN=<a-separate-random-development-secret>
```

These settings were not added to your `.env`. After configuring them, restart
Uvicorn. In `/docs`, use Authorize to supply the token as `X-Allocation-Token`.
This is a prototype development guard, not a driver/admin authentication system.
Keep the endpoint disabled when it is not needed; use HTTPS if accessed remotely.

Example request (replace the placeholders with an existing approved plate and
the UUID of a `building_entrance` node). **Running it after enabling the endpoint
and installing the RPC creates a real parking session.**

```http
POST /parking/allocate
Content-Type: application/json
X-Allocation-Token: <your-development-token>

{
  "plate_number": "<existing-approved-plate>",
  "entrance_node_id": "<building-entrance-uuid>"
}
```

Success: HTTP 201 with `plate_number`, `zone_id`, `zone_name`, `level_id`,
`level_name`, `level_number`, numeric `distance_meters`, ordered `route_node_ids`,
`parking_session_id`, and `status: "allocated"`.

Plates are trimmed and uppercased; punctuation, internal spaces, empty values and
non-ASCII plate characters are rejected. Node IDs must be UUIDs. Extra request
fields are rejected. Errors use FastAPI's `detail` envelope:

| HTTP | Typical cause |
| --- | --- |
| 403 | Invalid token, unapproved registration, inactive user/tenant, no permission |
| 404 | Endpoint disabled or unknown vehicle |
| 409 | Existing session, full/closed/unreachable zones, invalid graph mapping |
| 422 | Invalid request or selected source is not a building entrance |
| 503 | Missing backend settings, database unavailable, reservation RPC missing |

Domain/database error details include `code` and `message`; authentication guard
errors use a string detail, and request validation uses FastAPI's standard list.

## Tests and verification

Run the focused suite; do not broadly discover the older manual model demos:

```powershell
.\venv\Scripts\python.exe -B -m unittest discover -s tests/unit -v
```

New tests are in `test_database.py`, `test_dijkstra.py`, `test_allocation.py`, and
`test_parking_api.py`. They mock all database writes. Coverage includes directed
and disconnected graphs, inactive edges, precise distances, invalid weights,
permissions, capacity, nearest-zone selection, same-distance ties, eligibility
rejections, concurrent reservation result handling, fallback to another zone,
endpoint protection, request validation and startup without database credentials.

Verification on 2026-10-15:

- All 73 focused tests passed (37 existing ANPR tests and 36 new tests).
- The existing Uvicorn executable with `backend.main:app --reload` started;
  `GET /` returned 200 and OpenAPI included both ANPR and parking routes.
- Read-only Supabase queries retrieved 12 nodes, 24 edges, 6 zones and 3 levels.
- From the existing building entrance, Dijkstra reached all six zones with
  distances 55, 70, 170, 180, 285 and 300 metres.
- Reads for one existing approved vehicle, its active user/tenant, permissions,
  and session counts succeeded. Pure ranking found three eligible reachable
  zones; the nearest was 55 metres away. No reservation was attempted.
- No live parking session or ANPR event was created or modified. The SQL
  migration has not been applied. Real RPC execution and simultaneous database
  transaction contention remain untested pending migration review and explicit
  approval for write tests. Mocked conflict tests are not a database concurrency
  proof. No local PostgreSQL executable was available for isolated SQL testing.
- The installed Starlette test client emits a deprecation warning concerning
  httpx; the tests run successfully without dependency changes.

## Parking confirmation

Apply `backend/sql/002_confirm_parking_session.sql` manually through the Supabase
SQL Editor before using confirmation. It adds a service-role-only RPC using the
existing `parking_sessions` fields; no tables, columns or records are added or
changed by installing the function. The application never applies SQL files.
The complete table constraints are not checked into this repository; the fields
are evidenced by the existing live reservation report. Live schema compatibility
and function execution have not been verified for this change.

Use `POST /parking/sessions/{session_id}/confirm` with JSON
`{"vehicle_id": "<vehicle-UUID>"}` and the existing `X-Allocation-Token` header.
The existing `PARKING_ALLOCATION_ENABLED` and `PARKING_ALLOCATION_TOKEN` settings
also protect this endpoint. Startup remains `uvicorn backend.main:app --reload`.

`backend.parking.sessions.confirm_parking(session_id, vehicle_id)` is the reusable
service. The RPC locks the exact session/vehicle pair, changes `allocated` to
`occupied`, and sets `parking_confirmed_at` with database time. Repeating the
request for an already occupied session returns the original timestamp without
an update. Both statuses consume one capacity unit, so confirmation neither
reserves additional space nor releases space. No allocation or routing changes
are involved. Existing triggers may maintain `updated_at` on the first update.

Success is HTTP 200 with `parking_session_id`, `vehicle_id`, `zone_id`,
`status: occupied` and `parking_confirmed_at`. Invalid UUIDs return 422; an unknown
session or mismatched vehicle returns 404. Inactive/exited sessions and
inconsistent confirmation timestamps return 409. Database/RPC failures return
503 with no automatic retry or non-atomic fallback.

The caller-supplied vehicle ID is a consistency check, not authentication.
A future driver API must enforce ownership using authenticated identity before
calling this service. No frontend, exit handling or session closure is included.

Validation: 93 local unit tests passed, including 11 confirmation tests. Database
responses are mocked; SQL execution, actual concurrent confirmations and live
schema constraints remain unverified. No Supabase records were modified in tests.

## Parking session closure

Apply `backend/sql/003_close_parking_session.sql` manually in Supabase. This adds
the `close_parking_session(uuid, uuid)` service-role RPC without modifying existing
records. It has not been executed by the application or during local tests.
The supplied database CHECK constraints establish `completed` as a valid status
requiring `exit_time`; confirmation is optional for completed sessions.

Use `POST /parking/sessions/{session_id}/close` with
`{"vehicle_id": "<vehicle-UUID>"}`. The existing allocation enable flag and
`X-Allocation-Token` protection apply. The reusable service is
`backend.parking.sessions.close_parking(session_id, vehicle_id)`.

The RPC locks the exact session/vehicle pair and changes either `allocated` or
`occupied` to `completed`, recording database time in `exit_time`. It preserves
`parking_confirmed_at`, including null for an unconfirmed departure. Completed
retries return the original exit timestamp without updating the row. Cancelled
sessions and inconsistent/future-dated active records are rejected. No capacity
counter is changed: completed sessions no longer match the existing
`allocated`/`occupied` active-count filter, releasing one unit of zone capacity.

HTTP 200 returns `parking_session_id`, `vehicle_id`, `zone_id`, `status: completed`
and `exit_time`. Invalid UUIDs return 422; an unknown session or mismatched vehicle
returns 404; inappropriate status or timestamp state returns 409. Database errors
return 503 with no automatic retries or non-atomic fallback. A future driver API
must enforce ownership; supplied vehicle IDs are not authentication. Exit ANPR
integration is not included. Startup remains `uvicorn backend.main:app --reload`.

All 104 local unit tests passed, including 11 new closure tests. These exercise
service/API contracts, repeated/concurrent callers with mocked RPC responses,
failure handling and existing ranking after a session becomes inactive. They do
not execute SQL or prove database concurrency. No local PostgreSQL runtime was
available, and no Supabase records were changed. After installing the RPC,
database verification remains necessary for allocated/occupied closure,
timestamp preservation on retries, cancelled-session rejection, simultaneous
closures and active-count reduction, using separately approved test records.

## Entrance ANPR integration

`POST /anpr/entrance` runs `data/videos/entrance.mp4` synchronously and processes
each confirmed event immediately. Start with `uvicorn backend.main:app --reload`
as before. Set the existing `PARKING_ALLOCATION_ENABLED=true` and
`PARKING_ALLOCATION_TOKEN` settings, and supply `X-Allocation-Token` in `/docs`.
The request body is:

```json
{"entrance_node_id": "<existing-building-entrance-node-UUID>"}
```

The request explicitly maps camera `recorded-entrance` to that graph node.
This operation creates real reservations using the existing installed RPC and
backend Supabase credentials. The existing `GET /anpr/test` remains a
recognition-only demo; startup itself does not replay videos or reserve parking.

Flow: `ANPRPipeline.run()` -> `EntranceEventHandler` -> `allocate_parking()` ->
existing eligibility checks, Dijkstra ranking and `reserve_parking_zone` RPC.
Each item in `results` contains all six original event fields under `event`,
plus a status. Successful items contain the unmodified service result under
`allocation`, including zone, level, route, distance and session ID. Rejections
contain the existing service error code/message and do not stop later events.
Exit events are ignored. Database failures are returned per event without an
automatic retry, because the reservation may already have committed.

The handler is also callable as `CameraManager(on_plate_confirmed=handler)`;
construct it with an explicit `{camera_id: building_entrance_node_id}` mapping.
The manager discards callback return values, so wrap the handler if its results
need to be collected. Keep one handler for a finite recording run. Its event-ID
set is in memory, serialised for concurrent callbacks, and grows with the run.
It is not a durable ledger. Replays produce new event IDs; active-session checks,
RPC vehicle locking and the existing unique index prevent another active session
even across processes. Old events replayed after a session is closed are not
durably deduplicated; session closure is outside this integration.

All ANPR metadata is preserved in the result envelope. The checked-in database
interface/RPC exposes no event metadata storage, so no speculative columns or
tables are written. `entry_time` remains the RPC database time; a video offset
is not treated as a real-world entry time.

Validation: 82 unit tests passed, including 9 new entrance integration tests,
using mocked inference/database boundaries. No real-video-to-Supabase end-to-end
run was performed for this change. Live OCR, registered plates, entrance mapping
and the installed RPC must be verified together before claiming that validation.

Durable event persistence, simulation chronology, cancellation and reservation
expiry remain unimplemented. Confirmation and explicit session closure are now
available as described above; exit ANPR is not connected to closure. Allocated
sessions consume capacity until explicitly closed; no automatic expiry exists.

Graph and display metadata are read snapshots. Reservation eligibility and
capacity are rechecked atomically, but routes are not locked/versioned against
concurrent layout edits. Keep the layout stable while allocating in this
prototype; coordinated edits or graph versioning would be needed later. Zone
eligibility checks active levels; there is no additional rule forbidding transit
through an inactive level—administrators must deactivate the relevant edges.

Official references used:
- https://supabase.com/docs/reference/python/initializing
- https://supabase.com/docs/reference/python/select
- https://supabase.com/docs/reference/python/rpc
- https://supabase.com/docs/guides/database/functions
- https://fastapi.tiangolo.com/tutorial/body/
- https://www.postgresql.org/docs/current/explicit-locking.html
