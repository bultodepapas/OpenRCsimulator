# F6-GP-01 software input-cost comparison

This probe compares the pre-controller RcInput from commit 22b3e4825ec97289b76666ca9e942eaa7a8f703d with the current reader on the same Windows host and pinned Godot 4.7.2 executable. It measures the software path from four synthetic axis callbacks through one fixed-step poll to the four flight-command values. It is separate from the physical latency protocol in [F6a](../../radio-input/F6a/README.md).

Run the parse and input-state preflight first:

    powershell -ExecutionPolicy Bypass -File docs/research/controller-support-2026-10-14/run_cost_probe.ps1 -PreflightOnly

After the host is idle, run the default three paired repetitions:

    powershell -ExecutionPolicy Bypass -File docs/research/controller-support-2026-10-14/run_cost_probe.ps1

Each pair alternates baseline/current order. Every invocation warms the reader for 240 neutral polls, then for 1,200 active polls. It measures five batches of 2,400 polls (12,000 measured polls per invocation). The same known synthetic gamepad uses axis indices 0–3 with samples [0.25, 0.0, -0.4, 0.6], ten axis slots are returned by the reader callback, and dt is exactly 1/240 seconds. These are synthetic Godot-facing mapped-axis values supplied at the RcInput seam; the harness does not call the SDL/HID mapping or event-delivery path. Both readers are armed before measurement and start with the same 0.5 virtual rate-throttle position; connection, neutral arming and warmup are not timed. Preflight verifies that both variants produce matching commands from this input.

The timed path calls RcInput.on_motion once for each of the four sample axes, then calls poll(read_axis, dt, read_button) and reads sticks(). The released-button callback is passed to both versions. The current reader samples 128 button indices each poll; the baseline gamepad profile does not poll button state. This is part of the measured implementation difference. The controlled callback schedule is not a model of Godot/SDL delivery frequency.

The result separates event callbacks, poll-plus-command work and event-to-command work. It reports median and nearest-rank p95 in microseconds per poll, the p95 share of the 4,166.7 µs 240 Hz tick budget, and current-minus-baseline deltas. summary.json records the median of each invocation's median/p95 and the run-to-run range; runs.json preserves each invocation and batch distribution. Per-process Godot output is retained as log files.

The runner extracts only the two baseline source files from the pinned commit and builds minimal disposable resource roots under ignored .tools/controller-input-cost/. The current reader and its direct script dependencies are copied into a separate disposable root. The probe does not load the simulator scene, display, FlightSession, physics, or aircraft data. It does not call Input.parse_input_event or touch a physical controller. Timing uses Time.get_ticks_usec; the supplied dt is simulated fixed-step time, not elapsed wall time between delivered device events.

These are observational software-cost figures. The measured path is not total engine tick time, proof of remaining full-tick slack, device polling rate, physical latency, display latency, or end-to-end control latency. The separate filmed F6a protocol is required for physical latency claims. A small p95 share of the tick budget does not satisfy a physical latency gate.

## Observed software run

The native Windows run on 2026-10-14 used Godot 4.7.2-stable (official) on an AMD Ryzen 9 5900X 12-Core Processor. Three alternating process pairs ran sequentially; the Godot process list was clear immediately before and after the benchmark. Other OS background work was not controlled. Each invocation contained 12,000 measured polls. Values below are the median across the three invocation medians and p95s; each invocation's p95 is nearest-rank over its 12,000 samples. Timer values are quantized to integer microseconds.

| Timed path | Baseline median / p95 (µs) | Current median / p95 (µs) |
| --- | ---: | ---: |
| Four axis callbacks | 3 / 6 | 4 / 7 |
| Poll plus command read | 9 / 18 | 40 / 84 |
| Event to command | 12 / 23 | 44 / 91 |

For event-to-command, the current reader adds 32 µs at the median and 68 µs at p95. The baseline p95 uses 0.55% of the 4,166.7 µs tick budget; current uses 2.18%, a 1.63 percentage-point increase. Across the three invocations, event-to-command p95 ranged 22–27 µs for baseline and 84–92 µs for current. These figures describe only this synthetic software path and are not an acceptance threshold.

The full source hashes, per-invocation and per-batch distributions, and machine-readable summary are retained in [summary.json](runs/20261014T181149Z-bfe56399e695449592017d992f894a84/summary.json), [runs.json](runs/20261014T181149Z-bfe56399e695449592017d992f894a84/runs.json), and the adjacent baseline/current logs.
