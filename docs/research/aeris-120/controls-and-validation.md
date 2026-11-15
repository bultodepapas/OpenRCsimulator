# Controls, handling feel and validation protocol

**2026-11-15 · A120 research.** These are proposed configuration and acceptance procedures. No matching radio, servo, engine or aircraft was tested. [Plan/status](../../plans/aeris-120-3d-gas.md), [sources](sources.md), [source audit](integration-audit.md).

## 1. Control ownership and conditioning

Trace physical stick/channel → device calibration → permitted input shaping → accepted command → actual servo/surface state → local force/moment → aircraft motion. Record each boundary. The physics responds to deflected surfaces; it does not accept commanded roll/pitch/yaw rates as though the aircraft were stabilized.

| Route | Curve/rate owner | Required behavior |
| --- | --- | --- |
| Calibrated RC transmitter | Transmitter owns configured expo, rates and mixes | Preserve OpenRC's radio shaping bypass; calibrate channel order, reversal, endpoints and throttle independently |
| Gamepad | Device profile plus supported aircraft travel/profile semantics | Apply device expo once; distinguish short-stick ergonomics from aircraft mechanics |
| Keyboard | Virtual-stick response plus supported aircraft profile | Document rise/return behavior; do not qualify transferable 3D radio feel from keyboard flight |
| Script/replay | Recorded accepted controls or declared external-driver inputs | Preserve tape timing and identities; not a substitute for input-to-display latency or pilot adaptation |

EdgeTX explicitly allows weights/curves in inputs and mixes [S11]. That makes duplicate shaping a practical integration risk. Show and record ownership; do not guess it from the radio brand. Mode 1/2 changes the human stick assignment, not the force equations. Record channel mapping rather than assuming AETR is the device's physical axis order.

Use the existing cubic expo semantics where applicable: `f(x) = (1-e)x + e x³`; positive `e` softens the centre while preserving endpoints. A displayed manufacturer expo percentage is not automatically the same transfer curve. Trim, reversible setup changes and optional pilot mixes must have a single owner and remain visible in logs/configuration.

## 2. Reference throws and profile mapping

The EF sheet [S02] is a **donor setup**, not a measured AERIS flight tune:

| Axis | Published low reference | Published high/3D reference | Initial AERIS planning choice |
| --- | --- | --- | --- |
| Aileron | 20° up/down; 18–20% expo | 38° up / 37° down; 50–60% expo | Physical max 38° up / 37° down, pending linkage check |
| Elevator | 10–12°; 18–20% expo | 50–55°; 50–60% expo | Physical max 55°, pending linkage check |
| Rudder | 20°; 50–60% expo | 45+°; 60–80% expo | Physical max 45°, pending linkage check |

These angle references describe surfaces, not servo-shaft rotation or normalized aircraft rates. The published 60+° XA elevator option is outside the initial admitted envelope.

For one conservative development **normal** profile, proposed travel fractions are `20/38 = 0.5263` aileron, `12/55 = 0.2182` elevator and `20/45 = 0.4444` rudder, with approximate simulator expo 0.20/0.20/0.55. These are engineering choices derived from donor settings, not exact transmitter conversions. Because the aileron maximum is asymmetric, the shared fraction gives about **20° up / 19.47° down**, not exactly ±20°; document that limitation instead of claiming exact reproduction.

Current `normal`, `sport` and `full` semantics remain intact. `sport` retains normal pitch/yaw and full roll with normal expo. `full` gives physical full travel without aircraft expo. A radio pilot can select high 3D rates/expo on the transmitter while the radio path remains unshaped. Gamepad device expo still follows its profile. Do not add a `rates.3d` key to the closed schema or silently label raw `full` as an EF high-expo setup. A dedicated third simulator profile is a later D6/UI extension if needed.

Characterize the unassisted airframe with ordinary trim, no stabilization and no rudder-to-elevator/aileron mixes. After coupling is measured, an explicitly named pilot setup may include those mixes. Switching profiles changes targets; actual surfaces still traverse at their allowed speed.

## 3. Servo and throttle behavior

The source has one shared neutral-to-full servo travel time for three logical axes. The EF donor lists seven surface servos plus one throttle servo [S02]; AERIS's actual count is unconfirmed. The current law cannot independently model that donor installation's loaded servos. The [D6-SRV plan](../../plans/servo-dynamics.md) owns that future extension; avoid a second AERIS-only servo framework.

Convert manufacturer seconds/60° through actual linkage geometry. If `delta_surface = k * theta_servo` locally and the catalog speed is `omega_servo = 60°/t60`, a small-range estimate is `t_neutral_to_full = delta_max/(k * omega_servo)`. Real linkages are nonlinear and need several measured points. At 7.4 V, SB-2290SG's published `t60 = 0.13 s` corresponds to about 461.5°/s at its shaft [S10]; it does not establish AERIS surface transit under hinge load.

First use finite travel, explicit end stops and the existing rate model with a documented approximation. Measure the actual motion before adding small-signal lag, deadband, backlash or load-related blowback. Manufacturer no-load speed, holding/stall torque and transit delay are different quantities. Listing multiple physical servos in an inventory does not create independent runtime actuator states.

