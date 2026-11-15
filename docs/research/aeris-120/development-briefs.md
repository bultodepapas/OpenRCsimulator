# AERIS-120: bounded development briefs

**2026-11-15 · planning handoff, not implemented behavior.** The [A120 plan](../../plans/aeris-120-3d-gas.md) owns status and order. These briefs define reviewable boundaries, observations and discriminating checks for its existing steps. Runtime identity and existing tests are in the [source audit](integration-audit.md); deeper rationale is in the [evidence update](evidence-update-2026-11-15.md). No new public issue or PR is implied by these identifiers.

## Ready work and dependencies

| Brief | Owning step / collaborators | Concrete deliverable | Ready when |
| --- | --- | --- | --- |
| B1 — configuration and observation specimen | A120-01/02; AS, FL | Evidence ledger, actual geometry/mass inventory, generator skeleton and observation mapping | Unknowns remain explicit; no donor default silently becomes AERIS data |
| B2 — common gasoline hub inflow | A120-04; propulsion, SF/NK | Shared local-inflow contract and a failing/passing source-family comparison | Current base and spatial-wind semantics rechecked |
| B3 — coherent wing/tail wash | A120-04; aero/wake, SF/NK | One local flow/force accounting model with partial overlap and discretization evidence | B2 contract, actual geometry and baseline law family identified |
| B4 — installed propulsion response | A120-03; FUEL, propulsion | Identified equilibrium/step evidence and explicit lifecycle disposition | Matched prop/engine identity; unsupported parameters remain estimated |
| B5 — controls and perceptual timing | A120-06/11; D6-SRV, input, CAM/AUD | Installed surface mappings, conditioning identity and device/presentation observations | Actual linkage/device observations, or an explicitly unqualified approximation |
| B6 — aerodynamic and 3D calibration | A120-05/09; aircraft/physics, FL | Frozen fit, held-out comparisons and maneuver-specific claim | B1–B5 evidence sufficient for the regime being assessed |
| B7 — reverse flow and unresolved memory | A120-10; aero/propulsion, SF/NK | Reproduced mismatch, candidate law and supported-envelope disposition | A repeatable residual is distinguishable from flow/servo/measurement errors |

B1's inventory/contract work and B5's data collection can proceed alongside B2. B3 needs the common inflow definition. B4 bench evidence can proceed independently of model binding. Start B6 in attached flow; powered 3D acceptance requires B3. B7 must not delay basic instrumentation, and L3 must not be declared before its relevant gaps are resolved.

## B1 — a physically identified specimen

Create an input ledger under the existing [research kit](../../../research/aeris-120/README.md), preserving the aircraft-v2 `{value, unit, kind, source}` contract in the future generator. The current reference calculator is **not** that generator. Reconcile the supplied model's metres, datum and hinge pivots; use measured or inventory-derived dry/full/empty mass, CG and inertia. Preserve component identities and fuel state; do not add an engine twice to an all-up mass. Keep structural-LE coordinates, fixed state origin and live CG distinct.

**Deliverable:** a developer specimen with traceable unknowns, supported capability admission and stable model binding, followed by regenerated manifests/descriptors through their owners. A completed 3D mesh does not establish mass, inertia, control travel or contact geometry.

**Checks:** source-generator freshness; schema plus actual loader; positive-definite physically plausible inertia; full/empty mass/CG consistency; control signs and hinge alignment. Use existing contract/data/model checks from the audit. A schema-valid specimen is L0 only after its own required evidence, not because this plan exists.

## B2 — one definition of air velocity at the propeller hub

At the audited base, `Propulsion.stage_air_velocity()` handles hub rotational velocity for explicit glow/electric routes while legacy gasoline can fall back to datum inflow. Resolve this shared mechanism; do not add an `aeris_120` kernel branch or an unsupported `gas_prop` kind.

Define apparent air-relative velocity at point P from the state origin O as `V_rel(P) = V_ground(O) + omega × r_OP - wind(P)`, with all terms transformed into the same frame. This is the vehicle-point velocity relative to ambient air; air velocity **relative to that moving point** has the opposite sign, while ambient wind is still `wind(P)`. Document whether a supplied spatial override already represents hub velocity. Reusing it must not add `omega × r` a second time. Keep thrust-axis projection and crossflow distinct.

**Small first implementation slice:** unify the shared hub-point evaluation and pass that exact result to shaft load, thrust/normal force and wake-source evaluation. Review `propulsion.gd`, `FlightSession._coupled_response()` and the native equivalent together. Preserve unaffected family behavior and identify any intentionally corrected gasoline response.

