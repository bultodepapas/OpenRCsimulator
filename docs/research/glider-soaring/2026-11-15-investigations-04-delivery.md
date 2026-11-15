# Glider investigations 19–24: controls, presentation, evidence and delivery

**Research date:** 15 November 2026. **Source baseline:** OpenRC `ad21070798bfb9658785576a9c0b8bfc9a71fc7f`; plan branch before this expansion `49dce1db4fce7e907c38367cdfdbe1fc0338876a`.  
**Status:** source investigations and explicitly identified arithmetic completed; implementation, device tests, flight experiments and training studies remain proposed.  
Read the [investigation index](2026-11-15-investigations.md) and [canonical plan](../../plans/glider-soaring.md). Research IDs GI-19…24 do not replace SG implementation step IDs.

## GI-19 — Transfer authority and controller state, not only stick values

**Question.** How can manual-tug → manual-glider transfer avoid a hidden control transient on either aircraft?

**Evidence inspected.** MathWorks' R2026b bumpless-transfer example demonstrates tracking the applied manual command through the inactive controller's integrator before switching to automatic control [D19a]. EdgeTX v2.11's joystick guide documents differences in axis identification, polarity and platform mappings [D19b]. These establish control and device mechanisms, not an RC tow-controller gain or a qualified OpenRC input profile.

**Finding and inference.** The existing plan already requires glider stick pickup and tug-controller initialization with anti-windup. This investigation sharpens which signal and controller state must match: the newly AI-owned tug can receive a discontinuous command from stale integral/filter state even when its physical state is preserved. Matching a saturated command does not establish that the new guidance target is feasible. A radio's USB/mixer rate also does not measure input-to-visible-response latency; USB, OS polling, tick sampling, actuator dynamics, interpolation and display all contribute.

**Plan change — SG-10/11/13, P1.** Distinguish requested intent, post-limit/arbiter command applied to each actuator, and achieved physical actuator position. Initialize or track each tug-controller loop at its actual output boundary, in matching units and direction; set initial guidance from the accepted trajectory. For example, a servo commanded to 1.0 but currently at 0.5 due to lag must not have its command replaced by 0.5 merely to preserve physical position. Define per-loop anti-windup and tracking/reset semantics; inactive controllers never write effective commands. Update tracking state transactionally and checkpoint it while preserving physical servo state separately. Glider pickup includes trims, flight modes and source-profile identity; release remains available if takeover readiness fails.

**Discriminating experiment.** At several admitted trim points, prepare high/low throttle, nonzero bank, saturated elevator, displaced trims, stale switches and a disconnected/reconnected radio. Compare immediate takeover, a stated bounded blend and controller-state tracking with identical accepted starting frames. Inspect command jumps, achieved surfaces, tension, attitude excursions and event ordering. Repeat on actual Windows/Linux/macOS device paths before claiming device support. Proposed experiments are not executed here.

**Uncertainty.** Tracking gains, thresholds and allowable transient metrics depend on the actual aircraft/controller and must be set before qualification. This research does not select them.

## GI-20 — RC visibility is a measurable camera and latency requirement

**Question.** Can a player judge a small glider's attitude and tow geometry from the intended RC ground view?

**Evidence inspected.** Godot's Camera3D reference distinguishes field-of-view axes through `keep_aspect` [D20a]. A NASA record for King's 1993 V-22 display-delay experiment reports that handling effects depend on control-loop stability and bandwidth [D20b]; only the abstract/record was available in this review. Its cockpit task cannot establish an RC monitor's latency tolerance.

**Calculation performed.** For a centered, broadside span `b` at depth `d` in a pinhole camera of horizontal FOV `theta` and width `W`:

~~~text
projected_span_px = W*b / (2*d*tan(theta/2))
~~~

With `W=1920`, `theta=75 degrees` and `b=1.8 m`, the span occupies approximately **15.01 px at 150 m** and **7.51 px at 300 m**. These are analytic examples, not the app's camera configuration or a readability threshold. Orientation changes the silhouette; oblique foreshortening can shorten the projection, while bank can rotate it and reduce horizontal extent without necessarily reducing its total 2D length. A pure 100 ms delay adds 72 degrees of phase lag at 2 Hz; that arithmetic does not establish an acceptable RC limit.

**Plan change — SG-04/10/11/13/17, P1.** Add a recorded camera profile containing projection/FOV axis, viewport, tracking/zoom, stabilization, aircraft visual scale and aids. Preserve physical dimensions and physics when visual assistance changes; label any deliberate render-scale aid. Measure input-to-accepted-command, accepted-command-to-accepted-motion and accepted-motion-to-visible-response with synchronized clocks and a defined response event; actuator/aircraft dynamics are distinct from transport delay. Partial measurements alone do not establish end-to-end response. Camera interpolation follows accepted pair poses, including a restore-generation reset.

