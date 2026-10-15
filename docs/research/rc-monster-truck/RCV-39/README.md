# RCV-39 — Grime material CPU and resource optimization

2026-10-15. MONSTER CAR 2 now uses five vehicle-owned grime materials instead of 70: one for its 66 shell meshes and four for the tires' separate height bands. All 70 overlays remain attached. Exact comparisons skip unchanged dirt, wetness and world-to-vehicle uniform uploads. Moving an ancestor, pausing, cleaning and resetting still update the required values. Source geometry, shaders, lights, particle budgets, sound, fuel and physics are unchanged.

## Measurement

Godot 4.7.2 official Windows runtime, Ryzen 9 5900X, RTX 3090, Compatibility/OpenGL 3.3. The [paired component receipt](effects/receipt.json) records five alternating baseline/candidate rounds per case, each with 100 warmup and 2,000 measured updates. Values below are medians of the five round means. Moving measurements include the same parent-transform assignment in both implementations.

| Effects CPU case | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Moving on loose ground | 99.529 µs/update | 69.946 µs/update | 29.7% |
| Stable paused vehicle | 17.437 µs/update | 4.628 µs/update | 73.5% |
| Distinct grime materials per truck | 70 | 5 | 92.9% |

These are component CPU measurements, not an FPS improvement or total-memory measurement. Native activity runs also record the full presentation callback, but process-to-process variation affects even the unchanged physics timing. No whole-frame speedup is attributed to this optimization.

| Native fixed-tape run | Presentation mean before → after | Four physics ticks mean before → after | Draw calls / primitives, both versions |
| --- | ---: | ---: | ---: |
| Day, vehicle lights off | 3.875 → 3.054 ms | 29.276 → 24.287 ms | 1,082 / 940,813 |
| Night, all vehicle switches on | 3.209 → 3.106 ms | 25.042 → 25.003 ms | 618 / 617,614 |

Each native process renders 30 warmup and 240 measured frames at 1280×720, advancing four accepted ticks per frame with audio disabled. These synchronous callback measurements exclude GPU completion and frame scheduling. The solver remains the larger CPU cost: the candidate's four-tick batch averages approximately 6.1–6.3 ms per tick, above the 4.167 ms interval at 240 Hz. This phase does not close that performance gate.

## Preserved behavior

The [summary and evidence hashes](summary.json) validate all retained receipts. The paired observer tape covers gravel, dirt, mud, water, drying, pause, moving/scaled parents, cleaning and reset: **97 snapshots and 47,530 exact uniform comparisons**, with matching diagnostics and particle configuration. Prepared materials remain isolated between trucks; source mesh/material resources are unchanged. All seven shader uniforms are checked explicitly, including non-null values.

The [focused regressions](checks/verification.json) pass **910 checks with zero failures** across lighting, Bisonte effects, Nitro effects, Nitro activity and Bisonte activity. Added permanent checks cover independent trucks, subpixel movement during pause and cleaning after an ancestor moves. All engine logs are free of script/shader errors. The full repository suite and release export were not run.

All four native runs accept 1,080 ticks, preserve the solver identity (`solver_changed=false`) and produce the same digest of the 270 states sampled after each four-tick batch. This is a same-tape presentation check, not a new exact-replay or physical-calibration claim. The 96 dust particles, 32 exhaust particles, all four dust contacts and five-light budget remain unchanged.

The [baseline day](baseline-day/activity.png), [candidate day](candidate-day/activity.png), [baseline night](baseline-night/activity.png) and [candidate night](candidate-night/activity.png) captures were visually inspected. Geometry, dirt coverage and lighting remain consistent. Particle placement varies with rendering time; images are not pixel-equivalence proofs. The baseline night capture omits HUD/track text, as previously observed in RCV-37/38. This pass qualifies the 3D effects, not that intermittent font-rendering issue.

## Reproduction and references

The [vehicle guide](../../../../research/rc-monster-truck/monster-car-2/README.md) owns operation. [`rcv39/`](../../../../research/rc-monster-truck/monster-car-2/rcv39/) retains the original post-RCV-38 effects source, paired comparison, native harness and summary validator. Run measurements sequentially with fresh output directories:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script ../research/rc-monster-truck/monster-car-2/rcv39/bench_effects.gd -- --output=C:/path/to/effects
& .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script ../research/rc-monster-truck/monster-car-2/rcv39/bench_activity.gd -- --label=candidate --period=day --output=C:/path/to/day
python research/rc-monster-truck/monster-car-2/rcv38/verify.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out C:/path/to/checks
python research/rc-monster-truck/monster-car-2/rcv39/summarize.py
```

Repeat the native capture with `--period=night`. Native labels are metadata: retained baseline runs were taken before integrating the candidate. To reproduce a baseline, use an isolated checkout with `ground_effects.gd` replaced by the retained `baseline_effects.gd`; do not replace production files in an active shared tree. The regression runner is the unchanged RCV-38 suite and retains that suite ID in its receipt. The summary validator reads the canonical evidence directory and checks source/log hashes.

Godot's [CPU optimization guidance](https://docs.godotengine.org/en/4.7/tutorials/performance/cpu_optimization.html) supports warmed repeated measurements and separating driver-call overhead. [ShaderMaterial](https://docs.godotengine.org/en/4.7/classes/class_shadermaterial.html) documents that uniform updates affect every instance using the material. Here only equivalent shell uniforms share a resource within one vehicle; wheel-specific bands and other vehicles remain separate. Sources consulted 2026-10-15 against Godot 4.7.2.
