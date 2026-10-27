# M5-W05d-R1 — explicit spatial weather admission

2026-10-25. Software implementation evidence; atmospheric, aerodynamic and pilot qualification remain separate. This slice also implements the bounded kinematic-thermal component of M5-W08a-R1. [Current wind contract](../../../WIND-PLAN.md) · [advanced design](../../../advanced-wind-atmospheric-physics-masterplan.md) · [preceding powered-stage contract](../M5-W05c-R2/README.md).

## Scope and decisions

Weather `openrc-weather v5` selects a pure spatial provider and the explicit point-flow aerodynamic law. V1–v4 keep their old numerical paths, defaults and recordings. No aircraft data, kernel equations, empirical coefficients or golden flights are changed by this slice. Spatial presets are experimental choices; the interactive gentle-practice default and technical calm default remain available unchanged. Helicopter and companion admission refuses v5 pending their own qualification.

The reference field is a finite **flat-site** approximation with ground at NED `D=0`. Existing rendered hills, lake banks and ground-contact microrelief do not become aerodynamic terrain. The service does not claim local terrain AGL, ridge lift, terrain rotor, valley channeling, building wakes, buoyancy prediction, measured turbulence spectra, dynamic stall or a solved spatial propeller wake. Those labels cannot be enabled through an unsupported preset.

The original R1 attached-flow correction is retained for explicit callers. Production v5 selects a separately named continuous section surrogate, `matched-unwashed-full-angle-section-delta-v1`. This choice is necessary because a normal runway start, stall, gust or aerobatic transition crosses the narrow R1 admissible domain. Dropping the correction or switching laws at that boundary would cause a discontinuity. The continuation reuses the existing section/tail/polar angle laws and adds the paired local-flow difference to the old complete-aircraft baseline; it is not a new measured coefficient database. Finite numerical guards are refusal bounds, not aircraft operating envelopes.

## Source and contract map

| Area | Implementation and ownership |
| --- | --- |
| `physics/wind_spatial_config.gd` | Strict complete nested v1/v2 schema, detached canonical data, float64 values, exact sorted full-precision JSON hash. V2 contains a complete thermal field. |
| `physics/wind_spatial_field.gd` | Reference profile, resolved gust agenda, divergence-free finite-mode perturbation, optional thermal composition, declared finite domain, pure samples. |
| `physics/wind_thermal_field.gd` | Explicit finite-lifetime drifting cells with a compensated streamfunction circulation. |
| `physics/wind_config.gd`, `wind_field.gd` | V5 admission and preset lookup; legacy amplitudes and OU RMS must be zero so the spatial provider owns the complete wind. Positionless queries refuse spatial fields. |
| `physics/wind_aircraft_flow.gd`, `aero.gd`, `dynamics.gd` | Complete stage Air receipt; actual station positions; one `omega × r`; explicit continuous section difference and existing local powered/wash consumers. |
| `physics/ground_start.gd`, `sim/flight_session.gd` | Fresh Air receipt for every runway residual candidate; stage-position/time sampling; launch and replay identity; transactional invalid-domain refusal. |
| `physics/retractable_gear.gd` | Optional ambient increment at the deployed gear's drag center, supplied by both flight stages and runway residuals; the existing rotational term remains applied once. |
| `sim/trace.gd`, `sim/flight_log.gd` | V16 CSV with endpoint and k1 coordinates/times; source-bound ORFL replay; cheap datum-only read-only observer sampling. |
| `render/field.gd`, `main.gd` | Windsocks sample at their own fixed pole head through a read-only world callback. HUD, lighting and smoke use cheap datum Air observations rather than building surface receipts. Rendering conversions are isolated from float64 simulation state. |
| `ui/weather_dialog.gd`, `spatial_weather_controls.gd`, `ui/home.gd` | Preset selection, independent draft, progressive advanced controls, explicit limits, Apply/Cancel, atmosphere preservation, Home summary. |
| `app_state/preferences.gd` | V5 weather writes settings schema 6; older settings retain their schema path and future settings remain protected. |

## Governing field

Inputs are float64 NED position `[N,E,D]` in metres and nonnegative simulation seconds. Output is NED air-transport velocity in m/s. `t_epoch = t_sim + epoch_offset_s`; reset deliberately reuses the same epoch and seed. A different realization requires an explicit new identity/configuration. Sampling never draws random numbers or mutates the clock. Identical configuration, position and epoch produce identical samples independently of query ordering or aircraft identity on the pinned runtime.