**Discriminating experiment.** At native 1920×1080, evaluate heading/bank recognition, release alignment and approach decisions over qualified distances, orientations, backgrounds, lighting and graphics presets. Compare aids using matched trajectories and counterbalanced pilot sessions. Report errors and latency distributions, not FPS alone. No display or pilot trial was run.

**Uncertainty.** Minimum usable projected size and acceptable delay remain task/device/user dependent. Larger render scale or zoom may help readability while changing depth cues; evaluate that tradeoff explicitly.

## GI-21 — A seed is not a replay contract

**Question.** What identity must a paired soaring log retain to support exact replay and meaningful candidate comparisons?

**Evidence inspected.** Godot documents the RNG algorithm as an implementation detail and exposes distinct seed/state operations [D21a]. LLVM documents floating-point reassociation, contraction and approximate-function transformations that can change numerical results [D21b]. OpenRC's [existing flight-log guide](https://github.com/bultodepapas/OpenRCsimulator/blob/ad21070798bfb9658785576a9c0b8bfc9a71fc7f/docs/FLIGHT-LOGGING.md) already binds exact replay to the applicable source or package/backend identity and distinguishes changed-solver candidates.

**Finding and inference.** A new pair format should extend that strong existing contract, rather than promise cross-platform equivalence from a common seed. It must preserve both controller histories, line/event state, accepted input roles and the resolved weather agenda. Cosmetic random draws must not perturb physical draws or change AI decisions. Identical source names do not establish identical native arithmetic.

**Plan change — SG-07/11/15/17, P1.** Record full engine/package/backend and law/layout identities, relevant compiler settings for a native backend, both aircraft snapshots, installed hooks/line, solver policy and event tolerances, full field/epoch, RNG algorithm/state where used, per-actor controller state, and ordered release/ownership inputs. Isolate named random streams or persist the resolved schedule. Reject exact replay under incompatible identity; retain explicit changed-model/solver comparison semantics. A source change must not silently fall back and retain an exact label.

**Discriminating experiment.** Restore before/after slack take-up, release, handoff and interruption. Vary render FPS and cosmetic settings while replaying the same input tape. Insert unrelated cosmetic RNG calls; physical outputs must remain unchanged. Compare identical-build byte replay with a deliberately changed compiler/backend candidate and verify honest classification. Simultaneous events need identical ordering under exact replay; numerical refinement is assessed separately. These experiments remain unperformed.

**Uncertainty.** Which identities are already available through shared infrastructure and which pair-specific fields need versioning is an FL/SF design task. This is not evidence of an existing cross-platform replay defect.

## GI-22 — Define accuracy by intended use and uncertainty

**Question.** What would justify calling the selected glider physically representative, and which measurements should be collected first?

**Evidence inspected.** NASA-STD-7009B (5 March 2024) separates verification, validation, uncertainty, sensitivity and credibility for intended use [D22a]. NIST TN 1297's 1994 reporting guidance asks for uncertainty components, evaluation methods and any coverage factor [D22b]. These methods inform this project; this plan does not claim NASA qualification or prescribe its organizational approval process.

**Finding and inference.** A small residual against a tuned flight is weak evidence if speed, wind, mass or timing are uncertain, or if several fitted parameters compensate for one another. Acceptance must identify the observable, configuration, weather, measurement method and allowed discrepancy before the held-out test. An uncertainty interval is not automatically a 95% interval; its construction must be stated.

**Plan change — SG-02/03/09/16, P1.** Add an evidence matrix for glide sink, glide angle, trim, control response, launch state and tow tension. Separate calibration sorties from withheld maneuvers/configurations; preserve failures as well as successful runs. Report measurement uncertainty, numerical error and model discrepancy separately. Rank proposed measurements by sensitivity: mass/wing area, speed calibration, CG/control travel, parasitic drag, hook geometry and rope response are candidates, not a universal order. Sweep correlated parameter groups using documented bounds and assumptions. Report conditional ranges when probability distributions are unsupported.

**Discriminating experiment.** Fit one documented parameter set, freeze it, then predict a different speed/configuration or control input from held-out data. Compare time alignment, residual bias, variation and declared uncertainty. Perturb uncertain inputs separately and jointly; identify a parameter change that materially changes the user-facing decision. Add samples only where they resolve that uncertainty. No flight fit or Monte Carlo campaign was performed.

**Uncertainty.** The selected RC build has no complete measured dataset in this handoff. The team must choose meaningful metrics/tolerances using available measurement accuracy; this research supplies no invented universal percent-error gate.

## GI-23 — Free simulator content needs file-level provenance and applicability checks

