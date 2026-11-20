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
| 02 | Planned R1 | Helicopter nonterminal scenery response | — |
| 03 | Planned R1 | Prop-strike guard from shaft speed, not `engine_running` | — |
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
| 18 | Planned R1 | Mixed soft-ground/scenery arbitration | — |
| 19 | Planned R1 | Crash pause published after reason/event/damage | — |
| 20 | Planned R2 | Quad keeps solid response after a terminal wall strike; also cut the drive after a water crash | — |
| 21 | Planned R2 | Quad prop contact energy invariant | — |
| 22 | Planned R2 | Airship recording identity on a paused world change | — |
| 23 | Planned R4 | Submicron capsule entry tolerance | — |
| 24 | Planned R1 | Prop rim vs dry bank | — |
| 25 | Planned R2 | Finite quad prop disc vs box | — |
| 26 | **Fixed** | Car body damage follows the contacting probe's face; travel direction only as fallback | `test_rcv_damage` |
| 27 | Planned R1 | Deployed wheel vs scenery (capability) | — |
| 28 | **Fixed** | Director grades every snapshot against its own validated normal; the soft-rule C2 floor stays | `test_crash_integration` |
| 29 | **Fixed** | Quad crash FX and lens use the previous accepted state (motion into the impact) | `test_mr_crash_presentation` |
| 30 | **Fixed** | Helicopter lens uses the crash's `obstacle_kind`; a ground crash beside a spectator is ground-only | `test_lens_person_strike` |
| 31 | Planned R4 | Rotational padding must not become a contact | — |
| 32 | Planned R4 | Remaining-tick motion after a nonterminal scenery response | — |
| 33 | Planned R4 | Transient water contact policy (capability) | — |
| 34 | Planned R1 | Water normal speed includes interface motion | — |

## Improved plan

The original eight slices ordered work by theme. The remaining items are now ordered by **what each change costs to qualify**. Native-mirrored sources (`REFERENCE_SOURCES` in `research/native-kernel/build.py`) silently move flights to the GDScript reference until the native kernel is rebuilt and requalified, so they ship together.

| Batch | Findings | Files | Gate in addition to the audit's acceptance |
|---|---|---|---|
| **R1 native batch** | 02, 03, 18, 19, 24, 27, 34 | `flight_session.gd`, `rotorcraft/impact_detector.gd`, `hull_contact.gd`, `ground_wheels.gd`, `lake_surface.gd` (mirrored) | One native rebuild and requalification on Windows, Linux and macOS (NK gates). Companion rebind. Flight-log baseline/candidate comparison for any trajectory change; re-record goldens only for an explained physics change. |
| **R2 vehicle physics** | 20, 21, 22, 25 | `multirotor/controlled_plant.gd`, `sim/airship/*` | Quad and airship replay/golden checks; contact energy invariant tests; recording identity test with real `.orfl` files. |
| **R3 car scenery** | 14 | ground-vehicle course/session adapter over the shared collision world | Explicit capability matrix; wall dedupe; bounded candidates with visible overflow; both stock cars, driven passes. |
| **R4 contact-time policy** | 23, 31, 32, 33 | `sim/scenery_collision.gd`, lake policy | Flight-log comparison at 240/480 Hz; no false-clear results; owner decision on transient water. |
| **R5 presentation follow-ups** | — | wreck/effects | Per-section compound core proxy with slide/rebound retuning (a compound box set made sideways slides tumble on gear boxes, so it needs its own tuning). Quad/airship obstacle identity for lens strikes. 1080p captures of asymmetric, slope and scenery crashes. |

Promote each audit probe into the owning suite when its finding is fixed, as done for 01, 04–13, 16, 17 and 26–30. Do not change an expected value to match a defect.

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
