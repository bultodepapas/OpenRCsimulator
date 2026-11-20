# CR-AUD remediation — 20 November 2026

**Base:** main `e1ee214a4` plus this change. **Audit source:** branch `audit/collision-damage-2026-11-17` at [`8fdb1be6`](https://github.com/bultodepapas/OpenRCsimulator/tree/8fdb1be6727e0620cdf04df303f3cff4454d6743/docs/research/crash-damage-investigations/CR-AUD-2026-11-17), kept reachable by the tag `audit/CR-AUD-2026-11-17-evidence`.

This page is the single status ledger for CR-AUD-01…34 and the improved execution plan. It supersedes the ordering in the [improvement plan](improvement-plan.md) and the per-round plans; their acceptance gates stay valid. Software checks below are not physical validation, rendered qualification or hardware performance evidence.

## What came to main

- Every audit document, the source/provenance indices, all probe scripts and runners, and the compact manifests/summaries (92 of 511 files, 1.9 of 7.4 MB).
- Raw engine logs, per-run reports, `.orfl` recordings and the full source manifests stay at the tagged commit. Links to them are permalinks.
- The branch's dated additions to the [crash plan](../../../plans/crash-realism.md), [CRASH-DAMAGE-PLAN](../../../CRASH-DAMAGE-PLAN.md) and [GP plan](../../../plans/advanced-ground-flight-physics.md).

## Status ledger

**Fixed** means the audit's counterexample now passes and a regression check lives in the named suite. **Planned** rows keep the audit's acceptance gate and name their batch below.

| ID | Status | Change | Regression |
|---|---|---|---|
| 01 | **Fixed** | Quad and blimp scenes resolve the field lake like the field builder and pass it to every session preparation; terrain queries see the bed, lake identity enters session identity, starts at the water are refused, and water entry is an explicit terminal "Water contact" crash | `test_lake_session` |
| 02 | **Fixed (R1)** | The helicopter detector reports the earliest nonterminal body–scenery contact beside its terminal impact; the session applies the shared bounded scenery response inside the candidate step (a failed response refuses the tick) | `test_heli_scenery_response` |
| 03 | **Fixed (R1)** | The nonterminal prop-strike guard uses the accepted shaft speed, so a coasting or windmilling propeller strikes like a powered one; a stopped one never does. The terminal economics observation keeps its powered-only rule | `test_prop_strike_coasting` (promoted probe) |
| 04 | **Fixed** | Contact events v2 name the earliest-crossing witness (`crossing_point_index`, `crossing_probe_id`, `crossing_is_selected`, `selected_crossing_fraction`); v1 stays valid | `test_aircraft_contact_events` |
| 05 | **Fixed** | Effects keep the impact height and land chips/marks on the sampled ground; the fixed-wing wreck plane follows sampled terrain height and slope | `test_crash_effects`, `test_crash_wreck` |
| 06 | **Fixed** | Core launches at its inventory-COM velocity | `test_crash_wreck` |
| 07 | **Fixed** | One release transaction moves mass, first moment and box; both bodies take the rigid point velocity at their new COM | `test_crash_wreck` |
| 08 | **Fixed** | Pending sections stay on the active core until released | `test_crash_wreck` |
| 09 | **Fixed** | Core box = core meshes ∪ attached sections, rebuilt at each release | `test_crash_wreck` |
| 10 | **Fixed** | Provisioned scenery bodies (debris layer, `obstacle_id`) are secondary contacts | `test_crash_wreck` |
| 11 | **Fixed** | Wreck scenery is provisioned for every non-water crash | `test_crash_integration` |
| 12 | **Fixed** | Effect age consumes the whole supplied time; chip motion substeps (≤ 8 × 50 ms) | `test_crash_effects` |
| 13 | **Fixed** | `apply_energy` owns kerosene fire duration from the accepted fuel sample | `test_crash_effects` |
| 14 | Planned R3 | Car general-scenery collision (capability) | — |
| 15 | Fixed earlier | `35787fb5` | `test_parked_aircraft_collision` |
| 16 | **Fixed** | Delayed rotor release uses the current airframe frame for hub, axis and blade | `test_heli_wreck_delayed_frames` (promoted probe, 90 checks) |
| 17 | **Fixed** | A checkpoint requested inside the crash tick is refused; the next one carries the crash, cut and tape | `test_mr_graded_crashes` |
| 18 | **Fixed (R1)** | With soft hull contacts, a terminal scenery hit yields to the ground when the soft-ground terminal rule already holds at the obstacle's contact pose (ground-first tie; the obstacle takes no damage). A documented tick-boundary rule, not a measured first impact | `test_soft_ground_scenery_order` (promoted probe) |
| 19 | **Fixed (R1)** | The crash record, reason, contact events and scenery damage are committed before the pause is published; the pause still precedes the change notifications | `test_crash_pause_log` (promoted probe, real `.orfl`) |
| 20 | **Fixed (R2)** | A terminal frame-obstacle strike leaves the solid with the bounded response; after the crash the wreck keeps colliding with the terrain's declared aftermath law (out of the solid, no inward speed, kept fractions), without new events. A quad water crash is adjudicated in the plant's endpoint transition, so the drive is cut | `test_quad_obstacle_aftermath` (promoted probe), `test_quad_wreck_rest`, `test_lake_session` |
| 21 | **Fixed (R2)** | The prop-strike kick may not raise the coupled body-and-shaft kinetic energy; when the airframe's motion along the kick would, the impulse is bisected down (conservative limit, not a solved contact impulse) | `test_quad_prop_strike_energy` (promoted probe) |
| 22 | **Fixed (R2)** | Changing the airship's world identity on a started flight (paused included) emits `resetting`, closing recorders, as the quad does; every written file replays exactly | `test_airship_collision_recording` (promoted probe) |
| 23 | Planned R4 | Submicron capsule entry tolerance | — |
| 24 | **Fixed (R1)** | Near the lake's bounded bank the disc depth also scans 64 rim phases against the covered terrain; flat ground keeps its exact lowest point. A sampled rim proves the overlaps it finds, not clearance between samples (sagitta 0.18 mm at 15 cm) | `test_prop_bank_rim` (promoted probe) |
| 25 | **Fixed (R2)** | A session query judges the finite prop disc against each obstacle (alternating disc/proxy projections plus rim and hub samples), returning that obstacle's own witness, normal and class; the hub clearance is only a gate | `test_quad_disc_box_separation` (promoted probe) |
| 26 | **Fixed** | Car body damage follows the contacting probe's face; travel direction only as fallback | `test_rcv_damage` |
| 27 | Design R1b | Deployed wheel vs scenery (capability). Not patched: see *CR-AUD-27 proposal* below | — |
| 28 | **Fixed** | Director grades every snapshot against its own validated normal; the soft-rule C2 floor stays | `test_crash_integration` |
| 29 | **Fixed** | Quad crash FX and lens use the previous accepted state (motion into the impact) | `test_mr_crash_presentation` |
| 30 | **Fixed** | Helicopter lens uses the crash's `obstacle_kind`; a ground crash beside a spectator is ground-only | `test_lens_person_strike` |
| 31 | Planned R4 | Rotational padding must not become a contact | — |
| 32 | Planned R4 | Remaining-tick motion after a nonterminal scenery response | — |
| 33 | Planned R4 | Transient water contact policy (capability) | — |
| 34 | **Fixed (R1)** | Water normal speed is relative to the moving wave surface (`interface_down_speed_mps` on the event); calm water is bit-identical | `test_lake_collision` |

## Improved plan

The original eight slices ordered work by theme. The remaining items are now ordered by **what each change costs to qualify**. Native-mirrored sources (`REFERENCE_SOURCES` in `research/native-kernel/build.py`) silently move flights to the GDScript reference until the native kernel is rebuilt and requalified, so they ship together.

| Batch | Findings | Files | Gate in addition to the audit's acceptance |
|---|---|---|---|
| **R1 native batch** (done except 27) | 02, 03, 18, 19, 24, 34 | `flight_session.gd`, `helicopter_flight_session.gd`, `rotorcraft/impact_detector.gd`, `hull_contact.gd` (mirrored); `lake_collision.gd` | One native rebuild and requalification on Windows, Linux and macOS (NK gates). Companion rebind. Flight-log baseline/candidate comparison for any trajectory change; re-record goldens only for an explained physics change. |
| **R2 vehicle physics** (done) | 20, 21, 22, 25 | `multirotor/controlled_plant.gd`, `sim/airship/*` | Quad and airship replay/golden checks; contact energy invariant tests; recording identity test with real `.orfl` files. |
| **R3 car scenery** | 14 | ground-vehicle course/session adapter over the shared collision world | Explicit capability matrix; wall dedupe; bounded candidates with visible overflow; both stock cars, driven passes. |
| **R4 contact-time policy** | 23, 31, 32, 33 | `sim/scenery_collision.gd`, lake policy | Flight-log comparison at 240/480 Hz; no false-clear results; owner decision on transient water. |
| **R5 presentation follow-ups** | — | wreck/effects | Per-section compound core proxy with slide/rebound retuning (a compound box set made sideways slides tumble on gear boxes, so it needs its own tuning). Quad/airship obstacle identity for lens strikes. 1080p captures of asymmetric, slope and scenery crashes. |

Promote each audit probe into the owning suite when its finding is fixed, as done for 01, 04–13, 16, 17 and 26–30. Do not change an expected value to match a defect.

## CR-AUD-27 proposal (R1b)

Copying wheel points into the crash hull is wrong twice over: event indices are bound to `hull_probes`, and the undeformed support reference sits up to the wheel's compression below the terrain, so it would hit the buried part of any obstacle resting on the ground. The capability needs its own owner:

1. One contact point per deployed wheel at its **compressed** bottom (support reference moved up the strut by the accepted compression), swept against obstacle proxies only, never terrain.
2. A `gear_probes` binding and event source, so contact identity stays separate from hull probes.
3. Response by obstacle class: frangible/soft → the shared dissipative impulse at the wheel; hard → impulse plus a gear damage observation below the gear's declared tolerance, a terminal `gear` incident above it.
4. One incident per tick: earliest wins, a hull/wheel tie goes to the hull; no duplicate damage.
5. Gates: the audit's Avanti taxi box, a curb series, gear-up belly support and ordinary landings unchanged, replay identity.

It touches `ground_wheels.gd` and `flight_session.gd` (mirrored), so it ships with the next native requalification.

## Decisions taken here

- **Single attached-set core box.** It fixes membership (CR-AUD-09) and keeps the tuned behaviour of an intact wreck. Compound per-section proxies are R5.
- **Contact events v2** are additive. v1 readers must ignore or upgrade v2 hull impacts that carry a crossing estimate. An unidentifiable crossing is withheld, not emitted ambiguously.
- **Quad severity** uses `Simulation.previous`, the last accepted pre-step state. A crash injected without a step (no previous state) still reads the current state.
- **Quad and blimp water** is a deliberate terminal refusal, like the helicopter's: no flotation or hydrodynamic force model is claimed. The quad uses its conservative bounding sphere, and its motor state is not cut by the session (R2 follow-up).
- **Helicopter lens** trusts the authoritative `obstacle_kind`. Quad and airship routes keep the proximity query until their sessions expose obstacle identity (R5).

## Verification (Windows, Godot 4.8 beta 2, headless)

| Check | Result |
|---|---|
| Audit wreck/effects probe (`evidence/probes/crash_adversarial_probe.gd`) | 18 checks: 12 failures before, 0 after |
| Heli delayed-frame probe → `test_heli_wreck_delayed_frames` | 90 checks: 16 failures before, 0 after |
| Slope severity probe (28) | 8 checks: 3 failures before, 0 after |
| Staggered crossing (04) / car region (26) probes | 7/1 → 7/0; 22/4 → 22/0 |
| `test_crash_wreck` 378, `test_crash_effects` 74, `test_crash_integration` 256, `test_crash_masses` 34, `test_crash_breakup` 30, `test_crash_wreck_surface` 11, `test_crash_fracture` 24, `test_crash_sections` 37, `test_wreck_shadow_cache` 16, `test_ground_marks`, `test_crash_warmup` 18, `test_crash_severity` 44, `test_crash_energy` 251 | 0 failures |
| `test_heli_crash_presentation` 44, `test_heli_crash_visual` 33, `test_heli_crash_relaunch` 66, `test_lens_person_strike` 14, `test_lens_effects` 77, `test_mr_crash_presentation` 33, `test_mr_graded_crashes` 51 | 0 failures |
| `test_lake_session` 81, `test_mr_graded_crashes` 56, `test_mr_activity` 98, `test_mr_activity_race` 19, `test_airship_activity` 15; helper runs of `test_mr_session`, `test_mr_flight_log`, `test_airship_session`, `test_airship_flight_log`, `test_race_session_replay` | 0 failures |
| `test_aircraft_contact_events` 74, `test_rcv_damage` 187, `test_rcv_damage_session` 19, `test_rcv_session` 162, `test_flight_log` 4417, crash-cost suites | 0 failures |

Two existing oracles in `test_crash_wreck` encoded the defects themselves and were corrected: core velocity at the box centre (06) and a core box that excluded still-attached sections (09).

## R1 native batch — verification

The R1 changes touch native-mirrored sources, so the installed native kernel was rebuilt and requalified on Windows (MinGW-w64 GCC 15.2.0) and Linux (WSL Ubuntu, GCC 13.3.0) after the final edits. Both platforms passed all 19 installer gates. Every pass compared byte-identical: stage 128,664/128,664, trajectory 21,771, propeller 50,310, electric 32,010, liquid 15,572, glow 49,606, wake 19,138, wake-spatial 20,347, gear 35,452, weather 21,549, helicopter 50,336, electric-stage 66,988, liquid-stage 64,136, glow-stage 79,881, helicopter-stage 61,281, weather-stage 59,340, prescribed-stage 49,571 and legacy-ground 14,806. The mutant negative control failed as required. Evidence is recorded in [NK-4](../../native-kernel/NK-4/README.md#local-requalification-cr-aud-r1-2026-11-20).

| Check (reference evaluator unless noted) | Result |
|---|---|
| Audit probes: coasting prop (03) 23, contact order (18) 11, crash-pause log (19) 15, prop bank rim (24) 16 | Desired failures before → 0 after; promoted to the named tests |
| `test_heli_scenery_response` (02): open air vs frangible box, one accepted tick | 11 checks, 0 failures; north speed 2.00 → 0.016 m/s through the box |
| CR-AUD-34 rising wave on a still point | reported 0.0471178 m/s vs analytic 0.0471178 m/s |
| Regression sweep: 93 suites (golden flights, prop strike, soft contacts, scenery, RC track, hull, lake, water, gear, contact policy, accident/crash-cost, flight log, companions, all 52 helicopter suites) | 0 failures |
| `test_lake_covered_sampling` 761 | 0 failures. The byte parity oracle now accepts a deeper rim point when the full reference sampler recomputes the same depth |
| Native production paths after install (Windows): stage, session, replay, helicopter session/route, fallback | see NK-4 |

**Limits retained from review.** The helicopter applies the nonterminal response but still records no scenery damage, contact event or statistic; it responds to the earliest body contact per tick, and rotor–scenery nonterminal contacts remain terminal-only. Its heading memory and rotor state keep the tick-end values while the body takes the contact-time pose (same approximation as the fixed wing). The 18 rule refuses the tick when sampled mass properties fail, as the existing glow terminal check does. The rim scan runs only when the disc is below the lake's highest possible surface and inside its bank bounds.

## R2 vehicle batch — verification

None of the R2 files is native-mirrored, so no kernel requalification is needed; the flight-log solver identity changes (`solver_changed` on older logs) and the companion pin is renewed.

| Check (Windows, Godot 4.8 beta 2) | Result |
|---|---|
| Audit probes: quad obstacle aftermath (20) 32, prop strike energy (21) 16, airship recording (22) 31, disc/box separation (25) 29 | Desired failures before (1, 1, 1, 2) → 0 after; promoted to the named tests |
| `test_quad_wreck_rest`: terminal roof strike, 2400 aftermath ticks | Never below the roof (0.000 mm), at rest (0.0000 m/s) |
| `test_lake_session` | 82 checks, 0 failures; the quad water crash leaves motor mode crashed and the cut latch at 1 |
| Regression sweep: every `test_mr_*`, `test_race_*`, `test_airship_*`, quad and controller-audit suite plus golden flights (56 suites, including race replay and the quad/airship flight logs) | 0 failures |

**Review outcomes.** An independent review found the first aftermath version (a bounded bounce every crashed tick) kept a wreck hopping and spinning on a roof; it now uses the terrain aftermath law at the endpoint only. The disc query now also takes the deepest rim/hub sample and falls back to an outward normal; the passivity comparison has a round-off tolerance. Kept limits: when shaft braking alone (an extreme yaw rate) raises the coupled energy the kick is removed but the braking stays; the disc contact samples are a bounded search, not an exact disc–box distance; replay of logs recorded before R2 reports `solver_changed`.
