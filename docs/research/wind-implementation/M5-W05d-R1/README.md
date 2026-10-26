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
| `sim/trace.gd`, `sim/flight_log.gd` | V16 CSV with endpoint and k1 coordinates/times; source-bound ORFL replay; cheap datum-only read-only observer sampling. |
| `render/field.gd`, `main.gd` | Windsocks sample at their own fixed pole head through a read-only world callback. Rendering conversions are isolated from float64 simulation state. |
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

The matched surface pair holds controls, reference downwash, ground effect and other baseline state fixed. Fuselage/global residuals stay in the baseline once. Propeller hub/turbine intake receives its full local relative flow; wash force points query the same stage's ambient field and use matched washed/free evaluations. Wake feedback, wake convection through a general spatial field and per-surface terrain ground effect remain separate work. Gear forces remain ground-relative. No wind impulse, position advection, direct rotation, arbitrary gust moment or air-mass acceleration is added.

Checkpoint v12 wraps the existing propulsion/contact checkpoint version and binds the complete spatial configuration hash, identity, point-flow law, aerodynamic law and clock policy. Restore checks the receipt and preflights saved current/previous body station samples before mutating accepted state. JSON receipt comparisons normalize JSON key/number types without truncating float64 values; unknown fields or altered laws still refuse.

Trace v16 wraps its base trace format, recording k1 datum coordinates in addition to endpoint coordinates, both simulation sample times and both epoch times. The force rows use previous body position and previous stage time, not the current aircraft position at an earlier time. ORFL remains source/config bound and records datum observations only; it does not rebuild a complete aerodynamic receipt just to report airspeed.

## Presets and presentation

Available spatial presets cover a light realistic candidate, steady breeze, runway-dependent crosswind, finite irregular gust training, a smooth shear layer, one balanced thermal cell and strong steady wind. Existing Calm remains exactly zero. All values are authored practice inputs, not site measurements or universal safe RC limits. Ridge/rotor/valley entries state why they are unavailable. Current native controls preserve full-precision untouched values, preserve the thermal block and atmosphere, and clear only legacy wind amplitudes/OU RMS on explicit spatial Apply. Cancel does not mutate the flight or preferences.

Windsocks sample at their own world mast-head position. Global grass/cloud shader uniforms, GPU plume approximations and the current audio interfaces are still presentation approximations; they do not define or modify the physical field. No new art or sound assets were generated for this implementation.

## Verification and qualification

The baseline is detached commit `ac6fb953508bad76b2f12f9690a03ea5b20c014a`. Candidate verification overlays only the owned wind/UI/observer paths onto that baseline. This excludes simultaneous ground/aircraft/lighting changes from the shared working tree. Source/configuration receipts and exact replay comparisons accompany the final verification manifest. Early per-component results are not whole-tree qualification.

Required checks include analytic logarithmic-profile and pulse-area oracles; divergence and thermal flux; wall/top continuity; seed/order/clock identity; full-precision persistence; strict old-law compatibility; zero/stalled/reverse-flow continuity; local-force signs and force ownership; real-fleet starts/short flights; exact checkpoint and ORFL replay; malformed midstage rollback; local windsock coordinates; preset and UI Apply/Cancel/EN/ES behavior. Final measured results are recorded here after the frozen candidate run.

Performance must include every RK stage, distributed surface, propeller and wash query. Provider-only timings exclude aircraft work and cannot qualify 240 Hz flight. The default mode count is an explicit quality/cost choice, not an aircraft-dependent weather adjustment. No 1080p GPU/FPS claim follows from a headless benchmark.

Open acceptance gates: measured turbulence covariance/spectrum against a pinned independent reference; longer maneuver and timestep-refinement campaigns; human trainer/aerobatic/warbird handling; a sourced glider/lightweight fixture; spatial wake feedback; terrain/obstacle boundary infrastructure; atmosphere/heating data; shared companion world-clock and route qualification; target-hardware 1080p performance. These are not marked complete by software unit tests.

## Technical references

- [Luers, NASA-CR-2288](https://ntrs.nasa.gov/citations/19730018294): boundary-layer profile assumptions and roughness; the wall regularization here is an explicit implementation approximation.
- [Fung et al., 1992](https://doi.org/10.1017/S0022112092001423): kinematic simulation from finite incompressible modes; the current equal-variance band is not a claim to reproduce their spectra.
- [NASA Dryden verification, 20190000875](https://ntrs.nasa.gov/citations/20190000875): future independent trajectory-spectrum validation and units/conventions, not a shared 3D backend implemented here.
- [Allen, updraft model, 20060004052](https://ntrs.nasa.gov/citations/20060004052) and [20060024599](https://ntrs.nasa.gov/citations/20060024599): thermal dimensions, drift, lifetimes and compensating sink as research context; the present streamfunction is separately specified above.
- [FAA Glider Flying Handbook](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/glider_handbook): qualitative soaring and terrain behavior for future scenario validation.