The nested v1 identity includes uint32 seed, uint32 epoch ID, offset seconds and `xorshift32-v1`. The generator resolves finite modes during construction only. V2 requires exact agreement between outer and thermal epoch, datum, horizontal extents, maximum height and horizon. The complete configuration hash includes the thermal law and agenda, not just its seed. Returned configurations are detached copies.

For the neutral surface layer, with roughness `z0`, displacement `d`, height `z=-D` and reference height `zr`:

```text
U(z) = Uref ln((z-d)/z0) / ln((zr-d)/z0)
Wmean = [-U cos(theta_FROM), -U sin(theta_FROM), 0]
```

The declared wall join uses a cubic Hermite connection with zero velocity and zero slope at the flat wall, matching the logarithmic value and slope above it. This is a regularized kinematic wall approximation, not a viscous sublayer solution. A smooth transition joins a declared horizontal free-air vector above the surface layer. Nonoverlapping finite-height layers add horizontal C2 bumps; they cannot overlap the reference height. Mean/layer/free-air vertical components are forbidden by this law. Horizontal velocity depending only on height has zero divergence.

Gusts are explicit sorted finite events, with independent horizontal amplitude vectors. For `s=(t_epoch-start)/duration` inside `[0,1]`:

```text
b(s) = 64 s³ (1-s)³
Wgust = amplitude * b(s) * smooth5(z / ground_transition_height)
integral_0^1 b(s) ds = 16/35
```

Value, first and second time derivatives vanish at both ends. Events do not repeat implicitly or draw RNG on a query. The mean profile remains after the agenda ends, until the declared provider horizon. Maximum agenda size, overlap and summed amplitudes are validated. A finite positive gust agenda has a positive time integral; the displayed reference mean is the background, not the total time-average realization.

Turbulence is the analytic curl of a horizontal vector potential. Each mode uses a horizontal phase, a sinusoidal vertical factor and a C2 wall taper. The derivative of that taper is included analytically; tapering final velocity alone would violate divergence. Phases advect with the reference horizontal wind and have an intrinsic time frequency, so calm air can still vary. Wavelengths are stratified logarithmically; modes carry equal nominal variance. This is **not Dryden or von Kármán**, nor a validated inertial-range spectrum. Input `rms_mps` is nominal: finite phases, anisotropy, wall taper and position change the realized covariance. Do not label it measured local RMS.

The complete field is `Wmean + Wlayers + Wgust + Wcurl + Wthermal`, added once before aerodynamic relative velocity is computed. No total-vector clipping silently changes the model. Each provider refuses malformed or outside-domain samples; the simulation transaction rejects the stage and preserves the preceding accepted state. A small declared zero-wind extension inside the flat ground prevents a discontinuity at the wall. The UI exposes the finite altitude/time domain; this is not an unbounded global atmosphere.

## Balanced thermal circulation

Each cell has a fixed radius `R`, top height `H`, signed peak vertical speed, birth, duration, initial center and constant horizontal drift. Its center moves by `drift*(t_epoch-birth)` during its lifetime. With radius `r` about that center:

```text
A(t) = 64 s³(1-s)³                        # finite C2 lifetime
w(z) = w_peak sin²(pi z/H)                # 0 < z < H
Psi(r,z,t) = 0.5 A(t) w(z) r² exp(-r²/R²) taper(r)
u_r = -(1/r) partial(Psi)/partial(z)
w_up = (1/r) partial(Psi)/partial(r)
W_D = -w_up
```

The radial taper is one to `4R`, falls smoothly to zero at `5R`, and has its derivative included in the vertical velocity. The on-axis limit is evaluated analytically. The updraft has a sinking annulus and horizontal inflow/outflow; the flux through the complete support is zero, because `2*pi*(Psi_outer-Psi_axis)=0`. No uniform additional sink or lift bonus is applied. Both vertical velocity and radial circulation vanish at the floor and top. Signed negative strength describes a descending circulation; it is not a validated microburst model.

This is an authored divergence-free kinematic closure, not NASA Allen's measured model and not a thermal-convection solver. Surface heat flux, moisture, stability, cloud cover and solar forcing are deliberately not inferred from visual lighting. The shipped thermal practice cell is finite and prescribed. There is no dedicated validated sailplane in the current catalog; engine-off powered-aircraft checks cannot establish glider handling qualification.

