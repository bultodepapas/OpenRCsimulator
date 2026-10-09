# Wind and gusts

2026-10-09 · Revision 2 · Step prefix: **M5-W** · **Status: uniform wind and deterministic repeating gusts implemented and software verified. Gates W-A/W-B and physical acceptance remain open.**

Owns `app/physics/wind_*.gd`, wind session/trace integration, weather preferences/dialog, wind tests and `research/wind/`. Coordinate simulation, menu and landscape interfaces with their tracks. The owner explicitly selected this larger playable wind slice on 2026-10-09; it advances the former deferred proposal without closing Gate 2/PT2.

This replaces the 2026-10-05 proposal after auditing the current code. Its detailed historical design remains available with `git show 6973e42:docs/WIND-PLAN.md`; primary physics, runtime and future-tool investigations remain in the linked knowledge base. Do not treat its old "ground contact is a crash" or "RK4 has no stage time" statements as current behavior.

## Delivered slice

Home → **Weather** opens an English/Spanish draft editor with Calm, Steady breeze, Crosswind, Gusty and Updraft presets. The six controls set mean speed, meteorological direction, horizontal/vertical gust peaks, duration and period. Cancel/Esc changes nothing. Apply validates once, preserves untouched float64 values and reports refused preference saves. Weather persists through aircraft selection and flight restarts; technical launches ignore player preferences.

A session owns one immutable, spatially uniform air field. Mean wind plus authored repeating cosine pulses affect all four aircraft through their own existing aerodynamic/propulsion data. There is no aircraft "wind sensitivity" multiplier. Density remains the existing 1.225 kg/m³. The periodic practice pattern is not stochastic turbulence or measured site weather.

The scope includes moving-air trimmed starts, a wind-aware static runway solve, TAS/horizontal GS telemetry, wind-aware checkpoint identity, trace v4 for non-calm flights and existing tree/shader wind hooks. The current windsock mesh and cloud drift remain provisional visual work; their physical response is not accepted here.

## Physical contract

State velocity remains ground-relative in body FRD axes; position is world NED. Air transport is `W = [north,east,down]` m/s. Direction is **from** north clockwise; 360° canonicalizes to 0°. Cardinal vectors are exact: north → [-V,0,0], east → [0,-V,0], south → [V,0,0], west → [0,V,0]. A positive vertical gust setting means upward air, so its NED down component is negative. Horizontal zero has no bearing.

```text
v_air_body = v_ground_body - R(q)^T W(t)
TAS = |v_air_body|
GS_horizontal = hypot((R(q) v_ground_body)_north, (R(q) v_ground_body)_east)
qbar = 0.5 rho TAS²
position_dot_NED = R(q) v_ground_body
```

No second wind force, extra wind in position integration or invented -dW/dt acceleration is added. The same AirData reaches aero, propeller inflow, shaft update, slipstream transport and downwash. Wheel contacts, friction, anchors and impact velocities use ground-relative motion. Wind does not turn a render object into a physics collider.

Airborne reset solves the existing air-relative trim and adds `R^T W(0)` to initial ground velocity. It does not continuously re-trim away disturbances. All reset-time wake/lag queries explicitly use t=0. The static runway solver includes wind loads; a requested start without stable support fails visibly instead of falling back to airborne flight.

The existing H8 nonautonomous RK4 evaluates the field at t, t+h/2, t+h/2 and t+h. Field queries are pure and consume no RNG or scene/render clock. A pause freezes weather because simulation time stops; synchronous `sim.step()` uses the same field. The shader clock wraps at 1024 s only for appearance; physical wind never uses that wrap.

## Configuration and provenance

Format: `openrc-weather v1`. All keys are required; unknown keys, unknown format, booleans in numeric fields, NaN/Inf, invalid ranges and period < duration are refused. Direction 360→0 is the only numerical canonicalization. Supplied and returned dictionaries/vectors are detached.

| Key | Unit and accepted range | Default |
| --- | --- | ---: |
| speed_mps | m/s, 0…15 | 0 |
| from_deg | degrees from north, 0…360 | 0 |
| gust_mps | peak horizontal increment m/s, 0…8, along the selected wind direction | 0 |
| gust_up_mps | peak vertical increment m/s, −8…8, positive up | 0 |
| gust_duration_s | total pulse seconds, 0.5…20 | 4 |
| gust_period_s | start-to-start seconds, 0.5…120 and ≥ duration | 12 |
| gust_delay_s | first pulse delay seconds, 0…3600; preserved by the six-field editor | 2 |

