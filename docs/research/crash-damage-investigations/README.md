# Crash and damage investigations

**Status:** research and implementation index, updated 2026-10-16. **Serves:** [CRASH-DAMAGE-PLAN](../../CRASH-DAMAGE-PLAN.md) (CR- steps). This folder records research, proposals and bounded presentation evidence; it does not certify crash realism.

## Reports

[CR-31b repair planning](CR-31b/README.md), [CR-31c explicit inspection integration](CR-31c/README.md) and [CR-36c fleet valuation](CR-36c/README.md) record the 2026-10-15 extension: compatible repair choices, guarded salvage updates and independent electric/warbird/jet component prices.

[CR-36b: independent Extra 300S costs](CR-36b/README.md) records partial aircraft-specific inventory coverage, five servo proxies, prop-strike valuation and guarded independent dossier authoring.

[CR-28: component damage and USD repair economics](CR-28/README.md) records the 2026-10-15 source audit, price catalog, reconstructed Stik valuation, crash/salvage examples and fleet coverage gaps. The [active CR-28…38 plan](../../plans/crash-damage-economics.md) owns implementation; prices and gameplay assumptions do not establish physical failure thresholds.

[CR-22c-R1: first-impact stutter](CR-22c-R1/README.md) records the 2026-10-14 native fleet comparison, Compatibility shader warmup and selective emitter startup.

[CR-22c-R2: repeated contact work](CR-22c-R2/README.md) records once-per-tick soft-contact feedback, cached wreck shadows and cached scenery sort distances, with preserved output comparisons and lifecycle regressions.

[CR-22c-R3: resting chips](CR-22c-R3/README.md) records skipped scans after chips settle, shared ballistic increments and transition-only particle pause writes, with exact state comparisons and delayed-effect/reset checks.

| # | Report | Scope |
| --- | --- | --- |
| 01 | [Damage models in simulators and games](01-simulators-games-damage-models.md) | Crash handling, structural damage patterns, and lessons from RC simulators and other games. |
| 02 | [Godot destruction techniques](02-godot-destruction-techniques.md) | Godot presentation, pre-split meshes, rigid bodies, particles, renderer and performance constraints. |
| 03 | [RC construction materials, joints, and post-impact disposition](03-rc-construction-material-joint-evidence.md) | CR-07 literature review: scoped coupon data, RC gear-mount examples, and product-specific inspection constraints. No threshold is validated for the installed Stik structure; CR-07 remains open. Do not infer one from effective mass or crash videos. |
| 04 | [Crash audio, presentation and honest game feel](04-audio-presentation-feel.md) | Sound propagation, presentation boundaries, replay and pilot-facing feedback. |
| 05 | [Architecture and impact model for this repository](05-architecture-impact-model.md) | Proposed impact snapshot, structure data, resolver, damage feedback and wreck handoff. Proposals remain subject to the dependencies in the plan. |

## Evidence

The existing effective-mass experiment is in [`research/crash-damage/cr-00/`](../../../research/crash-damage/cr-00/), with [results](../../../research/crash-damage/cr-00/results.txt). It checks rigid-body calculations against the current aircraft inventories. It ranks the response by hit location; it does not measure material or joint failure strength, restitution, or validated crash outcomes.

## Suggested reading by step

- **CR-01 impact snapshot:** start with report [05](05-architecture-impact-model.md) for the proposed fields, then report [01](01-simulators-games-damage-models.md) for existing crash and reset patterns. CR-01 is limited to a typed contact snapshot and readable direct cause.
- **CR-02–CR-05 presentation:** use reports [04](04-audio-presentation-feel.md) and [02](02-godot-destruction-techniques.md) only after Gate 2 prioritizes the work and the relevant contact interfaces are ready.
- **CR-06–CR-10 structural breakup:** read reports [01](01-simulators-games-damage-models.md), [02](02-godot-destruction-techniques.md), [03](03-rc-construction-material-joint-evidence.md), and [05](05-architecture-impact-model.md). CR-07's literature review is recorded in report 03; aircraft-specific material/joint thresholds, uncertainty bounds, and held-out validation remain open.
- **CR-11–CR-15 flyable damage:** read report [05](05-architecture-impact-model.md) with the plan's required H8 persistent-state and G4b shared mass-property dependencies.

