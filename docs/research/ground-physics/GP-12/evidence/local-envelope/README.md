# GP-12 local normal-compliance envelope

2026-10-26 · The additive `NormalCompliance.bounds_interval(prepared,xmin,xmax,vmax)` API and its test are promoted. **Production parse + 553 assertions pass** with warnings treated as errors and exact completion markers. Runtime integration, force coefficients and existing law/default outputs are unchanged. [Report](report.json), [manifest](manifest.json).

| Collection | Scope | Assertions | Receipt |
| --- | --- | ---: | --- |
| Original draft | Interval proof, existing normal regression, checkpoint comparison | 465 + 88 + 22 = 575 | [draft checks](draft-checks/) |
| Final reviewed draft | Frozen complete old-output fixtures | 465 | [review](review-checks/review465/report.json) |
| Production | Parse, new interval test, existing normal test | 465 + 88 = 553 | [main checks](main-checks/) |

These counts include repeated checks across development and production, not 1,593 distinct assertions. All named collections are passing; earlier failed numerical-fixture attempts remain temporary development evidence and are not presented as successful receipts. Official Windows Godot `4.8.beta1.official.4d10419ca`, headless; no native/performance qualification.

## Bound and compatibility

The caller declares a **closed** compression interval `0 <= xmin <= xmax` and `|xdot| <= vmax`. The old elastic upper tangent at `xmax` and old damping maximum are retained. Only damping-ramp derivative terms shrink:

```text
Dbase = 2*cmax/onset       if onset>0 and xmin<onset; otherwise 0
Dstop = 2*cstop/stop_scale if xmax>stroke and max(0,xmin-stroke)<stop_scale; otherwise 0
Kpos  = Kelastic_max + (Dbase+Dstop)*vmax
```

A ramp is identically saturated on the whole interval before its slope term is omitted. The unilateral `max(0,trial)` map is 1-Lipschitz, so it preserves these bounds across the clipping kink where the underlying onset is continuous. Zero-onset base damping can claim local continuity only when `xmin>0` or base damping is absent; touching zero remains explicitly unsmooth. The caller still owns geometric stiffness, mobility and proof of whole-interval coverage. This is an additive numerical envelope API with no new physical parameter.

The new test covers 81 interval/exponent/onset combinations, independent polynomial-force secants and interior finite differences, stroke and damping thresholds, clipped rebound, zero-onset counterexamples, finite/order/type rejection and overflow. Finite-difference/secant ratios exceed 1 only at numerical roundoff (`3.32e-11`/`1e-14`). It does not claim to validate arbitrary corrupted normalized `prepared.values`.

[Thirty-six frozen complete old-function output hashes](legacy-function-hashes.json) bind `prepare`, 50 force evaluations, five old bounds and the scalar selector for nine fixtures. The [original capture](review-checks/legacy-capture/engine.log) precedes promotion. Production tests compare complete Variant-byte hexadecimal SHA256 identities to these independent captures, avoiding comparisons of a function with itself. A future intentional return-schema extension requires an explicit fixture/version reconciliation. The exact original 465-check test text was reconstructed from development edits and verified against its recorded pre-change SHA256; the original checked receipt was not rerun or rewritten.

The [promotion patch](promotion/normal-interval.patch) inserts only the method. Git's checkout conversion changed LF to CRLF during application; the [EOL receipt](promotion/eol-receipt.json) proves text equality to the approved payload before restoring the module's original LF format. Final [two-path identities](promotion/manifest.json) and [source snapshots](source/) retain exact reviewed bytes. Existing force/default function bodies remain unchanged.

## Bounded checkpoint comparison

The experiment restores the unchanged **6 s and 10 s** checkpoints from the [canonical numerical foundation](../numerical-foundation/README.md), then advances **four ticks per route**. [References and SHA256 identities](baseline-references.json) bind the existing snapshots/checkpoints; this collection does not duplicate that whole cohort. The old 10 s tape remains unchanged, including its separately documented original moment-observable failure. There was no full 10 s rerun.

The candidate uses `xmin=max(0,-gap-h*GAP_SPEED_MAX)`, `xmax=max(0,-gap)+h*GAP_SPEED_MAX`, and `kappa_lower=kappa-h*OMEGA_MAX`. Declared speed/rate/compression/projection limits, frozen split kernel, work scales and complete raw coarse/fine gate are retained. This remains a **conditional** envelope experiment, not a universal continuous nonlinear enclosure.

| Starting checkpoint | Original pieces per tick | Local pieces per tick | Largest local normalized gate | Local incremental accounted-energy drift |
| --- | --- | --- | ---: | ---: |
| 6 s | 16, 16, 16, 16 | 4, 4, 4, 4 | 0.000341 | 3.70e-13 J |
| 10 s | 16, 16, 16, 16 | 4, 4, 4, 4 | 0.000322 | 8.53e-13 J |

The declared rest fixture's scalar position bound falls from 61,500 to 1,500 N/m while its damping maximum remains 20 N s/m. The measured piece reduction uses the **combined local compression/load/kappa envelope**; it is not an ablation attributing the improvement to onset-slope removal alone. Largest four-tick differences between routes are 2.23e-9 m/s body velocity, 1.89e-11 m position, 2.99e-10 rad/s body rate and 8.16e-17 m/s rim speed. [Exact experiment results](experiment/result.json) retain all values.

Re-run production parse/465/88 using the [retained commands](promotion/root-run-commands.ps1), from the matching source snapshot with the existing checked runner. To validate copied receipts without rerunning physics:

```bash
python3 tools/godot/summarize.py docs/research/ground-physics/GP-12/evidence/local-envelope/main-checks
python3 tools/godot/summarize.py docs/research/ground-physics/GP-12/evidence/local-envelope/draft-checks
python3 tools/godot/summarize.py docs/research/ground-physics/GP-12/evidence/local-envelope/review-checks
```

Raw reports/logs preserve their original bytes, paths and timestamps; [origins](origins.json) bind the copies. [Fresh Git/autocrlf verification](attribute-roundtrip.json) checks retained transport. Its post-verification receipt is excluded from its own manifest/snapshot. No Session, stage policy, frozen tape, stock activation, physical calibration or performance claim is included.
