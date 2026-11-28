# NK-9a — the statistics detector's speed window in the native kernel

2026-11-28. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick main-thread cost](../../../plans/optimization-priorities.md).

## Why

The flight statistics run on every accepted tick, about 65 µs per tick in the live app:
- `fixed_wing_adapter.sample()` builds the sample;
- `service._observe` feeds it to `detector.observe`.

Headless, on real airborne Corsair samples, `observe` cost 18–19 µs per tick, and 12.8 µs of that was the speed
window. Each tick it appends dictionaries to the window and the pending candidates, trims them, duplicates and sorts
both 60-value speed lists for the medians, and commits mature candidates. Without the window, `observe` cost 6 µs.

## Change

- `nk_stats_speed.hpp` holds one detector's speed window and reproduces `_collect_speed` and its helpers exactly:
  - the window, the pending candidates, the previous accepted sample and the rejection counts, in insertion order;
  - GDScript's operation order and margins;
  - the engine's own `PackedFloat64Array.sort()`, `maxf` and `absf`, so equal values, signed zeros and comparisons
    behave as in GDScript;
  - the flight maxima written into the detector's own `flight` dictionary only when a candidate is committed, and
    for each speed only when it is stable.
- The kernel binds it as `stats_speed_*`; each detector holds its own kernel instance.
- `detector.gd` binds the window at `configure` and `restore`, with its resolved thresholds and cap. While bound,
  `_collect_speed`, `_clear_speed_state`, `_start_flight`'s count reset and `snapshot` use the kernel. Every other
  rule (phases, episodes, accidents, semantic events) stays in GDScript.
- Snapshots exchange the detector's own dictionaries: String keys in the order of GDScript's quoted literals.
  `restore` passes the restored fields to the kernel only in that canonical form (ordered keys, int ticks and counts,
  float numbers). A JSON round trip sorts keys, so such a snapshot keeps the GDScript fields, unchanged.
- Hook: `Detector.native_speed_enabled`, read when a detector is configured or restored.

## Evidence

- `app/tests/test_native_stats_speed.gd` (8 checks) records real accepted-tick samples from the Corsair, the glow
  Stik 61FX and the electric Stik 6S: 3,600 ticks each of climbs, turns and dives.
  - Each stream feeds a native and a reference detector. It runs once as recorded and once with faults after the
    flight starts:
    - speed spikes and position jumps;
    - NaN, over-cap and −0 speeds;
    - int speeds, an Array of ints and a missing or short vector;
    - rare incident and ground-contact flags;
    - one late tick gap.
  - After every sample the observe events, the snapshots and the flight records are byte-identical.
  - Every rejection reason occurs: acceleration, invalid sample, position discontinuity, speed cap and unsteady
    window.
  - Every 700 samples both detectors restore from a snapshot: canonical snapshots keep the native window, a JSON
    round trip keeps the GDScript one, and both continue equal.
  - The detector test's eviction fixture compares native against GDScript after every tick. Its rules override 16
    samples and a 0.5 s window. A `dt` burst evicts several entries in one tick. It also has signed zeros, a NaN
    speed and speeds over a 3 m/s profile cap. Count eviction and multi-entry eviction both occur.
  - A 10⁻⁹ change to the window's span is detected.
- 51 suites pass on the installed binary: every `test_native_*` script and every flight-statistics suite, including
  `test_flight_statistics_detector`'s spike-filter and restore-and-eviction cases.
- Independent review found no exactness bug. It checked operation order, the sort input, the sample reads, the
  flight maxima writes, the canonical-only restore and the lifetime. Its coverage gap (rules overrides, count and
  multi-entry eviction) is closed by the eviction fixture above.
- All nineteen installer gates pass for binary `83d56185e9d87cd82b7041f9a5a175b3c9f089102ffbe37888b717b1977ebba0`,
  and the mutant build still fails. Accepted results (tool root, not in Git):
  - `stage-20261128T092243481144Z.json` `848d779d7322bc043107665b6370f1b35a19d562c0cab719b1e60883479a5dd2`
  - `stage_mutant-20261128T092308770757Z.json` `5141bb9bdfef027a681d1fe1da91955defd6c21160f569db3f1a063a6eb2b01f`
  - `trajectory-20261128T092335445715Z.json` `d2f7f16a0f42ce8814e12bb48700b227029bb7c379ece9244d5f04a6498e4771`
  - `legacy-ground-20261128T092713181008Z.json` `ae30a50898d131ee02876710f2b2d93f837b345c2022c76dc33e196f48763b7d`

## Gain

Headless, the same 4,000 airborne Corsair samples, median `detector.observe` after the window fills, three rounds:
18–19 → 7 µs per tick.

## Scope

- Windows x86_64 only. The macOS and Linux parity runs are not done yet.
- The sampler (`fixed_wing_adapter.sample`, about 33 µs live) and the rest of the detector stay in GDScript.