A throttle-servo/carburetor state, shaft acceleration and input latency are distinct. The baseline shaft law must not be slowed by several unexplained lag filters. Any new continuous actuator state belongs in RK derivatives; sampled control logic remains once per accepted tick with its timing declared. New state must be checkpointed/replayed and supported by the backend.

## 4. What to measure as handling feel

| Pilot description | Discriminating measurement | Likely causes to separate |
| --- | --- | --- |
| “Too twitchy near centre” | Surface angle versus stick; small-command angular acceleration | Double expo/trim, linkage travel, CG, control derivative |
| “Heavy or delayed” | Device timestamp → command → surface → attitude onset | USB/render delay, sampled controls, servo rate, physical inertia |
| “Rolls but will not stop” | Roll-rate decay and overshoot after a matched release | Inertia, aerodynamic damping, actual surface return, input smoothing |
| “Hover needs constant full correction” | Powered zero-speed moment map and correction margin | Wake overlap, torque reaction, CG/thrust alignment, available surface travel |
| “Floats on the downline” | Airspeed/energy/RPM after throttle chop | Prop braking/windmilling, drag, mass and residual thrust |
| “Knife-edge pulls or rolls” | Both-direction rudder, pitch/roll moments and sink | Body sideforce location, fin force, thrust offset, gyro and optional mixes |
| “Harrier looks artificially stable” | Wing-rock amplitude/frequency, control workload, trim state | Missing local/asymmetric flow, excess damping, hidden stabilization |
| “Snaps are identical every time” | Entry-state sensitivity and recovery response | Scripted trigger, overconstrained control law or insufficient local separation |

Do not change camera gain, expo and physical coefficients in the same comparison. Freeze ground-pilot sightline, field of view, auto-zoom, wind, fuel and frame pacing. Evaluate chase view separately. Render actual simulated surface state and drive audio from accepted RPM/load/source state. Assess engine pitch, prop sound and event timing by listening; a source mapping alone is not audio acceptance.

## 5. Measurement and calibration order

