# Crash and damage investigations

**Status:** research index, 2026-10-06. **Serves:** [CRASH-DAMAGE-PLAN](../../CRASH-DAMAGE-PLAN.md) (CR- steps). This folder records research and proposals; it does not certify crash realism.

## Reports

| # | Report | Scope |
| --- | --- | --- |
| 01 | [Damage models in simulators and games](01-simulators-games-damage-models.md) | Crash handling, structural damage patterns, and lessons from RC simulators and other games. |
| 02 | [Godot destruction techniques](02-godot-destruction-techniques.md) | Godot presentation, pre-split meshes, rigid bodies, particles, renderer and performance constraints. |
| 03 | **Pending — RC construction and material/joint impact thresholds** | Owned by **CR-07**. This report must acquire traceable evidence for candidate failure limits, applicability to the modeled airframes, and uncertainty. The source document is not present. Until CR-07 completes this work, no structural threshold is accepted; do not infer one from effective mass or crash videos. |
| 04 | [Crash audio, presentation and honest game feel](04-audio-presentation-feel.md) | Sound propagation, presentation boundaries, replay and pilot-facing feedback. |
| 05 | [Architecture and impact model for this repository](05-architecture-impact-model.md) | Proposed impact snapshot, structure data, resolver, damage feedback and wreck handoff. Proposals remain subject to the dependencies in the plan. |

## Evidence

The existing effective-mass experiment is in [`research/crash-damage/cr-00/`](../../../research/crash-damage/cr-00/), with [results](../../../research/crash-damage/cr-00/results.txt). It checks rigid-body calculations against the current aircraft inventories. It ranks the response by hit location; it does not measure material or joint failure strength, restitution, or validated crash outcomes.

## Suggested reading by step

- **CR-01 impact snapshot:** start with report [05](05-architecture-impact-model.md) for the proposed fields, then report [01](01-simulators-games-damage-models.md) for existing crash and reset patterns. CR-01 is limited to a typed contact snapshot and readable direct cause.
- **CR-02–CR-05 presentation:** use reports [04](04-audio-presentation-feel.md) and [02](02-godot-destruction-techniques.md) only after Gate 2 prioritizes the work and the relevant contact interfaces are ready.
- **CR-06–CR-10 structural breakup:** read reports [01](01-simulators-games-damage-models.md), [02](02-godot-destruction-techniques.md), and [05](05-architecture-impact-model.md). CR-07 owns the pending report 03 and must complete its evidence review before any threshold is accepted.
- **CR-11–CR-15 flyable damage:** read report [05](05-architecture-impact-model.md) with the plan's required H8 persistent-state and G4b shared mass-property dependencies.

The current research has gaps and source-quality limits documented in each report. Treat borrowed examples as design references, not RC-airframe measurements. Record new sources, methods, uncertainty and non-results when completing CR-07.

## Implementation evidence

[CR-01a](CR-01a/README.md) records the bounded tick-boundary snapshot: detector ordering, rigid hull-point kinematics, explicit unknown gear velocity, lifecycle checks and unchanged ordinary-flight traces. Earliest crossing and rendered crossing pose remain CR-01.
