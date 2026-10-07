# F3b1 — Radio event cost and optimization decision

**Status:** measurement tool and regression tests verified, 2026-10-07. F3b optimization remains open. No production input, simulation, physics, model or menu files changed.

## Run

```bash
$(app/get-godot.sh) --headless --path app --import
$(app/get-godot.sh) --headless --path app --script res://tests/bench_radio_events.gd
```

The benchmark prints one `F3B_RESULT` JSON record with engine/OS/CPU identity, workload and seven sample averages per path. Each pass sentinel-clears the reader first and checks its final values independently, so the handler pass cannot hide a missing dispatch pass. It uses the real flight scene and an armed fake radio; physics and render processing are stopped during timing. Fresh motion events are constructed **outside** the timed region. Reusing a parsed event makes Godot warn and invalidates the run. Prepare imports first; a run with engine errors is invalid even if a result line exists.

The workload represents four axes reporting 1,000 events/s each, normalized to 60 Hz: 80,000 events / 1,200 modeled frames per round, after 8,000 warmup events. All four axes vary; the benchmark checks their final received values. `handler` calls the real `FlightSession._input`; `dispatch` calls `Input.parse_input_event` through the live scene tree. Both include loop/call overhead; dispatch includes engine and scene-tree propagation. Event construction, physics, rendering and idle time are excluded.

These are **amortized CPU costs per modeled frame**, not actual frame-time samples, percentiles, USB report intervals or input latency. A 4 kHz synthetic workload does not prove physical-radio throughput. The normal timing tests do not impose machine-dependent pass thresholds in CI.

## Measured decision

Source baseline: `f516ff208f50833b80c18f21c32411bce7c9b653`, Godot 4.7.2, Linux KVM / Intel i5-10500 host. Each comparison used three processes per variant, alternating order, seven warmed rounds per process. The host was shared with regression tests and other development; the spread prevents a strong speedup claim. Values below are medians of the three process medians, in µs per modeled 60 Hz frame.

| Comparison | Reader history | Handler | Full dispatch |
| --- | --- | ---: | ---: |
| A baseline | Dictionary | 60.78 | 341.08 |
| A candidate | Ten-bit integer | 57.75 | 344.52 |
| B baseline | Dictionary | 60.03 | 324.99 |
| B candidate | Ten-byte array | 56.88 | 327.66 |

The smaller handler medians did not become a stable full-dispatch gain. For example, B baseline handler medians ranged 51.84–67.70 µs and candidate medians 54.11–62.26 µs. **Neither candidate is adopted.** Keep the current reader and measure on a quieter host before changing it for performance. Do not stop forwarding events after arming: late-seen axes, updated raw values and the F6a marker still need them.

Raw results: [A](bitmask-measurements.json), [B](bytes-measurements.json). Reversible experiment patches: [integer](bitmask-experiment.patch), [byte array](bytes-experiment.patch); apply only in a disposable checkout of the named baseline. [Frozen measurement harness](bench_measured.gd) preserves the measured source; the public harness additionally verifies every pass with sentinel-cleared axes, adds an explicit enum cast outside timing and names an unused loop variable. The timed loops are unchanged. The [final harness run](benchmark-final.log) passes; [removing dispatch calls](benchmark-mutation.json) now fails all 32 dispatch delivery checks and prints no successful result. Early trials with missing imports or reused events were discarded and are not included in these tables.

## Verification

- `test_rc_axis_history.gd`: 9,251 checks over every one of the 1,024 possible reported-axis sets. Covers independent axes, invalid indices, other devices, polling without events, safe throttle arming, disconnect/reconnect, profile replacement and continued updates after arming. [Passing log](axis-history.log).
- [Disposable mutation checks](mutations.py): dropping events after arming and ignoring axis 9 both fail; the unchanged reader passes. [Results](mutations.json).
- The test also passed on both experimental readers; correctness alone did not justify adopting them.
- Full isolated `app/test.sh` exits 0: 99 existing test programs, model contracts, four aircraft traces and identical default/wake/swirl state hashes at 30/60/144 FPS. New test and final benchmark ran separately against the same unchanged production baseline. [Suite log](suite.log), [source hashes and verification](verification.json). Skill lint has no new diagnostics; the 12 existing warnings remain outside this change. The new history test also passes with the debugger enabled and no warnings.

F3b1 closes the measurement slice only. F3b's optimization and F6's physical stick-to-screen measurements remain separate open work.