**Discriminating checks:** zero angular rate in uniform wind recovers the datum case; at zero rate with a wind gradient, the hub-minus-datum difference is `-[wind(P)-wind(O)]`; a known off-axis hub with pure ±pitch/±yaw adds the analytic `omega × r` term; spatial-wind override is consumed once; matched prop/state gives matched air input across eligible source families; torque and force consumers use the same stage snapshot. Include origin/CG offsets. These are software/frame checks; they do not calibrate propeller crossflow loads.

## B3 — wing and tail share a coherent wash evaluation

Existing wing strips provide a useful force integration boundary, while `Slipstream.stage_loads()` currently contributes tail increments. The first design review must specify how wing inclusion preserves the existing baseline/oracle blend, local laws and moment arms. Reuse common local physics rather than maintaining separately tuned washed/unwashed curves.

For a given integrated element, a replacement/increment can be expressed as `F_free + [F_same_law(V_effective) - F_same_law(V_free)]`. This identity is useful only when **the same** area, section law, control state, blending weight, reference frame and moment convention are used in both evaluations. Adding a second full wing/tail load would double count. Preserve downwash/ground-effect terms where the chosen law already includes them; the deferred historical proposal failed related consistency checks.

**Inputs to define:** hub source velocity and load, geometry and thrust-axis frame, local ambient/spatial velocity, rotation at the element, wake support/overlap, axial and transverse increments, RPM/fuel/source state, and any declared transport state. Resolve the existing smooth-profile/swirl/transport compatibility restrictions as one contract. Do not merely enable incompatible fields in the authoring JSON.

**Required observations:** dimensional force and roll/pitch/yaw moment by component; actual surface angles; local free/effective velocity; overlap and force application point; total force/moment balance. Record whether values are accepted-endpoint observations or RK trial values. Diagnostics must be bounded, optional and read-only.

**Discriminating checks:**

- The total washed/free increment vanishes when every declared wake-source component and residual state is zero. Zero thrust alone is insufficient: torque-linked swirl or normal-force/sidewash can remain. Include forward-flow zero-thrust/nonzero-torque coverage; only the applicable axial momentum increment should vanish with zero thrust. During modeled wake decay, the declared transport state owns the remaining field.
- At zero freestream with a running prop, exposed controls may generate finite forces; unexposed elements do not receive a fictitious speed floor.
- Sweep a wake boundary across an element. Partial overlap must approach zero/full coverage continuously, with consistent moments.
- Refine spatial quadrature at fixed physical conditions and coefficients. Compare integrated forces **and moments**, not only a centre-point velocity. More strips are warranted only by unresolved convergence/error.
- Test mirrored controls/geometry with declared prop spin. Separate axial torque, swirl, normal force and gyro signs; actual aircraft asymmetry remains permitted.
- Demonstrate static force/moment maps before human hover. `T>mg` alone does not show sufficient pitch/yaw/roll authority or recovery reserve.

Calibration needs installed flow or load observations; the existing ground-field reducer does not measure wing/tail velocity. Test directional transport only after separating shaft response, field response and observer delay. Any new continuous state belongs in the model layout/RK derivatives and in reset, rollback, checkpoint and backend identity. Do not mutate a lag once per force call.

## B4 — gasoline bench and lifecycle

