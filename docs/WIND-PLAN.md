# Wind, gusts and turbulence

2026-10-25 · Revision 8 · Step prefix: **M5-W**.

**Status:** Legacy uniform wind, repeating cosine gusts and seeded temporal OU turbulence remain supported. Weather v3 adds custom field-level atmosphere; v4 adds the dry reference altitude column. Opt-in v5 adds a flat-site spatial field, resolved smooth gusts, divergence-free finite-mode perturbations and optional balanced kinematic thermals, consumed through local aerodynamic/propulsion stages. See [atmosphere](ATMOSPHERE-PLAN.md), the [advanced masterplan](advanced-wind-atmospheric-physics-masterplan.md) and [spatial implementation, equations and evidence](research/wind-implementation/M5-W05d-R1/README.md). Owner flight gates W-A/W-B, physical/spectral acceptance, terrain and shared companion qualification remain open.

Owns `app/physics/wind_*.gd`, wind session/trace integration, weather controls, wind tests and `research/wind/`. Coordinate UI, simulation and visual hooks with their owners. The interactive default is the authored `gentle-practice` profile: 1.5 m/s from 090°, 0.6 m/s horizontal and 0.15 m/s upward gust peaks, turbulence RMS [0.15, 0.15, 0.08] m/s, 3 s correlation time, 14 s gust period and 3 s delay. These are estimated practice conditions, not measured site weather.

## Implemented contract

Each session owns a versioned NED air-velocity provider, with no aircraft-specific wind multiplier. Legacy v1–v4 remains spatially uniform. V5 evaluates one deterministic field at actual aerodynamic station positions and RK stage times. Air-relative velocity feeds aero, propeller inflow, shaft loads and matched wash consumers. There is no extra wind force, position advection, or invented `-dW/dt` acceleration. Wheel contact and friction remain ground-relative. Companions retain their legacy OU behavior and refuse v5 until the shared-world clock and circuit qualification work.

```text
v_air_body = v_ground_body - R(q)^T W(t)
TAS = |v_air_body|
qbar = 0.5 rho TAS²
position_dot_NED = R(q) v_ground_body
```

Airborne reset trims to the selected air-relative speed and adds `R^T W(0)` to ground velocity; it does not continuously cancel disturbances. The runway solver includes wind and refuses an unsupported start. RK stages sample the field at their actual simulation times. Queries are pure; turbulence advances only on a committed tick, pause stops it, and rollback restores the filter window and RNG.

`WindField.sample_world(position_ned, time_s)` and `Environment.wind_world(position_ned, time_s)` accept finite float64 `[north, east, down]` metres and nonnegative simulation seconds, returning float64 NED m/s. The environment adds the existing owner-sampled turbulence once; invalid samples return three NaNs so the existing physics transaction refuses them. `Environment.air_world(position_ned)` returns the existing atmosphere dictionary with `ok`/`errors`. Fixed-wing `wind_at(time_s, state)` and the helicopter adapter use the supplied body's datum position; their one-argument form uses the accepted endpoint for observers. Multirotor research stages use their supplied body position. No query advances RNG. The legacy `sample(time_s)`/`wind(time_s)` APIs remain unchanged.

The airborne reset uses its launch position and datum moving-air trim; it does not trim away spatial disturbances. Spatial runway equilibrium receives a fresh point-Air receipt for every residual candidate. Legacy runway starts retain their one-vector path. The provider remains a scalar-query interface; it is not yet the proposed optimized packed batch API.

`WindAircraftFlow.sample(state, model, environment, time_s)` builds a detached float64 bundle at the six wing stations, both tails and optional propeller hub/turbine intake. It samples one stage time, retains the authored datum O and returns world samples, local relative flows and ambient-only increments `R^T(W_O-W_i)`. Local flows contain `omega × r` once. `Aero.ambient_spatial_loads` accepts only the wing/tail increments and adds a matched raw-surface difference to the unchanged `Aero.loads` baseline. Both passes hold reference wake, controls, ground effect and body state fixed; body residuals remain in the baseline once. Zero increments bypass all extra load arithmetic in every legacy regime.

Nonzero increments require attached forward local flow in both passes, station changes no larger than 3° in physical alpha/beta and 25% in section-plane dynamic pressure, and the existing sideslip/tail/polar eligibility limits. These are provisional refusal bounds, not clamps or measured aircraft limits. [Surface API, equations and verification](research/wind-implementation/M5-W05c-R1/README.md).

M5-W05c-R2 adds `WindAircraftFlow.stage_air` and consuming routes through `Dynamics`, propulsion, glow, wash transport and session stage evaluators. Its complete ephemeral Air receipt supplies full hub/intake relative velocity, ambient-only wing/tail increments and a held-time sampler at actual wash force points. Rotation enters each local calculation once; washed/free pairs share one ambient sample. The Air receipt retains its sampler owner explicitly. Incomplete/stale body or density receipts refuse; callers must also construct a fresh receipt for each model and stage time. [R2 contract and evidence](research/wind-implementation/M5-W05c-R2/README.md). M5-W05d-R1 selects that receipt only for explicit v5 weather, using a separately identified full-angle section-delta continuation. The original narrow R1 law remains available unchanged.

