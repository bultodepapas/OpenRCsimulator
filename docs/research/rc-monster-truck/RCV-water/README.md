# RC lake, water and mud — RCV-10/13/25

**2026-10-14.** The Bisonte now interacts with the existing aircraft-field lake through its float64 vehicle solver. The aircraft runway remains the default start. The garage adds a dry north-shore staging point, and the HUD distinguishes wading from submersion. Controls and recovery instructions belong to the [operating guide](../../../../research/rc-monster-truck/README.md#drive-and-experiment).

## Model and integration

`vehicle_environment.gd` evaluates four body cells and four moving wheel cells at every RK4 stage. Spherical-cap occupancy is clipped between the mean water surface and the actual bed, excluding displaced soil and making the shallow-water limit continuous. Buoyancy acts upward; quadratic drag opposes each cell's world velocity, including body rotation and suspension motion. Immersed wheel spin also produces dissipative axle torque. These loads enter the 14 generalized force channels **before** the coupled mass/friction solve in both backends. The lake bed still provides real tire support; there is no depth switch that artificially disables traction.

| Quantity | Configured value and provenance |
| --- | --- |
| Water density | 998 kg/m³, fixed fresh-water estimate |
| Body displacement | Four 0.35 L cells, radius 65 mm; effective open-body estimate |
| Wheel displacement | 0.30 L per tire, effective vented-wheel estimate |
| Total fully immersed displacement | 2.6 L, producing 25.4463 N buoyancy at default gravity |
| Vehicle mass / weight | Existing estimated 5.52 kg / 54.1327 N; this configuration sinks |
| Body drag | 0.009 m² reference area per cell, Cd 1.05 |
| Wheel drag | πr² reference area per wheel, Cd 1.10; existing tire radius 0.10 m |
| Axial wheel drag | −0.00015 × immersion × abs(ω) × ω N m, using absolute axle speed |
| Mud contact | Smooth shore-distance blend over 0.9 m outside the water edge; μ approaches 0.30 and rolling multiplier 4.5 |
| Wet step cap | 1/480 s; public Session clock remains 240 Hz |

Displacement, drag areas/coefficients and soil response are estimates, not measured truck properties. The 2 m wet-query margin is a broadphase bound only: it cannot wet the truck or generate fluid force. Ordinary dry terrain retains its previous integration step. The force surface is the shared **mean** lake datum; decorative waves do not feed the solver. Gravity changes also change buoyancy through the same g.

`AirfieldCourse` reuses the shared bed and adds water/material metadata. An optional native helper computes the identical bathymetry and signed shore distance; it falls back to shared GDScript for absent/incompatible native support. No spatial quantization, terrain cache or aircraft-contact equation changes were introduced. [Windows/Linux native parity and build identities](native/README.md).

The damage estimator subtracts environmental energy loss from its inferred contact loss, preventing water resistance from becoming fictitious crash damage. A supported landing with the body substantially submerged cannot earn a landing award. Recovery remains explicit, paused and marked as assisted.

## Presentation and persistence

The existing lake renderer, supplied truck meshes and bundled licensed splash sounds are reused. Separate fixed pools contain 32 water droplets, 32 mud clods and eight ripple meshes. Wheels emit only when motion and actual immersion/contact justify it; full submersion suppresses surface spray and ballistic clods. Wet sheen, accumulating mud and gradual washing use private material instances. These effects read accepted telemetry and never affect physics. They are bounded cosmetic approximations, not persistent fluid particles or deforming soil.

Solver v4 / native evaluator v3 retain ABI 1. Checkpoint format v3 now binds the environment implementation version and source artifact. Recording v4 includes body/wheel immersion, depth, mud, buoyancy and fluid power. Older solver identities are rejected rather than silently replayed through different dynamics.

The actual water entry exposed a pre-existing JSON checkpoint defect: repeated decimal serialization could alter a redundant displayed control number while its authoritative float64 bytes remained intact. Display mirrors now use a bounded 1e−12 relative/absolute comparison with strict shape/type/finite checks. Raw float64 blobs and their SHA-256 checks remain authoritative; the full checkpoint checksum is still required. The event checksum is computed after the final checkpoint normalization. Regression cases cover repeated JSON roundtrips and tampering.

## Verification

The [source investigation](research.md) retains primary references and baseline findings. The [numeric evidence](physics-test-2026-10-14.md) covers shallow/deep sampling, displaced-volume limits, dissipative work, generalized power, gravity/drop behavior, genuine step refinement and damage compensation. The active-dispatch regression compares all 31 derivatives across native/reference paths at 1, 8 and 20 m/s; each matches exactly. Direct uncapped RK4 comparisons support retaining the wet step cap.

The final [runtime suite](checks-final/verification.json) passed **all 28 RC checks**, including 121 Session assertions, 79 wet-effect assertions and 27 Home-to-car menu assertions. The optional broad Home layout check also passed. The overall 30-check receipt remains **failed** because `test_ui_home` expects the helicopter tooltip substring `Turbulence is not integrated yet`, whereas the unchanged Home source says `Turbulence and altitude-varying atmosphere are not integrated yet`. Both files were unchanged by this work; this unrelated assertion is retained in [its log](checks-final/test_ui_home.log), not waived or reported as green. All fingerprinted runtime sources remained stable during the suite.

The [accepted entry](entry-final/verification.json) completed 3,600 ticks / 15 simulated seconds, reached 0.772486 m bed depth and full cell immersion, with 25.4463 N maximum buoyancy and −161.077 W minimum fluid drag power. No body/suspension damage accumulated. A checkpoint written during immersion restored from JSON on disk and replayed the following 48 ticks with byte-exact final physical/damage state; explicit recovery returned to the dry staging point. Packed recording retained water channels. This checks the ordinary control/Session path without state injection.

The [dry circuit comparison](dry-comparison.json) completed 5,393 ticks at up to 5.973850 m/s. Every exported state and driver-input value matched the preceding strict-audit baseline exactly, with no damage. The [native scene comparison](render-comparison.json) likewise matches all exported water-drive values, control bytes and final 31-state values with and without rendering; particles cannot alter the trajectory.

### Optimization and remaining performance gate

The first complete entry exposed the checkpoint problem and expensive repeated GDScript bathymetry. Its [baseline receipt](entry-native/verification.json) is deliberately retained as a **failed** checkpoint result; it is useful only as the complete, source-stable physical/cost baseline. After the exact native terrain helper and checkpoint repair, the [comparison](entry-comparison.json) has zero differing trajectory/force cells, identical control bytes and identical final state.

| Debug Godot, complete Session tick | Before terrain helper | Accepted optimized entry |
| --- | --- | --- |
| Median | 41.580 ms | 13.706 ms |
| P95 | 72.818 ms | 17.733 ms |

These are wall-clock observations on a shared development machine, not controlled target-hardware qualification. P95 improved by about 76%, but **still exceeds the 4.167 ms public-tick budget** and the separate 500 µs target. The native dry circuit P95 was 4.978 ms in this run. Do not claim sustained real-time wet driving from these measurements. Costs exclude CSV writing and frame rendering; they include complete Session tick work. Physics time is retained rather than discarded when the interactive activity falls behind.

### Native visual inspection

The production OpenGL scene was driven with the same controls and a fixed inspection camera. The [initial capture receipt](capture-final/verification.json) passed all phases and exact replay; its first deep image marks full fluid-cell occupancy near 0.4 m bed depth. The fluid cells approximate the low chassis, so the tall shell can still lie near the visible surface at that point. The [final capture](capture-deep-final/verification.json) uses more than 0.65 m bed depth to show roof cover and explicitly passes the checks for activated bounded pools and fully immersed wheels stopping spray/clods. Its [trajectory comparison](deep-render-comparison.json) is also exact. The camera remains above the surface; these captures do not qualify an underwater camera.

Inspected native frames: [mud entry](capture-deep-final/water-entry-mud.png), [shallow water](capture-deep-final/water-entry-shallow.png), [deeper immersion](capture-deep-final/water-entry-deep.png). Observed peaks were 22 water droplets and 26 mud clods, below their 32-instance budgets; the simulation remained intact. Unlinked preliminary diagnostic runs are not accepted evidence.

The harness supplies controls directly to Session; its stale neutral-control hint does not represent the actual garage input-owner flow, which is covered by the menu suite. Splash audio is disabled during capture; the wet-effect suite checks pause, cooldown and reset behavior separately. No audio listening or physical-controller acceptance is claimed here.

Run the repeatable entry from the repository root into a **new** directory:

```powershell
python -B research/rc-monster-truck/water/run_water.py --godot .tools/Godot_v4.7.2-stable_win64.exe --out .tools/rcv-water-entry
```

Add `--capture` for the native OpenGL production-scene captures. The script stages at the supported shore spawn, drives 3,600 ordinary accepted ticks without state injection, records mud/shallow/deep phases, saves/restores while immersed and checks exact state/damage replay. Receipts include engine, source and native identities, control-tape and artifact hashes, errors and completion; require all gates, not just a written CSV. The runtime verifier also includes the two numerical water scripts and wet-effect tests.

## Limits

This is a still-water, rigid-bed model. It does not implement currents, added fluid mass, planing, CFD, sealed-hull flotation, electrical failure, corrosion, deformable mud, ruts or soil sinkage. Wheel/body cells approximate geometry and do not describe watertight cavities. The motor remains the estimated electric drive underwater; immersion alone does not invent hardware damage. Numerical and visual checks establish software behavior, not calibration against a real RC truck. Target-machine performance qualification remains separate.
