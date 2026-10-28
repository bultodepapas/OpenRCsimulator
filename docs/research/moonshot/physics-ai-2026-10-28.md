# Flight physics and AI pilot moonshot

**Date:** 2026-10-28  
**Scope:** independent physics, flight-data, and AI-controller review for a 12-month direction.  
**Repository baseline:** `96287766296b3fef6a37dcd4cc3847d7efbe9f19`. Runtime physics and companion files reviewed were clean at that baseline; concurrent CI/export, F4U, ground-data, and truck-native edits were outside this review.  
**Evidence rule:** deterministic software checks establish repeatability and declared invariants. They do not identify a real aircraft or establish physical realism.

## Assessment

The project already has a sound numerical and architectural base for measured, model-based flight intelligence: a 240 Hz fixed-step float64 rigid-body kernel, RK4, strict aircraft data, per-session `VehicleModel` evaluators, full simulation checkpoints, read-only aircraft logs, and a 60 Hz external-controller seam. Preserve this separation. A learned policy should not run inside aerodynamic stage evaluation or add vehicle branches to the kernel.

The main limiting factor is evidence, not lack of a neural network. The baseline fixed-wing aircraft models are not broadly flight-identified. The 2026-10-14 audit explicitly separates equation and replay checks from physical identification and records unresolved force-law, propwash, propulsion, and aircraft-data issues for its two inspected aircraft ([audit](../physics-audit-2026-10-14/README.md)). Existing flight-test and AI companion results are useful software/model-prediction evidence; they are not real-flight validation.

Three activities should remain separate:

1. **Identify the airplane:** infer uncertain aircraft/installation parameters from independently measured flight or bench data.
2. **Teach the pilot:** describe what happened in the user's flight with cited channels and an explicit maneuver reference.
3. **Fly the airplane:** control a target or recover from a condition using a bounded controller.

One data format can support all three, but success in one does not qualify the others.

## Current seams and evidence

