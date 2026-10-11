# D8b-R2 — Pull-up research index

2026-10-11 · **Status: 18 source-based investigations and four numerical investigations completed. Repair implementation and physical validation remain open.**

Owning step: **D8b-R2i**, within the [Ugly Stik pull-up plan, revision 2](../../../UGLY-STIK-PULLUP-PLAN.md). G/A/S/E labels below are local investigation IDs, not new roadmap tracks. The plan owns implementation status.

The research combines official Godot documentation, the original Jensen drawing archived by Outerzone, FAA guidance, NASA reports, UIUC experimental-airfoil resources, and JSBSim/OpenFAST/SciPy references. Each detailed investigation states its question, findings, local applicability, proposed change and limits. Sources were reviewed on 2026-10-11 and are linked beside the claims they support. These are 18 distinct engineering questions, not 18 physical experiments or 18 independent validations of the aircraft.

## Godot: six investigations

Detailed sources and analysis: [Godot report](research-godot.md).

| ID | Question and finding | Effect on the repair plan |
| --- | --- | --- |
| [G01](research-godot.md#g01--simulation-precision-and-the-render-boundary) | Precision: float64 simulation state is upstream of float32 rendering; recorded body-rate departure is not created by render conversion | R2b/f: measure packed state and compare render pose separately |
| [G02](research-godot.md#g02--fixed-tick-input-and-integration-ordering) | Scheduling: fixed input/servo/integration ordering differs from render timing and catch-up limits | R2b/g: tick IDs and explicit load/state timing; no frequency increase as a symptom fix |
| [G03](research-godot.md#g03--physical-key-polling-key-chords-and-input-mapping) | Keyboard: synthetic raw targets exercise shaping but not physical key delivery or ghosting | R2b/h: record raw keys and check the owner's actual key chords |
| [G04](research-godot.md#g04--attitude-interpolation-near-vertical-flight) | Attitude: near-vertical Euler displays cannot replace body rates, quaternions and trajectory evidence | R2b/f: nonsingular loop-plane metrics and matched-pose captures |
| [G05](research-godot.md#g05--replay-determinism-checkpoints-and-source-identity) | Replay: seeded/checkpoint repeatability does not imply cross-engine or cross-platform identity | R2b/g: exact engine, source/configuration/harness fingerprints and replay boundaries |
| [G06](research-godot.md#g06--headless-proof-native-window-proof-and-profiling) | Runtime proof: headless causality and native keyboard/display responsiveness establish different things | R2g/h: separate physics-cost and native usability checks |

## Ugly Stik and aerodynamics: six investigations

Detailed sources and analysis: [aerodynamics report](research-aerodynamics.md).

| ID | Question and finding | Effect on the repair plan |
| --- | --- | --- |
| [A01](research-aerodynamics.md#a01--identify-the-exact-airframe-and-its-evidence) | Identity: the target is the Jensen 60-inch plan; section name, installed masses and numerical throws lack matching specifications | R2c: distinguish original drawing, scan measurements, donor data and estimates |
| [A02](research-aerodynamics.md#a02--reynolds-number-and-a-matching-section-polar) | Polar: estimated Re is about 0.30–0.61 million for 15–30 m/s; no matched Jensen section polar has been identified | R2d: trace the contour and obtain matched data or explicit uncertainty bounds |
| [A03](research-aerodynamics.md#a03--load-factor-accelerated-stall-and-loop-geometry) | Accelerated stall: high speed does not prevent stall under a strong pull; full elevator does not prescribe loop radius | R2b/f: record load factor, entry energy, angle and command/recovery history |
| [A04](research-aerodynamics.md#a04--post-stall-lift-slope-and-roll-autorotation-gain) | Autorotation: its sign can be physical, but the estimated falling lift branch controls the unsupported severity | R2d/f: validate post-stall slope and roll growth, not just CLmax or derivative sign |
| [A05](research-aerodynamics.md#a05--spanwise-separation-and-induced-flow-consistency) | Spatial model: an attached induced-flow map and six strips do not validate separated spanwise flow | R2d/e: separate fixed-polar refinement, recalibration and measured separation progression |
| [A06](research-aerodynamics.md#a06--dynamic-stall-versus-quasi-steady-response-at-pitch-and-roll-rate) | Unsteady loads: local rate-dependent incidence is not separation memory; tail-downwash lag is not wing dynamic stall | R2e: add a continuous separation state only if matched transient evidence requires it |

## Computational simulation and validation: six investigations

Detailed sources and analysis: [simulation report](research-simulation.md).

| ID | Question and finding | Effect on the repair plan |
| --- | --- | --- |
| [S01](research-simulation.md#s01--can-mass-balance-establish-the-full-inertia-tensor) | Inertia: centered CG does not establish products of inertia; virtual ballast dominates the modeled Jxy | R2c: audit installed masses and independently verify full-tensor conventions and bounds |
| [S02](research-simulation.md#s02--which-propeller-effects-seed-the-lateral-departure) | Propulsion: gyro, reaction torque, P-factor and wake are distinct; departure survives removal of gyro and powered propulsion | R2b/f: source moment ledger and paired ablations; no blanket removal of physical effects |
| [S03](research-simulation.md#s03--do-tick-rate-traces-prove-temporal-convergence-of-the-sampled-flight-session) | Time integration: 240/480/960 Hz agreement does not prove RK4 order when sampled policies change too | R2e/g: reference the same hybrid system with fixed boundary maps and common-time metrics |
| [S04](research-simulation.md#s04--is-the-post-stall-result-stable-to-strip-resolution-and-model-uncertainty) | Resolution: discretization uncertainty and constitutive uncertainty require separate sweeps | R2d/e: retain physical inputs during a true convergence study; report recalibration separately |
| [S05](research-simulation.md#s05--what-does-the-scalar-dmxdp--jxx-say-about-nonlinear-stability) | Stability: dMx/dp divided by Jxx is not a full eigenvalue or transient growth rate | R2f: coupled continuous/discrete tangent analysis or mirrored finite perturbations with scaled norms |
| [S06](research-simulation.md#s06--what-evidence-can-identify-and-validate-a-stik-correction) | Identification: a fit to one pull cannot establish general handling validity | R2d/h: independent physical evidence, uncertainty and held-out maneuvers/configurations |

## Four executed numerical investigations

Full methods, controls and reproducible artifacts: [experiment report](research-experiments.md), [native output](supplement.json), [independent reduction](decomposition.json), [source fingerprints](supplement-manifest.json).

| ID | Executed result | Decision |
| --- | --- | --- |
| E01 | Five estimated transition widths preserve helper CLmax≈1.1, but maximum positive dMx/dp varies from 17.1308 to 4.9769 N·m/(rad/s) | Scalar peak matching cannot validate the falling branch; no tested width selected |
| E02 | 3/6/12/24 strips per side with recalibrated attached slopes reduce peak feedback about 14.8%; it remains positive | Resolution alone does not remove the mechanism; fixed-polar convergence remains to be done |
| E03 | Finite differences from ±1e-2 to ±1e-6 rad/s retain the strong positive derivative; spread about 0.00072% | The local derivative is not a differencing-step artifact |
| E04 | At 15.5°, varying separation weights contributes +13.8788 N·m/(rad/s), overcoming −2.7481 from remaining wing terms | Investigate the joined polar's slope and separation response; do not freeze weights in production |

The Python wing reduction agrees with native Godot within 5.33e-10 N·m/(rad/s) at five tested angles. This verifies a force reduction and isolates a model contribution; it is not an independent aerodynamic model. The original 28 session trials and 43 targeted checks are preserved in the [baseline evidence](README.md).

## Consequence for the proposed solution

The strongest supported first candidate is a bounded, evidence-backed revision of the wing's post-peak polar and spanwise separation behavior, after making input history and mass provenance explicit. The research does not select a numerical replacement coefficient, higher tick rate, finer production mesh, extra damping, or dynamic-stall time constant.

Promotion requires mathematical checks, numerical accuracy, defensible aircraft-data bounds, held-out flight/recovery evidence and native keyboard acceptance. Where matched physical evidence is unavailable, candidates remain experimental. No production physics was changed by these investigations.
