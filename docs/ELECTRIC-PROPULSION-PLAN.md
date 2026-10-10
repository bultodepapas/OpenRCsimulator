# Reusable electric propulsion

2026-10-10 · Revision 2 · Step prefix: **EL** (existing ROADMAP M4b namespace)

**Status: EL1a source kernel software verified; electric aircraft integration remains planned.**

Main-line physics subplan, selected by the owner on 2026-10-10. Owns `app/physics/electric_motor.gd`, electric tests, `research/propulsion/el*/` and `docs/research/propulsion/EL*/`; future loader, propulsion, trim, session and trace edits remain main-line work. Aircraft geometry/data, catalog, input and audio changes follow their owners. Research: [EL1a evidence](research/propulsion/EL1a/README.md), [primary sources](research/propulsion/EL1a/sources.md), [Timber reference](research/propulsion/EL1a/timber-reference.md). Related: [coupled shaft](PROPULSION-CORE-PLAN.md), [Timber](TIMBER-INTEGRATION-PLAN.md), [atmosphere](ATMOSPHERE-PLAN.md), [main roadmap](../ROADMAP.md).

Revision 2 incorporates [twelve targeted Internet investigations, EL1a-R1](research/propulsion/EL1a-R1/README.md). They tighten parameter provenance, ESC behavior, battery/load boundaries, propeller coverage, event handling and physical acceptance. This revision changes the plan and research only; it does not extend the verified EL1a implementation.

## Outcome and first configuration

One data-driven motor/ESC/battery chain must serve several direct-drive, single-propeller aircraft without aircraft IDs in physics. Keep propeller aerodynamics, motor torque, electrical supply and pilot/ESC control separate. Reuse the float64 flight solver and G2a/G2b rotor coupling. Electric work does not require completion of nitro failures, fuel burn or sound propagation.

Use the currently sold **E-flite Turbo Timber Evolution BNF Basic B, EFL105250B**, with a **4S 3200 mAh pack class**, as the reference selected after the owner delegated configuration choice. This is not a sales-popularity claim or confirmation of the incoming mesh's hardware revision. The B reference has an 800 Kv motor, 70 A ESC and stock three-blade 11×7.3 propeller. Manufacturer data establishes these labels, not winding resistance, loaded voltage, motor losses or propeller performance. The exact pack SKU/condition and its mass/position need their own evidence. [Revision and source matrix](research/propulsion/EL1a/timber-reference.md)

First flight target: fixed, explicitly prescribed bus voltage; wheels fitted, flaps up, slats off; direct drive, brake off, forward motoring, no receiver assistance; trimmed in-air start. Real BNF observations must identify AS3X as well as SAFE: disabling SAFE alone does not establish an unaided reference. A synthetic electric test airframe can exercise integration before Timber data is ready; it must not be labeled a validated Timber or silently registered over the nitro Stik.

“Brake off” is a simulator baseline until the installed SPMXAE70E's firmware/settings are read back. The generic Avian programming guide omits this exact 70 A model from its per-model tables; it does not establish all available modes or defaults. [Investigation 03](research/propulsion/EL1a-R1/01-motor-esc.md)

## Physical contract

| Piece | Initial rule | Evidence and boundary |
| --- | --- | --- |
| Motor | `kt = 60/(2π Kv_rpm/V)`, `E = rpm/Kv`, `I = max((d Vbus − E)/R, 0)`, `Qsource = kt (I − I0)` while rotating | Drela DC-equivalent three-constant model; positive rotation only. Equivalent current is not measured phase RMS current. |
| ESC | Effective duty `d` in `[0,1]`; ideal averaged conversion `Ibus = d I`; zero duty/disabled disconnects | Motoring-only approximation, no switching loss, active braking or regenerative path. Actual commercial switching topology is a later measured choice. |
| Mechanical loss | Coast retains `−kt I0`; at exact rest friction opposes only available torque, never starts reverse spin | Explicit Coulomb-loss extension of the model, not a measured low-speed/cogging law. Negative-speed input is refused. |
| Battery EL1 | Prescribed terminal voltage, no state or depletion | Nominal 14.8 V and charged 16.8 V are different operating assumptions. Neither establishes loaded pack voltage. No endurance claim. |
| Propeller | Existing `Ct/Cp`, stage RPM, axial air-relative velocity and field density | Shared load path. No stock three-blade map inferred from Kv, pitch or the Stik's two-blade data. |
| Rotor/body | Existing locked-inertia simultaneous solve | Source torque is internal. External propeller torque, relative-spin reaction and gyro momentum enter exactly once. |

