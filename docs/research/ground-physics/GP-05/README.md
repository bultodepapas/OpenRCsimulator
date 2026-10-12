# GP-05 integrated ground physics

Status: implementation integrated, 2026-10-11. Numerical verification is recorded below; independent RC calibration, pilot acceptance and the 500 µs target-machine budget remain open.

## Delivered model

The Stik, Extra and P-51 now integrate a separate rim-speed state for every wheel alongside the existing 240 Hz RK4 flight state. Each stage samples the field under each wheel, resolves the spring/damper reaction against the local terrain normal, and computes rolling resistance, longitudinal slip/spin-up and lateral grip separately. The combined tangential force is bounded by available tire grip. Wheel angular acceleration contributes the opposite body moment. Lift reduces contact load through the existing motion equations; an airborne wheel contributes no ground force and retains its spin. Throttle does not apply a brake or set a target speed.

Static anchors require small axle velocity and tire slip. Touchdown and contact loss use the same terrain as suspension compression and travel-limit detection. The existing six-degree-of-freedom equations produce weight transfer, tail lift, rotation, skid and asymmetric yaw. Aerodynamic and propulsion equations, generated geometry and aircraft mass/CG/inertia were preserved. The Avanti remains explicitly gear-up, without invented wheel contacts.

The authored wheel profiles distinguish wheel sizes and rotating inertia. Stik and Extra declare no brakes; P-51 brake equipment is unspecified and therefore applies zero torque. A separate bounded brake command exists in the force API and is tested with synthetic hardware; no current aircraft receives automatic braking or a new UI input.

| Aircraft | Mass, kg | Main / secondary radius, mm | Main / secondary spring, N/m | Main / secondary damping, Ns/m | Secondary steering |
| --- | ---: | ---: | ---: | ---: | ---: |
| Ugly Stik .60, tricycle | 2.8851 | 38.100 / 34.925 nose | 560 / 440 | 18.6 / 16.5 | +20° |
| Extra 300S .60, taildragger | 3.3643 | 34.925 / 12.700 tail | 673.706 / 222.246 | 16.492 / 9.472 | −25° |
| P-51D 120, taildragger | 21.5000 | 85.700 / 39.750 tail | 4405.888 / 1219.264 | 106.617 / 56.087 | −25° |

Coordinates are CG-relative body axes (forward/right/down). The full inertia tensor, CG, wheel coordinates, travel, quantities and individual source/evidence labels are retained in [the integrated inventory](../GP-03/profiles-integrated.json). Wheel inertia is an estimated solid-disk equivalent, not a measured tire property. Relaxation time is provisionally 0.03 s. Profile validation rejects incompatible wheel counts, invalid quantities and unsafe declared numerical scales before flight.

## Surface and presentation agreement

The physical surface lookup uses the renderer's field rectangles and precedence. The default runway is maintained grass; outside it is rough grass. Initial relief amplitudes are 1/4/7 mm for runway/mown/rough categories with deterministic 1.2/0.73/0.41 m wavelengths. A 0.5 m smooth height transition avoids a terrain-height step; rolling material changes remain discrete per wheel. These values describe load-bearing ground relief, not grass-blade height.

The renderer uses the same relief formula for nearby normals, with distance/pixel-footprint fading. It does not displace the coarse field mesh. Existing wheel pivots display spin, steering and compression without renaming model hinges. Struts remain rigid meshes, and hull collision retains its existing flat plane. The [terrain capture and shader checks](../GP-01/README.md) establish category/edge and formula agreement, not millimeter-accurate displaced silhouettes.

## Measurements

The [GP-02 analytic checks](../GP-02/README.md) cover load proportionality, zero airborne forces, force/power signs, grip bounds, reverse motion, brake availability, spin-up and timestep refinement. The [GP-04 scenario report](../GP-04/README.md) retains the aircraft/surface/speed matrix and raw measurements.

All 108 GP-04 cases passed their numerical checks, including 18 moving runway-edge crossings. Both mains crossed at distinct samples under positive load at each tested speed/direction. The 0.3 m drops exceeded provisional travel on the Extra and P-51 tail; these events remain explicit in the report. Full-session acceleration adds 12 separate powered/crosswind measurements.

At an initial 10 m/s with aerodynamics and propulsion disabled, direction-averaged distance to 0.1 m/s was:

| Aircraft | Runway, m | Rough grass, m |
| --- | ---: | ---: |
| Stik | 51.389 | 16.612 |
| Extra | 49.348 | 16.354 |
| P-51 | 65.046 | 21.244 |

Across 36 coast-down cases at 2/5/10 m/s, the largest deviation from the independent constant-drag estimate was 4.40%. This checks implementation consistency; these distances are not predictions calibrated against a real RC field. Drops from 0.1/0.3 m at 240/480/960 Hz differed by at most 0.76% in peak compression/rebound between adjacent rates. Maximum observed positive flat-ground mechanical-energy change was 3.41e-13 J. A force-only drop can exceed a gear's declared travel; it is not automatically a survivable landing.

