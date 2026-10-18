# SF-03 — RC ground vehicle on the shared Simulation kernel

2026-10-15 · **Status: implemented. The truck's 960-tick scripted run fingerprints byte-identically against HEAD; the whole fleet stays identical (11/11); the SF-03 kernel test passes 23 checks; every one of the 466 HEAD test programs has the same status and check count on this tree (seven pre-existing HEAD failures, none new).** Step SF-03 of the [simulation foundation plan](../README.md). This changes who owns the truck's tick, not its physics; nothing here validates the vehicle physically.

## Change

| File | Change |
| --- | --- |
| [`app/physics/ground_vehicle/vehicle_dynamics.gd`](../../../../app/physics/ground_vehicle/vehicle_dynamics.gd) | `step()` is split into `begin_tick()` (validation, cached initial road sample, substep count for wet zones and wall boxes) and `tick_policy()` (per-substep classic RK4 through `physics/integrator.gd`, the exactly-zero-derivative rest shortcut without renormalization). The private `_rk4_step` is deleted: the truck no longer carries its own RK4. `stage_derivative()` exposes the validated tick's stage derivative for the session. `step()` keeps its signature for oracles, parity tests and source-only callers and now runs the same policy. `SOLVER_VERSION` is unchanged because the law and its results are unchanged. |
| [`app/sim/ground_vehicle/session.gd`](../../../../app/sim/ground_vehicle/session.gd) | Owns a `Simulation` child with `process_mode` disabled, so ticks come only from `tick_once()`/`advance()`. `_install_kernel()` builds the truck's `VehicleModel` (4 inputs, no sampled or discrete state, 18 declared coupled values, identity with the solver version and state layout) with `stage` = the 31-value derivative split into `body_derivative` and `derivative`, and `step_policy` = `tick_policy` with the tick's substep count. The 31-value state, `tick` and `_state` are now read from the kernel; the duplicated tick loop, checkpoint-time clock and fault bookkeeping for the state are gone. `tick_once()` takes a kernel checkpoint before stepping and restores it if telemetry or the damage observer rejects the tick, so the pre-SF-03 transaction (nothing committed on a rejected tick) is preserved. Manual recovery and JSON checkpoint restore go through `_restore_kernel_state()`, a kernel checkpoint at the requested tick. The JSON checkpoint format `openrc-ground-vehicle-checkpoint v3` and the recording format are unchanged, so the four committed water-entry checkpoints still restore. |
| [`app/tests/test_sf_ground_vehicle_kernel.gd`](../../../../app/tests/test_sf_ground_vehicle_kernel.gd) (new) | 23 checks: kernel ownership and disabled engine stepping, declared layout, state composition, clock, JSON checkpoint restore through the kernel with exact replay, manual recovery at the same tick, one kernel tick byte-identical to `VehicleDynamics.step`, a kernel refusal faulting the session without committing, reset clearing the fault. |
| [`app/tests/test_rcv_vehicle_dynamics.gd`](../../../../app/tests/test_rcv_vehicle_dynamics.gd) | Its failure diagnostic replayed the final RK4 combination through the deleted private `_rk4_step`; it now replays it through `tick_policy` with one substep. No assertion changed. |
| [`app/tests/fingerprint_vehicles.gd`](../../../../app/tests/fingerprint_vehicles.gd) | Adds the ground vehicle (default garage course, fixed throttle/steering/brake/reverse schedule, SHA-256 over `state_snapshot()` per accepted tick) through the public session API only, so the same tool runs on trees before SF-03. |

## Proof

