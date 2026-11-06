OpenRCsimulator developer audit and remediation handoff
Consolidated findings from both audit passes
Item	Audited baseline
Repository	bultodepapas/OpenRCsimulator
Commit	3df2791752fe2c1faad132fcb11febbb0ae788d1
Engine	Godot 4.8.beta2.official.cafc17a19, Linux headless/debug editor
Executed physics backend	GDScript reference backend
Normal physics rate	240 Hz; explicitly identified refinement experiments also used smaller outer steps
Handoff date	November 6, 2026
Scope	Runtime correctness, numerical behavior, physics, input state, statistics, recording, and performance
Change status	No production fix, repository edit, commit, or remote mutation was made by these audits


This document contains six confirmed defects, the performance opportunities identified in both passes, the evidence needed to reproduce them, proposed repair directions, and acceptance criteria. It preserves the original finding identifiers F1–F5 and assigns F6 to the second-pass truck-friction finding. Recommendations below are implementation proposals; the executed evidence establishes the baseline behavior described here.

The most urgent work is to prevent an admitted Workshop model from faulting on its first tick, preserve bound flap/gear requests through ordinary pause/resume, and correct a truck contact law that can supply mechanical energy through friction. The strongest measured optimization removes a duplicate airflow calculation from the aircraft downwash pre-step.

All source links are pinned to the audited commit. Establish the corresponding behavior on the current development branch before applying a change; this handoff does not assert that later commits still contain every issue.
Contents
- Executive triage
- Evidence packages and interpretation
- F1 — Qualified Workshop aircraft cannot advance its first runway tick
- F2 — Pause changes bound flap and gear requests
- F3 — Statistics omit RC-track support terrain
- F4 — A sub-ULP epsilon breaks the connected glow-fuel trial
- F5 — Empty continuous-state logs fail their own reader
- F6 — Truck tire friction and brake constraints can add energy
- Optimization opportunities
- Investigated behavior that is not a new defect
- Reproduction commands
- Implementation sequence and release evidence
- Evidence index
Executive triage
Priorities are engineering recommendations, not existing upstream labels. P1 means repair before relying on the affected path; P2 is an observable correctness defect; P3 is a limited numerical or tooling defect. The F6 P1 recommendation concerns physics correctness and energy accounting, rather than a demonstrated application crash.
ID	Priority	Finding	Strongest executed evidence	Suggested owning area
F1	P1	Workshop admission and start qualification accept a glow aircraft whose contact subdivision conflicts with its whole-tick policy	Trial.freeze and runway qualification pass; the first step faults at tick 0	Workshop, aircraft admission, glow event stepping, shared kernel
F2	P1	Ordinary pause/resume changes bound flap/gear targets with unchanged transmitter-switch values	Production session changes flaps 1 → 0 and gear target up → down between ticks 2 and 3	RC input and flight-session command handling
F6	P1	Tire friction can supply mechanical energy; the brake constraint has the same sign defect	Stock energy balance plus a from-rest drive/brake/drive sequence reaching +168.8 W of tire-contact power	Ground-vehicle reference and native contact solvers
F3	P2	Statistics reject wheel support on raised circuit terrain that physics recognizes	Positive physical wheel compressions versus observer [-1, -1, -1]	Statistics adapter and composed terrain service
F4	P3	reserve + 1e-30 rounds to reserve, invalidating the intended connected exhaustion trial	Binary64 proof and approximately 0.23–0.89 ms production/diagnostic event-time differences	Glow lifecycle and event localization
F5	P3	A legal empty continuous block is represented inconsistently by snapshot, logger and reader	File is reported saved; inspection rejects its initial sample	Simulation snapshot and flight-log format handling


Performance work has different evidence levels:
ID	Opportunity	Evidence status
O1	Qualify circuit terrain for native execution	Source-established admission/fallback behavior; no measured speedup
O2	Apply native admission to eligible companion sessions	Source-established routing and tick multiplication; no measured speedup
O3	Reuse a prepared hull-reach bound	Source-derived operation count; no measured speedup
O4	Reuse air data inside the downwash pre-step	Exact-output and refusal comparisons; measured callback reduction of approximately 42% in the spatial-weather workload
O5	Prepare invariant spatial-wind station geometry	Promising prototype; an explicit stale-model counterexample requires an invalidation design
O6	Share repeated rotor-domain calculations within a stage	Overlapping calculations and component cost identified; no measured candidate speedup


Evidence packages and interpretation
Forward these archives alongside this Markdown file. They contain the executable probes and receipts; the audit wrappers are external evidence tools, not files already committed to OpenRCsimulator.
Package	Contents
OpenRCsimulator-audit-3df2791.zip	First-pass report; F1–F5 probes; checked original and packaged runs; source manifest; run_audit.py
OpenRCsimulator-math-audit-3df2791.zip	F6 probes; full truck traces; O4 candidate patch and comparisons; additional numerical checks; checked reconstruction; run_audit.py


This Markdown contains the complete findings for review. Use the saved-file links above to retrieve the archives, then supply the actual ZIP files to the developer for reproduction. Extract both beside this document to make the relative probe and result links below usable. Each archive contains its own correspondingly named top-level directory.

The baseline implementation, data and resource files used in the isolated projects were checked against the audited source bytes. The delivered wrappers verify the exact engine version and a 654-file application manifest before creating an isolated runtime. The first wrapper additionally copies three Workshop authoring JSON dependencies in the required adjacent-assets layout. The original performance harness used 226 matching tracked GDScript files and a smaller project; its separate manifest is retained.

The projects intentionally use reduced project.godot configurations and generated import/UID metadata. No native extension was loaded. Godot runs were checked through the repository's tools/godot/run_checked.py, so a process exit of zero with script/parse errors did not count as a successful reproduction. First-pass logs retain existing aircraft-model warnings and the expected calibration-overlap warning where applicable; these are not additional findings.

A successful counterexample is not a passing product regression. The F1, F2, F3, F5 and F6 probes succeed when the old defect is reproduced. Convert the observation into an assertion of the desired behavior when implementing a fix. F4 is a diagnostic comparison, not an independent physical oracle. O4 is an experimental equivalence/performance comparison, not a shipped optimization.
F1 — Qualified Workshop aircraft cannot advance its first runway tick
Priority: P1. Status: reproduced through production freeze, qualification and session code.
Expected and observed behavior
An aircraft/start combination accepted by Workshop should either advance under its admitted stepping contract or be rejected before flight with a specific incompatibility reason. The tested combination passes admission and runway qualification, then immediately pauses with a step-policy fault.

