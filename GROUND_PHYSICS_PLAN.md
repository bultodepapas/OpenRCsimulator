# Ground physics plan

Status: GP-00 completed before implementation, 2026-10-11; GP-01–03 integrated, GP-04–05 verification recorded below. Physical calibration and target-machine performance acceptance remain open. Owner: main physics line. Prefix: GP-. This root location is explicitly requested by the project owner. [Implementation, tuning and verification report](docs/research/ground-physics/GP-05/README.md).

Final outcome: 108 ground scenarios, 12 full-session acceleration probes, exact eight-case airborne parity, trace/replay and landing checks, and native pack smoke verification recorded. Shared-host contact evaluation measured 59–94 µs median; complete ground ticks exceed the 500 µs target. The implementation is experimental pending measured RC calibration and performance work; neither gate is silently marked passed.

## Objective and audit

Deliver aircraft-specific grass-field contact without changing aerodynamic, propulsion or rigid-body equations. Verification establishes numerical behavior; physical calibration requires measured RC rollout/drop/taxi data and pilot review.

The production engine is Godot **4.7.2.stable.official.ed1daf0bf**, verified by executing the installed Windows binary. `app/get-godot.sh` pins 4.7.2. Physics is float64 GDScript and `PackedFloat64Array`, RK4 at 240 Hz, not Godot rigid bodies. Godot 4.7 documentation confirms double-precision scalar floats. Keep all transcendentals behind `math3d.gd` and preserve the existing renderer boundary.

Existing foundations: `ground_contact.gd` provides individual spring/damper contacts, non-pulling normal forces, tire grip, rolling resistance, steering and optional static anchors; `ground_surfaces.gd` samples the same field rectangles used by rendering. `ground_start.gd` solves static equilibrium. Session continuous state already carries wake/shaft/battery dynamics with checkpoint validation. Mass, inertia, CG, contact locations, travel and steering are aircraft-specific validated data. Existing E1–E5 tests cover drops, coast-down, stiction, takeoff, landing, taildraggers and nose-over mechanics.

Gaps: ground is flat; there is no wheel rotational state or equipment-specific brake torque; rough-grass coefficients are provisional full-size analogies; contact diagnostics/crash travel must use the same height as forces. The default runway is a 100 × 12 m short-grass strip centered at N=15 m, E=0 m, surrounded by rough grass. There is no default intermediate mown rectangle. Avanti S is explicitly gear-up with no wheel contacts; do not invent invisible deployed gear or brakes.

## Force model

For wheel i, transform its CG-relative undeformed contact point and `v + omega × r` into NED. Query terrain height and gradient at that wheel, never at the CG. Construct upward normal n and an orthonormal rolling/lateral basis projected onto the local tangent plane. Compression is the normal gap below the terrain; its rate uses the same normal and point velocity.

`N_i = max(0, k_i * compression_i + c_i(compression_i) * compression_rate_i)` for positive compression only. Retain the existing smooth damping onset and aircraft travel limits. Sum each force and its `r × F` moment. Pitch/roll weight transfer, tail lift, rotation, intermittent contact and bouncing therefore emerge from the six-degree-of-freedom equations. No on-ground speed target, touchdown velocity reset, fixed deceleration or synthetic lift-off switch.

Separate mechanisms:

- **Rolling resistance:** `Frr = -Crr(surface, wheel radius) * N * regularized_sign(v_long)`. This represents deformation/grass losses, not a service brake. Maintain the current coefficients initially (runway/mown/rough factors 2.5/5/7.5); scale the vegetation component conservatively by wheel radius and label that scaling estimated.
- **Tire grip:** lateral slip force retains the current saturated slip-angle law. Longitudinal contact slip is `v_long - R*wheel_omega`. A dissipative bounded slip force spins the wheel up and opposes slip; clamp combined tangential demand to `mu*N`. Do not double-count rolling resistance as brake torque.
- **Wheel spin:** append one rim-speed state `R*omega` per configured wheel to continuous state, after existing wake/shaft/battery slots. Use `I/R²` as effective rim mass. The same stage force supplies body force and opposite wheel torque. A declared tire relaxation time limits stiffness at 240 Hz; test timestep refinement and energy rather than silently forcing instantaneous rolling.
- **Braking:** torque is enabled only by declared hardware and a separate command; absent/unknown equipment means zero brake torque. No automatic brake on throttle reduction. All currently supported fixed-gear profiles start unbraked unless a primary hardware source establishes otherwise. Synthetic braked fixtures verify the distinct API.
- **Rest:** retain low-speed anchors and load-limited breakaway. Release anchors on loss of contact. Use the same terrain query in force, anchor, compression and travel-limit paths.