The explicit point-inflow law remains selected even in uniform air. Some legacy shaft/RPM paths omit hub rotation, so their new explicit-law result may intentionally differ at nonzero body rates. This is separate from the preserved old no-key path; do not switch laws when a gradient happens to vanish. Spatial persistence/identity, candidate-position starts and local observers are now implemented; the full-angle aerodynamic continuation remains an empirical surrogate requiring physical qualification.

Wind-only profiles use `openrc-weather v1`; v2 adds turbulence and v3 adds atmosphere inputs. The v3 custom mode calculates one uniform field-level moist-air density and dry-air charge ratio from elevation, temperature, QNH and humidity. Reference mode preserves literal `rho = 1.225 kg/m³` and charge ratio 1.0. Weather v4 `standard_column` evaluates dry ISA at geometric altitude `field_elevation_m - NED_down` at each fixed-wing stage, within −500…11000 m; this is not AGL or density altitude. Reference/custom modes remain uniform. Rotorcraft still refuses the column until qualified. Aero/propeller use total density; the naturally aspirated shaft model uses dry-air charge, while other propulsion families retain their own laws.

Wind configuration values are complete, SI inputs: mean speed 0–15 m/s, meteorological direction **from** north clockwise (0–360°), horizontal gust 0–8 m/s, vertical gust −8–8 m/s with positive up, pulse duration 0.5–20 s, period 0.5–120 s and delay 0–3600 s. Period must be at least the duration; 360° canonicalizes to 0°. The technical/default-constructor route is calm, with dormant 4 s pulse, 12 s period and 2 s delay values; the interactive default is `gentle-practice` as specified above. Turbulence adds three NED RMS values (0–3 m/s each), correlation time 0.2–30 s and a uint32 seed. Atmosphere ranges and equations are in [M5-ATM](ATMOSPHERE-PLAN.md). Invalid types, nonfinite values, unknown fields and out-of-range input fail validation; untouched float64 values are retained.

For elapsed time `e = t − delay`, the gust is zero outside the pulse and `0.5(1 − cos(2π phase/duration))` inside it, where `phase = e mod period`. It starts and ends at zero, peaks at half-duration and integrates to amplitude × duration/2 per pulse.

The OU update is `x_next = a*x + sigma*sqrt(1-a²)*normal53`, `a = exp(−dt/tau)`, at 240 Hz. A pinned private PCG32 and float64 normal transform make reset/replay deterministic on the pinned runtime. The held endpoint interval is interpolated for RK stages; interior variance is slightly lower than tick-boundary RMS. This is a temporal practice approximation, not Dryden, a spatial spectrum or a measured turbulence model.

## Recording and evidence

V5 nests `openrc-spatial-wind v1` or v2 (with `openrc-thermal-field v1`). It requires zero legacy mean/gust/OU amplitudes. Its identity binds the complete full-precision configuration, seed, epoch, flat datum, finite domain and explicit laws. Surface shear, gusts and layers are horizontal; vertical velocity comes from divergence-free perturbations/thermal circulation. Reset reuses the epoch. Invalid samples refuse the physics transaction. [Detailed equations, domains and limitations](research/wind-implementation/M5-W05d-R1/README.md).

Spatial checkpoint v12 wraps the prior propulsion/contact checkpoint. CSV v16 retains the base trace identity and adds k1 positions plus endpoint/k1 epoch times. ORFL exact replay remains source-bound. UI preferences use schema 6 for v5; a separate native draft preserves Apply/Cancel behavior and atmosphere. Spatial presets do not automatically replace the existing interactive default. Unsupported ridge, rotor and valley modes remain visibly unavailable; finite thermal practice cells do not infer surface heating from the sky rendering.

Calm retains trace v3 and legacy flight-checkpoint v1 behavior. Wind-only mean/gust traces use v4; turbulence traces use v5 and carry their OU interval and RNG state. Wind checkpoints store the weather configuration and replay state, reject malformed or mismatched inputs before mutation, and reproduce continuation on the pinned runtime. Custom atmosphere adds the v6 trace/v3 checkpoint contract described in [ATMOSPHERE-PLAN](ATMOSPHERE-PLAN.md). These formats are feature-specific; other propulsion integrations have their own later versions.

Weather metadata accompanies recorded rows. v4/v5 readers independently check wind vectors, air-relative speed and state/load sample timing. The v5 reader reconstructs the seeded generator and OU continuation. Legacy trim/propeller-range readers remain calm/v3-only and refuse newer wind traces. Exact checkpoint replay is not a cross-Godot-version or cross-platform RNG promise.

