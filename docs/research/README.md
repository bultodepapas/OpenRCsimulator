# Research index

`docs/research/` holds the reports that record what was investigated or measured for a step, and the evidence that proves it. This index lists the entry points per track so a newcomer reads two or three documents instead of scanning every evidence folder. New reports are written in English (AGENTS.md rule 7); most reports before 2026-10-06 are in Spanish and are translated when next revised. The [documentation map](../README.md) explains how the whole documentation fits together; [RESEARCH.md](../../RESEARCH.md) at the root is the earlier notebook (everything read before Gate 1 and for plan review #3) and is frozen.

## Two folders, one rule

| Folder | Holds | Example |
| --- | --- | --- |
| `docs/research/` | Reports (`.md`), their sidecar data (`*-validation.json`, `*-metrics.json`, `sources.json`), probes and the evidence of a step (logs, PNG, JSON) | `visual-quality-implementation/L6b/README.md` and its 30 evidence files |
| `research/` (repository root) | Scripts and data of reproducible experiments and of the aircraft measurement pipelines: measure, fit, render, derive | `research/extra-300/ex05/derive_physics.py` generates `app/data/aircraft/gp_extra_300s_60.json` |

Aircraft tracks keep the report here and the scripts, picks and renders under `research/<aircraft>/<step>/`. Engine and feature tracks (menu, smoke, wind, landscape, visual quality, flight robustness) keep report, probes and evidence together here. Both are fine; what matters is that the report links the evidence and the evidence names the step.

Some scripts under `research/` read the gitignored `references/` folder (plans, scans and photos with unknown licenses) and cannot be rerun from a fresh clone. Their reports say so; the measured numbers they produced are committed.

## Whole-project audit

[PT1h code/document reconciliation and rc6 verification](release-readiness/PT1h/README.md) records the 2026-10-08 integration audit. [Tool workflows](../TOOLS.md) index the current commands and distinguish synthetic checks from field measurements.

[Project technical audit — 2026-10-06](project-audit-2026-10-06/README.md): independent code, physics, runtime, tests, export and roadmap review at `eaa8979`; verified findings, counterevidence, saved probes and a corrected dependency order. Supporting reports cover physics, runtime systems and roadmap/research.

The audit is a fixed evidence snapshot. [ROADMAP](../../ROADMAP.md#execution-order-and-release-gates) turns its recommendations into planned work; this does not mark the simulator findings fixed.

## Development workflows

[Graveacre AI-assisted asset workflow — 2026-10-09](graveacre-ai-workflow-2026-10-09.md): the Reddit post, its game/community links and official PixelLab/Retro Diffusion documentation; author claims, access limits and applications to our existing asset pipelines, visual review, parallel work and PT2 pilot feedback.

## Entry points per track

### Turbo Timber Evolution

[TT-00](timber-integration/TT-00/README.md): external Blender/CAD package inventory, reproducible STL and Blender DNA audits, official aircraft/import references and current code seams. The independent [Timber Integration Plan](../TIMBER-INTEGRATION-PLAN.md) owns TT- steps, the curated GLB pipeline, electric-flight prerequisites and later flap/ground validation.

### Desktop delivery

[DT-00](desktop-delivery-investigations/DT-00/README.md): current launch/export audit, fullscreen and DPI/recovery contract, Windows installer and macOS signing/notarization research, measurement protocol and native acceptance limits. The separate [Desktop Delivery Plan](../DESKTOP-DELIVERY-PLAN.md) owns DT- steps and coordinates existing UI-07/09 and visual/physics work.

[DT-00-R1](desktop-delivery-investigations/DT-00-R1/README.md): twelve follow-up investigations covering installer replacement, Mac trust, Linux runtime, fullscreen transactions, DPI/camera, native close/audio, provenance, native testing, performance statistics, settings durability, startup and installed USB radios. Isolated probes reproduce stale-reader settings loss and Git's untracked-file identity gap; revision 2 maps findings to phased acceptance.

[DT-00-R2](desktop-delivery-investigations/DT-00-R2/README.md): twelve further investigations focused on Godot and Apple Silicon M1 onward: actual graphics driver, Retina/MSAA/memory, ProMotion, ARM64/dependencies/OS floor, Spaces/input, trust/updates, thermal soak, USB, CoreAudio, native CI, numerical physics and diagnostics. Static Mach-O inspection and a synthetic checker-contract probe inform revision 3; no native Mac performance is claimed.

### Roadmap knowledge base (all phases)

[roadmap-investigations/README.md](roadmap-investigations/README.md) (plan review #4, 2026-10-06): ten documents that do the research in advance for each phase. 01 numerics, architecture and performance · 02 aerodynamics at RC scale · 03 propeller and propwash · 04 ground handling and collisions · 05 propulsion (glow, gas, electric, turbine) · 06 radio, servos and latency · 07 atmosphere, wind and turbulence · 08 validation and flight testing · 09 aircraft data and pipeline · 10 audio, perception and presentation. Read the phase's document before starting a step.

### Crash and damage

[crash-damage-investigations/README.md](crash-damage-investigations/README.md) indexes reports 01/02/04/05 and the pending material-threshold research (03, owned by CR-07). The [plan](../CRASH-DAMAGE-PLAN.md) starts with a typed contact snapshot and cause; effective-mass ranking is not structural validation.

### Flight model and simulation

Modal reference dashboard: [VAL-3](validation/VAL-3/README.md) provides strict US120/25e reference files, current Godot mode samples, estimated diagnostic bands, explicit unknown tuning history/uncertainty and a stale-output check. Actual Clp mutation and synthetic classification tests remain separate from aircraft validation.

Metamorphic flight checks: [VAL-4](validation/VAL-4/README.md) exercises symmetry, Froude scaling and passive energy through actual session ticks, including servo/downwash timing. Three source mutations are rejected in disposable app copies; the shared simulation is unchanged.

Scale-weighing reduction: [VAL-5a](validation/VAL-5a/README.md) provides offline tare-corrected mass and horizontal CG with calibration/datum covariance, strict input validation and synthetic verification. Real aircraft weighing remains VAL-5.

Swing-test reduction: [VAL-6a](validation/VAL-6a/README.md) provides offline bifilar/compound inertia estimates, common-axis rig tare, shared-input uncertainty and a synthetic plank check. Real rig and aircraft measurements remain VAL-6.

Static propeller readings: [VAL-7a](validation/VAL-7a/README.md) reduces matched thrust/RPM and optional torque into Ct, Cp and shaft power with uncertainty. Ideal-disc power stays distinct; real static tests and transient lag remain VAL-7.

Propeller source normalization: [G1a1](propulsion/G1a1/README.md) imports exact-hash UIUC static/tunnel files as sorted knots with complete source-line provenance, explicit deduplication and unknown diameter/tunnel RPM retained. Four primary-source readbacks and synthetic defect checks verify the tool; matched intended-propeller evidence remains open.

Propeller operating-range diagnostics: [G1b1](propulsion/G1b1/README.md) audits Ct/Cp queries from exact-input-identified traces, separating table extrapolation, documented source gaps, stopped/reverse flow and unknown coverage. Six session flights and direct engine-query comparisons verify the offline tool; online counters and matched-propeller validation remain open.

Throttle-step readings: [VAL-7b](validation/VAL-7b/README.md) reduces recorded RPM crossings into lag/delay diagnostics, retaining residuals, sampling limits and provenance. [VAL-7c](validation/VAL-7c/README.md) adds explicit opt-in uncertainty with shared-input covariance and screens unresolved crossings; correlated acquisition models and physical measurements remain open.

Ground-run video: [VAL-8a](validation/VAL-8a/README.md) reduces original capture-frame annotations and surveyed positions into duration, distance and mean along-runway ground speed, retaining shared-event/calibration uncertainty and exact input hashes. Physical flights and simulator comparisons remain VAL-8.

Complete-roll video: [VAL-8b](validation/VAL-8b/README.md) reduces verified full-turn annotations to mean period and signed cycle-average rate with shared timing covariance and exact clip/input hashes. It does not infer instantaneous body rate or roll damping; physical observations remain open.

| Read first | Then | Evidence |
| --- | --- | --- |
| [ugly-stik-rudder-audit.md](ugly-stik-rudder-audit.md) (the symptom: rudder over-authority) | [flight-model-robustness-audit.md](flight-model-robustness-audit.md) (the whole-model audit) → [flight-repair-implementation.md](flight-repair-implementation.md) (what was changed and tested, 2026-10-06) → [flight-robustness/repair-diagnostics.md](flight-robustness/repair-diagnostics.md) → [aero-consistency/D11d](aero-consistency/D11d/README.md) (D11d wing induced-flow map, 2026-10-07) → [aero-consistency/E0a2a](aero-consistency/E0a2a/README.md) (E0a2a tail downwash split, 2026-10-07) → [aero-consistency/E0a2b](aero-consistency/E0a2b/README.md) (E0a2b downwash lag, 2026-10-07) → [aero-consistency/D11f](aero-consistency/D11f/README.md) (D11f yaw damping) → [oracle data decision brief](aero-consistency/oracle-data-decision.md) → [aero-consistency/D11g](aero-consistency/D11g/README.md) (D11g the Stik's own rate derivatives; decision made) | [rudder-audit/](rudder-audit/) (19 experiments), [flight-robustness/](flight-robustness/) (probes, fuzz, eigenmodes, logs); [research/sensitivity/results.md](../../research/sensitivity/results.md) (D10 sweep and the UMN Ultra Stick 120 comparison); [research/flight-modes/](../../research/flight-modes/) (linearized modes) |

Trace integrity: [C7-R1](trace-integrity/C7-R1/README.md) hardens CLI duration/failure exits and the trimmed-flight checker; records regression mutations and exported-flight comparisons. [C7-R2](trace-integrity/C7-R2/README.md) defines active-model headers, state layouts and recording-start auxiliary snapshots.

Trim integrity: [D4-R2](trim-integrity/D4-R2/README.md) closes nonfinite false convergence and invalid linear-system acceptance, with exact fleet preservation and isolated regression evidence.

Playable wind: [uniform wind and repeating gusts](wind-implementation/README.md) integrates four-aircraft air-relative physics, precise Home conditions, explicit v4 telemetry, v2 weather checkpoints, FPS reproducibility, EN/ES rendered proof and native Linux source/export parity. [M5-W04a](wind-implementation/M5-W04a/README.md) adds seeded temporal OU turbulence, float64 Gaussian sampling, exact RNG/filter rollback/replay, v5 telemetry and independent statistical/PCG checks. Atmosphere/pilot validation remains open.

Radio calibration: [D6b-R1](radio-input/D6b-R1/README.md) validates persisted channel mappings and device identity, rejects malformed profiles whole, preserves files on refused saves and verifies safe replug through the real scene.

Calibration rearming: [D6b-R2](radio-input/D6b-R2/README.md) requires fresh finite low-throttle evidence after profile replacement, preserves raw-axis diagnostic history, and records private fault tests, real-session checks and paired event-cost observations.

Radio diagnostics: [F1](radio-input/F1/README.md) adds a standalone input report with per-device connection history, axis ranges and observed callback spacing; includes fake-device and CLI proof. Actual USB timing and physical-radio compatibility remain separate measurements.

Loader cost: [DATA-2b](aircraft-validation/DATA-2b/README.md) attributes the remaining startup cost and stops repeated induced-flow inversions after exact float64 midpoint stagnation; paired whole-model and refusal comparisons retain identical bytes.

Steady shaft integrity: [G2-R1](propulsion/G2-R1/README.md) rejects unbracketed or nonfinite RPM equilibria and verifies unchanged fleet trims and flight endpoints.

Aircraft input validation: [D1-R2](aircraft-validation/D1-R2/README.md) enforces finite numeric shaft tables, units and provenance; records malformed-input and session-reload checks. [D1-R3](aircraft-validation/D1-R3/README.md) replaces the gear bounding-box check with the resting-facet support polygon (taildraggers at their three-point attitude).

Solved stall-envelope integrity: [D1-R4](aircraft-validation/D1-R4/README.md) rejects unreachable, nonfinite or collapsed derived transitions, preserves valid fleet models and verifies refused reloads and solver faults.

Wing-strip calibration integrity: [D1-R5](aircraft-validation/D1-R5/README.md) rejects unreachable or nonfinite induced-flow calibration before deriving offsets/downwash, with exact fleet parity and failed-reload proof.

Aircraft loading cost: [DATA-2a](aircraft-validation/DATA-2a/README.md) bounds the existing discrete stall-peak search while preserving exact solved angles and full loader results. Paired fleet timings improve approximately eightfold; DATA-2's 15 ms whole-load target remains open.

Aircraft input identity: [DATA-3](aircraft-validation/DATA-3/README.md) hashes the exact loaded bytes, distinguishes semantic hashes in trace metadata v2 and defines explicit legacy/file-verification behavior. Includes late-digit/line-ending regressions, mutation proof and unchanged fleet traces.

Aircraft structural preflight: [DATA-4a](aircraft-validation/DATA-4a/README.md) adds a v1 JSON Schema and CI checks against the real loader, including valid optional/null cases and malformed quantities. [DATA-4b](aircraft-validation/DATA-4b/README.md) adds numeric boundaries, feature combinations and a clean incidence-rejection diagnostic. Physical cross-field checks remain runtime-only; the bounded corpus does not close DATA-4's remaining mutation-equivalence coverage.

Generated-output freshness: [DATA-1](aircraft-validation/DATA-1/README.md) adds the P-51 generation chain to CI, with five stale-copy rejection cases in a fresh clone.

Simulation state and headroom: [H4/H5](simulation-state/H4-H5/README.md) profiles all aircraft and measures behavior-preserving optimizations; [H6](simulation-state/H6/README.md) enforces math routing; [H7](simulation-state/H7/README.md) checks adjacent-float sensitivity and branch decisions; [H8a](simulation-state/H8a/README.md) verifies RK stage time; [H8](simulation-state/H8/README.md) defines complete checkpoints and rollback; [H8-R1](simulation-state/H8-R1/README.md) verifies fresh-owner continuation and rejects invalid clocks/derived inverses before restoration; [H9](simulation-state/H9/README.md) defines stamped tolerance replay; [H9-R1](simulation-state/H9-R1/README.md) rejects nonfinite live state, overflowing clocks and mismatched checkpoint streams; [H10](simulation-state/H10/README.md) records the conditional interface decision; [H11](simulation-state/H11/README.md) bounds contact stability and accuracy. [Gate P](simulation-state/Gate-P/README.md) measures an isolated native slipstream kernel against the GDScript oracle and the whole-fleet budget; [H12](simulation-state/H12/README.md), [H13](simulation-state/H13/README.md) , [H14](simulation-state/H14/README.md) and [H15](simulation-state/H15/README.md) make local-strip aero, slipstream, tilted-shaft propulsion and the attached-flow path allocation-free with exact trajectories.

M2 propwash: [E0b1](propwash/E0b1/README.md) independently verifies the existing ideal actuator-disc wake, its operating-point limits and conservation laws; [E0b2](propwash/E0b2/README.md) derives the Stik hub and neutral tail footprints with a freshness check; [E0b3a](propwash/E0b3a/README.md) reconciles the wash/free-tail law and session downwash lag; [E0b3b](propwash/E0b3b/README.md) adds exact neutral chord profiles, smooth occupancy and reverse-flow cutoff; production Stik remains off pending calibration and cost. The dense comparison records a large nonzero-swirl centroid error for E0b6. [E0b4](propwash/E0b4/README.md) records source-audited wash/coverage sensitivity, 581 fixed-condition checks and 33 mode solves; donor-model transfer is not Stik calibration. [E0b5](propwash/E0b5/README.md) adds a continuous axial-speed lag with RK-stage coupling, checkpoint/rollback proof and exact frame-rate hashes; geometry remains instantaneous and production stays off. [E0b6](propwash/E0b6/README.md) verifies distributed swirl, torque/sign/continuity and a source-audited uncertainty sweep; calibration and enabled-path performance remain open. [E0b6p](propwash/E0b6p/README.md) removes per-node force-helper allocations with exact sampled equivalence and a 3.76–4.31× correction speed-up; the whole-tick budget remains unmet. Its [complete native wake probe](propwash/E0b6p/native/README.md) preserves accuracy and trajectories, but still misses the whole-tick budget; production remains GDScript. The [whole-tick and native-phase attribution](propwash/E0b6p/attribution/README.md) verifies active timer equivalence, separates decoding from swirl computation and bounds the value of decoding work. The [single-lookup decoder](propwash/E0b6p/decoder/README.md) retains a measured local saving with exact load/flight output and 165 field-contract checks; whole-flight budget acceptance remains open. The [stage-local sharing comparison](propwash/E0b6p/stage-sharing/README.md) verifies 1,216 exact loads and 30 exact flights in both backends, but retains the candidate outside production because whole-tick gains are inconsistent and reverse cutoff regresses. The [prepared native-model experiment](propwash/E0b6p/prepared-model/README.md) adds copied model snapshots, generation-based invalidation and lifecycle refusal tests; two exact paired runs reduce active swirling cost, but 515–614 µs/tick still misses the budget and production remains unchanged. The [prepared-path attribution](propwash/E0b6p/prepared-cost/README.md) separates whole-tick adapter/non-wake cost and native static/dynamic validation, marshalling, axial loads and swirl; two exact trajectory runs and strict counter checks retain the budget and integration gates.

The [nested aero/simulation attribution](propwash/E0b6p/dynamics-cost/README.md) separates wing/tail loads, validation, RK arithmetic, rigid-body work and callback/checkpoint costs. Two original-buffer comparisons and 24 rejected report corruptions select wing-loop lookup hoisting as the next experiment; production and acceptance gates remain unchanged. The [wing-loop experiment](propwash/E0b6p/wing-loops/README.md) then preserves exact loads and 30 trajectories in each of three runs, but retains the combined change outside production because whole-flight gains are inconsistent. The next test separates wing-helper lookup hoisting from induced-map row offsets.

The [E0b7 field-observation preparation](propwash/E0b7/README.md) provides a nose-unloading/taxi-blip/takeoff-swing reducer and collection card with explicit sample error bounds, source hashes and calibration/held-out partitions. Synthetic and malformed-input checks verify the offline tool; actual observations, coefficient fitting and Stik wash enablement remain separate.

M2 ground handling: [landing-gear-contact-e1.md](landing-gear-contact-e1.md) (E1 spring-damper gear contacts, 2026-10-06) → [ground-friction-e2.md](ground-friction-e2.md) (E2 tyre friction, nose-wheel steering, tip-over, figure-eight taxi, 2026-10-06) → [ground-surfaces-e3a.md](ground-surfaces-e3a.md) (E3a runway, mown and rough surfaces under the wheels, 2026-10-06) → [ground-contact/E3b1](ground-contact/E3b1/README.md) (E3b1 per-wheel stiction anchors, 2026-10-07) → [ground-contact/E3b2](ground-contact/E3b2/README.md) (E3b2 runway start in static equilibrium, 2026-10-07) → [ground-contact/E3b3](ground-contact/E3b3/README.md) (E3b3 takeoff roll against a 1-D model integral, 2026-10-07) → [ground-contact/E1b](ground-contact/E1b/README.md) (E1b continuous touchdown damping, 2026-10-07).

Runway-start numerical integrity: [E3b2-R1](ground-contact/E3b2-R1/README.md) rejects nonfinite and wrong-sized Newton residuals, invalid operating inputs and linear-solve overflow while preserving valid static equilibria.

Taildragger breadth: [E5a](ground-contact/E5a/README.md) reviews the existing P-51 contacts and adds generated Extra 300S wheel contacts, with static moment balance, steering/component ground-loop signs, real-session refinement and isolated fault detection. Independent pilot contrast remains open.

Nose-over mechanics: [E5b](ground-contact/E5b/README.md) separates tail-up pitch reversal from three-point tail lift, verifies both against rigid contact moments, and exercises synthetic resistance patches. Numerical and fault-detection evidence does not calibrate real soft ground.

Experimental landing baseline: [E3c1a](ground-contact/E3c1a/README.md) commands approach, flare and idle rollout through the real session; measures every wheel's contact speed and runway containment, stable stopping and 240/480 Hz refinement. Propwash acceptance, the full circuit and pilot validation remain separate.

Experimental continuous circuit: [E3c2a](ground-contact/E3c2a/README.md) flies from an idling runway start through takeoff, the full pattern, the E3c1a landing handoff and an anchored idle stop; both headings, 240/480 Hz refinement, every-tick v3 trace and corruption checks. Rendered acceptance, physical measurements and PT2 remain open.

Manual circuit trial: [PT2 preparation](ground-contact/PT2/README.md) identifies the frozen Linux build, provides launch/recording and diagnostic instructions, and retains fresh export-smoke evidence. Owner flight and independent physical acceptance remain pending.

Rendered circuit review: [E3c2b](ground-contact/E3c2b/README.md) captures twelve recorded stages in production pilot/inspection views, checks actual poses, hinges, cameras and clocks, and preserves a repeatable [HTML kit](ground-contact/E3c2b/index.html). No dynamics replay or physical/readability acceptance is implied.

Full-circuit regression: [E4a](ground-contact/E4a/README.md) replays a saved 28,861-tick experimental circuit from frozen applied controls with H9 tolerances, complete sampled state and real crash guards. Rolling-resistance and anchor-stiffness changes are detected; physical and release acceptance remain open.

Full-circuit numerical sensitivity: [E4b](ground-contact/E4b/README.md) measures joint adjacent-float `sin`/`atan2` perturbations in both directions against E4a. Errors stay below 0.00401% of H9 tolerance with matching selected branches/modes; a deliberate branch change is detected despite identical state. Native-platform and physical acceptance remain open.

Plans: [FLIGHT-MODEL-ROBUSTNESS-PLAN](../FLIGHT-MODEL-ROBUSTNESS-PLAN.md), [RUDDER-REPAIR-PLAN](../RUDDER-REPAIR-PLAN.md), ROADMAP M1.

### Ugly Stik

| Topic | Read first | Then |
| --- | --- | --- |
| Sources and local references | [ugly-stik-resources.md](ugly-stik-resources.md) | [ugly-stik-sources.md](ugly-stik-sources.md), [ugly-stik-local-audit.md](ugly-stik-local-audit.md), [ugly-stik-new-files.md](ugly-stik-new-files.md) (with [-cad](ugly-stik-new-files-cad.md) and [-visual](ugly-stik-new-files-visual.md)), [aircraft-reference-index.md](aircraft-reference-index.md) (all aircraft) |
| Ten investigations before modelling | [ugly-stik-investigations/README.md](ugly-stik-investigations/README.md) | 01-03 geometry, 04-06 components, 07 CAD, 08 plan metrology, 09 export, 10 screen readability; `evidence/` |
| Model versions | [ugly-stik-model-v4.md](ugly-stik-model-v4.md) (current geometry v3 + finish v4) | [v1](ugly-stik-model-v1.md) ([rig](ugly-stik-model-v1-rig.md), [calibration](ugly-stik-model-v1-calibration.md), [visual](ugly-stik-model-v1-visual.md)), [v2](ugly-stik-model-v2.md), [review v2](ugly-stik-model-review-v2.md), [v3](ugly-stik-model-v3.md) ([metrology](ugly-stik-model-v3-metrology.md), [wing](ugly-stik-model-v3-wing.md), [installation](ugly-stik-model-v3-installation.md), [readability](ugly-stik-model-v3-readability.md)), [v4 controls](ugly-stik-model-v4-controls.md), [v4 equipment](ugly-stik-model-v4-equipment.md), [engine v5](ugly-stik-engine-v5.md) (+ [evidence](ugly-stik-engine-v5-evidence/)), [revalidation 2026-10-05](ugly-stik-revalidation-2026-10-05/) |
| Finish and tooling | [ugly-stik-visual-photo-brief.md](ugly-stik-visual-photo-brief.md) | [ugly-stik-visual-investigations/](ugly-stik-visual-investigations/README.md) (01-10), [ugly-stik-tooling-investigations/](ugly-stik-tooling-investigations/README.md) (01-10) |

Scripts, captures and galleries: [research/ugly-stik/](../../research/ugly-stik/) (`model-v1` … `model-v4`, [model-v4/README.md](../../research/ugly-stik/model-v4/README.md)). Plans: [UGLY-STIK-PLAN](../UGLY-STIK-PLAN.md), [UGLY-STIK-VISUAL-PLAN](../UGLY-STIK-VISUAL-PLAN.md).

### Extra 300S

| Read first | Then | Evidence |
| --- | --- | --- |
| [extra-300-family-research.md](extra-300-family-research.md) (which Extra and why) | [extra-300-resources.md](extra-300-resources.md), [extra-300-round2.md](extra-300-round2.md), [extra-300-photo-investigation.md](extra-300-photo-investigation.md), [extra-300-integration-audit.md](extra-300-integration-audit.md) (what a second aircraft needed from the app), [extra-300-model-v1.md](extra-300-model-v1.md) (metrology and preview), [extra-300-visual-review-v1.md](extra-300-visual-review-v1.md) | [research/extra-300/](../../research/extra-300/) (`ex01` metrology, `ex02` captures, [`ex05/derivation.md`](../../research/extra-300/ex05/derivation.md) physics) |

Shared tooling investigations for the Extra and the Stik: [extra-aircraft-tooling/README.md](extra-aircraft-tooling/README.md). Plan: [EXTRA-300-PLAN](../EXTRA-300-PLAN.md).

### Avanti S

| Read first | Then | Evidence |
| --- | --- | --- |
| [avanti-s-family-research.md](avanti-s-family-research.md) (variant and turbine) | [avanti-s-resources.md](avanti-s-resources.md), [avanti-s-turbine-research.md](avanti-s-turbine-research.md), [avanti-s-integration-audit.md](avanti-s-integration-audit.md), [avanti-s-av01-metrology.md](avanti-s-av01-metrology.md), [avanti-s-controls-and-installation.md](avanti-s-controls-and-installation.md), [avanti-s-geometry-followup.md](avanti-s-geometry-followup.md), [avanti-s-av02-preview.md](avanti-s-av02-preview.md); physics: [requirements](avanti-s-av05-physics-requirements.md) → [turbine dynamics](avanti-s-av05-turbine-dynamics.md), [airframe data](avanti-s-av06-airframe-data.md), [aero references](avanti-s-av06-aero-references.md) → **[physics model and validation](avanti-s-av06-physics-model.md)** | Contour refinement, in order: [transparency comparison](avanti-s-transparency-comparison.md) → [refinement](avanti-s-contour-refinement.md) → [v3](avanti-s-contour-refinement-v3.md) → [new angles](avanti-s-new-angles.md) ([sources](avanti-s-additional-angle-sources.md)) → [user profile](avanti-s-user-profile.md) → [refinement v4](avanti-s-refinement-v4.md) (latest). Scripts and viewers: [research/avanti-s/](../../research/avanti-s/) (`av01`, `av02`, `alignment`, `refinement`, `new-angles`, `user-profile`, `refinement-v4`) |

Plan: [AVANTI-S-PLAN](../AVANTI-S-PLAN.md).

### P-51D

| Read first | Then | Evidence |
| --- | --- | --- |
| [p51-family-research.md](p51-family-research.md) (why a 1/4-scale P-51D for 120 cc), [p51-flight-realism.md](p51-flight-realism.md) (physics cross-checked against NACA and RC-class data: sources, 22 corrections, flown envelope, open uncertainties) | [p51-silhouette-review-v1.md](p51-silhouette-review-v1.md) (dimensions measured by silhouettes over the AN 01-60-3 three-view and the owner's photo), [p51-visual-review-v1.md](p51-visual-review-v1.md) (shapes and details, 18 ranked findings), [p51-visual-review-v2.md](p51-visual-review-v2.md) (closure of V01-V10: before/after per step, status of the 18 findings, open items) | [research/p51/](../../research/p51/): [`p51-02/silhouette/README.md`](../../research/p51/p51-02/silhouette/README.md) (the silhouette method), [`p51-05/derivation.md`](../../research/p51/p51-05/derivation.md) (physics), [`p51-06`](../../research/p51/p51-06/README.md) (propeller calibration, engine anchor), [`p51-08`](../../research/p51/p51-08/README.md) (envelope bands), [`p51-13`](../../research/p51/p51-13/README.md) (section, spanwise stall) |

Plans: [P51-PLAN](../P51-PLAN.md), [P51-VISUAL-PLAN](../P51-VISUAL-PLAN.md).

### Menus and product shell

Experimental Stik runway delivery: [UI-06a session and trace contract](menu-investigations/UI-06a/README.md), [UI-06b Home and preferences](menu-investigations/UI-06b/README.md), [UI-06c export proof and pilot card](menu-investigations/UI-06c/README.md). The [scoped runway plan](../RUNWAY-START-PLAN.md) owns completion; physical pilot acceptance remains separate.

[UI-06a-R1](menu-investigations/UI-06a-R1/README.md) repairs checkpoint replay headers that inherited the destination flight's launch origin; physics-only checkpoints now declare that origin unknown.

[UI-06c-R1](menu-investigations/UI-06c-R1/README.md) refreshes the three-platform packages after that repair, verifies each compiled pack and repeats the native Linux runway smoke against a frozen source snapshot.

[menu-investigations/README.md](menu-investigations/README.md): 25 numbered investigations (01-22, 24, 25; number 23 is a probe only, explained in the README), Godot probes under `probes/`, a contrast checker and `sources.json`. Start with [02 input focus and radio isolation](menu-investigations/02-input-focus-radio-isolation.md). Plan: [MENU-PLAN](../MENU-PLAN.md).

### Visual quality and landscape

| Topic | Read first | Then |
| --- | --- | --- |
| Landscape research | [landscape-research.md](landscape-research.md) | [landscape-investigations/README.md](landscape-investigations/README.md) (01 sky … 11 wind ambience) |
| Visual-quality direction and tools | [visual-quality-tools-2026-10-05.md](visual-quality-tools-2026-10-05.md) | [visual-quality-baseline-2026-10-05/](visual-quality-baseline-2026-10-05/README.md), [visual-quality-round2/](visual-quality-round2/README.md) (native rendering tricks, textures, profiling, a Godot probe), [visual-quality-supplement-2026-10-06.md](visual-quality-supplement-2026-10-06.md) (+ [plugins](visual-quality-supplement-plugins-2026-10-06.md)), the owner's input ([visual](visual-quality-user-input-2026-10-06.txt), [assets](asset-sources-user-input-2026-10-06.txt)) |
| Asset sources | [asset-sources-catalog-2026-10-06.md](asset-sources-catalog-2026-10-06.md) | [asset-audio-animation-sources-2026-10-06.md](asset-audio-animation-sources-2026-10-06.md), [tree-resource-review-2026-10-06/](tree-resource-review-2026-10-06/README.md) |
| Trials | [material trial](visual-quality-material-trial-2026-10-06.md), [nature trial](visual-quality-nature-trial-2026-10-06.md) | Projects under [research/visual-quality/](../../research/visual-quality/) |
| Implementation evidence, one folder per step | [VQ-01a](visual-quality-implementation/VQ-01a/README.md), [VQ-01b](visual-quality-implementation/VQ-01b/README.md) (with [visual references](visual-quality-implementation/VQ-01b/REFERENCES.md)), [L5](visual-quality-implementation/L5/README.md), [L6a](visual-quality-implementation/L6a/README.md), [L6b](visual-quality-implementation/L6b/README.md), [L6c](visual-quality-implementation/L6c/README.md) | Each README states what was measured, how, and what it does not prove (software rendering verifies the protocol, not target-GPU performance) |
| Phased improvement proposal (2026-10-07): ground colour and anti-tiling, tree shading, field surfaces, horizon, sky, near field | [landscape-improvement-2026-10-07/](landscape-improvement-2026-10-07/README.md) | Reports 01–04 inside; measured problems in [scenery 05](scenery-investigations/05-landscape-image-review.md); Phases 0–4 [implemented and measured](landscape-improvement-2026-10-07/implementation/README.md) |
| L9c / improvement Phase 4 follow-up: field surfaces in the ground pass | [L9c evidence](visual-quality-implementation/L9c/README.md) | Bounded rectangle batch, custom-field fallback, edge/priority/repeat checks, unchanged physics/readability; shimmer acceptance open |
| L9c-R1: stripe sampling reference | [L9c-R1 evidence](visual-quality-implementation/L9c-R1/README.md) | Stripe-only camera-motion error, 8×/16× references, fixed world-space inset, repeat and raw/zero-detail controls; bounded regression verified |
| L10a: calm windsock scale cue | [L10a evidence](visual-quality-implementation/L10a/README.md) | Sourced dimensions, validated optional field cue, calm cloth geometry, repeated/scenery captures, unchanged physics and exported-pack verification |
| L10b: pilot station | [L10b evidence](visual-quality-implementation/L10b/README.md) | Bounded optional cue, open-rear geometry, grass exclusion, clear pilot threshold views, repeat/scenery captures and isolated regression |
| L7 / improvement Phase 5: far forest, continuous visual hills and visibility presets | [L7 evidence](visual-quality-implementation/L7/README.md) | Integer profile, preserved near-tree identities, topology, capture A/B, readability and pack checks |
| L4b / improvement Phase 6 and L15d rendering: sky and cloud shadows | [L4b evidence](visual-quality-implementation/L4b/README.md), [L15d](visual-quality-implementation/L15d/README.md) | Legacy parity, repeated production captures, density/projection probe, readability, pack checks and obsolete-output cleanup |
| L11a / improvement Phase 7: near grass and reused flowers | [L11a evidence](visual-quality-implementation/L11a/README.md) | Integer placement, clipping, shared ground colour, local FLIP/seam mutation, wind/fade captures, unchanged readability and pack checks |
| L15b / improvement Phase 8 preparation: rooted tree sway | [L15b evidence](visual-quality-implementation/L15b/README.md) | Repeated motion captures, calm parity, GPU root/wrap probes, expanded bounds, unchanged flight/readability and export checks; M5 integration pending |

Plans: [VISUAL-QUALITY-PLAN](../VISUAL-QUALITY-PLAN.md), [LANDSCAPE-PLAN](../LANDSCAPE-PLAN.md). Tree tooling: [tools/trees/README.md](../../tools/trees/README.md).

### Scenery and field life

| Topic | Read first | Then |
| --- | --- | --- |
| Props, cars, buildings, people, animals: sources and licenses | [01 prop asset sources](scenery-investigations/01-prop-asset-sources.md) | [asset-sources-catalog-2026-10-06.md](asset-sources-catalog-2026-10-06.md) |
| Flowers, bushes, motion, ambient sound, birds | [02 flora and ambience](scenery-investigations/02-flora-and-ambience.md) | [landscape 05 grass](landscape-investigations/05-grass-rendering.md), [11 wind ambience](landscape-investigations/11-wind-animation-ambience.md) |
| Club layout rules (AMA, BMFA, DMFV, FAI), markings, shelters, photo references | [03 field layout references](scenery-investigations/03-rc-field-layout-references.md) | [landscape-research.md](landscape-research.md) |
| Mesh merging, grounding, depth precision, motion, prior art | [04 Godot techniques and prior art](scenery-investigations/04-godot-techniques-and-prior-art.md) | — |
| What the landscape looks like today, measured (for the landscape track) | [05 landscape image review](scenery-investigations/05-landscape-image-review.md) | — |
| Implementation evidence, one folder per step | [SC-01](scenery-implementation/SC-01/README.md) (probe and style bake-off: merging, turbine depth, shadow quads, the ground bug, model sizes), [SC-03](scenery-implementation/SC-03/README.md) (the built scenery: captures, budgets, readability, tests), [SC-25](scenery-implementation/SC-25/README.md) (runway scenario: automatic takeoff captures, sync checks, run comparison) | Scripts in [research/scenery/sc01/](../../research/scenery/sc01/); llvmpipe numbers, not GPU performance |

Plan: [SCENERY-PLAN](../SCENERY-PLAN.md).

### Smoke

[rc-exhaust-smoke.md](rc-exhaust-smoke.md), then [smoke-investigations/README.md](smoke-investigations/README.md) (01-12) and the isolated emission experiment in [godot-evidence/](smoke-investigations/godot-evidence/README.md). Plan: [SMOKE-PLAN](../SMOKE-PLAN.md).

### Wind

[wind-physics-primary-sources.md](wind-physics-primary-sources.md), [wind-godot-integration.md](wind-godot-integration.md) (code audit; written before the 2026-10-06 flight repair, re-read against `physics/dynamics.gd` before W01), [wind-investigations/README.md](wind-investigations/README.md) (01-12). Plan: [WIND-PLAN](../WIND-PLAN.md).

### Cross-aircraft

[aircraft-reference-index.md](aircraft-reference-index.md): the index of the owner-supplied local references per aircraft identity (the files themselves are local only).

## Naming

Observed and kept:

| Pattern | Use | Example |
| --- | --- | --- |
| `<track>-<topic>.md` | A report | `extra-300-integration-audit.md` |
| `<track>-model-v<N>[-<part>].md` | A model revision and its parts | `ugly-stik-model-v3-wing.md` |
| `<track>-<topic>-YYYY-MM-DD.md` | A dated snapshot that will be repeated | `visual-quality-tools-2026-10-05.md` |
| `<track>-investigations/NN-<topic>.md` | Numbered research rounds, with a README that lists them | `landscape-investigations/04-trees-and-impostors.md` |
| `<report>-validation.json`, `-metrics.json`, `-checks.json` | Sidecar data of a report, named after the report | `avanti-s-av02-validation.json` |
| `<area>-implementation/<STEP-ID>/` | Evidence of one step, uppercase ID as in the plan | `visual-quality-implementation/L6b/` |
| `research/<track>/<step-id>/` | Scripts and data of a step, lowercase | `research/extra-300/ex05/` |

## Adding research

1. Write the report in `docs/research/` with the name pattern above, in one language, with date, sources (and their licenses), what was done, what came out, what it does not prove, and the command that reproduces it when one exists.
2. Put the evidence next to it or in the step's evidence folder; put scripts and raw data under `research/<track>/<step>/`.
3. Link the report from its plan and from this index. If it yields a reusable lesson, merge it into the appropriate topic following [LEARNINGS.md's criteria](../../LEARNINGS.md#keeping-this-useful), with a link to the step evidence.
4. Write in English. Never link `references/` or `app/captures/` as if they were in the repository; write "local only" in plain text. Third-party files need a license that allows redistribution and a `sources.json` with author, URL, license and hash before they are committed.

Latency measurement tooling: [F6a](radio-input/F6a/README.md) adds an optional live-flight raw-axis marker and a camera protocol; synthetic same-tick/state-equivalence tests and rendered captures support the tool. [F6b](radio-input/F6b/README.md) reduces per-condition frame annotations into median/p95 and explicit frame/cadence bounds, retaining exclusions and provenance. Physical F6 measurements remain open.

Radio event cost: [F3b1](radio-input/F3b1/README.md) measures the actual handler and scene dispatch under a synthetic four-axis 1 kHz workload. Two bookkeeping alternatives were not adopted because their full-path timing did not improve consistently; exhaustive axis-history tests protect future optimization.

- [L10c flightline barrier and complete-field review](visual-quality-implementation/L10c/README.md): estimated visual geometry, pilot runway clearance, deterministic cue/scenery captures and explicit launcher. [L10d contact grounding](visual-quality-implementation/L10d/README.md): one feathered mesh aligned with shared cue geometry.