Start with the stock GP Extra 300S .60 and create a Workshop draft with these component masses:
Component	Value	Provenance field
engine_main	0.311 kg	source = "measurement"
wing_main	0.270 kg	source = "measurement"
fuselage_rear	0.089 kg	source = "measurement"


These are synthetic counterexample inputs admitted by the schema, not claimed measurements of the real aircraft.

The executed sequence was:
1. Submit the draft through production Trial.freeze, including default presentation.
2. Observe derived mass 3.0795476 kg and landing_gear.substeps = 2.
3. Run the production Workshop start qualifier for the Club-field runway. It reports the start available and converged.
4. Load the exact frozen aircraft into a new FlightSession, use the product cruise trim of 0.5, and obtain a converged runway reset.
5. Call the first sim.step().
Observed result:
tick = 0
paused = true
fault = "step rejected: the step policy owns the tick and cannot honour 2 contact substeps"
Evidence: [Workshop probe](OpenRCsimulator-audit-3df2791/probes/workshop_freeze_repro.gd) and [original checked receipt](OpenRCsimulator-audit-3df2791/evidence/original/workshop/report.json).
Root cause and numerical contract
The gear loader derives a subdivision count from a spring-frequency accuracy condition. With stiffness \(k\), mass \(m\), and tick duration \(h=1/240\) s:
\[
\omega=\sqrt{\frac{k}{m}},\qquad \frac{\omega h}{n}<0.1.
\]
Reducing an otherwise valid mass can increase the necessary subdivision count \(n\). The glow propulsion runtime installs a whole-tick step_policy for fuel/source events. Near contact, FlightSession requests the gear-derived count, but Simulation rejects a whole-tick policy combined with more than one contact substep.

The start qualifier proves that reset converges; it does not establish that the first integration step can execute. The defect is in the composition of those contracts.

Relevant source:
- Gear subdivision derivation.
- Glow step-policy installation.
- Session contact-substep request.
- Shared-kernel rejection.
- Start qualification.
Repair direction and acceptance criteria
Immediate containment can reject this incompatible policy/contact combination during aircraft or start admission. The complete repair should compose glow event segments with the contact maximum-step requirement, while retaining one atomic accepted tick.

Do not remove the guard or silently clamp the gear subdivision to one: that discards the condition that requested the smaller step.
- [ ] The exact Workshop recipe either receives an explicit admission rejection or advances its first runway tick without the policy fault.
- [ ] Qualification exercises the relevant stepping contract, not only reset convergence.
- [ ] Contact becoming reachable during an airborne start is covered.
- [ ] Fuel/source events inside subdivided contact ticks have correct ordering and timestamps.
- [ ] Rejected stages roll back body state, continuous state, auxiliary state, modes and sampled state consistently.
- [ ] Composition does not repeat pre-tick input sampling, AUX/RNG updates or publication for each event/contact segment.
- [ ] Any admitted native configuration receives corresponding parity checks.
Scope: checked stock catalog glow aircraft derived one substep. The audit does not establish a general stock-glow startup failure. A later landing can encounter the same source-level incompatibility, but that airborne-to-contact trajectory was not executed. The rejecting guard is shared kernel code; native execution was not tested.
F2 — Pause changes bound flap and gear requests
Priority: P1. Status: reproduced through the production RC-input/session boundary.
Reproduction and observed state
Use the stock Avanti and a synthetic EdgeTX-style controller. Bind flaps to axis 4 and gear to axis 5. Send fresh low/off events to arm both channels, then move both axes to +1 and advance accepted ticks. Hold the session with pause_menu, sample input while held, release the hold, resume, and advance with both axes still at +1.
Quantity	Before pause	After resume
Accepted tick	2	3
Flap request	1.0	0.0
Gear target down	false	true
Flap axis	+1	+1
Gear axis	+1	+1


The resumed session is unpaused. The defect changes the requested actuator configuration; it does not make the physical actuators complete their travel instantaneously.

Evidence: [AUX pause probe](OpenRCsimulator-audit-3df2791/probes/aux_pause_probe.gd) and [checked receipt](OpenRCsimulator-audit-3df2791/evidence/original/aux_pause/report.json).
Root cause
FlightSession.hold() disables auxiliary input. Reconfiguring the shared auxiliary machinery clears arming evidence and resets smoke, flap and gear values. Fresh off evidence is required before a bound channel is armed again. A switch that stays high across the pause does not provide that evidence.

On resume, the session treats the unarmed channel's zero amount as a valid position request. Two distinct meanings have collapsed into the same scalar:
No valid new command is available.
The pilot commanded zero.
The first becomes an unintended flap-retract/gear-down command.

Relevant source: hold handling, AUX reconfiguration, bound amount, session consumption, and existing AUX tests.
Repair direction and acceptance criteria
Represent validity/readiness separately from amount, or preserve the last accepted actuator requests through ordinary pause. An unarmed position channel should not silently overwrite a valid flap/gear target. Smoke can still turn off immediately under its separate pump semantics.
- [ ] Unchanged high switches retain accepted flap/gear targets through an ordinary pause/resume cycle.
- [ ] Test each flap stage and both gear states, including axis and button bindings.
- [ ] Test pause, menu and focus transitions at the session boundary.
- [ ] Fresh off/on rearming and subsequent deliberate commands still work.
- [ ] Requested targets and accepted physical actuator continuity are both checked.
- [ ] Disconnect, calibration, focus and throttle-admission policies remain explicit and deliberate.
Scope: the reproduction uses a synthetic controller and bound AUX channels. It does not establish a hardware-transmitter result or the same defect for unbound keyboard/semantic toggles.
F3 — Statistics omit RC-track support terrain
Priority: P2. Status: reproduced geometric disagreement between physics and the statistics adapter.
Reproduction and observations
Place the default Stik level at NED position [39, -4, -0.755] on the default Club field with its default circuit. The sampled track height is 0.515 m and the aircraft's gear reach is 0.3505990400 m.
Observation	Result
Physical wheel compressions	[0.0119176434, 0.0128185565, 0.0145762139] m
Statistics adapter wheel values	[-1, -1, -1]
Statistics sample valid	true
supported, intended_support, stop_support	All false
clearance_ok	true


The landing profile is available, the gear is not collapsed, and a hull or propeller strike does not explain the result. A no-track control at the same elevated pose returns the expected negative wheel compressions.

Evidence: [track-statistics probe](OpenRCsimulator-audit-3df2791/probes/rc_track_statistics_probe.gd) and [checked receipt](OpenRCsimulator-audit-3df2791/evidence/original/track_statistics/report.json).
Root cause
The adapter's early rejection combines gear reach with the ordinary surface-table maximum height, omitting the track. It rejects the candidate because the aircraft's 0.755 m height exceeds the ordinary approximately 0.350599 m bound. A conservative bound that includes the 0.515 m raised track reaches approximately:
\[
0.3505990400+0.515=0.8655990400\ \mathrm{m}.
\]
That bound would retain the candidate for the actual wheel query. The observer also samples terrain without the track for clearance and orientation, so repairing only the early bound leaves another disagreement.

