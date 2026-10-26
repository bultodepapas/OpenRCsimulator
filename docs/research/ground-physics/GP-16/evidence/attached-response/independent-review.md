# GP-16 attached response independent review

2026-10-26. Read-only review of `aircraft_ground_damage.gd` and
`test_aircraft_ground_damage.gd` in this directory against current
`app/physics/{gear_damage,normal_compliance,aircraft_ground_dynamics,aircraft_ground_stage}.gd`.
No root draft/runtime/test files edited or independently executed by reviewer.
Root reports checked kernel tests; that is separate from this source review.

No physical composition defect found for resources produced by `prepare` within
the explicitly aligned, fixed-hub, accepted-boundary domain. Support/component
ordering is consistent with normal-stage hardware records. A failure changes every
bound support of the component and retains geometry, mass and rotor system.
Restricting stroke/stop scale/exponent while reducing stiffness/stop stiffness
makes the failed elastic family pointwise weaker. Potential is evaluated at the
same accepted geometry before/after; damping heat is not counted as failure loss.
Persistent mode selection and GearDamage's first-failure latch prevent repeated
events/loss. Re-evaluation uses the existing normal/common stage, with no second
force owner or body projection. Axis misalignment is explicitly unsupported.
Boundary-only sampling does not establish an interval peak or exact failure time.

Two P2 input integrity findings sent to root:

1. `prepare` compares untyped `raw.format` and axis `quantity.unit` with string
   constants before guarding primitive types. A correctly shaped dictionary can
   contain an integer/bool selector and trigger Godot invalid-operand diagnostics
   instead of a clean refusal. `_valid` similarly compares `prepared.ok` before
   checking its bool type. Include wrong primitive selectors/units/flags in tests.
2. `_valid` checks only outer keys and a recomputable digest. Rehashing after
   changing compiled failed-normal values, axes or healthy-stage internals can
   bypass the constructor's weaker-family/source consistency restrictions.
   Validate bounded nested shapes first, rebuild normal resources from their
   provenance, recheck weak-family/axis/source relationships and hardware/stage
   consistency. Include rehashed hardened, malformed and misaligned resources.
   GearDamage's own `_profile_valid` already rebuilds its source and is stronger
   than this new wrapper guard. Hash equality alone is not semantic validation.

The proposed fixes concern malformed/prepared-resource refusal, not a reported
energy defect in the currently tested constructor-produced fixtures. Progressive
stop and independent-component cases were being added by root during review.

Targeted follow-up source review: root's integrity-02 revision addresses both P2s.
Traversal depth/shared item budgets precede clone/compile; primitive type guards
precede comparisons; `_valid` rebuilds authored provenance plus the minimal model/
ground-profile fields consumed by Stage.prepare and compares the complete canonical
prepared result. The checked model subset includes inertia, selected wheel hardware/
contacts and consumed shaft/axis/rotor/glow data. No further actionable issue found
in this declared domain. Root reports 125/125 checks passing under
`tmp/gp16-attached-checks/integrity-02/`; reviewer did not independently rerun them.
