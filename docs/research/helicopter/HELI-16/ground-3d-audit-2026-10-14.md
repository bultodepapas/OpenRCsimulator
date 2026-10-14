# HELI-16: ground-start and aerobatic 3D audit

**Date:** 2026-10-14. **Scope:** current Windows working tree, Godot 4.7.2-stable, production helicopter route and its authored data, equations, numerical integration, controls, ground/field integration, replay and presentation. This is an audit and implementation plan, not a flight-model repair or physical certification. The [active plan §14](../../../plans/helicopter.md#14-ground-start-and-aerobatic-3d-execution-plan) owns priorities and acceptance; [HELICOPTER](../../../HELICOPTER.md) still describes the unchanged playable trainer.

## Assessment

The current helicopter is a useful, software-tested research trainer with a real float64 six-degree-of-freedom body and jointly integrated shaft, flap, wake and controller states. Retain it. It is not an identified HX-700: its visual is flybarless, its reference physics is the instrumented 8.2 kg X-Cell with an effective flybar, and its powertrain/controller/skids include declared estimates. Neither the ability to evaluate negative thrust nor passing a stationary-hover test qualifies a complete aerobatic envelope.

The requested ground start needs a lifecycle and contact solve, not a lower initial altitude. The requested 3D entry needs independently selected data and FBL/actuator laws, not just disabling the trainer. New controlled probes expose startup, rotor-stop and orientation-control gaps despite the existing test suites passing. These are missing scenario coverage, not evidence that the existing assertions failed.

The earlier [HELI-16-R1 audit](README.md#2026-10-14-deep-audit-heli-0916-r1) already repaired contact culling, disc normalization, configuration/checkpoint atomicity and repeated evaluation costs. This report preserves that work and does not report those repaired issues as still open.

## Current implementation map

| Concern | Current implementation and evidence boundary |
| --- | --- |
| Routing/data | `app_root.gd` selects a rotorcraft scene, but `helicopter_main.gd:83–86` calls default `session.setup()`; `rotorcraft_data.gd:43–48` accepts only the X-Cell ID and exact capabilities. A second catalog row cannot select different physics today. |
| State/numerics | `flight_dynamics.gd:18–24`: 13 body values plus Ω, a1, b1, vi, heading reference and yaw integral. `simulation.gd:243` uses generic joint RK4 unless a continuous-step callback is installed. Session installs the evaluator, not that callback. |
| Main/tail/aero | Source-based mean-rotor, tail/airframe and inflow laws; finite/domain checks, immutable contexts, independent component references and signed coupling. Source range is μ<0.15; small-flap flags use **10°**, while the algebra permits μ²<2. |
| Drive | `drive.gd`: torque/power-capped one-speed proxy with P-only governor; no independent motor/engine/freewheel state or soft-start lifecycle. Hold explicitly removes delivered drive torque. |
| Controls | `electronics.gd:127–188`: trainer attitude/rate control, instantaneous limited 120° mix, Euler-heading tail feedback; direct cyclic still retains this yaw loop. `swash.gd` has standalone lag/rate helpers, but actual session servo states are absent. |
| Ground | `skid_contact.gd:6–40`: four spring/damper contacts and velocity-regularized Coulomb friction. No static tangential anchors. `strike` uses instantaneous full-disc ground bounds, not swept scenery or stopped-blade geometry. |
| Lifecycle | `helicopter_flight_session.gd:172–213` always solves airborne hover and restores trainer/normal/powered defaults. Home and AppRoot force airborne. Keyboard/menu reset follows the same route. |
| Replay | Native checkpoint v2 binds model bytes, field/start, weather and complete current flight state. Future actuator, freewheel, mode-transition and contact memory must extend that contract. CSV is diagnostic, not exact native replay. |
| Visual | `heli_rotor_visual.gd:52–82` animates main/tail phase and disc tilt; collective is metadata. HELI-25c's 108 bindings/nine rods are neutral inspection admission, not achieved swash/feather/servo animation. |
| Performance | Prepared aerodynamic/electronics contexts and tick-cached presentation already remove substantial repeated work. Whole-tick and target-host frame acceptance remain open; see current diagnostic below. |

Paths above are relative to `app/`; line numbers describe this dated review and may drift. Runtime/data remain authoritative over older plan descriptions.

## Findings and controlled experiments

Severity is relative to the requested capability: **P0** blocks making ground/3D the default; **P1** blocks credible qualification; **P2** is subsequent presentation/maintenance work. These are not security ratings.

| ID / priority | Verified observation | Consequence and planned correction |
| --- | --- | --- |
| A1 / P0 ground | `reset()` always calls `Hover.solve_hover`; current field start is N=12,E=4,D=−3. Home disables the start selector and AppRoot overwrites it. | Resolve an authored pad, static skid state and lifecycle across every route (HELI-19a/20a…e). Changing `_start[2]` alone is insufficient. |
| A2 / P0 ground | At Ω=0 in 3 m/s horizontal wind, initial evaluation succeeds; the next RK stage rejects `main_rotor_advance_ratio_out_of_domain`. Both standalone and common-simulation probes reproduce this. | Qualified low-RPM aerodynamic regime/transition before pad spool-up (HELI-04-R2/07a). Keep wind and domain guards. |
| A3 / P0 ground | From Ω=0.001 rad/s under hold, common `Simulation` faults at tick zero when a stage crosses zero. The standalone helper snaps a successful partial-step boundary to a stopped event and returns an unconsumed remainder; the session does not install it. | Qualify event accuracy, then a full-tick adapter consuming the remainder with rollback/replay (HELI-17b). Wiring the helper alone does not resolve A2. |
| A4 / P0 arming | At zero shaft speed and drive fraction=0 with governor enabled, actual preset drive produces **1.2 N·m engine torque / 8.884 N·m net main torque**. Hold gives zero. | This is consistent with the current proxy, but fraction=0 cannot serve as a ground motor-disarm command. Add explicit enable/hold/ramp semantics (HELI-07b/20b). |
| A5 / P0 3D | At zero body/yaw rates and no yaw stick, rotating pitch from 89.9° to 90.1° changes heading error 0→−π, yaw-rate target 0→−1.5 rad/s and tail pitch 0.100→0.025 rad, **trainer disabled**. | Euler heading control introduces a false 3D yaw correction. Qualify a body-rate/FBL orientation formulation before flips/inversion (HELI-15b). |
| A6 / P1 usability | At solved hover stick −0.01934854, normal→idle-up changes collective **0.0960203→−0.00425668 rad** (+5.502°→−0.244°) and drive 0.85→1.0. | Curves can intentionally do this; it is not a numerical bug. Declare real-radio semantics and add a trainer transition policy, HUD and coverage (HELI-15c/20d). |
| A7 / P0 second entry | Scene builder/data path are hardcoded and the strict loader only accepts X-Cell. | Catalog ID must resolve both data and visual; extend capabilities before adding the 3D entry (HELI-36a/b). |
| A8 / P1 ground | Regularized friction is zero at zero slip, so it cannot balance a nonzero static tangential load; no ground equilibrium initializer exists for the helicopter. | Add supported static contact memory/solve, slope limits, breakaway and rollover evidence (HELI-19a). Flat landing success does not establish stable slope parking. |
| A9 / P1 realism | No achieved servo dynamics, source-specific FBL model, motor/freewheel or automatically localized C/M inflow events. Literal source range and estimation remain declared. | Separate hardware/data and numerical work; test signed/inverted transients and held-out responses (HELI-13a/15b/17a/24/36c). |
| A10 / P1 collision | Ground-disc check is instantaneous, includes the full disc at zero RPM and uses global maximum relief; scenery/fleet keepouts are not helicopter contacts. | Separate spawn exclusion, parked blades and rotating swept collision; use bounded local terrain/scenery (HELI-21a/33a). |
| A11 / P1 cost | Existing and current diagnostic whole-tick costs exceed the proposed 500 μs budget. | Profile complete regimes, preserve stage purity/parity, then optimize measured bottlenecks (HELI-09e/23a). No lower physics rate to conceal the cost. |
| A12 / P2 visual | Only rotor spin/tilt currently moves; the articulated asset still needs signed moving-frame/limit/servo integration, material baking and flight LOD. | Follow existing HELI-25c/26a admission, reuse the source, and consume achieved physical state. |

### Probe scope and reproducibility

[`review_probes.gd`](../../../../research/helicopter/audit/review_probes.gd) loads the actual generated aircraft, solves hover, and samples its real electronics and drive. The vertical crossing isolates the control coordinate issue: it deliberately sets zero rates/reference and probes two adjacent physical attitudes; it is not a simulated flip trajectory. The mode probe holds the hover stick and trim fixed. The drive probe isolates zero command/enable semantics. [Raw output](ground-3d-review-probes.json).

[`rotor_event_probe.gd`](../../../../research/helicopter/audit/rotor_event_probe.gd) compares `Flight.rk4_step_at` with a common `Simulation` using the same joint flight evaluator and no event callback. It uses a body 5 m above flat ground to isolate rotor equations from contact. It is not a full Home-to-ground-launch test. Source inspection establishes that the production session uses this generic step path. [Raw cases](ground-3d-rotor-events.json).

The stop helper returned **83.639 μs** as its last accepted partial-step boundary, then **snapped Ω to zero**, leaving **4.08303 ms** of the 4.16667 ms tick. It bisects successful RK attempts, not a proven root of Ω(t)=0. The initial derivative is −1.352065 rad/s², giving a constant-initial-slope stopping scale of about **0.740 ms**; that is not an exact reference either, but the disparity reinforces the need to investigate low-speed nonlinear/stiff behavior and event semantics. The current common-step route rejects the step. No physical stop time or event-root accuracy is established by this probe; those need an independent refined trajectory and energy error bound before integration.

Useful independent scale checks from the accepted inputs: `mg=80.41453 N`; rotor area `πR²=1.886919 m²`; ideal momentum hover `sqrt(mg/(2ρA))=4.170687 m/s`; equal four-point static compression `mg/(4k)=2.010363 mm`. Ideal momentum inflow is a sanity estimate, not measured hover power or a complete trim oracle.

Run the two probes from the repository root:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script ../research/helicopter/audit/review_probes.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script ../research/helicopter/audit/rotor_event_probe.gd
```

These diagnostic scripts intentionally report the current limitations; they do not repair them or pretend the expected fault cases are supported flights. Future implementation should turn each desired behavior into a passing regression with negative controls. The first scratch event harness omitted freeing its temporary Simulation nodes and reported shutdown leaks; the retained harness explicitly frees them. Engine diagnostics are checked separately from modeled expected fault fields.

## Field placement consequences

Read from [default field](../../../../app/data/fields/default.json), [scenery](../../../../app/data/scenery/default.json) and [ground start](../../../../app/physics/ground_start.gd): runway N=[9,21], E=[−50,50]; pilot (0,0); fixed-wing runway start (15,−47), eastbound; flightline barrier at N=4.5 with a central 6 m opening. The current helicopter point (12,4) lies inside the runway. The older plan's 10–15 m north pad suggestion also overlaps it.

The proposed **N=6,E=0**, eastbound candidate is beside the runway midpoint, 3 m from its south edge and beyond the central barrier opening. These center-point offsets do not prove rotor/body clearance. Its nearest decorative parked plane center is approximately 33.7 m away, and the fixed-wing threshold start is approximately 47.8 m away. Thus “midpoint beside runway” and “adjacent to parked airplanes” cannot honestly describe the same candidate. The plan prioritizes the former without relocating other aircraft.

The field has no separate mown physical surface rectangle at that point; off-runway contact resolves to rough. Any pad must coordinate field surface priority, rendered grass exclusion, terrain normals, support solve, scenery keepouts, pilot camera and collision. No invisible platform or visual-only patch should redefine physical height. Final placement awaits full envelope validation and pilot-view captures; this audit did not simulate a ground launch there.

## Verification and performance evidence

The fresh verification report and diagnostic samples linked here are finalized with this audit. Existing hover endurance, full-route cadence and native capture records remain in [HELI-16](README.md); they are not relabeled as newly executed tests.

**Fresh focused run:** 23 native `test_heli_*.gd` suites, **7,579 checks, zero failures**, with no script/shader/engine error diagnostics. Preset/schema freshness, four Python authoring tests, 67 independent Python reference tests, five oracle freshness checks and the float64 transcendental-boundary guard also pass. [Commands/scripts, summaries and complete captured logs](ground-3d-verification.json); [review source fingerprints](ground-3d-source-fingerprints.json). The new two diagnostic probes also run cleanly; their expected fault fields are reported above rather than counted as successful flights.

**Current per-tick diagnostic:** Windows, Ryzen 9 5900X, official Godot 4.7.2; 256 warmup ticks then 8,000 measured ticks per regime, nearest-rank percentiles. Timed scope is `Simulation.step()` plus session stage/contact callbacks. Rendering, frame scheduling, device polling and the test pilot's command calculation are excluded. Review agents avoided concurrent Godot runs during timing; the host was not isolated from unrelated applications.

| Regime | p50 | p95 | p99 | Maximum | Ticks above 500 μs |
| --- | ---: | ---: | ---: | ---: | ---: |
| Solved free hover | 798 μs | 1,044 μs | 1,348 μs | 5,062 μs | 8,000 / 8,000 |
| Powered light skid contact | 1,272 μs | 2,025 μs | 2,390 μs | 4,654 μs | 8,000 / 8,000 |

Each regime had one tick exceeding the full 4,166.67 μs simulation interval. This is a cost diagnostic, not proof of a rendered frame drop or a hardware gate result. Compared with the proposed median budget, hover is 1.596× and the powered contact case 2.544×; neither meets 500 μs here. At 60 Hz, four median-cost ticks correspond to about 3.19/5.09 ms of CPU work before scene/render costs; this multiplication is an estimate, not a measured frame distribution.

The contact case uses the existing scripted landing pilot for 7,200 ticks, then continues its compensation while timing. The rotor remains near **1,617 rpm**; skid vertical support rises from about **2.42 to 4.97 N**, versus aircraft weight 80.41 N. It exercises near-ground/contact code with most weight still supported aerodynamically. It does **not** establish rotor-off static support, ground-start behavior or their future computational cost. [All 16,000 raw samples, endpoint state hashes, contact loads and source hashes](ground-3d-performance.json); [retained measurement script](../../../../research/helicopter/audit/measure_session_regimes.gd).

An initial summary-only diagnostic was repeated to retain per-tick samples; the table uses only that complete rerun. Its timing differed without any flight-code change, illustrating host variability. Do not interpret the earlier/current timing difference as an optimization.

The existing paired control benchmark was also repeated for seven alternating 480-tick batches. Median batch means were 1,370.356 μs for revalidating electronics versus 1,163.556 μs for prepared electronics, a 15.1% reduction in that comparison; all seven paired 19-value endpoint state hashes agree. [Raw paired batches and source provenance](ground-3d-paired-controls.json). This compares the existing prepared path to a disposable revalidating copy, not a new change made by this audit. It does not establish full checkpoint/trajectory parity for every case, and batch means are not per-tick percentiles.

Reproduce the per-regime diagnostic and selected checks from the repository root:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script ../research/helicopter/audit/measure_session_regimes.gd -- --out=user://heli-review-performance.json
python research/helicopter/xcell/derive.py --check
python research/helicopter/xcell/test_derive.py
python -m unittest discover -s research/helicopter/reference -p 'test_*.py'
# Repeat the native invocation for each test_heli_*.gd script listed in the JSON:
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_heli_session.gd
```

## Numerical and physical evidence limits

Conservation checks in `test_heli_coupling.gd` are useful independent angular momentum/energy-rate tests. Dimensional known answers, separate Python equations, invalid-data checks and replay tests give stronger coverage than reference-vs-prepared parity alone. Prepared-path parity still matters for optimization, but shared arithmetic can preserve the same error in both paths.

A solved stationary hover with tiny drift establishes numerical equilibrium. It does not establish disturbed hover, real pilot feel, negative-load transients, correct full-authority actuator dynamics or measured power. No clear new main-rotor dimensional defect was established in this review. Missing evidence must not be relabeled a demonstrated equation bug.

The independent [HELI-04-R1 evidence](../HELI-04-R1/README.md) already shows that unsplit 240 Hz inflow integration fails its prescribed seam-sweep error tolerance. That report gives exact event times to its refinement experiment; it does not establish automatic runtime localization. Keep this distinct from the new low-RPM and zero-stop reproductions.

The review did not validate physical radio hardware, complete 3D flight, slope parking, swept scenery collision, aircraft-specific real flight data or target GPU frame-time acceptance. It did not rerun the repository-wide Bash runner or all airplane goldens. Earlier full-runner failures and timing limitations remain dated in the existing evidence. There is no claim that the full repository is green.

## Primary-source review and reuse

Reviewed 2026-10-14. External sources inform architecture/physical interpretation; source parameters do not identify this particular supplied HX-700.

| Source | What it supports and what it does not |
| --- | --- |
| [Gavrilets, Mettler and Feron, Dynamic Model for a Miniature Aerobatic Helicopter](https://users.encs.concordia.ca/~bwgordon/mit_heli_report.pdf), as already read/rendered in [HELI-01/05](../HELI-05/README.md) | Source of the X-Cell mean-rotor/flybar-lumped baseline. This audit relies on the retained source interpretation; its fresh PDF fetch failed. The surrogate drive/servo/visual choices do not inherit the paper's full-flight validation. |
| [Walker and Tischler, Identification and Control Design of a Sub-Scale Flybarless Helicopter](https://www.sjsu.edu/researchfoundation/docs/VFS_2021_Walker.pdf), pp. 5–7, 12 | The 13-page digital paper describes the failure of a quasi-steady body-only approximation for its strongly coupled flybarless rotor/fuselage dynamics and the use of an identified hybrid model. Supports retaining rotor states and identifying the controller; it does not authorize copying 360CFX coefficients into HX-700 or establish a 3D envelope. |
| [Johnson, NASA/TP-2005-213477](https://ntrs.nasa.gov/api/citations/20060024029/downloads/20060024029.pdf), and retained [HELI-04 interpretation](../HELI-04/README.md) | Mean-inflow/VRS reference; retained local evidence owns its equation/table errata and branch-discontinuity checks. The 76-page PDF was accessible through browser text. This review does not claim a new full rereading or transient validation. |
| [FAA Helicopter Flying Handbook, chapter 11](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/helicopter_flying_handbook/hfh_ch11.pdf), autorotation and dynamic rollover sections | Physical separation of powered flight/freewheeling, rotor-energy use during landing and skid-pivot rollover. Full-scale speeds, ground-resonance claims and training procedures are not RC parameter values or requirements for this simulation. |
| [Rotorflight governor documentation](https://doc.rotorflight.org/setup/governor/); [mixer documentation](https://doc.rotorflight.org/configurator/tabs/mixer/) | Practical separation of off/idle/spool/active/hold/recovery and calibrated physical blade travel. Use as behavioral references and test-case inspiration, not copied firmware, gain constants or a claim that this simulator implements Rotorflight. |
| [BEASTX governor FAQ](https://wiki.beastx.com/index.php?title=Help:FAQ:Governor/en) | Manufacturer explanation of load regulation, soft start and recovery-rate behavior; supports treating startup and bailout as explicit, distinct responses. Does not calibrate the current governor. |
| [Godot CPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/cpu_optimization.html); [physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html); [float type](https://docs.godotengine.org/en/stable/classes/class_float.html) | Profiling/measuring bottlenecks, separating fixed simulation from presentation, and scalar precision. Local pinned settings/code remain authoritative; the public `stable` docs do not establish 4.7.2-specific performance. Context7 was attempted and unavailable, so official documentation was used. |

PDF text access covered the Walker/NASA/FAA page indexes; browser screenshot extraction did not provide a usable inspection image in this audit and the direct local download attempt was stopped after stalling. No new table transcription or precision parameter adoption is based on those unverified renders. Existing locally reviewed source-equation evidence remains the basis for the current numbers. Further hardware identification needs manufacturer/manual pages inspected alongside any imported values.

Reuse the supplied HX-700 source/export pipeline and free official papers/tools. Availability for free download does not itself grant asset redistribution rights; keep the existing provenance/admission process. No new geometry, audio, textures, engine dependency or runtime implementation was created for this audit.
