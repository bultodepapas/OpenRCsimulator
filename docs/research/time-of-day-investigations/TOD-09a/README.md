# TOD-09a — Exact solar clock foundation

2026-10-10 · Status: implemented and software-verified; full regression passed. Visible progression is not enabled.

[Plan](../../../TIME-OF-DAY-PLAN.md) · [Render consumer audit](render-update-audit.md)

## Scope and integration boundary

The existing app keeps its applied time fixed. This step supplies the pure clock needed by later progression: [solar_clock.gd](../../../../app/environment/solar_clock.gd). It reads only an explicit anchor and simulation tick; it never reads system time, frame delta, shader time, rendering state or physical weather.

The current scene-update path rebuilds the full field on a paused edit. Optional scenery also bakes Sun direction into shadow meshes. TOD-09b must replace that path for continuous updates and prove shadow/material coherence before TOD-09c connects this clock to flight, menus, CLI, recordings and checkpoints. The [audit](render-update-audit.md) identifies each consumer and the remaining proof.

`openrc-visual-timeline v1` and `openrc-visual-checkpoint v1` retain their fixed-time contracts. A solar-clock record is not an accepted replacement for either. The new kernel has no production Main hook, preference key or progression switch, so it does not silently change existing recordings or flight behavior.

## Clock contract

A strict `openrc-solar-clock v1` record contains `anchor_tick`, `ticks_per_second` (exactly 240), `rate` (0 or 1), validated lighting `config`, and `subsecond_ticks` (0…239). Tick values are integers in 0…2^53−1 so native and JSON round trips agree. Integral JSON floats normalize to integers; strings, booleans, nonfinite/fractional ticks, missing/unknown fields and other rates/frequencies are rejected. Moving time requires astronomical mode; legacy daylight supports only rate zero.

- `create(config, anchor_tick = 0, rate = 0)` creates a detached anchor at a whole civil second.
- `validate(record)` validates and returns a detached normalized clock.
- `evaluate(record, tick)` returns the civil config and exact fractional tick at that tick, without mutating either input. Queries before the anchor are rejected; query order has no effect.
- `reanchor(record, tick, rate, config = null)` changes rate without losing the fractional phase. An explicit new civil selection resets the fraction to zero. It requires the old clock to evaluate successfully at the specified tick.

Gregorian arithmetic is integer-only. It handles midnight, month/year boundaries, leap day in 2000/2024 and the non-leap year 2100. The UTC offset and location remain explicit and fixed: there is no automatic DST lookup. The supported local-date domain is 2000-01-01 through 2100-12-31. Advancing beyond it returns an error instead of clamping or wrapping, even for a huge tick jump. A controller must stop/reselect before that boundary; creating a fresh valid anchor is the explicit recovery operation.

The exact phase survives stop/resume at subsecond ticks. Existing `SolarPosition.evaluate` accepts whole civil seconds, so the sample's config represents the containing second while `subsecond_ticks` retains the remainder. Later rendering should key updates to the resolved civil second, not assume a reanchored clock crosses seconds at `tick % 240 == 0`. This kernel does not claim subsecond solar interpolation.

The serialized 240 Hz matches the production project today. A future session adapter must check its actual fixed-step clock before accepting an anchor; changing render FPS does not change this frequency. Restart should create a new anchor from the configured start selection, not the elapsed sample. Pause/focus/crash handling must continue to freeze the authoritative simulation tick; no second wall-clock timer belongs here.

## Proof

[Tests](../../../../app/tests/test_time_of_day_clock.gd) pass 1,656 checks. The [fixture generator](../../../../research/time-of-day/tod-09a/calendar_oracles.py) uses Python's independent standard-library Gregorian arithmetic and an explicit random seed, never host date/time. Its 184 cases include every February rollover from 2000 through 2100, UTC offsets, year boundaries, exact tick-limit anchors, fractions and multi-day jumps. The app runner checks that the committed fixture still matches the generator.

Additional tests cover invalid records, detached inputs/outputs, 100 stop/resume cycles with no lost fractional ticks, same-tick rate edits, explicit retiming, restart construction, domain overflow and repeated held-tick sampling. Sample histories at 30/60/144 FPS produce identical clock results and lighting snapshots at the same tick. These are pure known-tick proofs, not claims that production progression or its lifecycle integration already exists.

```bash
python3 research/time-of-day/tod-09a/calendar_oracles.py --check
"$(app/get-godot.sh)" --headless --path app --script res://tests/test_time_of_day_clock.gd
"$(app/get-godot.sh)" --headless --path app \
  --script "$PWD/research/time-of-day/tod-09a/clock_probe.gd" -- --out=/tmp/tod09a-clock.json
app/test.sh
```

The [CPU probe](clock-probe.json) evaluates 5,000 samples per case after warmup. On this shared host during regression work, clock-only p50/p95 were 54/93 µs; clock plus lighting snapshot p50/p95 were 80/116 µs. This is exploratory CPU timing, includes validation/copying, and excludes scene updates, rendering and GPU cost. It establishes no target frame budget. Its hourly samples cross New Year without repeating the prior date.

The [check summary](check-summary.json) records the final source hashes and results:

- `app/test.sh`: exit 0; 154 GDScript test programs, model contracts, trace/CLI checks, golden flights, ground-contact regressions and complete-state 30/60/144 FPS checks passed. [Full log](full.log.gz).
- Focused clock test: 1,656 checks, zero failures. [Log](focused.log.gz).
- Static lint: zero errors, 12 existing warnings. [Report](lint.json.gz).
- Scene smoke: three scenes passed, zero errors/findings; 317 existing warnings. [Report](smoke.json.gz).
- Linux export: legacy daylight and astronomical midnight start from an empty working directory with exit 0, no engine errors and identical 25-row physical samples. This verifies the existing fixed-time app, not production clock integration. [Report](export-smoke.json), [build log](export.log.gz).

[SHA256SUMS](SHA256SUMS) covers this evidence folder. Target-GPU/display and pilot acceptance remain open, as in TOD-08b.