The current research has gaps and source-quality limits documented in each report. Treat borrowed examples as design references, not RC-airframe measurements. Record new sources, methods, uncertainty and non-results when completing CR-07.

## Implementation evidence

[CR-33a](CR-33a/README.md) defines the measurements needed before structural or thermal outcomes can determine a bill. [CR-33b](CR-33b/README.md) verifies isolated impact-energy estimates and bounded allocations; it supplies no failure thresholds and does not close CR-07. [Report 03](03-rc-construction-material-joint-evidence.md) reviews relevant literature but accepts no installed-aircraft structural threshold.

[CR-30c](CR-30c/README.md) records active-flight economic checkpoint validation. [CR-31d](CR-31d/README.md) specifies the bounded pure helper for package-cost optimization. [CR-36d electric](CR-36d/electric.md) records updated replacement-price proxies for the fictional Turbo Lumber inventory; its partial offers do not complete aircraft valuation.

[CR-31e](CR-31e/README.md) connects replacement-only package comparison to incident reports and archives. [CR-33c](CR-33c/resolver-contract.md) implements declared-capacity interval comparisons without production billing or serviceability clearance. [CR-36e](CR-36e/fleet.md) records exact exhaust variants and their remaining installation limits.

[CR-35a](CR-35a/README.md) verifies finite source budgets, explicit ignition ticks and analytic component heating/cooling. Its parameters and thresholds remain caller-declared; it is not connected to aircraft damage or visual fire.

[CR-36a](CR-36a/README.md) extends the economic dossier to the 55AX and FS-64V Stik configurations with exact propeller offers, explicit engine/silencer coverage substitutions, guarded inventory inheritance and production contact-to-report checks. Complete cost coverage remains separate from physical installation qualification.

[CR-29–32](CR-29-32/README.md) records the first playable accident-cost slice: generated USD dossiers, accepted-contact accumulation, conditional repair/salvage calculations, large persistent report, exact healthy-state parity and honest unknown costs. [CR-28](CR-28/README.md) remains the dated price/source record.

[CR-01a](CR-01a/README.md) records the bounded tick-boundary snapshot: detector ordering, rigid hull-point kinematics, explicit unknown gear velocity, lifecycle checks and unchanged ordinary-flight traces. [CR-01b](CR-01b/README.md) verifies crossing reconstruction along the existing pose interpolation, numerical unknown cases and unchanged flight traces. Component labels and crossing-time kinematics remain CR-01; the rendered handoff is covered by CR-01c below.

[CR-01c](CR-01c/README.md) records the production-scene crossing-pose handoff, fallback behavior, lifecycle checks and paired rendered evidence. [CR-01d](CR-01d/README.md) names every crash-hull point in the aircraft data and uses the name in crash presentation. Later 2026-10-13 slices: [CR-01e causes](CR-01e/README.md), [CR-03b effects and sound](CR-03b/README.md), [CR-09b breakup](CR-09b/README.md), [CR-09c real parts for imported models](CR-09c/README.md), [CR-22b energy sources](CR-22b/README.md) with its [source review](CR-22b/research.md), [CR-22c cost](CR-22c/README.md), [E3d1 soft contacts](E3d1/README.md), [E3d2 prop strike](E3d2/README.md) [CR-09d1 inventory masses](CR-09d/README.md) and [CR-09e/f physical parts, broken structure and bare wood](CR-09e/README.md).

The owner-prioritized 2026-10-11 presentation extension is documented in [CR-22a](CR-22a/README.md): production scenarios, flight parity, VFX/fire, native audio mix, budget, reset, licenses and remaining limitations. Supporting modules: [CR-02a audio](CR-02a/README.md), [CR-08a severity](CR-08a/severity.md), [CR-09a wreck](CR-09a/README.md), and [ownership coordination](CR-09a/coordination.md). The CR-08a bins are explicitly uncalibrated; [CR-08b](CR-08b/README.md) replaced them with effective-mass, per-kg grading, equally uncalibrated. CR-07 physical threshold acceptance remains open.

[CR-17a](CR-17a/README.md) records the 2026-10-12 local scenery destruction implementation: shared fence geometry, committed material profiles, checkpoint/reset state, cell-preserving removal, bounded aftermath and production integration. Its failure cutoffs are gameplay estimates.
