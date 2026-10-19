# P-51D RC realism audit

2026-10-12 · **P51-15…18 dated audit, correction and verification evidence.** [Current guide/remaining plan](../../P51-PLAN.md) · [Reproduction tools](../../../research/p51/p51-15/README.md)

Scope checked 2026-10-19: the original snapshot below predates flaps/retracts, product runway start, later trim/directional corrections and finite gasoline fuel. Its masses, auxiliary-slot count, proposed features and passing/failing counts describe that snapshot. Current implementation and pending acceptance have one home in the linked aircraft guide. Historical manifests and hashes remain unchanged.

Later steps: [P51-19 trim calibration to the XP-51 flight data](P51-19/README.md) · [P51-20 planform ground effect](P51-20/README.md) · [P51-21 runway start](P51-21/README.md) · [P51-22 slipstream downwash regression](P51-22/README.md) · [P51-23 CI and Linux verification](P51-23/README.md) · [P51-24 lateral-directional audit](P51-24/README.md) · [P51-25 fuselage directional term](P51-25/README.md) · [P51-26 slipstream quadrature and sidewash](P51-26/README.md) · [P51-11a flaps and engine smoke](P51-11a/README.md) · [P51-11b retractable gear and P51-11c brakes](P51-11b/README.md) · [P51-V13 scale lights](P51-V13/README.md) · [P51-V14 rudder on the aerodynamic hinge](P51-V14/README.md) · [P51-V15 control-surface audit](P51-V15/README.md).

## Delivered correction

The quarter-scale P-51 inventory treated separated pairs of servos and main landing gear as continuous boxes through the empty space between them. The generator now creates individual left/right components. Their locations and local dimensions remain explicitly estimated. This corrects the mass-distribution equations without inventing measured hardware data.

| Quantity | Baseline `df36b44` | Candidate |
| --- | ---: | ---: |
| Inventory mass | 21.499999 kg | unchanged |
| CG, LE frame `[aft, right, up]` | `[0.177762744, 0, -0.071146038]` m | unchanged |
| Roll inertia Jxx | 3.412230 kg·m² | 3.861834 (+13.18%) |
| Pitch inertia Jyy | 6.817989 kg·m² | unchanged |
| Yaw inertia Jzz | 9.496622 kg·m² | 9.946226 (+4.73%) |
| Product Jxz | −0.269807 kg·m² | unchanged |

For a separated pair, the lateral parallel-axis term is `M y²`; a continuous box uses `M width²/12`. The [independent oracle](../../../research/p51/p51-15/test_inventory.py) checks the resulting +0.449604 kg·m² roll/yaw change, retained mass/CG, full tensor, positive definiteness and principal-moment inequalities. It runs in `app/test.sh`. More roll inertia changes angular acceleration, not the steady roll-rate equilibrium by the same percentage.

The generator also fixed stale descriptions of camber, CLmax, induced drag, throws and servo response. Full-size neutral-point scaling was explicitly an unvalidated hypothesis; the static-RPM anchor was a secondary report without a retained instrumented test. Solved rudder trim did not implement fixed fin incidence. This correction retuned no aerodynamic or propulsion coefficient. The fixture preserved the complete installed continuous-state layout and rejected invalid resets/faults; this snapshot used four auxiliary slots.

## Consumer and behavior audit

| Path | Consumer/effect and disposition |
| --- | --- |
| `assets/aircraft/p51d-mustang-120/geometry.json` → P51-05 generator | Source dimensions, control stations, gear track, mass inventory and derived coefficients. Geometry/model ownership retained. Generate JSON and derivation together. |
| `app/physics/aircraft_data.gd` → rigid-body model | Validates v2 configuration, computes inventory mass/CG/full inertia; shared dynamics and rigid-body derivative consume it. No aircraft-ID branch or runtime equation change. |
| `app/app_state/aircraft_catalog.gd` → `FlightSession` | Experimental P-51 selection, trim, atmosphere, inputs, simulation initialization and lifecycle. Shared catalog/schema checks exercised. |
| `Commands` / servo → `Aero` / `Dynamics` | Trim plus normalized commands become rate-limited surface deflections and forces/moments. Both signs and low/high rates tested. Command clipping makes opposite inputs unequal around a large pitch trim. |
| `Propulsion` / shaft / slipstream | Gasoline engine, four-blade propeller, thrust angles, torque/gyro/P-factor and tail wash; split/coupled throttle transients compared. Installed maps remain estimates. |
| Gear / field contact → session crash | Locked-down taildragger, spring/friction terrain contact and hull crash. Constructed parked, takeoff and landing fixtures; exact checkpoint/restart. Production P-51 runway launch remains unsupported. |
| Model / hinge interface / other systems | All four model contracts and P-51 clearance checks pass. Existing hinge/node interface, audio, HUD, replay and crash consumers retain shared contracts; broad suite covers these integrations. No new flap/retract animation or force capability. |

