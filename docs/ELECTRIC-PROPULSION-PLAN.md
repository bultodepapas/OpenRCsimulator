# Reusable electric propulsion

2026-10-10 · Revision 1 · Step prefix: **EL** (existing ROADMAP M4b namespace)

**Status: EL1a source kernel software verified; electric aircraft integration remains planned.**

Main-line physics subplan, selected by the owner on 2026-10-10. Owns `app/physics/electric_motor.gd`, electric tests, `research/propulsion/el*/` and `docs/research/propulsion/EL*/`; future loader, propulsion, trim, session and trace edits remain main-line work. Aircraft geometry/data, catalog, input and audio changes follow their owners. Research: [EL1a evidence](research/propulsion/EL1a/README.md), [primary sources](research/propulsion/EL1a/sources.md), [Timber reference](research/propulsion/EL1a/timber-reference.md). Related: [coupled shaft](PROPULSION-CORE-PLAN.md), [Timber](TIMBER-INTEGRATION-PLAN.md), [atmosphere](ATMOSPHERE-PLAN.md), [main roadmap](../ROADMAP.md).

## Outcome and first configuration

One data-driven motor/ESC/battery chain must serve several direct-drive, single-propeller aircraft without aircraft IDs in physics. Keep propeller aerodynamics, motor torque, electrical supply and pilot/ESC control separate. Reuse the float64 flight solver and G2a/G2b rotor coupling. Electric work does not require completion of nitro failures, fuel burn or sound propagation.

Use the currently sold **E-flite Turbo Timber Evolution BNF Basic B, EFL105250B**, with a **4S 3200 mAh pack class**, as the reference selected after the owner delegated configuration choice. This is not a sales-popularity claim or confirmation of the incoming mesh's hardware revision. The B reference has an 800 Kv motor, 70 A ESC and stock three-blade 11×7.3 propeller. Manufacturer data establishes these labels, not winding resistance, loaded voltage, motor losses or propeller performance. The exact pack SKU/condition and its mass/position need their own evidence. [Revision and source matrix](research/propulsion/EL1a/timber-reference.md)

First flight target: fixed, explicitly prescribed bus voltage; wheels fitted, flaps up, slats off; direct drive, brake off, forward motoring, no receiver assistance; trimmed in-air start. Real BNF observations must identify AS3X as well as SAFE: disabling SAFE alone does not establish an unaided reference. A synthetic electric test airframe can exercise integration before Timber data is ready; it must not be labeled a validated Timber or silently registered over the nitro Stik.

## Physical contract

| Piece | Initial rule | Evidence and boundary |
| --- | --- | --- |
| Motor | `kt = 60/(2π Kv_rpm/V)`, `E = rpm/Kv`, `I = max((d Vbus − E)/R, 0)`, `Qsource = kt (I − I0)` while rotating | Drela DC-equivalent three-constant model; positive rotation only. Equivalent current is not measured phase RMS current. |
| ESC | Effective duty `d` in `[0,1]`; ideal averaged conversion `Ibus = d I`; zero duty/disabled disconnects | Motoring-only approximation, no switching loss, active braking or regenerative path. Actual commercial switching topology is a later measured choice. |
| Mechanical loss | Coast retains `−kt I0`; at exact rest friction opposes only available torque, never starts reverse spin | Explicit Coulomb-loss extension of the model, not a measured low-speed/cogging law. Negative-speed input is refused. |
| Battery EL1 | Prescribed terminal voltage, no state or depletion | Nominal 14.8 V and charged 16.8 V are different operating assumptions. Neither establishes loaded pack voltage. No endurance claim. |
| Propeller | Existing `Ct/Cp`, stage RPM, axial air-relative velocity and field density | Shared load path. No stock three-blade map inferred from Kv, pitch or the Stik's two-blade data. |
| Rotor/body | Existing locked-inertia simultaneous solve | Source torque is internal. External propeller torque, relative-spin reaction and gyro momentum enter exactly once. |

The kernel returns source torque, equivalent motor/battery current, command/actual terminal voltage, mode and power accounting. `Pbus = Pshaft + Pcopper + Protational`; coast can have negative shaft power with zero battery current. At open circuit the motor terminal voltage is its back EMF, even when command voltage is zero. An ESC's nameplate current rating is not automatically an implemented current clamp. High synthetic startup current must remain visible until a justified startup/current-limiting model exists.

Invalid types, nonfinite values, negative RPM/voltage, duty outside `[0,1]`, nonpositive Kv/R, negative I0 or arithmetic overflow return failure. No fallback to a glow law. EL1a is a stateless source; it does not advance RPM, arm hardware, handle a propeller or own simulation time.

## Data and runtime integration

### EL1b: schema and a normalized model

Add an explicit `electric_prop` branch to both `aircraft_data.gd` and `openrc-aircraft-v1.schema.json`; keep all existing branches and raw file identities unchanged. Validate the raw block before deriving a normalized model. Reject incompatible combustion/turbine fields and unsupported electric configurations with useful messages.

