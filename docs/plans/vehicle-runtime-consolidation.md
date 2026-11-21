# Vehicle runtime consolidation — architecture and incremental refactoring plan

**Date:** 2026-11-21. **Status:** proposal only; no runtime implementation. **Planning branch:** `plan/vehicle-runtime-consolidation-2026-11-21`. **Inspected source:** `main` at `57abea025f62b20233ca281d58d2acbee4ab8b8e`. **Planning steps:** VRC-00…VRC-11. **Primary scope:** the fixed-wing aircraft fleet; helicopter, airship and multirotor activity integration after the common contracts are proven. Experimental ground vehicles are an explicitly gated, secondary consumer.

## 1. Engineering decision

**Unify invariant behavior, not different physical systems.** OpenRC already has a shared float64, 240 Hz `Simulation` kernel and a `VehicleModel` callback contract. Aircraft v2 uses one strict contract and `AircraftModules` registry. Retain these authorities rather than create a competing engine, “universal aircraft base class,” generic solver, second capability registry or new game framework.

The practical debt is **coordination across large sessions and activity entry points**. At this inspected revision `app/sim/flight_session.gd` has 6,698 lines and 339 top-level function declarations; `app/main.gd` has 4,304 lines and `app/app_root.gd` has 5,338. These are scope indicators from a source scan, **not** measured performance defects or proof of duplicated algorithms. The helicopter, quad, airship and ground sessions independently provide lifecycle operations; their preconditions differ. Extract behavior only when tests demonstrate equivalence.

Goals:
1. One authority for aircraft capability/law admission and normalized model data.
2. One predictable shell-facing lifecycle vocabulary (status, pause/resume request, reset, restore, teardown), implemented by thin vehicle adapters where necessary.
3. Smaller, comprehensible fixed-wing and shell coordinators with bounded side effects, explicit ownership and deterministic tick boundaries.
4. Reusable input, field, observer and presentation **contracts**; do not accidentally share vehicle-specific throttle, arming, damage, race or recorder policies.
5. Optimization based on measured workloads, retaining exact replay and target-platform evidence.

Success is fewer competing decisions and independent tests, not lines deleted or a guessed frame-rate gain.

## 2. Existing owners and non-negotiable invariants

