# NITRO-06-R3 — Closed-form carburettor root

2026-10-27. Owner-approved physics change at the round-off level ("faster carburettor
solve"). Replaces the iterative solve and its NITRO-06-R1/R2 cost repairs. No law, constant,
schema or trace-identifier change. Headless evidence on the Linux dev VM (Godot 4.8-beta1
official editor binary); not native or release-build qualification.

## Derivation

NITRO-06 solves `r = y·g(r)` for the manifold pressure ratio `r ∈ (r_c, 1)` with
`g(r) = r^(1/γ)·√(c(1 − r^k))/Ψ_c`, `k = (γ − 1)/γ`, `c = 2γ/(γ − 1)`. Substituting
`t = r^k` gives `r^(1/γ) = t^(1/(γ−1))` and `r = t^(γ/(γ−1))`, so the balance reduces to

`t = A·√(1 − t)`, with `A = y·√c/Ψ_c`.

Squaring gives `t² + A²t − A² = 0`, whose root in `(0, 1)` is
`t = 2/(1 + √(1 + 4/A²))` (the cancellation-free form), and `r = t^(γ/(γ−1))`. The choked
branch (`y ≤ r_c`) is unchanged and the two branches meet within 1 ulp at `y = r_c`.

The former solve started Newton at the bracket midpoint and fell back to bisection whenever
a step left the bracket, which near `r → 1` was most of the time: 22 iterations on average
over a sweep and about 46 at the glow Stik's runway idle, each with five `pow`/`sqrt` calls
through `math3d.gd` wrappers.

## Accuracy

A 50-digit `mpmath` reference of the same equation, with the same rounded constants, over
14,075 demand ratios from the choke ratio to 10⁴ (prototype script retained beside the
evidence as [closed_form.py](closed_form.py)):

| Quantity | Former iterative solve | Closed form |
| --- | ---: | ---: |
| Root `r`, worst error | 10.7 ulp | 7.9 ulp |
| Admission `r(a/x)/r(1/x)`, 30,300 cases, worst error | 19.9 ulp | 12.8 ulp |

In the engine, [`carburetor_pair.gd`](../../../../research/performance/carburetor_pair.gd)
`--max-ulp=32` against the previous script: roots within 18 ulp over 506,348 inputs, and
admission within 30 ulp over 60,802 cases (the two methods' errors added). NaN, ±INF,
negative, ±0 and choked inputs stay bytewise equal. The independent Python bisection mirror
`research/glow-engines/carburetor.py` and its 1e-12 known answers are unchanged.

## Cost

`charge_ratio` over 20,000 interior demand ratios, median of 12 alternating rounds:
6.34 → 0.43 µs per solve (×15).

Glow Stik runway session (`session_probe.gd --case=runway`, 14,400 sampled ticks), baseline
NITRO-06-R2 (iterative solve with the root memo) from a hard-linked app snapshot:

| Pair | R2 median µs/tick | R3 median µs/tick | Change |
| ---: | ---: | ---: | ---: |
| 1 | 4,855 | 4,828 | −0.6% |
| 2 | 5,329 | 4,856 | −8.9% |
| 3 | 5,083 | 4,966 | −2.3% |

The state fingerprint changes (`e6448a89…` → `ba24b999…`), as expected for a round-off-level
root change. Over R2 the tick gain is small because R2 already halved the solves; R3 removes
the iterative loop, the shared memo and its mutex, and is more accurate. Against the
original solve, R1–R3 together cut the glow runway tick from about 5.5 ms to about 4.9 ms.

## Regressions

All 36 glow, NITRO, trim (including threaded launch trim), atmosphere, air-density,
propulsion-flow and golden scripts pass ([summary](tests.txt)). `test_glow_dive_support` is
excluded as a known pre-existing failure (attributed in NITRO-06-R1).
