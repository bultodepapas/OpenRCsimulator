# D6b-R2 radio event cost probe

2026-10-09 · **Status: observational software measurement; no performance-gate acceptance.** [Owning report](../README.md).

Observational synthetic benchmark run on 2026-10-09T13:34:07.296787+00:00 with Godot 4.7.2-stable (official) on Intel(R) Core(TM) i5-10500 CPU @ 3.10GHz.

The original and current readers were measured from disposable copies of the same app tree. Both copies have the same D1-R5 aircraft-data file (`95f8886a4a6d309ad5f749acc7ef98e4cf21b62615703c606dc94c8f68571348`). The original reader is `/tmp/openrc-d6b-r2-original-reader.gd`; the current reader is the repository copy at run time. A private copy of the existing benchmark harness adds only a SAFE regime switch and output annotation. Each process verifies delivery of all four axes. ARMED runs start with `radio.armed=true`; SAFE runs start with `radio.armed=false`, and physics polling is disabled, keeping the reader on the unarmed event path throughout.

At 4,000 synthetic events/s, median event costs across three invocations were:

| Regime | Path | Original (µs/event) | Current (µs/event) | Difference | Estimated added time per 60 Hz frame |
| --- | --- | ---: | ---: | ---: | ---: |
| ARMED | handler | 0.829 | 0.858 | +0.029 µs/event (+3.5%) | +0.0019 ms/frame |
| ARMED | dispatch | 4.486 | 4.794 | +0.308 µs/event (+6.9%) | +0.0205 ms/frame |
| SAFE | handler | 0.804 | 1.219 | +0.415 µs/event (+51.6%) | +0.0277 ms/frame |
| SAFE | dispatch | 4.734 | 5.120 | +0.386 µs/event (+8.2%) | +0.0257 ms/frame |

`handler` calls the app input handler directly; `dispatch` measures `Input.parse_input_event`. Event creation and physics/render work are outside the timed region. The SAFE harness never polls, so it measures a sustained unarmed path and is conservative for a real flight that polls and arms after observing low throttle. Concurrent app-suite load was present, making these figures observational rather than a performance gate. Raw logs and per-run medians are in `run-*.log` and `summary.json`; `runs.json` preserves the complete machine-readable records. Each run emitted the same nonfatal D1-R5 aircraft-data inertia warning before timing and no engine/script errors.
