# Project technical audit — 2026-10-06

Status: complete. Scope: repository at `eaa8979c7aba2ad5c5eb46e045968c1f3f7cc676`, initially clean. This is an audit, not an implementation plan; no new step-ID namespace is introduced.

## Verdict

**The project has a sound, testable engineering foundation for its early stage. Keep it. The current flight models are not yet validated to the standard needed for a high-quality RC simulator, and the master roadmap needs dependency and scope corrections before being followed as an execution plan.**

The strongest evidence supports the numerical kernel, shared flight/analysis path, data provenance, input safety, scene lifecycle and reproducible delivery. The largest risk is allowing internally consistent tests and parallel feature growth to substitute for reference-aircraft validation. The aerodynamic regime inconsistency is real; several smaller validators and smoke tests also accept invalid evidence. None of these findings establishes a need to replace Godot or rebuild the simulator.

The immediate direction should be: tighten acceptance checks and data validation; close the owner feedback loop; define the minimum state/coupling contract; correct approach-regime behavior; prove one Stik takeoff/landing circuit against independent measurements. Keep new aircraft and elaborate damage/weather work experimental until those dependencies are satisfied.

## Scope and coverage

Reviewed the production Godot app, physics/data and aircraft generator paths, input/UI/audio/render boundaries, test/capture/export/CI infrastructure, main roadmap and decisions, active aircraft/menu/visual/landscape/wind/smoke/crash plans, and the research supporting the next phases. Detailed passes: [physics and aircraft systems](physics.md), [runtime systems](systems.md), [roadmap and research](roadmap.md). The production source contains 159 GDScript files; this audit combines targeted source tracing, the engine's whole-script parse check, runtime tests and independent probes. It is not a claim that every historical research asset or generated mesh vertex was independently reconstructed. The archived three.js build was reviewed as a repository/CI boundary; its legacy browser suite was not rerun.

No production code, physical parameters or plan status was changed. Deliverables are this report, supporting reports/evidence, the research-index entry and a learning record.

## Method and limits

The audit read implementation and current plans, ran the pinned engine and repository checks, inspected rendered evidence, reproduced suspected failures, and challenged findings against counterevidence. Findings were recorded as they became verified. Independent technical passes cover physics, runtime systems, and roadmap/research; the lead consolidates and checks their conclusions. Existing reports are hypotheses, not proof of the current revision.

Severity: **high** means a current correctness or foundational sequencing problem; **medium** means a bounded defect or growth risk; **low** means maintenance friction. Timing is distinct: fix now, gate the next affected milestone, or document/defer. Missing future features are not defects by themselves.

A virtual Linux environment cannot establish real-radio feel, end-to-end physical latency, target-GPU performance, or Windows/macOS behavior. Automated inputs and software-rendered captures verify software paths, not those claims.

## Evidence ledger

- Baseline: clean Git working tree; commit recorded above.
- Full `app/test.sh`: **passed**, exit 0; 159 scripts parsed, 59 GDScript test programs, aircraft contracts, four actual-app trim traces and fixed-input 30/60/144 fps state hashes. Raw output: [test.log](evidence/test.log). No engine errors; nine audio teardown warnings are assessed below.
- All visual phases completed: the first combined command rejected a contaminated L6c log (exit 2); the 64-case L6c phase passed separately against the clean clone in an isolated directory (exit 0). The combined command was not rerun or reported as passing.
- Independent source/roadmap passes, primary-source checks and reproducible mutation/convergence probes are recorded below.

### Executed checks and observed behavior