These ranges/defaults are **estimated engineering and practice choices**, source: OpenRC's bounded first implementation. They are not measured RC wind limits. User-selected values are manual scenario inputs, not inferred atmospheric statistics; the trace records that evidence limit. Existing aircraft quantity provenance is unchanged.

For elapsed time e=t−delay, the pulse is zero before delay. Otherwise phase=e mod period:

```text
gain = 0.5 (1 - cos(2 pi phase / duration))  for 0 < phase < duration
gain = 0 elsewhere
W = W_mean + gain W_gust_peak
```

The pulse starts/ends at zero with zero endpoint slope, peaks at half-duration, and its component integral over one pulse is amplitude × duration/2. Pulses do not overlap. This is a time-parametrized authored input, distinct from certification spatial gust lengths or a random gust schedule. The same settings reproduce the same realization; this implementation has no seed because it has no randomness.

Direct launch examples:

```sh
"$(app/get-godot.sh)" --path app -- --weather=gusty
"$(app/get-godot.sh)" --headless --path app -- --weather=gusty --trace=/tmp/gust.csv --t=5
python3 app/tests/check_wind_trace.py /tmp/gust.csv --duration 5
```

`--weather-file=path.json` loads a complete configuration. SI overrides are `--wind-speed`, `--wind-from`, `--gust-speed`, `--gust-up`, `--gust-duration`, `--gust-period`, `--gust-delay`. A preset and file together are refused. Weather configuration changes require a launch/reset boundary; the Home editor never changes an active flight.

## Recording and replay

Calm preserves trace v3 columns/semantics and legacy flight-checkpoint v1 fingerprints exactly. `speed_mps` retains its historical 3D ground-speed meaning.

Non-calm traces use **openrc-trace v4**, metadata v3, and append state-time wind N/E/D, TAS, horizontal GS, k1 `loads_t_s`, k1 wind and k1 TAS. Tick k state is final, while k1 loads use state k−1 and current sampled auxiliary state. Mid-flight recording preserves the preceding body state at full precision, so the first force/TAS sample is not attributed to the current body. Weather metadata is frozen with its rows; malformed/incomplete weather records refuse saving. The v4 reader verifies these equations independently and rejects old/new timing confusion.

Non-calm checkpoints use **openrc-flight-checkpoint v2**, carry exact weather configuration and include it in the model/ground fingerprint. Restoring a valid same-model wind checkpoint into a fresh calm session reinstates its forcing and repeats continuation bit exactly. Invalid config/hash/layout/timestep fails before changing state. Legacy v1 cannot conceal wind. CSV's nine decimal places are diagnostics; exact replay uses Variant-encoded float64 checkpoint data.

Existing trim/propeller-range readers retain their v3 contract and refuse v4. The new reader handles the weather contract; do not acknowledge "still air" for a windy flight. A permanently portable replay or source-range audit of v4 needs its own extension.

## Step status and evidence

