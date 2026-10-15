# SF-00…02 — Simulation charter, `VehicleModel` contract, fixed-wing and rotorcraft adapters

2026-10-15 · **Status: implemented. Every flyable airplane and the research helicopter (hover and pad start) fingerprint byte-identically against HEAD (10/10); focused kernel, checkpoint, replay, propulsion and helicopter suites pass; every one of the 466 HEAD test programs has the same status and check count on this tree (seven pre-existing HEAD failures, none new), and the two new programs pass.** Steps SF-00, SF-01 and SF-02 of the [simulation foundation plan](../../../plans/simulation-foundation.md). This verifies structure and numerical identity; it does not change or validate any vehicle's physics.

## Change

| File | Change |
| --- | --- |
| [`app/sim/vehicle_model.gd`](../../../../app/sim/vehicle_model.gd) (new) | The contract: layout (`input_size` > 0; `aux_size`, `modes_size`, `continuous_size` either -1 for the H8 "arrays at reset fix the layout" rule or a declared size), free-form `identity`, and the read-only evaluators `loads`, `stage`, `block_loads`/`block_derivative`, `stage_rotor_momentum`, `rotor_momentum`, `pre_tick`, `post_tick`/`post_tick_joint`, `block_aux`, `step_policy`. `validate()` checks the static shape. |
| [`app/sim/simulation.gd`](../../../../app/sim/simulation.gd) | `model` and `set_model()`; the tick transaction reads layout and evaluators only from the model. The hard-coded `input_size in [4, 6]` becomes `model.input_size > 0`; declared sizes are enforced at reset and checkpoint restore (`_layout_matches_model`). The pre-SF-01 properties (`loads`, `input_size`, `pre_step`, `post_step`, `post_step_joint`, `rotor_momentum`, `continuous_loads`, `continuous_derivative`, `continuous_evaluate`, `continuous_rotor_momentum`, `continuous_aux`, `continuous_step`) remain as forwarding aliases so the 27 tests that configure the kernel field by field keep working; SF-03 migrates them and deletes the aliases. The call sequence inside `step()` is unchanged. |
| [`app/sim/flight_session.gd`](../../../../app/sim/flight_session.gd) | `_commit_aircraft` builds and installs the fixed-wing model (`loads`, `pre_tick`, `rotor_momentum`, identity `{fixed-wing, loads_law}`, 4 or 6 inputs). Propulsion and contact callbacks are still configured through the aliases (`PropulsionRuntime.CALLBACK_FIELDS` unchanged); the laws themselves still live in the session, so this is an adapter, not a relocation. |
| [`app/sim/helicopter_flight_session.gd`](../../../../app/sim/helicopter_flight_session.gd) | Installs the rotorcraft model: 4 inputs, 1 sampled rpm, `stage`, `step_policy` (rotor-stop adapter), `block_aux`. The continuous size is declared per start in `reset()`: 6 rotor states in hover, 14 on a pad start (four N/E elastic skid-friction pairs). |
| [`app/tests/test_sf_vehicle_model.gd`](../../../../app/tests/test_sf_vehicle_model.gd) (new) | 27 checks: contract rejections, `set_model` refusal leaves the model untouched, alias forwarding including `Object.set`, five inputs accepted, free fall at g·t as the kernel's known answer, declared layout enforced at reset and restore, -1 keeps the H8 rule. |
| [`app/tests/fingerprint_vehicles.gd`](../../../../app/tests/fingerprint_vehicles.gd) (new) | Proof tool, not a test: SHA-256 over state, continuous, aux, modes and k1 loads after reset and after every tick of a fixed input schedule, for every flyable airplane (960 ticks) and the helicopter in hover and from the pad (1200 ticks). Writes JSON with `--output=`. |
| [`app/test.sh`](../../../../app/test.sh) | The parse step no longer descends into `./captures/` (gitignored local outputs that can hold stale app copies; a fresh clone has none). |
| Documents | [DECISIONS](../../../../DECISIONS.md) charter row; [AGENTS](../../../../AGENTS.md) reconciliation sentence and kernel rule; [STACK](../../../../STACK.md) boundary; [ROADMAP](../../../../ROADMAP.md) track line; [documentation map](../../../README.md) registry row; [LEARNINGS](../../../../LEARNINGS.md) per-start layout lesson; plan status. |

## Proof