Lift unloads each wheel through the existing body motion and contact load. Every tire force tends to zero with N and is exactly absent off the terrain. Wheels may retain spin in flight, but ground loads must remain empty and airborne body trajectories must match the baseline exactly. Small wheel gyroscopic effects, unsprung axle dynamics and leg bending are outside this first implementation; state this explicitly rather than implying a full multibody tire model.

Implementation refinement: `Crr_i = Crr_aircraft * [1 + (surface_factor - 1) * sqrt(R_max_aircraft / R_i)]`. Existing aircraft coefficients already account for main-wheel size; a global reference radius would count that correction twice. Static anchors also require low rim slip, so a stopped axle with a spinning tire cannot acquire a false static contact. Body moments include the wheel spin-up angular-momentum reaction.

## Terrain and visible agreement

Keep the existing field rectangles and their precedence (runway, mown, rough, outside=rough). Use a deterministic, time-independent height function with analytical gradients and a smooth amplitude transition at boundaries. Initial relief targets: roughly 1 mm on maintained runway and 6–8 mm in rough grass, spatial wavelengths around 0.4–1.2 m. These are RC-scale engineering assumptions, not a surveyed field or measured grass height. No random force or frame-driven noise.

Match the visible grass categories, edge locations and terrain relief. Share the terrain parameters/formula with rendering where the existing mesh permits displacement; keep blade height distinct from load-bearing soil height. Wheel radius affects rolling losses, not the location of the field. Preserve existing landscape assets, scenery, distant hills and non-colliding objects. Provide a flat analytic fixture and sloped terrain fixture for independent force/energy tests. Do not turn distant visual hills into collision terrain accidentally.

Implemented scope: the coarse field mesh receives matching **normal cues**, not vertex displacement. Wheel physics samples the full millimeter relief; wheel pivots show compression and spin. Airframe hull collision retains the existing flat plane. The current six-value surface table uses rolling-factor classes as a temporary terrain-amplitude selector; changing these classes affects both resistance and relief. Separate calibration needs an explicit terrain-material field.

## Aircraft configuration

Preserve generated aircraft JSON and geometry. Add a provenance-bearing ground wheel profile keyed by aircraft ID/contact name, validated before flight; bind it to the existing derived gear. Profiles specify radius, rotational inertia (or an explicitly derived equivalent), relaxation time and maximum brake torque. Derive tire coordinates only from existing aircraft gear geometry; never replace mass/inertia/CG.

| Aircraft | Existing configuration | Ground treatment |
| --- | --- | --- |
| Ugly Stik .60 | Tricycle; steerable nose wheel | Individual main/nose sizes, existing spring/travel/steering; unbraked rollout |
| Extra 300S .60 | Taildragger; steerable tail wheel | Smaller tail tire, existing negative tail steering sign; three-point and wheel-landing fixtures |
| P-51D 120 cc | Larger taildragger | Existing generated gear/CG/inertia; larger mains, small tail tire; nose-over and asymmetric-drag checks |
| Avanti S | Gear-up, in-air experimental model | Retain flight and hull-contact behavior; deployed-gear taxi/landing acceptance requires model-owner geometry and equipment work |
| Electric/other data variants | Preserve their declared contacts | Explicit matching profile or clear legacy/no-profile behavior; do not infer brake hardware from propulsion type |

