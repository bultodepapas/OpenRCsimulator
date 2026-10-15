# DT-11a — reject nonintersecting helicopter canopy triangles

Current follow-up: [reuse each cut for four profiles](#follow-up-reuse-cuts-for-four-profiles).
The initial campaign below remains the evidence for triangle rejection alone.

2026-10-15. `heli_night_lights.gd::canopy_line` scans the HX-700 canopy to fit
four light strips to its actual surface. It previously allocated an intersection
array and tested three edges for every triangle at each of 17 stations. The
canopy contains **38,240 triangles**.

The collector now skips triangles whose three Z coordinates are strictly on the
same side of the station plane. Equality stays on the original path. Intersecting
triangles retain the same edge arithmetic, order, height extrema and contour
selection. This adds five lines, with no retained cache, geometry simplification,
asset edit or simulation change. It benefits new helicopter night-kit construction
in Home and flight; selecting an already cached Home model already reuses its kit.

## Measurement

Five fresh native Godot 4.7.2 `ed1daf0bf` processes, Windows, Compatibility/OpenGL,
RTX 3090 / NVIDIA 610.88, Dummy audio. Each process performs six alternating
reference/candidate pairs per workload, reversing the starting order on even
processes. Model creation and output comparison are outside the timers. Kit
construction includes its contour extraction, meshes, materials, lights and rotor
LED nodes, but excludes attachment to a rendered world and the first visual update.

| Workload | Reference warm median | Candidate warm median | Reduction |
| --- | ---: | ---: | ---: |
| Four canopy lines | 1,764.332 ms | 487.226 ms | 72.4% |
| Complete kit construction | **1,752.928 ms** | **494.424 ms** | **71.8%** |

Warm statistics pool pairs 1–5: 25 samples per variant per workload. The five
pair-0 medians are 1,565.748→473.123 ms for lines and 1,842.108→522.721 ms for the
kit. The kit workload follows the line workload in each process, so these are
first calls to those workloads, not import-cold or complete application startup.
Raw samples and summaries remain in `native-1..5.json` and `summary.json`.

This was a shared workstation: four unrelated headless Godot processes remained
present and were not stopped; their sampled cumulative CPU times barely changed.
Other background work and clock variation were uncontrolled. This deviates from
the isolated measurement gate and supports phase attribution only. Reference
warm kit medians vary substantially between processes. The paired reduction is
large, but **full Home/Fly latency, FPS and platform acceptance are not established**.

## Verification

- **60 real-model comparison pairs**: 30 four-line outputs are byte-identical;
  30 complete kits preserve node names, transforms and every mesh surface array.
- **256 seeded synthetic cases per process**, 1,280 pairs total: random triangles,
  station boundaries, coplanar/degenerate and nearly parallel edges, both sides
  and both strip heights. Empty input and incomplete trailing triangles also
  preserve the reference result. Source triangle bytes remain unchanged.
- Existing headless regressions pass without engine warnings/errors: helicopter
  night lights **27/27**, night rotor **18/18**, crash presentation **44/44**, and
  Home preview cache **18/18**. These cover modes, daylight isolation, exposure,
  phase, Home switch/reuse, material ownership and repeated impacts/reset.
- The native night-light test passes its 27 assertions but reports **two texture
  shutdown errors, 349,524 bytes each**. A rerun with the original collector
  reproduces both errors. This native lifecycle check is **not a clean pass**.
  The five native geometry comparisons themselves exit without errors/warnings.

The baseline diagnostic uses disposable copies of the original night-light
script, Home scene and night-light test. Only preload/self-load paths are
redirected so both direct kit construction and Home use the reference. Production
files were not reverted. `baseline-*.gd.gz`, `baseline-native.log` and the original
candidate native log retain the evidence. The shutdown issue remains open and
has not been attributed to a production resource owner by this campaign.

No full CI, export, visual flight soak or pilot readability acceptance is claimed.

## Reproduce

`source-before.json`, `source-after.json` and `check-sources.json` pin monitored
sources; `source-after.json` also retains the engine/model hashes. Unrelated
working-tree edits are preserved. Reference/candidate scripts are compressed
alongside the raw evidence. On an imported project:

```text
python research/visual-quality/heli-canopy/run.py --godot PATH_TO_GODOT --app app --out tmp/heli-canopy-repro
godot --headless --audio-driver Dummy --path app --script res://tests/test_heli_night_lights.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_heli_night_rotor.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_heli_crash_presentation.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_ui_home_preview_cache.gd
```

The comparison requires a native renderer and a new output directory. `--runs 1`
checks the runner; a separate successful run is retained in `runner-check/` and
excluded from the table. To replay the baseline diagnostic elsewhere, decompress
its three script copies together outside `app/` and replace their recorded
`C:/DEVELOPMENT/OpenRCsimulator/tmp/heli-canopy/` prefix with that directory before
running `baseline-test.gd` natively against the imported project.

## Follow-up: reuse cuts for four profiles

2026-10-15. The constructor now computes each station's intersections and height
extrema once, then extracts all four contours from those segments. Previously it
repeated that work for each side/height pair. `_canopy_lines` returns independent
packed lines in request order; `canopy_line` retains the single-profile API.
Profile scalars remain GDScript float64, avoiding a Vector2 conversion that would
round the requested heights. Segments remain local to one station; no mesh/node
cache, persistent state or invalidation policy is added.

Five fresh native processes use the same protocol and hardware as above, with
six alternating pairs per workload and reversed initial order on even processes.
The baseline **already includes the preceding triangle rejection**, so these
are separate measurements and their percentages must not be added together.
Model construction and exact-output checks are excluded. The workstation remains
shared with unrelated headless processes; this is phase attribution, not the
isolated full-loading acceptance gate.

| Workload, 25 warm samples per variant | Previous collector | Batched collector |
| --- | ---: | ---: |
| Four canopy contours | 468.997 ms | 118.124 ms |
| Complete kit construction | **465.734 ms** | **127.429 ms** |

Kit construction saves **338.305 ms / 72.6%** in this campaign. Pair-0 medians are
462.958→115.160 ms for contours and 452.936→137.198 ms for the kit; kit timing
still follows contour timing and does not measure full cold Home/Fly loading.
See [summary](batch/summary.json) and the five raw native JSON/log pairs in `batch/`.

All **60 real line/kit pairs** and **1,280 synthetic pairs** retain exact output.
Additional profile checks cover reordered/duplicate requests, sub-float32 height
differences, outside-range heights, a zero side, single-profile compatibility,
empty requests and mutation independence. Returned meshes, transforms and names
are unchanged; no visual or physics tuning is involved.

Six permanent checks in `test_heli_night_lights.gd` use independently specified
rectangular skins to validate contour positions, surface limits, request order,
duplicates, input immutability and output independence. Headless results are
**33/33 night lights, 18/18 night rotor, 44/44 crash presentation and 18/18 Home
cache**, all without engine errors/warnings. Native night lights pass the 33
assertions but still report the same two 349,524-byte texture shutdown errors;
the reference reproduction above remains relevant, and native lifecycle is not
counted as clean. Native comparison processes themselves close cleanly.

Frozen sources, test before/after, monitored hashes and logs are under `batch/`.
Reproduce the batch comparison with:

```text
python research/visual-quality/heli-canopy-batch/run.py --godot PATH_TO_GODOT --app app --out tmp/heli-canopy-batch-repro
```

The regression commands above remain current. A separate `--runs 1` runner check
is retained in `batch/runner-check/` and excluded from the measurement table.
Whole-application loading, steady FPS, exported packages and shutdown ownership
remain outside this repair's acceptance claims.
