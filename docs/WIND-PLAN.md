# Wind, gusts and turbulence

2026-10-12 · Revision 4 · Step prefix: **M5-W**.

**Status:** Uniform wind, repeating cosine gusts and seeded temporal OU turbulence are implemented and software verified. Custom field-level atmosphere is also integrated through weather v3; see [ATMOSPHERE-PLAN](ATMOSPHERE-PLAN.md). Owner flight gates W-A/W-B and physical/spectral acceptance remain open.

Owns `app/physics/wind_*.gd`, wind session/trace integration, weather controls, wind tests and `research/wind/`. Coordinate UI, simulation and visual hooks with their owners. The interactive default is the authored `gentle-practice` profile: 1.5 m/s from 090°, 0.6 m/s horizontal and 0.15 m/s upward gust peaks, turbulence RMS [0.15, 0.15, 0.08] m/s, 3 s correlation time, 14 s gust period and 3 s delay. These are estimated practice conditions, not measured site weather.

## Implemented contract

The session owns an immutable, spatially uniform NED air-velocity field shared by all current aircraft, with no aircraft-specific wind multiplier. Mean wind, a periodic cosine pulse and optional turbulence feed the same air-relative velocity used by aero, propeller inflow, shaft loads, wake and downwash. There is no extra wind force, position advection, or invented `-dW/dt` acceleration. Wheel contact and friction remain ground-relative. Wind has no position input, so shear, obstacle wakes and distributed wing/tail wind are not implemented.

```text
v_air_body = v_ground_body - R(q)^T W(t)
TAS = |v_air_body|
qbar = 0.5 rho TAS²
position_dot_NED = R(q) v_ground_body
```

Airborne reset trims to the selected air-relative speed and adds `R^T W(0)` to ground velocity; it does not continuously cancel disturbances. The runway solver includes wind and refuses an unsupported start. RK stages sample the field at their actual simulation times. Queries are pure; turbulence advances only on a committed tick, pause stops it, and rollback restores the filter window and RNG.

Wind-only profiles use `openrc-weather v1`; v2 adds turbulence and v3 adds atmosphere inputs. The v3 custom mode calculates one uniform field-level moist-air density and dry-air charge ratio from elevation, temperature, QNH and humidity. Reference mode preserves literal `rho = 1.225 kg/m³` and charge ratio 1.0. Density does not vary with aircraft altitude; M5-ATM-4 remains deferred. Aero/propeller use total moist density; the naturally aspirated shaft model uses dry-air charge, while glow lag and turbine retain their own current laws.

Wind configuration values are complete, SI inputs: mean speed 0–15 m/s, meteorological direction **from** north clockwise (0–360°), horizontal gust 0–8 m/s, vertical gust −8–8 m/s with positive up, pulse duration 0.5–20 s, period 0.5–120 s and delay 0–3600 s. Period must be at least the duration; 360° canonicalizes to 0°. Calm is the default, with a 4 s pulse, 12 s period and 2 s delay when enabled. Turbulence adds three NED RMS values (0–3 m/s each), correlation time 0.2–30 s and a uint32 seed. Atmosphere ranges and equations are in [M5-ATM](ATMOSPHERE-PLAN.md). Invalid types, nonfinite values, unknown fields and out-of-range input fail validation; untouched float64 values are retained.

For elapsed time `e = t − delay`, the gust is zero outside the pulse and `0.5(1 − cos(2π phase/duration))` inside it, where `phase = e mod period`. It starts and ends at zero, peaks at half-duration and integrates to amplitude × duration/2 per pulse.

The OU update is `x_next = a*x + sigma*sqrt(1-a²)*normal53`, `a = exp(−dt/tau)`, at 240 Hz. A pinned private PCG32 and float64 normal transform make reset/replay deterministic on the pinned runtime. The held endpoint interval is interpolated for RK stages; interior variance is slightly lower than tick-boundary RMS. This is a temporal practice approximation, not Dryden, a spatial spectrum or a measured turbulence model.

## Recording and evidence

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
| M5-W02c | Fixed periodic gust cadence is delivered; a random/resolved seeded agenda is separate. | Partial — remaining scope accepted |
| M5-W03a | Smooth mean direction/speed changes, including 359°→1° and the 180° tie rule. | Planned |
| M5-W03b | Draft weather editor and persistence. [EN/ES and precision evidence](research/wind-implementation/M5-W03b/README.md) | Implemented |
| M5-W04a | OU kernel, fleet replay, v5 reader, FPS and UI evidence. [Proof](research/wind-implementation/M5-W04a/README.md) | Implemented; physical/spectral acceptance open |
| M5-W04b | Local visual wind cues and HUD are present; windsock calibration and human readability remain. | Partial |
| Gate W-B | Owner variable-wind handling and conditions. | Open |
| M5-W05a/b/c | AGL shear, analytic spatial field, then distributed wing/tail/prop response. | Planned |
| M5-W06a/b | Compare a Dryden reference; adopt another spectral backend only if evidence justifies it. | Conditional |
| M5-W07 | Smoke/cloud/vegetation/audio wind consumers. | Per-consumer; physical/GPU proof required |
| M5-W08 | Terrain/obstacle wakes and thermals. | Later source-grounded work |

## Open limits and sources

The registered W05–W08 work is not part of the current uniform-field implementation. AGL shear needs a valid surface-layer domain; spatial wind requires position and station-specific samples; shader noise and cloud drift are visual unless tied to measured wind. The [physics notebook](research/wind-physics-primary-sources.md), [runtime audit](research/wind-godot-integration.md) and [twelve investigations](research/wind-investigations/README.md) retain derivations, statistical limits and future consumer notes.

[NWS wind direction](https://forecast.weather.gov/glossary.php?word=WIND+DIRECTION) establishes the meteorological “from” convention. [JSBSim FGWinds](https://jsbsim-team.github.io/jsbsim/FGWinds_8cpp_source.html) is a primary cosine-profile reference; the simulator's fixed time-period gust is an authored practice input. Software tests prove equations and reproducibility, not site weather, aircraft response or pilot handling. A ground anemometer or plausible windsock image does not identify a 3D turbulent field.
