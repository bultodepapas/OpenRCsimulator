# Physics, mathematics and aerodynamics audit at 57abea0

Audit date: **2026-11-21**. Original source: `57abea025f62b20233ca281d58d2acbee4ab8b8e`.
Engine: **Godot 4.8.beta2.official.cafc17a19**, Linux x86-64.

This is the historical A36 finding record. The [research home and implementation status](../docs/research/project-audit-2026-11-21/README.md) distinguish the original failures from later corrections and qualification. Do not interpret the original reproducer's expected failures as candidate acceptance tests.

## Original deliverables and scope

- [Nine-page report](../docs/research/project-audit-2026-11-21/originals/OpenRCsimulator-audit-57abea0.pdf): equations, numerical observations, source anchors, limits and repair order.
- [Portable evidence bundle](../docs/research/project-audit-2026-11-21/originals/OpenRCsimulator-audit-evidence-57abea0.zip): seven original checked report/log pairs, seven audit-authored probes, numerical results, CI records, source hashes and `reproduce.py`.

The original audit did not change production source. It reviewed the pending/completed audit ledgers before assessing current code. The portable reproduction ran four fixture imports and six clean probes; the seventh probe reproduced the specifically expected jet `engine_error` even though the child process exited zero. Numerical observations matched at `1e-10` relative / `1e-12` absolute tolerance.

The checks are headless software evidence. They do not establish full application, rendered-flight, native-platform, physical-aircraft or target-hardware performance qualification. Incomplete initial fixtures were rejected and excluded from positive conclusions. The blimp session fixture uses unchanged session/kernel/physics sources and an explicitly disclosed fail-if-used collision-world stub on an empty-scenery path. The component fixture needs no stub.

## Findings

| ID | Observation at the original snapshot | Evidence level |
| --- | --- | --- |
| F1 | Equivalent Phoenix propellers lose total thrust: twin -8.27%, four -15.86% in the synthetic steady-point witness | Executed component; independent algebra |
| F2 | Identical second wing doubles the fuselage-drag contribution despite an unchanged body | Executed component composition |
| F3 | Neutral stock-data blimp fins supply +0.077408754 W in reverse flow | Executed component; passive-force invariant |
| F4 | Admitted custom blimp battery supplies 4.6009 W two seconds after SOC crosses zero | Accepted session ticks; checkpoint continuation |
| F5 | Valid Phoenix jet derivation emits a format error and retains an unformatted provenance string | Executed diagnostic failure |
| O1 | 100 distinct scales leave 200 derived packages and 2,682,720 serialized payload bytes | Executed retention observation; not RSS/FPS |
| G1 | Exact-source CI preflight rejects 13 UID sidecars and skips downstream qualification | Observed GitHub run; known failure-class recurrence |
| G2 | Refused airship preparation with a nonfinite heading damages the prior flight | Executed invalid-API witness; UI reachability unestablished |
| G3 | Automatic airship recorder failures have no in-flight notification path | Source-confirmed control flow; no disk/UI reproduction |

## F1. Equivalent propulsion must preserve sums

[Phoenix propulsion derivation](../app/workshop/creator/phoenix/physics.gd) enlarges the equivalent diameter as `D_eq = D*N^(1/4)`, then uses that diameter to recompute pitch ratio. In the measured-table branch, the coefficient amplitude scales as `sqrt(P/D)`. At equal RPM, unchanged diameter-share, no active thrust cap and an unclamped pitch-ratio stretch:

\[
T=\rho n^2D^4C_T,\quad C_T\propto\sqrt{P/D},\quad
\frac{T_{eq}}{NT_1}=N^{-1/8}.
\]

The synthetic block used 0.20 m diameter, 0.15 m pitch, 8000 requested RPM, 1.5 kg, the trainer airframe and electric 3S base package. The solved operating points were:

| Propellers | Actual thrust N | N times single N | Shortfall |
| ---: | ---: | ---: | ---: |
| 1 | 4.697438 | 4.697438 | 0% |
| 2 | 8.618366 | 9.394877 | 8.27% |
| 4 | 15.808948 | 18.789753 | 15.86% |
| 8 | 28.996166 | 37.579507 | 22.84% |

