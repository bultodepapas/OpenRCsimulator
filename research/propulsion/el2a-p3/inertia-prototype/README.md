# EL2a-P3 inertia-cache experiment

2026-10-11 · **Status: NOT ADOPTED.**

Base: `b5febac` (EL2a-E1). This bounded scratch candidate touched only `sim/simulation.gd` and `sim/flight_session.gd` in a separate app copy. No production source was changed.

The candidate routes the two coupled-response inertia-inverse call sites through a reset/step cache. It revalidates all six inertia values and exact source bytes on each callback, computes a fresh inverse if public inertia changed (including signed zero), and returns a duplicate so callers cannot mutate simulation-owned cache storage. Reset, step refresh, and checkpoint restore keep the byte snapshot current. Mid-step mutation preserves the existing body tick-local inverse.

Proof: `test_inertia_inverse_cache.gd` passed 34/34 focused assertions. It checks unprimed and out-of-step calls, stage parity against fresh inversion, same-tick public inertia mutation, mutation of the returned packed array, signed-zero-only changes, and checkpoint restore. `correctness.log` contains the run output.

Diagnostic timing: four alternating 100k-call pairs measured the accessor at 126,616–146,407 µs versus 68,089–87,164 µs for direct inversion; ratios were 1.54×, 1.79×, 2.02×, and 1.91× slower. The run overlapped the root's Linux app suite, so treat timing as exploratory rather than acceptance evidence. Input/output bytes were checked outside timed loops. Full output is in `diagnostic-timing.log`.

Decision: reject. Exact byte revalidation, array checks, and the required detached return cost more than computing this six-value inverse. Reconsider only if the inverse is consumed through an internal non-escaping path that avoids a packed-array copy, then benchmark under an idle host. The candidate intentionally does not alter the simulation tick cache's existing numeric-equality policy.