| Check | Result | Record |
| --- | --- | --- |
| `fingerprint_vehicles.gd` on a HEAD copy versus this tree, same host and build | **10/10 identical**: Ugly Stik, three glow Stiks (17 continuous values), Extra, P-51, Ventage Jet (6 inputs, continuous turbine), Timber (electric), helicopter hover (6 continuous) and pad start (14 continuous); no faults | [HEAD](results/fingerprints-head.json), [SF-01](results/fingerprints-sf01.json) |
| `bench_regimes.gd` fingerprints (H15 method) | **32/32 identical**; 14 real fingerprints (Stik, Extra, P-51 in four regimes; Timber trim/stall) and 18 identical fixture faults, because that tool predates continuous-state propulsion and cannot fixture glow, electric or turbine aircraft | [comparison](results/bench-regimes-comparison.txt) |
| Contract test | 27 checks, 0 failed | [log](results/contract-test.log) |
| Focused suites on this tree: integrator, rigid body, H8 checkpoints (92), session guards (32), continuous state (42), RK stage time (22), retractable gear (68), propulsion runtime (214), coupled shaft (43), continuous turbine (46), glow coupling (65), wash transport (42), goldens, H8-R1 checkpoint integrity (149), H9-R1 replay integrity (153), failure shutdown (206), touchdown (12), ground contact (22), helicopter hover session (42), helicopter ground session (56) | all pass | [log](results/focused-tests.log) |
| Full test loop on a HEAD copy and on a copy of this tree | 466/466 programs with identical status and check-count summary; the 7 failures are the same pre-existing set; `test_sf_vehicle_model.gd` passes 27 checks | [HEAD table](results/suite-head-results.txt), [SF-01 table](results/suite-sf01-results.txt), [sections](results/suite-sections.txt) |

The first declared helicopter layout (six continuous values for every start) refused every pad start; the HEAD copy passed the same test. The per-start declaration above fixed it without changing any trajectory, which is the [LEARNINGS](../../../../LEARNINGS.md) entry for SF-02.

### Full suite

The stock `app/test.sh` stops at the first failing program, and HEAD has seven of them on this host, so the loop was run through a continue-on-failure variant ([test_all.sh](results/test_all.sh): identical sections and timeouts, each program recorded as `RESULT PASS|FAIL name summary`) on the HEAD copy and on the copy of this tree. The 46 sections before the loop (imports, helicopter and standardization references, H6/H7 guards, parse check) passed on both copies under the stock script; the post-loop sections ran identically up to the Turbo Lumber Evolution asset identity check, which needs the external delivery folder the copies exclude ([list](results/suite-sections.txt)).

Shared pre-existing failures, identical on HEAD and here: `test_p51_envelope`, `test_p51_ground`, `test_p51_handling` (one check each, the open P51-22 regressions), `test_rcv_airfield_course` (two lake-path checks), `test_rudder_authority` (the estimated recovery screen, same peak numbers on both trees), `test_yaw_damping` (the open R02 integration gate, worst 7.75 % on both trees) and `test_rcv_powertrain` (60 s timeout with three suites in parallel; it passes 9/9 alone on the HEAD copy). Three programs write to `res://../tmp`, which the gitignored `tmp/` folder must provide; the copies create it.

### Method

The HEAD copy is an rsync of the working tree without `app/captures`, `.git` and `docs`, with the three touched session/kernel files replaced by their HEAD versions and the new files removed. Both copies have `docs` linked, a `.tools` folder linking the pinned Godot binary, and one snapshot commit so the AS fresh-clone check can clone them. Running the suite from the working tree itself failed in the parse step on `app/captures/l9c/disabled-surface-app`, a stale app copy under the ignored captures folder; that is the `test.sh` change above. Commands:

```sh
G="$(app/get-godot.sh)"
"$G" --headless --path app --audio-driver Dummy --script res://tests/fingerprint_vehicles.gd -- --output=/tmp/fingerprints.json
"$G" --headless --path app --audio-driver Dummy --script res://tests/test_sf_vehicle_model.gd
app/test.sh
```

## Limits

- Cost was not re-measured on a quiet host: concurrent suites ran during every timing here. The kernel's evaluation sequence is unchanged; the additions are one property indirection per callback and a contract validation at reset and restore, both outside the stage loop. A quiet-host measurement with the H15 method belongs to the next performance step.
- The fixed-wing laws, propulsion runtime and contact filters still live in `FlightSession`; the model is an adapter over them. The compatibility aliases and the field-by-field test configuration are retired in SF-03.
- `bench_regimes.gd` cannot fixture continuous-state aircraft; `fingerprint_vehicles.gd` is the fingerprint tool for the whole fleet from now on.
- Nothing here validates any vehicle physically.

Commit message: `SF-00…02: VehicleModel contract; fixed-wing and rotorcraft sessions install models; 10/10 vehicle fingerprints byte-identical, 27-check contract test`
