# External audits — consolidated review

Consolidated on **2026-11-06**, including the subsequently supplied developer remediation and Apple Silicon/Metal handoffs. **Read this document first.** It organizes seven distinct source reports, merges overlapping recommendations, and preserves the distinction between reported defects, experimental optimizations, and model limitations. The seven source reports retain their original content under descriptive filenames in this directory; four byte-identical copies of A1 were removed.

This is a synthesis of the supplied reports, not a new audit of the current working tree. Technical results below are attributed to their original source snapshots. No fix, performance gain, physical validation, or completed project gate is established by this consolidation. Current implementation status belongs to the [documentation map and owning tracks](../docs/README.md).

## Contents

1. [Sources, duplicates, and chronology](#1-sources-duplicates-and-chronology)
2. [Main conclusions](#2-main-conclusions)
3. [Correctness and measurement findings](#3-correctness-and-measurement-findings)
4. [Physics findings and model limitations](#4-physics-findings-and-model-limitations)
5. [Mathematical optimization register](#5-mathematical-optimization-register)
6. [Reported performance and kernel experiment](#6-reported-performance-and-kernel-experiment)
7. [Follow-up order and acceptance evidence](#7-follow-up-order-and-acceptance-evidence)
8. [Tools and platform constraints](#8-tools-and-platform-constraints)
9. [Evidence availability and original-file fingerprints](#9-evidence-availability-and-original-file-fingerprints)

## 1. Sources, duplicates, and chronology

The labels A1–A7 identify source documents in this consolidation; they are not implementation step IDs.

| Source | Original document | Scope and source identity |
| --- | --- | --- |
| A1 | [Apple Silicon audit — apple-silicon-performance-audit-2026-11-05.md][A1] | Audit associated with 2026-11-05; latest reviewed commit `fc018b38e44bfd3b83d46c88f7e6c6ab0c8137ab`. Source research and synthetic benchmark-reducer checks; Mac timings quoted from existing repository campaigns. No new native Mac benchmark. |
| A2 | [Mathematical Optimization Lab][A2] | Frozen commit `3df2791752fe2c1faad132fcb11febbb0ae788d1`, timestamp **2026-11-06 01:23:16 UTC**. Twelve portable numerical probes; Linux x86-64, CPython 3.12.14, NumPy 2.3.5, SciPy 1.17.0. No Godot execution or target-GPU measurement. |
| A3 | [Stage-validation reuse — stage-validation-reuse-experiment.md][A3] | Experimental single-file kernel patch against `3df2791752fe2c1faad132fcb11febbb0ae788d1`. Godot `4.8.beta2.official.cafc17a19`, Linux x86-64, Intel Xeon Platinum 8573C, reference GDScript backend, 240 Hz. No date stated in the report. |
| A4 | [Propulsion and energy audit — propulsion-energy-audit-2026-11-06.md][A4] | Dated 2026-11-06, reviewed commit `3df2791752fe2c1faad132fcb11febbb0ae788d1`; same official Godot beta2 on Linux x86-64, isolated minimal 240 Hz project. |
| A5 | [Fixed-wing aerodynamics review — fixed-wing-aerodynamics-review.md][A5] | Reviewed commit `3df2791752fe2c1faad132fcb11febbb0ae788d1`; Godot beta2, float64 state, isolated sparse app copy and user profile. No date stated in the report. |
| A6 | [Developer audit and remediation handoff — developer-audit-remediation-2026-11-06.md][A6] | Dated 2026-11-06; consolidates two audit passes at `3df2791752fe2c1faad132fcb11febbb0ae788d1`. Linux headless/debug Godot `4.8.beta2.official.cafc17a19`, GDScript reference backend, normally 240 Hz. Six reported defects F1–F6 and six optimization opportunities O1–O6; no production fixes or native execution. |
| A7 | [Apple Silicon and Metal Optimization Handoff][A7] | Dated 2026-11-06, America/Bogota. Combines historical `fc018b38` audit, shader/architecture experiments at `93ffbb101917dff86ecc2632f07e2e45c450a178`, and separate CPU/physics results at `3df2791`. Pinned Godot beta2, Linux x86-64, Python 3.12.14/NumPy 2.3.5; CPU screens, shader-language checks and headless camera-method checks, but no new native Metal GPU execution. Not the same mathematical lab as A2. |

### Source names and duplicate removal

The folder contains this consolidated document and seven source reports. Source contents are unchanged; only filenames were improved. The four numbered copies `Pasted markdown (1).md` through `Pasted markdown (4).md` were deleted after confirming their SHA-256 matched the retained Apple Silicon report. They contained no independent evidence.

| Original filename | Retained filename |
| --- | --- |
| `Pasted markdown.md` | [apple-silicon-performance-audit-2026-11-05.md][A1] |
| `OpenRC_Mathematical_Optimization_Lab.md` | [mathematical-optimization-lab.md][A2] |
| `FINDINGS.md` | [stage-validation-reuse-experiment.md][A3] |
| `FINDINGS2.md` | [propulsion-energy-audit-2026-11-06.md][A4] |
| `FINDINGS3.md` | [fixed-wing-aerodynamics-review.md][A5] |
| `NEWONE.MD` | [developer-audit-remediation-2026-11-06.md][A6] |
| `NEW.MD` | [apple-silicon-metal-optimization-handoff-2026-11-06.md][A7] |
| `README.md` (consolidation) | `CONSOLIDATED-AUDITS.md` |

### Differences between snapshots

| Topic | A1 snapshot | Later A2 snapshot | How to read the difference |
| --- | --- | --- | --- |
| Missing UID sidecars | Reports failed release preflight at `fc018b38` because five sidecars are missing. | Says the missing sidecars have been added. | Keep the failure as historical evidence. Do not carry it forward as a confirmed current failure or infer that all CI is now green. |
| Reconstruction default | Native is the default; Spatial is available; Temporal is a separate trial. | Auto is the default, selecting supported MetalFX modes while retaining at least 1,000 internal rows, otherwise Native. A2 says Auto selects Native at 1080p. | Defaults changed. Record effective mode and dimensions in every new comparison rather than relying on either historical default. |
| Earlier report identity | A1 explicitly names `fc018b38` as its latest audited revision. | A2 §1.2 calls an earlier guide frozen at `93ffbb101917dff86ecc2632f07e2e45c450a178`. | These are different source references. The supplied files do not establish that A2's earlier guide is exactly A1. |
| Cloud-cache evidence | Earlier C2 timing describes an RGBA8 ground/near-grass tile; enabled implementation uses RG16F and C5b sky relief. | A2 screens additional mathematical candidates, often using analytic low octaves as a proxy for the filtered cache. | Neither earlier C2 timing nor portable A2 screens qualifies the exact current cache and shader combination. |

## 2. Main conclusions

| Topic | Consolidated conclusion | Evidence class |
| --- | --- | --- |
| Additional shader and renderer experiments | A7 prioritizes a small zero-contribution sky patch, bounded density evaluation and a high-octave hash lattice; it also develops polynomial, integer/angular/ground, crop-camera and rate-map proposals. | Portable numerical, front-end and camera-method evidence; no new GPU speedup for these candidates. A7's historical working-cache profile is separately scoped below. |
| Admission, commands, and truck energy | A6 prioritizes F1 Workshop first-tick rejection after qualification, F2 changed flap/gear targets after pause, and F6 positive tire/brake work. | Scoped production-code/session counterexamples; priorities are the external report's recommendations, not current project labels. |
| Observer, fuel trial, and recording contracts | A6 reports F3 track-support disagreement, F4 an ineffective sub-ULP fuel sentinel, and F5 empty-block log rejection. | Geometric/numerical/serialization counterexamples with explicit limits. F4 is distinct from A4's lost firing counter. |
| Downwash pre-step optimization | A6 O4 reports about 42% less callback cost in its spatial-weather workload, with sampled exact outputs and refusal controls. | Headless component experiment, not 42% whole-tick or FPS improvement; separate from A3 and A2 M09/M10. |
| Glow firing counters | A4 reports a pre-exhaustion crank firing lost when a tick ends with fuel starvation. It is a counter/lifecycle defect at the reviewed snapshot. | Production-session witness plus discriminating controls; current repair status not checked. |
| Benchmark integrity | A1 demonstrates that synthetic receipts can pass despite Native fallback or GPU-profiler instrumentation, and identifies incomplete rendering identity. | Reproduced reducer behavior and source inspection at A1's snapshot. |
| Rendering lifecycle | A1 identifies conditional cloud-bake, renderer-recovery, and custom-shoreline risks. | Source-derived risks; not reproduced Mac/display failures. |
| Apple performance | Recorded campaigns point first to ground/cloud GPU work and then sustained presentation at actual 1080p. | Historical measurements; no latest-default sustained 1080p/60 qualification established by these reports. |
| Mathematical work reduction | A2 prioritizes M01 corner reuse, M02 solar chord geometry, and cheap M03 relief scheduling; M09/M10 merit evaluation where physics cost is measurable. | Proposed implementations and portable mathematical screens, not measured device speedups. |
| Kernel validation reuse | A3 reports exact comparisons and measurable component savings; full-session changes are small/noisy. | Experimental patch, limited software verification and headless timings. |
| Fixed-wing aerodynamics | A5 establishes no new serious production defect. Two candidates are documented conventions; one selector asymmetry remains unresolved and low-impact in its witness. | Model/source review and diagnostic probes, not physical validation. |

Throughout this document, **reported confirmed** means demonstrated within the original report's scope, **conditional risk** means a source-derived failure condition, **candidate** means unpromoted work, and **documented limitation** means an acknowledged model assumption. Mathematical proof in real arithmetic, sampled floating-point agreement, source operation counts, and target-device measurements are separate evidence classes.

A6 arrived later in this folder but reviews the **same commit as A2–A5**, not a newer implementation. Its six-defect count belongs to its two-pass handoff, not to the entire consolidated collection. A4's firing-counter defect remains separate; A6 F4 supplies the fuel-boundary-rounding finding that A4 explicitly excluded. A6's ground-effect discussion overlaps A5 and is retained once as a documented convention. Neither A6's inconclusive validation microbenchmarks nor A3's positive component results supersedes the other: they describe different experiments.

### A7 overlap and evidence reconciliation

- **Revision and archive identity:** A7's shader mathematical lab is frozen at `93ffbb`, whereas A2 explicitly freezes its separate lab at `3df2791`. Their similarly named ZIPs, polynomial constructions, sample sets and bounds must not be merged into one experiment. The relevant artifacts are distinguished in §9.
- **Historical defects:** A7 repeats A1's UID, effective-render, profiler, identity, cache readiness, recovery and shoreline findings. These remain the existing entries in §3, not new defects. A2 reports added UIDs; A7's instruction to recheck historical CI does not reopen them as proven current failures.
- **Corrected C5 diagnosis:** A7 attributes the old black-output C5 failure to Mobile/Metal sky sampling of a ViewportTexture and reports a stable ImageTexture fix. It explicitly supersedes an earlier interpolation-based explanation. This does not erase the separately measured errors of its later post-threshold relief bundle.
- **Later CPU findings:** A7 §18 repeats A6 F6, O4, O5 and bounded rotor/runout/replay controls at `3df2791`. Keep their detailed evidence and limits in §§3, 4 and 6; do not add another defect count or pool repeated timings.
- **Related mathematics:** A7's remaining-noise density bounds differ from A2 M03's relief-contribution budget. Its high-octave hash lattice differs from A2 M01's coarse-corner sharing. Solar LUT versus A2 M02 chord geometry are separate alternatives. A7 parcel/derivative screens overlap A2 M12/M05 conceptually but use distinct controls and result sets.

## 3. Correctness and measurement findings

### Developer handoff: F1–F6

**Source: [A6][A6].** Preserve its finding IDs and scope. Its recommended P1 means repair before relying on the affected path, P2 an observable correctness defect, and P3 a limited numerical/tooling defect. F6's P1 concerns energy-law correctness, not a demonstrated application crash. These are historical report classifications; current repair status has not been checked.

| ID / priority | Reported reproduction and consequence | Repair boundary and acceptance |
| --- | --- | --- |
| **F1 / P1 — Workshop stepping admission** | A synthetic Extra 300S draft sets `engine_main=0.311 kg`, `wing_main=0.270 kg`, `fuselage_rear=0.089 kg`, each with `source="measurement"`. These are schema-admitted counterexample inputs, not real measurements. `Trial.freeze` derives mass 3.0795476 kg and two gear substeps; Club-runway qualification and reset converge at cruise trim 0.5. First `sim.step()` faults at tick 0: whole-tick policy cannot honor two contact substeps. | Gear spring accuracy requests smaller steps, while glow installs a whole-tick event policy. Reject the incompatible combination before flight or compose contact/event segments atomically. Do not remove the guard or clamp subdivisions to one. Test first tick, contact becoming reachable, event ordering, complete rollback, and one input/AUX/RNG update/publication per accepted tick. Checked stock glow models used one substep; a general stock-start failure or later airborne landing failure was not demonstrated. |
| **F2 / P1 — Pause overwrites bound AUX targets** | Synthetic EdgeTX-style Avanti: flaps axis 4 and gear axis 5 are armed low, then held at +1. Across ordinary `pause_menu` hold/resume, accepted ticks 2→3 change flap request 1→0 and gear target up→down despite unchanged switch values. | AUX reset clears readiness; the session consumes an unarmed zero as a valid command. Separate command validity from amount or retain accepted position requests. Cover axis/button bindings, all flap/gear states, pause/menu/focus, deliberate rearming and physical actuator continuity; keep smoke-pump and disconnect/calibration/throttle policies explicit. This is not instantaneous actuator travel or a physical-transmitter/unbound-toggle result. |
| **F3 / P2 — Statistics omit circuit terrain** | Stik at NED `[39, -4, -0.755]` on the default Club circuit has track height 0.515 m and physical wheel compressions `[0.0119176434, 0.0128185565, 0.0145762139] m`. Observer reports valid sample, wheels `[-1,-1,-1]`, no support, and `clearance_ok=true`. | Early bound omits track height: gear reach 0.3505990400 m should retain this candidate with combined bound about 0.8655990400 m. Clearance/orientation also omit track, so fixing the bound alone is insufficient. Reuse composed `environment.ground()` and `ground_max_height()` identities; check ramps, edges, field/lake, mutations and complete detector episodes. Witness is staged geometry, not equilibrium or a measured false landing count. |
| **F4 / P3 — Connected glow trial rounds onto reserve** | With reserve 0.0042846 kg, binary64 ULP is 8.673617379884035e−19 kg; `reserve + 1e-30` equals reserve. The intended connected trial instead selects fuel-unavailable behavior during event localization. | Prefer explicit connected-trial state; an alternative representable sentinel requires equivalent lifecycle/native handling and downstream checks. Test neighboring floats, independent constant-flow event timing, integrated torque/force, and native/reference parity. Diagnostic `+1e-12` is not a qualified fix. Production still reaches reserve/emits stop; no crash or visible handling consequence established. |
| **F5 / P3 — Empty continuous-state log rejects itself** | Valid in-memory Stik via `AircraftData.validate_and_derive`, before optional file-boundary wheel profile, has an empty continuous block. Record/save succeeds; inspection fails with `Initial sample disagrees with checkpoint: continuous`. Snapshot omits the empty key, initial sample includes `[]`, reader requires the key. | Normalize legally absent v1 optional blocks to empty or emit explicit empty blocks while preserving compatibility. Check record/inspect/replay for absent, empty and nonempty states; retain malformed-data rejection. All checked flyable catalog entries had nonempty blocks, so this is not a general catalog-recording failure. |
| **F6 / P1 — Tire/brake constraints can add energy** | Acceleration-relaxation target and symmetric magnitude limits permit positive tangential contact or brake work. Production-solver examples, stock Bisonte energy balance, and a from-rest drive sequence demonstrate the tire defect; a separate brake example/scan establishes the brake defect. | Enforce dissipative admissibility with the existing load-scaled force limit, preserve static reactions at zero slip, and qualify combined slip, reversal, holding, load loss, stage-integrated energy, convergence and backend parity. A magnitude-only force circle is insufficient; independent component sign clamps impose a different constraint. Native equations were inspected but not executed. |

**F4 timing detail:** from `reserve + 1e-7 kg`, production versus connected-trial diagnostic exhaustion times are 1.763268/0.877741 ms (Stik 55AX), 1.373147/1.144313 ms (Stik FS64V), and 1.702545/0.847247 ms (Extra). Reported differences are 0.885527, 0.228833, and 0.855298 ms; displayed columns round independently. The roughly 5e−13 s event `time_error_bound_s` bounds the root bracket, not accuracy of a trajectory using the wrong trial law. Initial-flow estimates support the diagnosis but are not physical stopping-time measurements. This is separate from [A4's firing-counter finding](#glow-fuel-event-counter-defect).

### F6 energy and reachability evidence

For stationary ground and this nonelastic tangential model, A6 requires `F_long*s_long + F_lat*s_lat ≤ 0` and `Q_brake*ω_relative ≤ 0`. Slip includes full contact-point translation, body rotation, suspension and wheel motion. The implementation has normal elastic energy, but no tangential/brake elastic store to explain positive work. At zero slip/spin, static reactions can have either sign with zero instantaneous work.

The scalar relaxation law requests `F = (−s/τ − a_free)/W`. If positive slip is already decelerating faster than the target, the force can point with slip. An identity 14×14 mass-matrix production-solver case with `s=1`, `a_free=−2`, `τ=1`, and 10 N cap returns +1 N/+1 W after two sweeps; the analogous brake case returns +1 N·m/+1 W. This isolates the solver, not a physical truck.

| A6 evidence | Reported result | Limit |
| --- | --- | --- |
| Stock Bisonte instantaneous energy balance | Flat road, `mu=0.9`, `rolling=1.0`, body speed 5 m/s, wheel spin 30 rad/s, radius 0.1 m, throttle 1/brake 0: slip +2 m/s and about +10.96036 N per tire after six sweeps. Motor +468 W, rolling −5.683934337 W, tires **+87.682882561 W**, total +549.998948224 W. | Positive tire contribution is about 18.7% of motor input at this instant, not lap average. It does not depend on the known 128-sweep cap. |
| Independent energy derivative | Central directional differences of production total energy along the public state derivative agree with total +549.998948224 W within 6.3e−8 W for four epsilon values from 1e−4 to 1e−7 s. | Includes body/hub/axial-rotor kinetic, gravity and elastic energy; selected witness has zero body rate, suspension and vertical velocity. |
| Ordinary drive/brake sequence from rest | Throttle 0–1.50 s, brake 1.50–1.75 s, throttle 1.75–2.75 s, brake 2.75–3.50 s; no overlap, steering or reverse. All 840 steps accepted; throttle reapplication yields **+168.812180765 W** tire power, with 25 positive tick-start samples. | Production flat-road trajectory, not a rendered circuit lap. No positive brake work in this ordinary sequence. |
| Outer-step refinement over first 2.25 s | Peak positive tire power: 168.812180765 W at 240 Hz, 168.803890401 W at 480 Hz, 168.800126563 W at 960 Hz, about 0.0071% change. | Supports a force-law defect rather than a timestep cure. Positive-only work sums are sampled estimates, not net created energy or exact RK-stage integrals. |
| Separate brake scan | 486 valid cases without refusals include +108 W brake power at negative wheel spin with simultaneous throttle/brake. | Admitted core state, not a demonstrated player-input sequence. |

A6 proposes adding `F·s ≤ 0` to the existing load-scaled force disk under its mobility-metric projection, and the brake power condition at nonzero relative spin. These are necessary energy constraints, not a complete calibrated tire law. A repair intentionally changes physics and needs solver/checkpoint identity handling and explained trajectory changes; no contact-law patch is supplied as validated production work.

### Apple rendering and benchmark audit

All rows below come from [A1, §3][A1]. They describe its frozen snapshot. Suggested responses are retained recommendations, not work completed here.

| Finding | Trigger and consequence | Reported status and follow-up |
| --- | --- | --- |
| Release preflight lacks five UID files | Missing sidecars stop release preflight; app, visual, native-qualification, and release-build jobs are skipped. | Historical observed CI failure. A2 reports the additions; verify the relevant gate before treating the baseline as accepted. |
| Measured cache differs from enabled cache | C2 measured RGBA8 ground/near-grass caching; later RG16F also feeds C5b sky relief and becomes the graphical default. | Qualification mismatch. Identify ground-only, sky-only, and combined candidates separately. |
| Cache published before bake success | A zero-filled texture is enabled immediately. After three process callbacks, failed/empty graphical readback can leave the placeholder cached and enabled after the temporary viewport is freed. | Conditional risk, not a reproduced Mac incident. Keep analytic rendering until successful validation; define failure, retry, and fallback behavior. |
| Requested and effective rendering disagree | A synthetic MetalFX Spatial request passes even though effective rendering records Native fallback. | Reproduced acceptance defect. Compare requested/effective renderer, reconstruction provider, scale, MSAA, and fallback state. It does not prove historical campaigns used the wrong renderer. |
| Instrumented runs remain eligible | A synthetic checked invocation containing `--gpu-profile` can receive `performance_pass=true`. | Reproduced acceptance defect. Keep profiler/HUD/diagnostic runs distinct from clean acceptance measurements. |
| Fixture identity omits cache changes | Sixteen named hashes omit the new cache implementation/shaders; normalized scenarios omit cache environment and effective bake state. | Source-derived identity gap. Bind full rendering source identity plus explicit cache state. A retained full-source manifest may distinguish revisions even when fixture identity does not. |
| Recovery confirms callbacks, not displayed images | `_process` progress can satisfy the renderer guard without proving valid display output. | Conditional risk. Add evidence appropriate to graphical recovery. |
| MetalFX activation confirmer races | An older confirmer in an on/off/on sequence can clear the pending marker for a newer activation. | Conditional lifecycle risk requiring a focused transition case. |
| Custom shoreline cut can fail while lake metadata is published | A hole wholly inside one source triangle is rejected by clipping; attachment can log failure and still publish lake/physics metadata. | Conditional custom-lake mismatch. A focused fixture is needed; this is not evidence that the default lake is broken. |

The five historical sidecars are `app/app_state/renderer_guard.gd.uid`, `app/render/cloud_shadow_map.gd.uid`, `app/render/cloud_shadow_map.gdshader.uid`, `app/tests/test_cloud_shadow_map.gd.uid`, and `app/tests/test_renderer_guard.gd.uid`. The original includes the [failing CI receipt](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/42120685263/job/127571913297).

The cache default at A1 applies to every non-headless display server, including Compatibility/OpenGL. `OPENRC_CLOUD_SHADOW_MAP=0` selects its analytic baseline; an unset variable must not be interpreted as disabled. A 2048² RG16F tile occupies 16 MiB, so four retained tiles use 64 MiB before temporary buffers. Layered weather derives different seeds and may fall back to analytic noise: a single-deck result cannot establish a layered-weather gain.

### Glow fuel-event counter defect

**Source: [A4, first finding][A4].** At fuel exhaustion, `GlowFlight.step` integrates and locates the event, then applies the stopped endpoint's zero firing fraction to lifecycle acceptance for the entire tick. A crank opportunity before the stop can therefore disappear from accepted `fire_count`. Trace `glow_fire_events` and the audio voice consume these counters.

- **Public-session witness:** stock `stik_glow_55ax_2t`, public `set_fuel_start_fill()` and `reset()`, then two ordinary `Simulation.step()` calls. Fill `0.01428833552836` leaves approximately 0.000000786168 kg of usable fuel above the specified 5 mL unusable residue. This is an intentional API-boundary case, not an ordinary Home-menu fill claim.
- **Observed tick:** tick 2 adds one opportunity and zero fires, stops for exhaustion without a simulator fault, and records 3.984254 J of chemical work. Estimated opportunity time is 0.0074020 s; the located event is reported at 0.0081907 s. The ordering estimate does not independently qualify fuel-event timing.
- **Discriminating control:** a valid constructed state at 8113.948 relative RPM and phase 0.9 gives one opportunity/zero fires with one 240 Hz step, versus one opportunity/one fire with two 480 Hz half steps. The first half remains burning; both paths record approximately 3.679 J of chemical work.
- **Counter isolation:** passing the identical bounded continuous candidate through acceptance with firing fraction 0 versus 1 changes only the fire counter. Replacing the endpoint fraction with the initial fraction is a diagnostic, not a general fix.
- **Suggested correction:** account for opportunities on their accepted event segments, carry the deterministic accumulator, and define before/at/after-stop ordering. Preserve the accepted continuous solution and rollback; cover multiple opportunities and an event-free control.

This finding establishes a lifecycle/counter error within the report. It does not establish incorrect shaft torque, fuel mass, trajectory, or audible waveform, and it excludes the separately known fuel-boundary-rounding issue. No natural full-tank exhaustion flight was run.

## 4. Physics findings and model limitations

These items must remain separate from the reported defects in §3.

| Item | Reported observation | Disposition |
| --- | --- | --- |
| Relative-shaft propeller power convention, A4 | Constructed stopped-source Extra sample: zero hub flow, 30 RPM relative shaft speed, body roll −400°/s. Propeller torque +5.777973 µN·m; absolute shaft speed −36.6667 RPM. Combined mechanical power is +22.185824 µW, versus −18.152038 µW with zero roll. | Quantified consequence of the documented mean axial-propeller/relative-shaft model, which omits blade-by-blade body-rate inflow. No flown trajectory, new undisclosed regression, or physical calibration established. |
| Slipstream versus ground effect, A5 | Tail downwash is scaled by ground effect, but the washed-minus-free slipstream increment is not. Extra, P-51, and Corsair declare both modules. | Explicitly documented height-independent slipstream increment. Changing it would be a physics-law change, not a demonstrated bug repair. |
| Extra lower-rudder force arm, A5 | Polygon-centroid x is 0.980531 m versus tail reference 0.849684 m. At 15 m/s, 12,000 RPM and 25° rudder, lower-piece force is 2.077987 N; using the centroid would add −0.271898 N·m yaw. Twenty decomposition cases match the full wake. | The geometric centroid is not a measured pressure center. The legacy reference-plane convention is documented; the alternative arm is not established as physically correct. |
| Negative-angle stall-selector asymmetry, A5 | Initial selector uses `a1` for both signs, while station selectors distinguish `a1`/`n1`. Turbo Lumber at −14°, 20 m/s: diagnostic weight 0.7037029102 versus production 0.9358366063; pitch moment changes from 5.118864385 to 5.071713366 N·m, about 0.92%. Seven-aircraft/positive-angle controls report no load failures. | Unresolved low-impact candidate. The one-expression variant exposes a difference; it is not a recommended or physically validated repair, and no substantial flight consequence is shown. |

Detailed assumptions and original evidence locations remain in [A4][A4] and [A5][A5]. Their numerical checks are software/model-consistency evidence, not aircraft validation.

### Additional bounded controls and known limitations from A6

| Investigation | Reported outcome and boundary |
| --- | --- |
| Selected baseline tests | `test_simulation.gd`: 11 checks; RC input: 41; AUX runtime: 38 with expected overlap warning. These do not cover F2's full session composition or establish full-suite success. |
| Rotor/body and inflow checks | 600 X-Cell states without refusals, maximum power-identity residual about 9.1e−13 W; 27,150 scalar inflow samples, maximum residual about 1e−13. Bounded controls, not full physical validation. |
| P-51 fuel runout | Runway start at valid 1.01% fill exhausts at 0.934817 s and continues 15 s without the suspected fault; a 200 m airborne start also continues. Legacy sub-1-RPM hold is documented; runway speed settles near 0.85135 RPM. |
| Event checkpoint replay | P-51 checkpoint tick 210 through 280 and Turbo Lumber rotor-stop tick 1430 through 1490 retain byte-identical subsequent checkpoints/events under prescribed held inputs on the reference backend. |
| Electric reverse breakaway | A stopped electric propeller reaches an already documented/tested unsupported-domain refusal in a stock glide/roll sequence. Separate model-domain work, not a newly discovered defect. Other reviewed electric/battery/ESC/fuel/mass/turbine paths yielded no additional serious defect in the handoff. |
| Known truck convergence/asymmetry | Symmetric braking witness returns success at the 128-sweep cap with yaw acceleration −0.0114509624 rad/s²; a cap-only diagnostic reaches update tolerances after 1,766 sweeps with −0.0000239593 rad/s². Reversing contact-pair order reverses yaw. Both force and brake tolerances already participate in early-out; unconditional success at the cap is the known limitation. |
| Convergence trajectory scope | A separate four-second sequence hits the cap in 671/960 tick-start evaluations but reaches only about 0.206 mm lateral offset and 0.00232° yaw; it is still moving at the end. This does not establish another new severe defect. Small updates are not a full complementarity residual, and nonunique reaction distributions need care. |
| Ground-effect/propwash convention | Overlaps A5's documented convention above. A6's exploratory numerical comparison was not retained in recovered packages, so A6 adds no quantitative magnitude claim. |

The known cap/asymmetry limitation is **distinct from F6's newly reported positive-work law**, whose stock energy witness converges in six sweeps.

## 5. Mathematical optimization register

**Source: [A2][A2].** Preserve its original M01–M12 and R01–R02 experiment identifiers. Results in this section are analytical proofs under stated assumptions, source analysis, or portable numerical models. No candidate has a measured Apple-GPU speedup in this lab. Full derivations, coefficients, source links, and probe names remain in the original.

A2 identifies partial-fBm exits, hash atlases, octave dictionaries, solar LUTs, crop rendering, relief caches, and rasterization-rate maps as topics already discussed in the frozen repository's `optimization help.md`. It does not count those ideas as new lab results or rerun their campaigns.

### Cloud and sky

| ID / source section | Candidate and useful reported result | Required boundary |
| --- | --- | --- |
| **M01**, §3 | Share four coarse value-noise corner hashes across three displaced relief queries when their wrapped lattice cells match: 12 source-level hashes become 4 on that path. Same-cell rates 82.49%, 97.20%, 99.14% for three tested light elevations; selected float32 and seam checks show zero difference. | Keep each query's original interpolation and original fallback at cell crossings. No saving when clustering is disabled. Unguarded sharing produced errors up to 1.0. This does not remove two thirds of the whole cloud shader and does not generalize to fine octaves. |
| **M02**, §4 | Replace ordinary solar `acos` with chord coordinate `c = sqrt(2 - 2μ)`, transforming disc thresholds too. Global real-arithmetic normalized halo error bound: 1.7838854e−4. Screened 1,162,773 distinct float32 cosines; sampled combined `0.35H + 4D` difference at one default radius: 6.0601160e−5. | Disc ramp is an approximation, not an algebraic identity. The halo bound does not bound the disc or GPU rounding. Preserve dynamic radius, limb/squash mode, occlusion, radiance generation, and multiply error by actual HDR solar contribution. |
| **M03**, §5 | Use monotonic relief endpoints to bound omitted density queries. Midpoint error is at most half the interval width before consumer weighting. At budget 0.001, cheap-decision query averages range 0.621–2.809 versus 3 in four selected screens. | Start with the cheap far bound; retain original density for silhouettes, occlusion, and other consumers. Classic and layered clouds require different color multipliers. Bound all layers/approximations together. Sample requests do not equal issued GPU work. |
| **M04**, §6 | Reject zero-support sun/moon aureole work by dot-product cutoff before inverse trig; ordinary disc has its own support. In 1,002,126 sampled inputs, two-ULP downward guards showed zero false culls. | Empirical guard is not a proof for every GPU math mode. Keep moon antialiasing derivatives ahead of varying early-outs, and keep optional solar limb/squash behavior distinct. A 45° cap's 14.64% sphere coverage is not viewport frequency. |
| **M11**, §9 | Approximate transmission `exp(−z)` only for bounded `z ∈ [0, 2.16]`. Degree-five Horner polynomial: sampled maximum error 2.6417046e−5 across 398,536 float32 inputs; real-coefficient truncation bound 2.6422810e−5. | Lower priority until exponential cost is measured. Rounded degree-six/seven results exceed ideal truncation bounds; the sampled endpoint slightly exceeds ideal 2.16. Five multiply-add stages may cost more than the exponential. Combine its error with M03. |

For M03, with body density and samples bounded to [0, 1] and normalized directions, the relief factor is nonincreasing in each unknown sample. Its coefficient satisfies `0.38 ≤ B ≤ 0.50`. A cheap far-sample sufficient bound is `E_far ≤ k B (1 − exp(−0.4)) / 2`, where `k` is the **actual consumer's** color contribution. A 1e−7 margin prevented budget overruns in one CPU stress screen; it is not a certified Metal margin. The hypothetical 32-lane coherence screen likewise does not establish Apple's pixel-to-SIMD mapping.

M01's portable model substitutes analytic low octaves for the actual filtered RG16F cache. Its four-query extension and cross-cell deduplication may remove more arithmetic but retain more live data and bookkeeping. Begin with the smaller three-query case and retain wrong-seed, disabled-cache, periodic-boundary, and both-ray-sign controls.

M03 also requires sampler/derivative discipline around varying branches. A2's source uses a non-mipmapped linear cache sampler; future mipmapped/anisotropic routes need gradients computed before divergent flow or a validated explicit-LOD/gradient operation. This is an implementation boundary, not evidence of an existing shader defect.

### Ground shading

| ID / source section | Candidate and useful reported result | Required boundary |
| --- | --- | --- |
| **M05**, §7.1 | Compute the base noise footprint once, then divide by the constant octave scales. Source spelling reduces eight vector derivatives/lengths to two of each. In 500,000 synthetic quads, maximum macro-noise difference 9.06e−6; dry-patch weight difference 3.50e−5. | Tolerance-based rendering change: differencing rounded transformed coordinates is not byte-identical. Keep derivatives outside divergence; cover ground, near-grass, lake-bank, and the bank's separate 2.8 m call. Inspect compiler reuse first. |
| **M06**, §7.2 | Share relief phases/cosines; omit sine work only where amplitude gradient is zero. In 300,000 samples, maximum slope-component difference 7.45e−9; modeled normal-angle difference 4.77e−7 degrees. | Preserve `∇h = A∇W + W∇A`, including feather-edge amplitude gradients and surface precedence. Physics terrain stays unchanged. Update affected literal-substring tests without treating a CPU mirror as GPU proof. |
| **M07**, §7.3 | Skip one photographic anti-tiling endpoint when its blend weight is exactly 0 or 1: three texture requests instead of six for the affected material. 29.54% endpoint positions in a uniform-area disk; same-endpoint quad rates fall as pixel footprint grows. | Finite texture values, original explicit gradients before branching, and exact endpoints only. Divergence may erase savings. Shared grass/dirt indices and offsets are another same-position reuse opportunity; cover normals and lake banks too. |
| **M08**, §7.4 | Share grass/dirt tangent frame in overlap pixels; normalize/blend in tangent space, project once, and retain final normalization. Across 400,000 synthetic normals: median angular difference 1.82e−6°, p99 6.12e−6°, maximum 0.0001394°. | Preserve dirt-only and grass-skipped paths, incoming normal magnitude where relevant, frame conditioning, and rigid view-transform assumptions. The model omits real texture decoding, view transform, and GPU execution. |
| **M12**, §10.3 | Guarded parcel rejection preserves selected IDs/factors in 250,000 random and 70,000 boundary samples with empirical guard 1.000001; averages 4.88 square roots versus nine in the random set. | **Research only.** Unguarded squared-distance ranking changes float32 tie behavior and material identity: raw crop-factor difference up to 0.283, default faded factor up to 0.133. Near threshold retain original roots and strict comparison order; GPU rounding/branch cost remain unresolved. |

### Same-evaluation physics reuse

| ID / source section | Candidate | Exactness contract |
| --- | --- | --- |
| **M09**, §8.1 | Pass already validated reference/spatial wing-flow results into the matching `local_loads` evaluations. For six strips, removing two passes implies 11,520 fewer source-level `atan2` evaluations and 23,040 fewer square roots per simulated second at four stages/240 Hz on that qualifying route. | Reuse only within the exact same RK evaluation and matching inputs. Distinguish reference/spatial and optional wake inputs. Preserve validation order, NaNs, signed zero, refusal, rollback, and serial reductions. Operation counts exclude additional events/substeps and are not timings. |
| **M10**, §§8.2–8.3 | Lazily prepare identical flap invariants once per evaluation; prepare clean-strip source factors once per source strip. Preparation falls from `A×N` to `N` for `A` active receivers and `N` strips; map products remain. Smaller glow-propeller opportunity: reuse axial-speed square and half-density across 12 annuli. | Keep original expressions and multiplication/accumulation order, and avoid evaluating a branch that was previously unused. No cross-stage, cross-tick, changed-control, changed-wind, or clean/flapped cache reuse. |

A2's native probes explain why algebra alone is insufficient: reassociating quaternion rotation changed at least one component in 9,673 of 10,000 binary64 cases (maximum difference 1.42e−14), and sharing apparently equivalent flow intermediates changed signed-zero bytes in a fixed case. Do not normalize intermediate RK quaternions or reorder reductions as part of a performance refactor. M09/M10 are separate from A3's kernel-validation candidate.

### Rejected or deferred alternatives

| Proposal / source section | Reported result | Disposition |
| --- | --- | --- |
| Local gradient replaces displaced cloud relief, §10.1 | Analytic derivative agrees with central differences, yet finite-displacement lighting error reaches 0.573 at low sun and 0.126 near overhead light. | Rejected shortcut: a local tangent changes the finite-distance optical-depth heuristic. |
| **R01**, footprint-aware noise statistics, §10.2 | A two-point moment model improves one conditional-bias statistic, but active-density RMSE remains about 0.039–0.067 against 16×16 supersampled footprints. | Do not ship residual-mean/moment substitution as a filtered equivalent. Filter thresholded density and lighting with a justified footprint/correlation model. |
| **R02**, analytic terrain-wave box filtering, §10.4 | Sinc filtering under constant amplitude and locally affine footprint skips any/all terms in 9.98%/7.68% of synthetic cases within a chosen budget. Filtered slopes themselves differ from current point samples: p99 0.00497, maximum 0.01055. | Separate visual-quality research, not a parity refactor. Perspective and amplitude edges need treatment; use moving supersampled references. A simpler pointwise bound skips all waves in only 1.54% of tested weights. |
| Generic fog pruning, §10.5 | Under sampled defaults, omitting a whole shaded contribution bounded by 0.03 at budget 1/255 becomes eligible only beyond about 5,728 m: roughly 0.017° depression from a 1.7 m camera. | Weak priority for the default pilot view; other fog/aerial cases may differ. Albedo error alone does not bound final shaded color. |
| Unguarded parcel ranking | Float32 distance ties change which material is selected. | Rejected version of M12; only the guarded research route remains. |

### A7 shader experiments at the separate 93ffbb baseline

**Source: [A7, §§7–14][A7].** Use the source section numbers below, not new M identifiers: A2's M01–M12 belong to a different lab. All numerical counts are scoped screens, logical work counts or conditional proofs. A7 supplies no native Metal timing for these candidates.

| A7 section / candidate | Reported result | Conditions, negative controls and disposition |
| --- | --- | --- |
| **§7 — Density interval termination** | With five nonnegative noise weights totaling 31/32, bound unfinished octaves and stop only when local post-cluster coverage proves smoothstep density exactly 0 or 1. Original screens report 105,144,320 parameterized comparisons without CPU differences. One grid skips 44.897% of octave work, or 37.415% including clustering. | Reused coordinates are not independent device observations. Keep complete ambiguous evaluations and raw-noise/tile consumers. Check placement depends on coverage. Unlike A2 M03, this omits internal octaves at saturation rather than approximating the contribution of whole displaced queries. |
| **§7 — C5b conditioned extension** | Bound the remaining 3/32 then 1/32 after cached low octaves. Four active-body/offset scenarios average 4.0781, 2.5404, 4.8447 and 2.3213 requested high octaves instead of six (19.25–61.31% logical reduction). Eighteen scenarios plus offsets show zero CPU bit mismatches; deliberately wrong remaining bound yields 9,717. | Harness computes all octaves and models half-float tile plus ideal interpolation, so it does not time early exits. The earlier 1e−5 normalized margin and later 1e−4 raw-sum margin have different units; neither certifies GPU rounding. Retain outward error bounds, seeds/seams/fallback and valid derivative flow. Proposed nearest/exact-fetch min/max atlas adds 16 MiB/seed and is unimplemented. |
| **§8 — High-octave hash lattice** | A repeated 1024² RG16F atlas stores octave-3/4 corner hashes, retaining original quintic interpolation. Three fully evaluated offsets trade 24 source hash calls for six new fetches plus three existing low-tile samples; +4 MiB/seed. Eight scenarios ×8,192 positions: maximum current-C5b→candidate density/active-relief differences 0.0001339316/0.0002461076. | Keep half-texel offset, explicit LOD 0, seed/readiness fallback, low cache and analytic silhouette. Missing offset/wrong seed cause octave errors 0.62684/0.96920. Hypothetical eight-bit interpolation gives density/relief errors 0.00071239/0.0011220, not a Metal specification. Full-analytic→current/candidate density errors 0.0152022243/0.0152694583 are different comparisons. Direct UNORM modeling does not prove supported texture formats or undo prior half quantization. |
| **§8 — Independent octave mip levels** | Proposed five separately authored lattices, 1024² through 64², total 1,396,736 samples: about 2.664 MiB R16F or 5.328 MiB R32F/seed. Ideal binary16 corner model bounds fBm error by 2^−12 and threshold density by 0.00146484375. | Unimplemented alternative, not ordinary generated mips: octave seeds differ. Actual mip upload/filter support, periodicity, stretched fields, sampler rounding and output lighting remain open. |
| **§10 — Integer hash factoring** | Modular neighbor additions reduce source multiplication spelling from 16 to seven per four-corner query for supported periods 4, 64, 128, 256, 512, 1024. 34,348,032 corner and 1.5 million point comparisons show no CPU bit mismatch with the same wrapped coordinates. | Preserve float wrapping/floor/interpolation and fallback for unsupported layouts. Removing float wrap changes 38,197/250,000 and 19,125/250,000 outputs in two domains. Wrap-once screens do not settle Metal/subnormal/FTZ behavior. This is per-query algebra, not A2 M01 cross-query sharing or the §8 texture path. |
| **§11 — Three-change zero-contribution patch** | At `93ffbb`, patch applicability and full-sky language checks pass: move existing nonpositive sun-disc-dot return earlier; skip directional scatter power when uniform `sun_scatter==0`; skip classic cloud density when its existing horizon fade is zero. | Preserve independent cirrus, notably `0.02 < EYEDIR.y ≤ 0.03`, moon derivatives and layered composition. Skipped work in this patch has no texture/derivative calls. Claim is intended bounded inputs with finite intermediates, not universal bit equality. Alpha-zero layered subtract/subtract expressions need a separate rounding decision; no GPU images/timing supplied. |
| **§12 — Aureole support** | Guarded dot cutoff 0.7071057558059692: zero false culls over 1,977,069 CPU values, 18 conservative retained zeros; unsafe 0.71 cutoff produces 5,840 false culls. | A distinct guard/sample set from A2 M04. Sphere-cap area is not viewport frequency. Keep moon `fwidth` ahead of varying control flow. |
| **§12 — Air-mass algebra** | Remove a sqrt/square round trip using the same rounded horizontal-length square and original clamp. Across 1,101,341 inputs: maximum air-mass difference 7.62939453125e−6, default sun-path difference 5.960465e−7, normalized moon-path 3.576279e−6. | Real identity, not bit identity. GPU dot contraction and inverse-square-root lowering lie outside the CPU model. |
| **§12 — Moon tangent / shared powers** | Cartesian tangent with original trig fallback at squared xy radius ≤1e−12: 550,006 directions, 25,002 fallbacks, maximum vector difference 3.47552e−7. Shared five-multiply chain produces powers 8/12/24; 996,895-input errors about 1.95e−7/2.97e−7/5.96e−7. | Keep longitude for UVs and polar fallback. Share only the same light cosine, preserve no upper clamp and small overshoot. Compiler strength reduction, registers and the moon's small screen area limit expected benefit. |
| **§13 — Pilot distance and hash palette** | Same pilot-distance arguments can be shared with wrapper retained for other consumers. Anti-tiling bounded indices suggest a palette: one million coordinates, indices 0–7, zero differences for the same CPU float32 hash; two hashes potentially removed, both textureGrad calls remain. | No measured speedup. Retain entries 8/9 and dynamic fallback; double-generated constants differ by up to 0.00474655 in supplied controls. Literal-hash dispatch/target folding need GPU equality checks. Uniform pilot-anchor and stable material caches remain proposals needing update/lifetime design. |
| **§13 — Parcel ranking and guarded rejection** | Naive squared ranking changes 6,640 site pairs/1,692 colors in 900,000 adversarial points, maximum raw component difference 0.2948699; 500,000 random points miss the problem. Guard `q > d2*d2*(1+1e−5)+1e−5` preserves IDs/colors across all 1.4 million points while avoiding 45.74%/43.98% logical roots in the random/adversarial sets. | Reject naive exactness claim. Guard is empirical and differs from A2 M12's 1.000001 experiment. Keep original roots/order for potential winners; branch cost may erase savings. Raw color differences precede outer blending/display. |
| **§13 — Shared derivative footprint** | Four scales, 250,000 synthetic quads each, show maximum filtered-noise differences from 1.12057e−5 to 1.75923e−4; scale 37 has two threshold flips. | Distinct screen from A2 M05. Rounded divide/translate before lane differences is not the real chain rule. Preserve derivative legality and qualify moving transitions. |
| **§14 — Warped solar LUT** | 512×1 R16F, 1,024 bytes, `t=sqrt((1−μ)/2)` with texel-center mapping: maximum normalized halo error 0.0006784201 over 820,197 float32 dots; about 0.000237447 after the 0.35 coefficient. Uniform-dot 512-entry error is about 0.35095. | Low priority; ideal interpolation and assumed precision, not final HDR error. Linear clamped/no-mip data and ready fallback required. Replacing halo alone leaves the `acos` shared with the analytic disc, so it adds a sqrt/fetch while removing only the exponential unless separately restructured. Distinct from A2 M02 chord geometry. |
| **§14 — Post-threshold relief bundle** | Baking near/mid/far thresholded densities into RGBA16F costs 2/8/32 MiB per combination at 512²/1024²/2048². At 2048², maximum scalar-relief error is 0.04254 default or 0.04963 clustered low sun; lower resolutions are worse. | Deprioritized for error/memory. Two 32 MiB replacement buffers plus existing 16 MiB tile already total 80 MiB before overhead. Light-ray drift needs invalidation; a +0.05 x-ray change raises default maximum error to 0.08776. This is separate from the corrected old black-texture failure and from A2's local-gradient rejection. |

**A7 §9 polynomial evidence is separate from A2 M11.** It uses the representable endpoint `X=2.1600000858306885`, center `C=X/2`, centered Horner evaluation, and original `exp` fallback outside the domain. An exact rational order-32 Taylor polynomial is converted/truncated in Chebyshev form, then coefficient quantization is bounded. Conditional floating-point bounds additionally cover center subtraction and Horner rounding under stated IEEE round-to-nearest, gradual-underflow and correctly rounded FMA assumptions.

| A7 polynomial degree | Real bound including quantized coefficients | Conditional IEEE-RN FMA bound | Observed host-FMA maximum |
| --- | --- | --- | --- |
| 5 | 2.641706e−5 | 2.660503e−5 | 2.645865e−5 |
| 6 | 2.026621e−6 | 2.214913e−6 | 2.112994e−6 |
| 7 | 1.57923e−7 | 3.46265e−7 | 2.7069e−7 |
| 8 | 4.34325e−8 | 2.31783e−7 | 1.6788e−7 |

The host screen compares 1,250,008 inputs with NumPy binary64 exponential, not interval-certified exact samples. Separately rounded multiply/add bounds for degrees five/six are 2.666935e−5/2.279280e−6; nine host out-of-domain/nonfinite fallback cases pass. These do not certify Metal fast math or NaN payloads. A bounded relief multiplier ≤0.5 halves the corresponding scalar transmission bound before color/postprocessing; A7's cited degree-six 1.013311e−6 is derived from the **real** bound, not the GPU or FMA bound. Native MSL sketches were not Metal-compiled. Degree five/six remain experiments against actual exponential lowering; more degree can increase dependent arithmetic with diminishing rounding benefit.

### A7 larger renderer proposals

**Native-pixel aircraft crop, §15:** render a lower-scale background plus a padded off-axis crop at one physical output pixel per crop pixel, sharing the full World3D and occluders, then composite before native UI. Existing aircraft-only magnifier infrastructure is not equivalent. Actual pinned Camera3D tests cover 96 configurations: 3,168 projection comparisons within 0.0086895 px; 1,056 inverse-ray comparisons within 2.884674e−6; 1,152 clipping checks excluding exact boundaries; matching camera-space depth; 72 wrong-offset controls rejected. These are camera geometry results, not rendered seams or performance.

The off-axis crop's `project_ray_normal()` disagrees in 792/1,056 cases (maximum vector difference about 1.29545); use validated main-camera pixel mapping or inverse projection. A7 also records an off-axis `project_position()` inversion diagnostic failure. Recheck on engine changes. The shaded-area model `s²+p` gives 0.5444 at two-thirds background scale and 10% crop, **not** 45.6% GPU savings: duplicated culling/submission/shadows, postprocessing and composition are omitted. Qualify occluders, motion/padding/hysteresis, large-crop fallback, effects, exposure/fog/depth/LOD, jitter, resize and total CPU/GPU time.

**Native Metal rate maps, §16:** separate row/column rasterization rates are not arbitrary 2D masks or display refresh control. At pinned engine `cafc17a`, ordinary Metal VRS texture creation errors, but external native `MTLRasterizationRateMap` import and render-pass assignment expose a real integration seam. Desktop `Viewport.VRS_TEXTURE` does not automatically connect it to built-in Mobile scene rendering. No native prototype/timing was completed; an engine patch may be needed but was not proven inevitable. Prototype simple-scene import/unwarping, then built-in integration, screen/depth/transparency/MSAA/history consumers and complete-frame benefit. Existing private texture storage, Metal 3 dispatch and transient-buffer TODOs are not standalone optimization results or proof of wasted traffic.

**Layered-cloud bounds, §17:** premultiplied front-to-back transmittance can bound omitted far radiance, but reordered floating-point results and solar occlusion must be covered. `exp(−8*density)` has sensitivity up to eight before solar intensity/display processing; arbitrary alpha cutoff near bright sun is insufficient. Retaining all densities and omitting only negligible far relief is a less aggressive candidate. Classic single-deck weather offers no general multilayer saving; no implementation/timing is reported.

## 6. Reported performance and kernel experiment

### Additional historical cache measurements reported by A7

At its `93ffbb` baseline, A7 describes a stable 2048² RG16F ImageTexture per seed: R holds full five-octave ground/near-grass noise; G holds the unnormalized first three octaves for C5b relief. The last two relief octaves and sky silhouette remain analytic. Base storage is 16 MiB/seed before copies and overhead. The reported stable-texture correction is distinct from readiness/failure qualification.

| A7 historical result | Scope and limit |
| --- | --- |
| Working C2+C5b tile off/on/default: 26.20/23.45/23.44 ms GPU | About 2.75 ms or 10.5% off/on difference in **single profiled runs**, not clean repeated acceptance or a new current-source measurement. |
| Separate 1920×1080 pilot/aircraft-ground stills: maximum difference 2/255, none above threshold | Named still-image scenes only; no moving-flight or sustained qualification. |
| Earlier combined C1+C2+D1: 61 FPS, p95 17.28 ms, p99 29.11 ms | Short diagnostic; p99 still missed the cited screen. It cannot isolate or sum each component's effect. |
| Sky relief disabled: about 2.34 ms less GPU time; historical shoreline D1 about 2.3 ms | Separate diagnostic ablations, not additive savings or candidate guarantees. |
| Mask-only wrapping: 28.40 versus 28.42 ms | Reverted as no useful M1 gain; integer source simplification alone is not evidence of faster rendering. |

The original attribution and Metal/GL results below overlap A7's retelling and are retained once. A7 additionally identifies the R4 host as MacBookAir10,1, macOS 27.0.1, AC power, and reports native-Retina p95 around 27.2–28.5 ms for the short Metal/GL comparisons. These are historical host/workload details, not current configuration claims.

### Apple measurements quoted by A1

These are **existing repository campaign results**, not measurements made during this consolidation or new native measurements by A1. The primary attribution workload used an M1 MacBook Air, seven-core GPU, 8 GiB RAM, Mobile/Metal, Medium scenery, pilot camera, and 2560×1600 display; its short sweep used 10 s warmup plus 20 s observation.

| Workload/change | Reported result | Interpretation limit |
| --- | --- | --- |
| Internal scale 1.0 → 0.5, 4× MSAA | 38.3 → 89.6 FPS, about 2.34× | Strong pixel-work signal, not matched-quality or sustained 1080p acceptance. |
| Main-thread sample / GPU attribution | About 57% waiting on GPU; 28.42 ms total GPU, 22.34 ms opaque | Supports GPU-first investigation in this workload. |
| Hide ground / disable ground cloud shadows | About 11.08 ms / 3.55 ms less GPU time | Separate ablations; savings cannot be added. |
| Separate sky diagnostic, clouds disabled | About 7.59 ms less GPU time | Different diagnostic; not additive to ground results. |
| Hide tested vegetation group | About 0.06 ms difference | Low priority for that view, not every scene. |
| Five short beta2 Metal-versus-GL pairs | 32.2–36.3% higher FPS with Mobile/Metal | Short comparison, distinct from sustained beta1 evidence. |
| Earlier beta1 seven-file bundle; three 30 min runs per role | 17.64–23.17% higher paired FPS; all 73 common complete state/input hash windows match | Candidate p95 about 31.2–31.8 ms and p99 43.8–44.4 ms remain outside intended pacing target. Bundle contains six shaders and lighting WeakRef reuse. |
| Earlier C2 RGBA8 cache | 28.09 → 25.72 ms GPU | Does not qualify later RG16F/C5b default. |
| Retina reconstruction comparison | Native 28.26 ms; MetalFX Spatial at about two-thirds scale 18.68 ms; bilinear at same scale 16.87 ms | MetalFX adds reconstruction cost; stills favored thin aircraft detail, but motion/readability needs qualification. |
| MSAA sweep | 4× → 2× about +2% FPS; disabling about +10% | Workload-specific; preserve thin-edge quality when comparing alternatives. |

Output dimensions and internal 3D dimensions must be recorded separately. At 2560×1600 output, 0.75 scale is **1920×1200**, and roughly two-thirds is **1707×1067**. Neither is actual **1920×1080 output**. Per-axis scale changes pixel count quadratically.

### Stage-validation reuse experiment

The following kernel experiment is independent of A7's rendering profiles and A6 O4's pre-step candidate.

**Source: [A3][A3].** The candidate changes only `app/sim/simulation.gd`. After the packed body-plus-continuous array has passed finiteness checks, it checks quaternion norm directly instead of slicing and rescanning the same 13 body values. A local `verified_joint` fact skips duplicate checks immediately after successful joint validation, only where no callback/mutation intervenes.

The candidate retains calculated-derivative checks, split/body-only checks, and first-stage checks after `model.rotor_momentum`, because that callback can invalidate a previously returned array. It preserves norm expression order/thresholds and has no persistent cache. Future changes must preserve that short read-only interval or revalidate.

| Verification reported by A3 | Scope |
| --- | --- |
| 44,025 derivative-equivalence checks | Seeded packed states, invalid sizes/fields, nonfinite values, signed zero, quaternion thresholds/overflow, and callbacks mutating returned derivatives. |
| 3,840 exact derivative-array comparisons | Four stages over 960 synthetic ticks, including joint, split, and body-only routes, plus stage inputs, outputs, states, loads, and faults. |
| 120 stock joint-stage samples per aircraft | Default Stik, finite-glow Stik, and Avanti; byte fingerprints for loads, continuous/body derivatives, and rotor momentum. |
| Three complete 720-tick flight recordings/replays | Each compares 721/721 rows without divergence. Baseline replay has `solver_changed=false`; candidate correctly has `solver_changed=true`. Exact matched rows do not establish unchanged solver identity or every checkpoint/event/platform case. |
| Nine existing tests pass | Simulation, vehicle model, contact substeps, event protocol/refinement, continuous state, ground-vehicle kernel, helicopter startup, and generalized coordinates. Full CI and rendered/physical validation were not performed. |

Component timing used 16 alternating AB/BA pairs, CPU 0 affinity, an editor/debug engine on a shared Linux host, with all samples/outliers retained. Percentage reductions are medians of paired percentages, **not ratios of the displayed independent medians**.

| Headless workload | Baseline median | Candidate median | Median paired reduction | Pair range |
| --- | ---: | ---: | ---: | --- |
| Packed guard, 1 continuous value | 1.986 µs/call | 1.491 µs/call | 27.13% | −44.48% to +35.96% |
| Packed guard, 4 continuous values | 2.104 µs/call | 1.704 µs/call | 22.04% | −24.21% to +29.35% |
| Packed guard, 25 continuous values | 3.319 µs/call | 2.734 µs/call | 17.59% | −26.75% to +37.61% |
| Synthetic joint-stage kernel | 78.085 µs/tick | 69.973 µs/tick | 11.30% | −4.86% to +22.78% |

Larger headless session comparisons used eight alternating process pairs per aircraft, 120 warmup and 480 sampled ticks. Default Stik's median paired tick-median reduction was **2.25%**; Avanti's was **0.19%**. Paired fingerprints matched, but timing variation prevents a reliable session-speedup conclusion. These runs omitted scenery collision, rendering, presentation/audio, and OS input. Body-only performance, native evaluation, full application, GPU, and target-hardware 1080p gains remain unmeasured.

### Developer handoff opportunities O1–O6

**Source: [A6, Optimization opportunities][A6].** These IDs are independent of A2's M/R register. Preserve existing correctness fallbacks; source-operation counts alone are not timing results.

| ID | Opportunity and reported evidence | Qualification boundary |
| --- | --- | --- |
| **O1 — Native circuit terrain** | At the audited snapshot, auto circuit policy can enable the Club circuit on detected dedicated GPUs at High/Extreme detail. A nonempty track intentionally prevents native stage admission, so a visual-detail choice can also change physics backend. | Implement/qualify matching composed terrain rather than removing the guard. Cover heights, normals, edges, wheels/hull, mutations, replay and fallback; record selected backend. No measured speedup. |
| **O2 — Native companion admission** | Player selects native before setup; companion sessions retain the low-level reference default. Three companions plus player imply 960 model ticks per simulated second at 240 Hz, before stages/substeps/observers. Pilot decisions every fourth tick do not reduce physics cadence. | Apply the same pre-setup capability rules and fallback; O1's track restriction also applies. Qualify traffic, fleet trajectories/recordings, reset/crash and fallback. Lowering physics cadence is a separate numerical change. No measured speedup. |
| **O3 — Prepared hull reach** | Circuit broadphase rebuilds a hull radius with per-point slices/norms; 26 Stik points imply 6,240 such operations/s, or 24,960 for four aircraft. `HullContact.prepare`/`prepare_geometry` already prepare detached geometry and reach. | Reuse only a conservative bound matching live geometry. Define admission/mutation invalidation and rollback; object identity alone cannot guard in-place edits. Profile actual allocation/tick cost; no measured speedup. |
| **O4 — Shared downwash pre-step air** | Same callback/state/time computes air twice: internally through `_wing_cl`, then for speed. One shared result halves wind queries; exact/refusal comparisons and about 42% spatial-weather callback reduction are reported below. | Keep lag formula and supported dispatch, environmental purity, invalid-data refusal and rollback. No cross-stage Air receipt reuse or whole-application speedup claim. |
| **O5 — Prepared wind station geometry** | Unguarded prototype matches 402 sampled comparisons across three normalized models. Eight noisy paired batches give median `stage_air` cost about 247.53→225.00 µs, seven favoring preparation. | **Not ready:** replacing `station_ys[0]` with NaN makes baseline reject while cached prototype succeeds. Timings exclude required guards/invalidation. Establish immutable validated geometry or supported mutation invalidation; continue sampling state/time/wind/density every stage. |
| **O6 — Shared rotor-stage calculations** | Domain precheck and aerodynamic/main-rotor stage overlap hub airflow, transition and advance-ratio work. One fixed-state diagnostic measures entire precheck at 2.187–2.433 µs/call and entire stage at 145.909–157.040 µs/call. | Component costs, not removable-work totals or candidate savings. Preserve rejection classification, domain/finite checks and replay. Lower priority until a tested stage-local candidate shows useful benefit. |

A6 also screened overlapping `Air.compute` work and repeated scalar/state validation without persuasive timing improvement. Those explorations are neither new defects nor production-ready patches; they do not invalidate A3's separately measured validation-reuse experiment.

### O4 measured downwash pre-step candidate

The active lag path requires a valid model, nonempty envelope, horizontal `downwash_lag_length`, and valid auxiliary index. `_wing_cl` returns a dimensional wing lift-velocity proxy in m/s despite its name. A6's replacement obtains one `air_data(s, sim.time())` result for both `Aero.wing_wake_velocity(...)` and speed, retaining the exact first-order lag update. Spatial Stik weather samples datum, six wing stations, both tails and propulsion: ten wind positions instead of twenty per callback.

Original timings used ten alternating batches of 128 warmed fixed-state calls on a shared Intel Xeon Platinum 8573C with the pinned debug editor. Values are **medians of batch-mean callback costs**, not tick-latency percentiles. Fresh reconstruction results stay separate.

| Workload | Original baseline → candidate | Original reduction | Reconstruction baseline → candidate | Reconstruction pairs favoring candidate |
| --- | --- | --- | --- | --- |
| Legacy steady, queries 2→1 | 77.33594→69.67578 µs | 9.9% | 80.65625→75.26172 µs | 7/10 |
| Spatial eight-mode weather, queries 20→10 | 577.63672→331.13281 µs | 42.7% | 605.01172→350.93359 µs | 9/10; about 42.0% reduction |

All original paired batches favored the candidate. Reported production `_kernel_pre_step` checks include 192 byte-identical outputs, 24 accepted integration steps in each weather mode with matching body/auxiliary/continuous/mode arrays, and four matching refusal/rollback cases: invalid legacy datum, invalid spatial datum, invalid station after a valid datum, and pending weather reset.

The direct helper call bypasses potential `_wing_cl` subclass dispatch. A production change must preserve supported dispatch or explicitly establish its contract. Reuse is limited to the same callback, state, model, density and time. Although the GDScript pre-step is shared across backends, no native extension was loaded; native/reference trajectory and refusal qualification remains open. The report does not measure the callback's fraction of full tick time, so **42% callback savings cannot be reported as 42% tick or FPS savings**.

## 7. Follow-up order and acceptance evidence

This is a reading and triage sequence synthesized from the reports, not a second implementation plan. Existing owners and step IDs remain authoritative in the [track registry](../docs/README.md#tracks-plans-and-step-ids).

| Order | Follow-up | Authoritative home |
| --- | --- | --- |
| 1 | Reconcile each finding against the actual candidate source; verify the UID/CI history, effective-render validation, diagnostic eligibility, and full rendering identity. | [Apple Silicon performance plan](../docs/plans/apple-silicon-performance.md), [CI/tool index](../docs/tools/README.md) |
| 2 | Triage A6's P1 findings: F1 admission/stepping composition, F2 command validity through pause, and F6 tire/brake passivity. Keep each repair independently reviewable. | [Aircraft Workshop](../docs/AIRCRAFT-WORKSHOP.md), [controller plan](../docs/plans/controller-support.md), [RC vehicle plan](../docs/plans/rc-monster-truck.md) |
| 3 | Resolve F3 observer terrain, F4 connected trials, F5 empty-block compatibility, and A4's separate firing-counter defect. Coordinate F1/F4/A4 event interfaces while retaining distinct acceptance cases. | [Glow engines](../docs/GLOW-ENGINES.md), [fuel system](../docs/FUEL-SYSTEM.md), [flight logging](../docs/FLIGHT-LOGGING.md) |
| 4 | Qualify cloud-cache readiness/fallback and graphical lifecycle, then distinguish ground, sky, layered-weather, and combined cases across supported renderers. | [Apple Silicon plan](../docs/plans/apple-silicon-performance.md), [atmosphere tools](../tools/atmosphere/README.md) |
| 5 | Evaluate A6 O4 first within its measured CPU opportunities, then O3 and guarded O5/O6; qualify O1/O2 terrain/admission coverage separately. Compare A3 and M09/M10 independently where physics cost warrants it. | [Kernel boundaries](../docs/STACK.md#boundaries-and-data-flow), [native-kernel research](../research/native-kernel/README.md), [AI companions](../docs/AI-FLIGHT-COMPANIONS.md) |
| 6 | Test M01, M02, and cheap M03 independently; keep M04 separate. Compare half-resolution clouds as a separate A1 proposal. | [Graphics tools](../docs/tools/graphics.md), [optimization priorities](../docs/plans/optimization-priorities.md) |
| 7 | Use capture to select pass-dependency/ground work; evaluate M05–M08 one at a time, then reconstruction/MSAA quality tradeoffs. Retain M11/M12 and R01/R02 at their lower/research priority. | [Apple technical background](../docs/APPLE-SILICON-TECHNICAL-BACKGROUND.md), [graphics tools](../docs/tools/graphics.md) |
| 8 | Qualify native Mac exports, cold/first-use behavior, recovery, and sustained finalists with actual presentation evidence. | [Shared M1 workflow](../docs/tools/macos-m1.md), [Apple Silicon plan](../docs/plans/apple-silicon-performance.md) |

Additional A1 proposals retained in this sequence:

- **Half-resolution sky clouds:** use stock Godot low-resolution sky passes for expensive clouds while retaining full-resolution celestial/horizon detail and reflection/IBL behavior. Quarter subpass pixel count does not imply quarter total frame cost; test sky-heavy and ground-heavy views, single/layered clouds, moving edges, and solar occlusion.
- **Small shader-variant set:** separate meaningful cloud/detail/screen-depth cases only when unused work actually disappears. Prepare variants before flight and inspect compiled output; uniform branches may already optimize well.
- **Footprint-aware detail:** preserve existing distance/derivative guards, smooth transitions, and coverage. A2's R01 rejection limits naive octave-mean substitution; it does not reject carefully validated filtering research.
- **Screen/depth dependencies:** water, glare, and afterimages can cause full-screen copies, resolves, and pass changes. Compare scenes where the relevant material was never created; hiding it may leave persistent renderer flags.
- **Reconstruction/readability:** at 1080p compare fixed Native, Spatial 85%, and Spatial Quality configurations where supported. Include propellers, gear, control surfaces, foliage, smoke, and fast camera motion.
- **Native Mac shader baking:** A1 identifies macOS export and non-headless baking requirements at its snapshot. Enabling a preset alone is insufficient; verify package behavior and cold Home→Fly/first effects through the owning export workflow.
- **Presentation:** after GPU headroom, compare two-image and default three-image swapchain behavior where supported. Process FPS, GPU duration, input response, and on-glass frame intervals are separate measures.

A7's shader work-package sequence is an additional source recommendation, not proof that it outranks A2's candidates on current hardware: recheck baseline/receipts and contact passivity; isolate the zero-contribution sky patch; test direct-analytic and C5b density bounds separately; test the high-octave lattice atlas; compare degree-five/six transmission polynomials with native `exp`; isolate integer/shared-power/pilot-distance changes; then consider the full-scene aircraft crop and native rate-map integration. O4 and guarded O5 retain their existing CPU entries. Larger engine work needs a captured limitation, minimal supported-path prototype and fallback. Native Mac baking/prewarm remains separate release work.

### Rendering acceptance

Record source/engine identity, hardware/OS, renderer, **effective** reconstruction/cache/bake state, MSAA, output/internal dimensions, scene/weather seed, camera, and settings. Qualify **1920×1080 first**, higher resolutions second, and 720p only as fallback evidence, following the [repository policy](../AGENTS.md#display-resolution-priorities).

Check raw modified-consumer quantities and final moving images, maximum/distributional errors, seams, unsupported/mismatched seeds, boundaries, lifecycle, and extreme supported settings. A linear-RGB budget of 0.001 is not a guarantee of invisibility or one display code value; HDR, exposure, tone mapping, bloom, and temporal history can amplify visible differences. Budget combined approximations together.

Use clean matched complete-frame A/B pairs, stable power/thermal conditions, and supported GPU/CPU diagnostics collected separately. Compare median and tail times, memory trend, and visual readability. The reports recommend short alternating pairs before sustained finalists, including three 30-minute runs per role. Retain only reproducible winners, then measure their combination; do not add individual percentage gains.

A7 specifies five alternating short pairs before sustained finalists, with p50/p95/p99/p99.9 intervals, slow-frame counts, cold/transition spikes, simulation-versus-wall progress, resource/peak memory, swap/thermal state and final-five-minute behavior. Record dirty-patch, engine/template/package hashes and unavailable signals explicitly. Window points, drawable pixels and internal pixels are distinct. A property readback does not alone prove GPU feature execution; diagnostic captures and clean acceptance serve different purposes. Its cited p95 ≤18 ms/p99 ≤25 ms screens permit missed 60 Hz refreshes and are not universal display-pacing guarantees. A historical 2/255 still comparison is not a general image tolerance. `step_usec` omits some observers/publication, and CPU/GPU durations overlap rather than simply adding.

For A7 cache work, follow accepted simulation time and use owner generations so stale completions cannot publish. Seed-only raw-noise/hash lattices normally evaluate coverage, lighting and drift live; light-conditioned post-threshold bundles additionally depend on coverage, clustering, shape and ray. Do not rebuild for inputs the cached function does not contain. Cover unready/failed/wrong-seed/stale fallback, more than four seeds, layer removal, rewind, dominant-light changes, headless operation and teardown. A GPU blit replacing readback/upload needs valid sky-sampling and transition evidence so it does not reintroduce the old C5 failure.

### Physics acceptance

A6's defect probes succeed when they reproduce the old failure; a successful reproducer receipt is **not a passing repaired-product regression**. Convert counterexamples to assertions of desired behavior. Its F4 diagnostic is not an independent physical oracle, and O4 remains an experimental comparison.

Preserve float64 state, 240 Hz RK4 semantics, model/kernel boundaries, serial reduction order, accepted-tick transactions, refusal behavior, and rollback. Use component-byte/reference oracles before timing, including clean/flapped/tailless cases, nonuniform winds, zero/reverse flow, malformed inputs, NaNs, signed zero, and events. Follow [flight-log baseline and same-tape comparison](../docs/FLIGHT-LOGGING.md), retaining `complete` and `solver_changed` meanings. An intentional new solver or physics law needs its own scientific/replay contract; software agreement does not establish physical realism.

For A6's performance candidates, retain identical aircraft, track, weather, tape and accepted-tick counts; record each vehicle's selected backend/fallback reason, stage/contact/event counts, mean and p95/p99 tick cost with units, allocations, observer and companion cost. Exercise 0/3 companions, circuit off/on, and airborne/runway/contact phases. The 240 Hz interval is 4.1666667 ms, not a measured processing duration. End-to-end 1080p frame qualification remains separate from headless callback results.

## 8. Tools and platform constraints

These are the reports' recommendations and snapshot-specific constraints. Confirm installed capabilities when executing a future experiment; this consolidation did not recheck external tool versions or availability.

| Need | Retained tool/workflow guidance |
| --- | --- |
| Existing app diagnostics | Reuse [tool index](../docs/tools/README.md), [debug bridge](../tools/debug/README.md), collectors, script profiler, and Perfetto output. A2 points to atmosphere density/relief probes, `shadow_map_probe.gd`, real sky consumers, ground/stripe/grass/seam checks, and supersampled linear-light comparisons. |
| GPU attribution | Xcode captures/counters and Instruments Metal/Game Performance tools; inspect installed templates. Metal HUD and GPU-profiler runs are diagnostics. Newer heat maps/shader tools must not become unavailable M1 prerequisites. |
| CPU and memory | Time Profiler/`sample`, Allocations/VM, and Metal resource views; account for overlapping memory views. Tracy/engine tracing requires an appropriate engine build. |
| Version/hardware-specific tools | A1 associates `gpucapture`/`gpudebug` with macOS 27, shader cost graphs/heat maps with M3+, and Processor Trace with M4+. Its Power Profiler reference covers iPhone/iPad, not a Mac measurement prescription. Verify actual availability. |
| Texture/asset work | Existing Godot compression/mipmap pipeline first; `astcenc`, KTX/Basis, and `meshoptimizer`/`gltfpack` only when evidence supports the bottleneck. Pin versions and preserve aircraft node/hinge names. Cache noise compression/filtering needs separate nonlinear-coverage/relief checks. |
| Engine/platform changes | A1's pinned engine instantiates a Metal 3 driver; Metal 4 and memoryless depth/MSAA changes require engine work, not an assumed project toggle. Check sampling/copy/resolve lifetime before changing attachments. |
| Precision and specialization | `mediump` alone does not prove desired Metal half arithmetic. Inspect generated code; protect coordinates, periodic boundaries, thresholds, HDR, and angular differences. A uniform is not automatically a Metal function constant. Query capabilities/SIMD width instead of hard-coding them. |
| Native CPU optimization | ARM64/Neon, Accelerate/vDSP/vForce, PGO, and ThinLTO are conditional on measured workloads and exactness. The cited `nk::R` implementation targets GCC/x86-64/SSE2; arm64 requires a real port and platform oracles. Keep independent arithmetic separate from ordered reductions. |

A1 warns that `-fno-fast-math` alone may leave FP contraction enabled. A2 warns that some fast double-precision vector functions can offer much less than binary64 accuracy. Neither double storage nor a real-arithmetic identity guarantees byte parity. Preserve effective arithmetic flags and scalar reference behavior instead of enabling global fast math.

A7 reports the pinned rendering driver using `MathModeFast` and SPIRV-Cross MSL ignoring `RelaxedPrecision`; its conditional arithmetic bounds therefore require actual emitted-operation checks. Rendering math policy is separate from simulation's contraction/float64 contract. Its polynomial construction actually used exact-rational Python and a compiled C harness: FPCore/FPBench, Herbie, Sollya and Gappa are researched tools, and Herbie/Sollya/Gappa were not run. The polynomial is Chebyshev truncation, not a Sollya minimax result. `metal-cpp` exposes APIs rather than automatically optimizing Godot; runtime ImageTexture data is not automatically covered by static import compression. Native PGO needs representative training and held-out validation; QoS is not portable named-core pinning. A7 also retains exported-app fullscreen/Game Mode verification, fixed reconstruction presets before dynamic resolution/hysteresis, and the distinction between display interpolation, simulation rate and input latency.

Primary technical references, frozen source URLs, and derivations remain in [A1][A1] and [A2's reference section](mathematical-optimization-lab.md#references), including Apple, Godot, LLVM, Arm, Khronos, and procedural-noise/filtering research.

## 9. Evidence availability and original-file fingerprints

### What is supplied here

This directory contains seven source Markdown files and this consolidated document. The reports reference additional deliverables, but those deliverables are **not included in this directory**. Their reported results are retained as source claims; the raw experiments were not rerun or independently inspected for this consolidation.

| Source | Referenced material outside this Markdown set |
| --- | --- |
| A1 | A linked `OpenRC_Apple_Silicon_Audit_2026-11-05.pdf`, described as 16 pages/55 references; GitHub source/CI and repository campaigns. The PDF's external library link remains in A1; its contents were not available in this folder. |
| A2 | `OpenRC_Mathematical_Optimization_Kit.zip`: portable probes/results under `angular/`, `noise/`, `ground/`, `native/`; uncompiled `sketches/`; `source_manifest.json`; `verification.json`; runner and pinned requirements. A2 §13 gives reproduction instructions for that kit, not for this Markdown-only directory. |
| A3 | `candidate.patch`, derivative/stock-stage probes, three flight recordings, checked-runner receipts, raw component samples, and `session_timing_no_scenery/`. |
| A4 | `audit_glow_fill_fire.gd`, `audit_glow_event_fire.gd`, `audit_propeller_roll.gd`, and checked receipts `glow-fill-fire-final-2b57tyi5`, `glow-event-fire-isolation-eusbtkbz`, `energy-import-cifyj0rq`, `roll-power-final-ubv7kj98`. |
| A5 | `probe_piece_arms.gd`, `probe_stall_selector.gd`, the isolated one-expression diagnostic `aero_sign_probe.gd`, and `checks/piece-arms-*` / `checks/stall-selector-*` receipts. |
| A6 | `OpenRCsimulator-audit-3df2791.zip` (F1–F5, manifests, original/packaged receipts, `run_audit.py`) and `OpenRCsimulator-math-audit-3df2791.zip` (F6 scalar/energy/driving/refinement, traces, O4 `prestep-candidate.patch`, exact/refusal/timing results, O5 exploration and additional controls). Both archives and their extracted directories are absent here; the second is distinct from A2's similarly themed Optimization Kit. |
| A7 | `OpenRC_Apple_Silicon_Experimental_Kit_2026-11-05.zip` (66 entries) and `OpenRC_Mathematical_Optimization_Lab_2026-11-05.zip` (69 entries, manifest covering 68 payload files), plus the original Apple PDF and separate `OpenRCsimulator-math-audit-3df2791.txt`. These are reported artifacts, not supplied here. Neither shader ZIP contains the later CPU harness, and A7's math ZIP is distinct from A2's `OpenRC_Mathematical_Optimization_Kit.zip`. |

### A7 reproducibility and evidence limits

A7 reports checking its recovered mathematical archive against `MANIFEST.json` when assembling that handoff. This consolidation has not received or verified those archives. Its source/reference map is largely plain-text labels in the supplied Markdown; those labels do not grant access to saved artifacts or constitute locally available probes.

| Package | Retained layout and reproduction boundary |
| --- | --- |
| Earlier experimental kit | `bounds_prototype/`, `cloud_prototype/`, `solar_prototype/`, `relief_cache_prototype/`, `crop_projection_prototype/`, `metal_research/`, `verification/`. `run_cpu_screens.py --repo ...` and optional `--only lattice`, `solar`, or `relief-cache`; repository/engine not bundled. Five shader-wrapper front-end checks and separate actual Camera3D-method receipts are reported. |
| A7 mathematical lab | `interval_noise/`, `exp_polynomial/`, `integer_noise/`, `angular_algebra/`, `grass_algebra/`, `exact_support/`, `verification/`, `run_cpu_experiments.py`, `MANIFEST.json`. Python/NumPy plus C11 compiler/libm as `cc` for polynomial screens; some groups require the pinned repository. Commands were checked on Linux, not qualified for macOS. Launcher regenerates retained JSON/logs: use a copy to preserve shipped evidence. |

The mathematical lab reports seven resource checks: original and modified full sky, integer, guarded-parcel, palette, angular and polynomial wrappers, with zero errors/warnings and `OPENRC_MATH_SHADER_LANGUAGE_PASSED`. The later interval experiment is **outside those seven resources**. Dummy-renderer uniform-list/front-end validation is not Metal compilation, actual texture sampling, image parity or GPU timing. The non-mutating patch applicability check belongs to `93ffbb`; rebase rather than blindly applying the patch to current source.

Reported archive SHA-256 values (not recomputed here):

- Experimental kit: `3c80742fec67e43720ebe43716385688506186d5f696432594c268ba30b8bc73`.
- A7 mathematical lab: `7ebb1ea430f1c601596cd94f7a3ce8827a44af30dbe2d6edd508d68234fa516d`.

### A6 reproduction and package limits

The handoff describes wrappers that verify the exact engine and a 654-file application manifest, then create isolated runtimes with reduced project configuration and generated import/UID metadata. The first also copies three Workshop JSON dependencies into the required adjacent-assets layout. The original performance harness separately used 226 matching tracked GDScript files. No native extension was loaded. Relative artifact links in `developer-audit-remediation-2026-11-06.md` require the two extracted archive directories beside it; their instructions do not make those absent files available here.

| Wrapper | Cases and interpretation |
| --- | --- |
| `OpenRCsimulator-audit-3df2791/run_audit.py` | F1–F5 cases: `workshop`, `aux_pause`, `track_statistics`, `glow_timing`, `empty_log`. Repeated `--case` selects cases. `--allow-changed-source` records mismatched names/context, not replacement hashes; retain candidate hashes separately and do not call it exact baseline reproduction. |
| `OpenRCsimulator-math-audit-3df2791/run_audit.py` | `scalar`, `energy`, `truck_drive`, `wind_pair`, `wind_refusal`; optional `truck_refinement` runs 240/480/960 Hz. Generates O4 only inside its isolated runtime, verifies baseline hashes, and has no changed-source override. |

A6 provides full commands using `--repo`, `--godot`, and `--output`; both require fresh output runtimes and the pinned source/engine. Use the original instructions once the packages are available, adapting desired-behavior checks to the owning workflow for repairs. Check completion, `ok`, diagnostics, required markers and source context; receipt `elapsed_seconds` includes process startup/import and is not physics timing.

A6 reports a fresh reconstruction completing import and the five default second-pass cases with zero errors/warnings. First-pass receipts retain existing model warnings and expected calibration-overlap warnings. This consolidation did not inspect those raw receipts or rerun them. The handoff claims no rendered UI, hardware controller, native execution, full suite, full flight envelope, sustained circuit landing, GPU campaign, or independent physical validation.

Failed/aborted attempts are explicitly excluded from accepted evidence: A3's initial component benchmark reused a mutable body-derivative array and failed reset; its full-scenery probe was rejected for missing sparse-checkout textures/GLTF despite Godot exiting zero. A4's initial `roll-power-8_iqjz9_` diagnostic failed on unsupported formatting; the corrected run is separate. A4's isolated import had two unrelated translation warnings and no errors. Do not convert these failed attempts or warnings into accepted timing runs.

### Identity details retained from the reports

- A3 baseline `app/sim/simulation.gd` SHA-256: `56953f116a293a984cbc5315b9cd97dc156e63cdd98c12fbc041e6df6baaab92`.
- A3 candidate SHA-256: `d6fca823652f3f78957517a6efb20898c8acb0b86e3f125d5a8748ff3ecf6255`.
- Godot executable SHA-256 reported by A3/A4: `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`.

### Original-file SHA-256

These hashes were calculated from the supplied files when consolidating. They identify the seven retained source reports, whose content is unchanged by renaming; they do not authenticate the external experiments.

| Source/files | SHA-256 |
| --- | --- |
| A1 — `apple-silicon-performance-audit-2026-11-05.md` | `db9cb4648737dc680459e29d002d7bbc7374c003865e2710cb3f8d04a1b03ea2` |
| A2 — `mathematical-optimization-lab.md` | `f43f138f605096480e74316bd18131b5d2e99e6e185f1b30f9088f224226e60c` |
| A3 — `stage-validation-reuse-experiment.md` | `0ddf88bb146f2f085204f54baa548b0c830260866eec81d0e133ddeb9690906a` |
| A4 — `propulsion-energy-audit-2026-11-06.md` | `de18844f4ebb42c3c12f4fb0a7d4c7d5425e9715979c431f6dca7f06fe89a3fe` |
| A5 — `fixed-wing-aerodynamics-review.md` | `33d19505c21a0c40ec5c7ec6162665d38322c15e10e16f8179b254016281e699` |
| A6 — `developer-audit-remediation-2026-11-06.md` | `dc5adfd6cb64860fa1ec948f002e1ffac47c16c458d875922b403104ee7c7120` |
| A7 — `apple-silicon-metal-optimization-handoff-2026-11-06.md` | `1eb780371898d91a5afec6052be9289fd900101633251ea66919da680c0b8f1b` |

[A1]: apple-silicon-performance-audit-2026-11-05.md
[A2]: mathematical-optimization-lab.md
[A3]: stage-validation-reuse-experiment.md
[A4]: propulsion-energy-audit-2026-11-06.md
[A5]: fixed-wing-aerodynamics-review.md
[A6]: developer-audit-remediation-2026-11-06.md
[A7]: apple-silicon-metal-optimization-handoff-2026-11-06.md