Proposed raw blocks (final names decided with loader tests): `motor` for Kv, equivalent resistance and no-load current; `esc` for an explicit ideal motoring mode; `battery` for fixed terminal voltage; the existing `propeller` geometry/load block and thrust offset. Every numeric entry retains `{value, unit, kind, source}`. State exactly whether resistance includes controller/wiring losses; never count the same loss twice. Keep rated battery capacity and ESC rating as reference metadata until the implemented law actually consumes them. Do not require a fake glow idle RPM, power curve, combustion lag or friction table.

Use the loaded `rotor_inertia` for propeller + spinner + motor rotor, separate from aircraft locked inertia. Require positive carrier inertia after rotor subtraction. Begin with `+1` rotor sense and direct drive; reject unsupported reverse/geared configurations rather than assuming the existing coupling handles them. A future gearing step must reflect speed, torque and inertia consistently. Multiple independent configurations must coexist without modifying a global singleton or branching on aircraft name.

### EL1c–d: shared loads, trim and continuous state

| Current seam | Planned change | Required proof |
| --- | --- | --- |
| `propulsion.gd`: `engine_torque`, `shaft_rate`, `steady_rpm`, `has_shaft` | Add a small source-kind dispatch. Separate source capability from the combustion `shaft.power_curve` layout. Reuse propeller loads and axis. | Old glow/turbine results byte-identical; no implicit electric-to-glow fallthrough. |
| `steady_rpm` and `trim.gd` | Electric bracket from source/prop bounds, finite torque residual, explicit failed/unbracketed result; use same source as flight | Synthetic analytic static equilibrium; powered in-air trim; no false root at the stopped-prop cutoff. No-load Kv×V alone is not loaded RPM. |
| `flight_session.gd`: `_supports_coupled_shaft`, `_coupled_response`, `_pre_step` | Select coupled integration for electric; remove combustion-friction assumptions from source-off evaluation | No electric split-Euler path or frozen RK-stage RPM. Explicit incompatible integrator selection fails. Existing default fleet modes unchanged. |
| `simulation.gd` and continuous callbacks | Keep stage evaluation pure; integrate source/prop/body together and commit accepted RPM to `aux[AUX_RPM]` | Stage-local air velocity and density, accepted-endpoint render/audio/trace RPM; whole-state rollback on faults. |
| `rotor_coupling.gd`, `dynamics.gd` | Reuse signed-axis/locked-inertia contract within its supported sense | Independent momentum and energy checks, tilted axis, source-off behavior; no duplicate stator reaction. |
| `flight_session.gd` checkpoint/metadata, `trace.gd` | Declare electric identity, source/configuration, integrator and state layout; expose electrical telemetry at one defined sample time | Fresh-session replay, cross-kind/config mismatch rejection, no old readers interpreting an electric drive as combustion shaft balance. |

The existing v4 checkpoint and weather routes require a version/reader audit before extension; do not simply add fields to a historical layout. Electrical telemetry must identify whether it describes the accepted endpoint or the previous-state load sample. Preserve existing CSV readers until a versioned extension has negative-control tests. Fixed-voltage EL1 needs no SOC state; EL2 must add all continuous battery states to checkpoints, rollback, hashes and replay together.

Kv×voltage is an electrical no-load reference, not a mechanical overspeed governor. A propeller driven by the airflow may exceed it while the motoring-only source draws zero current. Define the permitted propeller operating range and root bracket explicitly; do not clamp shaft speed to Kv×voltage or mistake a clamped endpoint for equilibrium.

Treat stopping as a specific numerical step: constant loss near zero can produce negative intermediate RK states. Establish event location or a declared convergence-tested low-speed regularization before flight integration. Do not hide the error with unconditional stage clamping. Test restart from rest, small duty below breakaway, zero-duty deceleration and a throttle chop at several timesteps. The existing propeller cutoff cannot restart a prop from air; stopped-prop drag and windmilling acceptance still depend on G1d. This plan does not promise a physically correct dead-stick glide before that evidence exists.

### EL1e–f: aircraft and product boundary

Input arming remains in the shared radio path. An armed electric command of zero means no applied motor voltage, unlike a glow idle. Audit boot with throttle high, arming at low, unplug/reconnect, keyboard source selection, pause, restart and engine/source-off modes through the real session. Pause must freeze RPM and future battery state; restart explicitly creates the selected initial powertrain state.

Exercise two synthetic configurations (e.g. 800 Kv/4S and 400 Kv/6S) through the same loader/trim/session route before any model-specific tuning. Preserve reference prop provenance and aircraft mass/CG/inertia; an electric Stik conversion needs its own loadout data, not only a renamed engine. Timber TT-07 supplies its dataset; TT-08 connects it, TT-09 proves isolated flight and TT-10 enables the catalog entry. TT-12 owns motor/prop sound and visual stop behavior. Do not make a generic combustion buzz the acceptance reference for electric audio.

Catalog enablement follows the existing model/menu process, including negative tests for unready data. Export proof must load the new model/data from a clean package. Flaps, slats, floats, water, SAFE/AS3X imitation, thrust reverse, gearboxes and multi-motor aircraft are independent future capabilities.