The full-session acceleration probe retains thrust, aerodynamics, gravity, servos, wheel state and crash detection. At one second after full-throttle application from rest in calm air, runway/rough speeds were Stik 8.202/6.243, Extra 7.124/5.784 and P-51 3.043/1.894 m/s. Its [12 raw scenarios](../GP-04/session_acceleration.json) include a 5 m/s crosswind and terminal crash outcomes. Zero roll/pitch/yaw input is deliberately not a stabilizing pilot: six cases encounter hull contact before four seconds, including the calm P-51 runway run. These are measured response probes, not safe takeoff or crosswind operating limits.

Existing automated Stik takeoff and landing maneuvers remain meaningful complementary tests: takeoff reaches lift-off at about 2.325 s, 22.73 m and 20.62 m/s, while landing fixtures check approach, contact, containment, stopping and refinement. The takeoff oracle now includes wheel rotational effective mass and the actual load-weighted rolling coefficient. No tolerance was widened to hide the changed physics. Taildragger/nose-over tests retain their existing physical moment and support checks.

## Integration and verification

The original pre-implementation plan is consolidated into this delivery record; its original SHA-256 and audit state are in [initial-verification.json](initial-verification.json). Three bounded Luna-max tasks covered terrain, wheel/session configuration, and independent scenario verification. The lead reviewed and integrated their contributions from an isolated draft using guarded three-way merges.

Concurrent crash/audio and aircraft-v2 work was preserved. The only textual merge conflict combined the new v6 wheel trace metadata assertion with the other track's actual aircraft-input-format assertion. The aircraft-contract comparison now applies the same wheel-profile step to both legacy and v2 derivations; it still compares the complete derived models. No generated aircraft JSON was edited by the ground track.

Wheel states participate in reset, joint RK evaluation, checkpoint validation/fingerprints and trace metadata. `openrc-flight-meta v6` declares wheel layout, model, profile hashes, hardware status and initial continuous state. Existing CSV field layouts remain versioned as before; legacy traces remain readable. Tests that injected the old force callback now inject the joint body/continuous callback, ensuring failure and rollback checks still exercise the active path.

Post-integration airborne parity is **exact** for all four catalog aircraft in calm and 5 m/s wind over 1200 ticks each. The hash covers every body state, existing auxiliary state, loads and inputs at every tick: compare [baseline](gp-airborne-before.json) with [integrated](airborne-integrated.json). No airborne golden was re-recorded.

Final checks passed: [14 trace-acceptance tests](gp-integrated-trace-final.log), [10 Linux turbulence/reader tests](gp-integrated-turbulence-linux-final.log), five time-of-day CLI tests, and [eight ground/crash/landing commands](gp-final-ground/report.json). The new trace reader explicitly accepts unknown original launch wheel state after checkpoint restore while still requiring a complete recording-start state; positive/negative controls cover this boundary. [Final supplement](final-supplement/report.json) reconfirms exact eight-case airborne parity and the same injected-input state at 30/60/144 rendering FPS. The float64/transcendental guards and owned diff whitespace checks passed.

A native `--export-pack Linux` smoke test included the profile JSON and new scripts through the existing export rules. The packed app produced a valid [wheel-enabled v6 flight trace](packed-flight.csv); [export log](gp-pack-export.log), [launch log](gp-packed-flight.log). This verifies resource packaging, not release installers or all-platform performance. [Source hashes](source-sha256.json) identify the integrated implementation and probes.

The final focused aggregate is [31/31 test programs](verification-summary.json), plus the separate CLI, scenario, presentation and pack checks.

The first full native GDScript sweep parsed all 385 scripts and ran 191 test programs. Its [raw report](initial-native-full-report.json) is intentionally retained with the initial failures. Ground-related fixture issues were subsequently corrected and rerun. [Integrated tests](gp-integrated/report.json) pass all ground, wheel/profile, checkpoint, stiction, P-51, runway, takeoff, downwash, session-guard, shaft, battery, wash, trace and golden checks; its first aircraft-contract failure is superseded by the passing [follow-up](gp-integrated-followup/report.json). The follow-up also passes atmosphere/wind, crash audio, input, pause/runway UI and crash integration. Its nonexistent `test_crash_ground.gd` entry was a runner invocation error, not a product test.

The initial `app/test.sh` attempt stopped at the existing generated-grass freshness check; the unmodified live tree failed the same check. [That log](gp-full.log) is retained. Downstream checks were run explicitly: H7 one-ULP/branch sensitivity and all model contracts passed; [runtime log](gp-runtime-suite.log), [model log](gp-runtime-continuation.log). Native turbulence CLI uses a pre-existing `/tmp` fixture and must run under Linux. The old D8b experimental candidate also differs from the concurrently migrated v2 catalog outside its wing polar and is currently refused. These broader-suite issues are not reported as passes or attributed to wheel forces. Current results supersede earlier baseline crash/UI failures, which were resolved by their owning track during integration.

## Performance budget

