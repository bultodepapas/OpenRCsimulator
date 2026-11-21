# Share / keep / reject decision matrix

**Scope:** `main@57abea02`, source-only architectural inspection. Proposed moves are subject to characterization; no extract has landed.

| Concern | Share / retain decision | Existing authority | Family-specific exception | First VRC step |
| --- | --- | --- | --- | --- |
| Rigid-body tick, event/rollback | **Retain existing shared code**, no replacement | `Simulation`/`VehicleModel` | Closed-loop quad's framed sampled protocol and joint intervals remain explicit opt-ins | 00, 11 |
| Aircraft v2 validation and law classification | **Retain shared**; remove only proven duplicate consumers | AS `AircraftModules`/`AircraftData` | Helicopter, airship, ground, multirotor have distinct schemas; do not mis-admit them as v2 airplanes | 00, AS owner |
| Fixed-wing airframes, gear, flaps, elevon and engines | **Share capability-driven laws** and validated data/manifest | AS + existing physics modules | Model-derived geometry, authored coefficients, artwork and physical qualification stay with the aircraft track | 02 |
| Pilot input device/profile/calibration | **Share service + profile admission**, not flight authority | D6 input, UI setup, GCA remediation | Collective, neutral/armed, reversible propulsion, race command, radio throttle require family policy | 03 |
| Pause/resume/hold UI semantics | **Share detached request/result/status contract**, leave admission in sessions | UI shell + each session | Ground neutral+armed; heli collective; blimp yaw/throttle; quad results/tape; fixed-wing holds | 01, 04, 05 |
| Start/reset/restore | **Share transaction vocabulary and observer discipline**, not envelope format | SF kernel / each session | Native guard, crash policy, field identity and recorder closes differ | 02, 05 |
| Terrain, weather and collisions | **Share pure checked input builders only after proving same law/domain** | LU/SC/GP/physics | Airship steady-wind limit; heli pad, quad gate obstacles, car road profile | 06 |
| Recorder / stats / trace | **Share registration/teardown discipline**, leave data schemas/versioning separate | FL/UI-FS, activity recorders | FPV race outbox and airship tape; ground export policy; fixed-wing `.orfl` | 07 |
| Camera, HUD, scene objects | **Share snapshot interface / optional components**, preserve visual families | Render/HUD/vehicle owners | Rotor blur, OSD, airship envelope, car dashboard, special aircraft rigs | 08 |
| Backend selection and performance | **Keep existing** native reference-selection contract; profile remaining overhead | NK/PT/physics | Qualification varies by vehicle, OS, source identity and configuration | 09 |
| Generic universal-aircraft inheritance | **Reject** | N/A | Would merge incompatible physical/session semantics and create fragile large base | Never |
| Generic “one replay file for all” | **Reject** | Current versioned formats | Exact replay safety and time/context interpretation differ | Never |
| One enormous migration / rename | **Reject** | Existing owners and CI | Impossible to attribute numerical or control regressions | Never |

## Proposed small interface contract (design, not source code)

An activity adapter should expose *requested intent*, *admission/refusal receipt*, and a *detached status snapshot*. Use explicit feature flags or typed capability entries; an absent operation is an explicit unsupported result, not a no-op. Keep active source/connection generation and shell focus identity in the request context, but do not cache or duplicate its authority in the adapter. A transition may be accepted but encounter a committed observer fault; the receipt must distinguish that from rollback.

Avoid pushing a generic `Dictionary` of unconstrained fields across every layer. Freeze a minimal versioned shape, reject unknown/invalid fields, and prefer tiny typed data records where Godot permits. Test one concrete consumer before widening it; do not publish an API based solely on aesthetic preference.

### Example activity acceptance matrix

| Activity | Resume admission | Tick path | Checkpoint/restore |
| --- | --- | --- | --- |
| Fixed wing | calibration/hold/crash/controller/valid-start/native guards | existing session control to 240 Hz kernel | full fixed-wing envelope, selected laws and observer transactions |
| Helicopter | rotorcraft readiness, collective, focus and power/heading rules | own `_physics_process` to same kernel | rotorcraft envelope with native guard and rotor state |
| Airship | throttle and yaw centered + valid session | explicit `tick_once(sticks)` | existing specialized state/continuous reset |
| FPV quad | prepared, crash/fault/tape capacity, arming/race policy | `tick_once(pilot, race_action)` with frame sampling | kernel envelope + race/result/outbox identity |
| Ground car | prepared, neutral+armed and no pause holds or backend mismatch | `tick_once(sample)` | own damage/control/event tape and recording policy |

**Migration proof:** for each accepted/refused request: check return/receipt, kernel tick, source identity, pause reason, installed callback, observer count, saved checkpoint, and UI action. Compare under focus loss, disconnect, immediate relaunch, and fault/restore. For physics-affecting changes use [FLIGHT-LOGGING](../../FLIGHT-LOGGING.md), not only a code diff.