## Battery and ESC growth

EL2a first adds only `OCV(SOC)`, pack resistance and coulomb-counted SOC. For ideal duty conversion with positive motoring current:

`Im = (d OCV − E)/(Rm + d² Rpack)`, `Ibus = d Im`, `Vbus = OCV − Rpack Ibus`.

The `d²` term follows from both voltage conversion and bus current; replacing it with `d` or using motor current directly for SOC is wrong. Clamp the current branch only under the declared no-regeneration policy. The source kernel can consume this solved terminal voltage. Then `dSOC/dt = −Ibus/(3600 Capacity_Ah)`. Pack configuration keeps mass constant during discharge.

EL2b adds a polarization RC branch only with identifiable data: `dVp/dt = Ibus/C1 − Vp/(R1 C1)` and `OCV` above becomes `OCV−Vp`. Use battery pulse tests with known temperature, state and uncertainty. Never transfer another pack's fitted coefficients as Timber measurements. Empty/overdrawn states need transactional failure or explicit cutoff events, not silent SOC clipping.

EL3 adds a per-ESC state machine for ramp, signal loss, low-voltage cutoff, recovery/hysteresis and optional braking. Sample discrete transitions on a documented boundary; include timers/modes in reset/replay. Manufacturer settings are configuration-specific: Hobbywing behavior is a separate preset, not Spektrum firmware. A measured brake requires a matching motor/propeller law and G1d, and does not imply battery regeneration. EL4 adds thermal winding resistance and ESC derating only after electrical energy/loss accounting is established.

## Steps and acceptance

| ID | Delivery | Dependencies | Proof | Status (date) |
| --- | --- | --- | --- | --- |
| EL1a | Pure three-constant source, ideal motoring ESC, fixed bus; research and integration plan | Existing EL scope | [1,057 focused checks, four isolated mutations, existing app regression and import](research/propulsion/EL1a/README.md); hand arithmetic, energy accounting, analytic transient, prop/coupling probes | Complete — software only (2026-10-10) |
| EL1b | Provenance-complete `electric_prop` loader/schema and two synthetic configurations | EL1a | Missing/unknown/unit/nonfinite/overflow failures; normalization parity; all old aircraft unchanged | Planned |
| EL1c | Shared electric source dispatch and steady operating-point/trim support | EL1b, G1 prop support | Residual and bracket checks; independent quadratic fixture; density affects prop load, not motor constants | Planned |
| EL1d | Coupled session, zero-speed transition, checkpoints and telemetry | EL1c, H8/G2a/G2b | Momentum/work, 120/240/480/960 Hz refinement, exact restart/replay, rollback, defined electrical sampling; cost report | Planned |
| EL1e | Synthetic experimental electric airframe integration | EL1d, data/input owners | Own configuration and trim, 30 s level/turn/climb/throttle-chop traces; pause/reset/high-throttle arming; 30/60/144 fps inputs | Planned |
| EL1f | Timber reference configuration and model handoff | EL1e, TT-07–09 | Motor/prop evidence matrix, uncertainty sweeps, finite flight envelope; TT-10/12/17 retain catalog/audio/package work | Planned |
| EL2a | OCV, sag and SOC | EL1d, identified battery data | Algebraic duty² sag oracle, charge/energy budget, exhaustion events, full-state replay | Planned |
| EL2b | One RC polarization pair | EL2a and residual need | Identified pulse/recovery trace; timestep refinement and battery-state rollback | Planned |
| EL3 | Per-ESC ramp, LVC, signal loss, brake/freewheel modes | EL2a for LVC; G1d for glide claims | Unit and session checks per mode, hysteresis/no chatter, explicit brake energy destination | Planned |
| EL4 | Winding/ESC temperature and derating | EL2/3 and thermal data | Sustained-power response and loss-energy balance against reference | Deferred |
| EL5 | Independent static and transient powertrain validation | Matched motor/ESC/pack/prop measurements | Current and thrust within ROADMAP target ±10%, also RPM/torque residuals; uncertainty and held-out points | Planned |
| EL6 | Endurance validation | EL2/3, recorded pack/flight telemetry | ROADMAP target ±15% flight time; matched loadout, duty, usable capacity and cutoff; held-out flights | Planned |

EL1 is complete only after its integration and flight proofs. EL1a numerical verification alone does not close it. Promotion remains experimental until independent physical evidence and pilot acceptance exist. Use one bounded change per substep, preserve old goldens, and do not tune against the same observations reserved for EL5/6 acceptance.

Before declaring the integrated path ready, measure whole-session cost with the existing 500 µs/tick target and report the source's incremental cost separately. A microbenchmark cannot close Gate P. If high-Kv/low-inertia configurations are stiff at 240 Hz, first bound the supported parameter envelope from timestep evidence; introduce substepping/implicit coupling only as a separately verified change.

**Next step:** EL1b, the electric loader/schema and two synthetic configurations. Obtain the motor's equivalent R/I0, rotor inertia and matched stock-prop thrust/torque data alongside code integration. No real Timber parameter is supplied by the synthetic fixtures.
