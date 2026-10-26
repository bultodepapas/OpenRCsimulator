# Numerical correctness foundation (review candidate)

2026-10-26. No production promotion. The authoritative collection is
`foundation-report.json`; the source closure and inputs are pinned in
`live-identities.json`. All68 source hashes still match after the completed run.
Earlier cohorts and all failed receipts remain unchanged.

The original tape accepted all2400 ticks (10 seconds) without a solver refusal.
Its checked receipt is `rest-checks/full-rest-general-work-local-witness-3th8qya1`:
complete=true,15 checks,1 failure. The failure is the old **normal-only** moment
observable. It omitted the actual tangent/rolling reaction. The original run
and failed observable are preserved, not relabeled successful.

Independent full-reaction postprocessing of the retained6s/10s checkpoints is
under `../gp12-reaction-trace`,45 passing checks per checkpoint. It integrates
normal external wrench with the actual RK weights, includes both half-impulse
reactions, and separately computes full common-rotor angular/CM linear momentum
change. The trace changes neither published state nor any original receipt byte.
At6s normal pitch−0.010753983831882695Nm and tangent pitch+0.010753983833322699Nm
cancel. Total residuals are2.04e-8N and5.93e-7Nm; at10s2.93e-8N and5.55e-7Nm.
These pass the unchanged1e-6*m*g and1e-6*m*g*0.9m gates. Momentum closures are
below2.4e-16Ns and1.64e-15Nms. All32 accepted impulses at each audited checkpoint
have independently bounded nonpositive actual-state work. Shaft source and
prescribed carrier work are zero in this passive fixture.

Replacing ONLY the incomplete moment observable therefore gives a derived
corrected15/0 fixture result from the complete frozen tape. This is explicitly
postprocessing, not a rewritten runner receipt or a second10s integration.
Maximum accounted energy drift is1.3309602309163893e-9J; maximum positive tick
work1.7621459846850485e-12J; maximum accepted numerical allowance3.25045e-14J
within the owner's1e-11J tick allocation. Installed P51 hardware, fixed half-fuel
properties and synthetic normal/aggregate parameters retain their original
scope; no fleet calibration or launch admission is claimed.

Compatibility1428/0 and focused slip17/work22/reuse23 pass. The distinct opt-in
arithmetic proof explains cancellation from actual operands, charges state
addition error, retains raw diagnostics and rejects positive actual-state work.
Private exact-operand local reuse preserves mathematical/certificate bytes;
only truthful build/request accounting changes. Default strict complete outputs
remain byte-identical. See `review.md` for derivation and limitations.

This foundation does NOT close the uniform-grid drop accuracy gates. The old
gentle/hard failures remain. Test-only gap/load-exit partitions pass their
unchanged work targets, but the common duration-dependent pre-kick locator still
needs implementation and complete-path qualification. Loaded brake/lift,
240/480/960 refinement, and performance remain open. The completed harness took
1741.875s wall time for10 simulated seconds; no target-host performance claim.

Use the repository checked runner for each retained script, with the root
Godot executable as command parameter. The exact commands, completion markers,
source hashes, engine hash and receipts are retained in the JSON collection.
The binary checkpoints/reaction tapes are lossless; JSON is inspection material.