The kernel returns source torque, equivalent motor/drive-input current, command/actual terminal voltage, mode and power accounting. Its battery-current output equals total pack current only when auxiliary loads are absent. `Pbus = Pshaft + Pcopper + Protational` describes this ideal drive port; coast can have negative shaft power with zero drive-input current. At open circuit the motor terminal voltage is its back EMF, even when command voltage is zero. An ESC's nameplate current rating is not automatically an implemented current clamp. High synthetic startup current must remain visible until a justified startup/current-limiting model exists.

Invalid types, nonfinite values, negative RPM/voltage, duty outside `[0,1]`, nonpositive Kv/R, negative I0 or arithmetic overflow return failure. No fallback to a glow law. EL1a is a stateless source; it does not advance RPM, arm hardware, handle a propeller or own simulation time.

## Data and runtime integration

### EL1b: schema and a normalized model

Add an explicit `electric_prop` branch to both `aircraft_data.gd` and `openrc-aircraft-v1.schema.json`; keep all existing branches and raw file identities unchanged. Validate the raw block before deriving a normalized model. Reject incompatible combustion/turbine fields and unsupported electric configurations with useful messages.

Proposed raw blocks (final names decided with loader tests): `motor` for Kv, equivalent resistance and no-load current; `esc` for an explicit ideal motoring mode; `battery` for fixed terminal voltage; the existing `propeller` geometry/load block and thrust offset. Every numeric entry retains `{value, unit, kind, source}`. State exactly whether resistance includes controller/wiring losses; never count the same loss twice. Keep rated battery capacity and ESC rating as reference metadata until the implemented law actually consumes them. Do not require a fake glow idle RPM, power curve, combustion lag or friction table.

The measurement manifest records winding connection, line/phase and RMS/peak conventions, temperature, identification method and validity range for Kv/R/I0. Nameplate Kv, phase-pair resistance and bus no-load current do not automatically form a consistent equivalent-port fit. Store I0's voltage/RPM/temperature context; constant I0 is a declared approximation. Keep pilot command, receiver signal and effective motor-port duty distinct. EL1's command-to-duty identity must be explicitly selected as an ideal mapping, with no claim that it matches Avian firmware. [Investigations 01–02](research/propulsion/EL1a-R1/01-motor-esc.md)

Use the loaded `rotor_inertia` for propeller + spinner + motor rotor, separate from aircraft locked inertia. Require positive carrier inertia after rotor subtraction. Begin with `+1` rotor sense and direct drive; reject unsupported reverse/geared configurations rather than assuming the existing coupling handles them. A future gearing step must reflect speed, torque and inertia consistently. Multiple independent configurations must coexist without modifying a global singleton or branching on aircraft name.

### EL1c–d: shared loads, trim and continuous state