Detailed reviews: [physics and configuration](P51-15/physics-audit.md), [ground/lifecycle method](P51-15/ground-audit.md), [primary sources and limits](P51-15/sources.md).

## In-engine evidence

The P51-15 comparison predeclared 1% bands for steady metrics and 5% for smooth transients. Contact events, nonlinear stalls/spins and stochastic weather were reported individually. Those comparison bands are not physical acceptance tolerances.

Godot **4.7.2 official** on native Windows and an isolated LF Linux checkout. Thirty-four airborne and five ground scenarios were run on both baseline and candidate at 240 and 480 Hz: **156 scenario executions**, plus reset/checkpoint/crash checks. All saved cases completed with finite, continuous states and no unintended crash or simulation fault. These are numerical/model predictions, not real-aircraft validation.

The [airborne report](P51-15/airborne-results.md) covers upright/inverted trim, glide, axis response, turns/slips, throttle steps, idle descent, stalls, commanded spin entry/recovery, pitch-loop inputs and weather/density. Steady trim is unchanged to numerical precision. Selected smooth response metrics change at most 4.54%; their candidate step refinement is at most 0.66%. Nonlinear stall/spin differences are reported individually: for example the idle full-up case's peak angle of attack changes 27.39°→37.97°. No claim of a closed planar loop or physically validated spin is made. Stochastic weather does not supply a matched-noise step-refinement test.

The [ground report](P51-15/ground-results.md) covers stopped/idle motion, rudder-free and heading-guided takeoff, approach/flare/landing. Candidate guided liftoff at 240 Hz is 3.996 s / 36.56 m / 22.07 m/s. Touchdown is 19.86 m/s with 1.15 m/s modeled sink; net touchdown-to-final along-runway displacement is 139.01 m. At 480 Hz it is 141.17 m (+1.56%). A contact-only distance measure varies 6.39% through a rebound and is retained as a sensitive metric, not passed off as rollout. All four lifecycle runs replay exactly after 240 ticks; deliberate hull crash restarts exactly after 1.5 s.

The ground harness was subsequently hardened to fail on incomplete/crashed scenarios even when states remain finite. Final reruns use `final-*-ground-*.json`; the original reports remain intact for review.

## Identity and integration

[Baseline](P51-15/baseline-manifest.json) and [candidate](P51-15/candidate-manifest.json) app manifests isolate this work from concurrent landscape/docs development. The frozen candidate app overlays only P-51 JSON and its envelope fixture. The first three airborne runs predate runner self-hashing and before/after checks; their identities still pin the probe and aircraft inputs. The fourth airborne and all ground runs include these checks. No flight-equation change occurred between them.

Final provenance review changed one JSON `source` string after the flight snapshot. [Final identity](P51-15/final-identity.json) verifies that frozen→final data differs only in source text and that baseline→final numeric/type/shape changes are confined to inventory. It also hashes the final generator, fixture, CI hook and research tools. The new inventory CI hook was added after the frozen full-suite run began and is verified separately; it is not claimed as part of that earlier invocation.

Native focused verification passes the P-51 **15 handling + 15 envelope + 12 ground checks**, aircraft data/schema, propulsion, runway-start policy, all four model contracts and P-51 clearance. The first catalog run encountered missing imported PNG resources; after the recorded resource import, its rerun passed 36 checks without engine errors. Both logs are retained, and the reproducible runner now imports resources first. See [focused results](P51-15/native-focused/results.json) and [catalog rerun](P51-15/native-catalog-after-import.log).

The [integration report](P51-15/integration.md) records 206/208 unit scripts and all 27 downstream integration groups passing. The full-suite attempt is not green: [baseline triage](P51-15/baseline-triage/triage.md) attributes an extreme-density Ugly Stik trim failure and a time-of-day/scenery assertion to the unchanged baseline. Continuation preserves coverage beyond the first failure; it does not turn `app/test.sh` into an uninterrupted pass. Repeated trim/stalled/ground timings show no repeatable >5% slowdown; the existing 500 µs target remains unmet on this host for both baseline and candidate.

## Remaining physical acceptance

The [current acceptance plan](../../P51-PLAN.md#limits-and-next-evidence) owns build measurements, installed propulsion, model-scale stability/stall and pilot/target-hardware gates. Features proposed in this audit were subsequently delivered where recorded in the later-step reports above. The 6.12° trim and fixed-gear/prescribed-fuel observations belong to the original snapshot, not today's configuration.