Solved RPM varies slightly; an independent fixed-8000-RPM evaluation matches the algebraic ratio. The [existing twin test](../app/tests/test_creator_phoenix_readers.gd) permits 1.6-2.4 times the single result, so its empirical tolerance misses the aggregation defect.

Build the individual completed tables first. For `D_eq=kD`, transform `J'=J/k`, `Ct'=N*Ct/k^4`, `Cp'=N*Cp/k^5`. This preserves thrust and shaft power through rows/interpolation; extrapolation floors, motor calibration, power caps, equivalent disk area, inertia and reaction-axis assumptions require separate qualification. Version the derivation. Regress counts 1/2/4/8 at static and advancing speeds with independent summed thrust and torque expectations.

## F2. Keep dimensional drag consistent across reference areas

[Converter.definition_values](../app/workshop/creator/phoenix/converter.gd) emits stacked wings at their total lifting area, while `physics_block` normalizes body drag by the selected main wing area. [Packages.airframe_aero](../app/workshop/creator/packages.gd) later uses the unchanged coefficient with the emitted area:

\[
C_{D,body}=0.75 A_f/S_{main},\quad
D_{body}/q=0.75 A_f(S_{emitted}/S_{main}).
\]

With 1.5 m span, 0.25/0.20 m root/tip chords and frontal area 0.006 m², adding an identical stacked wing changes `S` from 0.3375 to 0.675 m². The body coefficient remains 0.0133333, so `D_body/q` changes from 0.0045 to 0.009 m²; its intended value remains 0.0045. Both planforms remain within the allowed ranges without fitting.

This is a fuselage-contribution error, not twice the total aircraft drag. It is independent of real biplane interference accuracy. Preserve a dimensional body drag area or an explicit coefficient/reference-area pair until final geometry is known; scale dimensional area consistently during resizing. Regress added lifting wings and planform fitting while holding the body fixed. The original audit did not measure the entire imported-model corpus.

## F3. Neutral fin forces must remain passive

In [airship_dynamics.gd](../app/physics/airship/airship_dynamics.gd), neutral stationary fins in calm air, with stopped rotors and zero body rates, produce:

| Body-relative velocity m/s | Sum of fin force power |
| --- | ---: |
| `[-3, 0.5, 0]` | **+0.077408754 W** |
| `[+3, 0.5, 0]` | -0.374255883 W |

The dorsal fin supplies +0.090643063 W in the reverse case. Its current normal-law terms contain `sin(alpha)*cos(alpha)` and `sin(alpha)*abs(sin(alpha))`. Normal-force power includes `-q*S*V_plane*sin(alpha)^2*(a*cos(alpha)+c*abs(sin(alpha)))`; reverse flow changes the sign of the lift-slope contribution and skin drag need not offset it.

For this passive component, require `F dot v_local <= tolerance`, with `v_local=v+omega cross r`. Hull drag may still dissipate more, so this is not evidence of total-vehicle acceleration or a runaway flight. It is distinct from the earlier fixed-wing reverse-flow correction and the separately documented airship afterbody limit.

Use a defensible full-angle force direction or explicitly restrict the admitted regime. Test individual fins over signed flow and rotation, retain forward handling and moments, and do not hide a bad component behind total-vehicle dissipation.

## F4. Depletion must end battery supply

The [battery bus](../app/physics/airship/airship_dynamics.gd) clamps its OCV lookup at zero charge and freezes `dSOC` for `SOC<=0` while retaining electrical supply. The [reader](../app/physics/airship/airship_data.gd) admits a cutoff below zero-SOC OCV.

An accepted session used stock data with capacity 0.05 Ah, initial SOC 0.05 and cutoff 3.2 V/cell; zero-SOC OCV is 3.3 V/cell. All altered values lie within reader ranges. Calm air, empty scenery and a 100 m release eliminate contact. After low-throttle resume, full throttle yields:

| Tick | SOC | Current A | Electrical power W |
| ---: | ---: | ---: | ---: |
| 960 | 0.001801338 | 0.613317 | 6.071481 |
| 1103 | -0.000002818 | 0.485593 | 4.796765 |
| 1583 | -0.000002818 | 0.465726 | 4.600925 |

