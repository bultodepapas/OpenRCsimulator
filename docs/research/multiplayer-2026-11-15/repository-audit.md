# Repository readiness for multiplayer

**Audited source:** clean `main` at [`cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b`](https://github.com/bultodepapas/OpenRCsimulator/commit/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b), 2026-11-15 America/Bogota. Static inspection only. No simulator, multiplayer, exports or physical performance tests were executed. The [plan](../../plans/multiplayer.md) owns future changes; this file records evidence at the pinned revision.

## Current implementation

The application is native Godot **4.8-beta2**, exact engine string `4.8.beta2.official.cafc17a19`, with application version **0.2.8** in `project.godot`. Export presets target Windows/Linux x86_64 and macOS universal. Float64 simulation arrays do not imply that the engine was compiled with `precision=double`. The official engine getter and runtime source are the relevant evidence, not assumptions from the physics design. [R01–R03]

No production multiplayer peer, RPC route or room service was found in targeted searches of application GDScript/configuration. The root README explicitly says multiplayer is unavailable. Update HTTP, statistics-store UDP locking, Creator's local process lock and the debug bridge's localhost TCP service are unrelated networking; none establishes an existing multiplayer transport. [R04–R07]

| Source observation | Consequence for implementation | Evidence |
| --- | --- | --- |
| Each `FlightSession` creates a `Simulation`; each kernel installs one `VehicleModel` | Preserve one model per kernel. This is not globally one aircraft: AI companions already have independent sessions | [R08–R10] |
| Accepted state commits before `Simulation.stepped`; local interpolation uses previous/current simulation states | Read detached accepted values; create a separate network jitter buffer. Existing local interpolation is not network smoothing | [R09] |
| Physics uses 240 Hz, with 12 catch-up steps/frame; simulation time is tick × dt | A slow machine can fall behind wall time. Heartbeat, send cadence, timeout and room clock must not use physics tick | [R02, R09] |
| Body state has NED position, FRD body velocity/rates and a body→NED quaternion ordered w,x,y,z | The proposed NED network velocity needs an explicit rotation. Reuse existing axis and model-CG conversion; never reinterpret body velocity as world velocity | [R11–R12] |
| Native/reference backend and replay identities are explicit; multirotor exact replay is restricted to the same build/platform | Do not select input lockstep or full rollback based on float64/RK4 alone | [R13], [STACK](../../STACK.md#boundaries-and-data-flow) |

## Content and lifecycle

| Integration seam / blocker | Required design response | Evidence |
| --- | --- | --- |
| `AppRoot` owns an active foreground flight, staged loading, acceptance, controller attachment and cancellation | Separate room connection owner from candidate flight/replica owner. Late callbacks must not resurrect cancelled flights | [R14] |
| Menu hold/focus loss pauses local simulation; explicit safe resume belongs to local UI/input flow | Poll transport and forward host traffic outside held physics; show paused remote state. Network messages cannot arm/resume local flight | [R08–R09, R14] |
| Workshop can retain, detach and later restore a flight | First online mode leaves room before Workshop/trials. Preserve recorder prompts and retained-flight semantics | [R14] |
| Local statistics attach to the accepted player's session/configuration | Remote visual planes never attach to statistics, credit, repair costs, controller or local recording observers | [R14] |
| Companions build real default-aircraft sessions and pilots, then render through builder/frame helpers | Reuse visual ingredients and CG/animation mapping. Do not instantiate the companion agent/manager as a remote replica | [R15–R16] |
| Player-only paired checkpoints refuse active companion fleets; reset/restore handles transition generations | State explicitly that room replay/checkpoint restore is unsupported. Network reset/rejoin needs its own room/entity/flight epochs | [R17] |
| Field bytes, aircraft source and model manifests have distinct identities; scenario digest intentionally rounds to 12 significant digits | Do not advertise one generic hash as proof of all content. Qualify a bundled subset and an explicit compatibility manifest first | [R18] |
| Export resource checks do not execute the target OS binary | Windows/macOS/Linux networking and native extensions require actual target execution; a ZIP is insufficient evidence | [R03, R19] |

Companion visual code establishes a useful presentation seam, not a finished remote-plane interface. Its sound and control-surface updates currently read a local session. The first replica should use a bounded stock visual subset; later audio/extra actuators need an explicit presentation sample rather than a fake simulation. [R15–R16]

Environment identity also needs care. Sharing a seed does not synchronize evolving turbulence when pilots pause or progress at different simulation rates. The first room should lock an agreed stock field and calm profile. A later shared dynamic weather model needs explicit room-time semantics, while preserving each local solver's existing physics contract. This is an engineering inference from the observed timing/lifecycle boundaries.

## Racing

The experimental drone mode already has **local** racing; it is not absent merely because older plans used future wording. `race_model.gd` wraps one plant and a race director in the sampled transactional model. `race_director.gd` evaluates accepted 1/240 s path chords within its declared acceleration envelope. Course identities include resolved gates/pads/field/rules. Results and records remain local. [R20–R23]

Therefore a 20 Hz visual snapshot stream must not become an authoritative gate-crossing detector. A later informal room can share locally reported events/results with that trust level visible. Shared starts, fair timing, authoritative adjudication, anti-cheat and interacting vehicle collisions require separate work. Existing race replay does not qualify any of those capabilities.

## Existing tests to reuse when implementation starts

These are discovered regression entry points, **not tests executed for this documentation change**. Their existence does not prove networking behavior. Use the [checked-runner and scope guidance](../../tools/shared.md#verification-scope), then add the smallest new codec/timing/lifecycle and multi-process checks that prove the changed boundary.

| Boundary | Existing entry points under `app/tests/` |
| --- | --- |
| Accepted simulation, session guards and staged loading | `test_simulation.gd`, `test_session_guards.gd`, `test_flight_session_staged.gd`, `test_golden.gd` |
| Replica visual/lifecycle reuse | `test_companions_render_interpolation.gd`, `test_companions_presentation.gd`, `test_companions_lifecycle.gd`, `test_companions_external_rejection.gd` |
| UI, pause, Workshop and shutdown | `test_ui_pause.gd`, `test_workshop_integration.gd`, `test_ui_quit.gd` |
| Local credit and recording | `test_flight_statistics_lifecycle.gd`, `test_flight_log.gd`, `test_replay_integrity.gd`, `test_mr_flight_log.gd` |
| Future informal racing | `test_race_track.gd`, `test_race_gate_crossing.gd`, `test_race_director.gd`, `test_race_model.gd`, `test_race_session.gd`, `test_race_session_replay.gd`, `test_race_records.gd` |

The proposed first test isolates two copies with one stock field/model, immutable outgoing state and remote visuals only. LAN, actual WAN routing, service relay, target packaging and sustained 1080p performance are distinct later proofs. No new simulation test is warranted merely to validate this plan's prose.

## Immutable source references

Line anchors identify useful entry points in the audited commit; follow function bodies for the complete context.

| ID | Source |
| --- | --- |
| R01 | [Pinned engine getter](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/get-godot.sh#L4) |
| R02 | [Application and tick configuration](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/project.godot#L9) |
| R03 | [Desktop export presets](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/export_presets.cfg) |
| R04 | [README multiplayer status](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/README.md#L214) |
| R05 | [Release update checker](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/app_state/update_checker.gd) |
| R06 | [Statistics lock](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/statistics/store.gd#L882) and [Creator process lock](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/workshop/creator/process_lock.gd) |
| R07 | [Local debug bridge](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/debug/debug_bridge.gd#L1) |
| R08 | [Flight session construction](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/sim/flight_session.gd#L1695), holds at 1928 and resume at 2275 |
| R09 | [Simulation kernel](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/sim/simulation.gd), clock at 355, focus hold at 372, accepted publication at 634 |
| R10 | [VehicleModel contract](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/sim/vehicle_model.gd) |
| R11 | [Rigid-body state layout](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/physics/rigid_body.gd#L1) |
| R12 | [Frame and model-CG conversion](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/render/frames.gd) |
| R13 | [Multirotor flight-log/replay contract](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/sim/multirotor/flight_log.gd#L1) |
| R14 | [Application root](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/app_root.gd), launch 1313/1619, cancellation 1697, retained Workshop flight 3317, statistics 3426, resume 4123, end-flight 4223 |
| R15 | [Companion construction and rendering](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/ai/companions/agent.gd#L35) |
| R16 | [Companion scheduling](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/ai/companions/manager.gd#L137) |
| R17 | [Player-only checkpoint gate](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/main.gd#L2490), restore 2530 and reset generation 3192 |
| R18 | [Scenario/source identity](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/scenarios/scenario_config.gd#L190) and [multirotor data identity](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/physics/multirotor_data.gd#L64) |
| R19 | [Export smoke scope](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/export.sh#L365) |
| R20 | [Race model](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/sim/race/race_model.gd#L1) |
| R21 | [Race director](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/sim/race/race_director.gd#L1) |
| R22 | [Resolved course identity](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/sim/race/track.gd#L311) |
| R23 | [Local race records](https://github.com/bultodepapas/OpenRCsimulator/blob/cfb5acd5cfbcbf83f7f9220116c67fa082e8f27b/app/vehicles/multirotor/race_records.gd#L1) |

These identifiers are a compact source ledger, not a claim of full repository execution or of future multiplayer correctness.
