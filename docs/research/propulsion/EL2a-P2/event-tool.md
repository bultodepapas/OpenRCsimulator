# EL2a-P2 Event Comparison Tool

Date: 2026-10-11

**Status:** The comparison runner and whole-session probe are ready; one-case smoke passed. The repeated full comparison has not been run.

Step ID: EL2a-P2

## Purpose and contract

[`event_probe.gd`](../../../../research/propulsion/el2a-p2/event_probe.gd) creates a fresh trimmed `FlightSession` per case and runs at 240 Hz. Its full set covers near-empty 4S and 6S battery exhaustion under powered and coasting conditions, fixed-voltage rotor stop after throttle cut, and a battery no-event control. The fixtures are synthetic and establish event-handling behavior, not aircraft performance.

[`compare_events.py`](../../../../research/propulsion/el2a-p2/compare_events.py) copies and hashes both app snapshots, records the pinned Godot build, then alternates baseline/candidate execution order. Each event sample is the accepted full-tick endpoint. Timing covers only the simulation tick where an event is observed. It does not expose or compare crossing-root bits.

The runner checks repeated seed and endpoint checkpoint bytes and event-state replay within each implementation. For the no-event control, baseline and candidate seed and endpoint native checkpoint bytes must match exactly. Event comparisons require the same event types and containing ticks, then bound absolute state differences: body components and wash velocity `1e-8`, rotor speed `1e-5 RPM`, remaining charge `1e-8 C`, terminal energy and pack heat `1e-6 J`. Charge must reach exactly zero, accepted rotor speed must stay nonnegative, and sampled state must remain finite.

## Smoke evidence

One smoke round passed for the 4S powered battery case against baseline revision `5f85109ada405071864ee1c3c5c2a97ecaa4bc84`, using Godot `4.7.2.stable.official.ed1daf0bf` (SHA-256 `8d106cbe6144c2dc7e881d61d2429c1a8a76e6b22ef48bd5e48dcf934953f71e`). The event was observed at tick 1; seed checkpoint bytes matched across builds, and all measured event-state differences were within the declared limits. The single-round smoke does not establish replay repeatability. A later static hardening added strict continuous-state layout checks; the current runner needs a smoke after substantial timing work is cleared. The durable local smoke report is `/home/bulto/openrc-el2a-p2/event-tool-smoke-20261011-02/comparison.json`.

This single-case smoke validates runner wiring only. Its timing samples are not a performance result. Run the full comparison only after the production snapshot is fixed and the parent has cleared substantial timings:

```sh
python3 research/propulsion/el2a-p2/compare_events.py \
  --baseline-app /path/to/baseline/app \
  --candidate-app /path/to/candidate/app \
  --godot /path/to/pinned/Godot_v4.7.2-stable_linux.x86_64 \
  --out /absolute/durable/path/el2a-p2-event-comparison \
  --rounds 5
```

Use the same pinned engine for both snapshots and a fresh absolute output path. The runner rejects baseline revisions other than the pinned baseline by default, records source hashes and run order, and preserves logs, JSON reports, checkpoint bytes and isolated app snapshots under `--out`.
