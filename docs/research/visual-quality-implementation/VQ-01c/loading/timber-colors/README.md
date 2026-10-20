# DT-11a — sample shared plank vertex colors once

2026-10-19. **Adopted:** placed-object construction improves **27.1%**, from
**97.358 to 70.927 ms**, across five fresh native processes. A separate 13-prefab
workload improves **30.2%**, from **40.914 to 28.572 ms**, in five headless processes.

## Mechanism and attribution

`ClubFurniture._plank()` previously sampled the filtered Wood049 image separately
for all six triangle corners of every side quad. Adjacent triangles share ring
vertices. Compute each vertex color once while building its ring, then copy the
same colors into the existing triangle slots. Preserve local sampling coordinates,
arithmetic order, negative-seed remainder behavior, forced side alpha, cap colors,
transforms and damage ranges. The existing image cache is unchanged.

A 16-segment plank now samples **152 instead of 864** points; a 4-segment shed board
samples **56 instead of 288**. The temporary colors last for one plank invocation:
2,432 bytes of packed color payload for 16 segments, plus container overhead.
This is not a resident-memory measurement. No persistent geometry cache is added.

Disposable attribution copies identified picnic tables and the shed as expensive
placed objects: one warm default build spent 30.576 ms on four picnic tables and
17.915 ms on the shed. Checked attribution logs and source snapshots are retained.

Earlier generic MeshKit trials were rejected: transforming box corners once saved
only about 3.7% in a seven-prefab exploratory workload; transforming quad corners
once was about 2% slower, and batching quad arrays was about 11.5% slower in a
13-prefab workload. All preserved output. Their raw results remain in
`box-explore.json`, `quad-explore.json` and `quad-batch-explore.json`.

## Measurement and limits

Windows, Godot 4.7.2-stable, RTX 3090, Compatibility renderer. Native runs build six
alternating reference/candidate default-field pairs per process; processes 2 and 4
reverse the initial order. Pair zero includes shared first-use asset caches and
is retained but excluded from warm medians. Headless runs build twelve alternating
13-prefab pairs per process, also excluding pair zero from warm medians.
All runs are serial. Script/data hashes remain unchanged through the native campaign.

| Process | Objects reference / candidate, ms | Scenery reference / candidate, ms | Field reference / candidate, ms |
| --- | ---: | ---: | ---: |
| 1 | 101.559 / 73.551 | 204.255 / 178.317 | 585.311 / 567.956 |
| 2 | 97.358 / 69.606 | 202.903 / 162.131 | 588.398 / 529.906 |
| 3 | 125.476 / 113.835 | 225.096 / 268.257 | 638.780 / 847.185 |
| 4 | 94.951 / 69.125 | 186.317 / 162.334 | 539.438 / 519.490 |
| 5 | 96.751 / 70.927 | 199.929 / 169.270 | 572.004 / 542.515 |

Headline values are medians of process medians from [summary.json](summary.json).
Objects improve in all five processes. Overall scenery and field timings regress
in process 3, so these runs do **not** establish a reliable whole-field or Home/Fly
loading gain. Background activity and OS caches were uncontrolled. Detached CPU
construction does not measure GPU rendering or FPS; cold-load gains are unqualified.

All **30 native whole-field pairs** match stable node names/classes, transforms,
mesh arrays/bounds/primitive types, MultiMesh buffers/counts/bounds and botanical
layout metadata. Field inputs remain unchanged. All **60 headless prefab pairs**
match complete vertex, normal and color arrays, transforms and damage ranges.
The comparison does not cover every material property or rendered pixel.

## Regression and lifecycle checks

- New permanent color test: **84 checks** pass against both original and candidate
  scripts, and integrated production. An independent scalar sampler checks colors
  at emitted local vertices and cap colors across six seed/dimension/segment cases.
  Rotation, translation, reflection, nonuniform scale, segment clamping, nonopaque
  tones, existing geometry/damage prefixes and transform restoration are covered.
- A disposable wrong-color-slot mutation fails **30 assertions**. Its failed log
  is intentional and retained separately; no mutation enters `app/`.
- Scenery build and architecture suites pass their geometry, winding, determinism
  and budget checks. Scenery destruction passes **78 checks**; field integration
  passes **39 checks**, including independent Home/flight resources.
- The native [Home/Fly smoke](production-loading.json) completes three cycles,
  unpaused at tick 11 at each first draw, with zero orphan nodes on every return.
  Audio releases and isolated settings are removed. This is not a paired benchmark.

Accepted checked runs contain no engine errors or ObjectDB leak warnings. The
existing unsupported maple wind-material warning remains recorded. Full CI,
exports, long-duration soak and other-platform verification were not run.

## Evidence and reproduction

Baseline: `82885c68ca72af6b68d47ea549ff18710a5ae8e8`. The integrated runtime matches
`timber_candidate.gd.gz` except for one explanatory comment. [Runtime/test diff](runtime.patch),
[manifest](evidence-manifest.json), source hash map, checked logs and raw measurements
pin the experiment. Unrelated `.agents/` and `skills-lock.json` files were preserved.

Current production regression, from the repository root:

```powershell
python tools/godot/run_checked.py --timeout 60 --require-text 'club furniture colors: 84 checks, 0 failures' -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_club_furniture_colors.gd
```

For historical comparison, restore the baseline and imported assets in a separate
checkout. Decompress the `timber_*`, `shed_*`, `prefabs_*`, `scenery_*`, `field_*`
GDScript snapshots and `field_compare.gd.gz` together outside `app/`. Replace their
`C:/DEVELOPMENT/OpenRCsimulator/tmp/scenery-construction-20261019` preload prefix
with that directory's absolute forward-slash path. Then run:

```powershell
$probe = (Resolve-Path tmp/timber-repro/field_compare.gd).Path
python tools/godot/run_checked.py --timeout 120 --require-text 'field comparison pairs=6 failures=[]' -- .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script $probe -- --output="$PWD/tmp/timber-field-new.json"
```

Repeat with new outputs and fresh processes, alternating `--reverse`. Use
`timber_probe.gd` with `--headless` and completion marker `prefab pairs=12 failures=[]`
for the prefab comparison. The retained test accepts `--builder=<absolute-script>`
for original/candidate controls. `prepare_timber.py.gz` records how dependency
copies were produced; it requires original runtime source, not the optimized file.