| Check | Result / scope | Saved evidence |
| --- | --- | --- |
| Full headless suite | Exit 0; math/integration, data, aero/ground/propulsion, four-aircraft handling, fake-radio/input, menus, crash/restart, goldens and contracts. | [Raw suite](evidence/test.log), [machine-readable summary](evidence/summary.json). |
| Render/UI captures before L6c | 46 base images; 66 VQ cases; field error panels; L6b 13 repeated images with matching bytes, 480 tree identities and at most 8 vegetation draws. | [Capture log](evidence/capture.log), [VQ inventory](evidence/visual-quality-run-manifest.json), [tree report](evidence/treeline-review.json). |
| L6c attitude/treeline set | Isolated rerun passed: 64 captures, 8 measured groups, 24-image human kit. Human answers remain pending. | [Failure investigation](evidence/capture-contamination.txt), [isolated run](evidence/capture-l6c-isolated.log), [inventory](evidence/l6c-run-manifest.json), [measurements](evidence/readability-trees.json). |
| Clean-clone release builds | Three packages built; exported Linux executed; macOS universal/signature structure, version fields and all pack contents checked. | [Export log](evidence/export.log). |
| Generated outputs | Seven extra geometry/appearance/physics checks passed, including the missing P-51 CI checks; suite adds further checks. | [Generator log](evidence/generators.log). |
| Actual live render loop | 5.22 s sample, 26 frames; llvmpipe p50 203 ms/p95 236 ms. Simulation advanced slowly under the documented catch-up cap; no simulation fault. | [Frame samples](evidence/live-frametimes.json), [runtime log](evidence/live-render.log). |
| Independent negative/convergence/lifecycle probes | Reproduced the documented acceptance/validator gaps, shaft refinement order and audio teardown behavior. | Scripts and output linked in each finding and supporting report. |

The software-rendered run had a driver VSync warning and ran far below the 20 fps point needed for full-speed simulation with the 12-step cap. This is not evidence of target-GPU failure, and no responsiveness/handling judgment is based on that run. It verifies startup/render/tick/logger plumbing under a constrained renderer. The existing inertia warning is a plausibility comparison against borrowed data, not an engine crash.

Per-aircraft physics benchmarks (µs/tick, best of three runs, shared host):

| Aircraft | Trimmed | Started at α=15° |
| --- | ---: | ---: |
| Stik | 408.1 | 370.3 |
| Extra | 447.9 | 457.2 |
| P-51 | 1,255.8 | 1,186.9 |
| Avanti | 411.9 | 404.4 |

These timings include concurrent audit workload and a pre-existing renderer process. They are exploratory headroom evidence, not a controlled regression comparison or a release performance certificate. Static per-component tables are in the benchmark logs.

I inspected the current [Home](evidence/ui-home-en.png), [pause](evidence/ui-pause-en.png), [pilot flight](evidence/capture-physics.png) and [field](evidence/capture-land-az0-el0.png) images. They show a working shell, visible aircraft and rendered landscape. The aircraft's small projected size and changing backgrounds still require the blinded human attitude task; contrast/pixel counts alone cannot establish whether a pilot reads bank and pitch correctly. Selected images and their manifests are retained here; larger run manifests retain inventories/hashes, not an archived copy of every generated image.

## Verified lead findings

These findings were written as the evidence became available and cross-checked against the supporting passes.

### Confirmed: green tests include a preserved aerodynamic response discrepancy

**Inspected:** `app/tests/test_damping_regimes.gd:17–84`, ROADMAP D11b–e and E0a2. **Importance: high; gate realistic approach/landing acceptance.** `KNOWN_DEFECT = true` checks that the regime-dependent changes remain near their documented values: roll damping ×1.73, pitch damping ×0.28, yaw damping ×0.72, lift slope ×1.34. This is an honest characterization test, not a passing physical-consistency test. Keep it until the deliberate repair, but expose known defects separately in test summaries and require the actual consistency acceptance before declaring the M2 landing model validated. Counterevidence: the discrepancy is already acknowledged and assigned work; it is not concealed or a reason to discard the whole solver.

### Confirmed: generated P-51 sources are current, but CI does not enforce their complete regeneration chain

**Inspected:** `.github/workflows/ci.yml`, `app/test.sh`, geometry and physics generators. **Importance: medium; fix now in build verification.** The workflow checks Stik, Extra and Avanti geometry plus Extra physics; `test.sh` adds Avanti physics and P-51 appearance, but neither runs the P-51 geometry or physics `--check`. Both omitted checks pass independently at this revision (`evidence/generators.log`). Current data are not stale; the risk is a future source edit shipping old generated outputs. Add the two existing commands to the generated-data gate instead of inventing another pipeline.