| Existing authority | Decision |
| --- | --- |
| [Simulation / VehicleModel](../../app/sim/simulation.gd), [contract](../../app/sim/vehicle_model.gd), [STACK](../STACK.md#boundaries-and-data-flow) | **Keep.** One installed model, 240 Hz, float64, atomic tick and reset, event order, accepted endpoint and rollback. No per-vehicle branch in the kernel. |
| [Aircraft v2 contract](../AIRCRAFT_CONTRACT.md), [AircraftModules](../../app/physics/aircraft_modules.gd), [AS plan](aircraft-standardization.md) | **Keep.** Reuse one registry/schema/physical derivation. AS owns format, capability additions, Blender bindings and generated manifests; VRC does not redefine AS-00…18. |
| [Native backend policy](../STACK.md#native-backend-policy), [flight logging](../FLIGHT-LOGGING.md) | **Keep.** Reference path, qualified C++ evaluator, selected backend/law identity, checkpoint and replay guards. Do not port orchestration to native by default. |
| [Controller ownership](controller-support.md), [controls audit](https://github.com/bultodepapas/OpenRCsimulator/blob/895dd4352c5191f1539a8b8f4df1996cd33eb86f/docs/research/game-controls-audit-2026-11-21/AUDIT.md) | **Keep.** Menu focus and flight input remain different, with connection generation, verified profile/calibration, edge policy and family-specific readiness. Prior GCA-01…05 repairs remain separately owned and **not** completed by this plan. |
| [Existing optimization priorities](optimization-priorities.md) | **Keep.** VRC may propose bounded measurements; PT/VQ/GOD/NK owners decide performance acceptance and native qualification. |
| [Repository guidance](../../AGENTS.md), [track registry](../README.md#tracks-plans-and-step-ids) | Check live source and ownership before each PR. Preserve concurrent changes. No sweeping rename, formatting-only churn or golden rewrite mixed with behavior. |

A pure restructure **must not** change accepted state bytes, solver inputs, per-step event order, random state, clock, UI control meaning, profile storage, source identity rules, or resource ownership. Any unavoidable output change requires a separately identified behavioral PR with recorded reasons, baselines and replay comparisons.

## 3. Target architecture: composition before inheritance

`
Product shell (AppRoot, screen stack, Home, Pause)
  -> Activity entry adapters (fixed wing | helicopter | quad | airship | ground)
      -> ActivitySessionPort: stable request/status surface, NOT a physics base class
          -> Existing per-family session (owns safety, start/restore, timers, recorder)
              -> Existing VehicleModel callbacks -> existing Simulation
          -> Existing input service / activity-specific command conditioning
          -> Read-only view snapshots -> per-vehicle HUD / render adapter
`

**Port proposal, not an implemented API:**
- `describe_capabilities()`: immutable activity/vehicle features and supported operations, not guesses based on a vehicle name.
- `read_status()`: detached, typed/versioned view of lifecycle, pause reason, input readiness, active backend and identity. No live `Simulation` reference exposed to UI.
- `request_pause(reason)` / `request_resume(evidence)`: structured admission or refusal with an actionable reason. Each adapter delegates its own throttle/collective/armed/neutral/focus contract.
- `request_reset(start_request)` / `request_restore(typed_envelope)`: preserve each family’s existing candidate/commit protocol and recorder transitions. A common result describes acceptance; **do not standardize checkpoint payloads**.
- `close()`: idempotent, explicit event/subscription/worker release, after the owner’s existing recording/fault rules.
- Tick ownership stays exactly where it is; `tick_once` is **not** made universally callable from UI.

Prefer a small `RefCounted` interface description plus a per-activity adapter over a deep inheritance hierarchy or a central `match vehicle_type`. Do not silently translate “accepted by input setup” into “supported by activity”: admission and dispatch must agree. Do not let presentation call mutating physics setters.

### Responsibility split

| Module/owner | Owns | Must not own |
| --- | --- | --- |
| `app/app_root.gd` + existing `ui/`/`app_state/` | Navigation, screen transition, launches, cancellation, focus, preferences | Solver state, airframe law selection, per-frame controller shaping |
| Proposed activity adapter under appropriate `app/sim/<family>/` or `app/ui/` owner | Shell-to-session requests; result translation; listener lifetime | New simulation or input rules; hidden mutable checkpoint cache |
| `app/sim/flight_session.gd` and family sessions | Session-specific preparation, safety, recovery, model installation, accepted-tick observers | Repeated UI drawing/OS-device discovery/duplicated aircraft metadata |
| `app/physics/` + authoritative data | Pure laws, validation, normalized physics model | Scene-tree mutation, UI and user settings |
| `app/input/` | Device identity, profile/rates, calibration, normalized actions | Family-specific arming/collective/race rules |
| `app/render/` and `app/vehicles/` | Detached visual state, HUD/camera effects, model-specific art | Integrator state, control authorization, authoritative collisions |
| `app/sim/simulation.gd` | Atomic physical transaction, state/history, checkpoint/replay core | Vehicle catalog switches, UI, per-aircraft branching |

## 4. Consolidation policy by family

**Fixed-wing (first):** All supported airplanes continue through one `FlightSession` and `AircraftData`/`AircraftModules` path. Keep their *differences* in validated capability modules, input data, source generators, derived models and explicit adapters (flaps, elevons, retractables, glow, battery, turbine, contact, visuals). No per-model “fix” in the main kernel. Extract cohesive responsibilities from `FlightSession` only after characterization. The new aircraft onboarding gate must exercise at least a conventional electric, glow, turbine, flap-equipped, retractable and elevon/flying-wing configuration where current fixtures allow.

**Helicopter:** Can use the same shell status/transition protocol, not identical throttle/arm/reset semantics. Retain rotor physics, skid/contact, collective and native guard, and its own checkpoint format.

**Airship:** Can use lifecycle result/status contract and field/collision data adapters. Preserve reversible stern motor, yaw-centering and throttle-on-resume, blimp weather limits, tapes and recorder.

**Multirotor:** Can use shell status/transition protocol and read-only telemetry boundary. Retain controller-memory-in-checkpoint, frame sampling, arming/disarming, gate race, result outbox and tape limit. No fixed-wing RC command assumption.

**Ground vehicle (later):** Explicit opt-in; preserve neutral+armed recovery, recording-export blocker, dry/wet course and contact-damage contracts. Do not treat this as an aircraft.

## 5. Step plan and proposed independent pull requests

All steps below are **open proposals**. Status must be updated only in this plan with evidence links when implementation actually lands.

| Step / PR | Deliverable (one reviewable slice) | Main owners / dependency | Acceptance gate |
| --- | --- | --- | --- |
| **VRC-00 / PR-00** | Freeze precise source and catalog inventory; map controls/physics/scene dependencies and risk; baseline checks plus complete `.orfl` stock flights. | SF/AS/physics/UI; prerequisite | Evidence, hashes, test map, current native/backend selection; separate existing failures from new ones. |
| **VRC-01 / PR-01** | Add tests for an existing **shared session-status snapshot contract**, with family-specific adapters in test fixtures before runtime routing changes. | Session/flight/UI; after 00 | Read-only snapshots are immutable; no tick or event writes; family refusal reasons preserved. |
| **VRC-02 / PR-02** | Narrow fixed-wing session lifecycle helpers: group start/reload/reset candidate admission and result mapping, preserving all existing transactions. No algorithm rewrite. | Physics/FL/GP/EL, after 00/01 | Old-flight refusal, accepted start, observer faults, recording close, statistics and exact replay match. |
| **VRC-03 / PR-03** | Extract a small **fixed-wing input orchestration** unit for existing polling/readiness/release behavior, with command acceptance remaining in current owners. | D6/physics/UI; after GCA repair decision and 01 | Keyboard/radio/gamepad routes, rates, throttle/hold, disconnect/reconnect, focus and capture parity. |
| **VRC-04 / PR-04** | Introduce a thin activity-session adapter at **one** shell boundary (fixed wing first) and migrate just one pause/resume consumer. | UI/physics; after 01/02 | Identical pause menu, focus and startup failure states; no active-session leak/double signal. |
| **VRC-05 / PR-05** | Extend explicit adapter contract to helicopter (separate collective/rotor readiness), then airship, then quad in **separate** commits/PRs, not a mass switch. | HELI/BL/DR with UI, after 04 and relevant GCA decisions | Activity-specific safety, reset, controller roles, optional race, recorder and crash recovery checked. |
| **VRC-06 / PR-06** | Centralize only **pure, identical** field/obstacle/environment preparation inputs; leave family-specific validation and material/collision rules with each owner. | LU/SC/GP/physics; after characterization | Same terrain/weather/obstacle identity, collider order, first start/reload, lake contacts and native choice. |
| **VRC-07 / PR-07** | Factor common *observer registration and teardown* patterns; maintain independent recorder schemas and tick-boundary publication. | FL/UI-FS/AUD/physics; after 02/05 | Recorder open/close, repeated reset, observer fault, deterministic event ordering, no duplicate callbacks. |
| **VRC-08 / PR-08** | Simplify `main.gd` and helicopter/other view coordinators with detached presentation snapshots and well-owned camera/HUD components. | HUD/render/UI/vehicle owners; after 04/05 | Frozen render state, 1080p and accessible controller prompts; no visual resource aliasing. |
| **VRC-09 / PR-09** | Profile one actual hot path in a complete workload; remove a proven repeat or allocation with exact-state guard. | PT/VQ/NK and owning code; independent after 00 | Before/after p50/p95, memory/allocations, complete workload, actual backend and negative controls; no predicted gain masquerading as measured. |
| **VRC-10 / PR-10** | Normalize names/module seams, document public APIs, add ownership lint or dependency checks if warranted. Touch only migrated files, no global formatting. | Owners of touched paths; after 02…09 | Existing imports/UIDs, scene and generated-asset dependencies; no new cycles or broken packages. |
| **VRC-11 / PR-11** | Consolidation and release qualification: full affected matrix and CI, platform/device, native and package gates; decide next batch from evidence. | QA/DT/PT/physics/UI; after required migrations | No unresolved new regression, verified complete replay, stock vehicle selection and documented limitations. |

**Stop/rollback rules:** Each PR must remain independently revertible. Do not combine a data/law change with a structural move. If characterization fails, first isolate the existing bug in its owner, do not encode buggy output as a permanent reference. If a helper changes canonical checkpoint, state bytes, exported schema or accepted event timing, revert extraction or open a separate versioned behavior change.

## 6. Migration order and risk

1. **Prepare first:** VRC-00 and VRC-01; align with GCA-01…03 so unsafe action/ownership behaviors are not carried into new generic dispatch.
2. **Largest benefit, smallest semantic surface:** VRC-02 fixed-wing transaction/coordinator slicing, then VRC-04 one shell adapter.
3. **Broaden carefully:** VRC-03 input after repairs; VRC-05 family adapters one at a time, with explicit refusals.
4. **Optional reusable systems:** VRC-06 field data, VRC-07 observation lifetime, VRC-08 presentation (only after isolated contracts pass).
5. **Measure, do not speculate:** VRC-09 independently. VRC-10 after moves are stable; VRC-11 releases nothing unless qualification closes.

Treat each refactoring PR as small (one narrow responsibility and its tests, ideally one reviewable file cluster). Prefer composition, pure functions, explicit typed results and limited dependency injection over inheritance, `get_node` walks or mutable global singletons. A new helper is justified by *multiple real callers* or by demonstrated isolation/testability—not by abstract foresight.

## 7. Acceptance criteria for “cleaner, unified, optimized”

- Each aircraft capability has **one authoritative selector**, documented in AS, used by flight, Workshop and offline tools; no new per-ID conditional paths in `Simulation`.
- Each migrated activity has a documented adapter, lifecycle matrix and a test following request -> admission -> live dispatch -> pause/recovery. Existing family-specific policy must remain visible.
- UI receives detached state; a view cannot mutate solver arrays or decide arming.
- Rejection of a reset/restore leaves old accepted state, listeners and recording intact; accepted transitions publish once and retain source/backend identity.
- Before/after source, engine, OS, backend, model config, tape, events and completeness are recorded. For pure refactors, require unchanged exact-state/fingerprint where applicable; intended exceptions have a separate owner-approved change.
- No performance “win” without repeated paired target-path measurements; distinguish GDScript vs native, headless vs rendered 1080p, production workload vs microbench.
- Check full relevant vehicle/configuration matrix, affected consumer tests, and required CI before merging. Physical controller, pilot and platform tests remain separate claims.

See [source inventory](../research/vehicle-runtime-consolidation-2026-11-21/SOURCE-INVENTORY.md), [migration decision matrix](../research/vehicle-runtime-consolidation-2026-11-21/MIGRATION-MATRIX.md), [quality gates](../research/vehicle-runtime-consolidation-2026-11-21/QUALITY-GATES.md) and [dated research home](../research/vehicle-runtime-consolidation-2026-11-21/README.md).

## 8. Open design decisions for first implementation PR

- Whether the shell port belongs alongside current `ui/` activity routes or in one new narrowly owned `sim/session_port.gd` interface/adapter; select only after VRC-01 fixtures prove the minimum public shape.
- Whether fixed-wing start-result mapping can be isolated without changing the existing observer transaction. If not, keep it within `FlightSession` and prefer smaller pure validators.
- Which actual cross-family field helper is byte-equivalent under all supported lakes/terrain/weather; do not assume matching import lists imply matching semantics.
- Which complete-session/target platform shows remaining hot-path cost after the already delivered NK-2a and PT optimizations.

No behavior, architecture or speedup proposed here is implemented or performance-qualified by publication of this document.