The native Godot 4.7.2 measurements used Windows and an AMD Ryzen 9 5900X. Each contact regime warms 200 evaluations then records 2000 individual calls; each full-tick regime warms 200 ticks then records 1000. Takeoff uses repeated 120-tick blocks to avoid timing an uncontrolled taildragger after hull impact. Both versions start ground workloads from the same GP-04 supported poses. The baseline uses the original `Ground.loads`; the implementation uses the joint evaluator without diagnostic allocation.

These are **shared-workstation observations**, with other developer processes and validation work active. Two pairs reverse version order; the second retains every individual timing. They are not isolated target-machine measurements or a causal estimate of each individual change. See [baseline](benchmark-baseline.json), [implementation](benchmark-integrated.json), [repeated baseline](benchmark-baseline-repeat.json) and [repeated implementation](benchmark-integrated-repeat.json).

Second pair, microseconds per whole physics tick (median / p95):

| Aircraft | Regime | Baseline | Integrated |
| --- | --- | ---: | ---: |
| Stik | airborne | 448 / 653 | 650 / 740 |
| Stik | idle_runway | 611 / 971 | 1207 / 1420 |
| Stik | takeoff | 515 / 687 | 1168 / 1614 |
| Extra | airborne | 309 / 376 | 526 / 675 |
| Extra | idle_runway | 481 / 615 | 1055 / 1244 |
| Extra | takeoff | 529 / 727 | 981 / 1222 |
| P-51 | airborne | 583 / 838 | 797 / 981 |
| P-51 | idle_runway | 689 / 809 | 1279 / 1602 |
| P-51 | takeoff | 767 / 1043 | 1284 / 1554 |
| Avanti | airborne | 375 / 548 | 371 / 472 |

Across both pairs, the new complete three-wheel contact evaluation medians were 59–94 µs versus 9–20 µs for the baseline. The 75 µs allocation is not consistently met. The added ground-tick cost exceeds the provisional 150 µs allocation, and the 500 µs whole-tick target is **not met** for the wheeled aircraft. The baseline itself misses 500 µs in several regimes. Observed whole-tick p95 remains below the 4167 µs tick interval, which is headroom on this host, not a release guarantee. Follow-up should profile joint-state/validation allocations and terrain queries on the actual slow target, preserve the exact airborne and ground oracles, then optimize the measured hot path. No native dependency was introduced.

## Tuning

1. Keep geometry, mass, CG and full inertia correct in each aircraft's existing source pipeline; regenerate its physics data through that pipeline.
2. Fit static wheel loads/sag, then drops at several heights. Tune spring and damping separately and record travel exceedance; do not disguise excessive impacts by clamping compression.
3. Fit runway and rough-field coast-down with measured entry speed, distance, wind and throttle/engine state. Use held-out runs. Ground drag and aerodynamic drag must be identifiable separately.
4. Adjust `app/data/ground/wheel_profiles.json` only for wheel radius, rotating inertia, slip relaxation and sourced brake hardware. Keep `{value, unit, kind, source}` labels honest. Relaxation must satisfy the loader's 240 Hz stability bound; changing wheel inertia requires rerunning spin-up, energy and takeoff oracles.
5. Tune steering/slip after longitudinal losses. Validate both directions, one-wheel edges, wheel versus three-point touchdowns, tail-up behavior and crosswind corrections separately for each aircraft.

The rolling law uses `Crr_aircraft * [1 + (surface_factor - 1) * sqrt(R_max_aircraft / R_wheel)]`. Existing aircraft Crr already accounts for main-wheel size; scaling again against a global Stik wheel radius double-counts that effect and altered P-51 idle behavior. The current factors 2.5/5/7.5 and base Crr 0.04/0.04/0.03 are inherited estimates. The six-value surface table currently also uses those classes to choose relief amplitude: independent soil-height tuning requires separating the material identifier first.

## Remaining limits

Independent real-aircraft rollout, drop, spin-up and taxi measurements were not supplied. The present acceptance is numerical, with physical and pilot gates open. There is no free-caster shimmy, wheel gyroscopic coupling, unsprung multibody leg, deforming tire/soil, wet-grass model, retract actuation or independent brake input. Brake torque in the present API acts only during loaded contact; all production profiles are unbraked. Avanti ground operation needs model-owner deployed-gear/equipment work. Large terrain slopes/hills are not made collidable by this millimeter-relief implementation.

The visual probe also records an inherited 5 mm wheel-center/contact-reference offset on the Stik; Extra/P-51 mappings are approximately exact. Model geometry was preserved. The renderer steers about its model pivot rather than the local terrain normal, so millimeter-scale visual differences remain on bumps. See the [39-check visual probe and captures](../GP-03/README.md#integrated-visual-gear-check).

Primary technical sources and their applicability limits are retained in the [plan](README.md): JSBSim contact architecture, FAA soft-field and tailwheel mechanisms, NACA wheel spin-up research, and version-specific Godot documentation. They support the mechanisms, not the provisional RC coefficients.