### Confirmed bug: the app/export trimmed-flight acceptance can pass without a flight or with NaN results

**Inspected:** `app/tests/check_trimmed_flight.py:14–43`, its callers in `app/test.sh` and `app/export.sh`. **Severity: medium; fix now.** Independently reduced a genuine three-second app trace to its initial sample: the check still exits 0. Independently replaced the final altitude, speed, pitch and RPM with `nan`: it again exits 0, because comparisons against NaN are false. Evidence: `evidence/trim-check-mutation.log`. Require finite numeric samples, expected duration/tick count, strict tick/time continuity and sufficient rows before checking trim drift; add these negative cases. This weakens an important packaging/wiring proof. Counterevidence: the full simulation has non-finite guards and separate stepping tests; this does not prove ordinary flight currently emits NaN or fails to advance.

### Confirmed: trace metadata describes a model that is no longer universal

**Inspected:** `app/sim/flight_session.gd:571–595`, `app/sim/trace.gd`, P-51 propulsion data. **Importance: medium; fix now before collecting validation traces.** Every trace says `no propwash`, although the P-51 enables a slipstream increment. Trace rows also combine end-of-step state with start-of-step loads; this latter choice is documented in the header and is not itself a bug, but must be honored by identification tooling. Derive active-model metadata from the loaded configuration, name the canonical-JSON hash convention explicitly (it is not the source file hash), and record enough initial auxiliary state/configuration for the future replay reader. AGENTS still calls the format v2; the implementation is v3. Counterevidence: units, coordinate conventions, aircraft identity, dt and force timing are already present, providing a good basis to extend rather than replace.

### Verified delivery strength: clean-clone exports

`app/export.sh` ran against a fresh local clone of the baseline, with the pinned executable and existing verified template cache. Linux, Windows and universal macOS packages were produced; the Linux binary flew the trimmed-flight smoke, version fields matched, and each pack independently contained its field/tree resources. Raw evidence: `evidence/export.log`. This proves packaging on Linux, not Windows/macOS execution or target-hardware performance. The original workspace's `dist/` was preserved.

### Measured risk: the P-51 costs much more than the reference aircraft

**Inspected:** real-session `bench_physics.gd` runs for each catalog entry, `dynamics.gd:58–76`, `slipstream.gd:35–57`. **Importance: high for headroom planning; target-machine breach unproven.** On this Linux host under concurrent audit work, the Stik measured 408 µs/tick and Extra 448 µs, while the P-51 measured 1,256 µs/tick (about 5.0 ms of CPU work per 60 Hz frame at 240 ticks/s). Its component table measures 239 µs for `Dynamics.loads` in trim versus 45 µs for aero and 18 µs for propulsion individually; the optional slipstream path and composition deserve profiling. These are host measurements, not a prediction of the owner's GPU/frame time. Evidence: `evidence/bench-*.log`. Extend H4/H5 and Gate P to every shipped aircraft/regime; require an explicit budget for opt-in physics before adding it broadly. Preserve GDScript until profiles and the target machine justify changing it. Counterevidence: early P-51 remains experimental, the benchmark accepts aircraft IDs already, and the exact source of the additional cost requires a dedicated slipstream breakdown.

## Cross-domain assessment

