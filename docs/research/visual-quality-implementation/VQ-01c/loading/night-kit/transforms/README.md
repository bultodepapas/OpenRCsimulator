# DT-11a — native transforms for aircraft light geometry

2026-10-15. `aircraft_lights.gd::vertices` and `triangles` now transform each
surface's packed vertex array in native code. Indexed triangles still expand
indices in authored order, including repeated indices; unindexed surfaces append
their transformed array directly. Triangle primitive filtering and parent-to-root
transform composition remain unchanged.

This removes per-vertex GDScript multiplication from fixed-wing night-kit
preparation. Each selected surface needs a temporary transformed array; there is
no retained cache or change to source meshes. Unused indexed vertices may also
be transformed, but are not emitted into triangle output. Geometry, lighting,
aircraft contracts and simulation behavior remain unchanged.

## Measurement

Five fresh native processes, six alternating pairs per workload and visual family;
starting order reverses on even processes. Godot 4.7.2 `ed1daf0bf`, Windows,
Compatibility/OpenGL, RTX 3090 / NVIDIA 610.88, Dummy audio. Each process builds
one validated model per family and shares it between reference and candidate.
Model creation, byte comparison and resource teardown are outside the timers.

Warm medians use pairs 1–5, **25 samples per variant per family**. Geometry means
both vertex collection and triangle collection. Complete kit timing calls
`attach`, including surface tracing, materials, lights and crash-host metadata.

| Family | Geometry reference → candidate | Kit reference → candidate |
| --- | ---: | ---: |
| Stik | 30.850 → 17.997 ms | 272.770 → 254.493 ms |
| Extra | 9.225 → 4.688 ms | 132.558 → 122.900 ms |
| P-51 | 26.833 → 14.539 ms | 295.626 → 283.587 ms |
| Avanti | 47.240 → 40.154 ms | 644.411 → 631.339 ms |
| Timber | 14.368 → 12.032 ms | 183.801 → 182.046 ms |

Geometry extraction improves by **15.0–49.2%** in these observations. Full-kit
median reductions are much smaller, **1.755–18.277 ms**. Individual process/family
kit medians can regress; the larger extraction improvement must not be presented
as a whole-constructor or full-loading percentage. Pair-0 results are retained in
the raw JSON and summary; they follow model loading and do not measure cold startup.

This was not an isolated host: another track ran a headless P-51 envelope probe
during the campaign. Physics/data files also had concurrent edits, preserved by
this change. Both variants use the same model instance within each process, and
output counts agree across the five processes. These are phase observations, not
the isolated DT loading gate, FPS, input latency or exported-package acceptance.

## Verification

- **300 native fleet pairs**: 150 exact vertex/triangle array comparisons and 150
  full-kit comparisons. Kit checks include mesh arrays, transforms, visibility,
  shader source/uniforms, light properties and crash attachment metadata.
- **256 synthetic cases per process**, 1,280 cases total, compare both collectors:
  nested transforms, negative/nonuniform scale, indexed/repeated/unused vertices,
  unindexed geometry, multiple triangle/line surfaces, primitive meshes, missing
  meshes, hidden meshes and nonidentity root transforms. Source arrays stay intact.
- Existing world/field-light regression: **72/72 headless**. Home preview cache:
  **18/18 headless**. Night kit, including all catalog entries, modes, placement
  and wreck attachment: **30/30 headless and 30/30 native**, clean logs after the
  test initialization repair below.

The initial native night-kit test produced `sim_clock` shader warnings. Its
standalone setup did not register shader globals before building models. The
test now calls `ShaderClock.register()` before material compilation, as the
application and comparison harness already do. Assertions are unchanged. The
original warning log and test source are retained; corrected native/headless
runs have no engine errors/warnings. This repair does not resolve or reclassify
the separate [helicopter texture shutdown diagnostic](../../heli-canopy/README.md).

No full CI, exports, native flight soak or visual pilot acceptance was run.

## Reproduction and evidence

`source-before.json` and `source-after.json` monitor four runtime dependencies;
they establish only that the light collector changed among those paths, not
that the shared working tree was frozen. Compressed runtime/test sources, raw
timings, check logs and hashes are retained. A separate runner verification lives
in `runner-check/` and is excluded from the five-process table.

```text
python research/visual-quality/aircraft-light-transforms/run.py --godot PATH_TO_GODOT --app app --out tmp/aircraft-light-transforms-repro
godot --headless --audio-driver Dummy --path app --script res://tests/test_world_field_lights.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_night_kit.gd
godot --audio-driver Dummy --path app --script res://tests/test_night_kit.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_ui_home_preview_cache.gd
```

Use an imported project and a new output directory. The comparison uses a native
renderer; `--runs 1` checks the runner and exact-output contract.
