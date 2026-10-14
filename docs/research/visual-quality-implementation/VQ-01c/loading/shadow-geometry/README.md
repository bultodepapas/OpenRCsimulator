# DT-11a — native bulk transforms for shadow geometry

2026-10-14. `Projected.collect()` transforms each mesh's packed face stream with
Godot's native `Transform3D * PackedVector3Array` operation. When the caller uses
the default no-cutoff mode, it appends the complete stream directly. Static
casters retain their per-triangle height predicate. Visibility, propeller
exclusion, traversal order, incremental bounds and independent mesh ownership
stay unchanged. No simulation, asset, shader or persistent cache changes.

The earlier [loading attribution](../ground-image/README.md) recorded roughly
35 ms in aircraft shadow binding. This slice targets that construction work.
It does not change shadow refresh or the per-frame render workload.

## Decision and exact output

The [Godot 4.7 Transform3D reference](https://docs.godotengine.org/en/4.7/classes/class_transform3d.html#class-transform3d-operator-mul-packedvector3array),
checked 2026-10-14, documents transforming packed vectors in one native operation.
Actual parity and timing below use the repository's pinned Godot 4.7.2 binary.

Three native runs each make six alternating reference/candidate pairs across
six aircraft, 55 field meshes, and six complete aircraft shadow bindings:
**1,206 exact pairs**. The probes compare complete mesh surface arrays, triangle
counts and serialized AABB values; they compare the actual projector proxy after
binding. All pairs pass, with no engine errors or warnings. A new mesh still
belongs to each collected shape; there is no cross-model cache to invalidate.

Two alternatives were evaluated before adoption:

- Bulk transforms alone preserve output but retain most of the GDScript loop
  cost for aircraft. The adopted no-cutoff branch also appends packed faces.
- Replacing the incremental bounds scan with `ArrayMesh.get_aabb()` is rejected.
  It changes serialized bounds in five of the 61 tested collection workloads.
  A diagnostic confirms equal Stik surface arrays but unequal bounds. The
  original bounds scan is retained; no tolerance was introduced to accept it.

Exploration reports include the rejected cases and are separate from the passing
three-run campaign. The optimization assumes valid finite mesh geometry, as do
the existing model authoring and rendering contracts.

## Measurements

Windows, Godot 4.7.2 `ed1daf0bf`, Compatibility, RTX 3090 / NVIDIA 610.88,
Ryzen 9 5900X. Other work was active on the host. These are synchronous CPU-side
construction timings; comparisons/readback and carrier creation are outside the
timed interval. Each run discards pair zero from its warm summary. The table
uses the median of the remaining 15 samples per variant and workload.

| Aircraft | Geometry collection, original → adopted | Shadow binding, original → adopted |
| --- | ---: | ---: |
| Ugly Stik | 14.315 → 7.048 ms | 17.928 → 10.990 ms |
| Extra 300S | 4.387 → 1.881 ms | 10.183 → 7.558 ms |
| Avanti S | 1.547 → 0.644 ms | 7.631 → 6.474 ms |
| P-51D | 15.545 → 6.848 ms | 21.367 → 11.948 ms |
| Turbo Lumber | 10.976 → 5.062 ms | 15.198 → 10.255 ms |
| X-Cell research / HX-700 visual | 30.246 → 15.052 ms | 32.810 → 16.130 ms |

The sum of the 55 static field collection timings has a median of
**15.150 → 14.495 ms**. This roughly 4.3% result is small and does not qualify a
5% field improvement. It is not a full-field build measurement. Aircraft
collection improves in every per-run median; [summary.json](summary.json) keeps
those separate medians as well as the pooled values.

The comparison source is the frozen `5f7f4ad529940743bdc16e3d9691243a8a1c6cd8`
archive/import snapshot with the accepted ground-image and grass-mask changes in
both variants. Only `Projected.collect()` differs between the external scripts.
For binding, two otherwise identical `shadow.gd` copies select those scripts.
The reference collector is text-identical to the current pre-change source after
line-ending normalization. This does not identify the models as the latest
working-tree aircraft: their exact inputs are pinned in the
[source verification](source-verification.json).

## Regression and limits

The integrated shared-tree checks pass **227 headless assertions**: collection
77, projected shadow 37, field projected shadows 57, field integration 39 and
world presentation 17. The first three also pass **171 assertions with the native
renderer**. The collection checks cover exact face order, positive/negative and
nonuniform scale, shear, collapsed geometry, distant coordinates, cutoff equality,
infinite/NaN cutoff values, hidden/propeller subtrees, root meshes and unchanged
source arrays. These checks validate software behavior, not physical fidelity.

A disposable mutation that bypasses every height cutoff triggers 31 failures.
It never modifies production files. The initial test harness used authored
vertices instead of the face stream returned by the mesh and failed ten checks;
the corrected scalar oracle uses the same input face stream as the collector.
Both attempts are retained, and the failed draft is not counted as passing.

This slice does not rerun Home/Fly timing: the preceding campaign had no fully
active pair on this shared host. It makes **no FPS, cold-start, full loading,
current-package or native Linux/macOS claim**. Full app CI, exports, the visual
flight matrix, qualified foreground loading and soak remain open. No goldens
were re-recorded.

## Reproduce and next action

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script res://tests/test_shadow_collection.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script res://tests/test_projected_shadow.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script res://tests/test_field_projected_shadows.gd
```

Omit `--headless` for native checks. `app/test.sh` discovers the new test.
For attribution, decompress the retained scripts outside `app/`, update the
absolute collector preloads in `shadow-reference.gd` and `shadow-candidate.gd`,
and run `probe.gd` with a native renderer and `-- --directory=<script-directory>`.
Use identical imported application and sibling asset trees. `campaign.py.gz`
records orchestration; [manifest](evidence-manifest.json) pins inputs and outputs.

Continue the [global plan](../../../../../plans/global-performance-visual-quality.md):
attribute remaining Home/first-Fly costs on a consistent current snapshot, then
reserve foreground host time for loading and pacing acceptance. Appearance and
quality-profile gates remain unchanged.