**Question.** Can an existing glider model or flight-dynamics dataset shorten the first delivery without importing unsuitable data or unclear redistribution terms?

**Evidence inspected.** At PicaSim commit `5b2c5871b82aecae4ae6293b862f31600a6a949c`, its README and LICENSE identify PolyForm Noncommercial 1.0.0 for specified code/data, while its README treats models/images separately and directs other projects to obtain permission [D23a]. At JSBSim commit `f80b9df8de8c2a0b7835dbbeb708c8ce37a28d96`, the `sgs126.xml` header describes estimated/educational data, limited validation and a no-sale notice, despite the project's general LGPL library description [D23b]. The aircraft file's blob is `d6ba7e87f2d30ef44f0253aa75b4476c63afa0d5`.

**Finding and inference.** Neither example is an automatically reusable calibrated RC trainer. Repository-level labels cannot decide every model file's terms, and a full-size glider's coefficients cannot be geometrically scaled into a validated low-Re aircraft. This is an observed intake issue, not a legal determination of every possible use.

**Plan change — SG-02/03/17, P1.** Add a shortlist matrix separating geometry, texture, airfoil coordinates, measured polar, estimated aircraft configuration and code. For each candidate retain source revision/hash, author, file-specific terms, allowed intended use as reviewed by the project owner, scale/frames, editable source, hinges and physical applicability. Mark PicaSim assets and the inspected JSBSim SGS file **not admitted for automatic import**. Seek compatible alternatives or explicit permissions before incorporation; no contact or import was performed. Keep measured EG4 data acquisition independent of visual asset availability.

**Discriminating check.** A prospective importer must trace each delivered file back to its exact source and notices, regenerate geometry with the owning pipeline, and compare scale, CG datum, hinges and bounds. A readable mesh is not evidence for its aerodynamic values. The two upstream notice inspections were performed; no asset conversion or rights clearance was completed.

**Uncertainty.** A suitable licensed EG4 mesh has not been established. Existing VJX/OpenSwift leads remain different configurations and require their own per-file assessment.

## GI-24 — Training should assess decisions and transfer, not only duration

**Question.** Which lesson outcomes would demonstrate that the simulator teaches useful RC soaring skills?

**Evidence inspected.** The FAA Aviation Instructor's Handbook chapter on planning instruction describes objectives and progressively combined learning blocks [D24a]. The FAA-hosted 2007 FITS guide defines scenario purpose, desired outcomes, automation assistance and learner/instructor debrief [D24b]. They inform lesson design; they do not demonstrate training transfer from OpenRC to a real RC aircraft.

**Finding and inference.** Maximum airtime can reward chasing lift beyond a recoverable return, and a landing score can hide an intervention that prevented a stall. Practice, diagnosis and scored challenge need distinct outcome semantics. A sensible abort is sometimes the correct decision.

**Plan change — SG-05/06/10…15/16, P2.** Give each lesson a stated objective, admitted aircraft/weather, prerequisite skills, assistance identity, accepted end events and debrief questions. Sequence short glide/landing → speed/energy control → finite thermal centering and return → tow position → release/handoff → admitted aborts. Score only accepted simulation events. Preserve assistance, resets, restored segments, wind/aircraft versions and terminal incidents. Report success, assisted completion, deliberate abort and technical refusal separately. Present observations and alternative decisions; do not infer a pilot's intent from a single stick movement.

**Discriminating experiment.** Define accepted return, landing, assistance and abort outcomes before collecting data. Compare a lesson set before/after practice using withheld weather and matched difficulty; counterbalance order and record RC experience, controller, aids and sample size. Add an alternative-training/comparison group or repeated baseline where feasible to distinguish training from test familiarity and elapsed time; otherwise label change descriptive. Examine decisions, excursions and transfer errors, not only duration. A real-RC transfer study needs a separate supervised protocol; enjoyment ratings cannot establish transfer. No learner study or real-world training claim is made here.

**Uncertainty.** Difficulty, scoring weights and competency thresholds require player evidence. Keep them versioned and separate from the physical model; do not retune aircraft forces to improve a lesson score.

## Primary source register

All links were inspected on 15 November 2026. Web documentation is identified by the retrieved version/date where available; implementation must recheck the project's actual pinned dependency. Evidence descriptions above identify abstract-only inspection explicitly.