| Area | Assessment at this stage | Evidence / next decision |
| --- | --- | --- |
| Repository and architecture | Sound boundaries; retain `app/`, offline generators, source assets and frozen bake-off separation. Generated geometry size is not itself architectural debt. | Catalog, `FlightSession`, `Simulation`, shared `Dynamics`, render `Frames`; clean-clone export. |
| Numerical foundation | Strong verification of the float64 rigid-body kernel. Full-session accuracy must be considered separately from kernel RK4 order. | Analytic free fall, energy/angular-momentum conservation, convergence, finite guards; [physics](physics.md). |
| Aerodynamics | Suitable research scaffold, not an accepted landing/slow-flight model yet. | Explicit D11b defect and independent-aircraft comparison gaps; repair physical causes, not golden expectations. |
| Aircraft systems | Four differentiated models exercise useful seams. Reference confidence has not kept pace with breadth. | Experimental labels, generated numbers, prop/shaft/turbine dispatch; [physics](physics.md). |
| Input / controls | Good raw-axis, arming, disconnect, pause and menu isolation design. Real-radio response still needs measurement. | Injected-event UI/radio tests; [systems](systems.md). |
| Rendering | Appropriate Compatibility foundation; shared field, deterministic shader clock, provenance-aware captures. Visual assets can improve incrementally. | Actual Home, pause, aircraft and field captures; human attitude recognition remains separate. |
| Performance | No evidence for an immediate engine/language rewrite. P-51 cost makes one-aircraft headroom claims insufficient. | Per-aircraft benches; software-rendered live run is unsuitable for target-GPU acceptance. |
| Testing | Broad and meaningful verification, with specific acceptance holes and noisy teardown warnings. | Full test log, mutation probes, rendered captures, export smoke. |
| Documentation / research | Valuable evidence archive, weakened by current-state drift and inconsistent dependencies. | Old shaft/state recommendations and performance numbers coexist with newer implementations; [roadmap](roadmap.md). |
| Master plan | Good destination and engineering principles; not a dependency-consistent execution order as written. | H8/anchors, D11 closure, validation timing, unregistered crash track, over-broad future abstractions. |

## Keep these decisions

