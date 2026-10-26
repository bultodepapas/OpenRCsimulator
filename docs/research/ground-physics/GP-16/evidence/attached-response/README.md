# GP-16b/17b attached compliance response

2026-10-26. The existing normal stage now has a reusable adapter binding persistent
component failure to an authored weaker effective leg/tire response. It preserves
fixed hubs, wheel radii, common rotor inertia and the body's instantaneous velocity.
This is constitutive support failure, not a moving leg or detached component.

| Selected checked script | Checks | Receipt |
| --- | ---: | --- |
| Actual attached response and kernel drops | 125 | [report](checks/attached/report.json) |
| Existing gear-damage core | 113 | [report](checks/core/report.json) |
| Existing normal/common-rotor aircraft stage | 145 | [report](checks/stage/report.json) |
| Existing endpoint/checkpoint transactions | 274 | [report](checks/endpoint/report.json) |

All **657 checks** passed, with complete checked-runner receipts and zero engine
diagnostics. The new suite includes actual normal-force/potential changes, spring
and progressive-stop release, independent left-leg failure and resulting roll
moment, unknown strength, same-gear light/heavier/harder kernel drops, upward
elastic rebound, continued failed motion, exact checkpoint continuation and
rollback after a later kernel refusal. Its synthetic 240/480 Hz failure-time
comparison passes within one coarse tick; that fixture-specific comparison does
not bound missed peaks in arbitrary landings.

[Independent source review](independent-review.md) identified primitive-selector
and rehashed-resource integrity gaps. The final source bounds input traversal and
rebuilds compiled resources from source before accepting them. The reviewer checked
the fixes but did not independently rerun the suite. Tests include malformed
primitives, cycles and rehashed altered stiffness, axes, geometry and inertia.

[Manifest](manifest.json) pins 33 retained artifacts and the promoted source hashes.
Sources are a selected snapshot at packaging, not a complete application dependency
freeze. Tests ran in the shared main tree; unrelated concurrent work was present.
These receipts are not the separately frozen GP-11 full-suite cohort.

No stock model is enabled or calibrated by this change. Failure timing still needs
accepted-path localization; full collapse needs moving geometry/inventory and
continued hull contact. Resource rebuilding is a correctness-first implementation,
without a production performance claim. The adapter must eventually cache selected
immutable stages safely across unchanged failure masks and rebind on lifecycle
changes. See the [owning integration guide](../../README.md).