## Aircraft interaction and persistence

For stage datum `O`, body attitude `R`, body rate `omega` and station arm `r_i`:

```text
x_i = x_O + R r_i
v_air_i = v_ground_body + omega × r_i - R^T W(x_i,t_stage)
delta_i = R^T [W(x_O,t_stage) - W(x_i,t_stage)]
loads = existing_complete_baseline + [raw_surface(local+delta) - raw_surface(local)]
```

The matched surface pair holds controls, reference downwash, ground effect and other baseline state fixed. Fuselage/global residuals stay in the baseline once. Propeller hub/turbine intake receives its full local relative flow; wash force points query the same stage's ambient field and use matched washed/free evaluations. Wake feedback, wake convection through a general spatial field and per-surface terrain ground effect remain separate work. Wheel contact and friction remain ground-relative; deployed retractable-gear aerodynamic drag uses local air velocity at its own drag center, followed by its one existing rotational term. No wind impulse, position advection, direct rotation, arbitrary gust moment or air-mass acceleration is added.

Checkpoint v12 wraps the existing propulsion/contact checkpoint version and binds the complete spatial configuration hash, identity, point-flow law, aerodynamic law and clock policy. Restore checks the receipt and preflights saved current/previous body station samples before mutating accepted state. JSON receipt comparisons normalize JSON key/number types without truncating float64 values; unknown fields or altered laws still refuse.

Trace v16 wraps its base trace format, recording k1 datum coordinates in addition to endpoint coordinates, both simulation sample times and both epoch times. The force rows use previous body position and previous stage time, not the current aircraft position at an earlier time. ORFL remains source/config bound and records datum observations only; it does not rebuild a complete aerodynamic receipt just to report airspeed.

## Presets and presentation

Available spatial presets cover a light realistic candidate, steady breeze, runway-dependent crosswind, finite irregular gust training, a smooth shear layer, one balanced thermal cell and strong steady wind. Existing Calm remains exactly zero. All values are authored practice inputs, not site measurements or universal safe RC limits. Ridge/rotor/valley entries state why they are unavailable. Current native controls preserve full-precision untouched values, preserve the thermal block and atmosphere, and clear only legacy wind amplitudes/OU RMS on explicit spatial Apply. Cancel does not mutate the flight or preferences.

| Preset ID | Reference mean at 10 m | Additional components |
| --- | --- | --- |
| `spatial-realistic-v1` | 1.5 m/s FROM 075° | 0.08 m/s nominal turbulence; 24 authored gusts at 20% of the gusty agenda amplitude |
| `spatial-light-breeze-v1` | 2.5 m/s FROM 090° | Surface gradient only |
| `spatial-crosswind-v1` | 5 m/s FROM 000° | Surface gradient; crosswind is relative to runway heading |
| `spatial-gusty-v1` | 3 m/s FROM 090° | 24 gusts, 1.3–2.2 m/s peak increments, 3–5 s duration, last event ends at 1797 s |
| `spatial-shear-v1` | 3 m/s FROM 090° | C2 layer centered at 42 m, half-thickness 8 m, peak NED increment `[-0.7,0.35,0]` m/s |
| `spatial-thermal-soaring-v2` | 1.5 m/s FROM 090° | Cell born at 15 s, lifetime 360 s, radius 35 m, top 200 m, peak upward speed 1.2 m/s; initial center `[220,-120]` m |
| `spatial-strong-wind-v1` | 8 m/s FROM 090° | Surface gradient only |

These presets share `z0=0.03 m`, a 0.3 m wall join, surface-layer top 80 m plus a 20 m free-air join, flat ground at D=0, 200 m maximum height, 10 km horizontal half-extents and a 86400 s horizon. Their free-air vector matches the log profile at 100 m. The thermal drifts with that vector, its mid-height background. The default mode set is 24 modes between 5 and 50 m wavelength, with 4 s intrinsic coherence time; only the realistic preset enables nonzero turbulence. Other presets can be edited explicitly. The full finite gust agenda is authoritative in `wind_spatial_presets.gd`; it does not repeat after 30 minutes. Thermal activity is not enabled automatically by the realistic preset or the visual time of day.

