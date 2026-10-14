# AV-09: retractable landing gear

2026-10-14. Implementation and software qualification for the supplied Ventage Jet Blender model. This closes the landing-gear portion of AV-09; flap aerodynamics remain separate.

## Evidence and assumptions

The [SebArt A200 manual](https://www.sebart.it/download/AVANTI%20S%20JET%202.2m-Manual%20Intro.pdf) describes pneumatic retracts with a dual air valve, a separate nose-wheel steering servo and optional pneumatic wheel brakes. It does not specify cycle time, brake torque, spring rate or damping. The [manufacturer product page](https://www.sebart.it/jets-L.html) identifies the aircraft family. The installed optional brakes and rudder-to-nosewheel mix are explicit simulator configuration choices.

The supplied Blender `GearRetract` action provides the actual motion: frame 211 is stowed, frame 129 is deployed. The exporter samples 83 poses, including all twelve moving carriers/linkages and the nose door. Interpolated mesh vertices differ by at most 0.412 mm at sampled interval midpoints; the maximum carrier quaternion error is 0.8091°. These compare against the authored action, not measurements of a manufactured airframe.

Deployed model-space wheel centres are `[-0.320,-0.19212,0.345]`, `[0.320,-0.19212,0.345]` and `[0,-0.201,-0.518]` metres (right, up, aft). Main radius is 0.043378 m; nose radius is 0.035320 m. Contact paths use the centre minus radius along model up. The physical generator applies the existing wing-datum shift and CG conversion to every sample. This is a spherical point-contact envelope, not a resolved tilted tire patch.

Cycle times are estimated at 2.5 s each way. Estimated deployed drag area is 0.02 m² (11.025 N at 30 m/s and 1.225 kg/m³), ramped by extension. Downlock is required to support weight. Contact while unlocked uses zero admitted travel and produces the existing terminal-impact behavior. Full-down spring/damper and tire coefficients use the shared ground law; main brakes act through integrated wheel speed. No aerodynamic flap change accompanies deployment.

## Runtime and reproducibility

`G` requests extend/retract; `B` applies main brakes while held. A configured radio gear AUX owns the target, otherwise the semantic gear-toggle binding or keyboard can request it. Nose steering follows the existing yaw servo. Ground starts are downlocked and airborne starts stowed. The simulator inhibits retraction while a deployed wheel supports weight; this is not a claim about the pneumatic hardware.

`retractable_gear.gd` owns the float64 actuator, contact path and incremental drag. `FlightSession` uses the same accepted fraction for loads, limits, observations and rendering. Twelve carrier poses are interpolated by the common imported-model extension; wheel spin, nose steering and lower-leg compression are applied afterward. The original master is preserved; the prepared Blender, GLB, sidecar, physics JSON and identity manifests are generated.

Six-input sessions append gear target and brake demand to the four primary controls. Two gear states precede turbulence in auxiliary state. Checkpoints pin their layout and law; metadata v8/trace v10 preserve command, accepted target, actuator fraction and brakes. Legacy fixed-gear aircraft retain their original four-input layout. Timing reversal, reset and rejected transactions preserve deterministic state.

## Limits

Timing, brake torque, suspension and tires are estimates requiring physical measurement. The wet inventory, CG and inertia remain fixed during gear motion. The contact law is compliant point support; it does not resolve pneumatic pressure, tire carcasses, strut link masses or gear structural failure. The pre-existing AV-02 aerodynamic surrogate and turbine/fuel limitations remain as documented in the [aircraft guide](../../../AVANTI-S-PLAN.md). Software tests establish implementation consistency, not physical validation.

## Verification

Godot 4.7.2, Windows, 2026-10-14. [Verification manifest](verification.json) records identities, checks and retained logs. The [source conformance report](conformance/verification.json) passes all 17 commands, including generated identities, schema/module parity, historical migration, imported-model/render contracts, Workshop descriptors and all eight aircraft preflights.

| Check | Result |
| --- | --- |
| Actuator, drag, physical/visual contracts, rollback and checkpoint continuation | 68 checks passed |
| Actual-session runway, crosswind, taxi, steering, braking and landing | 26 checks passed |
| Gear trace v10 roundtrip, replay, turbulence placement and malformed data rejection | 19 checks passed |
| Keyboard G/B, paused release and radio AUX priority | 8 checks passed |
| Imported model, rig articulation, doors, wheel centres, steering/spin/compression and instance isolation | 389 checks passed |
| Existing generic trace and UI runway routes | 37 trace checks and all runway UI checks passed |
| Aircraft contract, handling, turbine and continuous turbine/wheel state | 2,887 / 47 / 27 / 46 checks passed |
| Checkpoints, replay integrity, replay policy and simulation kernel | 92 / 153 / 50 / 11 checks passed |
| Ground contact, friction, stiction, surfaces and runway-start integrity | 22 / 26 / 25 / 28 / 254 checks passed |

The new runtime tests are `app/tests/test_retractable_gear{,_ground,_trace,_input}.gd`; `app/test.sh` discovers them automatically. The [asset guide](../../../../assets/aircraft/avanti-s-a200/README.md#regenerate-and-verify) gives the generator and direct test commands. Existing glow-flight, runway-start and runway-checkpoint tests also passed. The broader Python CLI acceptance setup timed out during process startup and is not reported as a passing suite; focused real Avanti traces below passed independently.

### Measured software scenarios

The [ground-session log](logs/gear-ground.log) records positive static compression on all three wheels (20.9, 20.9 and 21.8 mm), 0.7 mm drift over two seconds at engine-off rest, and stationary rest in a 1.5 m/s crosswind. Powered taxi reaches 1.096 m/s after 2.5 s and yaws right by 0.115 rad with right steering. From 3 m/s, optional 1 N·m main brakes reduce stopping distance from 6.003 to 4.926 m and time from 3.95 to 3.38 s, using a 0.05 m/s stop threshold.

The 1.5 m/s sink scenario touches down at 1.508 m/s, reaches 64 mm peak equivalent compression and settles without a gear-limit event. The 4 m/s descent scenario triggers the nose terminal limit at 0.037 s. Repeating the nominal landing at 240/480 Hz changes final position by 0.02 mm and final speed by less than the printed 0.00001 m/s precision. These results qualify the chosen numerical model; they are not measured real-aircraft performance.

Actual one-second Avanti CLI traces with `--weather=turbulent` and `--weather=hot-high` pass the independent Python readers. They contain 241 rows each, metadata v8 and trace v10. Maximum turbulent wind/OU error is below 5e-10 m/s; the hot/high density is 0.9439353 kg/m³. Results are retained as [turbulent](logs/turbulent-check.json) and [hot/high](logs/hot-high-check.json) reports.

### Source and Windows package

The four [source captures](captures/captures.json) and [packaged captures](package-captures/captures.json) show stowed, 50% extension, downlocked and nose-steered states. They use the real `FlightSession`, accepted six-channel commands, 240 Hz stepping and the runtime ground-gear renderer. The capture harness is `research/avanti-s/av09/capture_gear.gd`; view [downlocked](package-captures/03-downlocked.png) and [in transit](package-captures/02-transit.png). Both native runs completed without engine errors using the Compatibility renderer on an RTX 3090.

The Windows release export includes its native vehicle DLL. The actual standalone executable completed a three-second Avanti flight, and `check_trimmed_flight.py` verified all 720 ticks, finite samples, stable 30 m altitude / 29 m/s speed and exact current aircraft input bytes ([result](logs/package-flight-check.txt)). The packaged render harness loads the exported PCK using the matching Godot executable with that DLL alongside it. This is recorded separately from the standalone executable flight, rather than treating an editor render as executable proof.

Model revision is `av09-retractable-gear-1`. The supplied master remains byte-identical. Exported GLB SHA-256 is `803d293d597d88d94cebe1c191e6453e5d108aca4d6e5d5eaabfa0a387cf0f36`; its 38 meshes contain 146,652 triangles. The [source manifest](../../../../assets/aircraft/avanti-s-a200/source-manifest.json) retains the master identity, interpolation measurements and export settings.
