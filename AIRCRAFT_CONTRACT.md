# Aircraft contract

**Status: current v2 authoring/runtime contract; AS-00–05 delivered, 2026-10-11.** Revision 1. Authored format: `openrc-aircraft v2`. Convention: `openrc-le-frd-v1`. [Audit](docs/research/aircraft-standardization/AS-00/), [migration and verification](docs/research/aircraft-standardization/AS-05/README.md).

## Scope and authority

An aircraft file describes one complete simulated configuration, not every possible build of a commercial airframe. All four catalog models and the electric regression specimens use this contract. The catalog controls product availability; the file controls physics. A valid file is not evidence of a realistic aircraft. Preserve the evidence kind and source of every number, particularly the virtual balancing mass and borrowed aerodynamic/propeller data.

`app/physics/aircraft_data.gd` is the load/derive boundary. `aircraft_contract.gd` applies the closed structural/module contract before v2 data can fly; the existing loader performs numerical and coupled physical validation. The versioned JSON schema is the offline structural counterpart. Its numeric bounds are loader safety/qualified-model limits, not universal laws of aviation. A structurally valid file can still fail area, CG, inertia, lift/fin, table, gear-support, timestep or trim checks. A failure returns errors and no usable model. No unknown version is downgraded automatically.

V1 is retained for explicit historical experiments. It keeps its documented permissive/default behavior; it is not the standard for a new aircraft. Migration must be explicit and reviewed. The loader hashes the actual source bytes and source version separately from its rounded semantic hash. New data invalidates old checkpoint identity even when numerical trajectories are preserved.

## Three ownership layers

| Layer | Owns | Must not contain |
| --- | --- | --- |
| Authored aircraft | Identity, supported capabilities, reference geometry, component inventory, provenance, coefficients/polars, control limits, propulsion/energy, gear and hull | Current RPM, battery charge, servo positions, contact compression, integrated pose or cached trim |
| Derived model | Total mass, inventory CG, full inertia, transformed arms/hull/contacts, strip geometry and calibrated slopes, stall transitions, radians/servo rate, flattened validated tables | Mutable flight history; separately authored copies of values already derivable |
| Runtime session | Pose/velocity/rates, servo positions, engine mode/RPM, wake/shaft/battery states, ground anchors and qualified ground extensions, commands, trim/start, crash and recorder lifecycle | Hidden per-aircraft constants or edits to the source inventory |

Physics and control consumers use the normalized model. Render vectors are allowed only after the float64 simulation boundary. Numerical strip count, 240 Hz step, gravity, integrator safeguards, weather, field friction and input-device shaping belong to shared systems, not duplicate aircraft fields.

## Coordinates, signs and units

- Authored structural positions are metres in `[x_aft, y_right, z_up]`, referenced to the wing leading-edge datum at the centreline. Each visual builder documents its offset to that datum. `frames` is explanatory metadata; `convention_id` selects the executable convention.
- Body forces, velocities, angular rates and inertia use right-handed FRD at the inventory CG: forward, right, down. For a structural point `p`, `r_body = [-(p.x-cg.x), p.y-cg.y, -(p.z-cg.z)]`. A propulsion `thrust_line_offset` or `intake_offset` is already a CG-relative structural offset; do not subtract CG again. Slipstream `hub` and piece `root`, tail and gear positions, and the crash hull are datum-relative.
- World position uses NED: north, east, down. Altitude above the flat datum is `-down`; local terrain clearance is a separate ground query. Quaternion order is `[w,x,y,z]`, body to NED. Moments use `r × F` about CG.
- Inertia is the symmetric matrix layout `[Jxx,Jyy,Jzz,Jxy,Jxz,Jyz]` in kg·m² about the inventory CG. Off-diagonal matrix entries are negative products of inertia. Point masses and aligned boxes are summed with the parallel-axis theorem. A declared CG cannot move independently of this inventory.
- Reference area is m²; span and coefficient chord are m. `mean_chord` means **S/b**, including tapered wings, not mean aerodynamic chord. Changing the coefficient reference length requires transforming the derivatives consistently. Planform/CG studies may retain MAC in evidence.
- Aerodynamic force coefficients use wind axes `[-D,Y,-L]`; moment coefficients use body axes at the aerodynamic reference point, then transfer to CG. `alpha,beta` are radians. Normalized rates are `p b/(2V), q c/(2V), r b/(2V)`; dimensional damping avoids division by zero.
- Authored aerodynamic elevator/aileron derivatives are per radian of trailing-edge **down**; rudder per radian of trailing-edge **left**. Pilot/render surface outputs are degrees trailing-edge up/right. `Aero.deflections_from_surfaces()` performs the sign/unit conversion once. Steering uses its own signed gear angle: negative tailwheel steering is intentional.
- Angled thrust is `[down,right]` degrees and axis `[cos(down)cos(right), cos(down)sin(right), sin(down)]` in FRD. Supported propeller rotation is clockwise viewed from behind; positive shaft RPM has this sense. A turbine has its existing explicit `rotor_sense` ±1.