Windsocks sample at their own world mast-head position. Global grass/cloud shader uniforms, GPU plume approximations and the current audio interfaces are still presentation approximations; they do not define or modify the physical field. No new art or sound assets were generated for this implementation.

## Verification and qualification

[Verification manifest](verification.json) · [candidate source identity](candidate-manifest.json) · [baseline identity](baseline-manifest.json) · [six candidate comparisons](flights/candidate-summary.json) · [presentation preparation receipt](presentation-regeneration.json) · [rendered UI review](ui-review.json).

All 44 selected regression scripts pass on the isolated candidate after the documented corrections: the original 42-script set plus engine-smoke and lighting-flight integration checks after the final observer correction. The final spatial UI script has 64 checks; world-consumer tests have 14. The existing localization audit also passes after manually translated controls stopped advertising automatic translation. The displayed first-gust magnitude is rounded for readability while untouched source values remain exact, and the two preset selectors match after full-precision JSON restoration. All 1376 GDScript files pass the checked per-script parse gate, with the two later observer edits rechecked separately. [Parse receipts](parse-checks.json). These checks cover the affected wind, atmosphere, starts, force, persistence, observer and UI paths; they are not a claim that the entire `app/test.sh` suite ran.

The baseline is detached commit `ac6fb953508bad76b2f12f9690a03ea5b20c014a`, solver fingerprint `8e955fb0770148a3f077ee7109a4a908e454ce616d5cef9ea52818ddba7b96f9`. The final candidate solver is `cba4552d2749e19ace9483de73a6114adb7beb15ce7e70922b05a2a02fe27904`. Verification overlays only the owned wind/UI/observer paths onto that baseline, plus the generated presentation preparation described below. This excludes simultaneous ground/aircraft/lighting source changes from the shared working tree. The retained manifests identify exact source bytes; early per-component results are not whole-tree qualification.

Checks cover analytic logarithmic-profile and pulse-area oracles; divergence and thermal flux; wall/top continuity; seed/order/clock identity; full-precision persistence; strict old-law compatibility; zero/stalled/reverse-flow continuity; local-force signs and force ownership; real-fleet starts/short flights; exact checkpoint and ORFL replay; malformed midstage rollback; local windsock coordinates; preset and UI Apply/Cancel/EN/ES behavior. The final verification manifest records each script separately, including superseded failures and their resolution.

The field test has 154 checks, including 48 exact pre-optimization float64 sample-byte fixtures across four configurations (8, 24 and 64 modes plus thermal v2), four positions and three times. Thermal-field tests have 57 checks; continuation tests 91; local gear drag 8; runway point-flow tests 15; integrated spatial-session tests 91; trace/ORFL tests 351; thermal aircraft-response tests 33. The fleet start/session tests cover ten existing fixed-wing configurations for short software smoke flights; this is not a handling campaign.

The sample-byte fixture was captured on Windows. On 2026-10-27 the Linux build of the same pinned engine (Ubuntu 24.04 glibc 2.39 under WSL2, and the ubuntu-24.04 CI image) produced different bytes for three of the 48 samples. All three are the north component of the 24-mode case at `D=-0.0001` m, with a magnitude of about 1e-14 m/s. The frozen pre-packed sources were reconstructed with [`fixture-capture/reconstruct_preopt.sh`](fixture-capture/reconstruct_preopt.sh). This uses the field from `4c1513949`, the parent of the packing commit, plus this folder's config, thermal and test sources. On Windows, the reconstruction reproduces all 48 original samples. On Linux, it matches the current packed code on all 48 samples and both config hashes. The optimization therefore preserves behaviour on each platform; only the platform's libm rounding differs. [`merge_os_capture.py`](fixture-capture/merge_os_capture.py) recorded the Linux capture as `wind_bytes_hex_by_os.Linux` (fixture format v2, provenance in `os_captures`). The test selects bytes by `OS.get_name()`, compares them exactly and fails on an OS that has no capture. Sample identity is therefore per pinned runtime and OS, not across operating systems.

Six preserved old-law ORFL tapes first replayed exactly on the baseline, with `complete=true`, `solver_changed=false`. They then ran on the final candidate using the identical aircraft data and recorded command tapes, with `complete=true`, `solver_changed=true`. Each has 261 rows (1.0833 s); all CSV values, including the 62–89 columns appropriate to each aircraft, are identical. Candidate mode is still an open-loop solver comparison, not an exact-source replay. No golden flights were re-recorded. The new spatial trace test separately verifies 60 exact replay ticks on the matching spatial source.

