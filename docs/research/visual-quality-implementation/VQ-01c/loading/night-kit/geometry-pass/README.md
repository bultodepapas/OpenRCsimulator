# DT-11a — extract aircraft light geometry in one pass

2026-10-15. Night-kit construction previously walked the model twice to collect
vertices and triangles, repeating ancestry transforms, surface-array reads and
native vertex transforms. `_geometry_arrays` now creates both outputs from each
transformed surface once. `vertices` and `triangles` keep their existing APIs and
use the same collector with their respective output enabled.

Mesh-type and primitive filters remain distinct: vertex collection retains
unused vertices and non-triangle surfaces from ArrayMesh/PrimitiveMesh, while
triangle collection keeps the original triangle-surface/index rules. Root-local
transforms, traversal order, hidden meshes, index winding and output ownership
are unchanged. The collector stores no persistent cache.

## Measurement

Five fresh native Godot 4.7.2 `ed1daf0bf` processes, Windows, Compatibility /
OpenGL, RTX 3090 / NVIDIA 610.88, Dummy audio. Six alternating reference/candidate
pairs per family/workload; even processes reverse the initial order. Both
variants use the same validated model. The reference includes the preceding
[direct edge traversal](../edge-walk/README.md).

Geometry timing covers both output arrays: two existing calls in the reference,
one combined call in the candidate. Complete-kit timing calls `attach`, including
extraction, contours, materials, lights and crash metadata. Model construction,
output comparisons and teardown are outside the timers. Warm medians pool pairs
1–5, **25 samples per variant per family**.

| Family | Geometry, reference → candidate | Complete kit, reference → candidate |
| --- | ---: | ---: |
| Stik | 12.735 → 8.954 ms | 85.855 → 81.157 ms |
| Extra | 3.019 → 1.723 ms | 42.828 → 40.577 ms |
| P-51 | 9.532 → 5.806 ms | 91.679 → 87.656 ms |
| Avanti | 28.029 → 23.197 ms | 207.808 → 201.568 ms |
| Timber | 8.523 → 7.086 ms | 64.329 → 62.936 ms |

Geometry medians decrease **16.9–42.9%**; full-kit medians decrease **2.2–5.5%**,
saving 1.393–6.240 ms. Geometry improves in all five process medians for each
family. Complete-kit process medians include one slower candidate process each
for Extra and Avanti; per-process values are retained in `summary.json`.

First-pair geometry medians also decrease: Stik 13.287→8.632, Extra 4.029→2.412,
P-51 10.773→6.287, Avanti 27.631→24.837 and Timber 9.477→6.969 ms (five samples
per variant). These are first collector calls on already-built models, not cold
application loading. The workstation remained shared with other tracks. Full
Home/Fly latency, FPS, pacing and isolated package qualification remain open;
do not pool absolute timings or improvements across campaigns.

## Rejected direct native replacement

The upstream [Mesh implementation](https://github.com/godotengine/godot/blob/master/scene/resources/mesh.cpp)
(reviewed 2026-10-15) shows `get_faces()` using a cached triangle mesh and also
expanding triangle-strip surfaces. The retained native probe verifies the
semantic mismatch on the pinned local engine: one triangle plus one four-vertex
strip produces **9 face vertices** through `get_faces()`, whereas the existing
triangle-surface-only collector returns **3**. Therefore a direct replacement
was rejected before performance qualification. No native cache timing or memory
benefit is claimed. The adopted collector retains the existing filters.

## Verification

- **300 exact native fleet pairs**: 150 combined geometry arrays and 150 full
  kits. Kit snapshots include mesh arrays, shader source/uniforms, transforms,
  visibility, light properties, shadow flags and crash metadata.
- **256 synthetic cases per process**, 1,280 evaluations total, compare combined
  and individual APIs under nested transforms, rotation/reflection/nonuniform
  scale, indexed/unindexed and mixed triangle/line surfaces, primitives, empty
  mesh nodes and hidden meshes. Source mesh arrays remain unchanged.
- Three permanent analytical checks cover root-local coordinates, unused/line
  vertex retention, index winding, non-triangle exclusion and mutation isolation
  between outputs, source meshes and later calls. World/field lights:
  **81/81 headless**; night kit: **34/34 headless and 34/34 native**, clean logs.
- Home preview cache: **18/18 assertions pass**, with the previously recorded
  four-object audio shutdown warning (MP3/WAV streams and playback objects).
  The [earlier reference/candidate diagnostic](../belly-stations/README.md#verification-and-remaining-diagnostic)
  remains open; this run is not a clean lifecycle pass.
- The first draft-test parse still referenced the old runtime API. Its log is
  retained separately. A disposable copy redirected that preload to the parsed
  candidate before integration; the integrated test then passed normally.

No physics, generated geometry or golden flights changed. Full CI, exports,
visual pilot acceptance and native flight soak were not run.

## Reproduce

Compressed runtime/test before/after sources, isolated diffs, raw native results,
check logs and hashes are retained here. The five-path guard covers the named
sources, not the whole concurrently edited tree. The reproduction runner used
the parsed draft for all five accepted processes before identical-byte integration.

```text
python research/visual-quality/aircraft-light-geometry/run.py --godot PATH_TO_GODOT --app app --out tmp/light-geometry-repro
godot --headless --audio-driver Dummy --path app --script res://tests/test_world_field_lights.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_night_kit.gd
godot --audio-driver Dummy --path app --script res://tests/test_night_kit.gd
godot --headless --verbose --audio-driver Dummy --path app --script res://tests/test_ui_home_preview_cache.gd
godot --audio-driver Dummy --path app --script ABSOLUTE_PATH/research/visual-quality/aircraft-light-geometry/native_faces_probe.gd
```

Use an imported project, native renderer and fresh output directory. The runner
compares the retained reference with the current app source, or a parsed draft
via `--candidate PATH`. `--runs 1` checks one process. The manifest records source
identities and commands.
