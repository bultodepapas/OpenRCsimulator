# DR M0–M3 software slice — FPV quad on the shared kernel

2026-11-11 · Windows dev PC, Godot `4.8.beta2.official.cafc17a19` · **Status: software evidence on estimated data.** An experimental 5-inch-class FPV quad flies in the app (Home → RC garage → *Fly FPV quad*, or `--multirotor=openrc-fpv5-x1`) and can fly a local three-lap gate race. Nothing here is validated against a real aircraft, a firmware, a radio or a target-host performance budget. Plan and step IDs: [drone-racing plan](../../../plans/drone-racing.md); handoff contracts: [FPV pack](../../../../FPV/00_START_HERE.md); decisions: [DECISIONS](../../../DECISIONS.md#closed-loop-control-samples-the-accepted-frame-through-an-opt-in-protocol).

## What exists

| Step | Code | Test (checks) |
| --- | --- | --- |
| DR-16a kernel protocol | [`vehicle_model.gd`](../../../../app/sim/vehicle_model.gd), [`simulation.gd`](../../../../app/sim/simulation.gd) | `test_sf_framed_sampled` (50) |
| DR-03 reference oracles | [`research/drone-racing/DR-03`](../../../../research/drone-racing/DR-03/README.md) | 20/20, repeated byte-identically |
| DR-08/15 rates | [`rates.gd`](../../../../app/physics/multirotor/rates.gd) | `test_mr_rates` (115) |
| DR-07 controller, allocator | [`flight_controller.gd`](../../../../app/physics/multirotor/flight_controller.gd), [`allocator.gd`](../../../../app/physics/multirotor/allocator.gd), [`actuator_map.gd`](../../../../app/physics/multirotor/actuator_map.gd) | `test_mr_allocator` (40), `test_mr_controlled_plant` (63) |
| DR-05/06/09/18…20 plant | [`controlled_plant.gd`](../../../../app/physics/multirotor/controlled_plant.gd), [`electric_bus.gd`](../../../../app/physics/multirotor/electric_bus.gd) | `test_mr_electric_bus` (32), `test_mr_controlled_plant` (63) |
| DR-09a/21 sample rate, tune | — | `test_mr_sample_rate` (11) |
| DR-10…13 data | [`multirotor_data.gd`](../../../../app/physics/multirotor_data.gd), [generator](../../../../research/drone-racing/openrc-fpv5-x1/README.md), [`openrc-fpv5-x1.json`](../../../../app/data/multirotors/openrc-fpv5-x1.json) | `test_mr_data` (86), `derive.py --check` |
| DR-16b/17 session, flight log | [`session.gd`](../../../../app/sim/multirotor/session.gd), [`flight_log.gd`](../../../../app/sim/multirotor/flight_log.gd) | `test_mr_session` (63), `test_mr_flight_log` (30) |
| DR-14/29…31/35/36a/37 activity | [`app/vehicles/multirotor/`](../../../../app/vehicles/multirotor/), [`multirotor_input.gd`](../../../../app/input/multirotor_input.gd), [frame intake](../../../../research/drone-racing/DR-29/README.md) | `test_mr_input` (61), `test_mr_camera` (46), `test_mr_activity` (73) |
| DR-23…26/32/36b racing | [`app/sim/race/`](../../../../app/sim/race/), [course](../../../../app/data/race/tracks/openrc-practice-oval-1.json) | `test_race_track` (39), `test_race_gate_crossing` (19), `test_race_director` (30), `test_race_model` (30), `test_race_session` (49), `test_race_session_replay` (8), `test_mr_activity_race` (9) |

Run one with the [checked runner](../../../tools/shared.md): `python tools/godot/run_checked.py --timeout 240 --label mr --require-text ' 0 failed' -- <godot> --headless --path app --audio-driver Dummy --script res://tests/test_mr_session.gd`.

## Kernel protocol

`framed-sampled-v1` is opt-in. The cache defect of the frozen source (motor duties surviving a refused tick) cannot occur under it: there is no owner cache. TX-01…10 of the handoff ledger are asserted on a generic toy model: identical resampling, rollback of body, shafts, controller memory, modes and inputs after a malformed k1/k2/k4 or sample, refusal of a sample or stage that mutates its arguments, live kernel state, mass, model identity or a callback, one held sample across substeps and step-policy trial stages, detached full-frame reset with owner, context and tamper seals, restore equal to a fresh control, checkpoint inside `stepped`, a committed observer fault. Legacy parity: the diff was reviewed line by line by an independent reviewer, and `test_golden` (4 golden flights, worst position error 7.1e-15 m), `test_sf_vehicle_model` (40), `test_endpoint_transition` (274), `test_simulation` (11), `test_checkpoint` (104), `test_checkpoint_integrity` (149), `test_continuous_state` (42), `test_sf_event_refinement` (60), `test_sf_event_protocol` (46), `test_shaft_coupled` (101), `test_wheel_coupling` (84), `test_session_guards` (32), `test_heli_session` (42), `test_airship_session` (43), `test_rcv_session` (162) and `test_dr_multirotor_kernel` (15) pass unchanged. That review demonstrated one hole (a stage writing live sampled state was committed); it is closed by the integration-spanning guard and has its own check.

Limits: the guard covers enumerated kernel and model state, not arbitrary captured objects. `restore_checkpoint` takes array sizes from the live arrays, so an owner is reset to the layout before it restores (the session does).

## Controller and plant

- **Arming** (INPUT-03…08): held-high switch at entry, high-throttle edge, source not ready, new source generation, attested recovery, disarm override, rate-throttle accumulator and its zero-throttle action.
- **Response on the shipped build**, ±200 deg/s steps at 240 Hz: roll and pitch rise 47 ms, overshoot 4 %, settling 62 ms; yaw rise 9 ms, overshoot 0.3 %. Gains come from a software sweep on this estimated plant. First tune (no feed-forward, less derivative): 38 % overshoot.
- **NUM-01**: plant refinement at fixed control times converges (final position h vs h/2 2.3e-7 m, h/2 vs h/4 1.4e-8 m after the step manoeuvre).
- **NUM-02**: 240 Hz against 960 Hz with fresh feedback, and 960 against 1920 Hz, pass the 15 % / 20 % / 5-point screen on roll ±, pitch and yaw (worst: yaw rise 10 %, a 1 ms difference on a 9 ms rise). Yaw feed-forward failed it (45 %) and is off.
- **PHY-02**: the coupled shaft/body solve reproduces the handoff oracle (alpha 50.2512562814 rad/s², shaft 10050.2512563 rad/s², 100 W including the cross term) and zero total angular-momentum rate.
- **PHY-05/06/08**: the scalar stage equals `rotor.gd`/`airframe.gd` to 1e-12 on 300 random states; the closed-form bus equals the exhaustive active-set solve wherever it is taken; terminal energy plus pack loss equals the chemical energy drawn to 1e-6 relative, also with regeneration; the one-quadrant variant never returns current.
- **Braking**: 50 ms after a chop the damped bridge's shaft is at 1245 rad/s against 2320 rad/s coasting (from 3187), and the roll rate reaches 43 % of its target in eight ticks against 0 % coasting.
- **Contact and terminal events**: rest at the solved sag, armed idle without lift-off, takeoff, hard impact (also on an exhausted pack), propeller strike, obstacle strike, depletion, restore at a terminal endpoint still cut, pad reset.

Not modelled: inflow, descent and propwash, ground effect, ESC current limit, motor thermal state, sensor noise and delay, structural damage. The drive cut and the crash impact law act at the end of the detecting tick.

## Session, replay and activity

A refused `prepare`, reset or restore leaves the running flight, its tape and recorder untouched. A complete flight (arm, climb, Acro roll, Angle segment, crash) and a recording started mid-roll replay exactly from the pilot tape with the controller rerun; a truncated file, a flipped byte, an unknown format and a changed identity are refusals; a candidate with scaled gains reports deltas and never `exact`. Exact means same build and platform.

The activity was reviewed in the running app at 1920×1080 (muted): pad start, armed, hover and forward flight in the rigid FPV view, chase and pilot views, crash aftermath. The OSD horizon line coincides with the terrain horizon and banks with it. 4:3 content mode is not implemented.

## Local racing

`test_race_session` flies three laps of the shipped six-gate oval with a scripted pilot in a race session on the default field with its obstacle inventory: laps 22.87 s, 21.18 s and 21.18 s; ordered gate events with crossing times inside their ticks; one valid terminal record, saved once; 720-tick drive-inhibited countdown; GO refusals; missed-gate retry; solid gate frames; pad reset, crash and cancel aborts; a lap-2 checkpoint restored into the same and a second session replays 480 rows byte-identically; a moved-gate course refuses the envelope. `test_race_session_replay` records the whole race (16 376 ticks) and verifies it by exact replay.

Limits: chord-path evidence with a declared 250 m/s² envelope (0.54 mm at 240 Hz); a crossing in a tick whose body was corrected (a crash) is unresolved; upright gates only; local practice rules, no federation compliance.

## Cost

Raw per-tick elapsed time around `Simulation.step()` with the shipped build (kernel, controller and plant; no session observers, recorder or rendering), 2400 ticks each, GDScript reference, this PC:

| Case | p50 | p95 | p99 | max |
| --- | --- | --- | --- | --- |
| Hover in the air | 0.55 ms | 0.67–0.94 ms | 0.94–0.98 ms | 1.2 ms |
| Resting on the pad (four contact substeps) | 1.31 ms | 1.89 ms | 2.17 ms | 3.35 ms |

The handoff's 500 µs p95 development budget is **not met**. The tick was 1.37 ms p50 before the guard reuse, the validator move and the scalar stage. No tick exceeded the 4.17 ms deadline. This is one machine, not Gate P and not a target-host qualification.

**In-app audit, 2026-11-12** (same PC, rendered 1920×1080, muted, debug bridge `perf`/`frames`, unchanged physics): whole session tick `sim_step_usec` 0.87 ms in the air and **3.3–3.7 ms resting on the pad** (disarmed, armed, or in the race countdown), on the original and the audited presentation code alike. On the pad the frame rate falls to 28–58 fps against a steady 120 fps (p95 8.9 ms, no hitches) in the air. Cause: within 0.25 m of the terrain the plant integrates `CONTACT_SUBSTEPS = 4` RK4 substeps (16 evaluations per tick instead of 4). The presentation `_process` costs about 0.45 ms per frame (telemetry about 80 µs, now evaluated once per accepted tick). Reducing the pad cost needs a physics change (a resting fast path or adaptive substeps, with requalification); none was made.

## Open

Selected-build measurement and pilot review (DR-38…40), advanced rotor law (DR-04), native 1080p frame pacing and input latency, real radio and gamepad acceptance, sub-tick located cut and rotor-stop events, 4:3 view, ghosts and further courses (DR-27/28), rich audio and effects (DR-33/34), the firmware-style settings workspace and rates import UI (handoff P17–P21), required CI on the full suite.