The thermal response experiment uses the same engine-off body and command tape at the center of a prescribed 1.2 m/s cell at 100 m, compared with an otherwise identical empty thermal agenda. Initial upward aerodynamic-force increments are 25.25498 N for Jensen and 16.35016 N for Turbo Lumber; after one second their height differences are +0.59884 m and +0.39194 m respectively. These signs arise through local airflow and the existing force integrator. They are software behavior observations, not measured lift validation. A separate half-second 240/480/960 Hz comparison reduces the maximum raw body-component difference from 0.00124144 to 0.00061946; this mixed-unit metric demonstrates decreasing difference only, approximately first-order overall, not fourth-order convergence of the complete split system.

The baseline already contained stale presentation source pins. Both worktrees had the same four mismatches; LF normalization was not the cause. The candidate alone ran the existing `build_models.py`, `build_customization.py` and `build_descriptors.py` generators, followed by their successful `--check` commands. Seven generated visual/Workshop files changed; no physics aircraft data changed. The customization generator also emits its baseline-defined v4 bindings with empty lighting layouts. The retained regeneration receipt lists every changed file and hash. This preparation is separate from the wind implementation; it resolved the initial UI/startup blockers without bypassing manifest validation or overwriting parallel presentation work.

At 1920×1080, the real rendered debug-bridge session verified spatial selection, advanced scrolling, Apply/Cancel and EN/ES Home summaries. Jensen startup succeeded; two paused 240-tick steps advanced exactly 2.0 simulated seconds with no crash or fault, on the runway at zero throttle. This is startup evidence, not an airborne gust-response or FPS measurement. The session exited with no leaked objects. Captures remain under ignored `tmp/`; no images were added to the repository. Spanish tabs retain their existing horizontal scrolling behavior.

To reproduce source-bound checks, start from the baseline commit, overlay `candidate-source/` at the repository root and then `verification-generated/` for presentation-dependent checks. Import with the pinned engine before running the commands retained in the check reports. `candidate-manifest.json` lists every physics/simulation/failure source hash, the owned overlay hashes and the generated verification overlay. Recordings retain their aircraft input, baseline/export/exact reports, candidate reports and both CSVs. Byte-preserving attributes protect their fingerprints on checkout; [fresh evidence-only clones](checkout-verification.json) verify payload bytes with both `core.autocrlf=true` and `false`, without touching the shared repository's index. The shared root continued receiving unrelated work; at retention its extra aircraft-lighting Spanish strings and player-lighting priority grant were deliberately excluded from the isolated overlay.

### Performance

Performance must include every RK stage, distributed surface, propeller and wash query. Provider-only timings exclude aircraft work and cannot qualify 240 Hz flight. The default mode count is an explicit quality/cost choice, not an aircraft-dependent weather adjustment. The final presentation-only correction makes each HUD/lighting/smoke Air observation one datum wind query plus one density query, with no stage receipt; an analytic position/time/density oracle verifies the values and unchanged input state. It does not change the solver fingerprint or the full-session benchmark workload, and it is not a new measured frame-time result. No 1080p GPU/FPS claim follows from a headless benchmark.

The full-session benchmark runs three batches per case, each with 240 warmup and 480 timed accepted ticks. Each case passes eight reset checks, advances every requested tick without fault/crash, and produces identical final-state hashes across batches. Untimed query counts are 60/tick for spatial Jensen/Turbo and 98/tick for spatial Extra, versus 6/6/7 for their legacy paths. Timings are medians of **batch-average** tick costs, not per-tick p95 latency. The host is an AMD Ryzen 9 5900X (24 logical CPUs), pinned Godot `4.8.beta1.official.4d10419ca`. Runs were sequential; OS background load was not sampled.

| Aircraft | Legacy v4 µs/tick | Spatial, 8 modes | Spatial, 24 modes | 24-mode share of 4166.67 µs tick |
| --- | ---: | ---: | ---: | ---: |
| Jensen | 563.710 | 2923.690 | 3887.408 | 93.3% |
| Extra 300S | 2241.552 | 5778.171 | 7029.010 | 168.7% |
| Turbo Lumber | 862.819 | 3350.700 | 4127.798 | 99.1% |