| Current seam | Planned change | Required proof |
| --- | --- | --- |
| `propulsion.gd`: `engine_torque`, `shaft_rate`, `steady_rpm`, `has_shaft` | Add a small source-kind dispatch. Separate source capability from the combustion `shaft.power_curve` layout. Reuse propeller loads and axis. | Old glow/turbine results byte-identical; no implicit electric-to-glow fallthrough. |
| `steady_rpm` and `trim.gd` | Electric bracket from source/prop bounds, finite torque residual and branch-stability check; explicit failed/unbracketed/unstable result; use same source as flight | Synthetic analytic static equilibrium and unstable-root negative control; powered in-air trim; no false root at the stopped-prop cutoff. No-load Kv×V alone is not loaded RPM. |
| `flight_session.gd`: `_supports_coupled_shaft`, `_coupled_response`, `_pre_step` | Select coupled integration for electric; remove combustion-friction assumptions from source-off evaluation | No electric split-Euler path or frozen RK-stage RPM. Explicit incompatible integrator selection fails. Existing default fleet modes unchanged. |
| `simulation.gd` and continuous callbacks | Keep stage evaluation pure; integrate source/prop/body together and commit accepted RPM to `aux[AUX_RPM]` | Stage-local air velocity and density, accepted-endpoint render/audio/trace RPM; whole-state rollback on faults. |
| `rotor_coupling.gd`, `dynamics.gd` | Reuse signed-axis/locked-inertia contract within its supported sense | Independent momentum and energy checks, tilted axis, source-off behavior; no duplicate stator reaction. |
| `flight_session.gd` checkpoint/metadata, `trace.gd` | Declare electric identity, source/configuration, integrator and state layout; expose electrical telemetry at one defined sample time | Fresh-session replay, cross-kind/config mismatch rejection, no old readers interpreting an electric drive as combustion shaft balance. |

The existing v4 checkpoint and weather routes require a version/reader audit before extension; do not simply add fields to a historical layout. Electrical telemetry must identify whether it describes the accepted endpoint or the previous-state load sample. Preserve existing CSV readers until a versioned extension has negative-control tests. Fixed-voltage EL1 needs no SOC state; EL2 must add all continuous battery states to checkpoints, rollback, hashes and replay together.

Kv×voltage is an electrical no-load reference, not a mechanical overspeed governor. A propeller driven by the airflow may exceed it while the motoring-only source draws zero current. Define the permitted propeller operating range and root bracket explicitly; do not clamp shaft speed to Kv×voltage or mistake a clamped endpoint for equilibrium.

Treat stopping as a specific numerical step: constant loss near zero can produce negative intermediate RK states. Establish event location or a declared convergence-tested low-speed regularization before flight integration. Do not hide the error with unconditional stage clamping. Test restart from rest, small duty below breakaway, zero-duty deceleration and a throttle chop at several timesteps. The existing propeller cutoff cannot restart a prop from air; stopped-prop drag and windmilling acceptance still depend on G1d. This plan does not promise a physically correct dead-stick glide before that evidence exists.

Specify event direction, trial-state domain and deterministic ordering when a continuous stop/exhaustion crossing meets a command or ESC sample boundary. A negative-RPM-refusing source needs a documented event-localization strategy, not an undefined trial callback. Keep continuous crossings separate from sampled ESC decisions; save the sampled controller's timers and sampling phase in replay. Check event-time convergence independently of smooth-trajectory order. A steady torque zero also needs a stable branch: the fixed-body scalar fixture uses `(dQsource/domega - dQprop/domega)/Jrot < 0`; this is not a whole-aircraft stability proof. [Investigation 10](research/propulsion/EL1a-R1/04-numerics-telemetry-uncertainty.md)

### EL1e–f: aircraft and product boundary

Input arming remains in the shared radio path. An armed electric command of zero means no applied motor voltage, unlike a glow idle. Audit boot with throttle high, arming at low, unplug/reconnect, keyboard source selection, pause, restart and engine/source-off modes through the real session. Pause must freeze RPM and future battery state; restart explicitly creates the selected initial powertrain state.

Exercise two synthetic configurations (e.g. 800 Kv/4S and 400 Kv/6S) through the same loader/trim/session route before any model-specific tuning. Preserve reference prop provenance and aircraft mass/CG/inertia; an electric Stik conversion needs its own loadout data, not only a renamed engine. Timber TT-07 supplies its dataset; TT-08 connects it, TT-09 proves isolated flight and TT-10 enables the catalog entry. TT-12 owns motor/prop sound and visual stop behavior. Do not make a generic combustion buzz the acceptance reference for electric audio.