Actual values and their evidence are retained in the implementation report. Suspension/CG tuning remains in each existing aircraft source pipeline. Wheel masses/inertias and field roughness without measurements are `estimated`, not `measured`.

## Integration and ownership

| Area | Assigned owner and boundary |
| --- | --- |
| Ground forces, wheel law, acceptance integration | Lead: new ground modules, narrow `ground_contact.gd` delegation, ground tests/research |
| Terrain/render audit and implementation | Bounded Luna max task; terrain module and one necessary renderer hook only; no landscape asset regeneration |
| Aircraft profiles/session continuous state | Bounded Luna max task after plan completion; profile loader and narrow session functions; no aerodynamic/propulsion equations |
| Independent review/test evidence | Luna max review of equations, fixtures and changes; lead reviews every contribution |
| Other active developers | Existing ownership registry remains authoritative; preserve all uncommitted changes, especially crash/audio, models, UI and scenery |

At audit start only crash-audio files were dirty; during audit crash presentation edits appeared in `main.gd`, `flight_session.gd` and crash tests. Reserve ground work in this plan; use isolated draft copies, apply only owned hunks, re-read shared files immediately before integration. Session crash auto-restart changes belong to the crash track and must survive. No direct communication endpoint for those external sessions is available; this file records the coordination boundary, not an acknowledgement from those developers. Any overlap discovered during integration requires a bounded merge and renewed verification.

Preserve existing public function signatures with optional arguments/new entrypoints. Do not change the 13-component rigid-body state, input-channel meanings, aerodynamic/propulsion calculations, model hinge names or UI flows. Continuous-state offsets, reset, fingerprint, trace metadata and checkpoint restore must account for wheel states. Diagnostics must identify actual ground law and estimated parameters. No dependency upgrade.

## Phases and proof

| ID | Deliverable | Required proof | Status |
| --- | --- | --- | --- |
| GP-00 | Audit, primary-source research and this complete plan before code | Engine version, ownership snapshot, reviewed equations and integration map | Complete |
| GP-01 | Validated aircraft wheel profiles and deterministic terrain | Invalid quantities rejected; surface/edge precedence and gradient oracles | Integrated; [evidence](docs/research/ground-physics/GP-01/README.md) |
| GP-02 | Per-wheel terrain, slip/spin, rolling and brake law | Power/force bounds, lift-off zero, spin-up, slope and unequal-wheel moments | Integrated; [28 analytic checks](docs/research/ground-physics/GP-02/README.md) |
| GP-03 | Session/diagnostic/render integration | Exact replay including wheel state; unchanged airborne body trajectory; visual/physical field agreement | Integrated; [state/reader checks](docs/research/ground-physics/GP-03/README.md), exact eight-case airborne parity |
| GP-04 | In-engine aircraft/surface scenario matrix | Measurements and timestep refinement below | Numerical matrix measured; physical/pilot validation open; [evidence](docs/research/ground-physics/GP-04/README.md) |
| GP-05 | Full regression, performance, tuning and limitations report | Durable logs, commands, reviewed diff and implementation report | [Results and remaining gates](docs/research/ground-physics/GP-05/README.md); no blanket full-suite or performance acceptance claim |

## Measurable acceptance and performance

Use native Godot headless tests plus a rendered field inspection. Retain raw JSON/CSV and logs under `docs/research/ground-physics/GP-04/`; reproducible drivers under `research/ground-physics/`. Distinguish software acceptance from physical validation.

