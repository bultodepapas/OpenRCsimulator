# AS-01: Conditional module semantics

2026-10-11 · Prefix: AS-

**Status: Source-checked semantics note for the AS-01 contract and parameter register.** Describes implemented behavior; it does not certify the borrowed or estimated parameters as measured aircraft properties.

## Propeller slipstream

The module adds the difference between each immersed tail surface's local load in washed flow and its load in free stream. It does not reapply the free-stream tail load, wash the wing, or model fuselage drag. `AircraftData._slipstream()` validates the data; `Slipstream.loads()` and its wake/immersion helpers evaluate it. See [`aircraft_data.gd`](../../../../app/physics/aircraft_data.gd), [`slipstream.gd`](../../../../app/physics/slipstream.gd), [`wash_transport.gd`](../../../../app/physics/wash_transport.gd), and [`swirl_loads.gd`](../../../../app/physics/swirl_loads.gd).

| Input | Runtime meaning | Dependencies and limits |
| --- | --- | --- |
| `hub` | Propeller hub position in the leading-edge datum, metres. Defines the shaft line from which the wake centre is projected aft. | Requires a slipstream module and the propeller's explicit `thrust_angles`; `[0, 0]` declares an axial shaft. |
| `wash_factor` | Two dimensionless gains in the order **`[static, forward]`**. The runtime linearly blends from the first to the second as mass-flow ratio `m = u/(u+w)` moves from 0 to 0.75; outside that interval it uses the endpoint. It multiplies actuator-disc induced speed `w` to get the added axial tail speed. | This is a fitted/estimated tail-wake gain, not the ideal momentum-theory factor. The file currently has no unit conversion or reordering. |
| `swirl_factor` | Dimensionless scale on the torque-derived circulation heuristic `Γ = factor × (wash_gain/2) × Q / [ρπR² max(u+w, 1 m/s)]`; local tangential speed is `Γ/r`, with a `0.3R` core radius. Positive values use clockwise-from-behind propeller sense. | `0` disables swirl. The formula is explicitly an estimated heuristic, not a closed angular-momentum solution. It is incompatible with `transport_speed_floor`. Legacy chord pieces use centroid swirl; the smooth-profile path integrates distributed swirl. |
| `vertical_drift` | `[0,1]` multiplier on the vertical displacement of the wake centre as it is advected aft by free-stream vertical velocity. The code comment identifies it with `1 − dε/dα`; sideslip-driven lateral drift is applied separately and is not scaled by this value. | Applies to both legacy and smooth geometry. |
| `pieces[*].surface` | Selects the horizontal or vertical tail local aerodynamic law. | Other surface names are rejected. Each piece contributes only the washed-minus-free increment. |
| `pieces[*].area`, `root`, `span_dir`, `span` | Geometric area, leading-edge-datum root, unit span direction, and span length. They define where and how much tail surface intersects the wake. | Smooth pieces must be behind the hub and span transversely: horizontal uses the y direction; vertical uses z. Smooth profiles are limited to 1–8 pieces. |
| `pieces[*].chords` | Legacy representation: root and tip chord widths in metres; the chord varies linearly along the span. | Used only when `edge_fraction` is absent. A per-piece `profile` is then forbidden. This preserves the existing sharp circular occupancy path. |
| `edge_fraction` | Smooth-occupancy opt-in. The nominal contracted wake radius is softened from `R_s(1−edge)` to `R_s(1+edge)` using a C1 cubic in squared radius, avoiding a hard tangency kink. This changes geometric occupancy; it does not claim a measured radial velocity profile. | Requires `reverse_fade` and per-piece `profile`; profiles replace `chords`. The shaft must be exactly axial. |
| `reverse_fade` | Two dimensionless bounds `[positive-flow onset, reverse-flow cutoff]`, expressed as `−V_axial / v_i0` where `v_i0` is static induced speed at the current RPM. A smoothstep scales the full smooth-path increment from 1 to 0 across the bounds. | Requires `edge_fraction`; onset must be less than cutoff. It is a bounded reverse-flow regularization, not a vortex-ring model. |
| `pieces[*].profile` | Piecewise-linear neutral chord-width distribution, flattened as interval rows `[a, b, c(a), c(b)]` in metres. Intervals may have gaps/discontinuities; integrated profile area must equal the declared piece area. | Required when `edge_fraction` is present; forbidden otherwise. Smooth occupancy integrates profile area and its first span moment, then applies the local tail law at the resulting centroid. |
| `transport_speed_floor` | Enables one continuous axial-wake-speed state per tail piece. Its target is the equilibrium induced-speed increment; `dv/dt = (target−dv)/τ`, with `τ = (root.x−hub.x)/max(u+w, floor)`. | Requires smooth profiles, an axial shaft, and `swirl_factor = 0`. The floor is an estimated zero-flow regularizer. Only axial speed is transported; wake geometry, reverse occupancy and direction remain instantaneous. Absent means the existing quasi-static wake; a stopped propeller adds no quasi-static increment. |

