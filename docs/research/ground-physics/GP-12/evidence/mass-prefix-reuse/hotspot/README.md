# Ground numerical hotspot diagnostic

Four retained states were each advanced once through the same 65-script
captured source closure: final unloaded-normal policy, existing bounds and
existing whole raw Accuracy gate. Plain and instrumented complete result bytes
match for all four. Hard78 remains a refused path; profiling did not repair it.
No runtime or canonical evidence files were changed.

| State | Plain ms | Timed ms | Result |
| --- | ---: | ---: | --- |
| Rest6s | 606.531 | 734.481 | accepted16 pieces |
| Rest10s | 661.567 | 658.939 | accepted16 pieces |
| Gentle98 | 174.165 | 202.091 | accepted16 pieces |
| Hard78 | 248.150 | 297.315 | original raw-path refusal |

Rest consumes51 impulse solves across five attempted refinements,244 Stage
evaluations,148 owner samples and96 derivative evaluations. AR.bounds takes
256–272ms inclusive,39% of timed ticks; its SPD-congruence subcall takes70–77ms.
The actual QP solver takes32–35ms inclusive, around5%. Stage takes179–203ms
inclusive, around27%; geometry is inside Stage and cannot be added again.
Whole serialization totals34–40ms (about5%) across1,613–1,654 calls and6.6MB.
At rest, assembly arithmetic proof construction is the first measured target.

Gentle unloaded spends94ms in Stage,32ms in the optional loss-policy seam and
31ms total serialization. It does not build AR mass/assembly witnesses. The
policy owner invokes preparation24 times;244 full Stage evaluations remain.
Repeated source/mechanical checks matter for this branch, but a fixed-matrix
optimization alone cannot improve it substantially. Stage snapshots are also
recomputed by the96 derivative calls. Removing sandbox-like checks would require
a separate trusted immutable-owner contract; it is not authorized here.

Measurements adapt the existing `tmp/gp12-local-reuse/profile_tick.py` wrappers.
They are one sequential quiet sample per state on a shared host. Nested inclusive
times overlap; exclusive times subtract only instrumented children and include
wrapper overhead. No statistical speedup, native performance, rendered frame
budget or physical qualification follows. The timed rest10 sample being slightly
faster than plain illustrates the timing noise.

`manifest.json` pins source closure and inputs; `report.json` pins full-output
equalities, passing checked reports and source-after checks. Rejected wrapper
development parse receipts remain under checks and are excluded from passing
claims. Removing inherited class_name registrations and retargeting literal
imports affects only disposable copies. Five source data assets remain byte
identical to the earlier retained reference. The report preserves their hashes.

`build.py` constructs the copies. The recorded checked commands are reproducible
through each passing report; `--case=rest6|rest10|gentle|hard` selects the retained
input. No ten-second tape was rerun and no golden was regenerated.
