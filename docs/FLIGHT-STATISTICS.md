# Flight statistics

Current-source feature, 2026-10-25. This guide describes the implementation; the [design and remaining acceptance gates](flight-statistics-plan.md) retain the UI-FS requirements and test matrix. Statistics are local to this installation's pilot profile, with no login or cloud synchronization.

## Using statistics

Open **Home → Statistics · Pilot total**, **Aircraft → Aircraft statistics**, or **Pause → Statistics**. Choose All aircraft or a recorded aircraft, then This session, Lifetime history, or Since counter reset. The first cards show airborne time, completed flights and successful landings. More statistics and history expand separately, with the newest records first.

Successful landings include confirmed touch-and-goes and full stops. A touch-and-go does not complete the flight. Touchdown success uses successful and failed resolved contact episodes; unknown contacts are excluded. The adjacent clean-stop fraction and crash count explain why a high touchdown rate can coexist with an eventual crash. An air start starts a flight but earns no takeoff credit.

**Pause → Flight overlays → Session statistics** enables the optional three-counter widget: successful landings, crashes and restarts. Its scope is either all aircraft or this aircraft, always for this session. Existing overlay position, size, opacity, compactness and layout-lock controls apply. Changing visibility or presets never resets statistics. Flight data distinguishes elapsed simulation time from session airborne time.

Returning to Home and switching aircraft retain the session. A clean application exit closes it; the next launch starts a new session. Recovery after an interrupted application retains the previous session, closes its saved active flight as interrupted/partial and preserves only acknowledged observations. It does not infer airborne time from the wall clock.

## Eligible activities and classification

Production Home fixed-wing routes are recorded, including air starts, Natural Random and failure practice. Catalog IDs identify aircraft; names and configuration hashes are captured with records. Rotorcraft, RC cars, companions, direct technical/replay routes and Workshop trials do not contribute. Entering a Workshop trial detaches the observer while preserving the paused parent flight; returning reattaches it once. Saved Workshop variants and optional practice goals are not enabled in this slice.

The observer lives outside the simulation kernel. `fixed_wing_adapter.gd` reads accepted 240 Hz state, gear compression, terrain, air data and session contact evidence. `profiles.gd` explicitly maps the reviewed fleet's main and stop supports and checks their accepted geometry. Changed or unknown support geometry disables landing credit instead of guessing. The pure detector applies the [metric and event rules](flight-statistics-plan.md#4-flight-event-rules): takeoff confirmation/backfill, support hysteresis, controlled contact, stop dwell, touch-and-go rearm, generation-wide incident latches and one crash per generation. Unsupported ticks alone contribute airborne time; pause/ground time does not.

**Rules v2 includes survivable gear-up accidents in the crash count.** Accepted hull contact with installed retractable gear short of its fully-down endpoint records an accident even when the airplane keeps sliding or flying. Repeated scraping and brief bounce recontacts share one incident; a later terminal escalation does not add another crash. A quiet damaged hull stop can close the flight as `damaged_stop`, without a successful landing. The counter remains limited to one crash per activity generation; distinct later semantic incidents are not extra M7 counts. Cause (pilot choice, failure or incomplete extension) and structural damage are not inferred from contact configuration. [GP-14a implementation and checks](research/ground-physics/GP-14/README.md).

New records retain `flight-statistics-rules-v2`; older records retain their original rules and terminal-only crash coverage. V1 detector checkpoints remain readable without fabricated historical accidents. The persistence service namespaces incident IDs by its activity UUID; the physical receipt's session generation remains a local counter. Statistical classification never calls the physics crash/pause path.

Maximum true airspeed and horizontal groundspeed are separate, validated sustained values. Spike/discontinuity rejection and pending windows prevent isolated collision impulses from becoming personal bests. Neither maximum awards points. `failed_stop` is the explicit terminal result for a stopped aircraft that fails controlled-landing criteria without a confirmed damage incident; it is neither a completion nor a successful landing.

Successful session lifecycle receipts count restarts only after reset/reload commits. Failed reload rollback leaves statistics intact. Physics-only checkpoint restoration ends the current observation as interrupted and disables recording until Restart, preventing replayed time from being credited twice.

