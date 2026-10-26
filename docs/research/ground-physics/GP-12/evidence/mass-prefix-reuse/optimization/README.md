# Fixed mass-prefix reuse draft

No production change. `production-review.patch` proposes three existing files;
`promotion-candidate/` contains equivalent res:// payloads for root review.
QP and Strategy are unchanged, including AR._solve_core's candidate callsite.

AR prepares only the fixed mass-dependent prefix: exact symmetry, Cholesky,
true-SPD congruence witness, inverse and inverse-residual bounds. Its opaque
FixedMassProof is produced locally and owned by the trusted read-only model.
No caller Dictionary supplies a proof. Private fields are implementation details;
this is not a sandbox against malicious GDScript reflection or subclassing.

Every use compares complete actual matrix bytes and width. A mismatch runs the
original prefix; it neither uses stale evidence nor mutates the prepared proof.
The owner can rebuild on reset, hot reload or changing mass/axis configuration.
There is one explicit object and no global cache. All actual J/z/bias/A/response
operands, their rounding bounds, capacity/objective gates and work proofs are
recomputed. The public old bounds signature/default and all law strings remain.

The optional proof is threaded Step→Impulse→existing local AR memo. It is not
added to samples, state, checkpoints or receipts. Matrix equality is the exact
mathematical dependency for this prefix; different axes producing the same
matrix need no different prefix, while their actual Jacobians remain rechecked.

41 focused checks cover full bound-byte parity, SPD and malformed matrices,
changed matrix/width/signed-zero misses, arbitrary/unprepared object fallback,
changed mobility refusal, independent output ownership and both retained real
gentle143 QP operands. Existing AR53, Impulse314 and Step167 checks also pass.
Development marker/parse errors remain retained and are excluded from passing
claims. The signed-zero fixture constructs its sign bit directly because the
literal -0.0 was folded in the first rejected test.

Actual rest6 advance makes51 bound calls and zero mass-prefix rebuilds after
one2.169ms preparation. Four-state complete results equal both the immediate
baseline and earlier original hotspot outputs, including the hard78 refusal.
The first one-pair timings were noisy and are retained without a speed claim.

Five warmed interleaved pairs in one process give:

| State | Baseline median ms (range) | Prepared median ms (range) | Preparation ms |
| --- | ---: | ---: | ---: |
| Rest6 | 866.143 (775.788–896.303) | 747.158 (630.064–779.219) | 2.131 |
| Rest10 | 898.076 (863.918–943.475) | 717.149 (630.636–766.312) | 3.594 |

All ten pairs and both warmups preserve complete result bytes;34 checks pass.
Median reductions are13.7%/20.1% in this bounded shared-host headless diagnostic.
This is not native/rendered/statistical or physical performance qualification.
No full tape was rerun. The optimization cannot materially help unloaded gentle
states where no assembly bounds are built, and does not solve QP convergence.

`report.json` binds exact target hashes, compatibility receipts, actual reuse
counts and measured pairs. `manifest.json` binds the captured draft sources;
the source-after check confirms those files did not change during the runs.
The authoritative earlier hotspot source/input cohort remains unchanged under
`../gp12-hotspot-review/`.

The persistent production test proposal is now
`promotion-candidate/app/tests/test_contact_mass_prefix.gd` (110 checks). It uses
res:// imports only and reuses six existing binary fixtures; no new binary is
needed. Fifteen complete pre-extraction bounds-return hashes and both public
Step law return hashes prevent candidate-against-itself parity tests. Valid
null/arbitrary/unprepared/mismatched proof fallbacks match the original complete
return bytes. Five actual Impulse outputs and both complete public Step outputs
also match with/without prepared reuse, including all objectives and receipts.

The exact res:// test payload parsed and passed in a disposable 25-script
dependency project using the reviewed runtime proposals. Main runtime and tests
remain untouched. `test-payload-manifest.json` binds this closure, the unchanged
original hash-capture source identities and the passing capture receipt.
The separate scalar capacity correction is still awaiting root merge/review;
these receipts qualify the mass-prefix proposal alone.
