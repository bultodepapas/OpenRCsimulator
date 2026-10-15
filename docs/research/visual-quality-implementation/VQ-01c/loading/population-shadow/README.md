# DT-11a — batch population shadow transforms

2026-10-15. `app/render/field_projected_shadows.gd` now transforms each selected
population instance's packed faces in native code before the existing triangle
height filter. This extends the [mesh shadow optimization](../shadow-geometry/README.md)
to the standing, seated and pilot population path. Selection, triangle order,
bounds expansion, mesh creation and placement metadata remain unchanged.

Godot documents the bulk
[Transform3D × PackedVector3Array operation](https://docs.godotengine.org/en/stable/classes/class_transform3d.html#class-transform3d-operator-mul-packedvector3array)
as faster than individual transforms on larger arrays (consulted 2026-10-15).
The change uses one temporary packed array per selected instance, with no retained
cache. Source mesh arrays are read-only. Reducing people, simplifying geometry or
retaining transformed instance buffers was unnecessary for this improvement.

## Measurement

Three fresh native processes, eight alternating reference/candidate pairs per
cell, Godot 4.7.2 `ed1daf0bf`, Windows, Compatibility/OpenGL, RTX 3090 / NVIDIA
610.88, Dummy audio. The real default field selects three shadow cells, containing
**94,765 population triangles** in total. Scenery construction and exact-output
comparison are outside the timed collector calls.

Each batch below sums the three cell timings for the same pair. Pair 0 is excluded
from both variants' warm statistics: the reference runs first in every process
and pays a large initial collection cost even in the population-free cell. Raw
pair-0 results remain in the JSON; they do not establish a cold-start benefit.
Order alternates within each process, not between process starts.

| Warm batch median | Reference | Candidate |
| --- | ---: | ---: |
| Process 1, seven batches | 28.399 ms | 26.963 ms |
| Process 2, seven batches | 29.658 ms | 27.206 ms |
| Process 3, seven batches | 30.946 ms | 29.086 ms |
| Pooled, 21 batches per variant | **29.990 ms** | **27.708 ms** |

The measured reduction is **2.282 ms / 7.6%** for this repeated construction work.
See `summary.json` and `native-1..3.json`/logs. This shared workstation was not
isolated from background work; one individual cell's process median is slightly
slower in process 3. These measurements do not establish full Home/Fly latency,
frame pacing, FPS, cold loading or exported-package acceptance.

## Verification and limitations

- **72 real-cell pairs** preserve complete mesh array bytes, exact bounds, triangle
  counts and population/elevated-placement counts.
- **256 deterministic synthetic cases per process**, 768 pairs total, preserve
  those outputs under parent/instance transforms, negative nonuniform scale,
  visibility changes and height filtering. The identity fixture checks one
  triangle at the 0.04 m cutoff and one at 0.041 m; source arrays remain unchanged.
- Existing field projected-shadow regression: **57/57 headless and 57/57 native**,
  including population ownership, budgets, fallback and lighting lifecycle.
- Existing Home preview cache regression: **18/18 headless**.
- Complete headless Home UI assertions pass, but shutdown reports **two leaked
  ObjectDB instances**. This is an unresolved diagnostic, not a clean lifecycle
  pass; this campaign does not establish its baseline or origin.
- The wider projected-shadow regression fails on the P-51 model contract: hashes
  for its geometry/source/generated script do not match. Those paths already had
  concurrent edits before this change and were preserved. The test directly
  exercises `projected_shadow.gd`, not the changed field collector. Its failed
  log is retained; this is not counted as a suite pass.

No simulation, aircraft data, goldens or graphics quality setting changed. The
full CI suite, native Home interaction soak and exports were not run.

## Reproduce

`source-before.json` identifies HEAD and four dependency paths before integration;
`source-after.json` verifies that only the field collector changed among those
paths. This is not a snapshot of all concurrently edited files. Compressed
reference/candidate sources and all listed check logs are retained. A separate
one-process runner check passes and is retained under `runner-check/`; it is not
pooled into the three-process timing campaign.

On an imported project, from the repository root:

```text
python research/visual-quality/population-shadow/run.py --godot PATH_TO_GODOT --app app --out tmp/population-shadow-repro
godot --headless --audio-driver Dummy --path app --script res://tests/test_field_projected_shadows.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_ui_home_preview_cache.gd
```

The comparison uses a native renderer and requires a new output directory;
`--runs 1` is a short parity/runner check. Omit `--headless` for the native field
regression. Further DT-11a work should measure complete loading and investigate
shutdown diagnostics before claiming those acceptance gates.