| ID | Primary source and inspected scope | Limit |
| --- | --- | --- |
| D19a | [MathWorks, Bumpless Control Transfer Between Manual and PID Control, R2026b](https://www.mathworks.com/help/simulink/slref/bumpless-control-transfer-between-manual-and-pid-control.html), controller tracking example | First-order process example; no RC gains or paid-tool requirement |
| D19b | [EdgeTX v2.11, Configure Advanced Joystick](https://manual.edgetx.org/v2.11/edgetx-how-to/configure-advanced-joystick-with-edgetx), axis/platform mapping guidance | Version-specific guidance; physical devices still need testing |
| D20a | [Godot Camera3D reference](https://docs.godotengine.org/en/latest/classes/class_camera3d.html), `fov` and `keep_aspect` | Retrieved latest documentation; actual camera configuration not measured |
| D20b | [King, Handling Qualities Effects of Display Latency, NASA-CP-3220, 1993](https://ntrs.nasa.gov/citations/19940008843), abstract and metadata | V-22 instrument tasks; no transferable RC threshold |
| D21a | [Godot RandomNumberGenerator reference](https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html), algorithm, seed/state | Engine RNG guidance, not proof of the project's actual random-stream implementation |
| D21b | [LLVM Language Reference, Fast-Math Flags](https://llvm.org/docs/LangRef.html#fast-math-flags), contract/reassoc/approximation semantics | Native compiler reference; no assertion that OpenRC enables these flags |
| D22a | [NASA-STD-7009B, 5 March 2024](https://standards.nasa.gov/sites/default/files/standards/NASA/B/1/NASA-STD-7009B-Final-3-5-2024.pdf), intended-use acceptance and sections 4.3.3–4.3.6 | Methods reference; project selects its own fit-for-purpose criteria |
| D22b | [NIST TN 1297, 1994 edition, section 7](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-7-reporting-uncertainty), reporting uncertainty | Historical methodological source; uncertainty requires actual measurements |
| D23a | [PicaSim pinned README](https://github.com/Rowlhouse/PicaSim/blob/5b2c5871b82aecae4ae6293b862f31600a6a949c/README.md#notes-on-the-licence) and [LICENSE](https://github.com/Rowlhouse/PicaSim/blob/5b2c5871b82aecae4ae6293b862f31600a6a949c/LICENSE.txt) | Distinct code/data and model/image terms; nothing imported |
| D23b | [JSBSim pinned SGS-126 model header](https://github.com/JSBSim-Team/jsbsim/blob/f80b9df8de8c2a0b7835dbbeb708c8ce37a28d96/aircraft/sgs126/sgs126.xml), original date 2001-01-01, declared revision 1.13 | Full-scale estimated model and file-specific notice; not RC calibration |
| D24a | [FAA Aviation Instructor's Handbook, chapter 7, 2020 edition](https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/aviation_instructors_handbook/09_aih_chapter_7.pdf), objectives and learning blocks | Full-scale instruction methodology; no OpenRC efficacy evidence |
| D24b | [Summers et al., FAA FITS guide, September 2007 v1.0](https://www.faa.gov/sites/faa.gov/files/pilots/training/firc/RM_thorugh_SBT.pdf), scenario planning and debrief | Historical training framework; proposed RC adaptation |

## Verification performed in this investigation group

Read primary sources and the current plan/source guides; verified both upstream repository revisions and file notices; calculated the two pinhole-camera examples, pure-delay phase and time-period examples independently with Python. No third-party code/model was imported, no simulator or radio session was run, and no physical, pilot, performance or training-transfer qualification was performed.

[D19a]: https://www.mathworks.com/help/simulink/slref/bumpless-control-transfer-between-manual-and-pid-control.html
[D19b]: https://manual.edgetx.org/v2.11/edgetx-how-to/configure-advanced-joystick-with-edgetx
[D20a]: https://docs.godotengine.org/en/latest/classes/class_camera3d.html
[D20b]: https://ntrs.nasa.gov/citations/19940008843
[D21a]: https://docs.godotengine.org/en/stable/classes/class_randomnumbergenerator.html
[D21b]: https://llvm.org/docs/LangRef.html#fast-math-flags
[D22a]: https://standards.nasa.gov/sites/default/files/standards/NASA/B/1/NASA-STD-7009B-Final-3-5-2024.pdf
[D22b]: https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-7-reporting-uncertainty
[D23a]: https://github.com/Rowlhouse/PicaSim/blob/5b2c5871b82aecae4ae6293b862f31600a6a949c/README.md#notes-on-the-licence
[D23b]: https://github.com/JSBSim-Team/jsbsim/blob/f80b9df8de8c2a0b7835dbbeb708c8ce37a28d96/aircraft/sgs126/sgs126.xml
[D24a]: https://www.faa.gov/sites/faa.gov/files/regulations_policies/handbooks_manuals/aviation/aviation_instructors_handbook/09_aih_chapter_7.pdf
[D24b]: https://www.faa.gov/sites/faa.gov/files/pilots/training/firc/RM_thorugh_SBT.pdf
