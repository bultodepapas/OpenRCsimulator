# Technical references and evidence rules

## Source of truth

Application behavior was reviewed at [`a7de9b35676d891bc2034cc344b910d9e1ef9c61`](https://github.com/bultodepapas/OpenRCsimulator/commit/a7de9b35676d891bc2034cc344b910d9e1ef9c61). Pinned GitHub links in the findings preserve that revision; relative code links in the caps document resolve to the same source on this audit branch, which changes no application source. Later branch edits can move relative links, so use the pinned base for historical comparisons.

The checked engine was **Godot 4.8 beta 2**, build **`cafc17a192acf67903910a68aeb3c076c0907a4b`**, obtained through the repository's pinned downloader. The official [release announcement](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/) identifies that build. The binary hash and actual checked commands are retained in the [verification record](verification.md) and [manifest](evidence/manifest.json). A system-installed engine with a different version was not substituted.

## External primary sources

Consulted during the audit on 17 November 2026 in the user's time zone. These sources guide API semantics and verification design; they do not certify OpenRC's physics, materials, or performance.

| Source | Relevant use | Limit on the inference |
|---|---|---|
| [Godot `RigidBody3D` documentation](https://docs.godotengine.org/en/latest/classes/class_rigidbody3d.html) | COM modes, inertia, linear/angular velocity, CCD, contact monitoring, damping, and safe state integration | `latest` documentation is mutable and marked unstable. The exact binary and controlled observations remain necessary; a class description is not a solver parity test. |
| [Godot `PhysicsDirectBodyState3D`](https://docs.godotengine.org/en/latest/classes/class_physicsdirectbodystate3d.html) | Query the physics body's COM-relative point velocity through an engine callback | A query's position frame must be handled correctly after rotation. The first audit fixture's unrotated-point assumption is recorded as an audit error, not an engine defect. |
| [Godot `PhysicsMaterial`](https://docs.godotengine.org/en/latest/classes/class_physicsmaterial.html) | Friction/bounce combination behavior and the independent effect of damping | Coefficients alone do not calibrate a composite balsa/foam/plastic/metal part against a field surface; bounce is not total energy conservation when damping acts. |
| [Godot 3D collision shapes](https://docs.godotengine.org/en/latest/tutorials/physics/collision_shapes_3d.html) | Primitive/compound collision representations and their practical constraints | A cheap primitive is not a geometric equivalence certificate for a wing, wheel, or rotor; measure coverage and runtime cost. |
| [Godot physics troubleshooting](https://docs.godotengine.org/en/latest/tutorials/physics/troubleshooting_physics_issues.html) | Timestep, small/fast-body, shape and tunneling considerations | Increasing timestep frequency or enabling CCD does not automatically qualify every contact path, especially OpenRC's own float64 geometry. |
| [Jolt `Body` interface](https://github.com/jrouwe/JoltPhysics/blob/master/Jolt/Physics/Body/Body.h) and [architecture](https://github.com/jrouwe/JoltPhysics/blob/master/Docs/Architecture.md) | Explicit COM velocity/point-velocity semantics and bounded collision-system design | The upstream moving branch is supporting API context, not proof of the exact backend used by a particular OpenRC run. The project setting did not explicitly name a backend in the audit probe. |
| [Box2D simulation documentation](https://box2d.org/documentation/md_simulation.html) | Continuous-collision, time-of-impact, and timestep/substep distinctions useful for designing adversarial tests | Box2D is a different, 2D engine. It is cited as an engineering reference, not a recommended replacement or evidence of OpenRC behavior. |
| [Glenn Fiedler, “Fix Your Timestep!”](https://new.gafferongames.com/post/fix_your_timestep/) | Distinguish integration subdivision, accumulated time, catch-up work and overload policy | General numerical-design reasoning; not a benchmark or an instruction to change OpenRC's current accepted-time semantics without a contract. |

No external article supplies aircraft-specific structural strengths in this audit. Stronger materials claims require traceable measurements for the installed component, construction, loading mode, loading rate, geometry, and uncertainty. A video, broad material label, or plausible fracture animation is insufficient.

## Repository research and ownership

The current source was reconciled with existing disclosures and tests, including:

- [Stack and kernel boundaries](../../../STACK.md), [aircraft authoring contract](../../../AIRCRAFT_CONTRACT.md), [track ownership](../../../README.md#tracks-plans-and-step-ids), and [verification scope](../../../tools/shared.md#verification-scope).
- [Crash-damage plan](../../../CRASH-DAMAGE-PLAN.md), [impact snapshot identity](../CR-01b/README.md), [turning-prop strike](../E3d2/README.md), [staged wreck breakup](../CR-09b/README.md), and [energy-source presentation](../CR-22b/README.md).
- [Material and joint evidence](../03-rc-construction-material-joint-evidence.md) and [impact-model architecture research](../05-architecture-impact-model.md). These research sources are starting points, not stock strength calibration.
- [Ground microrelief/hull limits](../../ground-physics/GP-10/README.md), [retractable/belly contact observations](../../ground-physics/GP-14/README.md), and [experimental physical gear-damage qualification](../../ground-physics/GP-16/README.md).
- [Landscape collision coverage](../../landscape-upgrade/LU-05/collision-report.md), [helicopter boundary](../../../HELICOPTER.md), and [drone-racing plan](../../../plans/drone-racing.md).

This audit does not reclassify an already disclosed unsupported capability as a newly introduced regression, nor does it infer implementation from a plan checkbox. Runtime code, selected configuration, accepted data, and completed evidence determine the implementation claim.

## Independent invariants used in the review

For a stationary planar surface, decompose the **contact point's** relative velocity into normal and tangent components. A whole-aircraft speed alone does not give the normal impulse or energy. With point effective mass `m_eff`, the normal kinetic term is `0.5 × m_eff × v_normal²`; dividing by total mass produces an estimate in J/kg. Rotation, contact location, slope, and constrained geometry can change the effective mass. The current presentation model's surface factors and class thresholds remain estimates.

For a rigid body's world-space COM velocity `v_COM` and angular velocity `omega`, a point at displacement `r` from the COM has velocity `v_COM + omega × r`. Giving a body a custom COM but initializing its `linear_velocity` from a different geometric center changes the represented momentum. A zero-rotation fixture cannot expose that mismatch.

For a no-impulse instantaneous split, compare mass `sum(m_i)`, first moment `sum(m_i × x_i)`, linear momentum `sum(m_i × v_i)`, and angular momentum about a common origin. The last requires consistent inertia tensors and frame transforms, including the parallel-axis contribution. An energy-budgeted cosmetic scatter must be recorded separately from the zero-scatter baseline. The audit's immediate C3 fixture proves a first-moment/linear-momentum inconsistency in assigned body properties; it is not a post-solver collision measurement or a complete angular-momentum test.

An accepted-path damage transition must not rely on rejected RK stages or discarded candidate states. A final-boundary force sample is not necessarily the interval's peak load. That distinction matters when introducing structural failure, where a failure time can change subsequent forces, geometry, mass, and control response. This audit recommends bounded receipts and transaction tests; it does not claim the existing experimental operator already validates every stock component.

## What the evidence does not establish

The retained checks do not establish physically calibrated fracture, real burn rates, reliable contact at arbitrary speed/scale, swept contact over every render triangle, exact cross-platform Godot debris trajectories, or complete native/reference equivalence. No target-hardware frame-rate or 1080p visual acceptance is inferred from a headless run. These are explicit work items with independent evidence requirements, not reasons to discard the narrower reproducible defects.
