# Inspected runtime inventory and evidence level

Read-only source snapshot: `main@57abea025f62b20233ca281d58d2acbee4ab8b8e` on 2026-11-21. The inventory is **not** a complexity ranking, benchmark, duplication count or full application inventory. “Functions” means lines beginning `func` or `static func` (no nested closures), from the inspected GDScript. Paths resolve to the pinned commit.

| Component | Lines | Top-level functions | Role / why inspect |
| --- | ---: | ---: | --- |
| [`app/sim/flight_session.gd`](../../../app/sim/flight_session.gd) | 6,698 | 339 | Shared fixed-wing session; controller start, weather, native callbacks, reset/restore and recorder coordination |
| [`app/app_root.gd`](../../../app/app_root.gd) | 5,338 | 239 | Product shell, five activity routes, loading and controller actions |
| [`app/main.gd`](../../../app/main.gd) | 4,304 | 151 | Fixed-wing scene, camera/render, controls, restart and observation |
| [`app/sim/ground_vehicle/session.gd`](../../../app/sim/ground_vehicle/session.gd) | 2,262 | 127 | Experimental car session; neutral/armed recovery, per-tick controls and recording |
| [`app/sim/simulation.gd`](../../../app/sim/simulation.gd) | 1,454 | 66 | **Existing shared kernel:** preserve unchanged absent a separate SF/physics proof |
| [`app/sim/helicopter_flight_session.gd`](../../../app/sim/helicopter_flight_session.gd) | 1,445 | 80 | Rotorcraft start, focus/RC safety, native guard and checkpoint |
| [`app/sim/multirotor/session.gd`](../../../app/sim/multirotor/session.gd) | 1,212 | 56 | Closed-loop quad and race, input tape, results and checkpoint |
| [`app/helicopter_main.gd`](../../../app/helicopter_main.gd) | 695 | 36 | Heli scene, camera, presentation and controller actions |
| [`app/sim/airship/session.gd`](../../../app/sim/airship/session.gd) | 640 | 31 | Blimp start, throttle/yaw resume policy and tape |
| [`app/sim/vehicle_model.gd`](../../../app/sim/vehicle_model.gd) | 235 | 2 | **Existing shared evaluator contract:** not a redesign candidate |

### Verified common *names*, not proved copy-paste equivalence

- All five sessions expose `resume` and `restore_checkpoint`. Four expose `reset` and four expose `checkpoint`. Three have `pause` and `tick_once`. These signatures do **not** imply interchangeable semantics.
- `FlightSession.resume` blocks on calibration, holds, crash, lost controller, missing start and native fault; helicopter guards collective/mode/ready state, the car requires neutral+armed evidence, airship rejects throttle/yaw above limits, and quad blocks on crash/fault/tape full. **Do not** replace these with a single boolean helper.
- In the airship `_set_paused` publishes `pause_changed`; the quad does likewise. This is a *candidate* for listener-lifetime factoring, with signal-count tests. The car additionally owns pause holds and armed readiness.
- Both `FlightSession._poll_controller` and helicopter `_poll_controller` call the existing radio poll and react to invalid inputs. That is a *candidate* common setup/transport seam, but flight-loop shaping and disconnection policy remain activity-specific.
- Airship `prepare` validates blimp weather bounds; quad `prepare` builds a closed-loop plant and race; car `prepare` protects unexported recordings. Shared spelling is not interchangeable preparation logic.
- The fixed-wing `checkpoint` and helicopter/quad/car checkpoint methods encode different envelopes and identity guards; airship has a specialized `restore_checkpoint(state, continuous)` signature. Do **not** introduce one new checkpoint schema.

### Already-shared foundations to reuse

| Boundary | Current source |
| --- | --- |
| Fleet capability classifier | [`app/physics/aircraft_modules.gd`](../../../app/physics/aircraft_modules.gd), [JSON registry](../../../app/data/schema/aircraft-modules-v1.json) |
| Fixed-wing physical admission | [`app/physics/aircraft_contract.gd`](../../../app/physics/aircraft_contract.gd), [`aircraft_data.gd`](../../../app/physics/aircraft_data.gd) |
| Normalized control/rates | [`app/input/commands.gd`](../../../app/input/commands.gd), [`controller_service.gd`](../../../app/input/controller_service.gd), [`controller_profile.gd`](../../../app/input/controller_profile.gd) |
| Flight kernel/model | [`app/sim/simulation.gd`](../../../app/sim/simulation.gd), [`vehicle_model.gd`](../../../app/sim/vehicle_model.gd) |
| Pure field/weather services | [`app/sim/environment.gd`](../../../app/sim/environment.gd), [`physics/wind_field.gd`](../../../app/physics/wind_field.gd) |
| Native evaluator and identity | [`app/sim/native_stage.gd`](../../../app/sim/native_stage.gd), [native guide](../../../research/native-kernel/README.md) |

### Interpretation

**Code quality risks to investigate:** coordinator breadth, duplicated shell-to-session glue, per-activity manual observer teardown, stale source documentation and difficult test setup. Source size and repeated method names justify *inspection*, not unconditional extraction. Earlier AS/SF/NK refactors and repairs must not be repeated.

**Proposed measurement:** calculate actual duplication fingerprints only after normalizing formatting and categorizing by semantics; distinguish generated model geometry, hand-authored model laws, orchestration and independent recorder formats. Measure regression behavior and hot paths before moving either.

**Evidence class:** source-only/design proposal. No runtime validation, speedup or correctness repair claimed.
