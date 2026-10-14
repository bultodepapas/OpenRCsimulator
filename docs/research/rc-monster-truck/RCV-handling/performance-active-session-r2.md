# Active Bisonte Session cost profile, R2

Evidence collected 2026-10-14 with the pinned Windows Godot 4.7.2 console build on an AMD Ryzen 9 5900X. The harness calls the production `Session.prepare_airfield()` path, which loads the current generated `app/data/vehicles/ground/mt8_bisonte.json`; it does not use the frozen `performance/vehicle_snapshot.json`. It builds the default production airfield course, resets to the authored `track_start`, runs 60 warmup ticks and measures 480 `Session.tick_once` calls at 240 Hz with straight throttle 0.55. There is no rendering, recording, or Track microbenchmark in the timed loop.

## Result

| Measure | Result |
|---|---:|
| Mean | 3,900.5 µs/tick |
| Median | 4,034 µs/tick |
| P95 | 4,963 µs/tick |
| Maximum | 7,145 µs/tick |
| Minimum | 2,451 µs/tick |
| Measured ticks | 480 |
| 240 Hz tick budget | 4,166.7 µs |

The mean was below one 240 Hz tick budget; P95 exceeded it by about 0.80 ms. This is a single shared-host run, not a clean-machine performance qualification. A process inventory just before the profile showed four other Godot processes, including RC session/track tests and a baseline handling probe. One of those remained in the immediate after snapshot. Their overlap and exit timing could affect this distribution; the before/after process inventories are retained as JSON.

The solver reported zero friction sweeps on 242 measured ticks and used at most 59 of the configured 128 sweeps. No measured tick hit the sweep cap. The complete sweep histogram is in the profile JSON. This observation covers this short straight-drive route only and does not bound jump, landing, braking, or sustained cornering work.

The active vehicle data identity is `mt8-bisonte-electric-4wd-estimate-v1`, SHA-256 `425f2a3fe810f82d609ad2b9dd9618b9fb45bcd813df57873cd8bc8759a750a5`. Its estimated CG height is 0.065 m, drive torque is 5.2 N·m per wheel with 120 rad/s fade, brake torque is 1.35 N·m per wheel, and front brake allocation is 0.85. The session used solver `openrc-ground-vehicle-dynamics-rk4-v3`, native backend `openrc-ground-vehicle-native-evaluate-v2` ABI 1, Windows DLL SHA-256 `adafd1f9682dff147e538fdb7686329c009edf255c639789ac28dc403bc6e65c`, default airfield course identity `9d51e40a528c3b1012457238604f9bc7356d15f92541288662eeae180221a027`, and track `bisonte-dirt-circuit`. The measured trajectory SHA-256 is `e2a01ace15ede705ee24c9c9f187029642f06e8f9ce1fbe252f5f39f6e24bb67`.

This is total `Session.tick_once` cost for the specified current model and route. The Track sampler microbenchmark in [the scalar-allocation report](performance-track-scalar-r2.md) measures only direct sampler calls against a preserved reference. These separate measurements do not attribute a whole-tick speedup to the sampler change.

## Reproduction and retained artifacts

Run from the repository root:

```powershell
$Godot = '.tools/Godot_v4.7.2-stable_win64_console.exe'
$Output = "$PWD/docs/research/rc-monster-truck/RCV-handling/performance-active-session-r2.json"
& $Godot --headless --audio-driver Dummy --path app --script `
  "$PWD/research/rc-monster-truck/performance-r2/bench_active_session.gd" `
  -- --output=$Output
```

- [Full profile JSON](performance-active-session-r2.json): per-tick timings, sweep histogram, model/course/backend identities, and trajectory digest.
- [Console log](performance-active-session-r2.log)
- [Source hashes before](performance-active-session-r2-source-before.json) and [after](performance-active-session-r2-source-after.json): unchanged across the profile.
- [Godot process inventory before](performance-active-session-r2-processes-before.json) and [after](performance-active-session-r2-processes-after.json)