Relevant source: support/clearance adapter, wheel early rejection, composed environment terrain, and episode detector.
Repair direction and acceptance criteria
Use the same composed ground service and conservative maximum-height service as the physics. session.environment.ground() already composes field, lake and track, and ground_max_height() includes the track bound. Keep height, normal, clearance and support under the same terrain identity.
- [ ] The staged tabletop witness reports physical wheel support consistently.
- [ ] Ramps, track edges, ordinary field and lake cases agree with the physical terrain.
- [ ] Broadphase rejection never discards a contact admitted by the authoritative narrow query.
- [ ] Invalid samples and supported terrain mutations retain their intended behavior.
- [ ] A complete landing/takeoff sequence checks episode integration after the geometric repair.
Scope: this is a directly staged geometric sample, not a settled equilibrium or a complete landing episode. The detector consumes the wrong fields, so statistics are exposed to misclassification; a specific false landing count was not measured.
F4 — A sub-ULP epsilon breaks the connected glow-fuel trial
Priority: P3. Status: exact floating-point defect with an executed event-localization diagnostic.
Numerical mechanism
The no-feed-line glow path attempts to keep a trial connected to the main tank by evaluating fuel at:
reserve + 1e-30
The lifecycle regards fuel as available only when fuel_kg > reserve. For the tested positive reserve \(r=0.0042846\) kg, binary64 spacing is:
\[
\operatorname{ULP}(r)
=2^{\lfloor\log_2(r)\rfloor-52}
=2^{-60}
=8.673617379884035\times10^{-19}\ \mathrm{kg}.
\]
Because \(10^{-30}\) kg is far below half an ULP, floating-point addition gives:
\[
\operatorname{fl}(r+10^{-30})=r.
\]
The intended connected trial is therefore still on the disconnected boundary. Intermediate RK trials can stop combustion/fuel consumption before the event policy has localized and committed the crossing, changing the differential equation integrated by the root search.

Relevant source: glow connected trial, fuel-availability lifecycle, native expression, and existing endpoint check.
Executed comparison
Each case starts at reserve + 1e-7 kg. Production Glow.step was compared with a temporary derivative wrapper that keeps connected trial evaluations above reserve using reserve + 1e-12. The production files were unchanged.
Aircraft	Production event	Connected-trial diagnostic	Reported difference
Stik 55AX	1.763268 ms	0.877741 ms	0.885527 ms
Stik FS64V	1.373147 ms	1.144313 ms	0.228833 ms
Extra 300S	1.702545 ms	0.847247 ms	0.855298 ms


Displayed columns are independently rounded from the retained results. Initial-flow estimates were approximately 0.877320, 1.143693 and 0.847247 ms respectively. They support the causal diagnosis but do not constitute independently measured physical stopping times.

The approximately \(5\times10^{-13}\) s time_error_bound_s in the event record is a root-bracket tolerance. A narrow bracket does not guarantee event accuracy when the trajectory being bracketed uses the wrong connected-state law.

Evidence: [timing comparison](OpenRCsimulator-audit-3df2791/probes/glow_timing_comparison.gd) and [checked receipt](OpenRCsimulator-audit-3df2791/evidence/original/glow_timing/report.json).
Repair direction and acceptance criteria
Prefer an explicit connected-trial state carried through evaluation/lifecycle interfaces. If a numerical sentinel is retained, use the next representable float above reserve consistently in both implementations, and verify that downstream arithmetic does not erase it. The diagnostic 1e-12 substitution is not a qualified production fix.
- [ ] A positive reserve and its adjacent representable values select the intended lifecycle side.
- [ ] A constant-flow analytic reference checks event time independently.
- [ ] Tests check integrated force/torque and event timestamps, not only the final residual and stopped state.
- [ ] Native/reference event behavior is qualified after the change.
Scope: production still reaches reserve and emits the stop event. No application crash or visible handling consequence was established. The native expression was inspected, not executed. Keep this below the flight-blocking, command-state and energy-law defects in repair priority.
F5 — Empty continuous-state logs fail their own reader
Priority: P3. Status: reproduced valid-session record/inspect round-trip failure.
Reproduction and root cause
Use AircraftData.validate_and_derive on the stock Stik source through the supported in-memory path, before attaching the optional file-boundary wheel profile. This produces a valid session with an empty continuous block. Start FlightLog, record a tick, and save. The logger reports success, but FlightLogCli.inspect returns:
Initial sample disagrees with checkpoint: continuous
Simulation.checkpoint() omits continuous when it is empty. The logger's initial sample always includes an empty array. The reader requires the checkpoint key to exist, creating an absent-versus-empty disagreement for the optional block.

Relevant source: snapshot omission, sample construction, and reader comparison.

