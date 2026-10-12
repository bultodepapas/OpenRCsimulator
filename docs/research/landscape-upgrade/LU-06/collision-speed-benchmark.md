# LU-06 — Representative scenery collision query cost

Date: **2026-10-11 (19:50 COT)** · Step: **LU-06** · **Status: measurement complete; no runtime code changed.**

I measured the production `Collision.first_hit` path against the normalized default world (3,867 immutable proxies in 950 bins) and the Ugly Stik's real `crash_hull`. Each case used 20 warmups and 200 timed calls. The native Windows run used Godot 4.7.2 (`ed1daf0bf`); a Linux full-suite process was the only known concurrent CPU workload, and no native render capture or benchmark was active. Treat these as host measurements with CPU contention, not isolated performance acceptance.

The project's default physics rate is **240 Hz** (`app/project.godot`, also reported by the runtime). At 80 m/s, a 120 Hz comparison sweep is 0.667 m and the actual 240 Hz session sweep is 0.333 m. Each near-obstacle path was centered on a located entering time of impact; the returned hit ID confirms that the timed queries hit the intended car or shade-tree crown. Empty-air queries used a distant path.

| Case | Step displacement | p50 | p95 | p99 | Maximum |
| --- | ---: | ---: | ---: | ---: | ---: |
| Empty air, 120 Hz comparison | 0.667 m | 15 μs | 31 μs | 42 μs | 65 μs |
| Near car, 120 Hz comparison | 0.667 m | 468 μs | 492 μs | 499 μs | 542 μs |
| Near shade-tree crown, 120 Hz comparison | 0.667 m | 263 μs | 380 μs | 465 μs | 497 μs |
| Empty air, actual 240 Hz | 0.333 m | 14 μs | 28 μs | 34 μs | 69 μs |
| Near car, actual 240 Hz | 0.333 m | 274 μs | 470 μs | 514 μs | 617 μs |
| Near shade-tree crown, actual 240 Hz | 0.333 m | 262 μs | 431 μs | 497 μs | 692 μs |

At the actual session rate, nearby car and tree queries still exceed the earlier 100 μs p95 target, while empty-air queries remain below it. These practical short-segment measurements are substantially below the earlier 16 m swept-segment stress results (1,054 μs near a car and 795 μs near a tree, [collision-report](../LU-05/collision-report.md)). That stress path travels 16 m at a pose speed of 1,920 m/s, a 1/120 s displacement; it is not a representative 240 Hz session tick. The measurements support retaining a nearby-object performance follow-up rather than claiming the query budget is met.

The raw command output, including all 200 sorted microsecond samples per case, is in [collision-speed-benchmark.log](collision-speed-benchmark.log). The exact scratch benchmark source is [collision-speed-benchmark.gd](collision-speed-benchmark.gd). It was run against a disposable copy of `app/`; no production scripts or tests were edited for this measurement.

Reproduction from the repository root:

```powershell
Copy-Item app .tools/landscape-upgrade/collision-speed-bench -Recurse
Copy-Item docs/research/landscape-upgrade/LU-06/collision-speed-benchmark.gd .tools/landscape-upgrade/collision-speed-bench/tests/benchmark_collision_speed.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path .tools/landscape-upgrade/collision-speed-bench --script res://tests/benchmark_collision_speed.gd
```

The benchmark builds the field/scenery/lights collision world from their production loaders, locates the first entering contact with a 16 m helper sweep, then measures the same short path at 120 and 240 Hz. Its per-case sample arrays and hit identities are preserved in the raw log.