## Counter windows and history

Management is available from Home while no flight is active. Session reset opens a new session; aircraft reset advances only that aircraft's counter window; pilot reset advances only the combined pilot window. Every reset preserves lifetime history and unrelated counter windows. A pilot counter total and independently reset aircraft counter totals intentionally need not add up; lifetime totals use the same retained ledger and do reconcile.

History deletion is a separate operation, with a scope/count/date preview, a deletion acknowledgement and Cancel initially focused. Aircraft deletion leaves other aircraft records intact and adds continuity gaps so deleting a crash cannot manufacture a streak. Pilot deletion removes all retained flight history. Preferences, aircraft files, Workshop builds, radio profiles and `.orfl` recordings remain untouched.

## Storage and implementation boundaries

`app/statistics/service.gd` is owned by AppRoot rather than a flight scene. It connects and disconnects the adapter, owns the local session, assembles bounded event details and exposes reducer queries. HUD summaries cache event aggregates and add current-flight scalar deltas; they do not copy history every rendered update.

`user://flight_statistics/` contains schema-version-1, checksummed, object-free native snapshots in two alternating slots. Validation covers identifiers, record/session relationships, numbers, bounds and nested checkpoint data. A single-writer lock prevents two processes from overwriting one another. Future/unsupported schemas are protected rather than replaced. This is the first statistics schema: no older player statistics are fabricated. Subsequent metric migrations must preserve missing coverage explicitly.

Automatic checkpoints are requested at events, holds and at most five simulated seconds since the last acknowledged checkpoint. One low-priority background writer serializes validation, encoding and disk I/O; published records are immutable while the worker reads them. The service copies mutable root containers, retains newly observed live data when an older snapshot completes, and joins the worker before reset, deletion, teardown or synchronous final save. Actual loss after interruption depends on the last completed write, not a guaranteed five-second wall-clock limit.

Deletion commits a durable fence before publishing the surviving records and purging the older slots. Recovery cannot fall back across that fence and resurrect deleted history. If surviving data are unavailable, the store stays protected and reports the problem. Failed final saves preserve the active observation and offer Retry, Cancel or explicit departure without the unsaved changes; the simulation remains held during that choice.

Implementation bounds: 100,000 ledger records, 10,000 sessions, a 64 MiB snapshot, and 128 detailed events per flight (later events still update counters and increment the omitted-detail count). The snapshot store is an initial alternative to the plan's segmented journal. It never silently discards records to stay within bounds. Limit/write errors remain visible and require user action.

## Verification and remaining qualification

Focused checks cover pure flight detection, scoped formulas, reset isolation, snapshot corruption, future schemas, writer contention, deletion fencing, background writes, lifecycle rollback/recovery, exact physics-state noninterference and repeated attachment. UI tests cover scope/period filters, paged history, safe confirmations and the optional HUD. Final run counts and integration evidence belong in the [implementation phases](flight-statistics-plan.md#8-implementation-phases).

Large-history performance is **not qualified**. On the development Windows host (Ryzen 9 5900X, Godot 4.8-beta1), five 10,000-record synchronous commits took 3.118–5.802 seconds, p50 3.764 seconds and nearest-rank p95/p99 5.802 seconds. This motivated the background automatic writer. Explicit final saves, resets/deletion, initial reads and full-history queries still do work proportional to retained history; they do not meet the plan's 2 ms stall gate. Incremental indexing/pagination and asynchronous management transactions remain necessary before claiming A10 at that size.

Native 1920×1080 captures at 100% and 200% text were inspected: the statistics screen keeps its filters, Back action and essential cards readable without horizontal scrolling. The flight widget was exercised through the existing overlay settings. These checks do not establish formal contrast, every device/resolution or human in-flight readability. Beginner/experienced-pilot comprehension, physical landing validation, target-hardware performance and packaged upgrade preservation remain separate release gates. Optional goals, acknowledgements and milestones remain UI-FS-07 work; current streaks and bests are descriptive statistics only.