Packing immutable mode scalars into float64 storage preserves all recorded samples exactly. The earlier complete 24-mode cases measured 4788.638 µs for Jensen and 11821.821 µs for Extra; the later observations are about 19% and 41% lower, but host/batch variation prevents treating this as a controlled universal speedup. Extra's final 24-mode batch means span 6936.7–8461.9 µs. The earlier 64-mode matrix was incomplete and is retained only as partial evidence. A first benchmark-harness conversion error and an incorrect script-URL launch produced no valid timing observations and are excluded.

**Performance gate remains open.** Even eight modes exceed the whole 240 Hz tick budget on Extra. Jensen/Turbo 24-mode costs leave insufficient room for other work; none establishes the repository's stricter physics budget or target-device 1080p qualification. Keep the existing default and experimental opt-in status. Next optimize measured repeated geometry/validation and identical within-stage queries, with exact sample/load parity, before considering an SF-approved native evaluator. Do not reduce weather intensity based on aircraft identity, omit surfaces or lower physics frequency to hide this cost.

The bounded source review identifies these follow-ups; none is counted as an implemented optimization or assumed speedup:

| Priority and affected code | Safe change and dependency | Required proof |
| --- | --- | --- |
| First: `FlightSession._wash_derivative` | Reuse its first Air receipt for the later retractable-gear branch at the same state/time instead of rebuilding it. The branch must actually be active in the measured aircraft. | One fewer complete receipt, ten fewer provider queries per applicable invocation, unchanged gear query, derivative/load/state bytes; repeat full-session timings. |
| Profile next: `WindAircraftFlow.geometry`, `sample`, `stage_air` | Prepare immutable geometry only against the installed normalized model's exact dependency values. Model dictionaries are mutable, so aircraft ID/object identity is insufficient. Invalidate on model/geometry change. Dynamic fuel CG currently changes moments later, not this fixed-datum geometry. | Geometry and all load bytes match across replacement and mutations of `cg_le`, wing reference/span/stations, tail positions and propulsion kind/offset. No provider-query reduction is implied. |
| Conditional: `StagePointSampler.delta_at` | Cache only measured repeated exact arm bytes inside one receipt; never across stages/ticks. Seed from existing station results only if matching arms are proved. Return detached results. | Count actual hits first; check repeated and near-but-distinct arms, order independence and invalid-domain behavior. Slipstream/swirl points are generally distinct. |
| Profile next: internal production sampling | Avoid diagnostic position/wind/all-relative-flow arrays where only Air, station deltas and hub flow are consumed; preserve the public diagnostic `sample()` result. | Complete Air, loads and accepted-state byte parity; measured allocation/function costs. Query count alone does not establish a gain. |

A function-level breakdown has not been measured. The optimization sequence must follow those measurements; do not turn a cache proposal into a new backend or silently change the public physics contract.

Open acceptance gates: measured turbulence covariance/spectrum against a pinned independent reference; longer maneuver and timestep-refinement campaigns; human trainer/aerobatic/warbird handling; a sourced glider/lightweight fixture; spatial wake feedback; terrain/obstacle boundary infrastructure; atmosphere/heating data; shared companion world-clock and route qualification; target-hardware 1080p performance. These are not marked complete by software unit tests.

## Technical references

- [Luers, NASA-CR-2288](https://ntrs.nasa.gov/citations/19730018294): boundary-layer profile assumptions and roughness; the wall regularization here is an explicit implementation approximation.
- [Fung et al., 1992](https://doi.org/10.1017/S0022112092001423): kinematic simulation from finite incompressible modes; the current equal-variance band is not a claim to reproduce their spectra.
- [NASA Dryden verification, 20190000875](https://ntrs.nasa.gov/citations/20190000875): future independent trajectory-spectrum validation and units/conventions, not a shared 3D backend implemented here.
- [Allen, updraft model, 20060004052](https://ntrs.nasa.gov/citations/20060004052) and [20060024599](https://ntrs.nasa.gov/citations/20060024599): thermal dimensions, drift, lifetimes and compensating sink as research context; the present streamfunction is separately specified above.
- [FAA Glider Flying Handbook](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/glider_handbook): qualitative soaring and terrain behavior for future scenario validation.