Evidence: [empty-block probe](OpenRCsimulator-audit-3df2791/probes/body_only_record.gd), [failure receipt](OpenRCsimulator-audit-3df2791/evidence/original/empty_log/report.json), and [catalog inventory receipt](OpenRCsimulator-audit-3df2791/evidence/original/catalog_inventory/report.json).
Repair direction and acceptance criteria
Make the versioned reader interpret a legally absent v1 continuous block as empty, or emit explicit empty blocks in new snapshots while preserving compatibility with existing legal files. A new format version is unnecessary if absence already denotes an empty optional block.
- [ ] A valid empty-block session passes record, inspect and replay.
- [ ] Legal absent-v1 and explicit-empty representations compare consistently.
- [ ] Nonempty blocks retain their exact comparisons and round-trip behavior.
- [ ] Malformed or incompatible nonempty data is still rejected.
Scope: every flyable catalog entry checked had a nonempty continuous block. The finding applies to admitted in-memory/body-only or compatible legacy-style sessions; general catalog recording failure was not established.
F6 — Truck tire friction and brake constraints can add energy
Priority: P1 for physics correctness. Status: algebraic proof, production-solver reproduction, stock-model energy balance, and a driven trajectory from rest.
Affected code and the missing invariant
The truck solves an acceleration-relaxation target and limits its forces/torques symmetrically. The magnitude constraint does not enforce nonpositive work.
- GDScript brake update, lines 1812–1824.
- GDScript tire update, lines 1835–1861.
- Mobility-metric force-circle projection.
- Native mirror, inspected only.
For the modeled nonelastic tangential contact against stationary ground, define slip at the actual contact point, including body translation/rotation, suspension motion and wheel rotation. The necessary passivity conditions are:
\[
P_{\mathrm{tire}}
=F_{\mathrm{long}}s_{\mathrm{long}}+F_{\mathrm{lat}}s_{\mathrm{lat}}\le0,
\qquad
P_{\mathrm{brake}}=Q_b\omega_{\mathrm{rel}}\le0.
\]
Here \(\omega_{\mathrm{rel}}\) is wheel spin relative to the body. At zero slip, static reactions may have either sign and perform zero instantaneous work. The tire energy stored by this implementation is normal compression energy; there is no tangential tire or brake elastic-energy state that can account for positive tangential work. See the energy contract and normal tire energy.
Algebraic counterexample
For the scalar flat-road example with a fixed tangent direction, let \(s\) be slip, \(a_{\mathrm{free}}\) the acceleration without the force being solved (including the row's non-force/bias contribution), \(W=JM^{-1}J^\mathsf{T}>0\) the mobility, and \(\tau>0\) the relaxation time. The contact acceleration satisfies:
\[
\dot s=a_{\mathrm{free}}+WF.
\]
The implemented target \(\dot s=-s/\tau\) requests:
\[
F=\frac{-s/\tau-a_{\mathrm{free}}}{W}.
\]
If \(s>0\) and \(a_{\mathrm{free}}<-s/\tau\), then \(F>0\) and \(Fs>0\). Other forces already reduce slip faster than the requested relaxation rate, and the solver adds force in the slip direction to enforce the slower target.

An executed minimal production-solver example uses an identity 14-by-14 generalized mass matrix, \(s=1\) m/s, \(a_{\mathrm{free}}=-2\) m/s², \(\tau=1\) s and a 10 N cap. It returns +1 N and +1 W after two sweeps. The corresponding brake-row example returns +1 N·m at +1 rad/s, also +1 W. The identity-matrix example isolates solver behavior; it is not a physical truck model.

Evidence: [asserted scalar reproduction](OpenRCsimulator-math-audit-3df2791/probes/ground_solver_passivity.gd) and [checked receipt](OpenRCsimulator-math-audit-3df2791/evidence/rotorcraft/ground-solver-passivity-asserted-f4_2ez0_/report.json).
Stock Bisonte energy balance
Initialize the unmodified default model on flat ground with mu = 0.9 and rolling = 1.0. Retain its initialized attitude/suspension. Set forward body speed to 5 m/s, all four relative wheel spins to 30 rad/s, throttle to 1, brake/steering to 0 and reverse to false. The tire radius is 0.1 m, so each longitudinal slip is:
\[
s=5-0.1(30)=+2\ \mathrm{m/s}.
\]
The accepted production solve returns approximately +10.96036 N per tire and exits after six sweeps. This witness does not depend on the known 128-sweep cap.
Mechanical contribution	Power
Motor input	+468.000000000 W
Rolling resistance	−5.683934337 W
Tire-contact power	+87.682882561 W
Predicted total mechanical-energy rate	+549.998948224 W


To verify that this is actual energy injection, evaluate the public state derivative \(\dot y\) and the production total-energy function:
\[
\frac{dE}{dt}\approx
\frac{E(y+\varepsilon\dot y)-E(y-\varepsilon\dot y)}{2\varepsilon}.
\]
For \(\varepsilon=10^{-4},10^{-5},10^{-6},10^{-7}\) s, the derivative agrees with 549.998948224 W to within \(6.3\times10^{-8}\) W, using the full-precision retained values. At this witness, body rate, suspension velocity and vertical velocity are zero. The energy function includes body, hub and axial-rotor kinetic energy, gravity and elastic terms; no omitted normal/suspension damping explains the excess.

The artificial contact power is approximately 18.7% of motor mechanical input at this instant. This is not a lap-average claim.

Evidence: [energy-balance probe](OpenRCsimulator-math-audit-3df2791/probes/truck_energy_balance.gd) and [energy log](OpenRCsimulator-math-audit-3df2791/evidence/contact/truck-energy-balance-y606076k/engine.log).
Reachability through ordinary driving
A separate test starts from VehicleDynamics.initialize() and advances through production VehicleDynamics.step() with the same stock model and flat road:
Time	Throttle	Brake
0.00–1.50 s	1	0
1.50–1.75 s	0	1
1.75–2.75 s	1	0
2.75–3.50 s	0	1


Steering remains zero, reverse remains false, and throttle/brake never overlap. All 840 steps at 240 Hz are accepted. Reapplying throttle at 1.75 s produces +168.812180765 W of tire-contact power. Front slips are approximately +5.57274 m/s and rear slips +2.17751 m/s; front longitudinal forces are approximately +14.16926 N and rear forces +2.49518 N.

The reconstruction uses full contact-point velocity and both tangential force components. It does not replace contact slip with hub speed. There are 25 positive tick-start samples in the 840-step run.

The optional [contact-power figure](OpenRCsimulator-math-audit-3df2791/contact-power.png) shows the complete sequence and a close-up of the positive-power pulse; it is included in the second evidence archive.

The first 2.25 s were also repeated at smaller outer steps while retaining the production tick policy's own substeps:
Outer rate	Peak positive tire power	Positive tick-start samples
240 Hz	168.812180765 W	25
480 Hz	168.803890401 W	48
960 Hz	168.800126563 W	94


The peak changes by approximately 0.0071% between 240 and 960 Hz. Together with the algebraic and energy checks, this locates the defect in the force law; reducing step size does not remove it.

The positive-only left-endpoint work sums are 3.686816, 3.500552 and 3.409141 J. These are sampled quadrature estimates, not net created energy, exact work integrals or RK-stage work integrals. Piecewise-linear integration of positive recorded power gives approximately 3.329558, 3.322076 and 3.319965 J after splitting at zero crossings and excluding intervals straddling control changes. Those latter estimates omit any positive contribution within the excluded intervals. The peak-power finding does not depend on either quadrature method.

Evidence: [drive probe](OpenRCsimulator-math-audit-3df2791/probes/truck_drive_sequence.gd), [240 Hz trace](OpenRCsimulator-math-audit-3df2791/traces/truck-trace-240.json), [480 Hz trace](OpenRCsimulator-math-audit-3df2791/traces/truck-trace-480.json), and [960 Hz trace](OpenRCsimulator-math-audit-3df2791/traces/truck-trace-960.json).
Brake scope, existing coverage and repair direction
No positive brake work occurred in that ordinary drive sequence. The brake defect is established by the independent production-solver example and a valid-state scan. The 486-case scan had no refusals and includes a +108 W brake-power witness with negative wheel spin and simultaneous throttle/brake; this is an admitted core state, not a demonstrated player-input sequence. The tire trajectory is the stronger player-relevance evidence. [State-scan probe](OpenRCsimulator-math-audit-3df2791/probes/truck_passivity_scan.gd)

The existing handling test checks the force circle and summed lateral dissipation in one coasting skid. It does not assert full \(F\cdot s\) across powered states. The project documents estimated friction parameters and capped iterations, but the reviewed truck notes do not accept positive tire/brake work as an intended limitation.

A necessary local tire admissible set is:
\[
\mathcal C=\{F:\|F\|\le\mu N,\ F^\mathsf{T}s\le0\}.
\]
The existing mobility-metric projection could be extended to:
\[
F^\star=\arg\min_{F\in\mathcal C}
\frac12(F-\hat F)^\mathsf{T}W(F-\hat F).
\]
Use the existing computed mu_load as the force limit, preserving its model and material scaling. The extra half-space adds a necessary energy constraint; it is not a complete calibrated tire law. Independent longitudinal/lateral sign clamps impose a different, overly restrictive condition. At zero slip, preserve static reactions of either sign. For brakes, enforce \(Q_b\omega_{\mathrm{rel}}\le0\) at nonzero relative spin while retaining both torque signs at zero for holding.
- [ ] Scalar tire and brake counterexamples become nonpositive-power cases.
- [ ] The stock energy balance satisfies the intended drive/loss accounting.
- [ ] Drive/brake/reversal trajectories, combined slip, static holding and near-zero crossings are covered.
- [ ] Airborne braking and loss/reacquisition of normal load retain valid behavior.
- [ ] Stage-integrated energy/work and step refinement are checked, not only endpoint telemetry.
- [ ] Convergence behavior and failure handling remain explicit.
- [ ] GDScript/native parity is executed after updating both implementations.
- [ ] Solver/checkpoint identity and intended golden-trajectory changes are handled through the repository's existing versioning and verification workflow.
Scope: source inspection establishes corresponding native equations, not measured native trajectories. The ground fixture is a controlled flat surface, not a recorded rendered circuit lap. No contact-law patch is claimed implemented or validated by this handoff.
Optimization opportunities
O1 — Qualify circuit terrain in the native backend
The circuit preference defaults to auto. On a detected dedicated GPU at High or Extreme detail, the policy enables the Club circuit. The player session receives that track, and native stage admission intentionally declines when the track is nonempty. For an otherwise eligible model, a scene-detail choice can therefore change the CPU physics backend as well as the visible scene.

Sources: circuit option policy, session track assignment, and native admission.

This fallback preserves terrain correctness. Removing the admission condition alone could make the native simulation use different ground. The opportunity is to implement and qualify the same composed terrain/contact geometry in native execution.

Acceptance work should cover track heights, ramp normals, edges, wheel support, hull collision, model/terrain mutation, trajectory parity and fallback. Compare identical aircraft, recorded inputs and weather with circuit off/on and record the selected backend, not merely the requested backend. No CPU percentage or FPS improvement was measured for this opportunity.
O2 — Admit eligible companion sessions to native execution
The player requests native execution before setup. Companion Agent creates a FlightSession and calls setup without choosing a backend, so it uses the low-level session's reference default. Selection must occur before setup.

Up to three optional companions each advance a complete simulation for every accepted player tick. Their pilot decision cadence of every fourth tick does not reduce the physics cadence. At 240 Hz:
\[
240(1+3)=960\ \text{model ticks per simulated second}.
\]
That count precedes RK stages, contact subdivisions, event localization and observers; it is not a measured CPU cost.

Sources: companion setup, session backend default/selection, player selection, manager stepping, and agent cadence.

Apply the same capability/admission rules to companions and preserve reference fallback. A nonempty circuit currently blocks this opportunity as well. Qualify traffic decisions, trajectories, reset/crash behavior, fleet recordings and fallback before changing defaults. Lowering companion physics frequency is a separate numerical change, not a consequence of the existing slower pilot-decision cadence.
O3 — Reuse prepared hull reach in the circuit broadphase
The circuit hull query slices and measures every hull point to reconstruct a bounding radius before rejecting an aircraft above or far from the track. The stock Stik has 26 points. At 240 Hz this represents:
\[
26\times240=6{,}240
\]
slice-and-norm operations per simulated second for one active Stik, or 24,960 for four such aircraft. These are source-derived counts, not timing measurements.

HullContact.prepare and prepare_geometry already compute a reach alongside detached geometry. Reuse that conservative bound when it matches the current live hull; rebuild at admission or supported mutation boundaries. A stale smaller radius can miss collisions, so object identity is insufficient if in-place geometry edits are allowed.

Sources: recomputed circuit reach and prepared hull geometry/reach.

This is a relatively small implementation opportunity. Verify conservative bounds, invalidation and rollback, then profile allocations and tick-time tails with the circuit active. Absolute savings may be modest; no FPS benefit is established by the operation count.
O4 — Share the downwash pre-step air calculation
This is the measured optimization candidate. When the downwash-lag auxiliary state is active, the session performs:
var cl_now := _wing_cl(s, aux)
var speed: float = air_data(s, sim.time()).V
The _wing_cl helper calls air_data() internally, using the same committed state and time. Its historical name is misleading: the returned quantity is a dimensional wing lift-velocity proxy in m/s, not dimensionless \(C_L\).

Sources: duplicate calls, helper, and downwash activation.

Activation requires a valid aircraft, nonempty envelope, horizontal downwash_lag_length, and a valid auxiliary lag index. In the tested Stik spatial-weather configuration, one air calculation samples ten wind positions: datum, six wing stations, horizontal tail, vertical tail, and propulsion station. The existing block queries twenty positions per callback because it repeats that calculation.

The tested one-change replacement was:
var lag_air: Dictionary = air_data(s, sim.time())
var cl_now := Aero.wing_wake_velocity(
    s, lag_air, _deflections(aux), aircraft.model, _ground_up(s)
)
var speed: float = lag_air.V
The exact first-order lag update remains unchanged:
\[
z_{k+1}=z_{\mathrm{target}}+
(z_k-z_{\mathrm{target}})\exp\!\left(-\frac{\Delta t\,V}{\ell}\right),
\]
with the target and speed now obtained from one air result for the same state/time.
Timing and verification
The original experiment used ten alternating batches of 128 fixed-state calls after warmup on a shared Intel Xeon Platinum 8573C and the pinned Godot debug editor. Values below are medians of batch-mean callback costs, not per-tick latency percentiles.
Weather workload	Wind queries per callback	Baseline	Candidate	Cost reduction
Legacy steady	2 → 1	77.33594 µs	69.67578 µs	9.9%
Spatial, eight modes	20 → 10	577.63672 µs	331.13281 µs	42.7%


Every original paired batch favored the candidate. A fresh reconstruction of the delivered bundle retained the improvement:
Replication workload	Baseline	Candidate	Pairs favoring candidate
Legacy steady	80.65625 µs	75.26172 µs	7/10
Spatial, eight modes	605.01172 µs	350.93359 µs	9/10


The spatial replication reduction is approximately 42.0%. Results are retained separately rather than pooled across different harness populations/times.

Correctness comparisons exercised the actual production _kernel_pre_step:
- 192 byte-identical pre-step outputs across varied positions, velocities, attitudes, rates and servo states.
- 24 accepted integration steps in each weather mode, with byte-identical body, auxiliary, continuous and mode arrays.
- Matching nonfinite pre-step outputs, kernel faults and rollback for four failure cases: rejected legacy datum, rejected spatial datum, rejected station after a valid datum, and pending weather reset.
Evidence: [candidate patch](OpenRCsimulator-math-audit-3df2791/prestep-candidate.patch), [paired probe](OpenRCsimulator-math-audit-3df2791/probes/prestep_pair.gd), [original measurements](OpenRCsimulator-math-audit-3df2791/evidence/performance/prestep-pairs.json), [refusal comparisons](OpenRCsimulator-math-audit-3df2791/evidence/performance/prestep-refusal.json), and [replication measurements](OpenRCsimulator-math-audit-3df2791/final-verification/prestep-pairs.json).
Production integration requirements
The environment contract requires pure deterministic position/time queries. Reuse is confined to the same callback, state, model, density and time. The Air receipt contract does not permit cross-stage reuse.

The experimental replacement calls the aerodynamic helper directly, bypassing possible _wing_cl subclass dispatch. A production implementation should preserve supported dispatch through an appropriate shared-data helper, or deliberately establish that such overrides are not part of the supported contract. Keep current refusal and rollback behavior.

The GDScript pre-step is shared by both backends, but native execution was not loaded in the benchmark. Execute native/reference trajectory and refusal checks before claiming complete backend qualification.

The measured 42% reduction applies to this callback. If it accounts for fraction \(p\) of total tick time and has speedup \(s\), whole-tick speedup would be:
\[
S_{\mathrm{tick}}=\frac{1}{(1-p)+p/s}.
\]
The audit did not measure \(p\) for the complete application; therefore it makes no 42% whole-tick or FPS claim.
O5 — Prepare invariant spatial-wind station geometry
wind_aircraft_flow.gd:_sample starts by calling geometry(model). That function rebuilds and validates station arms from authored model quantities on every sample. Preparing those arms once per admitted model could avoid repeated dictionary traversal, validation and allocation while still evaluating current state, time, wind and density each stage.

An unguarded prototype matched 402 sampled comparisons across three normalized models, lean/diagnostic receipts and sampled error cases. Eight alternating timing batches produced medians of approximately 247.53 → 225.00 µs per stage_air call; seven of eight pairs favored preparation, with substantial host noise. These timings omit the required invalidation/guard cost.

A deliberate negative control establishes why the prototype is not ready: after replacing station_ys[0] with NaN, the baseline rejected the model and the cached prototype still succeeded. Dictionary identity did not imply unchanged valid geometry. [Prototype results](OpenRCsimulator-math-audit-3df2791/evidence/performance/wind-pairs2.json)

Build prepared geometry at a validated model-change boundary and establish immutability or equivalent invalidation. Do not cache state-dependent station flow or Air receipts across RK stages. Preserve invalid-model refusals and test supported in-place mutations. Treat the benchmark as motivation for this design, not a qualified production speedup.
O6 — Share repeated rotor-domain calculations within a stage
The helicopter flight-domain precheck and subsequent aerodynamic/main-rotor evaluation perform overlapping hub-airflow, transition and advance-ratio calculations:
- flight_dynamics.gd precheck call and precheck calculation.
- aerodynamic_stage.gd.
- main_rotor.gd.
One fixed-state reference-backend diagnostic measured the entire precheck at 2.187–2.433 µs/call and the entire stage at 145.909–157.040 µs/call. This measures component cost, not a candidate speedup; not all precheck work is necessarily removable. It is not native, full-tick or target-hardware evidence. [Diagnostic probe](OpenRCsimulator-math-audit-3df2791/supporting-probes/rotorcraft/redundant_precheck_cost.gd)

A stage-local shared calculation may reduce duplication. Preserve rejection classification, finite/domain checks and arithmetic/replay behavior. The isolated precheck costs less per call than the O4 callback saving in these separate workloads; total benefit depends on stage/callback counts and a tested candidate. Give O6 lower implementation priority until that candidate demonstrates a useful saving.
Other microoptimizations screened
Reusing the overlapping Air.compute work inside spatial-air construction and replacing some repeated scalar/state validation were also explored. The collected timings did not establish a persuasive improvement. Keep validation intact and avoid claiming a speedup from instruction-count intuition alone. The exploratory wind results retain these candidates alongside O5; they are not additional confirmed bugs or production-ready patches.
Investigated behavior that is not a new defect
These checks establish useful boundaries on the audit, rather than certifying complete physical fidelity.
Investigation	Observed result	Interpretation
Existing kernel test	test_simulation.gd: 11 checks passed	Selected baseline control, not the complete suite
Existing RC-input test	test_rc_input.gd: 41 checks passed	Local coverage does not cover F2's full session composition
Existing AUX-runtime test	38 checks passed, with its expected overlap warning	Clearing/rearming tests can pass while accepted actuator requests change
Rotor/body power identity	600 sampled X-Cell states, no refusals, maximum absolute residual approximately 9.1×10⁻¹³ W	No new coupling defect in those samples
Rotor-inflow scalar root	27,150 samples, maximum residual approximately 1.0×10⁻¹³	Bounded numerical residual check
P-51 low-fuel runway runout	Valid 1.01% fill, exhaustion at 0.934817 s, continued for 15 s without the suspected fault	No new runout defect in that trajectory
P-51 airborne runout	Tested 200 m start continued without the suspected fault	Bounded trajectory result
Checkpoint across P-51 fuel exhaustion	Checkpoint at tick 210 replayed through tick 280 with byte-identical subsequent checkpoints/events	Reference backend and prescribed held inputs
Checkpoint across Turbo Lumber rotor stop	Tick 1430 replayed through tick 1490 with byte-identical subsequent checkpoints/events	Reference backend and prescribed held inputs


The powertrain investigation also reviewed electric bus/motor equations, battery charge/energy rates, ESC sampling, event composition, finite-liquid depletion, fixed-datum mass response, turbine cutoff and shaft stopping. It did not establish an additional serious defect in those reviewed paths.
Known electric reverse-breakaway limit
A stopped electric propeller can reach the documented reverse-breakaway refusal during a stock glide/roll sequence. The unsupported domain is explicitly documented and tested, so it is not counted as a newly discovered defect. A repair or extension would be separate feature/model-domain work. The P-51's legacy sub-1-rpm hold is likewise documented; the runway runout settled near 0.85135 rpm without the suspected session fault.
Known capped-friction convergence and numerical yaw
The truck's occasional 128-sweep cap hits and numerical asymmetry are already acknowledged in the RCV handling notes and research record. The second pass sharpened the evidence but did not discover that underlying limitation.

On a symmetric stock state with forward speed 0.1 m/s, zero wheel spin, brake 0.25, throttle/steering zero and mu = 0.9:
- Production returned ok after 128 sweeps with yaw acceleration approximately −0.0114509624 rad/s².
- A diagnostic cap-only extension took 1,766 sweeps to satisfy the existing update tolerances and returned approximately −0.0000239593 rad/s² yaw acceleration.
- The last production sweep still changed a tire force by approximately 4.82×10⁻⁴ N and a brake torque by 4.82×10⁻⁵ N·m, exceeding the respective 10⁻⁶ update tolerances.
- Reversing left/right contact-pair processing reversed the yaw sign.
Both force and brake update maxima are already included in the early-out condition. The issue is unconditional success at the cap, not omission of a brake-torque tolerance. Small updates also do not establish a full KKT/complementarity residual, and not every asymmetry in individual contact forces proves an error because reaction distributions can be nonunique.

A separate four-second zero-steering sequence—one second full throttle, three seconds 25% brake—hit the cap in 671 of 960 tick-start evaluations, yet had only approximately 0.206 mm maximum lateral offset and 0.00232° maximum yaw. The truck was still moving at the last sample; this was not a full-stop result. These observations do not support promoting the known limitation into another new severe bug.

Evidence: [convergence receipt](OpenRCsimulator-math-audit-3df2791/evidence/rotorcraft/truck-convergence-qaikxw2n/report.json) and [order/trajectory receipt](OpenRCsimulator-math-audit-3df2791/evidence/rotorcraft/truck-order-sequence-hpj04qrn/report.json).
Other documented modeling boundaries
The earlier review also considered why ground effect scales baseline downwash while leaving the propwash/slipstream increment unchanged. The aircraft contract specifies that behavior. It is a model-fidelity consideration rather than a confirmed implementation defect. The exploratory numerical comparison was not retained in the recovered evidence packages, so this handoff makes no quantitative claim about its magnitude.

Other apparent contact/rotor concerns that matched already documented approximation or supported-domain limits were excluded. No unexecuted suspicion is included in the confirmed defect count.
Reproduction commands
Prerequisites and extraction
Use a complete checkout at the audited revision and the exact pinned Godot build. Follow the repository's documented app/get-godot.sh setup, including Git LFS assets where required. Keep experiments in a separate checkout if investigating a current development branch.

After extracting the two archives, the working directory should contain this Markdown file and the directories OpenRCsimulator-audit-3df2791/ and OpenRCsimulator-math-audit-3df2791/. Their own README.txt files give additional environment details.

Paths below are placeholders to replace with local absolute paths. Output directories must be fresh: neither wrapper overwrites an existing runtime/ directory.
First-pass defects F1–F5
python3 OpenRCsimulator-audit-3df2791/run_audit.py \
  --repo /absolute/path/to/OpenRCsimulator \
  --godot /absolute/path/to/Godot_v4.8-beta2_linux.x86_64 \
  --output /absolute/path/to/fresh-pass1-output
Select one or more cases with repeated --case arguments:
Case name	Finding
workshop	F1
aux_pause	F2
track_statistics	F3
glow_timing	F4 diagnostic
empty_log	F5


Example:
python3 OpenRCsimulator-audit-3df2791/run_audit.py \
  --repo /absolute/path/to/OpenRCsimulator \
  --godot /absolute/path/to/Godot_v4.8-beta2_linux.x86_64 \
  --output /absolute/path/to/fresh-workshop-output \
  --case workshop
The first wrapper has --allow-changed-source for deliberate investigation of a local fix; it records the mismatch and changed file names in run_context.json, not replacement SHA-256 values. Record candidate hashes separately. Such a run is no longer an exact baseline reproduction. Translate counterexample assertions into desired-behavior tests before treating it as a repair gate.
Second-pass defect F6 and measured optimization O4
python3 OpenRCsimulator-math-audit-3df2791/run_audit.py \
  --repo /absolute/path/to/OpenRCsimulator \
  --godot /absolute/path/to/Godot_v4.8-beta2_linux.x86_64 \
  --output /absolute/path/to/fresh-pass2-output
Case name	Coverage
scalar	Tire and brake algebraic counterexamples in the production solver
energy	Stock Bisonte energy balance
truck_drive	Ordinary 3.5-second drive/brake sequence
wind_pair	O4 sampled equivalence, query counts and paired timings
wind_refusal	O4 four failure/rollback comparisons
truck_refinement	First 2.25 s at 240, 480 and 960 Hz; optional rather than part of the default run


python3 OpenRCsimulator-math-audit-3df2791/run_audit.py \
  --repo /absolute/path/to/OpenRCsimulator \
  --godot /absolute/path/to/Godot_v4.8-beta2_linux.x86_64 \
  --output /absolute/path/to/fresh-refinement-output \
  --case truck_refinement
The second wrapper generates the O4 experimental session candidate in the isolated runtime. It does not patch the supplied checkout. It deliberately verifies exact baseline hashes; it does not expose the first wrapper's changed-source override. Adapt the probe into the owning test workflow when validating a physics fix.
Interpreting retained results
Check each report.json for completion, ok, diagnostics, required markers and source context. Inspect the corresponding engine.log or result JSON for numerical values. A receipt's elapsed_seconds measures the whole process, including startup/import as applicable; it is not a physics benchmark.

The delivered second-pass wrapper was run from a newly reconstructed runtime. Import, scalar, energy, truck driving, wind pairing and wind refusal all completed with zero engine errors and zero warnings. This establishes that the delivered reproducer worked on the audited baseline. These physics experiments were not rerun merely to format this consolidated handoff.
Implementation sequence and release evidence
Suggested work packages
Keep each change independently reviewable. These packages can be assigned by the responsible developer without turning one change into a mixed physics/input/performance patch.
Order	Work package	Completion evidence
1	Contain F1 at admission, then compose the event/contact stepping policy	Exact Workshop recipe, first accepted tick, event/contact composition and rollback
2	Resolve F2 command validity versus zero amount	Session-level unchanged-switch pause/resume coverage and actuator continuity
3	Correct F6 tire/brake passivity in both kernels	Scalar, energy, ordinary driving, combined slip, static holding, refinement and executed backend parity
4	Repair F3 observer terrain composition	Geometric witness plus complete detector episodes
5	Repair F4 connected event trials	Adjacent-float/analytic event tests and integrated force/torque checks
6	Repair F5 optional-block serialization	Empty/nonempty record/inspect/replay compatibility
7	Implement O4 shared downwash air data	Existing exact/refusal comparisons, supported dispatch and backend checks
8	Implement O3 bound reuse, then evaluate O5/O6	Correct invalidation/refusal behavior and paired performance evidence
9	Qualify O1/O2 native terrain and companion coverage	Selected-backend proof, trajectory/replay/fallback qualification and whole-application measurements


Orders 1–3 are the highest-priority correctness work and can proceed in parallel with clear ownership. F1/F4 share glow event concerns; coordinate their interfaces. O1/O2 share native admission constraints. F6 changes physics and should not be concealed inside an optimization patch.
Physics and state-contract checks
Retain the baseline source/configuration and input tape before changing physics. Follow the repository's flight-log workflow: verify exact baseline replay, then compare a candidate using the same accepted tick/input sequence. Preserve source, data, solver, engine and backend identities. A changed solver should follow the project's checkpoint identity/version rules.

Golden-trajectory changes are expected only where the intended physics change explains them. Do not re-record a golden to remove an unexplained failure. Use focused checks during implementation, then the owning contract and required CI gates on a stable candidate. Software consistency is distinct from validation against a physical aircraft or truck.
Performance qualification
Measure identical aircraft, track, weather, input tape and accepted-tick counts. Record at least:
- The actual selected backend and fallback reason for each vehicle.
- Stage-evaluation count and any contact/event subdivisions.
- Mean and p95/p99 physics tick cost, with the measurement unit clearly stated.
- Allocation count, observer cost and companion count.
- End-to-end frame time on the target rendering hardware, separately from headless component cost.
Exercise companions at 0 and 3, circuit off/on, and airborne/runway/contact phases. The nominal 240 Hz interval is:
\[
\Delta t=\frac1{240}=4.1666667\ \mathrm{ms}.
\]
Use the repository's primary 1920×1080 presentation target for rendering qualification. A faster headless callback, process-startup duration, or lower-resolution capture cannot establish complete 1080p frame-time behavior.
Evidence index
The following paths are relative to the extracted package directories beside this file. Original receipts preserve original capture paths for provenance; the wrappers create fresh receipts using the developer's local paths.
Topic	Primary retained artifact
First-pass baseline file identities	[Manifest](OpenRCsimulator-audit-3df2791/source_manifest.json)
First-pass instructions and limitations	[README](OpenRCsimulator-audit-3df2791/README.txt)
F1	[Workshop probe](OpenRCsimulator-audit-3df2791/probes/workshop_freeze_repro.gd)
F2	[AUX probe](OpenRCsimulator-audit-3df2791/probes/aux_pause_probe.gd)
F3	[Statistics probe](OpenRCsimulator-audit-3df2791/probes/rc_track_statistics_probe.gd)
F4	[Glow timing diagnostic](OpenRCsimulator-audit-3df2791/probes/glow_timing_comparison.gd)
F5	[Empty-block record probe](OpenRCsimulator-audit-3df2791/probes/body_only_record.gd)
Second-pass baseline identities	[Manifest](OpenRCsimulator-math-audit-3df2791/source_manifest.json)
F6 branch proof	[Scalar probe](OpenRCsimulator-math-audit-3df2791/probes/ground_solver_passivity.gd)
F6 mechanical-energy proof	[Energy probe](OpenRCsimulator-math-audit-3df2791/probes/truck_energy_balance.gd)
F6 ordinary-control trajectory	[Drive probe](OpenRCsimulator-math-audit-3df2791/probes/truck_drive_sequence.gd)
F6 full sampled states and power	[240 Hz](OpenRCsimulator-math-audit-3df2791/traces/truck-trace-240.json), [480 Hz](OpenRCsimulator-math-audit-3df2791/traces/truck-trace-480.json), [960 Hz](OpenRCsimulator-math-audit-3df2791/traces/truck-trace-960.json)
O4 exact candidate	[Patch](OpenRCsimulator-math-audit-3df2791/prestep-candidate.patch)
O4 measurements	[Original pairs](OpenRCsimulator-math-audit-3df2791/evidence/performance/prestep-pairs.json), [fresh reconstruction](OpenRCsimulator-math-audit-3df2791/final-verification/prestep-pairs.json)
O4 refusal behavior	[Results](OpenRCsimulator-math-audit-3df2791/evidence/performance/prestep-refusal.json)
O5 and screened microoptimizations	[Exploratory results](OpenRCsimulator-math-audit-3df2791/evidence/performance/wind-pairs2.json)
Rotor/body energy identity	[Checked receipt](OpenRCsimulator-math-audit-3df2791/evidence/rotorcraft/heli-coupled-energy-nt9bs_sx/report.json)
Rotor inflow residuals	[Checked receipt](OpenRCsimulator-math-audit-3df2791/evidence/rotorcraft/rotor-inflow-residuals-2sa2s6db/report.json)
P-51 runway and airborne runout	[Runway](OpenRCsimulator-math-audit-3df2791/evidence/powertrain/gas-runway-e34_7p8f/report.json), [airborne](OpenRCsimulator-math-audit-3df2791/evidence/powertrain/gas-runout-hcfmsgl0/report.json)
Fuel-exhaustion/rotor-stop replay	[Checked receipt](OpenRCsimulator-math-audit-3df2791/evidence/powertrain/event-replay-w5ovyn1d/report.json)


Qualification boundary
The audit does not claim a rendered UI session, physical-controller test, native execution, complete regression suite, GPU/frame-time campaign, full flight envelope, sustained circuit landing, or independent physical vehicle validation. Its confirmed findings are the precisely scoped production-code, geometric, numerical and session counterexamples above. Its optimization claims are limited to the code-path counts and component measurements explicitly identified.

The recurring contract gaps are concrete: aircraft admission versus integrator capability; input validity versus commanded position; observer terrain versus physical terrain; representable trial state versus lifecycle branch; optional-state serialization; and force magnitude versus dissipative work. The acceptance criteria target those boundaries so repairs can be verified beyond the original single witness.