1. Contact load: 0/25/50/100% normal loads produce corresponding rolling/slip force limits; airborne returns exactly no ground loads. Flat stationary weight balance within 0.1% of mg.
2. Analytic rolling: flat, aero-off, settled coast-down at 2/5/10 m/s agrees with `a=Crr*g` within 5% after spin transient. Rough grass stops sooner than runway for every supported wheeled aircraft; record distance to 0.1 m/s and time. Negative/reverse speeds must dissipate energy too.
3. Spin-up: wheel starts at zero on a moving drop/touchdown; wheel speed approaches rolling speed with a finite drag transient. Slip power ≤0, combined grip bounded by mu*N, no spontaneous wheel acceleration in free flight. Synthetic brakes reduce stopping distance; unbraked aircraft ignore brake demand.
4. Suspension: 0.1/0.3 m drops at 240/480/960 Hz, peak compression, rebound height, contact loss/reacquisition and settling time. Accept finite state, no tensile ground force, no energy growth on flat ground, ≤5% difference between 480/960 Hz event measures and ≤10% between 240/480 Hz. Record collapse instead of clamping excessive impact.
5. Edges: each main wheel crosses independently at 2/5/10 m/s, both directions. One rough-side wheel produces the expected yaw moment; no height step or artificial impulse at the boundary. Fully off runway has larger resistance and vertical excitation than on runway.
6. Aircraft handling: Stik tricycle and Extra/P-51 taildraggers; taxi steering signs, takeoff unloading/rotation, three-point versus main-wheel touchdown, crosswind side loads/skid, slope response, taildragger directional divergence and nose-over moment balance. Accept mechanism-specific signs/bounds and record trajectories; no invented universal safe crosswind or pilot rating.
7. State safety: malformed profile/terrain refuses use, replay continuation matches exact body/continuous/aux bytes, pause/reset clears wheel state appropriately, mismatched configuration rejects checkpoint. Calm and windy airborne baseline body/aux remain identical.
8. Performance: 240 Hz gives 4167 µs/tick; project target remains **500 µs whole physics/tick** on the eventual target machine. Ground allocation target ≤75 µs/contact evaluation and ≤150 µs additional whole tick on this host, with ≥1000 measured warm ticks and median/p95 reported. Benchmark timing alone, label host/engine and whether baseline meets the project budget. Do not conceal a missed budget or infer target-machine acceptance from this workstation.
9. Run existing ground/taildragger/crash, continuous-state, golden flight and full `app/test.sh` regressions. Do not re-record airborne goldens. A deliberate changed ground result needs reviewed physical reasoning and retained old/new evidence, not a blindly widened tolerance.

## Tuning and limitations

Tune in order: geometry/mass/CG → static load and sag → drop damping → flat runway coast-down → rough-grass coast-down → wheel inertia/spin transient → steering/skid → crosswind handling. Use the existing VAL-5/6/8 measurement workflows. Keep calibration and held-out runs separate. No independent measured RC rollout/drop data was supplied; coefficients are provisional. Wet soil, rut formation, grass entanglement, tire pressure/temperature, retracts, toe/camber, free-caster shimmy, individual brake input hardware and deformable airframes are later work. Current Avanti landing gear is not implemented by this ground change.

## Primary sources (accessed 2026-10-11)

- [JSBSim FGLGear](https://jsbsim-team.github.io/jsbsim/classJSBSim_1_1FGLGear.html): per-contact spring/damper reactions, friction, steering, brake groups and moment arms. Architecture reference, not an RC coefficient calibration.
- [FAA Airplane Flying Handbook, Chapter 6](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/07_afh_ch6.pdf): soft-field acceleration and wheel unloading. Qualitative full-scale mechanism only.
- [FAA Airplane Flying Handbook, Chapter 14](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/airplane_handbook/15_afh_ch14.pdf): tailwheel stability, wheel/three-point landings, ground loops and soft spots. No direct transfer of full-scale operating limits.
- [NACA: The influence of wheel spin-up on landing-gear impact](https://ntrs.nasa.gov/citations/19930084093): wheel spin-up as a distinct landing-load mechanism; does not supply RC tire properties.
- [Godot 4.7 float](https://docs.godotengine.org/en/4.7/classes/class_float.html), [Godot VehicleBody3D](https://docs.godotengine.org/en/4.5/classes/class_vehiclebody3d.html): retain float64 custom solver; built-in vehicle implementation explicitly is not intended for realistic advanced vehicle physics. Version-specific API checked against Context7's Godot 4.7 documentation and the executable.
- Existing provenance: `app/data/ground/surface_friction.json` cites FlightGear grass material factors; keep their borrowed/estimated evidence labels and avoid presenting them as measured RC turf coefficients.
