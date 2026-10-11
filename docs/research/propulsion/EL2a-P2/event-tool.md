# EL2a-P2 Event Comparison Tool

Date: 2026-10-11

**Status:** Complete. Six final paired rounds pass all six cases, replay, layout and state-tolerance checks.

Step ID: EL2a-P2

## Purpose and contract

[`event_probe.gd`](../../../../research/propulsion/el2a-p2/event_probe.gd) creates a fresh trimmed `FlightSession` per case and runs at 240 Hz. Its full set covers near-empty 4S and 6S battery exhaustion under powered and coasting conditions, fixed-voltage rotor stop after throttle cut, and a battery no-event control. The fixtures are synthetic and establish event-handling behavior, not aircraft performance.

[`compare_events.py`](../../../../research/propulsion/el2a-p2/compare_events.py) copies and hashes both app snapshots, records the pinned Godot build, then alternates baseline/candidate execution order. Each event sample is the accepted full-tick endpoint. Timing covers only the simulation tick where an event is observed. It does not expose or compare crossing-root bits.

The runner checks repeated seed and endpoint checkpoint bytes and event-state replay within each implementation. For the no-event control, baseline and candidate seed and endpoint native checkpoint bytes must match exactly. Event comparisons require the same event types and containing ticks, then bound absolute state differences: body components and wash velocity `1e-8`, rotor speed `1e-5 RPM`, remaining charge `1e-8 C`, terminal energy and pack heat `1e-6 J`. Charge must reach exactly zero, accepted rotor speed must stay nonnegative, and sampled state must remain finite.

## Recorded comparison

[Final comparison](performance/comparison.json) uses baseline revision `5f85109ada405071864ee1c3c5c2a97ecaa4bc84` and Godot `4.7.2.stable.official.ed1daf0bf` on an AMD Ryzen 9 5900X under WSL2. Six alternating AB/BA rounds give six samples per event and implementation. All twelve complete probe reports pass the final strict validator; their logs and native checkpoint bytes are retained under [performance/runs](performance/runs/). See the [result table and limitations](README.md#performance).

The [snapshot manifest](performance/source-manifest.json) hashes every copied app file, including non-executable artifacts. Its ten changed paths comprise five intentional source/test changes, four baseline-only Python cache files and one generated, untracked baseline-only test `.uid`. The latter artifacts are not runtime changes. Event trial maps and normal flight results are qualified separately.

Reproduce the comparison on a fixed production snapshot with no concurrent test or rendering workloads:

```sh
python3 research/propulsion/el2a-p2/compare_events.py \
  --baseline-app /path/to/baseline/app \
  --candidate-app /path/to/candidate/app \
  --godot /path/to/pinned/Godot_v4.7.2-stable_linux.x86_64 \
  --out /absolute/durable/path/el2a-p2-event-comparison \
  --rounds 6
```

Use the same pinned engine for both snapshots and a fresh absolute output path. The runner rejects baseline revisions other than the pinned baseline by default, records source hashes and run order, and preserves logs, JSON reports, checkpoint bytes and isolated app snapshots under `--out`.