## Tabulated wing polar

[`wing_polar.gd`](../../../../app/physics/wing_polar.gd) evaluates optional `aero.wing_polar` data from [`aircraft_data.gd`](../../../../app/physics/aircraft_data.gd) and [`aero.gd`](../../../../app/physics/aero.gd). It supplements the finite-wing strip reference; it is not a 2-D airfoil-section polar.

| Input | Runtime meaning | Dependencies and limits |
| --- | --- | --- |
| `method`, `basis` | Must be `tabulated-wing-v1` and `finite-wing-strip-reference`. | Requires the calibrated local wing `induced_map`; unknown keys are rejected. |
| `positive`, `negative` | Separate evidence quantities, each containing 4–64 rows of `[|α| deg, |CL|, profile CD, attached fraction]`. Lift magnitudes are nonnegative in both branches; runtime applies the negative-side sign. The two branches need not be symmetric. | Angle rows increase from at least 8° to exactly 90°. CL/CD magnitudes are 0–3; attached fraction is 0–1 and nonincreasing. First row must join the computed attached wing slope/intercept, `CD0`, and fraction 1. Last row is exactly `[90°, 0, CD0+CD90, 0]`. |
| Interpolation and continuations | Shape-preserving cubic interpolation is used between rows. At or below the first row the actual coupled strip lift is retained; at 90° and beyond the explicit flat-plate continuation is used. The attached fraction blends the table lift with the existing induced/coupled strip solution. | Each branch is validated independently. The table does not replace the baseline wing map at attached angles or duplicate it as a second lift source. |

## Electric motor, ESC and battery

[`electric_motor.gd`](../../../../app/physics/electric_motor.gd), [`electric_supply.gd`](../../../../app/physics/electric_supply.gd), [`electric_battery_step.gd`](../../../../app/physics/electric_battery_step.gd), and `AircraftData._electric_propulsion()` implement one direct-drive propeller with an equivalent DC motor. The `no_load_context` is fit/validation context; temperature is not a thermal state.

