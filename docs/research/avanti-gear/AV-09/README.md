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

Qualification results and reproducible commands are recorded here after the generated rig and real-session checks complete.