Catalog enablement follows the existing model/menu process, including negative tests for unready data. Export proof must load the new model/data from a clean package. Flaps, slats, floats, water, SAFE/AS3X imitation, thrust reverse, gearboxes and multi-motor aircraft are independent future capabilities.

## Battery and ESC growth

EL2a first adds only `OCV(SOC)`, pack resistance and coulomb-counted SOC, for a declared balanced-pack operating envelope. For ideal duty conversion with positive motoring current and no auxiliary loads:

`Im = (d OCV − E)/(Rm + d² Rpack)`, `Ibus = d Im`, `Vbus = OCV − Rpack Ibus`.

The `d²` term follows from both voltage conversion and bus current; replacing it with `d` or using motor current directly for SOC is wrong. Clamp the current branch only under the declared no-regeneration policy. The source kernel can consume this solved terminal voltage. Then `dSOC/dt = −Ipack/(3600 Capacity_Ah)`, with `Ipack = Ibus` in this no-auxiliary case. Pack configuration keeps mass constant during discharge.

Define the auxiliary-load boundary before EL2a: BEC/receiver/servo draw is either explicitly omitted with a motor-only endurance label or measured at the pack side and included in both sag and SOC. Motor-only endurance does not close whole-aircraft EL6. For a prescribed pack-side auxiliary current `Iaux`, the derived positive-current branch is `Im = (d (OCV − Rpack Iaux) − E)/(Rm + d² Rpack)` and `Ipack = d Im + Iaux`. BEC output current at a different voltage cannot be added directly to pack current. Record charge `integral(Ipack dt)` and energy `integral(Vbus Ipack dt)` separately. Capacity and C-rating do not determine usable Wh, resistance or endurance. An aggregate pack model cannot establish weakest-cell protection. [Investigations 05–06](research/propulsion/EL1a-R1/02-battery.md)

EL2b adds a polarization RC branch only with identifiable data: `dVp/dt = Ipack/C1 − Vp/(R1 C1)` and `OCV` above becomes `OCV−Vp`. Use battery pulse tests with known temperature, state and uncertainty. Never transfer another pack's fitted coefficients as Timber measurements. Empty/overdrawn states or an infeasible bus operating point need transactional failure or explicit cutoff events, not silent SOC/voltage clipping.

Promote zero-RC to one-RC only when pulse/recovery residuals exceed measurement uncertainty and identified parameters predict held-out traces. Characterize temperature/SOC/current limits first; add a second RC branch, hysteresis or thermal state only if those residuals justify it. Existing UAV papers use different packs and test envelopes, including partial/low-rate discharge; their reported accuracy does not validate a 4S Timber powertrain. [Investigation 04](research/propulsion/EL1a-R1/02-battery.md)

EL3 adds a per-ESC state machine for ramp, signal loss, low-voltage cutoff, recovery/hysteresis and optional braking. Sample discrete transitions on a documented boundary; include timers/modes in reset/replay. Manufacturer settings are configuration-specific: Hobbywing behavior is a separate preset, not Spektrum firmware. A measured brake requires a matching motor/propeller law and G1d, and does not imply battery regeneration. EL4 adds thermal winding resistance and ESC derating only after electrical energy/loss accounting is established.

The Timber manual establishes soft LVC, but its transmitter alarm setting does not establish the ESC trip threshold. Determine the exact unit's voltage observable, cell-count configuration, delay, output reduction and recovery; do not copy ambiguous family percentages or thresholds. Treat receiver-rail/BEC behavior separately from propulsion cutoff. Likewise, open-circuit coast, active freewheeling, braking and reversal are distinct modes: none alone proves negative battery power. Do not add a generic RPM lag on top of coupled rotor inertia to fit unidentified ESC/measurement delay. [Investigations 02–03](research/propulsion/EL1a-R1/01-motor-esc.md), [06](research/propulsion/EL1a-R1/02-battery.md)

## Physical evidence and promotion

EL5/6 require a measurement protocol before fitting. Preserve raw files, exact hardware/firmware/settings, calibration, environmental conditions and the fit/validation split. Record the observation bandwidth and timestamp meaning alongside the model's state-time convention. The following requirements make the existing accuracy targets interpretable; they do not claim the measurements already exist.