| Check | Result | Record |
| --- | --- | --- |
| `fingerprint_vehicles.gd` on a HEAD copy versus this tree | **11/11 identical**: the eight airplanes, helicopter hover and pad start, and the ground vehicle (960 ticks, 18 coupled values, no fault) | [HEAD](results/fingerprints-head.json), [SF-03](results/fingerprints-sf03.json) |
| SF-03 kernel test | 23 checks, 0 failed, including "kernel tick is byte-identical to `VehicleDynamics.step`" | [log](results/kernel-test.log) |
| Every `test_rcv_*` program on this tree | 24 of 26 pass ([log](results/rcv-tests.log)). `test_rcv_airfield_course` fails two lake-path checks identically on the HEAD copy ([HEAD log](results/airfield-course-head.log)): pre-existing, unrelated to the session. `test_rcv_vehicle_dynamics` first failed to parse because its diagnostic named the deleted `_rk4_step`; after the reroute above it passes its 53 checks with no engine error. | [dynamics rerun](results/test_rcv_vehicle_dynamics.log) |
| Full test loop on a copy of this tree versus the HEAD copy | 466/466 programs with identical status and check-count summary; the same 7 pre-existing failures as HEAD ([SF-01 full-suite notes](../SF-01/README.md#full-suite)); both new `test_sf_*` programs pass | [SF-03 table](results/suite-sf03-results.txt), [HEAD table](../SF-01/results/suite-head-results.txt) |

### Why byte identity was expected

The truck's private RK4 and the kernel's `rk4_step_at` perform the same operations in the same order: stage states `s + (dt/2)·k` (division by two is exact), the weighted sum `((k1 + 2k2) + 2k3) + k4`, `s + (dt/6)·sum`, then a quaternion renormalization that divides each component by `sqrt(q0² + q1² + q2² + q3²)`. The kernel's k1 is the same `_derivative_core` result, split into body and coupled parts and joined again. The rest shortcut and the substep plan are reproduced in `tick_policy`. The fingerprint confirms it; the argument explains it.

## Limits

- Telemetry, damage, events and recording remain tick-boundary observers in the session. The per-tick kernel checkpoint that gives them a rollback costs a few microseconds against a millisecond-scale truck tick; moving observers into the kernel transaction is SF-04's event protocol, not this step.
- The truck's stage reports zero body loads to the kernel: the coupled generalized solve does not separate them, and telemetry owns the forces. Nothing reads that record for the truck.
- Cost was not re-measured on a quiet host. The evaluation sequence is unchanged; the additions are the per-tick kernel checkpoint and property indirection outside the stage loop.
- The 27 tests that configure the kernel through the pre-SF-01 properties were migrated and the aliases deleted on 2026-10-15; see [Alias cleanup](#alias-cleanup).

## Alias cleanup

2026-10-15 · The SF-01 compatibility properties on `Simulation` (`loads`, `input_size`, `pre_step`, `post_step`, `post_step_joint`, `rotor_momentum`, `continuous_loads`, `continuous_derivative`, `continuous_evaluate`, `continuous_rotor_momentum`, `continuous_aux`, `continuous_step`) are deleted. Every caller sets the `VehicleModel` fields through `sim.model`:

| Change | Where |
| --- | --- |
| 194 property uses rewritten mechanically (`<sim>.<old>` to `<sim>.model.<new>`; `pre_step` to `pre_tick`, `post_step` to `post_tick`, `continuous_evaluate` to `stage`, `continuous_loads/derivative/aux` to `block_*`, `continuous_rotor_momentum` to `stage_rotor_momentum`, `continuous_step` to `step_policy`) | `app/sim/flight_session.gd` (post-tick filters) and 31 scripts under `app/tests/` |
| `PropulsionRuntime.CALLBACK_FIELDS` names the model fields; `FlightSession._configure_continuous_callbacks` and the runtime test install them with `sim.model.set` | `app/sim/aircraft_propulsion_runtime.gd`, `app/sim/flight_session.gd`, `app/tests/test_aircraft_propulsion_runtime.gd` |
| String-keyed loops that cleared the propulsion callbacks use the model names | `app/tests/test_lake_session.gd`, `app/tests/test_aircraft_contact_session.gd` |
| The three alias-forwarding checks became one retirement check (`sim.get(<old name>) == null` for all twelve) | `app/tests/test_sf_vehicle_model.gd` (25 checks) |
| 63 lines of forwarding properties and their header comment removed | `app/sim/simulation.gd` |
| 38 further uses in 14 research scripts rewritten the same way after the full suite caught the two it drives (`research/ground-contact/e5a/checks.gd`, `e5b/checks.gd`: engine error and a hang in the ERR-trapped section); all 14 parse except `research/native-slipstream/verify.gd`, whose preload of `res://tests/gate_p/adapter.gd` has been missing since 2026-10-07 | `research/` (aircraft-standardization contact probe, Avanti av20 probe, climb-trim probe, d8b-r2 probe, glow bench, e5a/e5b checks, rotor event probe, physics-audit column-integration copies and R11 diagnostic, EL1 bench, EL2a-P3 inertia prototype) |

| Check | Result | Record |
| --- | --- | --- |
| Fleet fingerprints, baseline commit `1da9e092` (the commit before the cleanup) versus this tree | **24/24 identical** | [comparison](results/alias-cleanup-fingerprint-comparison.txt), [baseline](results/alias-cleanup-fingerprints-base.json), [cleanup](results/alias-cleanup-fingerprints.json) |
| Every touched test program plus the kernel, law, multirotor, rotorcraft and ground-vehicle suites | 41 programs: 40 pass; `test_shaft_coupled` fails two trace-metadata checks that fail identically on the untouched baseline tree and pass at d16ed71a, before merge f78901b9 brought the upstream P-51 data rewrite (pre-existing, see the results file) | [results](results/alias-cleanup-tests.txt) |
| Full continue-on-failure suite on a copy of this tree | 489 programs: 464 pass, 25 fail. Six failures are the known pre-existing set (P-51 envelope/ground/handling, `test_rcv_powertrain` timeout, `test_rudder_authority`, `test_yaw_damping`; `test_rcv_airfield_course` now passes). The other 19 (aircraft contract, atmosphere flight, Avanti rudder, control-surface observation, failure routes, lake geometry bake, overlay manager, RCV damage session, retractable gear ground, shaft coupled and ten UI programs) passed in the SF-04 suite and fail with identical status and summary on the untouched baseline tree `1da9e092`: they arrived with the upstream merge `f78901b9`, not with the cleanup. The AS-01/02 section's P-51 flaps refusal is fixed in `9504f481`. Six python sections timed out under concurrent load; rerun alone, the four CLI programs (trace acceptance, atmosphere, atmosphere column, shaft) fail one P-51 trace-schema assertion each, identically on the baseline tree (upstream), while the ground-contact e5a/e5b verifiers exposed a real cleanup regression in research scripts outside `app/`, fixed by migrating them (both pass now) | [suite](results/alias-cleanup-suite-results.txt), [19-program comparison](results/alias-cleanup-suite-newfail-comparison.txt), [reruns](results/alias-cleanup-suite-reruns.txt) |

Commit message: `SF-03: run the RC ground vehicle on the shared Simulation kernel through its VehicleModel; delete the truck's private RK4; 11/11 vehicle fingerprints byte-identical`