Use the existing [measurement reducers](../../TOOLS.md#aircraft-measurement-reducers), [flight-test tooling](../../../research/flight-test/README.md) and [flight logging](../../FLIGHT-LOGGING.md). Prefer existing free measurement/plotting tools. Record source commit, generator/data hashes, engine/backend, prop/exhaust, fuel state, atmosphere, controller firmware/profile and camera settings.

1. Establish geometry, dry/full mass, CG and inertia estimates. Check the asset's physical datum and controls without redesigning it.
2. Fit bench propulsion and actual servo travel from identified hardware; retain repeated measurements and uncertainty.
3. Fit power-off/idle glide, upright/inverted trim, low-angle forces and one-axis responses at several speeds.
4. Fit powered coupling, propwash control maps and thrust-line effects. Avoid fitting CG and elevator moment to the same uninformative observation.
5. Fit high-alpha steady states and transitions. Reserve different speeds, fuel states, throttle histories and maneuver entries as held-out validation cases.
6. Add unsteady state only for repeatable unresolved discrepancies; compare the added complexity against the simpler model.

Experimental identification literature supports separating parameter fitting from validation and exposing uncertainty [S17, S18]. Linear attached-flow estimates must not be extrapolated through stall. Calibrated video can support geometry/time/trajectory; an uncalibrated clip cannot identify exact airspeed, force or inertia. Label qualitative comparisons accordingly.

## Maneuver cards

Each card records initial state, fuel/density, setup, actual input/surface tape, RPM, markers, observations, uncertainty and supported envelope. Repeat in both directions/signs where applicable. Pass/fail tolerances are frozen before evaluating the candidate.

| Card | Maneuver / condition | Required observables and mechanism | Acceptance limit |
| --- | --- | --- | --- |
| A120-C01 | Taxi, takeoff and landing | Ground track, tail rise, rotation, prop/yaw coupling, contact energy, bounce and rollout | Match geometry and contact behavior; no artificial speed-based steering lock. Physical runway/tire calibration remains explicit |
| A120-C02 | Upright and inverted trimmed passes | Speed, throttle/RPM, elevator trim, drift and required pilot correction | Multiple speeds/fuel states; inversion need not be perfectly symmetric |
| A120-C03 | Idle glide and positive/negative stall | Sink/airspeed, lift break, wing drop, pitch recovery and hysteresis | No invented manufacturer stall speed; use measured envelope and uncertainty |
| A120-C04 | Axial roll and roll stop | Actual aileron motion, rate rise, steady rate, stop overshoot, adverse yaw/pitch | Several speeds and throws; separate actuator lag from inertia/damping |
| A120-C05 | Loop, vertical upline and downline | Energy/speed change, radius, RPM unloading and braking | No constant climb rate, fixed trajectory or unexplained energy gain |
| A120-C06 | Both knife-edge directions | Rudder required, sink, sideforce and pitch/roll coupling | Force/moment support with mixes off; record asymmetry and later pilot mixes |
| A120-C07 | Hover and throttle recovery | Force/moment equilibrium, RPM, drift, correction reserve and wake exposure | Human-controlled hover with no hidden lock; moment-map evidence before pilot scoring |
| A120-C08 | Torque roll | Roll acceleration and rate versus throttle/control, pitch/yaw correction | Emerges from torque balance and actual aileron exposure; no triggered animation |
| A120-C09 | Upright/inverted harrier and parachute | Attitude, sink, RPM/throttle, wing-rock statistics and pilot workload | Quasi-steady limits stated; do not force a universal oscillation amplitude |
| A120-C10 | Rolling harrier | Altitude drift, roll rate, phase of elevator/rudder inputs and wake variation | Correct coupled response to the pilot sequence; no automatic phase assistance |
| A120-C11 | Hammerhead, wall, waterfall and pop-top | Entry speed/rates, available powered authority, inertial/gyro coupling and recovery | Separate each entry and maneuver; initially experimental where transient data are missing |
| A120-C12 | Positive/negative snap and upright/inverted spin | Asymmetric stall, entry state, rotation statistics, exit input/time/altitude | No fixed spin trigger; evaluate recovery and envelope, not exact long-horizon trajectory |
| A120-C13 | Tailslide and reverse flow | Signed hub/section flow, torque/power regime, control reversal and transition | Numerical coverage first; legacy negative-J clamp does not qualify this maneuver |
| A120-C14 | Wind/density/fuel variation | Matched input/weather seed, drift, control load, RPM and balance | Recompute consistent atmosphere/mass effects; avoid extrapolating beyond measured range |
| A120-C15 | Idle, ignition cut, depletion, restart and pause/restore | Source state, shaft speed, wake decay, fuel mass and accepted controls | Only supported lifecycle actions; stopped engine cannot regain power from throttle alone |

## Numerical and integration gates

These are **proposed engineering gates**, not aircraft specifications. Adopt tolerances with the physics owners before implementation, and adjust only for documented resolution/measurement reasons.

| Gate | Evidence required |
| --- | --- |
| Frames and units | Positive force/control fixtures, known lever-arm moment, body/render mapping and normalized-angle conversion |
| Force consistency | Local-flow/section/power ledger; no double damping, prop reaction or washed surface loads; low-angle oracle continuity |
| Boundaries | Finite outputs over angle/deflection/RPM grids, zero local speed, signed-flow seams, fuel-out and contact transitions; no fabricated minimum aerodynamic pressure |
| Isolated conservation | Torque-free/known-load cases and rotor/body angular-momentum ledger using documented inertia convention; physically dissipative idle/contact behavior |
| Control authority | Powered/unpowered zero-freestream maps, immersed versus unwashed surfaces, direction of torque/swirl/gyro; test unsupported rotation senses in analytical fixtures only |
| Stage/state lifecycle | Continuous states evaluated at RK stages; sampled actions once at their declared boundary; reset, restore, rollback and candidate identity complete |
| Replay and backend | Exact replay under its supported engine/backend identity; explicit candidate replay with `complete`/`solver_changed`; new-law native admission/parity and reference fallback |
| Timestep/discretization | Controlled 120/240/480 Hz and strip-resolution study on identical physical input times; production remains 240 Hz |
| Shared regressions | Existing aircraft/laws unchanged unless a separately explained physics revision is intended; no unexplained golden refresh |
| Whole-session performance | Real target-machine p50/p95/p99 and sustained overload evidence at 1080p, including recordings/presentation; renderer quality must not alter physics |

A proposed nonchaotic ten-second refinement target is less than 1° final attitude difference, 0.5 m final position difference and 2% rate RMS difference on a declared nonzero reference scale. Inspect trends over two refinements and event times; these illustrative thresholds can be too loose or too strict for a specific case. For spins/wing rock, compare entry, statistics and recovery distributions as well as short-horizon convergence.

For identified bench hardware, provisional calibration goals are about 5% thrust/RPM error and 10% attached-flight response error **only if** measurement uncertainty and repeatability support those numbers. Freeze each observable's absolute/relative tolerance and denominator in the card. Missing data means unqualified, not an automatic pass using the simulator's own baseline as truth. No universal high-alpha numerical tolerance or consumer-device latency guarantee is claimed.

## 8. Pilot evaluation and delivery evidence

Use experienced 100–120 cc aerobatic pilots for the actual 3D assessment, with the same radio and fixed view. Run blinded A/B tasks where practical and record specific discrepancies in precision tracking, neutral sensitivity, roll stops, hover correction, throttle management, coupling and recovery.

Rate subjective confidence separately from measured agreement. Record whether the pilot knows the exact airframe/engine/prop or only the class. One pilot's preference cannot establish a full physical envelope, and consensus cannot replace missing flight data.

For a promoted configuration retain source/config identities, bench summaries, complete logs and replay reports, maneuver markers, calibration/holdout split, device/OS evidence and 1080p captures. Store lightweight summaries and hashes/download or regeneration routes, not unneeded raw media. Release wording must name remaining experimental maneuvers and the measured scope.
