# P-51D RC realism audit

2026-10-12 · **Status: P51-15…18 audit, correction and verification complete; aircraft physical acceptance remains experimental.** [Plan](../../P51-REALISM-PLAN.md) · [Reproduction tools](../../../research/p51/p51-15/README.md)

Later steps: [P51-19 trim calibration to the XP-51 flight data](P51-19/README.md) · [P51-20 planform ground effect](P51-20/README.md).

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

The generator also fixes stale descriptions of camber, CLmax, induced drag, throws and servo response. Full-size neutral-point scaling is explicitly an unvalidated hypothesis; the static-RPM anchor is a secondary report without a retained instrumented test. Solved rudder trim no longer claims to implement fixed fin incidence. No aerodynamic or propulsion numerical coefficient was retuned. The P-51 test fixture preserves the complete installed continuous-state layout and rejects invalid resets/faults; the current P-51 still uses four auxiliary slots.

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

1. Obtain actual reference-build mass, CG and component stations, then measured pendulum inertia. Current inventory dimensions and mounting stations are estimates.
2. Identify the installed engine/propeller thrust, torque, RPM and transient maps. Manufacturer two/three-blade simulations do not validate the selected four-blade extrapolation.
3. Measure model-scale rigging, trim and control response. Full-size neutral-point/airfoil sources and another RC kit's throws do not establish this build's behavior; trim currently requires about 6.12° up elevator at 25 m/s.
4. Validate low-Re stall and spin response against recorded flights. The current three-strip static stall model omits important dynamic effects; a direction-dependent scripted recovery is not physical acceptance.
5. Future supported work: retracts/flaps, fuel burn/CG movement, fixed fin incidence, fuselage yaw contribution, richer propwash, calibrated tires/oleos and P-51 product runway start. These remain explicit gaps, not partially active modules.
6. Real-radio/pilot evaluation, rendered handling review and slowest-target-hardware performance remain open. Headless numerical coverage cannot establish the RC pilot experience alone.

Standardization remains the shared foundation; this bounded pass corrects a demonstrated physical bookkeeping error and strengthens evidence before adding aircraft features. No parallel developer's model, scenery or UI work was reverted.