Reuse [VAL-7a static reduction](research/validation/VAL-7a/README.md), [VAL-7c RPM-step diagnostics](research/validation/VAL-7c/README.md), and [G1a1/G1b1 propeller provenance and coverage](research/propulsion/G1b1/README.md) through explicit format extensions where needed. VAL-7c's independent-input uncertainty option does not cover arbitrary filtered/correlated telemetry. G1b1's historical v3 load-time reconstruction does not cover new electric endpoint telemetry or internal coupled stages automatically. Keep those limitations visible and add negative controls when extending the tools.

| Evidence | Required distinction | Acceptance consequence |
| --- | --- | --- |
| Motor/ESC identification | Equivalent-port conventions, fitted losses and actual command-to-duty response | No duplicated controller loss, fictitious current limit or double-counted shaft lag. |
| Battery characterization | Exact pack, total pack current, charge versus energy, cutoff and intended temperature/current range | Held-out endurance ends at the same operational event as the observation; omitted auxiliary loads remain explicit. |
| Propeller data | Measured versus computational source; exact blade count/geometry; RPM/Reynolds number and advance-ratio coverage | No two-blade/static-only table promoted to stock three-blade advancing flight; out-of-range and stopped/windmilling behavior reported separately. |
| Transient acquisition | Independent rotor inertia or independently constrained torque/acceleration; synchronized command, RPM, thrust, torque and electrical channels | A fitted response time cannot by itself identify motor inertia, ESC ramp, pack relaxation and sensor delay. Mount reaction and propeller aerodynamic torque differ during acceleration by rotor angular-momentum change; identify the sensor plane. |
| Telemetry | Electrical versus mechanical RPM, pole-pair/pulse scaling, current plane, cadence/filtering, measurement/receive timestamps, missing samples | Independent tachometer/current checks; no double pole correction or interpolation presented as extra bandwidth. Smart Avian timing is measured separately from BLHeli examples. |
| Uncertainty | Calibration, repeatability, shared-input covariance and parameter uncertainty distinct from model error | Ct/Cp from shared RPM/diameter/density are correlated; electrical input is not independent shaft-power evidence. |

Sources and concrete negative controls: [07–09](research/propulsion/EL1a-R1/03-propeller-validation.md), [11–12](research/propulsion/EL1a-R1/04-numerics-telemetry-uncertainty.md).

Keep ROADMAP's ±10% current/thrust and ±15% endurance limits. Predeclare operating bins, absolute floors near zero and RPM/torque/transient limits before fitting; reserve separate observations for validation. For residual `e`, its expanded uncertainty `Ue`, and allowed magnitude `L`, the project rule is: pass if `abs(e)+Ue <= L`; fail if `max(0,abs(e)-Ue) > L`; otherwise inconclusive. Propagate relative-residual uncertainty with shared inputs, report coverage assumptions and worst-bin results, and never enlarge sensor uncertainty to hide model discrepancy. This conservative decision rule is a project choice informed by NIST uncertainty methods, not a manufacturer or NIST acceptance requirement. [Investigation 12](research/propulsion/EL1a-R1/04-numerics-telemetry-uncertainty.md)

## Steps and acceptance

| ID | Delivery | Dependencies | Proof | Status (date) |
| --- | --- | --- | --- | --- |
| EL1a | Pure three-constant source, ideal motoring ESC, fixed bus; research and integration plan | Existing EL scope | [1,057 focused checks, four isolated mutations, existing app regression and import](research/propulsion/EL1a/README.md); hand arithmetic, energy accounting, analytic transient, prop/coupling probes | Complete — software only (2026-10-10) |
| EL1a-R1 | Twelve targeted investigations and plan revision | EL1a; owner research request | [Question/source/decision/test matrix](research/propulsion/EL1a-R1/README.md); source-scope cross-checks; documentation validation | Complete — research only (2026-10-10) |
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
