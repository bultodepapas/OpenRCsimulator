# G2a-R1 serial step cost

2026-10-09 · **Status: observational software measurement; performance acceptance open.**

The same benchmark ran first against the clean pre-optimization archive, then against the candidate. No other Godot process ran during these measurements. Each fixture uses seven timed batches of 240 steps, each after reset and 240 warm-up steps. These are medians of batch means, not individual-tick tails. Shared-host load and sequential ordering limit causal timing conclusions.

| Air | Fixture | Integrator | Baseline (µs) | Candidate (µs) | Change |
| --- | --- | --- | ---: | ---: | ---: |
| calm | trim | split | 524.8 | 529.2 | +0.8% |
| calm | trim | coupled-rk4 | 1345.4 | 730.1 | -45.7% |
| calm | punch | split | 503.9 | 502.2 | -0.3% |
| calm | punch | coupled-rk4 | 1308.4 | 761.2 | -41.8% |
| hot-high | trim | split | 513.4 | 531.9 | +3.6% |
| hot-high | trim | coupled-rk4 | 1313.9 | 765.1 | -41.8% |
| hot-high | punch | split | 830.6 | 518.0 | -37.6% |
| hot-high | punch | coupled-rk4 | 1390.3 | 755.3 | -45.7% |

Coupled medians fell by 41.8–45.7% in these four fixtures, to 730–765 µs/step. The 500 µs target remains open. The unchanged split hot-high punch also has a large timing difference, demonstrating shared-host/sequential variability; do not interpret these observations as isolated causal percentages or individual-tick latency bounds.

[Comparison](cost-comparison.json) and [baseline](cost-baseline.json)/[candidate](cost-candidate.json) preserve all measured batch means. The [benchmark](../G2a-RK4/cost.gd) excludes trim, audio and rendering. The 500 µs target must be assessed separately from numerical parity and this shared-host measurement.

**Reproduce:** `python3 docs/research/propulsion/G2a-R1/cost_compare.py --baseline /tmp/openrc-stage-baseline --out docs/research/propulsion/G2a-R1`.
