# Arithmetic work and local witness reuse — draft review

2026-10-26. Production files and earlier evidence cohorts are unchanged.
The ten-second actual three-wheel rest run is pending under `rest-checks`.
`live-identities.json` pins its literal source closure, installed P51 resources,
engine and unrelated dirty tree at capture time. This is software evidence on
synthetic contact/aggregate data, not aircraft calibration or launch admission.

The retained tick262 failure is
`../gp12-slip-proof/next-failed-2a96aa6b3041b237.bin`. Its only failed check is
work closure: `5.565313974315818e-22 J`, versus the old
`5.309662843805692e-22 J` target. Mass, slip and total-energy checks pass.

For exact interpretations of supplied binary64 operands, define
`e_g=g-J^T p`, `F=Jz+b-v`, `D=J(z+delta)+b-v-A_sym p`.
Then the exact difference between the generalized-impulse incremental work
and original QP work is
`.5 p.(D+F)+(z+.5 delta).e_g`. The proof uses independently verified projected
mass-response/slip bounds and actual uncancelled dot/add operands. It binds
the reported objective, incremental work and closure to the exact repeated
arithmetic before explaining their difference. Positive operations are outward
bounded. No velocity, force or total shaft-energy floor is introduced.

Actual published velocity addition is treated separately. Error-free TwoSum
recovers `e=fl(z+delta)-z-delta` without changing state. Its kinetic correction
is `next^T M e-.5 e^T M e`, plus constant affine momentum against `e`.
Combined-solve residual work `(z+.5 delta).(M delta-g)` and all evaluation
rounding are bounded independently. The actual relative-support work upper
bound must be nonpositive. At the captured case, recovered shaft addition
error is `7.873908643157588e-15 rad/s`, contributing positive
`2.2723877759335706e-14 J`; actual net work remains provably negative below
`-2.63210754338949e-12 J`. This correction is charged to the owner's budget.

The algebraic work bound is `1.6150709462092312e-19 J`; total work charge is
`2.2724039742184834e-14 J`. It shares the original per-QP ceiling with the QP
assembly Gamma and any slip proof. The Step receipt retains separate sums
and their outward combined sum; the owner checks its accepted-tick ceiling.
Raw closure, original target, actual-state work and certificate law remain
visible. Original caps, QP passivity, mass and total-energy checks remain.
The default strict path is unchanged.

Focused checks cover forged work receipts/objectives, incorrect mass response,
ceiling overspend, exact impulse/generalized impulse/delta preservation,
nonfinite/overflow refusal, cancellation/subnormal TwoSum cases, and a separate
SPD example whose ideal passive QP produces positive actual-state work after
rounding. That example is refused rather than hidden by arithmetic consistency.

Witness reuse is local to one Impulse call. Exact complete
`[A,v,M,J,z,b,responses]` bytes bind the one retained operand set; changed
operands rebuild and cannot hit an old witness. No memo is exported, no public
API accepts a caller-authoritative memo, and the public dictionary certificate
still rederives its bounds. No global mutable cache is introduced. Five exact
retained cases have identical public mathematical/state/certificate bytes to
the unoptimized closure draft. The only expected output differences are the
truthful `assembly_witness_builds` counter and new request counter. Complete
strict-default outputs remain byte identical.

The bounded exact tick240→241 profile reduced bounds calls162→51. Inclusive
wall times were1.195s before and1.005s after, with concurrent load changing
Stage.evaluate165.6→264.2ms. Timings are nested; do not sum them or claim a
production speedup. Fifty-one QPs include discarded1/2/4/8 trials; only the
16-piece finer path publishes32 half impulses. Stage evaluation and compulsory
refinement remain substantial costs. This is not performance qualification.

Latest passing compatibility: QP659, Impulse314, Step167, Accuracy84,
Electric196 and strict-byte8 (1428 total). Focused slip17, work22 and reuse23
also pass. Runner marker mistakes are retained as rejected receipts; corrected
marker runs pass. The original gentle/hard drop raw8/16 work gates still
refuse at ticks98/78 and have not been weakened or qualified by this work.