The frame split follows standard flight-dynamics practice, while these exact datum/sign choices are OpenRC's contract; do not import another solver's inputs without conversion. [JSBSim frame reference](https://jsbsim-team.github.io/jsbsim-reference-manual/user/concepts/frames-of-reference/)

## Presence, evidence and defaults

Each physical quantity is exactly `{value, unit, kind, source}`. `value` is a finite numeric scalar/vector/table of the specified shape; booleans and numeric strings are invalid. Units are exact symbols, not automatically converted. Evidence kinds are `manual`, `measured`, `borrowed`, `estimated`, `derived`; `source` is nonblank and states the derivation or identifiable source. Uncertainty belongs in the source/report until an uncertainty model has a consumer. A guess remains `estimated` even if the simulation passes.

Missing required data is an error. JSON null never means zero or an inactive subsystem in v2. Absence is allowed only for a documented optional module or default below. Zero is accepted only inside a field's domain: zero steering/offset/incidence/current drain is meaningful; zero mass, capacity, span, servo time or static thrust coefficient is not. Empty optional subsystem objects are invalid. Extra keys, misspelled coefficients and inactive-branch parameters are errors.

Explicit in every v2 file: start speed, planform, propulsion kind, capability selections, convention, inventory size (zero box denotes a point mass), gear steering (zero denotes unsteered contact), and propeller rotation for combustion. The following physically defined defaults remain conditional rather than copied everywhere:

| Optional input | Absence means | Consumer |
| --- | --- | --- |
| `controls.max_throw.aileron_down` | Symmetric aileron travel using `aileron` | `_controls`, command surface mapping |
| `landing_gear` | Permitted only for `locked_up`; no tire/suspension loads, hull contact is terminal | Contract → `_landing_gear` → ground/crash |
| `landing_gear.breakaway_factor` | Existing dynamic rolling/slip law without static anchors | Ground/session anchor path |
| `propulsion.engine.shaft` (combustion) | Prescribed equilibrium RPM with first-order lag; no airspeed unloading from a torque-balance engine | Propulsion/session |
| Propeller/turbine `thrust_angles` | Axial thrust | Propulsion/turbine axis |
| `normal_force`, `pfactor_moment`, `slipstream` (combustion prop) | Corresponding force, moment or wake increment absent | Propulsion, slipstream, local aero |
| `horizontal.downwash_gradient` | No dynamic downwash coupling | Loader/aero/session |
| `wing_station_incidence` | Untwisted six-strip wing | Loader/local aero |
| `aero.surfaces.wing_section_cm_ac` | No section pitching moment on the strips (symmetric sections, or a Cm0 the data folds into the tail incidence) | Loader → `Aero._local_loads` strip couple; the oracle's `Cm0` must carry the same camber moment |
| `aero.wing_polar` | Existing analytic stall blend | WingPolar/local aero |
| `aero.ground_effect` | No ground effect: loads independent of height above the field | GroundEffect → Aero strips/oracle and tail downwash; session terrain height |
| Turbine `ram_flow`, `ram_jet` | No corresponding fitted ram correction | Turbine |
| Slipstream smooth-profile/transport extensions | Existing explicitly selected legacy wake, without that added law | Slipstream/session |

Optional inputs retain all dependencies and limits of their runtime parser. They are not globally interchangeable. In particular a propeller crossflow/P-factor/wake module requires an explicit shaft axis; smooth wake currently requires an axial shaft. Ground effect requires the calibrated local wing (strip induced map) and the horizontal tail's `downwash_gradient`. Negative power coefficient (windmilling) requires a rotor-dynamics path. Electric supports its specified motor/ESC/battery law, not arbitrary combustion wake modules.

## Capabilities and conditional modules

Capabilities are closed selections used to validate configuration consistency. They cannot turn an unimplemented system on. They are included in model identity; the actual normalized modules drive the existing force/lifecycle consumers.

| Field | Accepted values and rule |
| --- | --- |
| `controls` | `conventional`: aileron, elevator, rudder and throttle only |
| `gear` | `fixed_tricycle`, `fixed_taildragger`, `locked_down_taildragger`: deployed contact module required; `locked_up`: contact module forbidden |
| `propulsion_layout` | `single_tractor` for a propeller; `single_centerline_jet` for turbine |
| `energy` | `prescribed_fuel` for combustion/turbine; `fixed_voltage` or `ocv_resistance` must agree with electric battery kind |
| `damage` | `terminal_hull`: hull/gear-limit crossing ends the flight; wreck effects are presentation |
| `flaps` | `not_simulated`: any modeled flap mesh remains neutral |

For deployed gear, compare each contact's datum-relative x position with `balance.plan_cg` (x increases aft). `fixed_tricycle` requires at least two contacts aft of the CG and one ahead; both taildragger capabilities require at least two ahead and one aft. Contacts exactly at the CG count toward neither side. This runtime topology check is independent of steering angle, so all-zero steering remains valid; it imposes no maximum contact count.

`propulsion.kind` selects `glow_prop`, `electric_prop` or `turbine`. `glow_prop` is a historical solver-family name for combustion-driven propellers, including the P-51 gasoline engine; it is not a fuel chemistry claim. Descriptive engine names/provenance identify glow versus gasoline hardware. Prescribed fuel means the loaded wet inventory stays fixed: throttle does not burn mass or migrate CG. Turbine `fuel_flow` is consumption telemetry, not a fuel tank state. Hardware named in an inventory (battery, retract, flap servo, brake or gyro) contributes mass/inertia without enabling its dynamics.

| Aircraft | Configuration preserved |
| --- | --- |
| Jensen Das Ugly Stik 60 | Glow, single tractor, lagged RPM, tricycle contacts, static anchors, 15 m/s start, estimated 20/20/25° throws, borrowed/estimated ground-effect law |
| Great Planes Extra 300S .60 | Glow, single tractor, lagged RPM, fixed taildragger, 17 m/s start, manual-derived throws |
| P-51D Mustang 1/4 | Gasoline, single tractor, shaft balance, thrust angles, P-factor/normal force/tail wake, retract hardware locked down, 25 m/s start |
| SebArt Avanti S | P100-RX turbine spool/ram model, retract hardware locked up, no ground wheel module, 29 m/s airborne start, aileron differential |
| Synthetic Stik electric specimens | One direct-drive tractor BLDC equivalent, ideal motoring ESC, prescribed voltage or OCV/resistance battery, Stik reference airframe; test fixtures, not a fifth catalog airplane |

Runway-start menu availability is a separate qualified product policy, currently Stik-only. Having valid wheel contacts does not claim runway-start UI qualification. The P-51 and Extra retain their physics ground tests; Avanti cannot taxi on invisible wheels. Existing model wheel/gear articulation helpers are not proof of live suspension/steering animation.

Planned and **rejected as v2 active configuration**: EDF duct/fan and inlet/outlet momentum; pusher installations and wake orientation; multiple propulsion units and differential throttle; propeller reverse sense/pitch/gearing; retract deployment and changing contact/drag/inertia; flaps/slats/spoilers and mixing; fuel tanks/burn/slosh and changing mass properties; battery temperature/ESC heating/BEC/receiver failures; structural flexibility, part loss and persistent damage; distributed mass rotation; water/skis; moving terrain. Add a conditional module, consumer, provenance, complete lifecycle state, versioned schema and independent or analytic test before admitting any extension. Do not copy tractor propeller coefficients to an EDF.

## Physical modules and parameter effects

The [machine schema](app/data/schema/openrc-aircraft-v2.schema.json) specifies exact field shapes and per-field numerical ranges. The generated [152-path parameter register](docs/research/aircraft-standardization/AS-01/parameters.md) lists every quantity with its consumer. The [conditional module semantics](docs/research/aircraft-standardization/AS-01/module-semantics.md) define wake, polar, electric and tire parameters in detail. The following is the physical interpretation used when reviewing or tuning those fields.

**Mass and balance.** Inventory mass/position/box size determine total mass, CG and the six inertia entries. `balance.plan_cg` and `cg_tolerance` constrain agreement with that inventory; they do not override it. `plausibility.mass_range` rejects implausible totals. `plausibility.inertia_reference` supplies a warning against the existing mass/span-scaled UltraStick reference; it is not a measured inertia tensor or a calibration target. `balance.firewall` is reference/validation evidence only. All four inventories are virtual balanced builds; the balancing mass is not a claim about hardware actually installed. Positive/physical tensor and rotor-carrier checks remain mandatory. [Inertia sign reference](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGMassBalance.html)

**Aerodynamics.** `CL0,CLa` define the attached lift intercept/slope. `CLq` supplies pitch-rate lift; `CLde,CLda_each` supply control lift. `CD0,CL_minD,k_induced` define the shifted drag polar; `CDda_each,CDde,CDdr` add absolute control drag. `CYb,CYp,CYr,CYdr` define side force. `Clb,Clp,Clr,Clda_left,Clda_right,Cldr` define roll moment. `Cm0,Cma,Cmq,Cmde,Cmda_each` define pitch moment. `Cnb,Cnp,Cnr,Cnda_left,Cnda_right,Cndr` define yaw moment. The derivatives refer to the specified axes, reference lengths and normalization, not dimensional force gains. Stable-airplane sign restrictions currently constrain the admitted model family. `aero.reference_coefficients.CLadot` is preserved historical reference evidence; no alpha-dot derivative reads it. Downwash lag, when configured, derives its own unsteady response from the local tail law.

**Ground effect (M5-GE-1, optional).** `ground_effect.induced_coefficient/induced_exponent` define σ(h/b) = c·(h/b)^e / (1 + c·(h/b)^e), the fraction of each wing strip's induced angle that survives the ground's image vortex system at the strip's height h above the field; the strip keeps (1 − σ) of that angle as extra attached lift and its induced drag at the same CL scales by σ. `downwash_coefficient/downwash_exponent` define the same form for the wing's downwash at the horizontal tail, evaluated at the strips' mean height. Both reach exactly 1 at two spans. The session supplies the field terrain height under the CG; trim, linearisation and static solves are out of ground effect. Separated (flat-plate) flow and the slipstream tail increment are unchanged. The constants are fitted law coefficients (Raymer/McCormick and Wieselsberger image theory, image-VLM tail fit), not measured on any airplane; [evidence](docs/research/ground-effect/M5-GE-1/README.md).

`envelope.CL_max/CL_min`, blend width and `CD90` derive positive/negative stall transitions; sideslip blend controls the lateral full-envelope transition. The linear oracle remains valid through its qualified small-angle range. Local tail area/position/slope/incidence/effectiveness set actual lift, control authority and moment arm, with attached/local/stall blend bounds and `tail_CD0/tail_k/tail_CD90` drag. Wing aileron effectiveness and six station incidences control local asymmetric loading. Strip slope, lift offsets and induced-flow map are derived to reproduce the global static oracle, not additional user coefficients. The fin's global force/moment derivatives must match its local force and arm. Optional tabulated wing polars retain separate positive/negative branches with provenance and bounded extrapolation. Low-Reynolds-number and post-stall measurements remain aircraft-specific. [UIUC research/data](https://m-selig.ae.illinois.edu/pd.html)

**Controls.** Max throws bound the physical surface travel used by both aerodynamic and visual mapping. Servo full-throw time is neutral to full deflection, not a 60° manufacturer spec; its inverse is the normalized servo rate. Transmitter expo/dual rates and keyboard response belong to the input layer. The same shaped servo state drives rendered surfaces and physics; no renderer-only retuning. Aileron differential is explicit in Avanti.

**Combustion propeller.** Static maximum/idle RPM and lag define the legacy governor approximation. A shaft module instead supplies indicated peak/idle power, friction torque and its normalized power curve; propeller torque loads the rotating inertia. Brochure `peak_power/peak_power_rpm` are validated reference evidence and never replace the shaft curve. Diameter and Ct/Cp tables define `T=Ct ρ n² D⁴` and `P=Cp ρ n³ D⁵`, where `n=RPM/60` and `J=Vaxial/(nD)`; power/torque must use the same reference convention. Axis/CG-relative application point determine force direction and moment; rotating inertia also supplies gyroscopic/acceleration coupling. Normal-force/P-factor tables and geometric wake pieces are explicit opt-ins with existing dependency checks. Preserve measured versus borrowed propeller identity and Reynolds/RPM limitations. [UIUC coefficient and test definitions](https://m-selig.ae.illinois.edu/props/propDB.html)

**Turbine.** Throttle map, idle/max RPM, governor time and acceleration/deceleration limits determine spool state. Static thrust, installation factor, mass flow and intake/thrust offsets determine installed force and ram/inlet moment. Ram-flow and ram-jet tables are fitted optional corrections. Rotor inertia/sense determine angular momentum coupling. Fuel flow reports consumption at RPM but does not reduce aircraft mass. There is no propeller Ct/Cp/shaft/wake module in this branch.

**Electric.** Kv, motor winding-equivalent resistance and no-load current define the three-constant motor law; the no-load context voltage/RPM/temperature is evidence/validation context, not a thermal model. The ideal motoring ESC maps throttle directly and does not implement active braking or regeneration. Fixed-voltage battery is an infinite prescribed bus. OCV/resistance battery specifies capacity, internal resistance, auxiliary current, initial SOC and ordered endpoint-covering SOC/voltage knots. Charge, delivered energy and pack heat evolve in the coupled event solver; they reset/replay as runtime state. Zero current/resistance values allowed by the specific field do not mean missing data. Carrier inertia and timestep stiffness checks apply before flight.

**Ground and damage.** Each deployed wheel is an undeformed contact point with spring stiffness, damping, compression travel and signed steering angle. Rolling resistance, side friction and peak slip set the existing tire law; optional breakaway enables anchors. Contact support, nonnegative load, damping, heave/slip timestep and sag/travel checks protect the integrator. The field, not the aircraft, selects terrain/surface conditions. Ground-track wheel profiles/spin/brakes are separately versioned interfaces and must be validated where attached; AS does not invent them. Hull vertices locate terminal contact; wheel support points must not become duplicate hull crash points. Travel exceedance/impact reports and the wreck are not structural damage models.

The concurrent GP-03 interface is `openrc-wheel-profiles v1` in `app/data/ground/wheel_profiles.json`, keyed by exact aircraft ID and unique contact name. `WheelProfiles.apply_to_model()` runs after the aircraft derivation at the file-load boundary; invalid profiles block flight. In-memory aircraft derivation deliberately excludes this attachment. A deployed aircraft without a profile reports `legacy_fallback`; absent gear reports `no_gear` and rejects any matching profile. Neither absence silently enables brakes. Applied profiles carry their own identity into the session; file-backed v1/v2 comparisons must apply the same profile to both. Wheel radius, inertia, relaxation and brake inputs, consumers and limits are documented in the [module supplement](docs/research/aircraft-standardization/AS-01/module-semantics.md#concurrent-ground-profile-interface). This separately owned extension is outside the 152 aircraft-quantity paths and the frozen AS numerical-migration comparison.

## Lifecycle and other consumers

Selected catalog ID, loaded model ID and visual builder ID must agree on normal catalog startup; research electric donors deliberately reuse the Stik visual adapter. A mismatched selection is rejected before trim/flight. Reload validates a complete candidate and preserves the previous model/state if it fails. Reset selects the aircraft's declared trim speed, restores energy/engine/servo states and clears crash/recorder state. Pause holds those states. Checkpoints identify the complete model and solver/environment configuration and reject another model; new auxiliary state requires layout/reset/restore coverage.

Trace metadata records the real input format/hash, model ID, active propulsion/wake/aero law and start state. UI, HUD, camera, sound and crash presentation must consume normalized values or explicit presentation metadata; none may change physical constants. Visual geometry and control-node names remain owned by the model tracks. Future fuel/part effects must not infer hardware from a filename or free-text inventory name.

## Adding and tuning an aircraft

1. Copy the [synthetic template](research/aircraft-standardization/template/openrc-aircraft-v2.template.json); give it a unique ID and clearly mark its initial evidence as donor/estimated. Select only supported capabilities. Do not register it as flyable yet.
2. Establish one visual/structural datum. Measure span/area/chords, CG and component masses/positions; derive the tensor and geometry. Retain raw measurements, uncertainty and provenance in `docs/research/<track>/<step>/`.
3. Set control hardware travel/time and actual propulsion tables. Fit static/attached aero with consistent reference quantities, then local stall/tail behavior. Keep calibration and held-out verification observations separate. Tune one mechanism at a time.
4. Validate schema and Godot load/trim; run model/hinge, force, propulsion, ground, stall/control, lifecycle and performance checks. Compare state traces and force budgets. A passing self-consistency test is not physical validation.
5. Register the catalog and visual adapter together, add aircraft-specific tests, and retain measured gaps. Manufacturer limits, independent measurements and qualified pilot feedback decide physical acceptance. Unsupported features require a contract extension before use.

Use the [AS-05 authoring commands and verification](docs/research/aircraft-standardization/AS-05/README.md) for generated-output checks and documented results. The v2 migration preserved force equations and numeric calibration; it does not close physical or target-machine acceptance. Never hand-edit a generated aircraft JSON.
