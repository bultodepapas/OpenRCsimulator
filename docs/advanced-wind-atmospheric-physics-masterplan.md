# Advanced wind and atmospheric physics masterplan

**Audit date:** 2026-10-25. **Status:** audit and proposed engineering design; no gameplay implementation or physical qualification performed by this task.

**Source baseline:** `82376c1155c5557ea3397e10b81a6d4cd7b904a9`. The tree was clean at the initial check. During the audit, concurrent statistics/UI work was committed externally as `789ed226c38f3c89a6e917cf8f927da5838318cc`, followed by further unrelated presentation/audio/tool edits. The resumed review verified the relevant wind seams against the current sources and preserved that work; this is not an immutable whole-tree test result. Symbol names below are more durable than line numbers. This task edits only this masterplan.

**Ownership:** extend the existing M5-W and M5-ATM tracks, with SF/kernel, aircraft/AS, propulsion, GP/ground, UI, NR, AFC/companions, FW/TOD, LU/SC, SM and AUD co-owners at their existing boundaries. [Wind](WIND-PLAN.md), [atmosphere](ATMOSPHERE-PLAN.md), [architecture](STACK.md), [ownership registry](README.md#tracks-plans-and-step-ids), [aircraft contract](AIRCRAFT_CONTRACT.md) and [flight logging](FLIGHT-LOGGING.md) remain authoritative for shipped behavior and existing evidence. This document owns the proposed advanced-atmosphere design; it does not mark earlier gates complete or replace their evidence.

## 1. Executive summary and realism objectives

OpenRC already applies wind as air velocity rather than an invented force. It has deterministic uniform mean wind, smooth periodic gusts, seeded temporal Ornstein–Uhlenbeck (OU) disturbances, wind-aware starts, air-relative aerodynamic and propulsion inputs, configurable density, an optional dry ISA altitude column, weather controls, a moving windsock, presentation consumers and substantial replay/test infrastructure. **Preserve these foundations.** The interactive default is already a gentle breeze; the technical default is deliberately calm.

The largest realism limitation is that atmospheric velocity has no position argument. A whole airplane receives one wind vector, so a gust cannot cross the left wing, right wing and tail at different times. Current OU disturbances have a time scale but no atmospheric length scale. AI companions deliberately receive different turbulence seeds. Terrain geometry, atmospheric roughness, surface heating and weather evolution are not yet a coherent physical system.

Recommended architecture: evolve the existing `sim/environment.gd` into the access point for a versioned, pure, float64 spatial weather provider. Retain the uniform provider unchanged for old configurations. Introduce one shared world field, evaluated at actual RK stage positions/times, then route local ambient air through existing aerodynamic surfaces and propulsion inflow. Prefer a bounded divergence-free spectral/vector-potential field for interactive spatial turbulence; use Dryden as a verification reference and optional explicitly labeled trajectory model, not independent filters on each wing. Add bounded thermals with compensating circulation, then terrain flow only where physical terrain and boundary data support it.

Success means observable drift, crab/slip corrections, load-induced angular responses, coherent gust passage, ground transitions and soaring energy changes. It does **not** mean continuous motion at all costs: a trimmed airplane in uniform air can legitimately fly smoothly. Do not inject disturbances to conceal an aircraft-model deficiency, compensate for controls, guarantee a climb, or make every airplane equally difficult.

Non-negotiable contracts:

- No random attitude edits, direct angular impulses, camera shake as a physics substitute, extra wind force, position advection on top of ground velocity, or arbitrary lift/soaring bonus.
- Wind is air transport velocity in NED, m/s. Aircraft motion remains ground-relative; aerodynamic loads use local air-relative velocity exactly once.
- One physical environment identity per simulated world. Aircraft geometry and dynamics determine response; weather never reads aircraft identity, span or pilot skill to alter its field.
- All simulation quantities remain float64 scalars/packed arrays. Godot `Vector3`/`Basis` are presentation conversions only.
- Old weather laws, calm fixtures, aircraft data and exact-replay identities remain explicit. A new law is never silently substituted into an old recording.
- Physical plausibility, numerical verification, measured atmospheric validation, human handling acceptance and target-hardware performance are separate gates.

## 2. Exact repository audit

### 2.1 Method and confidence

Discovery began with the indexed `C-DEVELOPMENT-OpenRCsimulator` knowledge graph. Some graph searches omitted present physics/UI modules; current source inspection and bounded `rg` searches supplied the permitted fallback. Production `app/` was inspected; the frozen three.js prototype was not treated as runtime. Existing tests and evidence were read, **not rerun** for this documentation-only deliverable. No live flight, listening session, anemometer measurement or pilot evaluation was performed.

“Correct” below means the inspected formulation is appropriate for its declared scope, not that an aircraft has been flight-validated. “Missing” means absent from the inspected production weather path; similarly named thermal battery models, shader noise and rendered mountains do not establish atmospheric physics.

### 2.2 Runtime, data and presentation inventory

| Area and verified integration point | Exists and should be reused | Incomplete, incorrect for a broader claim, or missing |
| --- | --- | --- |
| [wind_config.gd](../app/physics/wind_config.gd): `defaults`, `GENTLE_PRACTICE`, `validate`, `presets`, upgrades | Strict complete SI settings; weather v1 uniform, v2 OU, v3 field atmosphere, v4 dry standard column; finite/type/range checks; seed validation; detached configurations | No position reference, length scales, shear layers, thermal/terrain modules, component provenance or spatial law identifier. Existing bounds are software envelopes, not measured RC weather limits. |
| [wind_field.gd](../app/physics/wind_field.gd): `sample`, `_direction_ned`, `atmosphere` | Pure mean plus repeating half-cosine pulse; correct meteorological FROM conversion; density/charge delegated to atmosphere | `sample(time_s)` explicitly uniform. Horizontal gust shares mean bearing; vertical pulse repeats globally. No directional gust events, spatial coherence scale, thermal lifecycle or wind shift agenda. |
| [wind_turbulence.gd](../app/physics/wind_turbulence.gd): `initial`, `step`, `_normal_pair` | Exact-discrete stationary OU recurrence, private Godot PCG stream, 53-bit uniform/normal conversion, persisted state | Three independent NED processes with common correlation time; no length scale, speed-dependent encounter spectrum, spatial covariance or boundary constraint. It is not Dryden or von Kármán. |
| [environment.gd](../app/sim/environment.gd): `wind`, `air`, `terrain`, `ground`, `identity` | Existing shared physical environment contract, pure terrain/atmosphere queries; separates visual time/lighting; adds session turbulence once | `wind(time_s)` has no position. Identity hashes surfaces and identifies lake but is diagnostic, not a complete spatial-world checkpoint receipt. Extend this seam rather than inventing an unrelated global service. |
| [flight_session.gd](../app/sim/flight_session.gd): `setup_weather`, `wind_at`, `turbulence_at`, `_initial_wind`, `air_data`, `_wash_loads`, `_turbine_evaluate` | Launch-boundary validation; failed edits preserve accepted flight; reset incorporates moving air; held OU endpoints interpolated during stages; RNG/window lives in snapshot; density evaluated at stage datum | Time-only wind must become stage-position sampling throughout all powertrain paths, trim, launch and observers. Weather changes currently require reset/new flight. Some comments still say “calm air” despite wind integration. |
| [simulation.gd](../app/sim/simulation.gd), [vehicle_model.gd](../app/sim/vehicle_model.gd), [project.godot](../app/project.godot) | Shared model-driven kernel, fixed 240 Hz, RK stage evaluation, transactional state/recovery; 12 catch-up ticks/frame limit | Do not put fixed-wing atmosphere branches in the kernel. Environmental state ownership across several sessions requires an explicit shared clock/snapshot policy. Below roughly 20 rendering FPS the configured catch-up cap can slow simulated time. |
| [air_data.gd](../app/physics/air_data.gd): `compute` | Subtracts body-transformed wind; computes TAS, alpha, beta and dynamic pressure from air-relative velocity; zero-speed-safe angle formulation | One ambient vector at the reference point. Do not subtract wind again in local surfaces or propulsion. TAS/EAS are not a calibrated pitot IAS. |
| [aero.gd](../app/physics/aero.gd): `loads`, `_global_loads`, `_local_loads`, `local_flow_weight`, `wing_wake_velocity`, tail functions | Empirical attached-flow oracle blended with local wing/tail loads; three equal-area stations per wing side; rigid-body rate-arm kinematics; section-plane lift/drag; moments from arms plus declared couples; dimensional downwash source | Local flow varies through rotation but not local atmospheric velocity. Differential gusts must affect the attached-flow region too. Adding a second full strip model over the empirical loads would double count. Existing quasi-steady coefficients do not establish unsteady gust response at all frequencies. |
| [dynamics.gd](../app/physics/dynamics.gd): `_components_from_air`, `loads_from_air`; [propulsion.gd](../app/physics/propulsion.gd), [turbine.gd](../app/physics/turbine.gd) | One load assembly; reuse same-stage shaft results; local hub/intake rotational velocity for relevant powerplants; thrust/torque feed wash consistently | Hub/intake needs ambient sampling at its world point. A spatial migration must cover prescribed RPM, coupled shaft, electric/battery, glow/fuel and turbine routes, not only the simple `_loads` branch. |
| [slipstream.gd](../app/physics/slipstream.gd), [wash_transport.gd](../app/physics/wash_transport.gd); `Aero.tail_surface_increment` | Aircraft-induced flow is distinct; washed-minus-free tail increment avoids duplicating baseline tail loading; transported wash state and lagged downwash exist | Both free and washed evaluations need the **same local ambient** sample. Do not promote aircraft wake into background weather or add independent gust-rate moments over resolved gradients. |
| [ground_effect.gd](../app/physics/ground_effect.gd), [ground_contact.gd](../app/physics/ground_contact.gd), [ground_start.gd](../app/physics/ground_start.gd) | Opt-in induced-angle/drag/downwash ground effect; ground-relative contact and friction; wind-aware runway equilibrium/refusal | Boundary-layer wind and aerodynamic ground effect are separate. Ground-effect ground reference is currently supplied under the body; per-surface terrain height is a later coordinated GP improvement. Taxi aero should persist with zero ground speed in moving air. |
| [atmosphere.gd](../app/physics/atmosphere.gd), weather v3/v4 | Literal reference density 1.225 kg/m³; custom moist-air density from temperature/QNH/RH/elevation; dry charge ratio; dry standard column by geometric altitude | Custom station weather is uniform with height; standard column is dry ISA, not an observed sounding. No prognostic heat budget, inversion profile, cloud/convection physics or general moist vertical column. Do not add another density multiplier. |
| [ground_terrain.gd](../app/physics/ground_terrain.gd), [lake_surface.gd](../app/physics/lake_surface.gd), [landscape catalog](../app/landscapes/catalog.gd) | Physical ground queries, surface rectangles, mm-scale soil relief and lake/bank sampling; Club field and Green Paradise adapters | Soil relief is not aerodynamic roughness `z0`. Rendered distant mountains/horizon data are not an aerodynamic ridge boundary. No audited general ridge-height/roughness/heat-flux map or terrain-wind solver. |
| [weather_dialog.gd](../app/ui/weather_dialog.gd), [home.gd](../app/ui/home.gd), [preferences.gd](../app/app_state/preferences.gd) | `WeatherDialog`/`WeatherPanel`, `WeatherPreset`, `WeatherTabs`, `WindAndGusts`, `TurbulencePage`, `AtmospherePage`; paired sliders/exact inputs; seed; Apply/Cancel; time/sky tabs; EN/ES; versioned `user://settings.cfg` | Technical N/E/up RMS controls are exposed early. No runway-relative crosswind summary, thermal/layer editor, named spatial scenario library or dedicated weather factory/default actions. A preference file is not yet scenario save/load. |
| [main.gd](../app/main.gd): `_weather_options`, `_weather_hud_line`, `_advance_windsock`, `_render_wind` | CLI preset/file/override route; ground speed, wind bearing/speed/up HUD; committed-tick windsock hook and render conversion | One common vector feeds all locations. Spatial observers must identify their sampling point and time, rather than treating aircraft wind as wind at the pilot or windsock. |
| [natural_random.gd](../app/scenarios/natural_random.gd), [scenario_config.gd](../app/scenarios/scenario_config.gd) | Seeded resolved scenario recipes and separate lighting selection | Validator explicitly requires weather v3. Advanced scenarios need a new capability/schema path; do not silently broaden old recipe behavior. |
| [companions/agent.gd](../app/ai/companions/agent.gd): `configure`; [manager.gd](../app/ai/companions/manager.gd): `validate_context` | Independent real sessions and wind-aware planning; bounded qualification envelope | Agent modifies turbulence seed by slot. This is inconsistent with a shared spatial atmosphere at coincident points. Manager limits weather to gentle reference-air conditions; new weather must remain unavailable there until AFC qualification is extended. |
| [windsock.gd](../app/render/windsock.gd), [windsock_motion.gd](../app/render/windsock_motion.gd), [field.gd](../app/render/field.gd) | Existing physical-looking bearing/inflation/sag response, authored dimensions, cached cue nodes; consumes wind without writing physics | Currently all cues receive common wind. Sample at sleeve/mast height; fabric response remains presentation and needs calibration/readability acceptance. |
| [shader_clock.gd](../app/render/shader_clock.gd), [world.gd](../app/render/world/world.gd), [smoke](../app/render/smoke/), [sky_appearance_config.gd](../app/environment/sky_appearance_config.gd) | Shared simulation-clock presentation, global `wind_vec`, smoke transport, cloud follow-wind/aloft choices, weather appearance/storm events | Shader flutter/smoke dispersion are cosmetic; cloud aloft motion is separately configured. Sky appearance and storm lightning do not imply physical thermals, shear, precipitation or downdrafts. A single shader uniform cannot represent a general field. |
| [flight_audio.gd](../app/audio/flight_audio.gd), [soundscape_model.gd](../app/audio/soundscape_model.gd), [windsock_audio.gd](../app/audio/windsock_audio.gd) | Wind/foliage ambience, positional aircraft sound and recorded windsock fabric; read-only accepted state | Currently derives common wind speed/direction. Listener-relative ambient wind and aircraft-relative airflow need separate inputs; sound intensity must not drive flight physics. Reuse licensed banks. |
| [trace.gd](../app/sim/trace.gd), [flight-log workflow](FLIGHT-LOGGING.md), wind/atmosphere tests | Metadata, checkpoints, exact continuation, independent CSV readers, stage/endpoint distinctions, replay/source identities and software evidence | Spatial sampling coordinates, component decomposition, field asset identity, gradients and multi-aircraft coherence tests are missing. Several older wind fleet tests enumerate four aircraft, while the catalog has grown. |

### 2.3 Default and catalog findings

Fresh interactive preferences select `GENTLE_PRACTICE`: **1.5 m/s FROM 090°, horizontal gust peak 0.6 m/s, upward gust peak 0.15 m/s, duration 4 s, period 14 s, delay 3 s, N/E/D RMS [0.15, 0.15, 0.08] m/s, tau 3 s, seed 20261011**. The default eastbound runway therefore receives predominantly a headwind, not a persistent slight crosswind. Technical routes use `WindConfig.defaults()` with zero atmospheric velocity; automation bypasses interactive preferences. Preserve that distinction.

A positive-only vertical pulse has nonzero long-term mean: the default contributes `0.15*4/(2*14) = 0.02143 m/s` upward, and its horizontal pulses add `0.08571 m/s` along the gust direction. That is acceptable for a declared practice waveform, but “mean wind” then describes the background, not the total long-time mean. The current Updraft preset is a global recurring vertical pulse, **not a thermal**. Future natural presets must report background mean versus realized gust statistics and avoid unexplained net upward transport.

The current [aircraft catalog](../app/app_state/aircraft_catalog.gd) contains the Ugly Stik family, Extra 300S, P-51D, F4U Corsair, Avanti/Ventage jet, Turbo Lumber and an experimental helicopter route. It does **not** contain a dedicated sailplane or ultralight indoor model. Use Stik/Extra/Turbo Lumber/warbirds for immediate acceptance, engine-off powered-aircraft cases for early vertical-air checks, and a separately sourced/validated sailplane and lightweight fixture before claiming glider/lightweight qualification. Do not invent a shipped glider or generate one merely to fill this audit.

### 2.4 Correctness versus simplification

No inspected evidence supports replacing the current basic wind subtraction or adding a direct wind acceleration. Uniform air is a valid model. The high-priority corrections are **extension hazards and misleading assumptions**: spatially uniform turbulence cannot produce spatial gust gradients; per-companion seeds do not form a common atmosphere; a universal positive vertical pulse cannot represent closed thermal circulation; independent renderer weather does not establish physical weather; global and local aerodynamic loads cannot simply be added.

The [wind guide](WIND-PLAN.md) still contains a paragraph saying density does not vary with aircraft altitude/M5-ATM-4 is deferred, while its referenced [atmosphere guide](ATMOSPHERE-PLAN.md), `WindConfig.COLUMN_FORMAT`, `WindField.atmosphere(down_m)` and column tests show the dry reference column is implemented. Correct that documentation during P0 integration. Likewise, its “Calm is the default” wording needs route qualification. Historical research remains dated evidence, not current implementation status.

## 3. Research basis and decision limits

Use primary models as independent references, not as automatic RC presets. Transport-aircraft certification gust amplitudes, wind-turbine inflow defaults and full-scale pilot thresholds are not validated meter-span aircraft weather. Parameter proposals in this document are **engineering estimates for testing**, not universal atmospheric constants or real-world operating limits.

| Reference | Engineering use | Applicability limit |
| --- | --- | --- |
| [NASA Luers, NASA-CR-2288, surface boundary layer](https://ntrs.nasa.gov/citations/19730018294) | Roughness/displacement, neutral log profile and stability corrections | Surface-layer assumptions fail in very stable, separated and heterogeneous flow. |
| [NASA Madden, Dryden implementation verification](https://ntrs.nasa.gov/citations/20190000875) | Spectral/filter verification and distinction between translational gusts and gust gradients | One-dimensional trajectory spectra do not supply a shared arbitrary 3D field. |
| [NASA Yeager, Dryden filters](https://ntrs.nasa.gov/citations/19980028448) | Independent numerical comparison/reference implementation | Pin spectrum conventions, units and sample rate before comparing. |
| [NASA Allen, Updraft Model, 20060004052](https://ntrs.nasa.gov/citations/20060004052), and [analytical thermal presentation, 20060024599](https://ntrs.nasa.gov/citations/20060024599) | The first is the detailed 2006 model paper with derivation/code/check case; the second is a separate 2006 presentation covering thermal scaling and sink | Desert-region measurements informed the model; it is not a universal local-weather forecast. Both identifiers were checked against NASA records. |
| [NOAA boundary-layer training](https://www.weather.gov/source/zhu/ZHU_Training_Page/clouds/planetary_boundary_layer/PBL.html), [NOAA stability computation](https://ready.arl.noaa.gov/documents/Tutorial/html/parm_stab.html) | Surface heating, mixed-layer growth and stability drivers | Visual sun elevation alone does not determine sensible heat flux or mixing height. |
| [TurbSim user guide](https://www.nrel.gov/docs/libraries/wind-docs/turbsim_v2-00-pdf.pdf?sfvrsn=5a0a30f8_1) | Existing free full-field spectral/coherence reference and offline fixture source | Wind-energy parameterization and dimensions must not be copied as RC truth. No runtime dependency required. |
| [FAA Glider Flying Handbook](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/glider_handbook) | Independent qualitative expectations for lift, sink, drifting thermals, ridge and lee effects | Full-scale handbook is not RC coefficient calibration or a simulator safety qualification. |
| [JSBSim FGWinds source](https://jsbsim-team.github.io/jsbsim/FGWinds_8cpp_source.html) | Open implementation reference for prescribed gust profiles and weather decomposition | Resolve coordinate conventions explicitly; copying a class name is not model equivalence. |

The existing [wind physics source notebook](research/wind-physics-primary-sources.md), [integration investigation](research/wind-godot-integration.md), [wind evidence](research/wind-implementation/README.md) and [atmosphere evidence](research/atmosphere/M5-ATM-2/README.md) supply prior derivations and provenance. Reuse their references and tools. Preserve new accepted measurements under the owning evidence directories, not large images in the repository.

## 4. Wind field mathematics and turbulence choice

### 4.1 Frames, clocks and mean flow

Let `x = [N,E,D]` be world position in meters from the existing field datum; `R(q)` maps body FRD to NED. Let `h(N,E)` be physical ground height upward from that datum:

```text
z_AGL = -D - h(N,E)                  # local surface clearance
z_geometric = field_elevation_m - D  # atmospheric column altitude
W_N = -U * cos(theta_from)
W_E = -U * sin(theta_from)
W_D = -w_up
render(W) = [W_E, -W_D, -W_N]
```

Scenario bearings are true degrees clockwise FROM north; solver angles are radians. At zero horizontal wind, display bearing as unavailable but retain the draft bearing. Identify time using integer simulation tick and rational stage fraction, then derive seconds. Wall clock, frame count, camera and graphics quality never affect physical samples.

The proposed ambient field is:

\[
\mathbf W(\mathbf x,t)=\mathbf U_{profile}(\mathbf x,t)+\mathbf G(\mathbf x,t)
+\mathbf T(\mathbf x,t)+\mathbf C(\mathbf x,t)+\Delta\mathbf W_{terrain}(\mathbf x,t).
\]

`U_profile` includes reference mean **and its vertical profile**, not two copies of the mean. `G` contains coherent gust events, `T` residual turbulence, `C` thermal/vertical circulation, and terrain contributes a **correction** to incident flow. A terrain asset containing total flow must first subtract its declared reference flow. Aircraft-induced wash stays outside this sum. Maintain a component/bandwidth ledger so a thermal, wake and background turbulence do not each claim the same variance.

### 4.2 Surface layer and layers aloft

First support flat, approximately homogeneous open fields. Above the roughness sublayer, neutral flow can use:

\[
U(z)=U_r\frac{\ln[(z-d)/z_0]}{\ln[(z_r-d)/z_0]},\quad z>d+z_0.
\]

`U_r` is wind at reference AGL `z_r`; `z0` is aerodynamic roughness length; `d` is displacement height. Resolve the initial factory profile to `z_r=10 m`, `z0=0.03 m`, `d=0`; investigate short-grass `z0=0.01–0.05 m`. These are **estimated site parameters**, not measured defaults. Do not infer `z0` from tire rolling resistance or millimeter soil relief.

Do not evaluate the logarithm at wheel height. Declare a lower model height, initially `z_min=max(0.3 m,10*z0)` for this open-field approximation. Below it use an explicitly named monotone cubic Hermite wall blend, matching zero surface velocity and the value/slope at `z_min`; bound the matched slope to preserve monotonicity. This regularization is an engineering approximation, not an extension of log-law validity. Reject subsurface samples except documented contact-roundoff tolerance. Above the declared surface-layer top, initially 50–100 m and constrained by mixing height, smoothly join authored free-air layers rather than extrapolating indefinitely.

Layer knots specify horizontal vectors, height basis (`AGL_flat_site` or geometric altitude), transition depth and interpolation law. Use bounded C1/C2 interpolation. Vector interpolation between opposite directions passes through reduced speed; speed/bearing interpolation instead needs a shortest-angle rule and explicit 180° tie. Keep those modes distinct. A profile following arbitrary terrain height does not automatically satisfy continuity or no penetration; terrain-following correction belongs to P3.

P2 may introduce a consistent Monin–Obukhov closure:

\[
U(z)=\frac{u_*}{\kappa}\left[\ln\frac{z-d}{z_0}-\psi_m\left(\frac{z-d}{L_{MO}}\right)
+\psi_m\left(\frac{z_0}{L_{MO}}\right)\right].
\]

Here `kappa≈0.4`, friction velocity `u*` and stability length `L_MO` need defensible surface-flux inputs; neutral means `1/L_MO=0`. Very stable, canopy and separated flows are outside the initial law. A generic stability slider is insufficient without a consistent closure. [NASA surface-layer report](https://ntrs.nasa.gov/citations/19730018294), [Businger et al.](https://doi.org/10.1175/1520-0469(1971)028%3C0181%3AFPRITA%3E2.0.CO%3B2).

### 4.3 Gusts and gradual changes

Preserve current periodic gusts as `legacy_periodic_v1`. A spatial test gust can use:

\[
g(s)=\tfrac12 A[1-\cos(\pi s/H)],\quad 0\le s\le2H,
\]

zero outside. `A` is m/s and `H` the gradient distance in m. A world-fixed/advected plane has `s=n·(x-x0-X_advection(t))`; do not advance it separately using each aircraft's speed. A uniform temporal pulse remains useful and must be labeled as such. [JSBSim's gust implementation](https://jsbsim-team.github.io/jsbsim/FGWinds_8cpp_source.html) is a waveform reference, not a natural recurrence model.

Natural gusts use a seeded **resolved agenda**: event ID, start, duration, amplitude vector, location, extent, propagation and lifecycle fixed independently of query order. Initial investigation: duration 2–8 s and nonperiodic interval 8–30 s, refined by presets below. Use smooth finite-support windows. A localized vector multiplied by an envelope can violate continuity; interactive localized events use a vector potential or compatible mass-flux structure. The uniform temporal test mode remains explicitly idealized.

Longitudinal/lateral components are signed in a fixed scenario frame. Slow wind shifts follow a smooth vector timeline over tens of seconds/minutes, not random bearings each tick. Bound event overlap at configuration resolution, not by clipping resulting velocities during flight. If a control promises a long-time mean, center its fluctuations over the declared observation window; otherwise label background mean and report realized statistics. New default vertical disturbances are balanced, while old positive pulses retain their exact behavior.

### 4.4 Model comparison

| Model | Benefit | Limitation | Decision |
| --- | --- | --- | --- |
| Existing OU | Cheap, exact-discrete endpoint covariance, mature replay | Temporal only; no spatial scale; interpolated-stage variance differs slightly | Keep legacy/temporal practice mode. |
| Dryden filters | Rational low-order filters, independent reference PSD, explicit RMS and lengths | Trajectory/frozen-flow assumptions; independent filters cannot provide a common spatial field | W06 reference and optional explicitly labeled trajectory test. |
| von Kármán spectrum | Useful inertial-range behavior in some conditions | Non-rational filter approximation/synthesis; still not automatically 3D or universally superior | Candidate spectral target after evidence comparison. |
| Finite solenoidal Fourier/vector-potential field | Pure 3D sampling, analytic gradients, coherent stations/fleet | Wall treatment, anisotropy, finite-mode recurrence and band limits require verification | **Interactive prototype**, investigate 24–64 modes. |
| Baked spectral-tensor/coherent grid | Rich covariance reference; free Mann/TurbSim-related tools | Memory, tiling, interpolation and domain constraints; wind-energy defaults not RC measurements | Offline fixtures first; optional provider later. |
| Runtime CFD/LES | Can resolve appropriate flow with valid boundaries/resolution | Cost and data requirements exceed this increment | Out of scope; reuse suitable offline research/data. |

One-sided Dryden spatial angular-wavenumber spectra, normalized by `integral_0^infinity Phi dOmega=sigma²`, are:

\[
\Phi_u=\frac{2\sigma_u^2L_u}{\pi[1+(L_u\Omega)^2]},\qquad
\Phi_{v,w}=\frac{\sigma_{v,w}^2L_{v,w}}{\pi}
\frac{1+3(L_{v,w}\Omega)^2}{[1+(L_{v,w}\Omega)^2]^2}.
\]

For a straight frozen-field traversal, `S(omega)=Phi(omega/V_e)/V_e`, where `V_e` is encounter speed. Specify radians/cycles and one-/two-sided normalization; per-Hz and per-radian PSDs cannot be compared directly. Dryden's high-frequency decay is approximately `Omega^-2`, versus a von Kármán inertial-range `Omega^-5/3`. These slopes do not validate real site turbulence. [NASA Dryden verification](https://ntrs.nasa.gov/citations/20190000875), [NASA low-altitude measurements](https://ntrs.nasa.gov/citations/19770025195).

OU uses `x_next=exp(-dt/tau)*x+sigma*sqrt(1-exp(-2dt/tau))*xi`. Exact-discrete covariance does not establish timestep-independent aircraft trajectories or differentiable knots. Preserve its legacy arithmetic. New convergence tests must evaluate the **same continuous field realization** at 240/480/960 Hz; drawing a different sequence at each step is not a valid convergence test.

### 4.5 Recommended coherent field

An open-air prototype uses transverse modes:

\[
\mathbf T(\mathbf x,t)=\sum_{j=1}^{M}\mathbf a_j
\cos[\mathbf k_j\cdot(\mathbf x-\mathbf X_c(t))+\phi_j+\nu_jt],
\qquad\mathbf k_j\cdot\mathbf a_j=0.
\]

`k` is rad/m, `a` m/s, `X_c=integral U_c dt` atmospheric convection displacement, and `nu` rad/s intrinsic evolution. Choose mode weights/polarizations from a declared tensor. Fit requested covariance with transverse amplitudes; scaling Cartesian components after projection can break divergence-free behavior. Independent phase covariance is `sum(a_j*a_j^T)/2`; finite-window covariance and coherence need separate measurement.

Near boundaries use `T=curl(A)` and apply height/windows to **A before differentiation**. Multiplying velocity by `f(z)` yields `div(f*T)=f'(z)*T_z`. A flat-wall potential envelope with zero value and first derivative at the surface can enforce zero velocity there, but changes the spectrum and must be revalidated. No penetration is mandatory. A low-altitude bounded Boussinesq approximation may use constant reference density for continuity; a future stratified mass-flux potential `rho*W=curl(A_mass)` supports `div(rho*W)=0` over larger columns.

For the first new vertical-circulation provider, admit reference/custom **uniform-density** air. Pairing it with the standard density column requires a declared anelastic/mass-flux treatment or a quantified Boussinesq error budget accepted for that domain; do not assert exact mass continuity from `div(W)=0` when density varies with height. This is a new-provider capability gate, not removal of existing v4/OU behavior.

The advection velocity belongs to the atmosphere, never the querying aircraft. With zero advection and intrinsic evolution, a fixed point sees frozen turbulence; that is acceptable only for a labeled frozen test. Use band-limited deterministic intrinsic mode evolution for the first interactive law and call it kinematic synthetic turbulence. If later refreshing modes, use bounded overlapping C2 windows with controlled variance and persisted/regenerable epoch identities; test for amplitude dips and artificial beats. A divergence-free kinematic field is not a Navier–Stokes solution. [Mann's spatial-tensor model](https://doi.org/10.1017/S0022112094001886), [surface-layer Taylor-hypothesis study](https://doi.org/10.1007/s10546-024-00861-1).

RC investigation ranges: horizontal energy-containing scales **5–50 m**, vertical **1–15 m**, with a candidate minimum resolved wavelength **2 m**. These are search ranges, not measurements or mandated aircraft-size scaling. Compare 1/2/4 m cutoffs and station resolution. A 2 m mode encountered at 20 m/s is 10 Hz, but at 60 m/s is 30 Hz. Speed changes encounter frequency, not weather. Unresolved sub-meter energy must be reported as omitted or treated with justified aerodynamic admittance; do not alias it into slow shaking. A claimed tensor spectrum must match its resulting 1D cuts; do not promise exact Dryden and arbitrary anisotropic incompressibility simultaneously.

## 5. Thermals, vertical currents and terrain

### 5.1 Atmospheric and heating inputs

Preserve moist density `rho=(p-e)/(Rd*T)+e/(Rv*T)` and dry charge `(p-e)/(Rd*T)` in their existing owners. A thermal velocity must not also multiply lift, density or engine power. A later physical temperature/humidity perturbation needs its own consistent thermodynamic column; it is an M5-ATM extension.

Convective scales are `B0=(g/theta_v)*mean(w'*theta_v')_surface` and `w*=(B0*zi)^(1/3)` for positive buoyancy flux. `B0` is m²/s³, mixing height `zi` m, `w*` m/s. The dry estimate `B0≈g*H_s/(rho*c_p*T)` omits latent heat/moisture effects. Surface budget `R_n=H_s+LE+G_storage` explains why sunlight alone is insufficient. Current runtime has no calibrated surface heat budget or land-cover heating map.

P2 first accepts authored `B0/zi` or equivalent thermal parameters with provenance. Optional “follow day conditions” resolves a **physical forcing timeline** from time/date/location, cloud transmissivity and surface class, including minutes-scale heat storage. Record it in weather identity. Cosmetic sky edits do not change physics. At night solar convection normally decays with surface heat, while mechanical turbulence and stable shear may remain. Overcast is not universally zero mixing. Existing visual evening must not accidentally activate midday thermals. [NOAA boundary-layer material](https://www.weather.gov/source/zhu/ZHU_Training_Page/clouds/planetary_boundary_layer/PBL.html), [NOAA stability inputs](https://ready.arl.noaa.gov/documents/Tutorial/html/parm_stab.html).

### 5.2 A verifiable thermal circulation

Start with a bounded axisymmetric kinematic circulation, then compare population statistics with [Allen's updraft/sink research](https://ntrs.nasa.gov/api/citations/20060004052/downloads/20060004052.pdf). In upward coordinates about a drifting center:

\[
\Psi(r,z,t)=\tfrac12 A(t)w_c(z)r^2e^{-r^2/R(z)^2},\quad
u_r=-\frac1r\partial_z\Psi,\quad w=\frac1r\partial_r\Psi.
\]

Thus `w=A*w_c*(1-r²/R²)*exp(-r²/R²)`: rising center, sinking annulus, zero infinite-plane vertical flux. Derive radial flow using derivatives of both `w_c` and `R`; use analytic `r=0` limits. Make `w_c` and its derivative vanish at ground/top. If finite support is needed, taper **Psi** with a C2 window (candidate 4R–5R), then differentiate. Test resulting sink and horizontal velocities. This is a proposed closure, not Allen's exact empirical profile or a buoyancy PDE.

Drift uses integrated shared background at a declared representative height. Start with uniform drift; independently translating height slices in shear breaks continuity unless the coordinate transform includes compensating horizontal flow. Lifecycles have deterministic IDs and smooth growth/decay, initially each 15–30% of lifetime. Do not spawn near the camera or always under an aircraft. Resolve birth/death and location independently of queries.

Investigation envelope: radius **10–80 m at flight height**, core updraft **0.3–3 m/s**, lifetime **2–12 min**, mixing height **200–1200 m**. Defaults use only the mild end. In this profile `R` is the zero-crossing radius. Atmospheric thermal size does not scale automatically with aircraft span. A self-balanced circulation must not also get a second uniform environmental sink; choose one closure. Area balance alone does not prove local continuity.

### 5.3 Vertical currents, vortices and severe cases

Uniform up/down air is a useful test away from boundaries, but cannot pass through solid ground. Localized downdrafts need radial outflow/return circulation. Severe shear needs finite thickness. Do not call a sign-reversed thermal a realistic microburst without checking its surface flow and reference evidence.

A regularized eddy reference may use `v_theta=Gamma/(2*pi*r)*(1-exp(-r²/a²))`, with circulation `Gamma` m²/s, core radius `a` m and finite center limit. Declare axis/sign, extent and lifecycle; compactify through a potential and verify boundary flux. It is an authored vortex, not automatically a dust devil, tornado or terrain rotor. Default off. Severe events are bounded opt-in scenarios, not training certification.

### 5.4 Terrain feasibility and staged models

| Feature | Existing support | Missing prerequisite |
| --- | --- | --- |
| Flat-field shear | Ground query, datum, surface rectangles | Explicit aerodynamic roughness and valid domain. |
| Flat-field thermals | Coordinates/time/seed and cues | New circulation/population; authored heat context until measured. |
| Ridge lift | Visual mountain/horizon assets | Shared physical macro-heightfield/normals matching flyable rendered/contact terrain, inflow and domain. |
| Slope/valley winds | No qualified thermal terrain flow | Valley geometry, heating/drainage and stability; local slope alone is insufficient. |
| Obstacle shadow | Scenery/collision inventories | Aerodynamic bounds, porosity, wake class/extent, validated coefficients. |
| Lee rotor | No qualified rotor provider | Terrain/stability/incident-flow domain and separated-flow reference data. |

For a shallow ridge the surface condition is `w=U_h·grad(h)` (NED down reverses sign). It is a **boundary condition**, not a height-independent lift volume. Reuse free offline potential-flow tools/data or a verified shallow-ridge analytic solution with decay. Potential flow does not model separation. Never use tire micro-relief slopes as ridge slopes.

First obstacle cases should be isolated simple geometries. A velocity deficit requires diversion/shear; remaining turbulence variance needs an explicit budget. Smooth wake orientation follows upstream mean flow, not on/off per-stage raycasts. Forest porosity differs from a solid hangar. A general lee rotor also involves boundary-layer separation and stratification; a swirling volume behind any hill is insufficient. [Doyle and Durran](https://doi.org/10.1175/1520-0469(2002)059%3C0186%3ATDOMWI%3E2.0.CO%3B2).

## 6. Aircraft integration and force ownership

### 6.1 Local velocity, forces and moments

Use the **actual state datum O**, not an assumed moving CG. Constant-mass legacy state is CG-based; finite-fuel routes use [FixedDatumBody](../app/physics/fixed_datum_body.gd) with live mass/CG properties. For station offset `r_i` from O:

\[
\mathbf x_i=\mathbf x_O+R\mathbf r_i,\qquad
\mathbf v_{rel,i}^{b}=\mathbf v_{O,g}^{b}+\boldsymbol\omega^b\times\mathbf r_i
-R^T\mathbf W(\mathbf x_i,t).
\]

`v_rel` is aircraft velocity relative to air, not the opposite velocity of fluid over a surface. Existing wash helpers represent their own signed increments; convert induced **air velocity** with the same subtraction convention rather than guessing its sign. Preserve each current wash convention and pin it with a thrust-on test. A surface's orientation then maps the body flow into its chord/normal plane. Use the current section-plane speed law, not total 3D speed indiscriminately for a two-dimensional polar.

For a suitable section, `q_i=0.5*rho_i*V_plane_i²`, `L_i=q_i*S_i*C_L`, `D_i=q_i*S_i*C_D`; lift is perpendicular to plane flow and drag opposes it. Moments are `sum(r_i×F_i + M_ac,i)`. Declare whether loads are about O or current CM and transform exactly once through the existing mass-property path. Do not shift forces to CM in both weather integration and `FixedDatumBody`.

For near-forward flight, `alpha=atan2(w,u)` and `beta=atan2(v,sqrt(u²+w²))`. An upward gust has negative NED D, increases body-relative downward velocity for level forward flight, and initially raises alpha. A crosswind changes beta and local loading; angular response must come from these forces and arms. At zero relative speed angles may be conventionally zero, but forces must follow the existing finite low-speed law. A stationary ground aircraft in wind has nonzero relative speed and can weathercock, unload wheels or tip if aerodynamic loads exceed contact support.

Position remains `x_dot=R*v_ground_body`. Because integrated velocity is ground-relative, **do not add** `-dW/dt` or `-(v·grad)W` to the rigid-body acceleration. Those derivatives arise only when rewriting equations in air-relative state. For diagnostics, encounter change is `dW/dt=partial_t W+(v_ground·grad)W`; it must not become a second gust force.

### 6.2 Compatibility with the empirical/local blend

Replacing all current aerodynamic coefficients with strips would alter every aircraft and exceed this scope. Conversely, changing only `_local_loads` leaves the attached empirical region blind to differential wind. Use a **versioned, opt-in modest-gradient correction** first:

\[
\mathcal L_{aero,new}=\mathcal L_{aero,existing}(W_O)
+[\mathcal L_{sections}(W_i)-\mathcal L_{sections}(W_O)].
\]

`L` is the six-component wrench. The two raw local evaluations share state, geometry, rates, controls, density, ground-effect factors and held wing-downwash state; only ambient station samples differ. These are **unwashed section loads**: propeller slipstream is handled by the separate washed-minus-free increment below. They must be raw matched surface evaluations, **not** nested calls to blended public `Aero.loads()`. An exact uniform-provider branch returns the current implementation without extra arithmetic, preserving its bytes. This is a compatibility bridge, not proof that the global empirical residual remains physically correct for every gradient.

Initial implementation sequence:

1. Add a stage flow bundle and independent constant/linear-field fixtures. Reuse six wing stations, horizontal tail, vertical tail and hub/intake; body/reference point remains explicit. Derive points from existing normalized aircraft geometry.
2. Add matched ambient deltas for wing/tail loads with downwash state held identical. Diagnose full left/right and wing/tail samples. Fuselage terms may remain at the reference point initially; label that approximation, then add validated body stations if evidence requires them.
3. Sample hub/intake ambient wind at its point; existing `omega×r` remains once. Recompute the existing propulsion law with that inflow rather than adding a generic propeller wind force. Every shaft, glow, electric, battery and turbine adapter must use the same stage bundle.
4. Evaluate slipstream as **washed local tail minus unwashed local tail**, both with the same ambient field. Either replace the old increment once, or use a strictly matched spatial-minus-uniform increment; never do both. Reuse the same stage thrust/torque and transported wash.
5. In a separately explained law revision, derive the dimensional wing wake source from spatial strip flow and migrate its lag/trace identity. Do not change ambient gradients and the wake closure invisibly in one candidate.
6. Before strong gradients/one-wing stall/reversed-flow scenarios ship, make transition selection inspect all relevant local flows and validate a local/residual formulation through attached/stalled/blended regimes. Do not abruptly switch to a completely different model when a gust crosses a threshold. Keep a documented gradient-domain limit on the first bridge.

The guard for the bridge is physical-domain based: monitor maximum station angle deviation, local flow reversal and relative dynamic-pressure spread. Candidate investigation thresholds are `max |delta alpha_i| <= 3°`, `max |delta beta_i| <= 3°`, and `max |q_i-q_ref|/max(q_ref,q_floor) <= 0.25`, with no reference/individual strip crossing its stall boundary. These are **provisional eligibility criteria**, not numerical clamps. Refuse incompatible factory scenarios until the broader law is qualified; user custom scenarios can be marked experimental but must still remain numerically bounded. Do not clamp local flow to force a scenario into the bridge.

### 6.3 Force ownership table

| Quantity/effect | Sole owner | Must not also happen |
| --- | --- | --- |
| Ambient NED velocity, thermals, terrain disturbance | Environment/weather provider | Weather applying body forces, moments or rotations. |
| Reference and point air-relative velocity | Stage flow builder / existing air-data functions | Wind subtraction in both builder and surface law. |
| Wing/tail/body loads and arms | Aero, with matched delta during transition | Full local loads added over full empirical loads; extra random gust moments. |
| Propeller/turbine loads and induced flow | Existing propulsion/slipstream/transport laws | Atmospheric service applying thrust or injecting aircraft wake into mean wind. |
| Density and dry charge | Atmosphere and existing powerplant adapters | Independent weather/aircraft density or engine-power multipliers. |
| Ground effect | Existing opt-in aerodynamic module | Boundary-layer wind masquerading as lift bonus. |
| Contact/friction/wheel velocity | Ground physics | Subtracting wind from tire-ground velocity. |
| Integration/gravity/live mass | Shared Simulation and current body evaluators | Weather modifying position/velocity outside the solver. |
| Cues, smoke, audio and aids | Read-only presentation | Shader/particle noise feeding back into aircraft dynamics. |

### 6.4 Flight phases and RC interpretation

Steady uniform wind does not inherently make a free-flying airplane bank or turn; equal air-relative states have equal loads. Ground track drifts. Crab means heading into the wind while retaining near-coordinated airflow; a wing-low slip uses sideslip and aerodynamic side force. The touchdown transition must follow wheel contact and ground-relative side velocity, not an automatic heading snap. Taxi loads remain active in moving air even at zero ground speed. [FAA crosswind techniques](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/10_afh_ch9.pdf), [AMA RC landing approach](https://www.amaflightschool.org/getstarted/how-do-i-master-landing-approach).

At takeoff/landing, ground shear changes local airspeed as height changes; propwash can retain tail authority at low forward speed. At aerobatic attitudes use existing full-angle/local-flow limits, not small-angle gust formulas. Increasing wind is not a substitute for validating inverted, knife-edge, stalled or backward flow. Differential wing loading must remain symmetric under mirrored aircraft/weather fixtures.

For soaring, ground climb is approximately `thermal updraft - aircraft still-air sink` after transient adjustment, not simply thermal velocity. In uniform horizontal wind, gliding airspeed/polar do not improve. Define ground-referenced mechanical energy `E=m*g*z+0.5*m*|v_ground|²`; wind can exchange energy through aerodynamic work. An airspeed-based total-energy vario needs an explicit derivative and sensor model; it is not an oracle thermal detector. Start with true-state diagnostic climb/TAS/energy and label optional netto estimates until the aircraft sink polar is validated. No sailplane qualification can be claimed from an engine-off trainer alone.

## 7. Versioned architecture, configuration and pseudocode

### 7.1 Minimal necessary extension

Retain the existing dependency flow:

```text
validated weather + field metadata + physical forcing timeline
                    -> immutable atmosphere provider
Environment -> per-stage point samples -> aircraft evaluator -> wrench -> Simulation
            -> committed observer samples -> UI / windsock / smoke / sound
```

Proposed additions under the existing `app/physics/wind_*.gd` ownership: schema/resolver, spatial field, profile, spectral field, gust agenda and thermal primitives. Names are proposed, not existing files. `sim/environment.gd` remains the public shared access point; `wind_field.gd` is the legacy provider/compatibility adapter. Do not introduce a scene-tree `Area3D` per gust, a second physics engine or a global mutable singleton clock. A shared resource/service instance may be session-managed without being a Godot spatial node.

Conceptual API (pseudocode, not an implemented class):

```text
WindField3D.sample_world(position_ned_f64, sample_clock, output_f64, flags) -> status
Environment.sample_air_world(position_ned_f64, sample_clock, output_f64) -> status
Environment.sample_air_points(packed_positions, sample_clock, outputs) -> status
Environment.identity() -> immutable versioned receipt
```

Required sample data: ambient `W_NED[3]` m/s, density kg/m³, dry-charge ratio, valid/domain status, sample position and tick/stage/time. Optional diagnostic data: mean/gust/turbulence/thermal/terrain vectors, `gradW[9]` in s⁻¹ with documented row/column order, partial-time derivative m/s², temperature K, pressure Pa, source IDs and AGL. Rich dictionaries belong in setup/diagnostics; the hot path uses preallocated packed arrays/scalars. Do not construct a dictionary per strip per mode per RK stage.

`sample_world` is pure, finite inside its declared domain, independent of caller/order/LOD and repeatable for identical position/time/identity. Invalid inputs propagate a structured failure into existing fail-closed transaction handling. A default “zero wind on any error” would conceal faults. Negative AGL and undefined macro-terrain must be distinguishable from valid calm. Queries do not advance RNG, age cells, commit edits or publish state.

### 7.2 Configuration contract

Reserve a proposed new weather schema only at implementation after checking then-current versions; **`openrc-weather v5` below is a proposal**, not an accepted file format. Maintain old v1–v4 schemas exactly. Canonical keys and units should be explicit:

| Block | Required resolved contents |
| --- | --- |
| Identity | Format, provider law/version, seed algorithm/version, uint32 root seed, source/provenance, preset ID/revision, canonical content hash. |
| Frame/time | NED local datum, field ID/hash, elevation datum, world epoch tick, fixed-step rational seconds, supported spatial/time domain. |
| Mean/profile | Reference FROM bearing/speed or canonical NED vector, reference AGL, profile law, z0/d/lower/top limits, ordered layer vectors/basis, smooth change agenda. |
| Gusts | Mode, component sub-seed, event generator version, duration/interval/amplitude distributions with bounds, spatial extents, envelope/propagation law, resolved events or reproducible agenda receipt. |
| Turbulence | Exactly one active backend, tensor/spectrum version, RMS frame and covariance, scales m, min/max wavelengths, mode count, intrinsic evolution/advection law, wall treatment. |
| Thermals | Enabled, model version, heating mode, B0/zi or authored parameters, center/radius/height/lifecycle distributions, birth-region/spacing rule, drift, mass-return closure, independent sub-seed. |
| Terrain | Provider/asset hashes, physical height/roughness/obstacle metadata, supported flow domain, model coefficients/provenance and correction/total-flow convention. |
| Atmosphere | Existing validated reference/custom/standard-column block; optional future thermodynamic-law ID. |
| Coupling | Explicit physical sun/cloud timeline or independent authored forcing; source identity. Presentation-only settings stored separately. |

Boundary validation includes finite numbers, units, positive scales, sorted/nonduplicate heights, minimum transition thickness, valid domain and flat-site constraints, PSD-positive covariance, coherent component budgets, maximum events/modes/overlap, capability support and unknown-key rejection. No permissive “best effort” load of a new physics law. Canonicalization must retain unedited numeric precision. Resolved configurations include all defaults; do not rely on changing software defaults to reconstruct old sessions.

Aircraft schema stays v2. Optional station detail is derived from existing `aero.surfaces`, geometry and powerplant offsets; a new optional authored extension must pass aircraft-contract/generator review. No aircraft stores its own weather process. Aircraft without adequate stations use the legacy/reference-point capability and cannot claim distributed gust qualification.

### 7.3 Stage evaluation and transactional ownership

```text
launch:
  validate and resolve scenario, physical field metadata and capabilities
  build immutable provider and frozen event/mode descriptors
  validate starts against provider at launch point/time
  install provider through Environment; record complete identity

evaluate(stage_state, stage_continuous, stage_clock):
  x_O, R, v_O_ground, omega = existing_float64_state(stage_state)
  points = station_world_positions(x_O, R, model_station_offsets)
  air_samples = Environment.sample_air_points(points, stage_clock)
  require all samples valid
  flows = v_O_ground + omega_cross_offsets - transpose(R)*air_samples.wind
  reference_air = air_data_from_reference_flow(flows.reference)
  if provider.is_legacy_uniform:
      return existing_evaluation_exactly_as_before(...)
  aero = matched_spatial_aero(reference_air, flows, held_downwash, ground_factors)
  power = existing_powertrain_evaluation(flows.hub_or_intake, stage_continuous)
  wash_delta = washed_minus_free_tail(flows.tail, power.same_stage_wake, ...)
  contacts = existing_ground_relative_contacts(stage_state, ...)
  return existing_load_and_derivative_assembly(aero, power, wash_delta, contacts)

commit accepted tick:
  publish bounded observer samples and state
  advance only explicitly stateful owner data transactionally
  record epoch/edits/identity and any state required for exact continuation
rollback:
  restore all owner state and published time; discard derived stage caches
```

Old OU stays in its current sampled auxiliary/mode state. New finite modes and analytic agendas should be stateless functions of immutable identity and absolute world time. For advected features, either analytic/pre-resolved paths or a shared weather trajectory with checkpointed state is required; integrating advection separately inside each aircraft reintroduces incoherence. Pause and aircraft reset need a declared policy: ordinary single-flight reset resets world epoch; resetting one companion does not reset the common weather. Joining later samples the current world epoch.

Do not use `(tick, stage_index)` alone as a cache key: two RK midpoint calls have the same time and different positions/states. Cache only immutable mode coefficients and identical-position/time queries, keyed by world/config epoch and coordinates. Density at a common body datum can be reused within a stage if explicitly approximated uniform across the aircraft; wind gradients cannot. Invalidate caches on world reset, restore, field/config change and provider revision.

### 7.4 Persistence, migration and shared aircraft

Load old weather with the old arithmetic, old NED OU axes and old RNG consumption. Never reinterpret tau as a spatial length or change old seeds. New presets get new IDs; keep `gentle-practice` unchanged. Apply the new product default only to fresh preferences or an explicit user selection. “Factory weather” restores the chosen shipped revision; “Make default” affects future launches, not a flight recording.

Preserving law output does not authorize bypassing `.orfl` solver-source checks. Verify original exact replay with its matching source/engine first. Compare the candidate's legacy mode against frozen baseline state/load fixtures, and retain a matching-build route for old exact logs when source identities differ. Export/read compatibility and identical numerical behavior are separate from accepting a recording under a new solver fingerprint; an intentional law migration must never masquerade as original exact replay.

Advance preference schema deliberately, preserve newer-file non-overwrite behavior, and retain invalid files for diagnosis. Version scenario documents separately from weather and preferences. Update Natural Random's v3 restriction through an explicit recipe capability/version; saved old resolved scenarios remain unchanged. Update trace/checkpoint/flight-log readers as a coordinated schema change, including endpoint versus load-stage sample positions. Preserve original source/config identities; do not merely increment a header while silently changing the solver.

For AFC, retain current gentle/reference-air eligibility until requalified. New spatial mode removes per-slot weather reseeding and supplies the same immutable provider/epoch to player and companions; pilot RNG remains independent. Nearby points correlate according to the field, and coincident point/time queries must match exactly. Existing companion capture is not shared-world exact replay: add a separate fleet receipt/clock policy before claiming that feature. Helicopter and ground activities retain their own capability gates; a shared interface does not imply automatic support for every atmosphere mode.

Interactive changing weather first means a timeline resolved **before launch**. Live edits should initially retain the current reset-required behavior. A later scheduled transition can be queued at an accepted tick, validated before mutation, recorded as an event, and blended over a specified duration. It must not rewrite past field values or invalidate an in-flight recorder silently.

## 8. Defaults and fully resolved preset proposals

### 8.1 Default policy and physical rationale

Keep current `gentle-practice` as the installed compatibility preset. Introduce `realistic-default-v1` only after P1 acceptance; add thermals to a **new preset revision** after P2, enabled only with a suitable physical daytime context. Fresh users get a gentle, oblique prevailing wind, mild gusts and low residual turbulence; existing preferences and technical routes do not change automatically. Dead Calm remains directly available for beginners, calibration and deterministic fixtures.

Candidate default search ranges: reference mean **1–2 m/s**, runway crosswind **0.2–0.6 m/s**, along-wind gust peak **0.3–0.7 m/s**, cross-gust peak **0.1–0.25 m/s**, residual RMS approximately **[0.10–0.20, 0.08–0.15, 0.04–0.10] m/s** in mean-flow along/cross/up axes. No universal physical standard selects these numbers: they are conservative starting conditions near the existing authored profile, chosen to test subtle corrections without forcing instability.

At 12 m/s forward airspeed, an isolated 0.1 m/s vertical perturbation gives a small-angle `delta alpha≈0.48°`; at 6 m/s it is about `0.95°`. A 0.39 m/s crosswind needs approximately `asin(0.39/12)=1.86°` crab in level constant-speed track holding. These kinematic estimates explain the initial envelope, but actual control workload depends on stability, mass/inertia, wing loading, geometry and control authority. Use `sigma_w/V`, `W_cross/V_approach`, `L/span` and reduced frequency `k=omega*c/(2V)` as comparison diagnostics. **Never scale the atmosphere per aircraft to equalize difficulty.** Offer an explicit easier preset when needed.

### 8.2 Shared resolved defaults for the new preset family

The following definitions plus each row's overrides are complete **design specifications**, not currently loadable weather JSON. Every omitted effect is explicitly off. All bounds are authored estimates pending validation; “default” below means the proposed factory candidate, not measured site weather.

| Block | Shared value |
| --- | --- |
| Root identity | New weather law; factory revision 1; root seed `20261025`; independent versioned substreams for modes, gusts and thermals. Keep a fixture of resolved descriptors, not only a seed. |
| World | Field local NED; epoch tick 0; flat-site domain N/E ±2000 m, AGL 0–1200 m for initial qualification. Leaving a bounded provider domain gives explicit invalidity before launch/flight can silently continue; a later global provider must be separately declared. |
| Air | Existing literal reference air; custom uniform air remains an independent override. Standard-column plus new vertical circulation requires the §4.5 mass-consistency gate. Default physical daylight context is disabled until P2; no dependence on visual evening. |
| Profile `N` | Neutral flat short-grass: `z_ref=10 m`, `z0=0.03 m`, `d=0`, wall blend to `z_min=0.3 m`; log valid to 50 m; C2 join over 50–100 m to the value at 50 m, constant above. `U` below means reference speed at 10 m. |
| Profile `F` | Uniform wind, no ground profile; test/legacy/calibration use only. |
| Turbulence `S` | Proposed 32-mode solenoidal field; 2 m minimum/200 m maximum wavelength; scale vector in mean-flow axes supplied below; RMS supplied below measured at 10 m. Intrinsic evolution candidate 30 s at energy-containing scale, shorter toward high wavenumber with an explicit 2 Hz cap; wall-compatible potential envelope below 2 m, then constant. All resulting statistics must be recalibrated after wall shaping. |
| Mode construction | Log-spaced radial bins, seeded stratified directions/polarizations/phases; bounded spectral tensor fit to target covariance/scales; publish actual discrete tensor and 1D cuts. Version/pin fitting coefficients. Until that fit passes §11, label `synthetic_solenoidal_v1`, not exact Dryden/von Kármán. No silent fallback to OU. |
| Gust `A` | Resolved smooth events with deterministic bounded draws. Along/cross amplitudes in table are maxima; draw magnitudes uniformly from 0.5–1 times max and cross sign equally. P1 spatial gust prototype uses broad coherent structures of nominal radius 100 m, smooth support to 300 m, based on a vector potential; amplitude is the calibrated peak at reference height. Global temporal gust remains a separately labeled test option. |
| Gust scheduling | Draw next start-to-start interval uniformly from table bounds, duration uniformly from its bounds; ensure interval ≥ duration. Initial delay 5 s. Scenario resolution rejects overlaps exceeding two events. No repeated fixed period unless the test preset explicitly asks for it. |
| Vertical gust | Zero in these new factory presets; vertical energy comes from `S`, thermals or the named circulation model. Legacy positive pulses unchanged. |
| Thermals | Off unless a thermal profile below is selected. No extra uniform sink over a self-balanced profile. |
| Mean evolution | Constant unless row overrides. No unsolicited wind-direction random walk. |
| Terrain/obstacle/vortex | Off unless explicitly specified by a qualified fixture. No visual mountain inference. |
| Interface | No wind arrows/thermal volume by default; windsock and normal ambience on. Diagnostic truth overlays opt-in. |

`S` scales are correlation targets, not three independent Dryden filters. Implementations must report the achieved tensor/coherence; a preset cannot be declared fully qualified merely because its numeric fields parse. RMS near the wall will differ from its reference-height target. Mode count and physics cutoffs are part of law/configuration identity, never graphics quality.

Thermal profile `M`: self-balanced streamfunction, `R=30 m` at 100 m AGL, smooth radius growth from 10 m near the lower envelope, top `zi=400 m`, peak core `0.6 m/s` near 0.3zi, lifetime 300 s, 20% growth and decay, one birth each 75 s, maximum four live cells, deterministic jittered/stratified centers in N/E ±500 m. Use prehistory to initialize a mature population; serialize prehistory event IDs. Physical condition: authored mild positive heating (candidate `B0=0.0015 m²/s³`, giving `w*≈0.84 m/s`), sun elevation 50°, cloud fraction 0.25. These inputs are a consistent candidate envelope, not a uniquely derived plume population. Night/unsuitable heating selects the explicitly thermal-off variant.

Thermal profile `Q`: same law, `R=45 m` at 150 m, lower radius 15 m, `zi=800 m`, peak 2 m/s near 0.3zi, lifetime 480 s, birth every 80 s, maximum six live cells, 20% growth/decay; centers ±500 m; authored `B0=0.006 m²/s³` (`w*≈1.69 m/s`), sun 60°, cloud fraction 0.2. Drift is shared mean wind at 0.3zi. Exact height profiles use C2 envelopes and resolved coefficients included in fixtures. Strong-core frequency, net sink and overlap require validation before accepting these values.

### 8.3 Factory presets

Let `psi_runway` be the selected **launch runway's** true heading. Resolve offsets to absolute FROM bearings on launch and save the result; a subsequent runway selection must visibly re-resolve a draft, never secretly change a running field. Along/cross gust maxima are `G_a/G_c`, residual RMS is `[along,cross,up]`, scales are `[L_a,L_c,L_z]` m. Positive crossflow means wind transport toward runway right; FROM `psi+15°` transports toward runway left. UI must display this distinction correctly.

| Preset / proposed ID | Mean and profile | Gust maxima; duration; interval | Turbulence RMS; scales | Other fully resolved override / availability |
| --- | --- | --- | --- | --- |
| **Dead Calm** / `dead-calm-v1` | U=0, F | 0/0; disabled | [0,0,0]; disabled | All atmospheric motion off, reference air. Return existing calm path exactly; P0/current capability. Custom density may be selected independently but is no longer the exact reference fixture. |
| **Realistic Default** / `realistic-default-v1` | U=1.5, FROM psi+15°, N | 0.45/0.15 m/s; 3–6 s; 14–24 s | [0.15,0.12,0.06]; [20,10,4] | Mean headwind ≈1.45 and crosswind ≈0.39 m/s at reference height. P1 has no thermals; P2 revision 2 selects M in suitable physical daytime. No terrain/vortex. |
| **Gentle Breeze** / `gentle-breeze-spatial-v1` | U=2, FROM psi, N | 0.2/0.05; 4–7 s; 20–35 s | [0.08,0.06,0.03]; [25,12,5] | Thermals off, steady stable-feeling practice; neutral profile explicitly approximate. P1. Distinct from existing `gentle-practice`. |
| **Crosswind Training** / `crosswind-training-v1` | Headwind=1, crossflow-right=1 m/s at 10 m; derived U=1.414 and absolute bearing, N | 0.2/0.2; 3–5 s; 15–25 s | [0.08,0.08,0.04]; [20,10,4] | Thermals off. Training crossflow editable −5…+5 m/s and headwind −2…+5; zero-gust/zero-turbulence switch for initial lessons. P1; higher values require aircraft/gradient capability. |
| **Gusty Afternoon** / `gusty-afternoon-v1` | U=3.5, FROM psi+25°, N | 1.0/0.4; 2–5 s; 8–16 s | [0.35,0.25,0.18]; [15,8,3] | P1 pilot candidate without thermals; P2 revision can add M after variance/handling requalification. No terrain. |
| **Thermal Soaring** / `thermal-soaring-v1` | U=1.5, FROM psi, N | 0.2/0.1; 4–7 s; 20–35 s | [0.10,0.08,0.08]; [25,15,5] | Q thermal profile; sink and drift integral to field. P2. Powered engine-off trials first; sailplane acceptance blocked on a validated model. |
| **Ridge Soaring** / `ridge-soaring-fixture-v1` | U=6 at 30 m above upwind flat datum, wind normal into ridge; qualified ridge inflow replaces N | 0/0; disabled | [0.15,0.12,0.08]; [30,20,8] upstream, with boundary-consistent correction | P3 fixture: 30 m high, 120 m half-width smooth ridge, crest along E, height `30*exp(-(N/120)^2)` m, extent E ±1000 m with bounded end treatment. Matching physical/rendered terrain required. Attached-flow approximation only; no automatic lee rotor. |
| **Wind Shear** / `wind-shear-v1` | Lower U=2 FROM psi to 20 m; C2 layer transition 20–60 m; upper U=6 FROM psi+30°; near ground N normalized to lower U | 0/0; disabled | [0.10,0.08,0.05]; [20,10,4] | No thermals/terrain. P1 analytic field fixture; public challenge only after P2 strong-gradient aerodynamic validation. Advanced controls alter vectors and thickness, never an acceleration impulse. |
| **Rotor & Turbulence** / `lee-flow-fixture-v1` | U=6 at the ridge inflow reference; same geometry as ridge case | 0/0; disabled | Background [0.15,0.12,0.08]; [30,20,8] | **Unavailable until P3** reference asset supplies full bounded lee correction, covariance, stability profile and hashes. No invented factory rotor coefficient. A separate authored eddy may be offered explicitly as an analytic fixture, never substituted under this name. |
| **Strong Wind Challenge** / `strong-wind-v1` | U=7, FROM psi+20°, N | 1.5/0.6; 2–4 s; 8–14 s | [0.5,0.35,0.25]; [20,10,4] | Thermals/terrain off. P2 strong-gradient/load-response gate plus aircraft launch feasibility. No promise that every aircraft can hold position or take off. |
| **Custom Weather** / `custom` | Exact clone of selected resolved preset | User edits independently validated blocks | User selects one backend and explicit units | No hidden defaults on reload. Initial new Custom starts as Realistic Default P1 with thermal/terrain off; old custom documents remain old laws. Unsupported combinations refuse with specific reasons. |

“Fully specified” does not justify fabricating a rotor dataset: its row defines the missing required fixture and remains unavailable. All other proposed generated presets require committed generator-version/descriptor fixtures before runtime acceptance. Test and document the difference between randomized **resolution at launch** and random per-query behavior.

Advanced severe-shear fixture: lower wind 2 m/s FROM runway, upper 8 m/s FROM runway+60°, C2 transition 30–50 m AGL, all other disturbances zero. Localized strong-downdraft fixture: reversed balanced circulation with peak −3 m/s, radius 60 m, vertical envelope 0–300 m, 60 s lifetime with 15 s rise/fall, center 200 m ahead of runway threshold and 100 m to the side, seed fixed, background 3 m/s FROM runway. Both stay experimental until the full local-flow, ground-boundary and timestep tests pass. The downdraft is an analytic circulation exercise, not a validated microburst.

### 8.4 Aircraft-specific evaluation without aircraft-specific weather

| Representative | Existing candidate | Required assessment |
| --- | --- | --- |
| Sport trainer | Ugly Stik family | Neutral stability and correction workload; runway drift, takeoff hold, straight approach, go-around; no unexplained self-excited motion. |
| Aerobatic | Extra 300S | Local wing/tail response in upright/inverted/knife-edge and roll maneuvers; weather response remains force-driven through attitude changes. |
| Light/STOL | Turbo Lumber | Low-speed gust alpha, flap/propwash interaction and touchdown unload/tip behavior; do not call it a validated ultralight surrogate. |
| Higher loading/inertia | P-51D, F4U and jet | Same atmosphere at higher encounter speed; load-frequency/prop-intake checks and numerical bandwidth. |
| Sailplane | No catalog model | Obtain suitable free, licensed model/data where available, then aircraft-contract/polar validation; first use engine-off cases only for mechanism verification. |
| Very lightweight RC | No dedicated catalog model | Separate measured mass/inertia/polar fixture and pilot evaluation; default may be too demanding even when suitable for Stik. |

For the default, accept a 10-minute seeded circuit/landing set only after pilot testing across the first three classes shows intermittent, understandable corrections without unexplained stalls or control saturation. Log correction duty cycle, RMS controls, bank/pitch excursion, path error and stalled-strip events. Set a provisional nonmaneuvering roll/pitch disturbance target of roughly 1–3° RMS with no automatic flight stabilization; treat it as a **review band**, never a controller or weather amplitude feedback target. Aircraft dynamics, trim and pilot input can move these values. A failed aircraft-specific case triggers diagnosis or a suggested calmer preset, not a hidden per-aircraft wind multiplier.

## 9. UI, training, cues and configuration

### 9.1 Evolve the existing Conditions dialog

Keep `WeatherDialog`'s transactional draft/Apply/Cancel, paired exact numeric inputs, keyboard/controller focus and EN/ES conventions. The initial page should expose preset, wind speed at reference height, FROM direction, runway component preview, and compact gust/turbulence/thermal summaries. A single Advanced control reveals profile/layers, RMS/scales, seeds, thermal population and atmosphere. Use the existing tab/scroll framework; a large new card grid is unnecessary unless 1080p usability testing demonstrates a benefit.

Basic turbulence strength maps to explicit shown RMS targets in the resolved configuration; advanced mode shows frame and scales. Do not label RMS as peak, interval as frequency without units, or a positive vertical pulse as thermal activity. Display background wind, expected gust increment and reference height distinctly. Show disabled terrain presets with the missing landscape/model capability; avoid an available-looking selector that silently produces ordinary wind.

For runway unit vector `h=[cos psi,sin psi,0]` and right vector `r=[-sin psi,cos psi,0]`, show `headwind=-W·h` and `crossflow_right=W·r`. Also label where wind **comes from**: positive rightward transport is wind from the left. Show components at runway/reference height and optional current aircraft location; do not confuse pilot left/right view with runway left/right. A bearing dial and tiny vector profile can explain the data without scientific jargon. Crab guidance derives from track/heading/airspeed, not from body-frame saved weather.

Advanced layer editor: rows for height, reference basis, speed and FROM direction, plus a profile preview and transition thickness. Sort/validate knots explicitly; preserve typed precision. Thermal editor exposes strength, scale, lifecycle and physical forcing as linked explanations; the return circulation is part of the chosen law, not an independent arbitrary sink slider. Allow expert overrides only within a valid model contract.

Add named **Save conditions**, **Load conditions**, **Restore preset**, **Make launch default** and **Restore factory weather** with distinct semantics. Cancel changes nothing. Save/load use validated versioned scenario documents; factory reset affects weather preferences only, not radio, aircraft, statistics or unrelated settings. Applying during flight initially explains that a new flight is needed, following current behavior. No new approval flow is required beyond the existing product transaction.

### 9.2 Training and feedback

Training cards: steady head/tail/crosswind drift; crab then wing-low touchdown; gust approach/go-around; taxi weathercocking; wind-gradient approach; uniform updraft/sink verification; thermal centering/exit; ridge track after terrain qualification. Each card freezes aircraft/configuration, start, seed, duration, input/pilot mode and metrics. Begin crosswind lessons with no gusts/turbulence, then independently add one disturbance. [AMA approach guidance](https://www.amaflightschool.org/getstarted/how-do-i-master-landing-approach) supports runway/pilot-station ground references; it does not calibrate simulated control forces.

HUD additions should be optional: TAS and ground speed, heading/track/crab, beta, runway head/crosswind, AGL, local vertical air, aircraft climb, load factor and energy/vario diagnostics. Label true-state wind/thermal information as a training aid rather than an actual onboard instrument. A physical variometer reads aircraft response and lag; a debug heatmap knows the field directly. Display recorded events with corresponding source sample times.

### 9.3 Visual/audio consumers

- Windsock: sample at its actual sleeve/mast position each committed tick; feed existing motion/inflation model. Preserve its own visual damping without smoothing aircraft physics.
- Arrows/thermal volumes: bounded debug grid with fixed world sample coordinates and legend; optional training-only thermal core/sink display. Invisible dry thermals remain possible; visible clouds are not perfect thermal markers. [NOAA turbulence guidance](https://www.weather.gov/source/zhu/ZHU_Training_Page/turbulence_stuff/turbulence/turbulence.htm?lv=true).
- Smoke: CPU-authoritative field samples feed a bounded visual grid or emitter/segment sampling. GPU particle flutter remains dispersion detail. A tracer crossing shear should follow sampled advection; do not claim particle-scale CFD or exact visual replay unless implemented.
- Vegetation/clouds: reuse shared coarse field for local bend/transport. Cosmetic leaf flutter uses independent visual RNG. Cloud layer advection may sample mean at layer height; legacy independent aloft appearance remains explicitly visual.
- Audio: ambient wind at listener/pilot station, fabric at windsock, aircraft airflow at the aircraft. Keep smoothing/gain curves and existing licensed recordings. Avoid perpetual strong whoosh in light air or an audible thermal beacon unless the user enables a training aid. Acoustic propagation in moving air is a separate later feature, not required for atmospheric force correctness.

Verify at **1920×1080 first**, then higher resolutions, then 720p fallback; include EN/ES expansion, keyboard/controller focus, long numeric entries and scroll behavior. Use existing debug-bridge UI/capture workflows. Readability, listening and pilot acceptance require actual sessions; code inspection alone cannot close them.

## 10. Phased implementation roadmap and change ledger

The rows below are proposed extensions/repair substeps within existing M5 namespaces, not claims of completed work. Reconcile final substep names with track owners before implementation. Complexity is relative engineering effort: **S** isolated change/fixture, **M** several coordinated modules, **L** broad physics/integration with independent validation, **XL** infrastructure plus physical-data dependency. It is not a delivery-date promise. Every row includes current state, correction, physics/strategy, affected code, dependencies and proof.

### P0 — Physics correctness and contracts

| Proposed ID | Today → correction and implementation | Affected code / ownership | Complexity, dependency | Required verification |
| --- | --- | --- | --- | --- |
| M5-W05b-R1 | Time-only field → pure position/time API with exact legacy adapter; no new default yet | `sim/environment.gd`, `physics/wind_field.gd`, session/vehicle adapters; SF/M5 | M; audit all consumers and freeze baseline | Same v1–v4 samples and full-state fixtures byte-identical; constant/linear fields; actual RK midpoint positions; rejected samples leave state unchanged. |
| M5-W05c-R1 | Common ambient flow at all surfaces → station geometry and matched modest-gradient aerodynamic delta | `physics/aero.gd`, `dynamics.gd`, `air_data.gd`; AS/physics | L; W05b-R1, aircraft geometry and live-datum conventions | Uniform bypass, analytic antisymmetric gust moments, rate-arm-only parity, no duplicated tail/wash or CM shifts. |
| M5-W05c-R2 | Hub/intake rotational flow with common wind → local ambient flow across all powertrain/ground paths | `propulsion.gd`, `turbine.gd`, `slipstream.gd`, `wash_transport.gd`, `glow/flight.gd`, session coupled/fuel/electric evaluators; propulsion/GP | L; stage bundle from R1 | Prop-on/off, standing crosswind, runway trim and all admitted aircraft routes; same-stage thrust/torque reuse and reaction moments. |
| M5-W01d-R1 | Mature uniform traces/checkpoints → spatial identity/sample metadata and compatibility readers | Session checkpoint/configuration, `trace.gd`, flight-log modules/readers, CLI; FL/M5/SF | L; schema reserved after current-version audit | Old exact logs remain supported/refused for explicit identity reason; new restore preflights before mutation; coordinates, load-time and endpoint values independently recompute. |
| M5-W05b-R2 | Companions reseed OU → common immutable field/epoch in new mode, old mode retained | `ai/companions/agent.gd`, `manager.gd`, fleet recording, Environment; AFC/SF | M/L; W05b-R1 and new qualification profile | Coincident point/time identity; stepping/query order invariance; joining/reset semantics; unsupported weather refuses. Fleet decision replay remains a separate deliverable. |
| M5-ATM-4-R1 | Dry column exists but some docs stale → reconcile law/altitude/trace claims and preserve density ownership | `WIND-PLAN.md`, existing atmosphere guide, session integration; ATM/UI | S; current-source verification | Guide matches v4/standard-column code; AGL/geometric/EAS distinctions; no duplicate density/charge factors. |

P0 exit: legacy behavior preserved, force ownership auditable, pure field API and synthetic spatial fixtures verified across the current admitted fleet. No claim of natural turbulence yet. Preserve `.orfl` baseline and verify exact replay before aerodynamic candidates; documented expected differences are compared on the same input tape.

### P1 — Realistic mean wind, coherent gusts and default candidate

| Proposed ID | Today → correction and implementation | Affected code / ownership | Complexity, dependency | Required verification |
| --- | --- | --- | --- | --- |
| M5-W05a-R1 | No wind height dependence → neutral flat-site profile, bounded wall join and authored layers | Proposed wind profile module, `Environment.terrain`, config; M5/GP | M; P0, explicit roughness and domain | Reference-height equality; continuity/slopes at joins; no wall penetration; invalid terrain/domain rejects; layer direction wrap. |
| M5-W02c-R1 / M5-W03a-R1 | Fixed periodic same-heading pulse → resolved irregular gust agenda and slow vector shifts | Proposed gust/timeline modules, config/session; M5 | M; P0 identity | Analytic pulse area/derivatives; agenda independent of queries; overlap/mean ledger; no discontinuous turn at 359°→1°. |
| M5-W05b-R3 / M5-W06a | Temporal OU only → bounded solenoidal modes and Dryden/von Kármán reference comparison | Proposed spatial kernel; `bench_wind.gd`, wind tests and existing research tooling; M5/PT | L; P0, target tensor, wall treatment, independent reference | RMS/PSD/covariance/coherence, fixed vs moving probes, calm evolution, mode/wavelength refinement, complete-field divergence. |
| M5-W03b-R1 | Technical tab-first controls → simple preset/crosswind preview, advanced disclosure, saved scenarios/defaults | `weather_dialog.gd`, `home.gd`, `preferences.gd`, i18n, CLI; UI/NR | M; schema resolver, P1 factory candidates | Round trips/invalid files/Cancel precision; direction signs; actual 1080p EN/ES controller flow. |
| M5-W07-R1 | One uniform presentation vector → correct local observer samples | `main.gd`, windsock/field/world/shader clock, audio, smoke; FW/SM/AUD | M; spatial API | Cues at distinct heights/positions agree with provider; observers never change physics fingerprint; pause/reset behavior. |
| M5-W04a-R1 / Gate W-B extension | Gentle temporal default exists → new mild spatial candidate and fleet/pilot evaluation | Presets and existing flight tools; M5/UI/aircraft | M plus pilot dependency; all above | Measured workload and landing behavior, target CPU budget, reversible explicit preset selection. Enable fresh-user default only after acceptance. |

P1 exit: mild common field is continuous and bounded, deterministic and affordable, produces differential loads in its qualified domain, and passes W-A/W-B handling review. The plan calls for a better default, but implementation must not turn it on merely because the feature parses.

### P2 — Convection, advanced atmosphere and wider aerodynamic domain

| Proposed ID | Today → correction and implementation | Affected code / ownership | Complexity, dependency | Required verification |
| --- | --- | --- | --- | --- |
| M5-W05c-R3 | Modest-gradient bridge retains CG-based residual/lag → local validity transitions and spatial wing-wake source | `aero.gd`, downwash state/session adapters, aircraft generators if needed; M5/AS/propulsion | L; P0/P1 response evidence | One-wing stall/reversal, tail-only gust, blend continuity, wake delay, no residual/damping double count; intentional law/trace revision. |
| M5-W08-R1 | Global Updraft pulse only → self-balanced finite thermal/downdraft circulation with drift/lifecycle | Proposed wind thermal/population modules, config; M5 | L; coherent field, domain/flux tests | Analytic divergence/flux/wall limits; core/ring/edge trajectories; lifecycle/replay; energy/polar comparison. |
| M5-W08-R2 / M5-ATM-4-R2 | Lighting separate and no heat model → optional physical forcing timeline and consistent stability context | Weather resolver, atmosphere extensions, time/sky adapters; ATM/TOD/FW/NR | L; heating metadata and reference sources | Day/night heat lag, cloudy/clear and surface fixtures; visual edits cannot alter accepted physical weather; no hidden moist/ISA reinterpretation. |
| M5-W06b | Conditional spectral upgrade → choose richer tensor/provider only if data justify it | Spatial provider/reference assets; M5/PT | M/L; spectral error or measured-data need | Held-out covariance/PSD improvement, equal numerical/CPU gates, law identity; no upgrade based on appearance alone. |
| M5-W08-R3 | No sailplane/ultralight qualification → source suitable free data/assets, admit independent fixtures | Aircraft-authoring pipelines and tests; AS/aircraft owners | L/external data; separate aircraft acceptance | Validated sink polar/mass/inertia and sensitivity; thermal climb/centering comparison; preserve catalog status labels. |

P2 exit: thermal circulation and response have independent physical references, strong-gradient presets meet aerodynamic/numerical gates, and daytime coupling is explicit. Formal thermodynamic/terrain prediction is still not claimed.

### P3 — Terrain and advanced weather

| Proposed ID | Today → correction and implementation | Affected code / ownership | Complexity, dependency | Required verification |
| --- | --- | --- | --- | --- |
| M5-W08-R4 | Micro-relief/scenery only → shared physical macro-terrain/roughness/porosity/heat metadata | Landscape/field providers and validators; LU/SC/GP/M5 | XL; suitable free terrain data and provenance, contact/render alignment | Same height/normals for aero/contact/render; domain/LOD invariance; field hash and fresh-checkout asset checks. |
| M5-W08-R5 | No ridge flow → bounded attached-flow ridge correction | Proposed terrain-wind provider, offline reference assets; M5/LU | L; R4 | Boundary condition, decay, zero-slope/reversed-wind limits, windward climb/lee descent and reference comparison. |
| M5-W08-R6 | No qualified obstacle wakes → simple porous/solid wake classes with coherent residuals | Scenery aero metadata, spatial index, field compositor; SC/M5 | L; R4, geometry-specific reference | Deficit/diversion, downstream recovery, continuity and turbulence budget; oblique wind and overlapping wakes. |
| M5-W08-R7 | No qualified rotor/valley/severe weather → named limited-domain reference providers | Terrain/stability forcing, weather assets and scenario capability; M5/ATM/LU | XL/external data; R5/R6, validated stratification | Rotor/valley/downdraft against source/reference data, numerical limits, explicit unsupported-case refusal. |
| M5-W03a-R2 | Reset-only edits → optional recorded scheduled live transitions | Session/recorder/config and UI; SF/FL/UI | M/L; checkpoint/event design | No retroactive changes, before/after continuity, restore across transition, cancel/reject atomicity. |

P3 exit is **per scenario**, not “all weather solved.” Ridge acceptance does not close rotor, obstacle, valley or downburst gates. Keep unsupported entries disabled and document their exact missing inputs.

## 11. Stability, performance, telemetry and validation

### 11.1 Numerical and bandwidth requirements

Fixed step is `dt=1/240 s`. Sample actual stage state and time, including both distinct RK midpoints. Smooth forcing permits a meaningful refinement study; ground contact, stall boundaries and event knots can reduce observed order, so do not promise fourth-order convergence through every discontinuity. Evaluate the same analytic field realization at all step sizes and report observed order/errors.

Provisional resolution rule: at least **12 samples per shortest material forcing period** in the admitted envelope, then verify against finer timesteps; 20 is preferable for load/phase accuracy. The relevant encounter bound includes `|k·(v_ground-U_c)+nu|`, rotational station velocity and thin shear-layer crossing. At 240 Hz a 2 m mode at 60 m/s has only eight samples/period, so the common 2 m candidate is **not automatically qualified for the fastest aircraft**. Either qualify it by refinement with sufficient accuracy, choose a larger global wavelength cutoff at scenario resolution (e.g. 4 m), or add a justified solver substep capability through the existing model/kernel contract. Do not quietly change field cutoff per aircraft or FPS. Nyquist alone is inadequate.

High-frequency gust force accuracy also needs aerodynamic admittance/unsteady response evidence. Current quasi-steady strips do not validate arbitrarily rapid gusts at low Reynolds number. Use reduced frequency and available [UIUC low-speed airfoil/propeller data](https://m-selig.ae.illinois.edu/pd.html) to bound applicable coefficient regimes; static polars alone cannot identify dynamic gust transfer functions. Defer an unsteady-aero extension until a documented response error requires it; never cure it with a random damping multiplier.

Long runs need bounded phase arguments and stable event epochs. Reduce phase deterministically in float64, test large positive times and negative prehistory event indices, and avoid reseeding on a phase wrap. At zero mean, evolution remains finite; at zero RMS, skip noise exactly; at zero relative airspeed, no division by speed. AGL/column upper bounds, below-ground points, zero-width layers, impossible covariance and extreme wind/start combinations fail before mutation.

The repository pins Godot **4.8-beta1** in `get-godot.sh`; no upgrade is proposed. Preserve GDScript float64/packed state and existing render conversion; the [official float reference](https://docs.godotengine.org/en/latest/classes/class_float.html) distinguishes scalar double precision from default vector precision. Official [physics interpolation guidance](https://docs.godotengine.org/en/latest/tutorials/physics/interpolation/physics_interpolation_introduction.html) distinguishes render interpolation from fixed simulation ticks; it does not validate OpenRC's custom solver or exact replay across engine/platform changes. These latest-documentation references explain the concepts; implementation must verify APIs against the pinned engine.

### 11.2 Proposed performance budgets

These are allocation targets to measure, not observed results. The existing whole-physics **500 microseconds/tick target-host gate** remains authoritative. Profile current baseline first; if it already exceeds the gate, record that fact and do not present an incremental wind budget as full acceptance.

| Workload | Initial budget / measurement |
| --- | --- |
| One fixed-wing aircraft | Candidate 10 principal points × 4 RK stages = 40 station samples/tick; actual prop/shaft substeps, diagnostics and repeated evaluations must be counted, not assumed away. Start ≤32 modes; compare 24/32/64. |
| Incremental field cost | Target p95 ≤50 µs/tick for mild field, excluding unrelated baseline aero cost; target combined spatial-load overhead ≤100 µs/tick. Must still fit the whole 500 µs gate. Tighten or reduce optional scope if not met. |
| Multiple aircraft | Measure 1, 4 and 8 independently integrated sessions as stress cases, even if product admission allows fewer. Report total world CPU and per-aircraft cost; do not multiply a single-aircraft claim into a fleet qualification. |
| Shared coefficients/events | Resolve/cache per-world immutable data once; target setup ≤100 ms for ordinary presets and bounded transient memory. No frame stalls hidden in the first gust. |
| Active phenomena | Initial caps: 32 modes, ≤8 live thermal descriptors, ≤2 overlapping coherent gusts, ≤16 nearby qualified obstacle influences per sample; cap violations reject/resolve during setup, never nondeterministically drop physical effects. |
| Memory | Candidate ≤16 MiB shared atmosphere data plus bounded per-stage scratch; no retained growth after 30 min and 100 reset/restore cycles. Report actual peaks. |
| Presentation | Debug grid ≤512 arrows updated at ≤10 Hz; visual interpolation independent of physics. Extra weather presentation target <0.5 ms CPU/frame at 1080p with aid enabled; measure GPU separately. |

Forty points ×32 modes ×240 Hz is about **307,200 mode-point evaluations/s per aircraft**, before extra coupled-stage work. Sin/cos, allocations and duplicate load evaluations can dominate. Precompute wavevectors/polarizations/weights, transform station offsets once per stage and batch samples. First optimize measured duplication and allocations. If using a grid cache, its interpolation/quantization becomes part of the physical law, needs error/continuity tests and cannot vary with rendering LOD. Prefer stateless analytic queries until measurements justify that complexity.

Reuse [bench_wind.gd](../app/tests/bench_wind.gd), [bench_physics.gd](../app/tests/bench_physics.gd), the [debug bridge](../tools/debug/README.md) and [tool index](tools/README.md). `bench_wind.gd` currently reports percentiles of **batch means**, not individual-tick p95; extend existing instrumentation for actual tick distributions before claiming a p95 gate. Benchmark on idle target hardware with pinned build, CPU/GPU/OS, engine/backend, resolution, aircraft, scene, scenario, sample count and warmup. Use 1080p integrated runs first; headless field throughput is not visual/performance qualification. A native port requires the repository's SF backend policy and measured need, not intuition.

### 11.3 Telemetry and independent analysis

Record a lightweight default row with tick/time, datum position, attitude, ground velocity, reference wind, TAS/alpha/beta, density/charge, total force/moment, contact state and weather identity. Diagnostic capture optionally includes each station's position/wind/relative flow/q/force/arm/couple, component vectors, divergence/boundary metrics, source event IDs, downwash/wash inputs and sample count/cost. All channels declare reference frame, units and load-stage versus endpoint time. Keep the recorder read-only/bounded; reuse CSV and free NumPy/SciPy/Matplotlib tools where already available rather than building a plotting application.

Telemetry invariants: component sum equals total ambient wind; local velocity reconstruction matches aerodynamic input; sum of owned wrenches equals published load; impulse/energy observations correspond to the same interval; observer reads cannot alter RNG or flight fingerprints. Store canonical scenario, field assets/law hashes, engine/source fingerprint, fixture/input tape, markers and `complete`/`solver_changed` status with reports. A recovered prefix is diagnostic evidence, not exact replay.

### 11.4 Software and physical test matrix

Numerical tolerances below are **proposed gates**, to be fixed in reviewed fixtures before tuning. Tighten to analytic precision where practical; do not loosen after a failure without a documented error budget. Physical comparisons use measurement uncertainty and held-out cases rather than these arbitrary software tolerances.

For dimensionless divergence use `epsilon_div=L_char*abs(div W)/max(U_char,0.1 m/s)`, with each fixture declaring its characteristic length/velocity. For anelastic tests substitute `div(rho W)/rho_ref`. Flux residual is absolute net outward mass flux divided by total one-way throughput, with a declared small denominator floor for zero-flow fixtures; Dead Calm requires exactly zero instead. Sweep finite-difference/grid spacing so cancellation noise is not mistaken for a physical defect or concealed by a coarse grid.

| Test | Controlled experiment | Proposed measurable acceptance |
| --- | --- | --- |
| Legacy preservation | All v1–v4 configs/calm goldens; old `.orfl` exact replay with original matching source/engine, then candidate legacy-mode fixture comparison | Byte-identical admitted numerical state/load payloads; identity envelopes may explicitly identify the new build. Malformed config rejected before any accepted-state mutation. Existing Galilean tolerances remain, including 3e-7 state/air and 5e-7 position bounds where applicable; no bypass of solver fingerprints. |
| Pure common field | Repeat/reorder points, render/trace interleaving, player/AI query order, coincident aircraft | Same point/time/identity yields exact packed bytes; seed/config changes documented; no caller-dependent field. |
| Frames and crosswind | Cardinal FROM bearings, headings 0/90/180/270°, arbitrary quaternion and tilted aircraft | Analytic transforms/component signs within 1e-12 for simple float64 fixtures; rightward transport/left-origin labels correct. |
| Stage position/time | Linear spatial shear and analytic sinusoidal time forcing, including differing midpoint positions | Every sample matches independent analytic field; midpoint cache cannot reuse a different state. 240/480/960 Hz residual trend agrees with expected smooth problem order. |
| Field continuity | Traverse profile joins, gust support/birth/death, thermal rings/top and any grid seams | Value/derivative match analytic envelope; no finite jump as probe spacing shrinks. Use normalized divergence ≤1e-8 for analytic flat fixtures away from numerical differencing noise; convergence of finite differences required. |
| Wall/flux | Sample flat wall and closed boxes/cylinders including thermal support | Normal velocity ≤1e-8 m/s in analytic wall fixtures; integrated mass-flux residual <0.1% of one-way throughput after grid refinement. Terrain approximations need separately justified tolerances, not inherited perfection claims. |
| Spectral statistics | At least 10 seeds, duration ≥100 largest correlation times; static and straight-traversal probes at several heights/speeds | Analytic finite-mode covariance and target RMS within 5% over aggregate; per-band PSD within declared 95% confidence interval and initially ±20% integrated energy over resolved octave bands; cross-point normalized covariance error <0.05 versus target. Report omitted spectral energy. |
| Calm/hover-like probes | Mean=0, sigma=0; mean=0 with evolving sigma; fixed point; very slow crossing | Exact zero for Dead Calm; evolving law does not freeze at zero mean; finite output with no speed division or aircraft-dependent advection. |
| Differential wing/tail gust | Antisymmetric vertical gradient across wings; tail-only smooth event; mirror cases | Correct roll/pitch/yaw signs and moment-arm sums; no response in uniform-delta bypass; force-difference error <1e-9 of fixture scale against independent section oracle. |
| Gust response | Isolated lateral/vertical/longitudinal half-cosine, several H/V and amplitudes | Initial alpha/beta/q change matches kinematics; force/load factor agrees with independent linear/section calculation in valid regime; refinement changes peaks/phase by <1% at admitted rate. No direct attitude kick. |
| Crosswind landing | Same aircraft/input card, 0/1/2/3 m/s crosswind both signs, steady then gust; crab/wing-low methods | Record centerline error, heading-track difference, beta, touchdown lateral speed, wheel loads and ground yaw; mirror symmetry and no heading snap. Use aircraft-specific pilot-reviewed bands, not universal success guarantees. |
| Taxi/takeoff | Stationary wind-on hold, slow taxi, acceleration through liftoff, head/tail/crosswind | Tire velocity remains ground-relative; static aero exists; wheel unload/liftoff follows forces; no duplicate advection. Start solver fails clearly if equilibrium unsupported. |
| Thermal soaring | Uniform updraft fixture then balanced core/ring crossing and circling, engine off | In settled uniform air, climb approximately `w_up - still-air sink` with <2% mechanism-test error after accounting for bank/airspeed; energy work agrees with force/time integration. Population climb is not compared to core velocity alone. |
| Shear/strong gradients | C1/C2 layer crossings in ascent/descent and both directions; one-wing stall and prop-on cases | No force discontinuity from profile or blend; finite states; refinement peak/trajectory errors <1% in declared domain. Outside domain explicit experimental/refusal status. |
| Ridge/wake/rotor | Flat/sloped/reversed inflow, upstream/windward/lee probes and trajectories | Zero terrain correction on flat reference, correct boundary/decay; quantitative flow comparison against declared source data. No rotor acceptance from visual plausibility or potential-flow tests. |
| Replay and faults | Pause/resume, reset, restore at event boundary, injected invalid stage, provider-hash mismatch | Exact accepted continuation; state/RNG/world epoch unchanged after rejection; recorded future events preserved; no silent recovery to calm. |
| FPS and fleet | Same tick/input tape at 30/60/144 FPS and catch-up stress; reordered fleet stepping | Exact physics for equal accepted ticks on pinned runtime; separately report simulated time slowdown under catch-up cap. Multi-session reset affects only its declared owner. |
| UI and observers | Save/load/default/reset/Cancel, EN/ES, seed edits, listener/mast/aircraft separated | Numeric precision preserved, wrong versions refused, point-specific cues correct; observer-enabled/disabled flight bytes identical. Actual 1080p capture/listening required. |

Reuse existing `test_wind_field.gd`, `test_wind_turbulence.gd`, `test_wind_flight.gd`, `test_turbulence_flight.gd`, `test_wind_trace.gd`, `test_air_data.gd`, `test_rk_stage_time.gd`, `test_aero_flow.gd`, `test_ground_effect.gd`, `test_sf_environment.gd`, atmosphere-column tests, companion tests and independent trace readers. Extend their catalog coverage to all currently admitted fixed-wing routes, including newer aircraft and finite-fuel/battery variants. Add focused spatial tests for new invariants; do not replace existing evidence or rerecord goldens merely to make tests pass.

### 11.5 Physical validation and pilot acceptance

Use existing free models/tools and publicly downloadable reference data before writing equivalents. Audit licensing/provenance. A sonic anemometer time series, multi-height mast record or measured field/UAV data can identify RMS, PSD, scale and stability only within its sampling bandwidth/site conditions. A single handheld wind reading cannot validate a 3D field. Separate parameter-fitting data from held-out validation; record measurement height, surface, averaging period, sample rate, sensor response and uncertainty.

For aircraft response, use documented RC flight behavior and measured airspeed/IMU/control logs where available; match aircraft mass/inertia/polar/control configuration and encounter conditions. Compare small-gust transfer functions, response phase/peaks, drift, touchdown and sink/climb, not just a video that looks lively. RC pilot review should cover trainer/aerobat/light-STOL at the same physical weather, with randomized seed/order and a calm control case. Record observations and unresolved disagreement; specialist agreement is not independent physical evidence.

No current measurement establishes universal RC default turbulence scales, a glider polar for this catalog, valid ridge/rotor terrain, or target-host cost for this proposed implementation. Those remain explicit acceptance dependencies.

## 12. Decisions, risks and release criteria

### 12.1 Recommended decisions

| Decision | Reason / consequence |
| --- | --- |
| Evolve existing Environment; no kernel weather branch | Current architecture already has pure stage evaluators. New position samples are necessary; a new simulation engine is not. |
| Preserve legacy provider and exact calm path | Allows controlled A/B tests, old recordings and existing aircraft to remain usable. New realism is an explicit law/preset change. |
| Shared Eulerian field for interactive use | Different aircraft/stations must encounter the same air. Aircraft-speed-filtered Dryden remains a reference, not a world service. |
| Solenoidal finite-field prototype with measured covariance | Balances coherent 3D samples and bounded cost; finite modes alone do not establish atmospheric accuracy. |
| Matched local aerodynamic deltas before full reformulation | Avoids wholesale retuning while enabling small gradients. Strong gradient acceptance requires later local validity/wake work. |
| Balanced thermal circulation, explicit heating | Prevents unexplained net lift and midnight solar thermals. A coherent kinematic model remains distinct from forecast weather. |
| Physical terrain before terrain-weather claims | Rendered scenery and millimeter ground relief cannot define ridge/rotor boundary conditions. |
| Change fresh-user default only after gates | Current gentle air is already functional. More complexity is not automatically a better beginner experience. |
| Freeze physics independent of visual quality | Graphics LOD and camera affect presentation budgets, never atmospheric samples or force fidelity. |

Record accepted architecture choices in [DECISIONS.md](DECISIONS.md) during implementation; this plan recommends them but does not manufacture an approval or implementation event.

### 12.2 Main risks and mitigation

| Risk | Severity | Mitigation / stop condition |
| --- | --- | --- |
| Double-counted wind, tail load, wash, induced drag or damping | Critical | Force ledger, matched uniform tests and independent local oracle; stop rollout on unexplained uniform difference. |
| Incorrect datum after moving CG/fuel | Critical | Station offsets from fixed datum, one CM wrench transform; fuel-state fixtures. |
| Apparent coherence with invalid wall/divergence | High | Differentiate enveloped potentials; test composed field/terrain boundary and flux. |
| Plausible-looking but wrong spectral scaling | High | Units/normalization/tensor identity; independent PSD/coherence tests and measured applicability limits. |
| Low-speed or high-speed numerical failure | High | No speed division, frequency/domain admission, same-field timestep refinement; no silent clamps. |
| Legacy recording/preference migration changes physics | High | Separate schema/provider laws, exact old-path regression and preflight restore checks. |
| Multi-session time/RNG divergence | High | Immutable provider/world epoch; no query mutation; future stateful weather gets one transactional owner. |
| Default overwhelms a lightweight aircraft | Medium/high | Fleet/weight-class trials, explicit gentler choice, no hidden atmosphere multiplier. |
| Heavy mode/station cost | High | Count all evaluations, profile idle target hardware, caps and offline assets; preserve whole-tick budget. |
| Surface/cloud data absent or artistically inferred | High | Explicit authored/estimated provenance and feature capability gates. |
| Atmospheric accuracy overstated by solver tests | High | Separate model verification, measurement validation, pilot and performance gates in every report. |

### 12.3 Consolidated specialist findings and unresolved decisions

High-reasoning Luna Max specialists were used for atmospheric physics, RC aerodynamics, Godot integration, UX and architecture/QA, following [SUBAGENTS](SUBAGENTS.md). The independent reviews converged on the existing Environment seam, pure shared spatial fields, local airflow ownership, preserved legacy replay and terrain capability gates. Their substantive challenges are incorporated: height-multiplying noise breaks divergence; a frozen field can freeze in calm air; a seed alone is not a complete world identity; the empirical/local blend complicates differential gusts; positive plumes need return circulation; and companion logs are not shared-world replay.

Tradeoffs resolved here: use coherent finite modes rather than independent per-surface Dryden; retain Dryden as reference; use an opt-in matched-load bridge rather than immediately replacing the calibrated empirical law; start with authored physical thermal forcing rather than deriving it from visual brightness; disable rotor scenarios instead of inventing missing data. Remaining empirical decisions are tensor/scale calibration, whether 32 modes meet spatial/temporal statistics and cost, the strong-gradient aerodynamic transition, validated heating/terrain datasets, and aircraft-specific pilot acceptance. Each is assigned a phase and falsifiable test above.

### 12.4 Release acceptance checklist

- P0: old behavior/replay preserved; correct stage positions; one force owner per effect; all admitted aircraft and start modes covered; no undocumented solver change.
- P1: continuous bounded field, common fleet identity, spectral/coherence/boundary tests, numerics and target cost pass; 1080p weather workflow and actual W-A/W-B pilot review before fresh-user default changes.
- P2: balanced thermal flow and correct energy response; heating/night behavior explicit; strong-gradient loads and missing aircraft qualification resolved for each claimed preset.
- P3: physical terrain/data provenance, attached/separated flow scope and per-scenario reference comparison; no automatic rotor/valley/downburst promotion.
- All phases: no shake/rotation shortcut, no duplicate forces, no arbitrary aerodynamic bonus, no aircraft-specific weather process, no silent fallback; preserve active evidence and document limitations.

**Deliverable verification for this audit:** repository/source and specialist research review, document structure and local-link checks, and review of the documentation-only diff. Runtime, spectral, performance and pilot tests listed above are future acceptance work, not results of this planning task.