Charge freezes while motor drive and thrust persist. The crossed state restores, and 480 continuation ticks reproduce body and continuous-state bytes exactly. Determinism alone does not establish physical correctness. The shipped battery settings differ; this proves the admitted custom path, not stock-battery endurance.

Define the depletion boundary transactionally. Accepted charge stays in its domain; battery-supplied current and drive stop after exhaustion while justified rotor coasting remains. Test crossing, post-event current, timestep refinement and checkpoint/replay/rollback. An arbitrary stage mutation or instantaneous removal of stored rotor energy is not an adequate repair.

## F5. Escape the jet provenance percentage

The [jet provenance template](../app/workshop/creator/phoenix/physics.gd) contains literal `1 %` beside `%s`. A valid jet derivation raises `String formatting error: unsupported format character`. Package IDs and efflux speed 100.0 remain available, but the source string is unformatted. The child process exits zero and the checked wrapper correctly rejects engine errors.

Escape the literal percent as `%%`; assert formatted provenance and a clean checked run. The observed failure does not establish wrong jet thrust or blocked flight.

## O1. Give derived packages lifetimes

[Packages._derived_packages](../app/workshop/creator/packages.gd) retains deep copies without retirement. [Authoring setup](../app/workshop/creator/authoring.gd) can derive candidates across five size attempts and two mass passes; document rollback does not retire registry entries.

100 distinct admitted scales produced 200 retained packages and 2,682,720 serialized payload bytes. Repeating an identical scale did not grow the registry. This is not process RSS, a whole-app leak rate, a measured latency regression or an FPS gain.

Prefer temporary candidate derivation and accepted-only registration, or explicit ownership and safe retirement. A blind LRU can invalidate open drafts. Regress distinct import/resize, rejected attempts, close/reopen and active draft resolution; then compare sustained RSS and setup latency. Profile hashing, copies and equilibrium solves before promising cache speedups.

## G1. Current CI blocker is a recurrence

[Run 44833680915](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/44833680915) at the audited SHA fails preflight on 13 missing/invalid tracked UID sidecars. App, visual, native and release jobs are skipped. The later missing-selection-artifact error follows the early stop. Exact paths, job IDs and status are in the evidence bundle.

Generate and commit sidecars with the pinned editor and rerun required CI at the integrated source. Preserve the gate. The [completed ledger](COMPLETED-AUDIT-WORK.md) records earlier UID repairs; this is a current recurrence of that failure class.

## G2. Refused prepare must retain the old flight

[Airship Session.prepare](../app/sim/airship/session.gd) promises refusal preserves the old flight but commits options/model before reset. After an accepted tick, `prepare({}, {heading_deg=NAN})` returns false, emits reset/fault signals and damages the prior session/checkpoint.

This was a constructed invalid-API test; normal UI reachability was not established. Prepare/validate the candidate before publication and regress preservation of old state, history and recorder when refusal occurs. Use the shared transaction contract.

## G3. Surface automatic recorder failures

[Airship flight_log](../app/sim/airship/flight_log.gd) stops and closes on a packet/flush failure, stores a note and prints to stderr. [The activity](../app/vehicles/airship/airship_scene.gd) displays the note during explicit F10 only; a later F10 can replace the failed recorder and show a new-start note. Automatic limits have a similar visibility gap.

This is source-confirmed control flow, not an injected disk-failure/UI result. Emit/retain failure status, surface it during flight, preserve recoverable-prefix identity, and test post-header failure plus automatic limits and retry through the actual activity.

## Continuing the mathematics and aerodynamics work

Prioritize independent properties: engine additivity, coefficient/reference-area consistency, passive element power, bounded stored energy, atomic refusal and live-owner-bounded retention. Preserve float64, fixed 240 Hz, and kernel-owned integration/events/checkpoints. A native evaluator replaces model callbacks; it does not take ownership of the tick transaction.

Continue with source-matched imported-aircraft performance cards, reference/native equivalence where supported, complete replay, rendered workflows and physical calibration. Preserve baseline/source/backend identity. Measure median/p95/p99/max step and frame times, catch-up bursts, simulated/wall-time ratio, setup latency and sustained memory on target hardware. No target-hardware performance campaign was executed in this audit.
