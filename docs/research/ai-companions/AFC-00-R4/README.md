# AFC-00 R4 — Promoted-pilot Windows rendered baseline

Measured 2026-10-20 local time (2026-10-21 UTC) using the promoted companion pilot `3842cbdba80c7bef5041844132a811bfd27c1cb68de759ce06f39bb97ca1f024` and solver qualification `2f4f35c04c837e89c5317412991046cd097dd3c9f501e9697702e94a6cff4bfa`. This is a fresh per-count native baseline for one neutral-trim rendered workload.

| Companion count | Frames | p50 ms | p95 ms | p99 ms | Sim/wall | Render gates |
| ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 0 | 14,599 | 3.940 | 5.686 | 8.152 | 1.00003 | pass |
| 1 | 10,267 | 5.249 | 8.186 | 10.652 | 1.00000 | pass |
| 2 | 4,856 | 12.032 | 17.175 | 21.806 | 0.99993 | p95 miss; p99 pass |
| 3 | 1,390 | 42.065 | 52.017 | 58.687 | 0.99302 | p95 and p99 miss |

The proposed render limits are p95 ≤16.67 ms and p99 ≤25 ms; the pacing gate is simulation/wall in `[0.98, 1.02]`. All four captures had active player endpoints, no crash/fault/pause, focus retained, and active companions where requested. Counts 2 and 3 remained paced, but their render percentiles miss the targets. Passing counts 0 and 1 in this one scenario does not establish a broad population ceiling or release support.

Each measured case used 10 s warmup plus 60 s sample on Windows 11 Pro build 26100, Ryzen 9 5900X, 64 GiB RAM, RTX 3090 / driver 617.42, Godot 4.7.2, Compatibility/OpenGL 3.3, 1280×720, vsync off, max-fps 0. The player input adapter held neutral targets at the accepted initial trim throttle. Companions used their normal seeded circuit pilots. Production focus-pause behavior and simulation frequency were unchanged. The smoke was only a 1 s / 4 s fixture check.

There was no unrelated Godot overlap during the accepted count 0–3 captures. One count-1 preflight was deferred while an unrelated presentation test ran; the valid count-1 capture started after it exited. Three known scenery tree-wind warnings and the existing Stik inertia advisory remain in logs; runner error count was zero.

This does not support a causal speedup claim against [AFC-00-R2](../AFC-00-R2/README.md): R2 measured the original circuit pilot on a different frozen source/world snapshot. This also measures rendered frame pacing, not callback CPU cost or the 2 ms callback budget.

[verification.json](verification.json) binds source, hardware, fixture, count gates and every raw artifact hash. [frozen-source-manifest.json](frozen-source-manifest.json) and [source-manifest-pre.json](source-manifest-pre.json) enumerate the private clone's 4,338 application files before and after the matrix; no app file changed and all pinned tools/key inputs match. Small runner reports/logs and exact probe/reducer/runner source are retained in [checks](checks/) and [sources](sources/). Large raw frame/fixture/assessment JSON remains at `D:/OpenRCsimulator-AFC-work/evidence/performance/windows-promoted3842-2f4-20261021/`; the receipt lists every path, size and SHA-256.

## Reproduce

Run each count through the pinned checked runner with a fresh output directory, requiring `AFC native fixture complete; active endpoint=true` and `frame times:`. The runner and reducer commands, source hashes and exact run commands are in [verification.json](verification.json). The exact probe and reducer sources are retained under [sources](sources/).

Keep this result separate from broad aircraft, device, all-visible, mixed-regime, endurance, cross-platform and callback-cost qualification.
