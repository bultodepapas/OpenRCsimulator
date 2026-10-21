# Observation ABBA timing supplement (2026-10-21)

This records one bounded, headless microbenchmark of the airspeed-preserving `Agent.observation()` candidate. It is supplemental to the R5 output-parity evidence and makes no production or whole-flight performance claim. No runtime source was changed for this run.

The run used the exact R5 companion sources in `D:/OpenRCsimulator-AFC-work/observation-airdata-scratch-20261021`. A real count-1 player, manager and companion advanced together for 1,200 ticks at 240 Hz (5.0 seconds), beyond the gentle-practice gust delay of 3.0 seconds. The fixture then stayed frozen while the production `Agent.observation()` and a research subclass override shared the same session, state and weather. The override changed only the observation method. Both arms entered through `agent.call("observation")` at the same dynamic call depth.

After two excluded ABBA warmup rounds, the probe ran 240 rounds in A1/B1/B2/A2 order with 1,024 calls per block. It retained 480 block samples per arm (491,520 calls per arm). A sample is the elapsed time for an entire block and its block-averaged microseconds per call; the percentiles below describe those block means, not individual-call latencies. Snapshot-byte parity and state fingerprints were checked outside timed blocks after every complete round.

| Arm | Mean of block means (µs/call) | p50 block mean | p95 block mean | p99 block mean |
| --- | ---: | ---: | ---: | ---: |
| Production `Agent.observation()` | 23.7353 | 23.0254 | 27.9033 | 35.9922 |
| Research subclass override | 16.7959 | 16.1797 | 21.0010 | 26.6826 |

Across the 240 paired ABBA rounds, the candidate-over-baseline block-mean ratio averaged 0.7076; the median was 0.7034 and the 95th percentile was 0.7673. The maximum was 1.0393, so at least one paired round favored the baseline. These ratios describe this one method-level measurement on this prepared state and host. They do not predict manager callback, flight, render-frame, fleet or target-hardware cost.

All 240 post-round checks reported byte-equal snapshots and unchanged session state, with one stable state fingerprint. The probe's completed report also requires the outside-block warmup parity check to pass. Every source hash in the before/after maps matched. The checked runner passed in 26.672 seconds under its 90-second timeout; it captured no Godot `ERROR` or `WARNING` diagnostics. The engine log contains two app-level aircraft-inertia advisory lines during fixture setup.

The host was Windows on an AMD Ryzen 9 5900X, with Godot 4.7.2 stable and unchanged 240 Hz physics. The captured Godot process inventory was empty immediately before and after the run. See [preflight](preflight.json), [postflight](postflight.json), and the full [timing receipt](receipt.json) for source, tool, host and artifact identities.

The immutable probe output with all 960 raw block samples is [here](raw/observation-abba-report.json). The checked-runner report and captured engine log are [here](runner/checked-runner-report.json) and [here](runner/engine.log). [The offline reducer](reduce_abba.py) validates sample accounting, round pairing, parity, state stability and source stability, and writes [verification.json](verification.json), including all 240 paired ratios. Exact probe, subclass, scalar helper and checked-runner source copies are in [sources](sources/).
