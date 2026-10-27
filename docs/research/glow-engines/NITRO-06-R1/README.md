# NITRO-06-R1 — Share the nozzle-flow terms inside the carburettor root solve

**Superseded 2026-10-27 by [NITRO-06-R3](../NITRO-06-R3/README.md):** the root now has a closed form, so the shared-term loop no longer exists in `carburetor.gd`. This record keeps the measurements of that interim step.

2026-10-27. Working-tree change on baseline `b6e3fe7d4`. Headless CPU evidence on the Linux
dev VM (Godot 4.8-beta1 official editor binary, shared host); not FPS, release-build or
target-hardware qualification. No law, constant or trace identifier changes.

## Finding and change

A script profile of the glow Stik (`stik-glow-61fx-2t`) idling on the runway put the step
at 116.6 ms per profile sample, against 67.5 ms for the electric Stik. Within it,
`Carburetor.charge_ratio` took 16.5 ms over 1,464 solves, with 68,076 calls of
`_flow_function_slope`: about 46 Newton/bisection iterations per solve. Every iteration
called `flow_function(r)` and `_flow_function_slope(r)`, which evaluate `r^k`, `r^(1/γ)`
and the same square root with identical expressions, each through `math3d.gd` wrappers.

The loop now evaluates those three terms once per iteration for `r` in `(r_c, 1)` and
calls the original functions outside that interval, keeping every expression's operand
order. `flow_function` and `_flow_function_slope` stay as the public and reference
formulas, and the Python mirror `research/glow-engines/carburetor.py` is unaffected.

## Parity

[`carburetor_pair.gd`](../../../../research/performance/carburetor_pair.gd) compares
`HEAD`'s script with the candidate, bytewise:

- `charge_ratio` over 506,348 inputs: a geometric sweep of y from 0.4 to 10⁴ in 0.002%
  steps plus NaN, ±INF, −1, ±0, 1e-300, the choke ratio and its next double, 1 and
  1e300: **0 mismatches**.
- `admission` over 60,802 combinations of opening (0.02–1), speed (0–18,000 rpm) and two
  capacities: **0 mismatches**.

`session_probe.gd --case=runway` for the glow Stik gives one state fingerprint across all
six runs below. Of 26 glow, NITRO and golden scripts ([run summary](tests.txt)), 25 pass,
including `test_golden`, the glow oracle (723 checks), traces (286) and byte-exact stage
reuse (2,000 load checks). `test_glow_dive_support` fails 2 of 10 checks for the Extra
300 dive (pitch −32°, peak 39.3 m/s, 13,156 rpm). It fails identically with the baseline
`carburetor.gd`, so the failure predates this change and belongs to its owner.

Attribution: running the test in hard-linked snapshots of `app/` set to older commits (the
shared tree untouched), it passes at its introduction `40749e42c` and fails from merge
`58f3a3a22` onwards (binary search over 241 first-parent commits: last pass `6827201cc`).
The passing commit with only `gp_extra_300s_60.json` from `58f3a3a22` reproduces the same
two failures exactly. That file's sole change raises `wing_aileron_effectiveness` from
0.34067 to 0.467909, the [D11-R1](../../aero-consistency/D11-R1/README.md) recalibration,
whose evidence does not list this test.

Diagnosis and repair (same day): the fixture pushes over with full-down elevator at 30 m/s.
Since D11-R1 the Extra departs there into a sustained negative-g rotation (roll rate about
−1.2 rad/s, pitch −32° after 12 s) instead of diving; the engine is never exercised. The push
sits on a departure edge: capping it at −0.8, −0.6 or −0.4 stick, or changing the roll-damper
gain to 1.0 or 0.25, each gives the intended dive (−78.8°, 66 m/s, 18,100 rpm peak). A higher
roll gain makes the glow Stik tumble instead, so the test now caps the push at −0.6. The glow
Stik is unchanged by the cap (20,072 rpm peak either way, a thin pre-existing margin over its
20,000 rpm check). `test_glow_dive_support.gd` passes 10/10.

## Cost

| Measurement | Baseline | Candidate | Change |
| --- | ---: | ---: | ---: |
| `charge_ratio`, 20,000 interior solves, median of 12 alternating rounds | 7.53 µs | 5.37 µs | −29% |
| Glow runway session, pair 1, median µs/tick | 5,216 | 5,300 | +1.6% |
| Glow runway session, pair 2 | 5,371 | 5,044 | −6.1% |
| Glow runway session, pair 3 | 5,263 | 5,058 | −3.9% |

The session pairs are noisy (median −3.9%); the expected effect is about 4% of the
step, since the solve was 14% of the profiled step. Treat the component result as the
evidence.

## Owner candidate: the solve mostly bisects

An instrumented copy of the unchanged algorithm (no output difference) over 11,870 values
of y between 0.53 and 200 needed 3–58 iterations; none reached the 64-iteration cap.
Long solves cluster at 53–57 iterations, which is pure bisection from the initial
bracket, and the runway idle averages about 46. `ROOT_TOLERANCE` is 1e-15, below the
noise of `h = r − y·g(r)` near `r = 1`, so the stop usually comes from the bracket width,
not the residual. A better start (for example the previous stage's root) or a tolerance
at the residual noise floor would cut most iterations, but it changes roots at the
ulp level: a physics change for the NITRO owner, with fingerprints and glow traces
re-qualified. The [X8-12 lesson](../../../LEARNINGS.md) describes the same pattern for trim.
