# Vantage Jet: current scope and remaining work

Checked 2026-11-10 · Aircraft/model owner · Prefix **AV-00…31** and repair steps AV-17-R1/R2/R3/R4. Code, accepted configuration and generated data define implemented behavior. Implementation, passing software checks and physical validation are separate claims.

## 1. Identity and scope

**Vantage Jet**, catalog ID `sebart-avanti-s-a200-p100rx`, references the original SebArt A200 (2.00 m span, 2.22 m length) with the **2017 non-BL JetCat P100-RX**. BL, EDF, XS and other Avanti variants do not identify this installation. Borrowed cross-airframe estimates must retain their stated provenance.

The aircraft is **EXPERIMENTAL**, with airborne and downlocked runway starts. The current [generated aircraft](../app/data/aircraft/sebart_avanti_s_a200.json) selects continuous turbine RPM, finite liquid fuel, retractable tricycle gear and simulated flaps. Its implementation does not establish a measured aircraft envelope.

| Current software | Implementation / boundary |
| --- | --- |
| Turbine response | [Turbine law](../app/physics/turbine.gd): mapped demand, asymmetric spool schedules, stage RPM/thrust/gyro and local intake velocity. Installation, intermediate maps, rotor inertia/sense and response remain estimates. |
| Finite main tank | [Liquid-fuel adapter](../app/sim/liquid_fuel_flight.gd): RPM-map consumption, stage mass/CG/inertia, located exhaustion, source latch, residue, reset and checkpoint state. Source-off uses an estimated existing-schedule rundown; this is not a complete ECU/thermal sequence. |
| Retracts and ground | AV-09: accepted extension, wheel contact/spin, nose steering, assumed main brakes and runway launch. Actuation/contact mechanics remain estimated; broader landing qualification is pending. |
| Flaps | AV-09-F: accepted actuator travel, local aerodynamic loads/wake, rendering and manual elevator mix. Detents are 0°/20°/50°; mix is 8%/20% of full elevator travel following actual flap angle. Force coefficients, timing and speed advisory are not measured A200 limits. |
| Inputs and polar | AV-17-R1/R2/R3: keyboard pitch progression, normal-gamepad pitch/yaw settings and progressive wing polar. These are implemented input/model choices, not physical identification. |
| Presentation | AV-31: shared version-2 GLB builder, authored sections and gear/control bindings; turbine audio reads telemetry. SM-11-R1 adds optional [tailpipe show smoke](SMOKE.md#avanti--ventage-jet-show-smoke-sm-11-r1) using the authored outlet and existing H/AUX controls. Visual planform/installation does not replace the physical surrogate. |

Full ECU startup, EGT/core thermal history, pump/supply-battery dynamics, cooling/relight, hopper transfer and slosh remain future work. Basic fuel exhaustion/rundown must not be described as those systems.

## 2. Documentation and ownership

| Topic | Authoritative home |
| --- | --- |
| Source identity, Blender build, model bindings and check commands | [Asset guide](../assets/aircraft/avanti-s-a200/README.md) |
| Aircraft assumptions, estimates and generated output | [AV-06 inputs](../research/avanti-s/av06/inputs.json), [derivation](../research/avanti-s/av06/derivation.md); never hand-edit aircraft JSON |
| Turbine mechanisms, AV-05b/AV-10 and AV-18…30 status | [Turbine plan](plans/turbine-realism.md#13-incremental-implementation-sequence) |
| Shared fuel law, datum, fill/reset and remaining FUEL work | [Fuel standard](FUEL-SYSTEM.md), [remaining FUEL gates](plans/fuel-mass-balance.md) |
| Physical/model authoring and extensions | [Aircraft contract](AIRCRAFT_CONTRACT.md), [Blender handoff](BLENDER-AIRCRAFT-HANDOFF.md) |
| Player controls and replay comparisons | [First launch](FIRST-LAUNCH.md), [flight logging](FLIGHT-LOGGING.md) |
| Dated source/verification records | [Vantage Jet research index](research/README.md#ventage-jet), [AV-14…17 investigation](research/avanti-realism/README.md) |

AV owns the aircraft sources, generated data pipeline, model tools/tests and research. Physics, AS, input/UI, fuel, audio, HUD, crash and export retain their [registered shared boundaries](README.md#tracks-plans-and-step-ids). Preserve unrelated work and exact source identities.

## 3. Steps

Delivered foundations are recorded in the linked evidence, not an instruction to repeat old migrations. AV-00/03/05a/06 enabled the reference and turbine aircraft; AV-14…17 corrected geometry/inventory and added full-session probes. AV-31 replaced the visual blockout. Remaining scope is explicit below.

| ID | State | Remaining work / evidence |
| --- | --- | --- |
| AV-01 | Provisional metrology | Calibrate A200 planform, tail, root-LE/chord, component and engine locations; retain discrepancies. |
| AV-02 | Physical surrogate retained | The old visual blockout is superseded; its estimated physical geometry remains in AV-06. Mesh agreement alone cannot calibrate it. |
| AV-04 | Rig implemented | [AV-31](research/avanti-blender/AV-31/README.md) records rest/sign/pose checks. Installed servo response, loaded clearance and physical travel remain unmeasured. |
| AV-07/16 | Flight/probe infrastructure implemented; current verification pending | Dated trim/envelope/lifecycle evidence exists. Recheck the real current session, refinement and replay; resolve native handling/recording failures before claiming a green current suite. Pilot evaluation remains open. |
| AV-08 | Finish/audio integrated | Acoustic identification for the installed P100 and independent visual/pilot reading remain open. |
| AV-09 / AV-09-F | Gear and flaps implemented | [Gear](research/avanti-gear/AV-09/README.md) and [flap](research/avanti-flaps/AV-09/README.md) evidence covers software integration. The 2026-10-19 recheck recorded gear trace/ground failures; the November brake characterization does not requalify that whole suite. Physical contact/flap identification and matched approach/landing/braking acceptance remain pending. |
| AV-11 | Physical validation pending | Matched-build metrology, bench/flight observations and uncertainty-qualified comparisons. No simulator-only trace closes this gate. |
| AV-12 / AV-17 integration gate | Partial delivery evidence | AV-31 has isolated Windows package/capture proof. Current full-suite, target-machine performance and cross-platform release qualification remain open; coordinate AV-30. |
| AV-13 | Future extensions | Scope additional ground/propulsion behavior explicitly; existing retracts, brakes, runway starts and flaps are already implemented. |
| AV-17-R1/R2/R3 | Implemented repairs | [Keyboard](research/avanti-realism/AV-17-R1/README.md), [polar/gamepad](research/avanti-realism/AV-17-R2/README.md), [yaw](research/avanti-realism/AV-17-R3/README.md) retain dated proof. Pilot acceptance and aircraft-specific identification remain open. |
| AV-17-R4 | Pitch datum corrected | [Reference-point correction and accepted-command evidence](research/avanti-realism/AV-17-R4/README.md). The generator converts CG-referenced Cmq to the stored ARP convention; runtime fuel transfer remains unchanged. Local/global consistency and physical identification are separate gates. |
| AV-31 | Imported model integrated | Build/binding/section checks and local package evidence exist; physical installation calibration and target cost remain separate. |

AV-05b, AV-10a/b/c and AV-18…30 have one detailed register in the turbine plan. Finite-fuel runtime is already present; ECU/thermal/pump work remains planned. Do not reset completed implementation to “future” merely because physical acceptance is open.

## 4. Limits and acceptance

The physical wing/tail/installation still use an estimated surrogate. The neutral-point anchor, inventory distribution, empty-main-tank balance convention, fuel arm and thrust line are assumptions recorded by the generator and fuel guide. Historical fixed half-tank masses/CGs are dated snapshots, not current live-mass specifications. The Blender source contributes visual/contact measurements, not calibrated aerodynamic geometry or a new force point.

The [AV-14…17 record](research/avanti-realism/README.md) retains original audits, independent arithmetic, refinement bands, loop diagnostics and baseline suite failures. It predates continuous turbine integration, gear/flaps and finite fuel. A body-pitch integral is not proof of a planar loop; model speed/polar predictions are not an identified flight or structural envelope.

Aircraft acceptance requires a fixed hardware/engine/ECU/fuel configuration, measured mass/CG/inertia, identified forces/response and held-out flight observations. Keep source/run identities, input tapes, complete traces and uncertainty verdicts. Software regression, target cost, rendered readability and owner radio/pilot acceptance each need their own evidence.

## 5. November review implementation sequence

The [retained external review](research/avanti-realism/review-2026-11-10.md) describes snapshot
`313bb24e`; its R0–R12 labels are cross-references, not new repository track IDs.
Implementation started from `3699b237`. Current code and the evidence below supersede
the review's implementation assumptions. Keep each behavioral correction independently attributable.

| Review package | Owner / current disposition |
| --- | --- |
| R0 baseline | AV-07/16: reference accepted-command pulse and loop-entry tapes, exact replay and pinned data/solver retained under AV-17-R4. Normal UI/device path and target-machine baseline remain open. |
| R1 pitch reference | AV-17-R4: generator correction and software checks implemented, including native parity and same-tape comparison. Full handling/energy and lateral-effect interpretation remains open; see its evidence. |
| R2 brake diagnosis | AV-09 + GP: [active-wheel characterization](research/avanti-gear/AV-09/brake-audit-2026-11-10/README.md). This does not calibrate stopping distance or promote the GP-12 candidate law. |
| R3 ground correction | GP + AV-09: pending the R2 branch/rollout evidence and an identified torque/traction target; preserve rest, release, steering, touchdown, refinement and native gates. |
| R4 control ownership | Input + AV/session: pending explicit simulator/transmitter flap-mix ownership, profile migration and surface-chain diagnostics. Preserve existing profile behavior. |
| R5 lateral consistency | AV + physics/native: next aerodynamic investigation; map residual body terms and global/local derivatives before selecting one correction. |
| R6 spatial ailerons | Shared aero + AV geometry: after R5, identify coverage and preserve initial aggregate authority; validate strip loading and flap interaction. |
| R7 physical sheet | AV-01/11: existing AV-06 inputs/derivation remain the estimate ledger; matched A200 mass, geometry, fuel arms, inertia and installation measurements are still needed. |
| R8 propulsion/energy | AV-18…30 + AV-11: await matched installation measurements and held-out level/glide/acceleration/dive comparisons. |
| R9 flap/stall | AV-09-F + AV-11: follows controls, spatial model and metrology; retain independent first-load-loss and approach/recovery evidence. |
| R10 engineering debrief | FL + UI-FS: pending defined maneuver/energy metrics with sample timing and configuration labels; reuse the existing recorder/debrief. |
| R11 optimization | Performance/native/UI owners: profile the full 1080p path before changing algorithms; current headless tests make no performance claim. |
| R12 acceptance | AV-11/12 + release/pilots: independent physical identification, pilot comparison and target-machine package gates remain open. |
