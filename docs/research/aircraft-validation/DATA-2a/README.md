# DATA-2a — Faster stall-envelope loading without changing the grid

2026-10-07 · **Status: validation in progress.** DATA-2's 15 ms whole-load target remains separate. Scope: stall-start solve and peak search in `app/physics/aircraft_data.gd`, one focused app test and offline evidence. DATA-3 exact-input identity is preserved.

## Change and rationale

The old solver performs 60 bisections per stall side, scanning 801 lift samples each time. The discrete sampling is part of the existing aircraft model: replacing it with a continuous extremum could move the solved angle and flight behavior. The new search keeps every sample location and calls the same `Aero.lift_alpha` for sampled values. It skips only intervals whose conservative upper bound cannot beat a known sampled value. Four coarse samples establish an initial lower bound; they do not limit the region searched or assume a single peak.

A typed, fixed-capacity depth-first stack avoids per-interval allocation. Bisection stops when the rounded midpoint equals an endpoint: further identical midpoint evaluations cannot alter the returned angle. Unsupported search domains retain the original exhaustive scan. No global cache, schema changes or flight-loop work is introduced.

## Bound

For magnitude `x` and stall side `s`, signed lift is `f(x)=(1-w)B+wP`, where `B=s*CL0+CLa*x`, `P=CD90*sin(2*x)/2`, and `w` is the clamped cubic smoothstep. On the fast path, `CLa>0`, `CD90>0`, positive blend width and the whole sampled interval lies in `[0,pi/2]`.

Let `r=(start+width)-start`, matching the actual envelope denominator. Smoothstep gives `|w'| <= 1.5/r` and `|w''| <= 6/r²`. On this domain, exact endpoint/quarter-turn bounds enclose P, B and P'. With `value_gap >= |P-B|` and `slope_gap >= |P'-B'|`,

```text
|f''| <= M = 2*CD90 + 3*slope_gap/r + 6*value_gap/r².
```

For any interval of length d, the curve lies below its endpoint chord plus `M*d²/8`. Consequently `max(f_left,f_right)+M*d²/8` bounds all its grid samples. The blend is C1 and piecewise C2; bounded jumps of the second derivative at its endpoints do not invalidate this chord bound. Binary subdivision covers all 801 integer indices. Leaves with adjacent indices already have both values evaluated.

Pruning uses a strict comparison with an additional `1e-12*max(1,abs(bound))` roundoff cushion. This is a conservative engineering guard for the validated double-precision input range, not a directed-rounding interval proof. Actual lift evaluations retain the old arithmetic, including `float(k)/800.0*1.25` and the signed lift operations. A deliberately tiny curve exercises the stack with every interval unpruned.

## Reproduction and acceptance

[Runner and usage](../../../../research/aircraft-data/data2/README.md). The [frozen reference](../../../../research/aircraft-data/data2/reference.gd) comes from the original loader. Its full sampled search is retained only as an oracle and production fallback.

[Verification](verification.json) records 571 focused checks, 1,000 seeded solved angles with zero differences, and 48 exact full-loader result comparisons (model, metadata and warnings). Three isolated mutations are rejected by assertion failures: omitted curvature, wrong negative-side bound and wrong sample spacing. [Focused log](focused.log) · [Sweep](sweep.log). Independent read-only mathematical/code review found no blocking issue.

Twelve alternating load pairs per aircraft on the shared host; milliseconds include full JSON parse, validation and derivation. OS file caches are warm; no application-level model cache is used. These are loader-call timings, not total app startup or uncached-disk timings. [Raw pairs](timings.log).

| Aircraft | Old median ms | New median ms | Speedup | New min–max ms |
| --- | ---: | ---: | ---: | ---: |
| jensen_ugly_stik_60 | 123.61 | 13.91 | 8.89× | 12.13–16.54 |
| gp_extra_300s_60 | 123.73 | 13.93 | 8.88× | 12.87–21.36 |
| p51d_mustang_120 | 121.42 | 15.77 | 7.70× | 13.48–17.72 |
| sebart_avanti_s_a200 | 120.87 | 14.47 | 8.35× | 12.38–17.97 |

All latest medians improve; P-51's 15.77 ms still misses the 15 ms target. Earlier same-candidate runs under different concurrent load measured fleet medians at 15–19 ms. Do not interpret the latest lower run as universal timing acceptance. Golden flights and the isolated full-suite result are pending.


## Limits and follow-up

The historical 801-point grid remains an approximation to the continuous lift peak. This change verifies unchanged behavior, not stall calibration or independent aerodynamic validation. Large/unusual input domains use the slower fallback. The broader DATA-2 cold-load target stays open when any aircraft's measured load time exceeds 15 ms; profile remaining work before another optimization.

Knowledge base: [aircraft data pipeline](../../roadmap-investigations/09-aircraft-data-pipeline.md). Equations above are derived directly from the repository's smoothstep lift law; no third-party code or data was copied. Earlier interval-value bounds preserved the fleet angles but were slower; the curvature bound was selected after paired prototypes.