- Keep Godot and the Compatibility renderer. The selected engine can run the app, its real input/UI paths and all three export targets; no audited requirement establishes a need to change engine.
- Keep float64 simulation independent of Godot render transforms and built-in contact dynamics. This makes coordinate, precision and test contracts explicit. The positive reason is control of numerical semantics; Godot itself also has a fixed physics tick, so describing all Godot physics as inherently render-frame-synchronized is imprecise.
- Keep the 240 Hz fixed step and render interpolation until numerical/performance evidence justifies a change. Fixed ticks plus interpolated presentation are consistent with [Godot's official interpolation model](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/physics_interpolation_introduction.html).
- Keep known-answer tests, goldens, negative loader tests and actual input-event tests. They address distinct failure modes. Add narrowly targeted missing assertions; do not replace them with a generic test framework.
- Keep provenance and generator-first aircraft authoring. Fix the weak nested validators and missing generator checks before designing a replacement schema.
- Keep the linear aerodynamic oracle as a regression/reference tool while correcting local loads. Its borrowed coefficients are evidence of a candidate model, not measurements of this Stik.
- Keep experimental aircraft available as explicit experiments. Avoid extending their realism promises until their measured envelope and costs justify it.

## Aircraft-specific confidence

| Aircraft | What is supported | What must remain provisional |
| --- | --- | --- |
| Ugly Stik | Measured-plan geometry, consistent inventory/CG, shared flight/mode evaluator, golden regression and comparison with related identified aircraft. | This particular build's mass/inertia/throws/prop installation are not flight-identified. The updated comparison still shows roll response about 2–2.4× faster than related references. Measure the likely causes; do not force a coefficient to match a different airplane. |
| Extra 300S | Source geometry and generated data agree; flown roll/loop/stall/recovery checks exercise the aircraft's own path. | Much of the expected handling is calculated from the same coefficients. EX-09 remains independent contrast, and its full envelope/installation evidence is incomplete. |
| P-51D | Generated geometry/physics agree in independent `--check` runs; model/clearance and flown envelope checks run; shaft, slipstream and asymmetric effects test useful variation. | Scaled full-size references and an estimated giant-scale build are not flight validation. Its greater tick cost, coupled shaft order and transient reaction torque need bounded follow-up. |
| Avanti S | Manual/engine inputs, turbine branch, spool/ram tests, generated data, 30 handling checks and documented sensitivity study. | The neutral point is deliberately anchored to assumed 3% MAC margin at the manual's aft CG, moving wing-body aerodynamic center by 50 mm. This is a disclosed fitted prior, not an independently measured static margin. In-air, fixed-fuel, gear/flaps-up behavior remains the supported scope. |

For the Avanti, I inspected `research/avanti-s/av06/derive_physics.py:271–287` and [its model report](../avanti-s-av06-physics-model.md), including its explicit validation limitation. **Importance: medium fidelity boundary; document now and validate later at AV-01/AV-10/pilot evaluation.** Preserve the visible adjustment and uncertainty range; mark its stability outputs as dependent on that assumption. The report already admits that the anchor is not measured stability, which is the correct interpretation. Do not cite the resulting margin as fresh independent confirmation of the manual or airframe geometry.

## Acceptable limitations and work that can wait

| Limitation | Why acceptable now | Boundary before it becomes unacceptable |
| --- | --- | --- |
| Flat field; trees have no flight collision | Focused reference-flight environment; currently disclosed | Terrain/obstacle scenarios must add a shared float64 contact sampler and explicit obstacle contract. |
| Simple finite crash, freeze and reset | Enough to keep the early flight loop recoverable | M2 needs contact/impact diagnostics; structural failure realism requires material/airframe evidence. |
| No fuel burn, starting procedure, thermal engine model, flaps/retracts or full weather | Planned functionality, not missing foundations by itself | Introduce each with its state, mass/force and replay dependencies; Avanti remains in-air, gear/flaps up. |
| Estimated inertias, aero derivatives and prop data | Labeled and useful for software development | Measure uncertain dominant quantities before fitting handling or claiming training fidelity. |
| Placeholder procedural engine sound | A useful running-engine cue with pure synthesis tests | Near-field control response and propagation must be measured before audio contributes to realism acceptance. The official [generator documentation](https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html) confirms the buffering/latency tradeoff; 22,050 Hz is a reasonable GDScript choice. |
| Auto-zoom and developer overlays | Help a pilot find the airplane and help developers inspect it | Keep aids selectable and test orientation/approach cues with the intended monitor and camera mode. |
| Repeated test assertion helpers and short duplicated world assembly | Low-cost local code, understandable at current scale | Extract only when actual divergence appears; no framework rewrite. |
| Archived three.js prototype | Useful decision history, outside the production runtime | Do not add features there; consider path-filtering its full CI job if routine CI cost becomes material. |

Do not implement speculative platform features merely because they have a roadmap row. Defer a general component-tree migration, generic contributor registry, mod-package system, broad weather model, fragmentation/fire, twin engines, VR and elaborate servo thermal/load behavior until a selected user-visible milestone needs them. Preserve their research. Electric propulsion is a legitimate future RC use case; it need not wait for every optional nitro realism effect, once the shared propulsion/state contract is sound.

## Recommended dependency order

This is a correction to the existing plan, not a replacement multi-year roadmap.

1. **Make evidence trustworthy now.** Repair the trace acceptance false positives, shaft table validation and generator CI omissions; distinguish known-defect characterizations from accepted fidelity. Repair current trace metadata and the few contradictory current-state instructions.
2. **Close the first feedback loop.** Run the owner Gate 2 session with a real radio and monitor. Record aircraft/build, camera mode, setup success, axis direction, latency/frame pacing and specific handling tasks. Measure mass/CG/inertia/throws and prop/ground quantities where available. Reversible research may continue; do not interpret owner unavailability as acceptance.
3. **Settle narrow state semantics before new persistent physics.** Specify continuous vs sampled vs discrete state, RK-stage time, auxiliary rollback, trace/checkpoint layout and replay ownership. Do this before wheel anchors, coupled rotor state, downwash lag, fuel or damage flags. Avoid implementing unused generalized components.
4. **Repair reference-aircraft approach behavior and close every measured derivative.** D11 must account for Clp, Cmq, Cnr and CLα. Match wing/tail contributions without double-counting and retain passivity/convergence tests. A vortex-lattice tool can supply evidence; a new in-house solver is not automatically a prerequisite to a bounded correction.
5. **Complete one trustworthy Stik ground circuit.** Static hold, contact onset, steering/friction, propwash/low-speed control authority, takeoff, flare/landing, reset and circuit replay. Obtain independent thrust/rpm and ground measurements before accepting distance/handling bands. If the comparison field is not at the model's sea-level density, thread a consistent measured density through trim/loads/propulsion before comparing; the complete atmosphere/weather system can remain later.
6. **Measure all active aircraft and then expand.** Gate P should use representative trimmed, stalled, ground and propulsion-heavy cases on the intended slow machine. Choose the next aircraft/system branch from pilot evidence. Promote minimum trim/setup work from M3 when it blocks that loop; advanced servo effects can wait. Split M5 into distinct atmosphere, wind, stalled-flow and aids milestones rather than treating them as one polish batch.
7. **Add crash depth and scenery after contact semantics.** A typed impact snapshot and readable cause are a small useful increment. Wreck handover, material breakage, fragments, replay, fuel/fire and audio propagation have separate prerequisites and should not all be the next “small step.”

Success for the next milestone is a measured, repeatable reference-aircraft loop that the owner can fly and explain. It is not the number of checked plan rows, aircraft, render effects or research pages.

## Additional verified findings and architectural limits

| Finding | Severity / importance | Evidence and consequence | Action and timing |
| --- | --- | --- | --- |
| Shaft power-curve validation accepts coerced string values and missing provenance | Medium, current validator defect | Reproduced with P-51 data; normal `_q`/table rules are stronger than `_shaft`. Current committed data are valid. [Physics B2](physics.md#b2--shaft-power-curve-validation-is-weaker-than-the-general-aircraft-data-contract). | Reuse strict numeric/finite/table provenance checks now. |
| Gear validation tests a bounding box rather than support polygon | Medium, current validator defect | A three-contact fixture accepts a CG outside its support triangle. It can admit a setup that cannot statically support the aircraft. [Physics B3](physics.md#b3--ground-setup-accepts-a-cg-inside-the-gear-bounding-box-even-when-it-is-outside-the-support-polygon). | Use actual support-polygon/barycentric acceptance when validating a statically supported start; add this negative case before broader gear configurations. Do not reject intentionally unsupported in-flight configurations. |
| Full-session shaft dynamics converge at first order in the tested transient | Medium now; high dependency for G2 | Independent P-51 step-halving showed RPM differences 1.516, 0.756, 0.378, 0.189 rpm; the body-only kernel remains fourth-order. [Physics T1](physics.md#t1--the-full-flight-session-is-split-order-time-dependent-rk-stage-loads-are-not-wired-through). | Document split integration now. H8/G2 must define and verify coupling; stage times must reach time-dependent loads before M5. The small observed differences alone do not justify an emergency integrator rewrite. |
| Rotor acceleration reaction is omitted | Medium current model limit | Gyroscopic `ω × h` and steady prop load torque are present; `−dh/dt` from shaft/spool acceleration is not. [Physics B8](physics.md#b8--propeller-and-turbine-spool-acceleration-reaction-is-omitted). | Address G2b with angular-momentum balance and mutation tests; include turbine spool transients and avoid double-counting shaft torque. |
| Static ground hold is approximated by smooth velocity-dependent friction | Accepted current limitation; high before runway-start acceptance | A stationary airplane cannot balance nonzero idle thrust with a friction law that is zero at zero speed. [Physics B4](physics.md#b4--true-ground-stiction-is-not-implemented-so-stationary-idle-aircraft-creep). | Implement/verify stiction or anchors through E3b after state semantics; measure real creep/rolling resistance. |
| Powered/dead-stick performance lacks matched propeller evidence | Medium fidelity limit | Stik uses measured 11×6 data for a 12×6 outside measured RPM; below 1 rpm propeller aerodynamic load vanishes. [Physics B6/B7](physics.md#b6--stik-propeller-coefficients-are-used-well-outside-the-measured-rpm-and-diameter). | Keep estimates labeled. Match measured static thrust/RPM and the relevant operating band before takeoff/climb/glide realism claims; full four-quadrant/2-D tables can follow demonstrated need. |
| Persisted radio-profile validator accepts malformed mappings | Medium robustness gap, bounded today | Duplicate axes, out-of-range centers/endpoints, unknown kind and NaN accepted by a direct probe; wizard-generated profiles are constrained and sim finite guards limit propagation. [Systems SYS-06](systems.md#sys-06--saved-radio-profile-validation-is-structural-but-permissive). | Tighten before profile import/sharing or wider controller support; retain an actionable fallback/error. |
| Exit-time audio warnings | Low test hygiene, not demonstrated gameplay leak | Five real lifecycle cycles returned to 218 nodes; all playback IDs released after an idle second. [Systems SYS-07](systems.md#sys-07--objectdb-exit-warnings-are-transient-audio-teardown-not-repeat-cycle-growth). | Clean fixture shutdown when touching those tests; do not rewrite scene lifecycle. |
| Home/help ground-contact description is stale | Low user-facing inconsistency | `app/ui/home.gd:119` says touching ground restarts; E1/E2 and `test_crash.gd` now distinguish wheel contact from hull/gear collapse. Visible in this audit's Home capture. | State that starts are airborne and landing support is experimental; update paired help/localization strings with the next UI change. |
| Trace CLI accepts negative duration as successful one-row output | Medium automation defect | `--trace=/tmp/openrc-audit-negative.csv --t=-1` exited 0 with one row; [log](evidence/trace-negative-duration.log). `main.gd:444–450` validates neither duration nor achieved ticks/faults. | Reject nonfinite/nonpositive duration; require achieved tick count and no sim fault before success, alongside the checker fix. |

**Important qualification to D11:** derivatives can physically vary with angle of attack. The oracle's borrowed coefficients and the ±15% test band are not laws of aerodynamics. The actionable defect is the unvalidated transition between two incompatible response models in the attached/approach operating region. Closure must explain wing/fin/tail contributions and their supported angle dependence, then set documented acceptance bands. Merely tuning the local model to reproduce an arbitrary oracle, or relaxing the test to the new result, would not establish realism.

## Roadmap issues requiring a decision

Full inspected scope, line references, counterevidence and actions are in [the roadmap audit](roadmap.md).

| Issue | Importance | Correction |
| --- | --- | --- |
| H8 is intended to precede persistent wheel anchors, but recommended order puts E3b first | High | Move the minimum state/replay contract before E3b1; keep implementation bounded to actual consumers. |
| D11 names four failing derivatives but its repair rows do not explicitly close Cnr | High | Name the fin/yaw-damping cause, owner and test; a completed wing correction cannot stand in for that proof. |
| Real ground/prop measurements appear after modeled takeoff/circuit proofs | Medium–high | Permit development with estimates, but move measurement before realism acceptance. Internal hand integrals remain verification. |
| Gate 2 is open while shared physics and several product tracks expand | Medium–high | Declare which work is reversible exploration and which needs pilot/hardware acceptance. Keep the next reference-flight loop narrow. |
| H10, DATA-8 and VLM/AVL can become independent tool/framework projects | Medium | Flat runtime packs are a measured optimization; a contributor framework or v2 component tree needs a concrete next consumer. Choose a proven offline tool or small derivation before building a general aero solver. |
| CR-/Gate CR are unregistered; the crash research index and report 03 are missing | Medium | Repair registry and links now. Do not invent material thresholds to fill a missing evidence document. |
| CR-A packages many effects as “Now”; CR-C only recommends H8 despite persistent damage | Medium | First identify/report impact. Require state/replay/mass semantics before flyable damage; defer the presentation bundle. Effective mass predicts contact response/ranking, not a validated balsa failure threshold. |
| Current knowledge-base snapshots contradict newer implementation and each other | Medium | Reconcile only affected sections before the next task: D11a sensitivity, shaft/slipstream status, split-vs-coupled RPM recommendation and old 501 µs cost. Preserve historical evidence with its revision/date. |

The registry/index is useful and worth maintaining. Adding another audit layer without reconciling the next-step instructions would worsen the problem; use this report to make a short set of decisions, not to create another parallel execution plan.

## Disproved or deliberately downgraded concerns

- The Stik's alleged main-axle mismatch in old E1 research compares two different coordinate origins. Applying the render datum yields the same 0.215 m aft-of-leading-edge position as physics; no geometry fix is warranted ([physics B5](physics.md#b5--the-e1-reports-stik-axle-conflict-is-a-coordinate-datum-misread-not-a-physicsrender-mismatch)).
- Passing the same time to RK stages has no current effect because the production load path ignores time and uses calm, constant-density air. It is a future forcing-interface dependency, not proof that current free-flight trajectories are wrong.
- Exit warnings did not reproduce as cumulative scene/audio leaks.
- Large generated mesh files and repeated small test helpers do not justify a framework rewrite.
- Same-machine fixed-input hashes do not prove physical-radio sampling equivalence or cross-platform bitwise determinism. Existing tolerance goldens already avoid requiring bitwise identity across platforms.
- No GPU, real transmitter, physical airplane or native Windows/macOS run was available in this audit. Their unclosed acceptance gates remain unclosed; successful headless/capture/export checks cannot substitute for them.

### Capture failure investigation: shared log contaminated by an older process

**Inspected:** `app/capture.sh`, `app/tests/capture_runner.py:29–47`, `/proc` file descriptors, the L6c case-31 log. **Importance: medium test-environment robustness; no current app defect established.** The full capture command exited 2 at `l6c-game-ground-climb`: the log contained script errors. A Godot process already running for more than eight hours still had stdout open on exactly that path; `/proc/<pid>/fd/1` and the current log had the same inode. Errors preceded the new run's engine banner, and the new run wrote its successful saved-image line amid those errors. Evidence: [capture-contamination.txt](evidence/capture-contamination.txt). The runner correctly refused contaminated evidence. The per-run lock does not exclude a process that predates or bypasses it, and truncating a log leaves old open descriptors attached. **Action:** prefer unique run/output directories (or fresh log inodes) and process-group cleanup; document failed versus recovered runs explicitly. No other developer's process was terminated. The full 64-case L6c phase subsequently passed in a separate directory against the clean clone; earlier capture phases had passed. Both outcomes are retained, rather than relabeling the first run as successful.


## Reproduction and review handoff

From the repository root, `app/test.sh`, `app/capture.sh` and `app/export.sh` reproduce the standard checks; export to a disposable clone if existing packages must be retained. On a shared workspace, use an isolated clone/output directory for captures. The archived browser suite and native Windows/macOS execution were outside the executed checks.

The diagnostic probes are deliberately outside `app/` and do not become production tests. For example:

```bash
GODOT_AUDIT="$(app/get-godot.sh)"
"$GODOT_AUDIT" --headless --path app --audio-driver Dummy --script "$PWD/docs/research/project-audit-2026-10-06/evidence/physics-validator-probe.gd"
"$GODOT_AUDIT" --headless --path app --audio-driver Dummy --script "$PWD/docs/research/project-audit-2026-10-06/evidence/p51-step-halving.gd"
"$GODOT_AUDIT" --headless --path app --audio-driver Dummy -- --trace=/tmp/openrc-audit-trim.csv --t=3
python3 docs/research/project-audit-2026-10-06/evidence/trim_checker_probe.py /tmp/openrc-audit-trim.csv
```

Runtime/profile/audio reproduction commands are in [systems.md](systems.md). Findings name the existing roadmap steps that should own a repair; this audit introduces no additional execution track. Implement fixes as separate, evidence-bearing changes. Do not mark a physical model validated merely because its regression tests, this report, or a plan row say it is ready.