| Area | Implemented seam/evidence | What it establishes / does not establish |
|---|---|---|
| Shared simulation | [`VehicleModel`](../../../app/sim/vehicle_model.gd) supplies a state layout and pure model evaluators; [`Simulation`](../../../app/sim/simulation.gd) owns fixed ticks, integration, checkpointing, and accepted-state publication. State is float64; a session installs one vehicle model ([stack contract](../../STACK.md#boundaries-and-data-flow)). | Strong place to isolate aircraft, controller, and logging. It does not identify model parameters. |
| Aero and local analysis | [`aero.gd`](../../../app/physics/aero.gd) uses an empirical small-angle reference blended with local wing/tail loads; its local wing currently uses three equal-area stations per side. The file documents missing dynamic-stall memory and notes that propwash is a separately configured effect. [`wing_polar.gd`](../../../app/physics/wing_polar.gd) accepts a bounded table but says the rows are not measured 2-D section polars. [`trim.gd`](../../../app/physics/trim.gd) solves the real session equations; [`linearize.gd`](../../../app/physics/linearize.gd) offers float64 central differences and mode analysis. | A useful low-order physics prior and local controller model. A good Jacobian or internally consistent trim is not a flight-identified aircraft. Polar, stall, wake, actuator, and propulsion uncertainties remain aircraft/regime specific. |
| Simulation flight logs | The fixed-wing `.orfl` recorder stores exact checkpoint/input/event packets. Export provides `flight.csv` plus a JSON report with events and source/configuration identity; replay verifies the same solver, and candidate replay is open loop. See the [workflow](../../FLIGHT-LOGGING.md) and [FL-01…04 evidence](../flight-logging/FL-01/README.md). | It can establish exact replay with `complete=true` and `solver_changed=false`; it cannot validate physical truth. CSV commands at tick *k* drove *k−1→k*, while state at *k* is the endpoint. Keep this timing explicit in analysis. |
| Test pilots and candidates | The fixed-wing [`ft-card-v5` battery](../../../research/flight-test/README.md) runs 40 tests through the real session path, supports baseline/candidate app copies, and records source/data identities. Its latest fleet profile says 314/320 tests were valid. | Broad, deterministic predictions from the implemented model. Tests have no aircraft realism pass bands, and their scripted pilot is not a human-skill corpus. |
| Autonomous companions | [`FlightSession` external-driver calls](../../../app/sim/flight_session.gd) admit/validate a command packet and advance an ordinary session tick. [`pilot_probe.gd`](../../../research/ai-companions/pilot_probe.gd) already lets a caller substitute a `--pilot` script. The qualified Stik companion matrix repeats seeded runs bit-for-bit and tests one to three aircraft in two weather profiles ([pilot evidence](../ai-companions/pilot/README.md), [AFC-04-R4](../ai-companions/AFC-04-R4/README.md)). | There is a deterministic circuit/traffic-avoidance controller and a promising policy seam, not a learned player autopilot or instructor. The accepted scope is narrow; infeasible encounters, multi-seed endurance, and performance remain open. Callback measurements also miss the 500 µs physics-cost target ([AFC-00…06](../ai-companions/AFC-00-06/README.md)). |
| Offline summary gap | [`summarize_csv()`](../../../tools/flight_log/flight_log.py) streams whole-flight min/max/RMS, but only receives the CSV. It does not join marker events from the export report, so a user's F11 marks do not become per-maneuver summaries. | This is a bounded, useful debrief gap. The inputs already exist; no new flight recorder, solver, or plotting package is required. |

The fixed-wing state path is architecturally well suited to shadow controllers and policy comparisons. The numerical cost is not free: the stack sets a 500 µs target-host budget, and existing companion callback measurements exceed it. Keep inference offline or at the existing 60 Hz command cadence until measured. Never move learned work to each RK4 stage.

**Native-stage qualifier (2026-10-27 evidence):** NK-3 reports 49,553 bit-exact Stik ticks, 12,000 stage contexts, and 2.0–3.8× per-tick speedups on a shared debug VM. [`native_stage.gd`](../../../app/sim/native_stage.gd) is an optional installer helper, but no fixed-wing `FlightSession` path invokes it by default; packaging, fleet fallback, release-template timing, and target-host qualification remain open ([NK-3](../native-kernel/NK-3/README.md)). This promising bounded optimization is separate from the present intelligence work and is not a reason to replace or port the float64 reference kernel first.

## External evidence: what transfers

- Aircraft identification routinely uses deliberately informative control excitation and measured input/output response. NASA describes frequency-response estimation followed by fitting stability/control derivatives to measured responses in its [multisine system-identification paper](https://ntrs.nasa.gov/citations/20205003364). ArduPilot Plane already exposes a real-aircraft chirp/log system-identification workflow and an autotune feature; its docs warn that autotune is conservative and manual tuning can do better ([SYSID](https://ardupilot.org/plane/docs/common-systemid-mode.html), [AUTOTUNE](https://ardupilot.org/plane/docs/automatic-tuning-with-autotune.html)). Reuse those tools and methods where useful; do not create a second generic aircraft-identification or charting product.
- Small fixed-wing flight tests can identify useful control-augmented models from open- and closed-loop data. The [2025 Journal of Aircraft study](https://doi.org/10.2514/1.C038147) reports a small flying-wing UAS procedure and agreement of lateral-directional model metrics within 10% of flight-derived frequency responses. This supports measurement-led, low-order identification, not universal transfer to every model aircraft.
- A 2026 open-access fixed-wing paper combines a physics-based differential-flatness model with Gaussian-process residual prediction and a delay model. It reports HIL and real-flight trajectory tests on a 1.524 m Slick 540 70E, using a Pixhawk and RTK state estimate, and reports lower trajectory errors than its baseline ([GGD paper](https://doi.org/10.1016/j.cja.2026.104205)). This is the closest current evidence for a learned residual at RC-like scale. It learns a task-specific trajectory model; it does **not** show that an arbitrary neural residual can safely replace sectional aerodynamics or generalize across OpenRC aircraft and post-stall maneuvers.
- A separate fixed-wing adaptive autopilot paper uses recursive least squares plus MPC but evaluates the method in linear/nonlinear software aircraft models, not real flight ([PCAC paper](https://arxiv.org/abs/2402.00352)). Treat this as simulation evidence, not flight qualification. A fixed-wing identified-model NMPC study reports actual path-following flights, but assumes a low-level attitude controller and identifies its control-augmented dynamics ([Stastny and Siegwart](https://arxiv.org/abs/1802.02624)). That architecture is a better first controller reference than end-to-end RL.
- Open-source [ArduPilot SITL and Plane](https://ardupilot.org/dev/docs/sitl-simulator-software-in-the-loop.html) are available reference tools for exercising an existing autopilot; the project already uses PlotJuggler as an optional free CSV viewer. These can serve as an external comparison or analysis aid. Their aircraft, sensor, and firmware models do not substitute for this simulator's RC model or acceptance gates.

## Three transformational directions

### 1. Measured, uncertainty-aware RC digital twin

**Mechanism.** Keep the current equations as the interpretable prior. Collect a small, planned set of real-aircraft excitation flights and bench measurements. Fit only identifiable terms first: control-surface/servo response and delay, local roll/pitch/yaw response near trim, prop/motor response, and speed/wind dependence. Compare both flight-level outputs and frequency-response models on held-out flights. Add a bounded residual model only when it closes an out-of-sample error that the physical parameters cannot explain. Store fitted terms as sourced, versioned aircraft quantities with a stated validity envelope and uncertainty; do not silently adapt accepted data during play.

**Player benefit.** A digital model can reflect the player's actual aircraft, setup, throws, and propulsion instead of an attractive generic approximation. A later Workshop flow could make the data lineage visible and let a pilot see which areas are measured versus estimated.

**Credible now.** Flight-test system identification and mixed physics/data residuals are demonstrated in small fixed-wing systems. The repository already has exact state/input records, identified data contracts, trim/linearization tools, and a free offline plotting option.

**Hypothesis/speculation.** The repository currently has no evidenced general real-aircraft telemetry import/flight-identification loop, calibration instrument inventory, or representative held-out RC logs. Inferring full low-Re stall and post-stall aero from ordinary pilot flights is especially weak: sparse, noisy flight data are not equivalent to controlled section-polars or a wind tunnel.

**Gate.** Start with one aircraft and one narrow attached-flow band. Use independent real flights, aligned sensor/control timing, documented mass/CG/servo/prop state, excitation that is safe for that airframe, and a training/held-out split by flight. Require improved held-out state/rate predictions and no degradation beyond declared uncertainty; publish confidence and the valid regime. Keep any per-aircraft fit outside the shared kernel. No in-simulator generated log may count as real calibration evidence.

**Risks/alternatives.** Weak excitation, wind, unmeasured servo lag, and sensor delay make parameters unidentifiable. A fit may compensate for the wrong physics with a misleading coefficient. If real logs are unavailable, use existing AVL/AeroSandbox-style tools and sourced geometry as a clearly labeled prior, then keep uncertainty open instead of training on synthetic truth.

### 2. Evidence-linked flight instructor

**Mechanism.** Turn user-marked flights into factual, maneuver-sized debriefs. First show time/tick, altitude and airspeed change, alpha/beta range, peak body rates, command range, and actual servo range for each marked window. Later add task templates and conditional lessons only where their tolerances come from a declared source or instructor-reviewed data. Every explanation should point to the input interval and measured result. A language model may eventually render a constrained explanation, but must not invent a causal story or grade from unvalidated thresholds.

**Player benefit.** Learners get a useful answer to “what changed during that maneuver?” without leaving the simulator or relying on memory. History can later adapt the next practice task to a player's recurring difficulty.

**Credible now.** The `.orfl` files retain commands, accepted state, actual servo state, air data, markers, and configuration identity. Exact timing semantics are documented. Existing flight-test profiles give predicted metrics for explicitly defined tasks.

**Hypothesis/speculation.** There are no cited pilot-rating data or user-study results here showing that a numeric score or generated coaching sentence improves RC flying skill. Do not turn model-derived measures into a universal “good landing” or “bad loop” score.

**Gate.** Every report value must trace to source rows, units, marker boundaries, and complete/source identity. Begin with descriptions, not grades. For an eventual lesson, compare its claims against independent expert pilot annotation and test whether novices interpret the advice correctly before making skill-improvement claims.

**Risks/alternatives.** A short marked window may miss the entry or recovery; a marker is not a validated maneuver label. Atmosphere, aircraft, camera perspective, and pilot intent alter acceptable behavior. Use manual mark boundaries and PlotJuggler overlays until reviewed task references exist.

### 3. Shadow-to-assist autonomous pilot

**Mechanism.** Begin with a transparent controller: trim-relative attitude/rate loops or a constrained outer path/attitude controller built from the existing trim and local linearization. Run at the companion's existing 60 Hz decision rate, stage commands through the session's external-driver contract, and use the same deterministic scenario inputs as the current companion qualification. First operate as a shadow that logs proposed controls without changing the user's flight. Only after safety and usefulness evidence should a bounded assist take limited authority. Learn maneuver style from expert examples or tune gains offline; consider RL only as a bounded candidate against this baseline.

**Player benefit.** A selectable helper can hold a safe circuit, demonstrate a maneuver as a ghost, or recover one axis while the player retains the rest. The same structured feedback enables “why did it help?” explanations.

**Credible now.** Identified-model guidance and adaptive controllers have small fixed-wing flight-test precedents. The existing companion API already supplies a detached state/traffic snapshot and validates normalized commands. Current companion matrix/replay artifacts can be reused rather than building another generic runner.

**Hypothesis/speculation.** A player-facing learned autopilot that handles different RC aircraft, wind, stalls, landing, and unusual attitudes is not demonstrated. A deterministic RL environment may reward exploitation of present solver errors. The existing companion feature is not performance qualified, and current traffic-avoidance qualification is a narrow route claim rather than a general collision guarantee.

**Gate.** First qualify shadow predictions against current player control logs and repeated seeded scenarios. For an active assist, require hard input bounds, a clear handoff, model-uncertainty refusal, no kernel branch, no simulation faults, explicit success and failure metrics, and target-host cost qualification. Then conduct instructor-supervised human trials; simulation success alone cannot establish real-world safety or pilot skill gain.

**Risks/alternatives.** MPC or online learning may exceed the physics budget; learned policies may fail outside training conditions; a model mismatch can make “recovery” unsafe. Keep the human in control and use existing ArduPilot SITL as an optional external controller reference. A non-ML trim/attitude helper is a credible product if it proves the player benefit sooner.

## Recommended first slice: marker-window debrief

Do not start with a new general campaign runner or a numeric skill score. The flight-test and AI companion tracks already have domain-specific scenario runners, identity receipts, candidate selection, deterministic repeats, and replay verification. The narrow tool gap is that the existing Python summary reads only `flight.csv`, while maneuver marks live in the export `report.json`.

**Small implementation:** add `debrief LOG --out NEWDIR --godot ...` to `tools/flight_log/flight_log.py`. It must exact-replay the source `.orfl` into a fresh directory first; callers cannot pair arbitrary CSV and report files and have them certified. Retain `flight.csv`, `replay.json`, and `godot.log`, then write `debrief.json` with the report and its metadata/source solver identity, source/CSV/report SHA-256 values, and bounded per-window summaries. Include altitude and true-airspeed start/end/change/range; alpha, beta and body-rate start/end/change/range; and command, servo and force/moment ranges. A test can mock the Godot process at this CLI seam; the runtime and physics remain untouched.

**Marker/timing contract:** F11 marks a manual boundary, not an automatically recognized maneuver label. Group same-tick labels in recorded order. With no marks, describe the whole flight as unmarked. Otherwise include the unmarked prefix from recording start through the first mark, windows between distinct marks, and the last mark through recording end. State rows use inclusive `[start_tick, end_tick]`; a marker endpoint is shared by both adjoining windows. Command and load rows use `(start_tick, end_tick]`: command row `k` drove `k−1→k`; report `loads_t_s` as the load epoch. A mark at the last tick creates a one-state, zero-duration tail with no command/load interval samples.

Refuse incomplete reports, omitted events, malformed/out-of-range/out-of-order markers, and report/CSV row, tick, or timestep mismatches. On refusal, keep the replay artifacts and omit `debrief.json`. The reducer streams the CSV with bounded memory. Unit tests exercise the CLI with a mocked replay process and adversarial report/CSV fixtures; a real Godot exact replay is a separate integration gate. Exact replay establishes source-solver consistency, not physical accuracy or causality.

The FL-05 implementation is isolated to the existing flight-log CLI and its Python unit tests (about 275 lines of implementation in this first pass), with no runtime, physics, golden, dependency, or plotting changes. Use [PlotJuggler and its official CSV loader](../../FLIGHT-LOGGING.md#plot-with-an-existing-free-tool) for visual inspection. The unit suite covers mocked CLI replay, marker/timing edge cases, artifact hashes, and refusal behavior; a real source log replay should be verified by the owning track. This factual layer is a foundation for future coach prompts, human annotations, and independently validated controller data, not itself evidence of those outcomes.

## Suggested 12-month sequence

| Period | Deliverable | Exit gate |
|---|---|---|
| Months 0–2 | Marker-window factual debrief; explicit row timing and source identity. | Every claim traceable; incomplete/truncated markers visible; no automatic grades. |
| Months 2–5 | One-aircraft real telemetry and bench-data intake plan; use existing ArduPilot SYSID/logging and free analysis tools where suitable. | One documented, synchronized, permissioned data set with instrument/airframe provenance; held-out flights reserved before fitting. |
| Months 5–8 | Fit one low-order attached-flow/actuator model or quantify that data are insufficient; compare to current model. | Held-out flight improvement with uncertainty and no unexplained regression; generated data remain through source pipeline. |
| Months 8–12 | Shadow controller or instructor-reviewed single-maneuver assist. | Seeded regression, explicit refusal/handoff, 1080p product integration if interactive, target-host physics-cost check, and supervised pilot feedback. |

If real-flight data or qualified human review are unavailable, continue with descriptive debrief and the existing non-ML controller. Do not claim physical calibration, user skill improvement, or safe autonomy from simulation-only evidence.

## Source list

Primary external sources used above:

- NASA, [Aircraft System Identification from Multisine Inputs and Frequency Responses](https://ntrs.nasa.gov/citations/20205003364).
- AIAA, [System Identification for Small Flying-Wing Unmanned Aircraft Using Open-Loop and Closed-Loop Flight Data](https://doi.org/10.2514/1.C038147), *Journal of Aircraft*, 2025.
- Liu et al., [GGD: A data-driven delay-compensated differential flatness model of small fixed-wing UAVs with application to trajectory tracking](https://doi.org/10.1016/j.cja.2026.104205), *Chinese Journal of Aeronautics*, 2026.
- Scott and Powers, [A Data-Driven Autopilot for Fixed-Wing Aircraft Based on Model Predictive Control](https://arxiv.org/abs/2402.00352), simulation study.
- Stastny and Siegwart, [Nonlinear Model Predictive Guidance for Fixed-wing UAVs Using Identified Control Augmented Dynamics](https://arxiv.org/abs/1802.02624), flight experiments.
- ArduPilot, [Plane System Identification](https://ardupilot.org/plane/docs/common-systemid-mode.html), [Plane AutoTune](https://ardupilot.org/plane/docs/automatic-tuning-with-autotune.html), and [SITL](https://ardupilot.org/dev/docs/sitl-simulator-software-in-the-loop.html) official documentation.
