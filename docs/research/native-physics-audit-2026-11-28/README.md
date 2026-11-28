# Native physics audit and implementation priorities

**OpenRC Simulator · 28 November 2026 · production baseline `8d4169f8febfd7d78a028eaa817414217a54f24b`.** This is an audit and implementation plan. It changes no production force law, integration policy, controller, aircraft data or native binary.

The strongest immediate opportunities are passive-contact energy, heading-independent ground constraints, continuous and saturation-aware FPV control, and consistent operating inputs across propulsion and tail-load paths. Fix those bounded inconsistencies before expanding unmeasured flight regimes. Native allocation and repeated-work reductions can proceed in parallel, with actual execution ownership and target timings recorded. Richer rotor, airfoil, turbine and EDF models need matched data and separate physical acceptance.

| Review entry point | Contents |
| --- | --- |
| [Prioritized improvement plan](improvement-plan.md) | Affected files, native designs, dependencies, engineering effort, benefits, risks and measurable acceptance gates |
| [Independent verification](verification.md) | Per-finding adjudication, independent checks, narrowed/rejected claims and final evidence limits |
| [Baseline and scope](baseline-and-scope.md) | Pinned source, 27-suite baseline, native admission limits, units, frames and coverage |
| [Reproduce the evidence](../../../research/native-physics-audit-2026-11-28/README.md) | Checked-engine runner, actual C++ header probes, independent equations, production-function counterexamples and compact receipts |
| [Research sources](sources.md) | Primary scientific, engineering, manufacturer and experimental references, with report-specific transfer limits |
| [Tracking issue #24](https://github.com/bultodepapas/OpenRCsimulator/issues/24) | Dedicated branch, audit deliverables and implementation handoff |

## What was established

All **27 selected existing reference-engine suites passed, with 6,527 reported assertions** and unchanged production-source fingerprints. The source inventory covers 272 physics/simulation/native files and 106,404 lines; it defines the inspected surface, not exhaustive verification of every line or state. Actual native-header components and independent equation/data witnesses add checks that the existing regression suite did not contain. The lead also reproduced the FPV frame-energy defect and two controller defects by calling the actual prepared production functions through the checked engine.

The environment did not contain an admitted native aircraft or ground sidecar. Its GCC 14.2 differs from the qualified Linux GCC 13.3. There was no GPU, configured test pool or controlled production target. A ground native comparison explicitly skipped. Consequently these results establish software/source/component evidence, **not** a qualified native release, pilot acceptance, matched physical flight accuracy or a measured FPS gain. The plan retains those gates.

The independent reviewer adjudicates **39 primary subclaims** from nine domain reports, counting the two electric initialization input errors separately, plus two previously reported collision cross-checks. A finding can confirm that a deliberate simplification exists without calling it a bug. Physical-error magnitude, player incidence and performance gains remain unverified wherever no matched experiment or target trace exists. The [ledger](verification.md) is authoritative for those distinctions.

| Primary verdict | Count | Meaning |
| --- | ---: | --- |
| Confirmed bug | 18 | Reproducible violation of a stated contract, physical invariant or accepted configuration boundary |
| Documented simplification | 12 | An intentionally limited law with a demonstrated consequence; improvement requires its own justification |
| Implementation limitation | 6 | Missing coverage, model domain or observability, distinguished from a contradicted contract |
| Performance opportunity | 3 | Proven redundant work or allocations; target latency and FPS benefits remain unmeasured |
| **Total** | **39** | Two independently rechecked prior collision mechanisms are additional and not counted again |

The evidence includes **48 new assertions against actual production functions** in three checked-engine probe groups: rotor/frame impact, FPV controls and airship boundaries. The verifier also records nine nested qualifications and sixteen rejected or still-unverified extensions of the primary claims.

## First implementation queue

This ordering balances evidence, consequence, reach and dependencies. It is a lead recommendation, not a measured utility score. Related changes should remain independently reviewable.

| Order | Finding or work package | Decisive evidence | First acceptance target |
| --- | --- | --- | --- |
| 1 | **DRONE-03: coupled rotor/frame impulses** | Actual stock contact function: body loses 0.0064924 J while complete rotor/body energy gains 0.0107881 J; zero-rotor control dissipates | Passive complete-system energy cannot increase; untouched rotor absolute spin remains continuous |
| 2 | **MECH-01/02: ground constraints** | Rotating the truck and matching 1 mm road patch changes lateral force from 0 to 3.068 N; applying a 6.5 N wall load after the tire solve leaves 2.640 m/s² patch acceleration | Rotational equivalence and the same constrained response for the same combined external force |
| 3 | **CTRL-01/02: FPV command continuity and anti-windup** | Actual controller: 190.4266°/s raw roll-command jump across a 2e−8 rad pose change; yaw integral grows into an upstream torque cap | <0.001°/s seam difference; upstream-only saturation cannot integrate farther into that limit |
| 4 | **PROP-01, AERO-01, ELEC-01a/b: operating-point consistency** | Identical wind representations change P-51 propeller loads by about 1 N; tail increment differs by 0.213628 N·m; hot launch has 0.05680 N·m torque residual | Shared hub flow/ground downwash/pack state, with the specific zero/rate/far-ground/calm controls |
| 5 | **MECH-03/04: collision and valid airborne states** | Stock-hull geometry can miss a true box crossing; zero-load vertical truck is refused by a distant-ground contact-frame calculation | Earliest real box entry and finite airborne dynamics across ±90° pitch |
| 6 | **PROP-02, ELEC-02/03: energy-port and calibration accounting** | Brake-versus-indicated idle mismatch; floating bridge voltage reported as cell voltage; source current used as motor current offline | Correct idle reference, pack-side cell report and independently reconstructed source power |
| 7 | **HELI-02/03: documented input contract and bounded rotor direction** | Vertical height substituted for wake-path distance; finite flap-derivative jump across pure sideflow | Wake-normal geometry and continuous in-range direction response; separate high-μ envelope gate |
| 8 | **MATH-02/03/04: authorable airship boundaries** | Accepted depleted-pack configuration can still drive; near-sphere coefficient cancellation; allowed contact stiffness exceeds the current step's demonstrated accuracy | Resource disconnect, positive stable coefficients, and ≤1% undamped contact-energy error or explicit refusal |
| 9 | **ENG-01 then ENG-02/03/04: measured native work** | Stage versus integrated ownership differs by family; 25 allocations/6,400 bytes in one synthetic event path; repeated spatial prop and ground geometry work | Actual ownership counters, zero scoped clear-path scratch allocations and unchanged equivalent-refactor outputs |
| 10 | **MATH-01 / CTRL-03: stage-time RPM and servo trajectories** | Jensen quarter-second static impulse +1.302%; first elevator ramp tick receives twice the continuous law's mean deflection | Analytic impulse/exposure checks while the pilot sample clock remains 240 Hz |
| 11 | **DRONE-01, AERO-04/02: prepared data and local response** | Same-run withheld thrust rows improve substantially; control footprint and wing-to-tail gust pathways have explicit discrepancies | Preserved calibration limits, correct local geometry and consistent gust-source transport |
| 12 | **Data-dependent regime work** | Autorotation drivetrain, VRS increment, rotor interactions, Reynolds effects, stopped propeller, turbine transients, actuator motion and EDF each have distinct evidence gaps | Matched identification and holdouts before stock physical promotion |

The detailed plan supplies day ranges. Small source/input fixes are generally 1–5 engineer-days each after their existing adapter is available. Native FPV controller/contact work needs its own typed sampled/transaction boundary. Measurement-dependent work is longer and is not covered by those small-fix estimates. No calendar commitment follows from adding overlapping ranges.

## Actual native architecture

| Family | Existing possible native ownership | Boundary that must remain visible |
| --- | --- | --- |
| Fixed-wing | Eligible continuous stages and integrated endpoint answers on admitted builds | Some callbacks/policies still delegate; package and platform domains differ |
| Helicopter | Continuous rotor/body/skid stage under supported dry/uniform conditions | Explicit whole-tick refusal; lake and platform exclusions; session owns remaining transaction/policies |
| FPV multirotor/race | Production controlled plant is currently framed/sampled script | Preserve one controller sample, held commands, endpoint and race event order in a native port |
| Ground electric/Nitro | Separate native chassis/force evaluator and optional terrain sampling | Shared integration policy, external wet/wall and Nitro drive context; its own ABI/receipt |
| Airship | Purpose-built script dynamics through the shared simulation | Needs an independently admitted native model/adapter, not a fixed-wing coverage label |
| Optional fixed-wing servo interval law | Current narrow implementation requires reference backend | Native interval protocol is a separate implementation step |

The plan keeps authoritative numerical state and laws in project-owned float64 C++; Godot remains the existing host boundary. An optimization must preserve or explicitly version atomic tick/restore/refusal, recording identity, sampled control, event ordering and qualified floating-point behavior. Counting requested native backends or stage calls alone cannot establish integrated ownership.

## Domain reports and specialist accountability

The lead coordinated exactly ten specialist roles, in batches of at most three concurrent helpers. Each helper invocation explicitly requested `gpt-6.2-astra` with `max` reasoning through the available model-override API and a fresh, self-contained brief. That records the requested routing; no provider-level model attestation is inferred. The active lead session was retained. Helpers wrote exclusive research outputs; the lead owned the worktree, serial engine launches, integration and GitHub publication. The verifier did not author the domain findings it adjudicated.

| Role | Report and main evidence |
| --- | --- |
| Aerospace physicist | [Fixed-wing](domains/fixed-wing.md): load composition, control footprint, gust source, Reynolds domain; actual C++ headers |
| Helicopter expert | [Helicopter](domains/helicopter.md): inflow, flap direction, ground effect, drive/autorotation and VRS scope; actual C++ headers |
| Drone expert | [Multirotor](domains/multirotor.md): manufacturer fit, inflow, coupled impact energy, timed prop contacts and interference; independent equations plus lead production witness |
| Propulsion engineer | [Combustion/turbine](domains/combustion-turbine.md): gasoline inputs/fuel, stopped propeller, turbine transient, glow mass/power controls; actual C++ headers |
| Electric propulsion expert | [Electric/EDF](domains/electric-edf.md): launch state, pack/bridge ports, current provenance and distinct EDF family; native components, circuit/data oracles |
| Mechanics physicist | [Mechanics](domains/mechanics.md): ground constraints, scenery CCD, contact-frame admission, buoyancy/water checks; actual ground C++ and geometry oracles |
| Mathematician | [Numerics](domains/mathematics.md): stage-time load coupling, charge exhaustion, shape conditioning, stiffness admission, conservation and step refinement |
| Flight-controls engineer | [Controls](domains/flight-controls.md): attitude seam, anti-windup, interval servos and helicopter actuators; algebra/native components plus lead production witness |
| Senior native engine developer | [Native engine](domains/native-engine.md): execution map, allocations, duplicate work, determinism and current guard limits |
| Independent findings verifier | [Adjudication](verification.md) and [method](verification-method.md): independent code/equation/data checks, controls, bounded classifications and rejected overclaims |

## What should be retained

The audit does not justify replacing the shared RK4 method wholesale. Its independent spinning-ballistic and co-moving variable-mass fixtures exhibit fourth-order convergence; at 120/240/480 Hz the ballistic position error falls from approximately 6.47e−5 to 4.07e−6 to 2.55e−7 m. Complete body-plus-ejecta linear and angular momentum converge consistently. Endpoint normalization alone would not reveal phase error, but the independent attitude check does. A narrow event bracket does not erase underlying integration error. These controls direct the fixes toward specific coupling and admission boundaries.

The fixed-wing motor power identities and helicopter generalized angular-work identity close in the stated component stands. The reviewed glow 2T/4T laws have correct firing-opportunity and power conversions, and their tested axial blade sweep meets the chosen passivity bound. Inertia sign conventions and live fuel moment transfers were checked in the cited paths. These are bounded analytical/software results, not proof of aircraft calibration.

Several tempting stronger claims were excluded: the stock VRS instability increment is disabled; high-RPM windmilling already exists and should not be described as absent autorotation altogether; the tilted-rotor residual does not prove net energy creation; a 24% tandem-rotor experiment does not quantify X1 interference; the current fast-plan guard has a per-root budget and watch fallback; and identical reference/native results can share a physical-model error. Detailed verification preserves the contrary evidence.

## Research and physical validation strategy

Primary sources include NASA/NACA rotorcraft, propeller, variable-mass and 6DOF references; UIUC low-Reynolds-number and propeller data; named motor and engine manufacturer data; measured miniature-turbine and model-helicopter studies; control-theory and official controller implementations; and numerical/contact-engine documentation. The [source index](sources.md) links these to their actual use. Manufacturer or paper measurements are identified by their model, conditions and measurement boundary. Fitted anchors, withheld rows from the same experiment, independent runs and flight validation remain distinct.

For every richer model, predeclare hardware and geometry, mass/CG/inertia, air density/temperature, measurement ports, excitation, sampling, uncertainty, fit/holdout split and claimed operating envelope. Use invariants and manufactured limits first, then matched measurements, then native full-session/platform checks and target CPU traces. A model that cannot be identified or beat the simpler baseline beyond uncertainty should remain an explicitly scoped experiment.

The deliverable records source-supported improvement decisions and the evidence required to implement them. Production repairs, changed-law recordings, complete native qualification, physical measurements and pilot/target acceptance remain implementation work under the existing owners.