Preserve the current combustion-family/finite-fuel route and relative rotor coupling. Use the [acquisition map](../../../research/aeris-120/README.md#acquisition-map) for matched static thrust/RPM/torque and up/down step records. A null torque measurement must remain null; rated horsepower, thrust and ideal disk power do not fill that column.

Specify whether the initial specimen starts already running, and separately specify future ignition cut/start/restart events. The current gasoline path does not acquire glow lifecycle actions simply because its family is named `glow_prop`. Tank-feed/unporting/choke behavior requires its own accepted law and data. Avoid claiming inverted endurance from a diaphragm-carburetor principle alone.

**Checks:** known net torque and shaft inertia; relative-carrier acceleration coupling; spin-up reaction counted once; opposite ±pitch/±yaw gyro directions; steady prop power/torque identity; noncreating energy on cut; finite-fuel mass/CG/inertia evolution; exhaustion/pause/restore. For parameter fits, reserve independent load/step/temperature conditions. A global throttle-to-RPM time constant must not duplicate shaft dynamics.

## B5 — physical controls and perceived response

Document command → servo shaft → linkage → actual left/right surface angle, including reversals and endpoint asymmetry. Measure small/large travel and return separately under identified voltage/load. A catalog speed cannot identify bus sag, deadband, stiffness or blowback. Coordinate any additional state with D6-SRV; the baseline remains an explicitly approximate common slew law until replaced through that owner.

For radio use, record transmitter curves/mixes and verify the shaping bypass. For gamepad/keyboard, keep device conditioning and aircraft profile identities explicit. Compare the actual surface tape, not only stick travel. A new surface-to-force tune cannot compensate for duplicate expo or a bad linkage conversion.

Keep three observations distinct: physical-stick-to-displayed-marker latency, accepted-command-to-actual-surface response, and aircraft-motion response. Internal timestamps do not locate photon emission. The existing F6 camera protocol/reducer covers the first declared marker path, not total aircraft response. Freeze display/frame pacing and camera conditions in physics A/B trials; qualify presentation changes separately at 1080p.

## B6 — identify the simplest model supported by the data

Use the existing A120-C01…15 cards, adding the input/observable contract below. Fit mass/controls/bench evidence first, attached-flow behavior next, then powered and separated regimes. A single roll trace cannot independently identify inertia and both control/damping moments; a single hover trim cannot isolate wash speed from surface effectiveness.

| Observation group | Required recorded meaning | Missing-data disposition |
| --- | --- | --- |
| Identity and clock | Source/config/backend, exact hardware, datum, raw-file hashes, clock/filter offsets, validity flags | Unmatched runs remain qualitative or incomplete |
| Commands and surfaces | Conditioned command plus actual left/right angles, trim, rates/expo/mixes and throttle/butterfly where measured | Command-only data cannot identify loaded servo dynamics |
| Motion and air data | Orientation, body rates, CG-corrected specific force, GNSS, air-relative vector/wind and valid range | No use of GPS speed as airspeed or high-alpha extrapolation of an ordinary pitot |
| Propulsion and fuel | RPM, source enable/state, actual fuel/mass configuration, measured/derived thrust and torque identity | Calculated loads are model outputs, not independent observations |
| Simulated mechanism ledger | Local velocities, angles, force/moment components and any wake/separation state | Proposed diagnostic output, not claimed existing `.orfl` CSV fields |

Use pure accepted-endpoint observers or an owning offline probe for detailed mechanism data; any recorder extension needs FL ownership. Preserve baseline `.orfl`, prove exact replay, then run the candidate on the same tape. That is an open-loop model comparison. Changed conditioning, new pilot strategy and closed-loop handling need a new controlled recording. Keep `complete` and `solver_changed` visible.

**High-value paired experiments:** powered/unpowered large-deflection maps; matched up/down histories; both knife-edge directions; upright/inverted harriers with recorded corrections; isolated responses followed by withheld rolling-harrier combinations. Analyze entry, hold and recovery separately. Use short-time motion plus distributional/recovery comparisons for divergent spins, rather than demanding identical long-horizon trajectories.

For pilot work, fill the [evaluation record](../../../research/aeris-120/pilot-evaluation.template.md) before observing candidates. Define desired and adequate task tolerances, comparable setup and independent trial assignments. Keep tracking error, saturation and compensation separate from preference and confidence. No universal “realism score” follows.

## B7 — decide unsteady and reverse-flow extensions from a reproduced gap

First test whether a quasi-steady local-flow model with measured actuator/shaft behavior predicts held-out histories. At matched instantaneous local velocity, deflection and RPM, a repeatable force/moment difference between histories may justify memory. Check clock/filter bias, sensor saturation, rate effects and uncertainty before selecting a state equation. A fitted delay alone does not identify separation memory versus convected wake.

Separate reverse **axial inflow**, negative propeller torque/power at positive advance ratio, stopped-prop behavior and reversed shaft rotation. Current positive-J windmilling coverage does not qualify all four. For tailslides, record the unsupported domain explicitly until signed flow, control effectiveness, source/cut state and transitions are independently covered.

Any candidate must state its valid envelope, extra parameters and observations capable of identifying them. Require short-horizon/refinement checks, complete state lifecycle and supported native/reference admission. A lower training error alone is insufficient to replace the simpler law. A120-10 remains pending, with maneuver-by-maneuver experimental/deferred wording until the evidence changes.

## Review package for each future implementation slice

Retain the problem/reproduction, exact parent and candidate, owned source/generator changes, parameter provenance, focused tests, same-tape reports where applicable, independent physical evidence, and explicit limits. Use the existing test pool/checked-runner and ownership rules when running Godot or hardware tests. This documentation/research-tool change required no app launch, golden refresh, backend change or fleet qualification.