| Input | Runtime meaning | Dependencies and limits |
| --- | --- | --- |
| `motor.kv_rpm_per_volt` | Motor speed constant `Kv`; it defines back-EMF `rpm/Kv` and torque constant `Kt = 60/(2πKv)` N·m/A. | Positive and finite. `Kv × source reference voltage` sets the normalized maximum-RPM reference/search scale, not a governor limit. |
| `motor.resistance_ohm`, `resistance_scope` | Equivalent winding resistance in the DC motor law; scope must be `motor_winding_equivalent`. | ESC, wiring and connector losses are excluded. Pack resistance is a distinct battery parameter. |
| `motor.no_load_current_a` | Equivalent current used for rotational-loss torque `Kt × I0`; at zero RPM that loss is capped by electromagnetic torque so the shaft cannot start backwards. | Nonnegative. `no_load_context` records voltage, RPM and temperature used as evidence; temperature does not alter runtime constants. Context RPM cannot exceed `Kv × context voltage`. |
| `esc.kind`, `esc.command_mapping` | Only `ideal_motoring` and `identity` are supported. Effective duty is the normalized command in `[0,1]`; command voltage is duty × bus voltage. | This is a one-quadrant motoring approximation. It has no regeneration, active braking, current limit, thermal behavior or low-voltage cutoff. When disabled or overrun, motor current is zero; freewheeling RPM still experiences the no-load rotational loss. |
| `battery.kind = fixed_voltage` | Prescribed constant bus voltage, with no modeled charge, sag or battery state. | Branch contains only `voltage_v`; it is an infinite supply. |
| `battery.kind = ocv_resistance` | Dynamic pack with capacity, internal resistance, pack-side auxiliary current, initial SOC and a piecewise-linear OCV-vs-SOC curve. Bus sag is solved with motor duty/current; pack current is motor bus current plus auxiliary current. SOC falls at `−I_pack/(3600 × capacity_Ah)`. | SOC knots strictly increase from exactly 0 to 1; OCV is positive and nondecreasing. At SOC 0 the ideal exhausted pack disconnects all loads. Charge exhaustion is located as an integration event, then the source coasts. This is not an RC, temperature, BMS-cutoff or regeneration model. |
| `battery.auxiliary_current_a` | Constant pack-side load; it contributes pack sag/current even when the motor is disabled. | At the exhausted SOC boundary the pack disconnect convention turns all loads off. The initial auxiliary voltage drop must leave positive bus voltage at minimum OCV. |
| Propeller and battery solver | Propeller uses the shared Ct/Cp tables and direct-drive rotor. OCV battery state and rotor RPM use the coupled event-aware integrator. | Reverse rotor sense/gearing and arbitrary ESC modes are unsupported. Fixed-voltage specimens retain no battery charge state. |

## Landing-gear and tyre coefficients

[`aircraft_data.gd`](../../../../app/physics/aircraft_data.gd), [`ground_contact.gd`](../../../../app/physics/ground_contact.gd), and [`ground_surfaces.gd`](../../../../app/physics/ground_surfaces.gd) implement the baseline point-contact law. The frozen AS comparison uses its flat field; the concurrent GP extension below supplies terrain and rotating wheels. Aircraft tyre coefficients describe the dry-pavement baseline; field surface factors multiply them. These values are not runway-start permissions.

| Input | Runtime meaning | Dependencies and limits |
| --- | --- | --- |
| `contacts[*].stiffness`, `damping`, `max_compression` | Per-wheel normal spring/damper in N/m, N·s/m and metres. Normal force is clamped to pushing only; damping ramps in from touchdown. | At least three supported contacts are required. Static support, damping ratio, spring/tick stiffness and compression checks are loader constraints. A wheel point may not also be a hull crash point. |
| `contacts[*].max_steering` | Maximum signed wheel angle multiplied by the session steering command. | Required in v2; explicit `0` disables steering on that contact. Range is −45° to +45°; negative tailwheel steering is intentional. Only legacy v1 defaults an omitted value to zero. The contacts' wheel headings are projected onto the ground plane before tyre forces are resolved. |
| `rolling_resistance` (`C_rr`) | Dimensionless longitudinal resistance coefficient; sliding force is `−C_rr N × sat(v_long/v_creep)`. | 0–0.3; `v_creep = max(0.01 m/s, 0.1 C_rr m/s)` is a shared numerical regularizer, not aircraft tyre data. Static holding is absent unless breakaway anchors are enabled. |
| `side_friction` (`μ`) | Dimensionless cap for lateral tyre force and the combined ground-plane friction circle, `μN`. | 0.1–1.5. Surface `friction_factor` multiplies μ and is constrained ≤1 to preserve the loader's stability bound. |
| `peak_slip_angle` | Angle in degrees whose tangent sets the lateral-force saturation scale: `tan(slip)=v_lat/max(|v_long|,1 m/s)`, then force saturates at `μN`. | 1–30°. The loader checks the implied low-speed damping rate against the configured physics timestep. `SLIP_FLOOR=1 m/s` is numerical, not a tyre measurement. |
| Optional `breakaway_factor` | Enables per-wheel static anchor state. Along-wheel hold limit is `breakaway_factor × C_rr × N`; lateral hold is `μN`; both remain inside the friction circle. | When absent, the original stateless rolling/slip law is used. Present range is 1–2 and enables solver-sized anchor stiffness/damping, not measured tyre stiffness. No brakes are modeled. |
| Field surface factors | `friction_factor` multiplies `μ`; `rolling_factor` multiplies `C_rr` at each wheel's current field position. | The validated field table supplies runway/mown/rough rectangles with a final catch-all. These are world/field values, not duplicated per-aircraft settings. |