| ID | Work and evidence | Status |
| --- | --- | --- |
| M5-W00 | Primary-source/runtime audit and scoped plan; historical assumptions reconciled here. | Complete — research |
| M5-W01a | Calm/steady config and field: 54 checks, fleet calm parity and cost. [Evidence](research/wind-implementation/M5-W01a/README.md) | Implemented |
| M5-W01b | Uniform field through aero/propulsion/wake on all four aircraft. [Flight tests](../app/tests/test_wind_flight.gd) | Implemented |
| M5-W01c | Moving-air trim and reset using Galilean comparison. | Implemented |
| M5-W01d | CLI, HUD, trace/checkpoint contracts and three source/native Linux trace pairs. [Integrated proof](research/wind-implementation/README.md) | Complete — software |
| Gate W-A | Owner steady head-, tail- and crosswind flights. | Open |
| M5-W02a/b | Reuse H8 RK stage-time forcing; verify the cosine pulse and fourth-order refinement. | Implemented |
| M5-W02c | Legacy periodic cadence plus explicit finite nonperiodic v5 gust agendas. | Implemented authored events; automatic meteorological event generation remains separate |
| M5-W03a | Smooth mean direction/speed changes, including 359°→1° and the 180° tie rule. | Planned |
| M5-W03b | Draft weather editor and persistence. [EN/ES and precision evidence](research/wind-implementation/M5-W03b/README.md) | Implemented |
| M5-W04a | OU kernel, fleet replay, v5 reader, FPS and UI evidence. [Proof](research/wind-implementation/M5-W04a/README.md) | Implemented; physical/spectral acceptance open |
| M5-W04b | Wind-driven swiveling windsock, inflation, gravity sag and damped fabric response. [Construction sources and verification](research/wind-implementation/M5-W04b-R1/README.md). | Implemented presentation; physical calibration and human readability remain open |
| Gate W-B | Owner variable-wind handling and conditions. | Open |
| M5-W05a/b/c | Flat-datum shear, analytic spatial field, distributed wing/tail/prop response. | Implemented experimental v5 path; terrain-relative shear and physical qualification remain open |
| M5-W05b-R1 | Float64 position/time adapters and actual body-stage queries; invalid-field rollback, legacy comparison and fleet fixtures. [Evidence](research/wind-implementation/M5-W05b-R1/README.md) | First P0 slice implemented; spatial weather admission and remaining P0 work open |
| M5-W05c-R1 | Fixed-datum station flow and matched unwashed wing/tail load difference; analytic gradient and legacy compatibility checks. [Evidence](research/wind-implementation/M5-W05c-R1/README.md) | Experimental kernel implemented; powered consumers follow in R2; spatial admission pending |
| M5-W05c-R2 | Complete stage Air receipt, local propulsion inflow and matched wash/transport consumers; actual powered-session stages and refusal rollback. [Evidence](research/wind-implementation/M5-W05c-R2/README.md) | Experimental integration implemented; persistence, starts and scenario qualification remain open |
| M5-W05d-R1 | Explicit v5 spatial scenarios, complete stage law, starts, checkpoint/trace identity, local windsock and native UI. [Evidence and limits](research/wind-implementation/M5-W05d-R1/README.md) | Implemented experimental path; physical/handling/performance qualification remains distinct |
| M5-W08a-R1 | Finite drifting streamfunction thermals with compensated sink, shared field identity and replay. [Equations and evidence](research/wind-implementation/M5-W05d-R1/README.md#balanced-thermal-circulation) | Implemented kinematic closure; heating/meteorological calibration remains open |
| M5-ATM-4-R1 | Reconcile this guide with the implemented v4 dry altitude column and route-specific defaults. | Documentation corrected |
| M5-W06a/b | Compare a Dryden reference; adopt another spectral backend only if evidence justifies it. | Conditional |
| M5-W07 | Smoke/cloud/vegetation/audio wind consumers. | Per-consumer; physical/GPU proof required |
| M5-W08 | Terrain/obstacle wakes and thermals. | Bounded kinematic thermals implemented; heating and terrain/obstacle models remain open |

## Open limits and sources

V5 shear is relative to an explicitly flat datum, not arbitrary physical terrain. The finite-mode field is not a Dryden/von Kármán spectrum; its nominal turbulence input is not measured local RMS. Kinematic thermal circulation does not predict solar heating, atmospheric stability or clouds. Matched wash does not establish spatial wake evolution or strong-shear validity. Terrain/obstacle flow, live mean-weather transitions, spectral calibration and shared companion qualification remain open. Shader noise and cloud drift are visual unless tied to physical wind. The [physics notebook](research/wind-physics-primary-sources.md), [runtime audit](research/wind-godot-integration.md) and [twelve investigations](research/wind-investigations/README.md) retain derivations, statistical limits and future consumer notes.

[NWS wind direction](https://forecast.weather.gov/glossary.php?word=WIND+DIRECTION) establishes the meteorological “from” convention. [JSBSim FGWinds](https://jsbsim-team.github.io/jsbsim/FGWinds_8cpp_source.html) is a primary cosine-profile reference; the simulator's fixed time-period gust is an authored practice input. Software tests prove equations and reproducibility, not site weather, aircraft response or pilot handling. A ground anemometer or plausible windsock image does not identify a 3D turbulent field.
