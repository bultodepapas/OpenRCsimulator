# DT-11a — bounded ground-patch buffer reuse

2026-10-19, Windows, Godot 4.7.2-stable, RTX 3090, Compatibility renderer.
Repeated complete default-field construction improved **8.5%**, from **583.190 to
533.547 ms**, with exact geometry in all 30 native comparisons. The production
change is in `app/scenery/ground_features.gd`; physics and generated data are unchanged.

## Attribution and implementation

The real Home/Fly baseline and disposable field-phase timers identified scenery
construction as the largest remaining repeated field phase. The default gravel
patch alone repeatedly cost about 43 ms. This applies Godot's
[measure-first approach](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html)
to an existing deterministic constructor.

`patch()` now caches serialized vertex, normal and color buffers keyed by the
complete polygon, surface, theme, seed and MeshKit transform. A miss invokes the
original algorithm unchanged. A hit decodes independent arrays and appends them
after any existing geometry. Transform identity matters: gravel masks use the
already transformed coordinates. No geometry operations or order were changed.

The main-thread cache holds at most eight FIFO entries and **4 MiB of serialized
keys plus payloads**. Oversized entries are generated but not retained. The default
patch retains **338,620 bytes (331 KiB)**. Containers and temporary allocations are
additional; this is not an RSS ceiling. Scene nodes, meshes and materials remain
fresh per build. Changed inputs miss; returned-buffer edits cannot alter the cache.

## Measurements

Five fresh native processes each built six alternating reference/candidate field
pairs. The initial variant was reversed in processes 2 and 4. Pair zero is retained
but excluded from warm medians because unrelated first-use caches are shared.
Hashes compare all node classes/names, transforms, mesh arrays/bounds/primitive
types and MultiMesh buffers/counts/bounds. Input field bytes also remain unchanged.
This geometry check does not compare every material uniform or rendered pixel.

| Process | Reference field, ms | Cached field, ms | Reduction |
| --- | ---: | ---: | ---: |
| 1 | 576.549 | 532.919 | 7.6% |
| 2 | 592.115 | 532.279 | 10.1% |
| 3 | 573.119 | 537.867 | 6.2% |
| 4 | 621.419 | 533.547 | 14.1% |
| 5 | 583.190 | 534.509 | 8.3% |

The headline uses the median of these process medians. Repeated patch construction
alone fell from **42.600 to 0.184 ms** by the same aggregation. See
[field summary](field-summary.json) and `field-run-1.json` through `field-run-5.json`.
Detached field construction excludes tree attachment, first draw and GPU frame cost.

A separate CPU-only miss probe clears the cache outside every timed invocation:
five processes, 12 alternating pairs each, all **60 byte-identical**. Excluding the
first pair, median-of-process-medians was **42.132 → 42.916 ms**, a **0.784 ms / 1.9%
miss penalty**. First-use field samples also had two candidate patch outliers near
58 ms versus reference samples near 43 ms; they remain in the raw field results.
The cache trades a small measured miss cost and bounded retention for repeat savings.
See [miss summary](miss-summary.json). This is not a cold-OS-cache benchmark.

## Real Home/Fly lifecycle

Three fresh process pairs used one disposable source copy, changing only the ground
script between runs; pair two reversed the variant order. Immutable assets/imports
were hard-linked as read-only inputs, other app files copied, and app source/data
hashes checked between runs. No import ran in the copy. Each process used isolated
preferences, the default Ugly Stik, native 1280×720, 4× MSAA, VSync, 60 fps cap and
Dummy audio, with three real Fly/End-flight cycles.

| First-post-draw measurement | Reference, ms | Candidate, ms |
| --- | ---: | ---: |
| Initial Home from app-resource loading | 3799.837 | 3791.220 |
| First Fly | 2728.783 | 2627.985 |
| Repeated Fly | 1469.960 | 1432.094 |
| Return Home | 965.797 | 900.824 |

Values are medians of process medians; repeated Fly uses cycles 2–3, returns use all
three cycles. Repeated Fly improved **2.6%**, and returns **6.7%**. Initial Home was
effectively unchanged within the observed process spread. First Fly still exceeds
two seconds. OS/import/shader cache state and background desktop activity were
uncontrolled. These six short runs do not establish tail latency or platform acceptance.

All **18 cycles** reached their first flight draw unpaused at tick 11, with 1,098
flight nodes, 622 Home nodes and zero orphan nodes. Every process released audio
playbacks and removed its settings sidecar. The known maple material/wind warning
reproduced in both variants; accepted runs have no engine errors or ObjectDB leaks.
[Loading summary](loading-summary.json) and the six `loading-N-variant.json` files
retain the individual timings and shutdown evidence.

## Verification and provenance

- New permanent cache regression: **94 checks**, including exact cold/warm output,
  preserved prefixes, mutation isolation, all key dimensions, mirrored/nonuniform
  transforms, count eviction, byte-budget eviction and oversized-entry refusal.
  Budget mutations run only on disposable source copies.
- Six existing suites pass: scenery ground LU08, landscape gravel, scenery build,
  field integration, field surfaces and world flow. Changed scripts parse. The test
  is discovered automatically by `app/test.sh`; full app CI/exports were not run.
- Existing maple wind warnings and the world-flow test's deliberate invalid-time
  warning are retained. No accepted check contains an engine error.
- Two harness failures are retained and excluded: an initial probe type-inference
  parse error, and a snapshot missing `assets/aircraft/model-bindings.json`. The
  repaired snapshot completed all six loading runs; production never lacked that file.

[Checked runs and commands](checks.json) include successful and failed attempts,
with compressed raw logs. [Manifest](evidence-manifest.json) pins hashes and
[runtime patch](runtime.patch) includes production and regression changes. The
executed candidate differs from production only by two explanatory comments.
`source-before.json` records the starting commit and working tree; compressed app
source/data hash maps pin both campaigns. The original ground source agrees with
commit `bd6596aecce3b4e32c75d674fd628ef517fcda3d` after newline normalization.

## Reproduce

Decompress `ground_reference.gd.gz` outside `app/`, then from the repository root:

```powershell
python research/performance/ground_patch_cache/prepare.py --work tmp/patch-pair-new --reference tmp/ground_reference.gd
$probe = (Resolve-Path tmp/patch-pair-new/field_compare.gd).Path
python tools/godot/run_checked.py --timeout 120 --require-text 'field comparison pairs=6 failures=[]' -- .tools/Godot_v4.7.2-stable_win64_console.exe --path app --audio-driver Dummy --script $probe -- --output="$PWD/tmp/patch-pair-1.json"
python tools/godot/run_checked.py --timeout 60 --require-text '94 checks, 0 failures' -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_ground_patch_cache.gd
```

Repeat in fresh processes with new output files and alternating `--reverse`. The
preparer uses current field/scenery dependencies; reproducing dated timings also
requires the pinned dependency snapshot and host. To inspect miss cost, decompress
`patch_miss_probe.gd.gz` beside the prepared reference/candidate scripts and run it
headless with a new `--output`. The exact campaign drivers and loading probe are
retained compressed; their original absolute paths appear in the checked commands.

This closes the measured construction slice. FPS/GPU improvements, exported builds,
pilot input/readability, long soak and Linux/macOS qualification remain unmeasured.