Simulated deployed contacts and menu runway-start eligibility are separate. The current Stik-only runway-start route is deliberate app/UI policy; it does not add an aircraft capability or imply that other aircraft lack ground-contact physics. Extra/P-51 retain physics ground tests, while Avanti has no contact module and starts airborne.

## Concurrent ground-profile interface

Observed during AS integration on 2026-10-11; implementation and qualification belong to [GP-03](../../../../GROUND_PHYSICS_PLAN.md). The AS source schema remains closed: these fields live in the separately versioned `openrc-wheel-profiles v1` file, not duplicated in aircraft JSON. [`wheel_profiles.gd`](../../../../app/physics/wheel_profiles.gd) binds the exact aircraft ID and all unique contact names after file-backed aircraft derivation. Applied profiles augment normalized contacts and retain provenance. Invalid data fails the load; absent profiles report `legacy_fallback`, while aircraft without gear report `no_gear` and cannot receive a profile.

| Input | Meaning and consumer | Admitted range / dependency |
| --- | --- | --- |
| `wheel_radius` | Metres; `ground_wheels.gd` converts rim speed to angular speed and modifies vegetation rolling loss. | 0.005–0.5 m; derived largest-wheel radius prevents reapplying wheel-size scaling already present in aircraft Crr. |
| `wheel_inertia` | Axial rotational inertia; `I/R²` is the effective rim mass in the wheel/body slip law. | 1e-9–10 kg·m²; summed effective wheel mass must be ≤10% of aircraft mass. It does not add inventory mass again. |
| `spin_relaxation` | Spin/slip response timescale consumed by `ground_wheels.gd`. | 0.001–1 s structurally; runtime additionally requires `dt/tau ≤ 0.25`. |
| `brake_torque` | Maximum equipment torque, multiplied by a separate brake command; no throttle-linked braking. | 0–10,000 N·m; zero is valid and inactive. |
| `brake_availability` | Explicit equipment evidence: `none`, `unspecified`, `available`. | `none`/`unspecified` require zero torque; `available` requires positive torque. All current fleet profiles are unbraked. |

The profile uses the same four-key quantity/provenance convention. Session wheel rim-speed states have independent continuous-state offsets, reset/checkpoint/trace identity and ground-force consumers. Terrain is a field input, not an aircraft coefficient. This arriving GP implementation changes ground behavior and state layout independently of AS; the frozen exact AS migration proof does not certify those later changes. The live contract test compares both data versions after identical profile attachment.

## Source map

The current parser and consumers are authoritative for the meanings above: `aircraft_data.gd::_slipstream`, `::_wash_profile`, `::_wing_polar`, `::_electric_propulsion`, `::_electric_battery`, and `::_landing_gear`; `slipstream.gd::loads/wake/immersion/profile_moments/reverse_weight`; `wing_polar.gd::prepare/evaluate`; `electric_motor.gd::evaluate`, `electric_supply.gd::evaluate/evaluate_available/evaluate_dynamics`, `electric_battery_step.gd::advance`; `ground_contact.gd::loads/anchor_step/damping`; and `ground_surfaces.gd::load_table/validate/build`. These are script/function names, not class names. Existing focused proofs include `test_slipstream_scalar.gd`, `test_slipstream_downwash.gd`, `test_wash_profile.gd`, `test_swirl_accuracy.gd`, `test_wash_transport.gd`, `test_wing_polar.gd`, electric source/battery tests, and ground contact/friction/stiction tests.