| ID | Work | Status/proof |
| --- | --- | --- |
| M5-W00 | Primary-source/runtime audit and scoped plan | Historical research retained; current implementation assumptions reconciled here |
| M5-W01a | Validated calm/steady weather | Implemented: 54 config/field checks; [fleet calm parity and cost](research/wind-implementation/M5-W01a/README.md) |
| M5-W01b | Uniform field through aero/propulsion/wake | Implemented: [flight tests](../app/tests/test_wind_flight.gd), all four aircraft and current shaft inflow |
| M5-W01c | Trim in a moving air mass | Implemented: W·t Galilean comparison and reset-time tests |
| M5-W01d | CLI, HUD, trace/checkpoint versions | Complete software delivery: 29 trace/9 HUD checks, CLI/reader refusals, v4/v2 contracts and three source/native Linux trace pairs; [integrated evidence](research/wind-implementation/README.md) |
| Gate W-A | Owner steady head/tail/crosswind flight | Open; software verification does not supply pilot or airframe validation |
| M5-W02a | RK stage-time forcing | Already delivered by H8; reused and checked with an exact cosine-forcing integral |
| M5-W02b | Known 1−cos pulse | Implemented: peak/endpoints/area and fourth-order manufactured-forcing refinement |
| M5-W02c | Seeded gust agenda | Fixed periodic cadence delivered; random/resolved seeded agenda remains planned |
| M5-W03a | Slow mean direction/speed changes | Planned; shortest-arc 359→1 and 180° tie rule need explicit tests |
| M5-W03b | Draft UI and persistence | Implemented: [rendered EN/ES evidence](research/wind-implementation/M5-W03b/README.md), numeric precision and future-schema refusal |
| M5-W04a | Correlated OU turbulence | Planned; filters/RNG/checkpoint/statistical acceptance required |
| M5-W04b | Physical local wind cues | Shader/tree hook and truthful HUD delivered; windsock/inflation calibration and human reading pending |
| Gate W-B | Owner variable-wind handling/conditions | Open |
| M5-W05a | AGL shear profile | Planned; simulation-owned terrain and valid surface-layer domain |
| M5-W05b | Analytic spatial field | Planned; position sampling and affine-field oracles |
| M5-W05c | Distributed wing/tail/prop corrections | Planned; current CG AirData cannot represent gradients |
| M5-W06a | Dryden reference study | Conditional research; establish whether it adds useful realism |
| M5-W06b | Accepted spectral backend | Conditional; replace the selected approximation rather than double-count it |
| M5-W07 | Smoke/cloud/vegetation/audio consumers | Per consumer; physical advection and GPU evidence needed |
| M5-W08 | Terrain/obstacle wakes/thermals | Later source-grounded extensions |

## Foundations for later steps

- Temporal OU is a labelled approximation, not Dryden: a=exp(−h/tau), x_next=a x+sigma sqrt(1−a²) xi. Version RNG/algorithm, draw outside RK-stage queries, checkpoint RNG/filter/agenda and test pause/rollback/FPS. An engine RNG can use float32 internally; multiplying by sigma in GDScript64 alone does not prove sample precision or Gaussian tail fidelity.
- Statistical proof needs RMS, autocorrelation/PSD, cross-component correlation, detrending, windows and uncertainty for correlated samples. Do not subtract a fitted mean without declaring it. Zero sigma must be exact zero and zero airspeed needs an explicit encounter-time policy.
- Logarithmic AGL shear requires reference height, roughness/displacement and a valid neutral surface-layer domain; never extrapolate a singular log profile to z=0. It is different from aerodynamic ground effect.
- Spatial wind needs geometry-owned per-station positions, local velocities and wind-gradient/vorticity conventions. Uniform wind must produce exactly zero distributed correction even with rates and stall; never blindly add new loads over the existing CG/local-flow model.
- Clouds currently drift in cells/s; that is not physical wind m/s. Advection needs integrated displacement, scale/height and no jump at shader-clock wrap. GLES3 particles may already integrate VELOCITY; never add displacement twice.
- Physical sampling stays float64. FastNoiseLite/shader noise is appearance unless precision and spectra are established. Shape wind with atmospheric evidence; never tune aircraft coefficients to hide a mismatch.
- Budgets remain ≤500 µs/240 Hz physics tick on the owner's target. Measure all models/regimes and distinguish tick latency percentiles from batch-average percentiles. Current noisy measurements include P-51 overruns; neither wind gates nor Gate P are closed. Profile before optimizing or adding native dependencies.

## Sources and limits

[NWS wind direction](https://forecast.weather.gov/glossary.php?word=WIND+DIRECTION) establishes the from convention. [JSBSim FGWinds](https://jsbsim-team.github.io/jsbsim/FGWinds_8cpp_source.html) is a primary reference for cosine profiles; our fixed time period is an authored practice choice. Code is original GDScript; no JSBSim source is copied.

The retained [primary physics notebook](research/wind-physics-primary-sources.md), [runtime audit](research/wind-godot-integration.md) and [twelve investigations](research/wind-investigations/README.md) cover NASA turbulence references, spectra, schemas, runtime, spatial diagnostics and visual consumers. Their dates and old-code findings remain historical where superseded here.

Software tests verify equations, state contracts and reproducibility. Independent wind/site measurements, pilot handling/readability and native target-GPU acceptance remain open. A ground anemometer or qualitative windsock video does not identify a 3D turbulent field; preserve instrument height/exposure/cadence/obstacles and retain held-out validation rather than treating plausible appearance as physical truth.
