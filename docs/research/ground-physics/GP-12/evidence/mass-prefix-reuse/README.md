# GP-12 fixed mass-prefix reuse

2026-10-26. **Promoted optional numerical API; 858 production assertions pass**
in six checked invocations with exact completion markers, warnings-as-errors
and no diagnostics. The 110-check persistent test joins AR 53, Impulse 314,
Step 167, unloaded-policy 130 and Accuracy 84. These are selected, repeated
regressions, not 858 new independent assertions or a full-suite pass.
[Report](report.json), [exact production sources](production/source/app/),
[promotion receipt](optimization/root-promotion.json).

## Numerical contract

`ContactAssemblyResolution.prepare_mass(matrix,width)` creates one opaque proof
owned locally by the trusted read-only model. It retains only the mass-dependent
prefix: exact symmetry, Cholesky, true-SPD congruence witness, inverse and inverse
residual bounds. Complete actual matrix bytes and width must match at every use.
A mismatch recomputes the original prefix; no stale proof is used or updated.
The owner can rebuild on reset, hot reload or changing mass/axis configuration.
No global cache or repeated whole-configuration hash is introduced. Private
fields are implementation details, not protection from malicious GDScript
reflection or subclassing; arbitrary dictionaries cannot supply proof authority.

The optional proof passes explicitly through Step, Impulse and the existing
call-local AR memo. Every actual Jacobian, velocity, bias, response and mobility
operand and its assembly/slip/work bound is recomputed. Objective, capacities,
outward arithmetic, law identities, state and receipt fields remain unchanged.
Absent/unprepared/mismatched proof paths retain original complete return bytes.
The object enters no sample, state, checkpoint or receipt. This slice does not
select it for stock Session flights and does not change QP/Strategy convergence.

The [persistent test](production/source/app/tests/test_contact_mass_prefix.gd)
uses six existing fixtures and no new binary. Fifteen complete pre-extraction
bounds returns and both public Step law returns are independently frozen by
SHA256; the test cannot pass by comparing the candidate with itself. Null,
arbitrary and unprepared objects, changed matrix/width/signed-zero and zero-mass
fallbacks preserve complete original returns. Five actual Impulse pairs preserve
all objectives, state and receipts. Input/output independence is checked.
[Capture identities](optimization/test-payload-manifest.json),
[captured hashes](optimization/baseline-production-hashes.json).

## Measured hotspot and bounded change

The same four retained states were each advanced once in plain/instrumented
source copies. **All four complete output binaries are identical**, including
hard78's honest raw-accuracy refusal. Rest6/rest10 perform 51 impulse solves,
244 Stage evaluations,148 owner samples and96 derivative evaluations across
five refinement attempts. Assembly bounds cost 256–272ms inclusive, about39% of
timed advances; their SPD subcall costs 70–77ms inside that total. The QP solver
costs 32–35ms inclusive, about5%. Stage costs 179–203ms inclusive, about27%.
Serialization costs 34–40ms across 1,613–1,654 calls and 6.6 MB. Nested inclusive
times overlap and must not be added. Exclusive timings include uninstrumented
work and wrapper overhead. [Original hotspot report](hotspot/report.json),
[plain/timed full outputs](hotspot/results/).

The unloaded gentle slice builds no assembly witnesses. Stage 94 ms, the optional
loss-policy seam 32 ms and serialization 31 ms dominate its 202 ms instrumented
advance. Fixed-matrix reuse cannot substantially help that slice. These owner
callbacks deliberately revalidate captured resources; the measurements do not
authorize removing checks or claim arbitrary-script sandboxing is required for
trusted immutable production resources.

The first separate baseline/optimized pairs were noisy and are retained in full:

| State | Baseline ms | Prepared ms | Result |
| --- | ---: | ---: | --- |
| Rest6 |623.484 |734.455 | Accepted 16 pieces |
| Rest10 |653.428 |525.425 | Accepted 16 pieces |
| Gentle98 |192.133 |182.602 | Accepted 16 pieces |
| Hard78 |253.314 |390.263 | Raw-path refusal unchanged |

All four outputs equal both the immediate baseline and the original hotspot
outputs. A counted rest6 advance confirms **51 bound calls, zero prefix rebuilds**
after one 2.169 ms preparation. [Reuse counts](optimization/results/counted/).

Five warmed, alternating-order pairs per checkpoint in one process give:

| State | Baseline median ms (range) | Prepared median ms (range) | Once-only preparation ms |
| --- | ---: | ---: | ---: |
| Rest6 |866.143 (775.788–896.303) |747.158 (630.064–779.219) |2.131 |
| Rest10 |898.076 (863.918–943.475) |717.149 (630.636–766.312) |3.594 |

All ten pairs and both warmups preserve complete output bytes; 34 checks pass.
Median reductions are 13.7%/20.1% for this bounded diagnostic, with substantial
shared-host spread. [Every pair](optimization/paired-results.json),
[complete before/after outputs](optimization/results/).
**A resting tick still takes roughly 0.7 s**, far beyond real time at 240 Hz.
There is no native, rendered-frame, target-hardware or statistical performance
qualification. No full ten-second tape was rerun, no golden flight changed,
and no physical validation or stock launch follows. The later scalar-capacity
and weak-mode QP corrections are excluded from these source identities.

## Retention and reproduction

The collection retains measured plain/timed source closures, the optimized
closure, exact full outputs, four state inputs, five source assets, six existing
fixture inputs, root production sources and original checked reports/logs.
[Origins](origins.json) preserve raw copy hashes; report commands retain their
original temporary paths and clocks. Production source-before imports and CRLF
were reconstructed from the measured plain copy and verified against the exact
recorded pre-change SHA256s. Earlier canonical evidence remains unchanged.
Development parse/marker mistakes are excluded from passing collections.

The [manifest](manifest.json) binds payload bytes. The post-snapshot
[fresh Git/autocrlf transfer receipt](attribute-roundtrip.json) excludes itself
from its own snapshot and validates every retained artifact plus checked-log
summaries. It stages/commits only a disposable fixture, never the real repository.

To verify retained checks without rerunning physics:

```bash
python3 tools/godot/summarize.py docs/research/ground-physics/GP-12/evidence/mass-prefix-reuse/production/checks
python3 tools/godot/summarize.py docs/research/ground-physics/GP-12/evidence/mass-prefix-reuse/hotspot/checks
python3 tools/godot/summarize.py docs/research/ground-physics/GP-12/evidence/mass-prefix-reuse/optimization/checks
```

On the matching four-source production snapshot, run the existing checked
runner with `--warnings-as-errors --require-text` and the exact completion marker
for `res://tests/test_contact_mass_prefix.gd`; the retained
[production receipt](production/checks/prefix-k_olsnit/report.json) owns that
command. Other five production commands are retained beside it. Standalone
source copies require rebasing their literal temporary import prefixes and
providing the retained inputs; their hashes establish what actually ran.
