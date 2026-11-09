# Wind, atmosphere and airflow: technical reference

Code audit: 2026-10-31. Baseline: `a73e6f32f388eda1778f2dd27866d6aca146f5d8`, plus the working-tree presentation edits identified under [verification](#verification). This document describes implemented behavior. The [phased engineering roadmap](WIND-ATMOSPHERE-ROADMAP.md) describes proposed changes. Neither existing documentation nor a passing model test is evidence of physical realism.

These are the two authoritative documents for environmental physics and its airflow interfaces. Vehicle, graphics, audio and tooling guides retain their own contracts and link here. Earlier wind/atmosphere guides, the advanced masterplan and dedicated research narratives have been consolidated; their data, source snapshots, recordings, provenance and reproduction tools remain in place and are indexed below. No physics, parameters or golden flights were changed by this audit.

## Scope and architecture

The audit follows configuration → provider → session → stage airflow → loads → accepted state → observers/replay. It includes GDScript and native weather, atmosphere, fixed-wing surface/propulsion/wake interactions, helicopter and multirotor boundaries, ground-vehicle exclusions, UI/CLI/scenarios, companions and presentation. Engine/battery thermal management is a different system: only ambient density/charge and airflow interfaces are covered here. Frozen prototypes and historical source overlays are not production implementations.

| Boundary | Current source and symbols | Responsibility |
| --- | --- | --- |
| Public weather configuration | [wind_config.gd](../app/physics/wind_config.gd): `validate`, `defaults`, `presets`, `upgrade_atmosphere`, `upgrade_column` | Complete versioned objects, typed finite bounds, explicit feature promotion; technical calm and interactive gentle defaults differ. |
| Spatial admission | [wind_spatial_config.gd](../app/physics/wind_spatial_config.gd): `resolve`, `_validate_domain`, `_validate_events`, `_validate_thermal_coupling` | Canonical identity, flat datum, bounded domain, ordered agendas and law identifiers. |
| Physical providers | [wind_field.gd](../app/physics/wind_field.gd): `sample_world`, `atmosphere`; [wind_spatial_field.gd](../app/physics/wind_spatial_field.gd): `sample_world`; [wind_thermal_field.gd](../app/physics/wind_thermal_field.gd): `_cell_velocity` | Pure queries of uniform or spatial velocity and uniform or column atmosphere. |
| Shared environment | [environment.gd](../app/sim/environment.gd): `wind_world`, `air_world`, `wind`, `air` | Delegates weather and adds the session-owned OU sample once; physical ground/lake/course are separate queries. |
| Session ownership | [flight_session.gd](../app/sim/flight_session.gd): `setup_weather`, `wind_at`, `turbulence_at`, `air_data`, `_restart_weather_aux` | Reset/publication boundaries, sampled OU state, stage callbacks, starts, telemetry and persistence. |
| Physics kernel | [simulation.gd](../app/sim/simulation.gd), [vehicle_model.gd](../app/sim/vehicle_model.gd), [integrator.gd](../app/physics/integrator.gd) | Integrates the installed vehicle evaluator; weather remains a model/session dependency, not a vehicle-specific kernel branch. |
| Fixed-wing local flow | [air_data.gd](../app/physics/air_data.gd): `compute`; [wind_aircraft_flow.gd](../app/physics/wind_aircraft_flow.gd): `sample`, `stage_air` | Converts ambient wind to body-relative datum and station airflow; preserves float64 and fixed authored datum. |
| Loads and wakes | [aero.gd](../app/physics/aero.gd): `loads`, `ambient_spatial_loads`; [dynamics.gd](../app/physics/dynamics.gd); [slipstream.gd](../app/physics/slipstream.gd) | Own aerodynamic baseline, local corrections, propulsion inflow and matched wash loads. |
| Native evaluator | [weather_adapter.gd](../app/sim/native/weather_adapter.gd), [native_weather.gd](../app/sim/native/native_weather.gd), native headers listed below | Adapts admitted weather/OU windows and duplicates numerical field evaluation behind the existing vehicle callbacks. |
| Observation | [main.gd](../app/main.gd), [trace.gd](../app/sim/trace.gd), [flight_log.gd](../app/sim/flight_log.gd), render/audio consumers below | Reads accepted state or explicitly identified k1 state. Presentation never writes wind into flight dynamics. |

### Frames, units and clock

Simulation vectors are `PackedFloat64Array`; scalar arithmetic uses GDScript `float`. NED position is `[north,east,down]` metres, wind is NED m/s; body axes are forward/right/down. `q` rotates body to NED. Weather direction is meteorological FROM, clockwise from north:

```text
Wmean = [-U cos(theta), -U sin(theta), 0]
v_air,O = v_ground,O - R(q)^T W(xO,t)
TAS = |v_air,O|; qbar = rho TAS²/2
alpha = atan2(w,u); beta = atan2(v,sqrt(u²+w²))
x_dot,NED = R(q) v_ground,O
```

`Air.compute` handles zero-speed angles and returns air data. Ground contact uses inertial/ground-relative velocity. There is no second wind force, added continuous position drift, or explicit `-dW/dt` acceleration. Wind changes forces through relative flow. Rendering converts NED to Godot axes at the boundary.

The ordinary flight tick is 240 Hz. RK stage queries use their own state and time; equal-time midpoint stages can occupy different positions. `wind_at(t,state)` uses that state's datum; without a state it uses the accepted endpoint, so the one-argument observer API is not a historical-position query. Spatial epoch time is `simulation_time_s + epoch_offset_s`; both times must fit the declared horizon. Pausing freezes simulation-time weather. Reset repeats the authored epoch; neither rendering nor query order advances spatial RNG.

## Configuration and admission

[WindConfig](../app/physics/wind_config.gd) rejects unknown/missing keys, wrong numeric types, nonfinite values and unsupported versions. `360°` canonicalizes to `0°`; otherwise full precision is retained. Upgrade helpers return candidates; validation remains required.

| Weather format | Added behavior | Important restriction |
| --- | --- | --- |
| `openrc-weather v1` | Uniform mean plus periodic cosine horizontal/vertical gust | No stochastic state or custom atmosphere. |
| v2 | Three-component temporal OU turbulence | Uniform in space, independently owned by a session. |
| v3 | `reference` or `custom` uniform atmosphere | Custom inputs apply at field level for the whole flight. |
| v4 | `standard_column` atmosphere | Dry reference column by geometric altitude, not a moist sounding. |
| v5 | Nested `openrc-spatial-wind v1` or v2; v2 adds `openrc-thermal-field v1` | Legacy mean/gust/OU amplitudes must all be zero; physical atmosphere still chosen explicitly. |

Legacy ranges: speed 0–15 m/s; FROM 0–360°; horizontal gust 0–8 m/s; upward gust −8…8 m/s; duration 0.5–20 s; period 0.5–120 s and at least duration; delay 0–3600 s. OU component RMS 0–3 m/s, tau 0.2–30 s, seed an exact uint32.

`WindConfig.defaults()` is calm. `GENTLE_PRACTICE`, used by fresh interactive preferences, has 1.5 m/s FROM 090°, 0.6 m/s horizontal and 0.15 m/s upward gust peaks, 4 s duration, 14 s period, 3 s delay, RMS `[0.15,0.15,0.08]`, tau 3 s and seed 20261011. Direct technical flight starts from calm unless weather is supplied. These are authored inputs, not measurements.

### Spatial parameters

Defaults and all cross-checks are in `WindSpatialConfig.defaults/resolve`. The datum is fixed to `ground_down_m=0`; the word AGL in this schema means height above that flat plane, not above the actual ground/contact surface.

| Group | Implemented bounds/defaults |
| --- | --- |
| Identity | `seed_u32` and `world_epoch_id_u32` each 0–4294967295; `epoch_offset_s` 0–86400 s; `xorshift32-v1`. Full canonical JSON SHA-256 binds all values/laws, not seed alone. |
| Domain | N/E half-extents 100–10000 m (default 10000); height 20–1000 m (200); horizon 60–86400 s (86400); below-ground zero extension 0.01–1 m (0.25); gust wall transition 0.1–50 m (3). |
| Profile | Reference speed 0–20 m/s (0), height 0.1–200 m (10), roughness 0.001–0.5 m (0.03), displacement 0–20 m (0); wall join 0.1–100 m (0.3), surface top 1–500 m (80), free-air join thickness 0.1–200 m (20); horizontal free-air components ±30 m/s. |
| Layers | At most 16 ordered, nonoverlapping layers; half-thickness 0.1–100 m, horizontal components ±5 m/s; cannot touch reference-height support or start below wall join; `resolve/_validate_layers` owns count/component/height limits. |
| Gusts | At most 32 ordered unique events; starts 0–86400 s, duration 0.1–120 s, horizontal components ±2.5 m/s, zero vertical component; at most four concurrent and sum of amplitude norms ≤8 m/s by validator interval convention. |
| Spatial turbulence | Scalar nominal RMS 0–1 m/s (0), 8–64 modes (24), minimum wavelength 2–100 m (5), maximum wavelength 2–500 m (50), ordered min≤max; coherence parameter 0.1–600 s (4). |
| Thermals | At most 16 cells/four overlaps; lifetime 120–720 s; radius 10–80 m; top 200–1200 m, further limited to spatial domain ≤1000 m when composed; signed peak −3…3 m/s, concurrent absolute peaks ≤6; N/E drift components ±20 m/s. Per axis, full support requires `max(abs(c0), abs(c0 + drift * duration)) + 5R <= half_extent`. |

The wall join must be at least `d + max(0.3,10*z0)`, reference height strictly between wall and surface top, and upper blend inside the domain. The cubic wall slope ratio must lie in `[0,3]`. Thermal/spatial datum, epoch, domain and horizon must match. No query silently clamps an out-of-domain aircraft back into valid weather: `WindField` translates failure to three NaNs, and the consuming transaction refuses invalid physics.

`WindSpatialPresets.entries` supplies seven available presets: light training (`spatial-realistic-v1`), light breeze, crosswind, gusty, shear, thermal soaring and strong wind. Ridge lift, terrain rotor and valley channeling are explicitly unavailable. The “Realistic” label is a UI name, not validation. Gusty contains 24 finite events ending around 1797 s; it does not repeat through its one-day validity horizon. The thermal preset contains one cell born at 15 s, living 360 s, center `[220,-120]` m, radius 35 m, top 200 m, peak 1.2 m/s, drifting with the preset upper background. No automatic replenishment exists.

## Implemented field equations

### Uniform mean and repeating gust

`WindField.sample` uses `p = fposmod(t-delay,period)` after the delay. Inside `0<p<duration`, `g=0.5*(1-cos(2*pi*p/duration))`; elsewhere `g=0`. It returns `Wmean + g*[-G cos(theta),-G sin(theta),-Gup]`. Cardinal directions have exact branches. Pulse integral is amplitude×duration/2. Consequently the configured speed is background wind, not the full time average: gentle-practice adds 0.085714 m/s along its horizontal gust direction and 0.021429 m/s upward on average. The uniform “updraft” preset is not a thermal circulation.

### Temporal OU turbulence

[wind_turbulence.gd](../app/physics/wind_turbulence.gd): `initial`, `step`, `_normal_pair`, `_uniform_open` implement, for each active axis:

```text
a = exp(-dt/tau)
x_next = a*x + sigma*sqrt(max(0,1-a*a))*normal
```

Initial state is stationary Gaussian, not zero startup. The private Godot RNG is seeded and its state retained; `_uniform_open` constructs a float64 open-interval uniform and Box–Muller supplies normal pairs. Zero-sigma axes consume no draws. `FlightSession` stores previous/current samples plus the interval time in aux and RNG state in modes; interpolation is read-only during RK/trace queries. Advancing the interval is part of the simulation transaction, so refused steps do not consume future random state.

Linear interpolation preserves endpoint samples but lowers interior variance: at fraction `f`, stationary variance is `sigma²*((1-f)²+f²+2*f*(1-f)*a)`. This is a temporal one-pole practice model, not Dryden, a spatial spectrum or per-wing turbulence. Exact continuation is tied to the pinned runtime/math implementation; a seed alone is insufficient for restoring a running filter.

### Spatial background, layers and gusts

Let `h=-D`, `S(s)=s³(10-15s+6s²)` with `s` clamped to `[0,1]`. `_neutral_profile` evaluates:

```text
U(h) = Uref * log((h-d)/z0) / log((href-d)/z0)
Wlog = [-U(h)*cos(theta), -U(h)*sin(theta), 0]
```

Below wall height `hw`, `_wall_join` uses cubic Hermite factors `h01=-2s³+3s²`, `h11=s³-s²`, `s=h/hw`, matching the log value and slope while giving zero value/slope at the ground. Above surface top, `_profile_wind` blends the continuing log profile to constant free-air wind using `S` over the configured join thickness. Each layer adds `deltaW*(1-S(abs(h-center)/half_thickness))` inside its support. All these components are horizontal and horizontally uniform; their divergence is zero despite vertical shear.

`_gust_wind` sums each active event's horizontal amplitude times `B(s)=64*s³*(1-s)³`, `s=(epoch-start)/duration`, multiplied by `S(h/ground_transition_height)`. This gives zero pulse value and first/second temporal derivatives at event endpoints. The agenda is fixed, not generated during flight. Prepared packed events retain order. `_first_possible_gust` uses binary search with `epoch-start >= maximum_duration` to skip definitely expired events; worst-case remaining scan is still 32 entries. The endpoint admission mismatch is recorded under findings.

### Finite-mode spatial perturbations

`_resolve_modes` mixes seed and epoch ID into a private xorshift32 state, resolves all modes once and stores nine float64 scalars per mode. Wavelengths are stratified in log space. For each mode, `k=2*pi/lambda`, `kz/k∈[0.5,1)`, horizontal wave direction and horizontal potential axis `a=(aN,aE)` are seeded. Define:

```text
c = -aE*kN + aN*kE
A = 2*sigma / sqrt(mode_count) / sqrt(kz²+c²)
omega = signed(2*pi/coherence)*(0.5+u) - kN*Wref,N - kE*Wref,E
phi = kN*N + kE*E + phase0 + omega*epoch
f(h) = S(kz*h/(2*pi))*sin(kz*h)
Wmode = [aE*A*f'(h)*cos(phi), -aN*A*f'(h)*cos(phi), A*f(h)*c*sin(phi)]
```

The implementation reduces horizontal/temporal phase separately modulo full-precision `TAU_F64` before trig evaluation. The vertical derivative includes the wall-taper derivative, which is essential to the curl construction. NED down is already the third component. Differentiating shows `dWN/dN+dWE/dE+dWD/dD=0`; no post-hoc speed clipping is applied. Intrinsic `omega` keeps the field evolving even when reference mean wind is zero.

This is a deterministic finite harmonic field. Equal nominal modal variance/log-wavelength distribution does not implement a Dryden/von Kármán spectral tensor. `coherence_time_s` controls intrinsic frequencies, not exponential decorrelation; coefficients do not renew. Nominal RMS is not a guaranteed component or local RMS: height phase, wall taper, seeded directions and finite realization matter. Advection uses the reference mean, not each altitude's sheared mean or aircraft speed. Those are law limitations, not hidden stochastic features.

### Balanced kinematic thermals

`WindThermalField._cell_velocity` implements an axisymmetric streamfunction around the drifting cell center `center0 + drift*(epoch-birth)`. For age fraction `s`, radius distance `r`, cell radius `R`, top `H` and signed peak `P`:

```text
L(t) = 64*s³*(1-s)³                        inside the lifetime
w(h) = P*sin²(pi*h/H)                     inside 0<h<H
T(r) = 1                                 for r≤4R
     = 1-S(r/R-4)                        for 4R<r<5R
     = 0                                 outside
Psi = 0.5*L*w(h)*r²*exp(-r²/R²)*T(r)
u_r = -(1/r)*dPsi/dh
u_up = (1/r)*dPsi/dr
W = [u_r*offsetN/r, u_r*offsetE/r, -u_up]
```

At `r=0`, the explicit analytic limit is `u_up=L*w(h)` and horizontal flow is zero. The vertical core has compensating outer sink (sign reversed for negative P); compact radial support closes the integrated volume flux. Cells add linearly. Seed is agenda provenance only: the explicit cell list completely determines the field. This is prescribed circulation; temperature, pressure, humidity, solar time, cloud cover and terrain do not generate or modify it.

Two boundaries matter. First, velocity is continuous but its radial component is not C1 across `h=0,H`; see F01. Second, the circulation is divergence-free in **volume**, not density-weighted mass: by the product rule, the separately implemented `standard_column` and velocity laws imply `div(rho*W)=W_D*d(rho)/dD`, generally nonzero locally. This is a mathematical inference, not a measured mass-flux error. The code permits that combination without an anelastic correction. This limits physical interpretation of the composite weather; it does not imply a numerical division-by-zero at the axis.

### Atmosphere

[atmosphere.gd](../app/physics/atmosphere.gd) has three distinct paths:

- `standard()` returns literal `rho=1.225 kg/m³`, dry density 1.225, pressure 101325 Pa, temperature 288.15 K, charge and sigma 1, density altitude 0. It intentionally does not recompute the rounded density literal.
- `evaluate(elevation,temp,QNH,RH)` uses uniform custom air. Accepted elevation −500…4000 m, temperature −20…45 °C, QNH 870…1085 hPa and liquid-water RH 0…100%. RH remains liquid-referenced below freezing.
- `standard_column(altitude)` admits geometric altitude −500…11000 m and dry ISA troposphere. `WindField.atmosphere(down)` supplies `field_elevation-down`; custom temperature/QNH/RH are validated stored inputs but are not applied to this dry column.

With `Re=6356766 m`, `g0=9.80665`, lapse `L=0.0065 K/m`, `Rd=287.05287`, `Rv=461.523329`, `T0=288.15`:

```text
Hgeo = Re*z/(Re+z)
b = g0/(Rd*L)
p_custom = 100*QNH*(1-L*Hgeo/T0)^b
T_custom = temp_C+273.15
e_sat = 611.21*exp((18.678-temp_C/234.5)*temp_C/(257.14+temp_C))
e = RH/100*e_sat
rho_dry = (p-e)/(Rd*T); rho = rho_dry + e/(Rv*T)
sigma = rho/1.225; engine_charge_ratio = rho_dry/1.225
T_column = T0-L*Hgeo; p_column = 101325*(T_column/T0)^b; e_column=0
```

Density altitude inverts the dry reference density law: `rho0=101325/(Rd*T0)`, `Hrho=T0/L*(1-(rho/rho0)^(1/(b-1)))`, then `zrho=Re*Hrho/(Re-Hrho)`. It is a diagnostic, not terrain height. EAS is `TAS*sqrt(rho/1.225)`. Fixed-wing stages sample density/charge at the datum once, not at every aerodynamic station. There is no varying gravity, Reynolds-dependent polar lookup or thermodynamic coupling of the thermal cells.

## Airflow, loads and induced flow

### Fixed-wing station ownership

`WindAircraftFlow._sample` constructs `x_i=x_O+R*r_i`, samples `W_i` at the same stage time, and returns:

```text
delta_i = R^T*(W_O-W_i)                    ambient difference only
v_air,i = v_air,O + omega_body × r_i + delta_i
```

There are six wing stations, horizontal-tail slot 6, vertical slot 7 and optional propulsion slot 8 in `geometry/sample`; powered `stage_air` requires that slot and refuses its absence. `WindAircraftFlow.geometry` uses the authored fixed datum O and aircraft geometry. Tailless aircraft use swept wing locations and reserve a zero unsampled horizontal-tail slot; the aggregate vertical element remains one station, so separate winglet gradients are unresolved. Rotation enters once. Changing fuel CG is handled by the owning mass/wrench transformation, not by moving the weather datum opportunistically.

`stage_air` supplies datum Air, body-state bytes, density, sample time, station deltas, hub/intake point velocity, wake-source ambient delta, and an explicitly retained `StagePointSampler` owner. Wash queries use their actual force arms, sharing one ambient sample between washed/free evaluations. Production `include_flow=false` omits diagnostic arrays, not physical queries or validation. The receipt is ephemeral; `matches_stage` checks state and density but cannot enforce matching time/model/provider (F06).

### Aerodynamic baseline and matched correction

[Aero](../app/physics/aero.gd) retains the empirical/reference load law and its existing attached/high-angle blending, stall envelopes, control deflections, damping, downwash and ground effect. Spatial flight selects `SPATIAL_CONTINUATION_LAW`:

```text
Lspatial = Lbaseline
         + Lraw_sections(v_reference + station_delta, held_wake)
         - Lraw_sections(v_reference,                 held_wake)
```

The two raw passes share density, controls, body state, ground effect and **reference** wing wake. Body residuals remain owned by the baseline once. Exact zero station deltas bypass subtraction and return baseline aero bytes. Nonzero gradients therefore produce differential section forces and arm moments without also adding an invented gust moment. Local section lift/drag is rotated in its flow plane and accumulated as force plus `r×F`/section couple; dynamic pressure follows local speed. Existing derivative/residual terms remain baseline assumptions, not newly validated spatial physics.

The earlier `ambient_spatial_loads` narrow path remains available, with attached-forward-flow checks, ≤3° local alpha/beta change and ≤25% section-plane q change plus existing polar/tail limits. Production v5 uses `ambient_spatial_continuation_loads`, which instead applies the existing full-angle section continuation with defensive finite/size bounds. Neither path solves unsteady stall or circulation transport. Holding reference wake in both passes deliberately excludes gradient-induced wing-to-tail wake feedback. A numerically finite strong-gradient result is not evidence of physically correct separated flow.

### Propulsion and wake interfaces

| Consumer | Implemented airflow law and boundary |
| --- | --- |
| [propulsion.gd](../app/physics/propulsion.gd): `stage_air_velocity`, `thrust_torque` | Explicit stage receipts use hub/intake flow including `omega×r`. Non-Glow prop maps use axial advance `J=max(axis·vhub,0)/(n*D)`, thrust `Ct*rho*n²*D⁴`, power `Cp*rho*n³*D⁵`, torque power/(2*pi*n), with stopped/map-envelope branches in source. Clipping reverse advance here is a map assumption. |
| [glow/](../app/physics/glow/), [dynamics.gd](../app/physics/dynamics.gd), [flight_session.gd](../app/sim/flight_session.gd) | Coupled shaft/prop stages consume same-stage inflow and density: legacy old-shaft paths use datum air; detailed Glow/electric/turbine and explicit spatial stages use hub/intake air. Engine charge is separate from aerodynamic total density. Legacy prescribed-RPM, old shaft, electric and detailed Glow families retain different engine laws; no universal atmosphere torque multiplier exists. |
| [turbine.gd](../app/physics/turbine.gd): stage force evaluation | Uses intake-relative air including intake arm rotation, gross nozzle force and captured-air momentum; the native generic point arm is set to intake, not nozzle. |
| [slipstream.gd](../app/physics/slipstream.gd): `stage_loads`, `source_air`, `wake` | Tail wash adds matched washed-minus-free tail loads, sharing ambient wind/downwash. Source air is datum air plus hub ambient difference; it deliberately excludes hub rotational inflow from that transport closure. Stage thrust/torque can be supplied to avoid inconsistent propulsion reevaluation. |
| [wash_transport.gd](../app/physics/wash_transport.gd): derivative helpers | Optional per-piece axial wake state lags toward equilibrium according to convection speed/distance; its continuous state is integrated with the vehicle. |
| [ground_effect.gd](../app/physics/ground_effect.gd): `factors` | Aerodynamic proximity correction uses the existing aircraft/ground geometry. It neither generates terrain wind nor changes spatial flat-plane height. |

For positive thrust, the slipstream momentum closure includes `vi=0.5*(sqrt(max(u²+2*T/(rho*A),0))-u)` and axial increment `dv=k_w*vi`. It applies configured contraction, coverage, reverse-flow fading and torque-related swirl. Transport uses `(dv_target-dv)*max(u+vi,flow_floor)/distance`. This is a tail-oriented empirical wake model, not a spatial fluid solver: it does not generate a common world wake for another vehicle, dynamically bend a wake through ambient gradients, or solve wing wash/fuselage scrubbing.

Selecting spatial weather also selects the point-inflow law **even when its instantaneous wind is uniform or zero**. Some old shaft paths use datum inflow without hub rotation; the new point law can therefore change whole-aircraft loads at nonzero body rate despite zero ambient gradient. The exact-zero guarantee belongs to the aerodynamic correction, not arbitrary cross-law whole-flight parity. `test_spatial_propulsion_flow` explicitly exercises this distinction.

### Helicopter, multirotor and ground vehicles

[helicopter_flight_session.gd](../app/sim/helicopter_flight_session.gd): `setup_weather` refuses spatial fields, nonzero OU turbulence and vertical atmosphere. Supported mean/gust/custom-uniform air is sampled at the supplied RK state/time. [rotorcraft/flight_dynamics.gd](../app/physics/rotorcraft/flight_dynamics.gd) subtracts ambient wind before rotor/airframe evaluation; hub/fin motion adds local rigid-body velocity. This is not distributed spatial environmental inflow across the rotor disk.

The helicopter's [inflow.gd](../app/physics/rotorcraft/inflow.gd): `target/normalized` computes signed induced velocity from `vh=sqrt(abs(T)/(2*rho*pi*R²))`, normalized climb/crossflow, a piecewise equilibrium law with explicit instability/loss parameters and a terrain-intersection-dependent ground factor. [dynamic_inflow.gd](../app/physics/rotorcraft/dynamic_inflow.gd): `evaluate/derivative` uses a dimensional first-order lag:

```text
Veff = sqrt(crossflow² + (vi+climb)²)
tau = (0.849/4)*R/max(Veff,flow_floor)
dvi/dt = (vi_target-vi)/tau
```

Dimensional state avoids dividing by rotor speed at spool-up. The code explicitly treats this as a chosen lag, not a validated transient vortex-ring model. [main_rotor.gd](../app/physics/rotorcraft/main_rotor.gd), [tail_rotor.gd](../app/physics/rotorcraft/tail_rotor.gd) and [airframe.gd](../app/physics/rotorcraft/airframe.gd) consume density, relative hub/fin flow, induced velocity and body rates; low-RPM closures and blends are separate from stopped/normal rotor operation. Spatial weather admission cannot be inferred from their existence.

The main-rotor normal-speed branch defines `tip=omega*R`, `mu_x,y,z=v_hub/tip`, `lambda=vi/tip`, `mu²=mu_x²+mu_y²`. It refuses `mu²>=2`, computes `CTideal=(a*solidity/2)*(collective*(1/3+mu²/2)+(mu_z-lambda)/2)`, caps CT, then `T=CT*rho*pi*R²*tip²` and `Q=[CT*(lambda-mu_z)+cd0*solidity/8*(1+7*mu²/3)]*rho*pi*R³*tip²`. Flap angles orient the thrust normal; hub-arm, spring and reaction-torque moments remain distinct. Its `16/(gamma_flybar*omega)` flap time scale and low-RPM substitute are explicit approximations.

The tail rotor includes main-wake subtraction in vertical hub flow and body-rate contributions in normal flow, solves `_trim` to obtain local collective/normal-flow slopes, caps CT and applies blockage to thrust. It reconstructs induced velocity from capped unblocked CT; its torque uses the same profile/induced-power form. `rotorcraft/airframe.gd:_piece` subtracts wake from rigid-body point air, applies component-area fuselage drag `-rho*A_i*u_i*|u|/2`, and bounded fin/tail normal-force laws. These implement density-aware helicopter loads but do not establish a measured stopped-blade, windmilling or separated rotor wake model.

The [multirotor plant](../app/physics/multirotor/plant.gd) is explicitly research-only, without a playable session. It samples wind/density once at the datum, then adds `omega×hub` per rotor. [rotor.gd](../app/physics/multirotor/rotor.gd) uses `T=cT*omega²`, `Q=cQ*omega²` and horizontal rotor drag `Fxy=-kh*omega*Vhub,xy`; neither density nor axial inflow enters its thrust/torque law. Density affects [airframe drag](../app/physics/multirotor/airframe.gd) only. Thus equal rotor speed at zero flow produces equal static thrust at different atmospheric densities. Rotor-scale environmental gradients cannot produce differential local inflow with the current datum-only query. These are explicit promotion blockers, not a defect in an advertised playable multirotor.

The [ground-vehicle environment](../app/physics/ground_vehicle/vehicle_environment.gd) and [session](../app/sim/ground_vehicle/session.gd) consume road, gravity and water; their dynamics do not query physical atmospheric wind. A shared `Environment` class does not establish universal wind coupling. Any future vehicle effect belongs in its model adapter, not the simulation kernel.

## Lifecycle, publication and reproducibility

`FlightSession.setup_weather` builds/validates before changing accepted ownership, refuses live changes after tick zero, and publishes weather/reset boundaries transactionally. A pending configuration blocks ordinary wind reads until reset. `_restart_weather_aux` installs the seeded OU window; initial spatial wind is queried at the actual start location.

Airborne reset begins with an air-relative datum trim then adds initial wind to ground velocity. It is not a distributed-gradient equilibrium solve and does not continuously trim away disturbances. Runway preflight supplies a fresh point-Air receipt for every candidate residual state; unsupported static equilibria refuse. Hand launches remain ground-relative throws. The spatial branch selects direction from release-position wind and initializes RPM from local hub flow; legacy branches use background-only wind for direction (omitting initial OU) and ground-relative axial velocity for RPM (F17). Field elevation changes pressure/column altitude, not terrain translation.

`Simulation.step` samples the tick inputs/aux once, advances trial OU state, evaluates RK stages, projects/validates and publishes the complete accepted frame. Invalid local wind, atmosphere, domain or loads reject the transaction; tests exercise a midpoint crossing the spatial domain and full rollback. The weather provider itself has no per-query random side effect. Legacy `Environment.wind(time)` is weaker than `wind_world`: it only adds length-three noise and ignores other noise lengths rather than uniformly rejecting them. Production position-aware paths use `wind_world`; this is retained API debt, not a demonstrated production failure.

| Record | Implementation |
| --- | --- |
| Spatial identity | `FlightSession._spatial_weather_receipt` binds complete provider hash/epoch and station/aero laws. Configuration access returns detached copies. |
| Checkpoints | `FlightSession.checkpoint/restore` wraps the existing propulsion/contact versions for spatial weather and validates the receipt/current and prior samples before adoption. Spatial format is `openrc-flight-checkpoint v12`; later feature wrapping can coexist. |
| CSV | [trace.gd](../app/sim/trace.gd) selects feature-dependent schemas; spatial v16/v17 preserve base metadata and add datum/k1 coordinates and endpoint/k1 epoch times. The k1 load belongs to the previous body state/time, not the endpoint state. Legacy calm/wind/OU/custom-air formats remain distinct. |
| ORFL | [flight_log.gd](../app/sim/flight_log.gd) headers retain full weather, checkpoint, trace metadata, solver/backend identities; samples observe accepted-datum air. Reset/publication closes the old accepted recording. Exact replay requires matching source/runtime identity; candidate replay is explicitly solver-changed. |
| Native | [nk_weather.hpp](../research/native-kernel/src/nk_weather.hpp), [nk_spatial_weather.hpp](../research/native-kernel/src/nk_spatial_weather.hpp) reproduce field/atmosphere/thermal formulas; [nk_stage.hpp](../research/native-kernel/src/nk_stage.hpp) samples stage position/time and station flow. Native OU uses the already prepared session interval rather than a second RNG. |

`WeatherAdapter` guards built-in provider/configuration identity and rejects changed/custom providers; native construction receives resolved modes. The duplicated GDScript/C++ formulas, validation and point-flow paths require explicit parity maintenance. The application's default backend request and low-level session reference default differ; [native selection](../app/sim/native_stage.gd) and its adapters decide actual admission/fallback. A GDScript-focused test run is not native parity proof. `weather_oracle.gd` and `weather_stage_oracle.gd` contain parity cases, with standalone spatial stages requiring `include-spatial=true`; the full native `build.py` already supplies that option.

## UI, scenarios, companions and presentation

| Entry or consumer | Actual behavior and sample contract |
| --- | --- |
| [main.gd](../app/main.gd): `_weather_options` | Fixed-wing preset/file/numeric CLI inputs validate through WindConfig; direct technical defaults are calm. |
| [preferences.gd](../app/app_state/preferences.gd), [weather_dialog.gd](../app/ui/weather_dialog.gd) | Persist full weather with versioned preferences (v5 uses outer schema 6); separate draft Apply/Cancel, precise untouched values, mode/preset selection. |
| [spatial_weather_controls.gd](../app/ui/spatial_weather_controls.gd) | Patches represented profile keys while preserving independent upper wind. Timing edits retain the exact gust vector; intensity edits preserve its direction, using the shown reference direction only for a new zero-magnitude gust. Editing gust controls replaces a whole multi-event agenda with one event. Display rounding is not numeric authority. Summary shows ceiling/horizon; it does not expose all horizontal domain limits or edit the ceiling. Thermal agenda is retained, not generated from UI lighting. |
| [app_root.gd](../app/app_root.gd): `weather_for_aircraft`; [helicopter_main.gd](../app/helicopter_main.gd) | Home helicopter route strips unsupported OU without overwriting saved preferences; spatial/column can still reach session refusal. Direct helicopter weather CLI flags are not parsed (F03). |
| [natural_random.gd](../app/scenarios/natural_random.gd), [scenario_config.gd](../app/scenarios/scenario_config.gd) | Resolved seeded recipes require v3 weather. Lighting uses a separate domain; spatial thermal generation is not implemented here. |
| [companions/manager.gd](../app/ai/companions/manager.gd): `validate_context`, `_before_step`, `_after_step` | Explicitly refuses v5 and weather beyond its gentle envelope. Plans all agents from tick N observations, advances after player tick N+1 commits. No shared spatial-world admission. |
| [companions/agent.gd](../app/ai/companions/agent.gd): `configure` | Shares uniform mean/gust but sets OU seed `(player_seed+companion_seed+slot*104729)&0xffffffff`. Coincident aircraft generally see different turbulence. Seed zero/slot zero can equal the player seed. |
| [field.gd](../app/render/field.gd): windsock update; [windsock_motion.gd](../app/render/windsock_motion.gd): `update_to` | Samples fixed pole-head NED position through `wind_world`; invalid query freezes cue. Motion uses endpoint wind for all 120 Hz catch-up substeps; >0.5 s gap/rewind resets. Fixed internal substeps do not make its path render-cadence independent. |
| [main.gd](../app/main.gd): `_render_wind`; [world.gd](../app/render/world/world.gd): `update` | One aircraft-endpoint wind drives global vegetation/person/flower shader wind and campfire. Scenery locations are not independently sampled. |
| [sky_appearance_config.gd](../app/environment/sky_appearance_config.gd): `mean_wind_ned`; [cloud_transport.gd](../app/render/weather/cloud_transport.gd): `build` | Legacy mean-only follow-wind transport or explicit aloft motion. Spatial legacy speed is zero, so follow-wind cloud motion is zero (F02). |
| [flight_audio.gd](../app/audio/flight_audio.gd), [windsock_audio.gd](../app/audio/windsock_audio.gd) | Listener ambience and fabric gating use aircraft wind; sock inflation uses its local motion. These inputs can disagree in a spatial field. Aircraft airflow sound and ambient listener wind need different sample ownership. |
| [smoke/exhaust.gd](../app/render/smoke/exhaust.gd), smoke profile renderers, [crash/director.gd](../app/render/crash/director.gd) | Smoke uses an aircraft sample for extant particles; crash effects snapshot impact wind. Neither queries general spatial wind at each particle/debris point. |
| [birds/bird_tracks.gd](../app/scenery/birds/bird_tracks.gd), [bird_director.gd](../app/scenery/birds/bird_director.gd) | Authored closed circuits/climbs, solar/cloud activity modulation. Circling soarers do not identify physical thermal cells. |
| [storm_events.gd](../app/environment/storm_events.gd), [storm_bank.gd](../app/render/weather/storm_bank.gd) | Visual-seed lightning schedule/cloud/rain effects. No precipitation loading, physical downdraft, storm turbulence or heat forcing. |

## Findings

Severity here ranks engineering priority, not measured accident risk. **Defect** means an inspectable contradiction or wrong input; **contract gap** means a promised constraint is not enforced; **limitation** means a deliberately incomplete physical model or consumer. Source arguments below do not imply that a new reproducer was executed unless stated under verification.

| ID / priority / class | Trigger → consequence; code evidence | Required response |
| --- | --- | --- |
| F01 / P1 / defect | Active thermal at `0<r<4R`, crossing floor/top: `_cell_velocity` uses `w=P*sin²(pi*h/H)` then zero outside. Radial velocity slope at the ground is `-L*P*pi²*r*exp(-r²/R²)/H²`, nonzero; thermal-soaring preset cell at midlife/r=35 gives about −0.00381 s⁻¹. Thus total field is not C1-zero at the wall as `WindSpatialField.sample_world` claims; top has the analogous kink. `test_balanced_thermal_field` checks boundary values, not these one-sided slopes. Native thermal copies it. | Correct the continuity claim immediately in future code maintenance; version a smoother vertical streamfunction only with derivative/flux/trajectory evidence. No velocity jump or catastrophic instability is established. |
| F02 / P1 / defect | `SkyConfig.mean_wind_ned` reads legacy speed only; `WindConfig._validate_spatial` requires that speed zero. All spatial presets give zero follow-wind cloud advection through `CloudTransport.build`. | Explicit spatial background/cloud-height policy, shared conversion, regression for v5 plus legacy and explicit-aloft behavior. |
| F03 / P1 / defect | Direct rotorcraft routing supplies calm default; `helicopter_main` receives arguments but lacks fixed-wing `_weather_options`. `--weather=steady`, files and even invalid weather arguments are silently ignored there. | Resolve CLI weather before route dispatch or reject unsupported flags; retain helicopter capability refusals. |
| F04 / P1 / capability/UI gap | Home keeps spatial/column weather, `weather_for_aircraft` removes only OU, and helicopter `setup_weather` refuses after launch. | Centralize capability admission and explain unsupported selection before launch; do not silently replace spatial/column with calm. |
| F05 / P1 / defect | `CompanionManager._before_step` records player state/input without wind. `Pilot` traffic prediction falls back to its own `_planning_wind`; independent OU seeds mean it subtracts the wrong wind when predicting the player's banked trajectory. | Include player wind at the same observation tick; test unequal OU windows, heading/curvature and query purity. |
| F06 / P2 / contract gap | `WindAircraftFlow.matches_stage(air,s,rho)` validates time's type/range only, and accepts no expected time/model/provider. Same-state/rho receipts from another stage/model/provider can pass. Current inspected call sites construct fresh receipts; no live stale reuse was found. | Bind expected time and immutable model/provider identity at receipt consumption; avoid introducing a mutable cross-stage cache. |
| F07 / P3 / defect | Gust overlap admission compares `t<start+duration`, runtime compares `t-start<duration`. Binary64: `0.2+0.5==0.7`, but `0.7-0.2<0.5`. Four new events at 0.7 plus one ending event can pass a four-overlap bound yet count five runtime supports. Analogous thermal example: 999.9, 120.2, 1120.1. Near-end pulse is negligible and new pulses are zero; no material speed-bound violation is proved. | Align interval predicates in validators and evaluators, test representable neighbors and legacy admission compatibility; preserve pulse arithmetic. |
| F08 / P2 / limitation | `World.update`, audio and smoke use aircraft wind at distant fixed/particle locations; windsock is local. Moving aircraft through shear can change all scenery/listener ambience and mismatch fabric gating. | Declare each observer's position/time; sample fixed cues locally and budget cosmetic particle approximations explicitly. |
| F09 / P2 / presentation defect | `Main._advance_windsock_to` coalesces ticks; `WindsockMotion.update_to` applies newest wind to all catch-up steps. Time-varying wind produces different visual motion at different render cadence. | Reconstruct/consume each cue timestep's physical sample or explicitly qualify approximation with cadence-error bounds. |
| F10 / P1 qualification / limitation | Default max-height 200 m equals thermal preset top; any raised wing/tail/hub can leave domain before datum reaches ceiling. Epoch offset shortens usable horizon. UI ceiling is informational. | Cover station-aware bounds and exact refusal UX; author scenario domain with clearance or expose explicit domain configuration. Retain fail-closed behavior. |
| F11 / P1 qualification / limitation | Curl modes and thermal streamfunction conserve volume, but `standard_column` supplies varying density. `div(rho*W)` is generally nonzero for vertical flow. | Declare approximation, quantify flux residual over accepted scenarios; only adopt an anelastic law if required, as a distinct version. |
| F12 / P1 qualification / limitation | Scalar nominal spatial RMS and quasi-periodic modes are neither local/component RMS nor a calibrated spectrum/coherence law (`_resolve_modes`, `_turbulence_wind`). | Measure generated covariance/PSD/height dependence and compare held-out site data before realism claims or default changes. |
| F13 / P1 qualification / limitation | Spatial matched aero retains reference wake; propulsion representation can change hub-rotation semantics; full-angle continuation does not validate gradient stall behavior. | Force ownership ledger, constant-field cross-law decomposition, refinement and held-out differential-gust/wake cases. |
| F14 / P2 / architecture debt | GDScript/native weather, field math, station flow and continuation duplicate laws; legacy `Environment.wind` validation differs from `wind_world`. There is no packed batch sampling interface; every point reconstructs result arrays/dictionaries. | Enforce one contract and paired oracles; remove measured duplicate construction before considering a new cache or changing resolution. |
| F15 / P1 promotion / limitation | Research multirotor thrust/torque ignore density/axial inflow and use one datum wind; ground vehicles do not consume wind; helicopter intentionally excludes spatial/OU/column. | Keep per-vehicle gates. Add only explicitly scoped model adapters and validation; no generic kernel weather-force branch. |
| F16 / P2 / UX/semantic gap | Spatial gust edit reduces a full agenda to one event; “Realistic” label lacks measured qualification; birds/storms are independent visual phenomena. | Make replacement/finite agenda and experimental status explicit; distinguish physical thermal cues from decorative ones. |
| F17 / P1 / defect | `FlightSession._hand_launch_rpm` uses ground-relative axial speed for v1–v4, subtracting local wind only in the spatial branch. `_reset_hand_launch_start` uses `_weather.sample(0)` for legacy heading, omitting initial OU. The admitted gearless MoonRunner can start at an RPM inconsistent with its first air-relative prop load, or select the wrong runway direction for initial OU. | Initialize from reset-time combined wind/local hub flow for every supported weather law; test steady head/tailwind, seeded OU, release heading, torque balance and replay while preserving the ground-relative throw. |

Other retained limitations: spatial ground is flat despite contact terrain; no obstacle wakes/ridge/valley solver, no thermal heat/stability/cloud prediction, no shared aircraft wakes, no live mean-weather transition, and no world-owned spatial companion epoch. These follow from the cited provider/consumer paths; they are not promises to add every feature.

## Verification

The 2026-10-31 audit ran **24 distinct focused GDScript programs: 4,579 checks, zero failures**, through the existing checked runner on Linux x86_64, Godot `4.8.beta1.official.4d10419ca`. The [compact receipt](research/wind-implementation/audit-2026-10-31.json) retains commands, completed verdicts, log hashes and selected source hashes. Raw checked reports/logs remain in ignored `tmp/wind-audit-20261031/checks/` and `tmp/wind-audit-airflow/`; the test programs are retained and reproducible through the [checked runner](../tools/godot/README.md).

| Program (`app/tests/`) | Checks | Result |
| --- | ---: | --- |
| [test_atmosphere](../app/tests/test_atmosphere.gd) | 149 | Pass |
| [test_atmosphere_column](../app/tests/test_atmosphere_column.gd) | 83 | Pass |
| [test_balanced_thermal_field](../app/tests/test_balanced_thermal_field.gd) | 57 | Pass |
| [test_dr_multirotor_kernel](../app/tests/test_dr_multirotor_kernel.gd) | 15 | Pass |
| [test_sf_environment](../app/tests/test_sf_environment.gd) | 27 | Pass |
| [test_spatial_aero_continuation](../app/tests/test_spatial_aero_continuation.gd) | 91 | Pass |
| [test_spatial_powered_stage](../app/tests/test_spatial_powered_stage.gd) | 277 | Pass |
| [test_spatial_propulsion_flow](../app/tests/test_spatial_propulsion_flow.gd) | 29 | Pass |
| [test_spatial_stage_lean](../app/tests/test_spatial_stage_lean.gd) | 668 | Pass |
| [test_spatial_thermal_response](../app/tests/test_spatial_thermal_response.gd) | 33 | Pass |
| [test_spatial_wash](../app/tests/test_spatial_wash.gd) | 30 | Pass |
| [test_spatial_weather_session](../app/tests/test_spatial_weather_session.gd) | 101 | Pass |
| [test_spatial_weather_trace](../app/tests/test_spatial_weather_trace.gd) | 351 | Pass |
| [test_spatial_wind_aerodynamics](../app/tests/test_spatial_wind_aerodynamics.gd) | 189 | Pass |
| [test_spatial_wind_contract](../app/tests/test_spatial_wind_contract.gd) | 176 | Pass |
| [test_spatial_wind_field](../app/tests/test_spatial_wind_field.gd) | 155 | Pass |
| [test_spatial_wind_prepared](../app/tests/test_spatial_wind_prepared.gd) | 1543 | Pass |
| [test_turbulence_flight](../app/tests/test_turbulence_flight.gd) | 161 | Pass |
| [test_weather_publication](../app/tests/test_weather_publication.gd) | 196 | Pass |
| [test_wind_aircraft_flow](../app/tests/test_wind_aircraft_flow.gd) | 88 | Pass |
| [test_wind_field](../app/tests/test_wind_field.gd) | 66 | Pass |
| [test_wind_flight](../app/tests/test_wind_flight.gd) | 51 | Pass |
| [test_wind_turbulence](../app/tests/test_wind_turbulence.gd) | 29 | Pass |
| [test_wind_world_consumers](../app/tests/test_wind_world_consumers.gd) | 14 | Pass |

Documentation verification checked 1,480 new/affected destinations against the initial baseline in the working tree, then 524 new destinations/anchors against the final snapshot in a fresh sparse local clone using cloned Git objects. All 37 retired narratives are absent; retained artifact links resolve. Website generation matches all 11 locales and its five static tests and the 20 documentation-checker tests pass; `git diff --check` passes. Shared-tree commits landed during the audit; all 255 selected source hashes still match the reviewed/tested bytes. The receipt identifies the exact checked tree and limits.

Three first attempts used the wrong required completion text (`0 failed` instead of the programs' `0 failures`); the runner correctly rejected those attempts despite process exit zero. All three were rerun with their correct marker and completed successfully. Both attempts remain in the receipt. Duplicate specialist runs are not double-counted.

The source audit also checked the F07 binary64 endpoint arithmetic and derived F01's one-sided thermal derivative. New defect-specific engine reproductions were not added in this documentation change. Existing passes therefore do **not** close the findings. In particular, thermal-response refinement reports maximum mixed-body-component differences of about 0.00124135 for 240/480 Hz and 0.000619432 for 480/960 Hz: this is a software trend, approximately first order in that diagnostic, not a fourth-order full-flight or physical validation claim.

The full `app/test.sh`, new native-oracle build, target-host performance, real-time 1080p rendering, audio listening and field/pilot validation were not run. No performance claim is based on concurrent audit/test work. Initial unrelated edits in `app/audio/helicopter_audio.gd`, `app/render/world/campfire.gd`, their two tests, and the AUD-15/FW-67-74 evidence files were preserved; presentation observations refer to those working-tree bytes. Runtime/aircraft data and goldens remain unchanged by this audit.

## Historical evidence

The following artifacts retain earlier implementation and research evidence. They are **historical inputs**, not current acceptance claims. Their manifests, source overlays, checked logs and scripts define their original scope; this audit did not rerun old performance/export experiments. Raw data and recordings have not been removed. Narrative claims superseded by current code have been replaced by the reference above.

<a id="evidence-wind-implementation"></a>

**wind-implementation**

[artifact directory](research/wind-implementation) · [manifest.json](research/wind-implementation/M5-W01d/manifest.json) · [package-smoke.json](research/wind-implementation/M5-W01d/package-smoke.json)

<a id="evidence-wind-implementation-m5-w05d-r1"></a>

**wind-implementation/M5-W05d-R1**

[artifact directory](research/wind-implementation/M5-W05d-R1) · [baseline-manifest.json](research/wind-implementation/M5-W05d-R1/baseline-manifest.json) · [candidate-manifest.json](research/wind-implementation/M5-W05d-R1/candidate-manifest.json) · [checkout-verification.json](research/wind-implementation/M5-W05d-R1/checkout-verification.json) · [merge_os_capture.py](research/wind-implementation/M5-W05d-R1/fixture-capture/merge_os_capture.py) · [reconstruct_preopt.sh](research/wind-implementation/M5-W05d-R1/fixture-capture/reconstruct_preopt.sh) · [candidate-summary.json](research/wind-implementation/M5-W05d-R1/flights/candidate-summary.json) · [parse-checks.json](research/wind-implementation/M5-W05d-R1/parse-checks.json) · [presentation-regeneration.json](research/wind-implementation/M5-W05d-R1/presentation-regeneration.json) · [ui-review.json](research/wind-implementation/M5-W05d-R1/ui-review.json) · [verification.json](research/wind-implementation/M5-W05d-R1/verification.json)

<a id="evidence-wind-implementation-m5-w05d-r2"></a>

**wind-implementation/M5-W05d-R2**

[physics](research/wind-implementation/M5-W05d-R1/candidate-source/app/physics) · [artifact directory](research/wind-implementation/M5-W05d-R2) · [checkout-verification.json](research/wind-implementation/M5-W05d-R2/checkout-verification.json) · [linux-20261028](research/wind-implementation/M5-W05d-R2/checks/linux-20261028) · [report.json](research/wind-implementation/M5-W05d-R2/checks/linux-20261028/fresh-clone-minimal/report.json) · [engine.log](research/wind-implementation/M5-W05d-R2/checks/linux-20261028/fresh-clone/engine.log) · [report.json](research/wind-implementation/M5-W05d-R2/checks/record-boundary-fixture-r0rdptyc/report.json) · [comparison-manifest.json](research/wind-implementation/M5-W05d-R2/comparison-manifest.json) · [payload-manifest.json](research/wind-implementation/M5-W05d-R2/payload-manifest.json) · [record_boundary_fixture.gd](research/wind-implementation/M5-W05d-R2/record_boundary_fixture.gd) · [root-before-comparison.json](research/wind-implementation/M5-W05d-R2/root-before-comparison.json)

<a id="evidence-wind-implementation-m5-w01a"></a>

**wind-implementation/M5-W01a**

[artifact directory](../research/wind/M5-W01a) · [app-test.log](../research/wind/M5-W01a/app-test.log) · [baseline.json](../research/wind/M5-W01a/baseline.json) · [compare_core.py](../research/wind/M5-W01a/compare_core.py) · [core-calm.json](../research/wind/M5-W01a/core-calm.json) · [core-comparison.txt](../research/wind/M5-W01a/core-comparison.txt) · [core-gusty.json](../research/wind/M5-W01a/core-gusty.json) · [core-source-manifest.json](../research/wind/M5-W01a/core-source-manifest.json) · [core-steady.json](../research/wind/M5-W01a/core-steady.json)

<a id="evidence-wind-implementation-m5-w04a"></a>

**wind-implementation/M5-W04a**

[artifact directory](research/wind-implementation/M5-W04a) · [cost-baseline.json](research/wind-implementation/M5-W04a/cost-baseline.json) · [cost-steady.json](research/wind-implementation/M5-W04a/cost-steady.json) · [cost-turbulent.json](research/wind-implementation/M5-W04a/cost-turbulent.json) · [native-flight.json](research/wind-implementation/M5-W04a/native-flight.json) · [native_compare.py](research/wind-implementation/M5-W04a/native_compare.py) · [older-reader.json](research/wind-implementation/M5-W04a/older-reader.json) · [schema_probe.gd](research/wind-implementation/M5-W04a/schema_probe.gd) · [source-manifest.json](research/wind-implementation/M5-W04a/source-manifest.json) · [statistics.json](research/wind-implementation/M5-W04a/statistics.json)

<a id="evidence-wind-implementation-m5-w05c-r1"></a>

**wind-implementation/M5-W05c-R1**

[artifact directory](research/wind-implementation/M5-W05c-R1) · [manifest.json](research/wind-implementation/M5-W05c-R1/baseline-source/manifest.json) · [baseline-verification.json](research/wind-implementation/M5-W05c-R1/baseline-verification.json) · [checks](research/wind-implementation/M5-W05c-R1/checks) · [gp_extra_300s_60](research/wind-implementation/M5-W05c-R1/flights/gp_extra_300s_60) · [jensen_ugly_stik_60](research/wind-implementation/M5-W05c-R1/flights/jensen_ugly_stik_60) · [p51d_mustang_120](research/wind-implementation/M5-W05c-R1/flights/p51d_mustang_120) · [sebart_avanti_s_a200](research/wind-implementation/M5-W05c-R1/flights/sebart_avanti_s_a200) · [stik_glow_61fx_2t](research/wind-implementation/M5-W05c-R1/flights/stik_glow_61fx_2t) · [turbo_lumber_evolution](research/wind-implementation/M5-W05c-R1/flights/turbo_lumber_evolution) · [verification.json](research/wind-implementation/M5-W05c-R1/verification.json)

<a id="evidence-wind-implementation-m5-w05d-r5"></a>

**wind-implementation/M5-W05d-R5**

[artifact directory](research/wind-implementation/M5-W05d-R5) · [checkout-verification.json](research/wind-implementation/M5-W05d-R5/checkout-verification.json) · [cli-verification.json](research/wind-implementation/M5-W05d-R5/cli-verification.json) · [integrated-stable-after.json](research/wind-implementation/M5-W05d-R5/integrated-stable-after.json) · [integrated-stable-before.json](research/wind-implementation/M5-W05d-R5/integrated-stable-before.json) · [integration-comparison.json](research/wind-implementation/M5-W05d-R5/integration-comparison.json) · [original-source-manifest.json](research/wind-implementation/M5-W05d-R5/original-source-manifest.json) · [payload-manifest.json](research/wind-implementation/M5-W05d-R5/payload-manifest.json) · [reproduction-manifest.json](research/wind-implementation/M5-W05d-R5/reproduction-manifest.json) · [summary.json](research/wind-implementation/M5-W05d-R5/workloads/summary.json)

<a id="evidence-wind-implementation-m5-w05b-r1"></a>

**wind-implementation/M5-W05b-R1**

[artifact directory](research/wind-implementation/M5-W05b-R1) · [manifest.json](research/wind-implementation/M5-W05b-R1/baseline-source/manifest.json) · [baseline-verification.json](research/wind-implementation/M5-W05b-R1/baseline-verification.json) · [checks](research/wind-implementation/M5-W05b-R1/checks) · [gp_extra_300s_60](research/wind-implementation/M5-W05b-R1/flights/gp_extra_300s_60) · [jensen_ugly_stik_60](research/wind-implementation/M5-W05b-R1/flights/jensen_ugly_stik_60) · [p51d_mustang_120](research/wind-implementation/M5-W05b-R1/flights/p51d_mustang_120) · [sebart_avanti_s_a200](research/wind-implementation/M5-W05b-R1/flights/sebart_avanti_s_a200) · [stik_glow_61fx_2t](research/wind-implementation/M5-W05b-R1/flights/stik_glow_61fx_2t) · [turbo_lumber_evolution](research/wind-implementation/M5-W05b-R1/flights/turbo_lumber_evolution) · [verification.json](research/wind-implementation/M5-W05b-R1/verification.json)

<a id="evidence-wind-implementation-m5-w03b"></a>

**wind-implementation/M5-W03b**

[artifact directory](../research/wind/M5-W03b) · [capture.gd](../research/wind/M5-W03b/capture.gd) · [home-es-1280x720.json](../research/wind/M5-W03b/captures/home-es-1280x720.json) · [flight-gusty-en-1280x720.json](../research/wind/M5-W03b/captures/release/flight-gusty-en-1280x720.json) · [flight-gusty-es-1280x720.json](../research/wind/M5-W03b/captures/release/flight-gusty-es-1280x720.json) · [home-en-1280x720.json](../research/wind/M5-W03b/captures/release/home-en-1280x720.json) · [home-es-1280x720.json](../research/wind/M5-W03b/captures/release/home-es-1280x720.json) · [modal-gusty-en-1024x720.json](../research/wind/M5-W03b/captures/release/modal-gusty-en-1024x720.json) · [modal-gusty-en-1920x1080.json](../research/wind/M5-W03b/captures/release/modal-gusty-en-1920x1080.json) · [modal-gusty-es-1280x720.json](../research/wind/M5-W03b/captures/release/modal-gusty-es-1280x720.json) · [modal-steady-en-1280x720.json](../research/wind/M5-W03b/captures/release/modal-steady-en-1280x720.json) · [modal-steady-es-1024x720.json](../research/wind/M5-W03b/captures/release/modal-steady-es-1024x720.json) · [source-manifest.json](../research/wind/M5-W03b/captures/release/source-manifest.json)

<a id="evidence-wind-implementation-m5-w05d-r4"></a>

**wind-implementation/M5-W05d-R4**

[artifact directory](research/wind-implementation/M5-W05d-R4) · [baseline-manifest.json](research/wind-implementation/M5-W05d-R4/baseline-manifest.json) · [candidate-manifest.json](research/wind-implementation/M5-W05d-R4/candidate-manifest.json) · [checkout-verification.json](research/wind-implementation/M5-W05d-R4/checkout-verification.json) · [integrated-after.json](research/wind-implementation/M5-W05d-R4/integrated-after.json) · [integrated-before.json](research/wind-implementation/M5-W05d-R4/integrated-before.json) · [payload-manifest.json](research/wind-implementation/M5-W05d-R4/payload-manifest.json) · [parity.json](research/wind-implementation/M5-W05d-R4/replays/parity.json)

<a id="evidence-wind-implementation-m5-w05d-r6"></a>

**wind-implementation/M5-W05d-R6**

[workloads](research/wind-implementation/M5-W05d-R5/workloads) · [artifact directory](research/wind-implementation/M5-W05d-R6) · [checkout-verification.json](research/wind-implementation/M5-W05d-R6/checkout-verification.json) · [comparison-manifest.json](research/wind-implementation/M5-W05d-R6/comparison-manifest.json) · [integrated-after.json](research/wind-implementation/M5-W05d-R6/integrated-after.json) · [integrated-before.json](research/wind-implementation/M5-W05d-R6/integrated-before.json) · [integration-comparison.json](research/wind-implementation/M5-W05d-R6/integration-comparison.json) · [payload-manifest.json](research/wind-implementation/M5-W05d-R6/payload-manifest.json) · [pinned-sequence.json](research/wind-implementation/M5-W05d-R6/pinned-sequence.json) · [parity.json](research/wind-implementation/M5-W05d-R6/replay/parity.json) · [timing-affinity.json](research/wind-implementation/M5-W05d-R6/timing-affinity.json) · [workload-parity.json](research/wind-implementation/M5-W05d-R6/workload-parity.json)

### Observer datum reuse (M5-W-AUD-22 / WOPT-02, 2026-11-09)

`FlightSession.observer_air_and_wind` gives the overlay one full air-data receipt
and a detached datum wind for the same accepted state/time/provider observation.
Successful spatial sampling reuses its already sampled datum; failed station
validation retains invalid air and independently samples the datum for the HUD.
No frame/stage cache or datum-only substitute is introduced. Legacy weather,
pending reset, non-endpoint calls and derived session overrides preserve the old
wind-then-air sequence; the overlay also retains its original Node-adapter path.
Spatial refusal samples the fallback datum after validation, relying on the
environment's pure deterministic provider contract.

[Windows checked evidence](research/wind-implementation/M5-W05d-R6/wopt02-20261109.json)
includes 161 checks through the actual overlay snapshot, 738 existing lean-stage,
25 fuel-overlay and 12 battery-overlay checks. Entire overlay bytes match an
independent old-sequence session. Stik at 8/24/64 modes and three times uses
10 rather than 11 provider calls; X99 at 24 modes uses 9 rather than 10. Refusal
counts, station order/time, ownership, changed providers, signed zero, pending
reset and unchanged checkpoints are covered. This is a bounded call-count and
software-parity result, not a measured frame/FPS gain. Full CI, native package,
target performance and physical qualification remain separate.

### Thermal query reuse (M5-W-AUD-21 / WOPT-01, 2026-11-08)

`WindThermalField._cell_velocity` allocates its zero result only on inactive
returns and evaluates the repeated vertical sine once. The original left-to-right
multiplication and cell/axis accumulation order remain intact; every query owns
its result and there is no persistent cache or law/configuration change.

The [baseline comparator](../research/wind/thermal_parity.gd) compares a retained
`a3f2e38` provider against the current source on the same engine/host. Windows
headless checks pass **63,613** result-byte, identity and ownership assertions:
20,000 seeded queries over 0/1/4/16-cell agendas, lifecycle/taper/height boundaries,
invalid queries, signed zeros, and mutation of one of two held outputs. Existing
analytic thermal, aircraft response/refinement and spatial session/checkpoint
suites pass 73, 33 and 111 checks. The [evidence index](research/wind-implementation/M5-W05d-R6/wopt01-2026-11-08.json)
records source and checked-log identities.

Reproduce by retaining `git show a3f2e38:app/physics/wind_thermal_field.gd` outside
`app/`, then running the comparator through the checked runner with
`-- --baseline=<absolute retained file>`. No baseline is rewritten. Native
installation/fleet/package, required CI and complete-session/frame performance
remain separate gates. A changed mirrored source invalidates older native
receipts and selects the reference until independently requalified. No new
speedup, FPS, target-hardware or physical claim is made.

<a id="evidence-wind-implementation-m5-w04b-r1"></a>

**wind-implementation/M5-W04b-R1**

[artifact directory](research/wind-implementation/M5-W04b-R1) · [cost.json](research/wind-implementation/M5-W04b-R1/cost.json) · [gust-and-turn.gif](research/wind-implementation/M5-W04b-R1/gust-and-turn.gif) · [verification.json](research/wind-implementation/M5-W04b-R1/verification.json)

<a id="evidence-wind-implementation-m5-w05d-r3"></a>

**wind-implementation/M5-W05d-R3**

[artifact directory](research/wind-implementation/M5-W05d-R3) · [baseline-manifest.json](research/wind-implementation/M5-W05d-R3/baseline-manifest.json) · [candidate-manifest.json](research/wind-implementation/M5-W05d-R3/candidate-manifest.json) · [checkout-verification.json](research/wind-implementation/M5-W05d-R3/checkout-verification.json) · [integrated-source-observation.json](research/wind-implementation/M5-W05d-R3/integrated-source-observation.json) · [payload-manifest.json](research/wind-implementation/M5-W05d-R3/payload-manifest.json) · [parity.json](research/wind-implementation/M5-W05d-R3/replays-final/parity.json) · [spatial-exact.json](research/wind-implementation/M5-W05d-R3/replays-final/spatial-exact.json)

<a id="evidence-wind-implementation-m5-w05c-r2"></a>

**wind-implementation/M5-W05c-R2**

[artifact directory](research/wind-implementation/M5-W05c-R2) · [manifest.json](research/wind-implementation/M5-W05c-R2/baseline-source/manifest.json) · [baseline-verification.json](research/wind-implementation/M5-W05c-R2/baseline-verification.json) · [flight_session.gd](research/wind-implementation/M5-W05c-R2/candidate-source/app/sim/flight_session.gd) · [manifest.json](research/wind-implementation/M5-W05c-R2/candidate-source/manifest.json) · [checks](research/wind-implementation/M5-W05c-R2/checks) · [gp_extra_300s_60](research/wind-implementation/M5-W05c-R2/flights/gp_extra_300s_60) · [jensen_ugly_stik_60](research/wind-implementation/M5-W05c-R2/flights/jensen_ugly_stik_60) · [p51d_mustang_120](research/wind-implementation/M5-W05c-R2/flights/p51d_mustang_120) · [sebart_avanti_s_a200](research/wind-implementation/M5-W05c-R2/flights/sebart_avanti_s_a200) · [stik_glow_61fx_2t](research/wind-implementation/M5-W05c-R2/flights/stik_glow_61fx_2t) · [turbo_lumber_evolution](research/wind-implementation/M5-W05c-R2/flights/turbo_lumber_evolution) · [verification.json](research/wind-implementation/M5-W05c-R2/verification.json)

<a id="evidence-wind-investigations"></a>

**wind-investigations**

[artifact directory](research/wind-investigations) · [config-controls-probe.json](research/wind-investigations/config-controls-probe.json) · [probe_config_controls.gd](research/wind-investigations/probe_config_controls.gd) · [probe_scipy_wind_analysis.py](research/wind-investigations/probe_scipy_wind_analysis.py) · [scipy-wind-analysis-results.json](research/wind-investigations/scipy-wind-analysis-results.json)

<a id="evidence-atmosphere-m5-atm-2"></a>

**atmosphere/M5-ATM-2**

[artifact directory](research/atmosphere/M5-ATM-2) · [cost-baseline-calm.json](research/atmosphere/M5-ATM-2/cost-baseline-calm.json) · [cost-candidate-calm.json](research/atmosphere/M5-ATM-2/cost-candidate-calm.json) · [cost-candidate-hot-high.json](research/atmosphere/M5-ATM-2/cost-candidate-hot-high.json) · [export-results.json](research/atmosphere/M5-ATM-2/export-results.json) · [hot-high.json](research/atmosphere/M5-ATM-2/hot-high.json) · [native-results.json](research/atmosphere/M5-ATM-2/native-results.json) · [native_compare.py](research/atmosphere/M5-ATM-2/native_compare.py) · [older-reader.json](research/atmosphere/M5-ATM-2/older-reader.json) · [schema_probe.gd](research/atmosphere/M5-ATM-2/schema_probe.gd) · [source-manifest.json](research/atmosphere/M5-ATM-2/source-manifest.json) · [test-gate.json](research/atmosphere/M5-ATM-2/test-gate.json)

<a id="evidence-atmosphere-m5-atm-1-sources"></a>

**atmosphere/M5-ATM-1/sources**

[reference_check.py](research/atmosphere/M5-ATM-1/kernel/reference_check.py) · [reference_results.json](research/atmosphere/M5-ATM-1/kernel/reference_results.json)

<a id="evidence-atmosphere-m5-atm-1-kernel"></a>

**atmosphere/M5-ATM-1/kernel**

[artifact directory](research/atmosphere/M5-ATM-1/kernel) · [reference_check.py](research/atmosphere/M5-ATM-1/kernel/reference_check.py) · [reference_results.json](research/atmosphere/M5-ATM-1/kernel/reference_results.json)

<a id="evidence-wind-m5-w01a"></a>

**wind/M5-W01a**

[artifact directory](../research/wind/M5-W01a) · [app-test.log](../research/wind/M5-W01a/app-test.log) · [baseline.json](../research/wind/M5-W01a/baseline.json) · [compare_core.py](../research/wind/M5-W01a/compare_core.py) · [core-calm.json](../research/wind/M5-W01a/core-calm.json) · [core-comparison.txt](../research/wind/M5-W01a/core-comparison.txt) · [core-gusty.json](../research/wind/M5-W01a/core-gusty.json) · [core-source-manifest.json](../research/wind/M5-W01a/core-source-manifest.json) · [core-steady.json](../research/wind/M5-W01a/core-steady.json)

<a id="evidence-wind-godot-integration"></a>

**wind-godot-integration**

[artifact directory](research)

<a id="evidence-wind-physics-primary-sources"></a>

**wind-physics-primary-sources**

[artifact directory](research)

<a id="evidence-roadmap-investigations-07-atmosphere-wind-turbulence"></a>

**roadmap-investigations/07-atmosphere-wind-turbulence**

[artifact directory](research/roadmap-investigations)


### Retained research rationale

Historical notebooks identified distinctions still visible in code: physical simulation time must be separate from shader wrapping; query order cannot advance weather RNG; untouched UI values must retain precision; spatial coherence requires a common position/time field; potential taper derivatives matter for divergence; a balanced plume requires return circulation; nominal spectra and byte parity do not establish meteorological realism. The current equations, defects and roadmap supersede their earlier implementation recommendations.

Historical performance receipts compare different engines, hosts and source snapshots. In particular, R5 workload verification is untimed and the R6 interrupted/contaminated timing pair is excluded from performance conclusions. R1/R2 and atmosphere batch timings cannot establish current native performance or 1080p qualification. Use retained manifests/reconstruction scripts in disposable checkouts and import their resources before replay. Do not overwrite baseline recordings.

### Preserved source bibliography

These links are preserved from the consolidated research for provenance and future independent validation. They were not consulted as evidence for current implementation in this code-only audit; no new claim about their contents or current versions is made here.

- [NWS: Wind Direction](https://forecast.weather.gov/glossary.php?word=WIND+DIRECTION)

- [FAA JO 7900.5E, cap. 7](https://www.faa.gov/media/70751)

- [Documentación y código de los setters](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGWinds.html)

- [NASA-CR-2288, *A model of wind shear and turbulence in the surface boundary layer*](https://ntrs.nasa.gov/citations/19730018294)

- [GovInfo, 14 CFR §25.341](https://www.govinfo.gov/content/pkg/CFR-2022-title14-vol1/pdf/CFR-2022-title14-vol1-sec25-341.pdf)

- [FAA AC 25.341-1: Dynamic Gust Loads](https://www.faa.gov/documentLibrary/media/Advisory_Circular/AC_25_341-1.pdf)

- [JSBSim `CosineGustProfile` source](https://jsbsim-team.github.io/jsbsim/FGWinds_8cpp_source.html)

- [NASA-TM-78141, *A technique for simulating turbulence for aerospace vehicle flight simulation studies*](https://ntrs.nasa.gov/archive/nasa/casi.ntrs.nasa.gov/19780004071.pdf)

- [Madden, NASA, *Verifying Implementation of the Dryden Turbulence Model and MIL-F-8785 Gust Gradient*](https://ntrs.nasa.gov/search.jsp?R=20190000875)

- [Yeager, NASA/CR-1998-206937](https://ntrs.nasa.gov/citations/19980028448)

- [NASA-TM-2008-215633, §2.3.13](https://ntrs.nasa.gov/api/citations/20090022159/downloads/20090022159.pdf)

- [NASA-CR-2886, low-altitude turbulence measurements](https://ntrs.nasa.gov/citations/19770025195)

- [NASA-CR-178288, *Analyses and assessments of spanwise gust gradient data*](https://ntrs.nasa.gov/citations/19880000625)

- [U.S. Standard Atmosphere, 1976](https://ntrs.nasa.gov/api/citations/19770009539/downloads/19770009539.pdf)

- [NDARC Theory Manual, §4–5 Environment and Atmosphere](https://rotorcraft.arc.nasa.gov/Publications/files/NDARCTheory_v1_6_938.pdf)

- [Comparison of Fuel Consumption of Descent Trajectories](https://aviationsystems.arc.nasa.gov/publications/2012/AIAA-2012-4818.pdf)

- [New Equations for Computing Vapor Pressure and Enhancement Factor](https://doi.org/10.1175/1520-0450(1981)

- [Water Vapor Pressure Formulations](https://www.eol.ucar.edu/data-software/conventions-and-standards/water-vapor-pressure-formulations)

- [Revised formula for the density of moist air (CIPM-2007)](https://www.nist.gov/system/files/documents/calibrations/CIPM-2007.pdf)

- [Pressure Altitude and Density Altitude spreadsheet guide, TM-215](https://www.weather.gov/media/wrh/online_publications/TMs/TM-215.pdf)

- [TR-426: The Effect of Humidity on Engine Power at Altitude](https://ntrs.nasa.gov/archive/nasa/casi.ntrs.nasa.gov/19930091500.pdf)

- [AC 150/5345-27F](https://www.faa.gov/regulations_policies/advisory_circulars/index.cfm/go/document.information/documentID/1040591)

- [AC PDF](https://www.faa.gov/documentLibrary/media/Advisory_Circular/150-5345-27F-Wind-Cone.pdf)

- [AIM guidance on airport visual indicators](https://www.faa.gov/air_traffic/publications/atpubs/AIM/aim0403.html)

- [TAF wind convention](https://www.faa.gov/air_traffic/publications/atpubs/aim_html/chap7_section_1.html)

- [Annex 14, Volume I catalogue](https://store.icao.int/en/annex-14-aerodromes)

- [ICAO AP-ADO/TF/7 working paper](https://www.icao.int/sites/default/files/APAC/Meetings/2026/2026%20AP-ADO-TF-7/03-Working%20Papers/WP16-AI5-Development-of-Guidance-Material-on-the-Use-of-As-Far-As-Practicable-AFAP-Rev.1-A.pdf)

<a id="evidence-weather-publication"></a>

**GP-14h weather publication**

Historical publication evidence covers pending weather, observer reentry/fault handling and closure of the old recording. Its source subset is not a complete application identity. Current behavior is described under lifecycle above.

[artifact directory](research/ground-physics/GP-14/evidence/weather-publication)

<a id="evidence-atmosphere-reset-baseline"></a>

**LU-06 historical atmosphere reset baseline**

Historical Godot 4.7.2 native/WSL comparison diagnosed a platform-sensitive extreme-air trim refusal and a test reading an empty checkpoint. Retained logs describe that snapshot only; current acceptance follows the tests above.

[artifact directory](research/landscape-upgrade/LU-06)

<a id="evidence-wind-source-collection"></a>

**Acquired wind/thermal/terrain validation sources**

The 2026-10-19 acquired collection distinguishes measured atmospheric flow, generated turbulence and inferred UAV wind. Catalog/provenance files retain acquisition outcomes, original references and applicability limits; terrain or full-scale datasets do not automatically calibrate RC presets.

[sources.json](research/flight-dynamics/rc-validation-library-2026-10-18/wind-weather/sources.json) · [doi.org](https://doi.org/10.1007/BF00122351) · [doi.org](https://doi.org/10.1175/1520-0469%281988%29045%3C0727%3Atsotcb%3E2.0.co%3B2) · [doi.org](https://doi.org/10.1175/1520-0469%281988%29045%3C2039%3Atsotcb%3E2.0.co%3B2) · [elib.dlr.de](https://elib.dlr.de/210473/) · [doi.org](https://doi.org/10.5194/essd-14-19-2022) · [doi.org](https://doi.org/10.25921/jhnd-8e58) · [doi.org](https://doi.org/10.5194/essd-16-2525-2024) · [arxiv.org](https://arxiv.org/abs/2608.00241) · [ntrs.nasa.gov](https://ntrs.nasa.gov/citations/20070022339) · [doi.org](https://doi.org/10.1038/s41586-018-0533-0) · [arxiv.org](https://arxiv.org/abs/1802.08215) · [ntrs.nasa.gov](https://ntrs.nasa.gov/citations/20060004052) · [doi.org](https://doi.org/10.1038/s41467-024-48670-x) · [ntrs.nasa.gov](https://ntrs.nasa.gov/citations/19780004071) · [ntrs.nasa.gov](https://ntrs.nasa.gov/citations/19770025195) · [ntrs.nasa.gov](https://ntrs.nasa.gov/citations/19880000625) · [orbit.dtu.dk](https://orbit.dtu.dk/en/publications/the-great-belt-coherence-experiment-a-study-of-atmospheric-turbul/) · [doi.org](https://doi.org/10.1016/j.egypro.2016.09.199) · [www.datacommons.psu.edu](https://www.datacommons.psu.edu/commonswizard/MetadataDisplay.aspx?Dataset=6506) · [doi.org](https://doi.org/10.3390/atmos8100195) · [doi.org](https://doi.org/10.1594/PANGAEA.946960) · [doi.org](https://doi.org/10.3390/atmos10030124) · [doi.org](https://doi.org/10.5194/amt-18-2103-2025) · [ntrs.nasa.gov](https://ntrs.nasa.gov/citations/20200003206) · [doi.org](https://doi.org/10.1029/2003JE002161) · [faculty.washington.edu](https://faculty.washington.edu/dcatling/Tratt_etal2003.pdf) · [repository.library.noaa.gov](https://repository.library.noaa.gov/view/noaa/32477) · [doi.org](https://doi.org/10.1175/2009JTECHA1260.1) · [www.pa.op.dlr.de](https://www.pa.op.dlr.de/trex/publications/WeissmannEtAl_2009_TREX_Vorticity.pdf) · [doi.org](https://doi.org/10.3390/geosciences16070262) · [www.mdpi.com](https://www.mdpi.com/article/10.3390/geosciences16070262/s1) · [www.yorku.ca](https://www.yorku.ca/pat/research/Askervein/ASK83.pdf) · [doi.org](https://doi.org/10.1175/BAMS-D-17-0227.1) · [doi.org](https://doi.org/10.5194/acp-19-3797-2019) · [doi.org](https://doi.org/10.5194/acp-19-2713-2019) · [doi.org](https://doi.org/10.1175/BAMS-D-13-00131.1) · [arxiv.org](https://arxiv.org/abs/1501.02297v1) · [doi.org](https://doi.org/10.1007/s10546-015-0034-8) · [doi.org](https://doi.org/10.1016/j.agrformet.2025.110745) · [zenodo.org](https://zenodo.org/records/4095052) · [wemep.readthedocs.io](https://wemep.readthedocs.io/en/latest/windconditions/benchmarks/askervein.html) · [www.eol.ucar.edu](https://www.eol.ucar.edu/content/isfs-netcdf-files) · [www.eol.ucar.edu](https://www.eol.ucar.edu/content/perdig%C3%A3o-isfs-data-report) · [doi.org](https://doi.org/10.26023/ZDMJ-D1TY-FG14) · [doi.org](https://doi.org/10.5194/essd-12-3357-2020) · [doi.org](https://doi.org/10.5194/essd-13-3539-2021) · [doi.org](https://doi.org/10.5281/zenodo.4399967) · [catalog.py](../research/reference-library/catalog.py) · [artifact directory](research/flight-dynamics/rc-validation-library-2026-10-18/wind-weather)

### Additional retained references

Further links preserved from the earlier implementation/research notes; provenance only, not evidence of current runtime behavior.

- [Fung et al., 1992](https://doi.org/10.1017/S0022112092001423)
- [NASA Dryden verification, 20190000875](https://ntrs.nasa.gov/citations/20190000875)
- [20060024599](https://ntrs.nasa.gov/citations/20060024599)
- [FAA Glider Flying Handbook](https://www.faa.gov/regulations_policies/handbooks_manuals/aviation/glider_handbook)
- [Godot 4.7 `RandomNumberGenerator` docs](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html)
- [Godot 4.7.2 `random_number_generator.h`](https://github.com/godotengine/godot/blob/4.7.2-stable/core/math/random_number_generator.h)
- [Godot 4.7.2 `random_pcg.h`](https://github.com/godotengine/godot/blob/4.7.2-stable/core/math/random_pcg.h)
- [`random_pcg.cpp`](https://github.com/godotengine/godot/blob/4.7.2-stable/core/math/random_pcg.cpp)
- [Godot 4.7.2 `pcg.h`](https://github.com/godotengine/godot/blob/4.7.2-stable/thirdparty/misc/pcg.h)
- [`pcg.cpp`](https://github.com/godotengine/godot/blob/4.7.2-stable/thirdparty/misc/pcg.cpp)
- [Welch](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.welch.html)
- [guía de análisis espectral](https://docs.scipy.org/doc/scipy/tutorial/signal.html)
- [CSD](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.csd.html)
- [coherencia](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.coherence.html)
- [Notas de SciPy 1.18](https://docs.scipy.org/doc/scipy/release/1.18.0-notes.html)
- [licencia](https://github.com/scipy/scipy/blob/main/LICENSE.txt)
- [cont2discrete](https://docs.scipy.org/doc/scipy/reference/generated/scipy.signal.cont2discrete.html)
- [expm](https://docs.scipy.org/doc/scipy/reference/generated/scipy.linalg.expm.html)
- [Van Loan, “Computing Integrals Involving the Matrix Exponential”](https://doi.org/10.1109/TAC.1978.1101743)
- [README oficial](https://github.com/JSBSim-Team/jsbsim)
- [API Python](https://jsbsim-team.github.io/jsbsim/python/FGFDMExec.html)
- [notas 1.3.1](https://github.com/JSBSim-Team/jsbsim/releases/tag/v1.3.1)
- [PyPI 1.3.1](https://pypi.org/project/jsbsim/1.3.1/)
- [Guía TurbSim v2.00](https://openfast.readthedocs.io/en/main/_downloads/cb14d3e2d3533d76e405d730fea19846/TurbSim_v2.00.pdf)
- [InflowWind](https://openfast.readthedocs.io/en/main/_downloads/a231262e7763b4d61759ebe4e0fc30b2/InflowWind_Manual.pdf)
- [Repositorio y licencia OpenFAST](https://github.com/OpenFAST/openfast)
- [Propósito y límites 0.4.8](https://lkilcher.github.io/pyTurbSim/about.html)
- [licencia en el repo](https://raw.githubusercontent.com/lkilcher/pyTurbSim/master/LICENSE.txt)
- [Node 4.7](https://docs.godotengine.org/en/4.7/classes/class_node.html#class-node)
- [Engine 4.7](https://docs.godotengine.org/en/4.7/classes/class_engine.html#class-engine)
- [SceneTree 4.7](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html#class-scenetree)
- [Node process modes 4.7](https://docs.godotengine.org/en/4.7/classes/class_node.html#enum-node-processmode)
- [RandomNumberGenerator 4.7](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html#class-randomnumbergenerator)
- [RNG C++ 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/random_number_generator.h)
- [PCG 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/random_pcg.h)
- [inicialización PCG 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/random_pcg.cpp)
- [math_defs.h 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/core/math/math_defs.h)
- [Profiler Godot 4.7](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/the_profiler.html)
- [Performance 4.7](https://docs.godotengine.org/en/4.7/classes/class_performance.html#class-performance)
- [API Performance 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Performance.xml)
- [CLI 4.7](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
- [Engine.xml 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Engine.xml)
- [GUT oficial](https://github.com/bitwes/Gut)
- [GdUnit4 oficial/compatibilidad](https://github.com/godot-gdunit-labs/gdUnit4)
- [licencia GdUnit4](https://github.com/godot-gdunit-labs/gdUnit4/blob/master/LICENSE)
- [Node 4.7](https://docs.godotengine.org/en/4.7/classes/class_node.html)
- [SceneTree 4.7](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html)
- [Engine 4.7](https://docs.godotengine.org/en/4.7/classes/class_engine.html)
- [Performance API 4.7](https://docs.godotengine.org/en/4.7/classes/class_performance.html)
- [Referencia JSON](https://docs.godotengine.org/en/stable/classes/class_json.html)
- [contrato del tag 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/JSON.xml)
- [ConfigFile](https://docs.godotengine.org/en/stable/classes/class_configfile.html)
- [API jsonschema](https://python-jsonschema.readthedocs.io/en/stable/validate/)
- [licencia v4.26.0](https://raw.githubusercontent.com/python-jsonschema/jsonschema/v4.26.0/COPYING)
- [condicionales del estándar](https://json-schema.org/understanding-json-schema/reference/conditionals)
- [Range](https://docs.godotengine.org/en/stable/classes/class_range.html)
- [SpinBox](https://docs.godotengine.org/en/stable/classes/class_spinbox.html)
- [Range 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/gui/range.cpp)
- [SpinBox 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/scene/gui/spin_box.cpp)
- [ImmediateMesh](https://docs.godotengine.org/en/stable/classes/class_immediatemesh.html)
- [MultiMesh](https://docs.godotengine.org/en/stable/classes/class_multimesh.html)
- [guía de optimización](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html)
- [Referencia de particle shaders](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/particle_shader.html)
- [Código GLES3 fijado](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/drivers/gles3/shaders/particles.glsl)
- [ParticleProcessMaterial](https://docs.godotengine.org/en/stable/classes/class_particleprocessmaterial.html)
- [New Equations for Computing Vapor Pressure and Enhancement Factor](https://doi.org/10.1175/1520-0450(1981)
- [Area3D, XML de 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/doc/classes/Area3D.xml)
- [Interpolación física](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html)
- [float](https://docs.godotengine.org/en/stable/classes/class_float.html)
- [FastNoiseLite, interfaz 4.7.2](https://raw.githubusercontent.com/godotengine/godot/4.7.2-stable/modules/noise/fastnoise_lite.h)
- [RandomNumberGenerator](https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html)
- [Global uniforms](https://docs.godotengine.org/en/stable/tutorials/shaders/shader_reference/shading_language.html#global-uniforms)
- [FAA AC 150/5345-27E, §§3.2.2 y 3.5](https://www.faa.gov/documentlibrary/media/advisory_circular/150_5345_27e.pdf)
- [NOAA boundary-layer training](https://www.weather.gov/source/zhu/ZHU_Training_Page/clouds/planetary_boundary_layer/PBL.html)
- [NOAA stability computation](https://ready.arl.noaa.gov/documents/Tutorial/html/parm_stab.html)
- [TurbSim user guide](https://www.nrel.gov/docs/libraries/wind-docs/turbsim_v2-00-pdf.pdf?sfvrsn=5a0a30f8_1)
- [Businger et al.](https://doi.org/10.1175/1520-0469(1971)
- [Mann's spatial-tensor model](https://doi.org/10.1017/S0022112094001886)
- [surface-layer Taylor-hypothesis study](https://doi.org/10.1007/s10546-024-00861-1)
- [Allen's updraft/sink research](https://ntrs.nasa.gov/api/citations/20060004052/downloads/20060004052.pdf)
- [Doyle and Durran](https://doi.org/10.1175/1520-0469(2002)
- [FAA crosswind techniques](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/10_afh_ch9.pdf)
- [AMA RC landing approach](https://www.amaflightschool.org/getstarted/how-do-i-master-landing-approach)
- [NOAA turbulence guidance](https://www.weather.gov/source/zhu/ZHU_Training_Page/turbulence_stuff/turbulence/turbulence.htm?lv=true)
- [UIUC low-speed airfoil/propeller data](https://m-selig.ae.illinois.edu/pd.html)
- [official float reference](https://docs.godotengine.org/en/latest/classes/class_float.html)
- [physics interpolation guidance](https://docs.godotengine.org/en/latest/tutorials/physics/interpolation/physics_interpolation_introduction.html)
