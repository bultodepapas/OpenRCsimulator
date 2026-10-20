# LU-32 — Per-frame lighting and storm update cost

2026-10-20. This round reduces repeated presentation CPU work while retaining
the scenery, light sources, meshes, shaders and simulation behavior.

- Airfield lighting compares the current sky material, solar direction and
  exposure before recalculating unchanged light output. Explicit snapshots,
  binding and profile/activation changes invalidate the poll cache. Regional
  and field lighting reuse one calculated night factor.
- Storm materials upload cloud color, haze color and fog only when those
  values change. Bank height bounds initialize when materials are created.
  Clock, visibility, advection and camera-copy selection still update on every
  call.
- Lightning uploads skip identical source/radiance values while still
  refreshing event metadata. Reconfiguration invalidates both material
  caches. All caches are bounded and owned by the scene node.

## Measurements

Godot 4.7.2, Windows. The accepted CPU benchmark runs headless, with the real
fixture/regional-light and storm material setup. Eleven alternating
before/after pairs each contain 20,000 calls, following warmup. Values are
median microseconds per call; changing-input cases include input writes.

| Update | Before µs | After µs | Change |
| --- | ---: | ---: | ---: |
| Fixed sky lighting | 4.494 | 1.340 | −70.2% |
| Solar direction changing every call | 4.297 | 4.661 | +8.5% |
| Fixed storm colors/fog, advancing clock | 7.892 | 5.807 | −26.4% |
| Cloud color changing every call | 8.127 | 7.565 | −6.9% |
| No active flash | 2.833 | 2.106 | −25.7% |
| Flash level changing every call | 3.183 | 3.256 | +2.3% |

The stable-input paths benefit most. The continuously changing lighting and
flash cases show small measured regressions (0.364 and 0.074 µs/call); the
cache is not a universal speedup. Shared desktop load produces substantial
sample variation. These measurements do not establish an FPS improvement,
GPU saving or lower-end hardware acceptance. The complete flight loop was
not benchmarked in this round.

Two earlier native microbenchmark attempts are rejected and retained in
`checks/`: the first incorrectly rewrote a shader path in the comparison
harness; both emitted texture cleanup diagnostics when exiting the isolated
fixture harness. The corrected headless CPU benchmark passes. The four
separate native production-world capture runs also pass without those errors.

## Verification

The final six focused suites pass **407 checks**: storm bank (55), field
lighting (68), marker optics (34), regional lighting (201), electrical bank
(32), and world presentation context (17).

Added regression cases exercise explicit snapshot overrides, exposure-only
changes, sky material replacement, rebinding, fog-only changes, clock updates
with unchanged materials, flash source/exposure changes, equal-radiance event
metadata, repeated flash clears and material reconstruction. Existing tests
cover camera attachment/detachment, advection, scene isolation and switches.

Nine paired native captures use the RTX 3090, Compatibility/OpenGL, 1280×720
and 4× MSAA:

- Six storm views: day, dusk and full moon, at 25° and 50° FOV.
- Three night views: runway fixtures, field/transmission-line overview and
  wind turbines.
- Eight pairs have identical RGB pixels. The field overview differs at only
  two sky pixels, with a maximum channel difference of 1/255. No scenery or
  fixture pixel differs in that pair. This is not claimed as exact image
  equality for all nine views.

Native frame intervals are retained in the night capture reports but are not
used as a performance acceptance claim. The existing unsupported maple
wind-material warning remains. This focused pass does not rerun or resolve
the pre-existing grass-mask integration failures recorded in LU-31.

## Evidence and reproduction

[CPU samples](performance.json), [RGB comparison](image-parity.json),
[source hashes](source-identity.json), [checked runs](checks/),
[storm before](storm-before/), [storm after](storm-after/),
[night before](night-before/), [night after](night-after/).

The `*.before.gd` files retain the actual pre-change implementations.
Copy those files, `prepare_probe.py` and `bench_updates.gd` to
`tmp/landscape-perf-r2/`, then run from the repository root:

```powershell
python tmp/landscape-perf-r2/prepare_probe.py
python tools/godot/run_checked.py --out-dir tmp/landscape-perf-r2/checks --label cpu-benchmark --timeout 60 -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script C:/DEVELOPMENT/OpenRCsimulator/tmp/landscape-perf-r2/bench_updates.gd
```

The preparation script rewrites only quoted script paths, including the
lighting builder's self-load; it preserves shader paths. It also prepares
baseline variants of the existing production capture tools. Their full
commands are recorded in the checked reports. Adjust absolute scratch paths
when reproducing on another workspace. `retain.py` copies reports, hashes
sources and compares RGB images using Pillow/NumPy.
