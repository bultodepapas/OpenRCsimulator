# DT-11a — native helicopter canopy transforms

2026-10-15. The canopy collector now transforms each source surface's packed
vertices once using `Transform3D * PackedVector3Array`, then expands indices in
their original order. Non-indexed output uses `append_array`. Source geometry,
root-relative transforms, winding and contour arithmetic stay unchanged. The
temporary transformed surface array is released after collection; there is no
persistent geometry cache or simulation-state change.

## Measurement

Godot 4.7.2 `ed1daf0bf`, Windows, Compatibility/OpenGL, RTX 3090, Dummy audio.
Five fresh native processes; six serial pairs per workload, alternating variant
order and reversing the starting order between processes. Model construction,
output snapshots and cleanup are outside the timed region. Pair zero remains in
the raw results; the table pools the other 25 samples per variant/workload.

| Workload | Reference median | Candidate median | Interpretation |
| --- | ---: | ---: | --- |
| Extract 38,240 canopy triangles | 7.022 ms | 5.994 ms | 14.6% reduction; all five process medians improve |
| Construct complete night kit | 146.902 ms | 145.397 ms | Mixed process results; no qualified whole-kit gain |

Three process medians regress slightly for complete-kit construction. Shared-host
activity is uncontrolled; the accepted performance conclusion is limited to the
extraction phase, about 1 ms saved in this campaign. This does not establish a
perceptible Home/Fly loading improvement, cold startup, FPS or crash-latency gain.
[Summary](summary.json), [commands and hashes](manifest.json), and five native
JSON/log pairs retain the distribution and first-pair samples.

## Correctness and robustness

All **60 real canopy/complete-kit geometry pairs** match byte for byte. Each
process also runs the same 256 synthetic cases: 1,280 case evaluations, not 1,280
unique scenarios. They cover indexed and non-indexed surfaces, reversed/repeated/
degenerate indices, unused vertices, nested rotations, reflected nonuniform
scales, root-local coordinates, source ownership and subsequent parent movement.

The initial probe exposed an existing error: Godot returns a null index slot for
non-indexed `ArrayMesh` surfaces. Assigning it directly to `PackedInt32Array`
failed before reaching the intended non-indexed branch. The candidate normalizes
only that null slot to an empty packed array. The [failed probe log](unindexed-probe-failure.log)
is retained; it is excluded from accepted measurements. Synthetic cases compare
against the original scalar transform arithmetic with this explicit null fallback,
since the unmodified reference cannot process those surfaces. The real indexed
HX700 comparison uses the unmodified frozen reference.

Three permanent checks verify mixed-surface order/root coordinates, independent
output/source buffers and immediate parent-transform changes. Draft runtime,
harness and test were parsed outside `app/` before integration.

| Integration check | Result |
| --- | --- |
| Helicopter lights, headless | 42 checks; clean exit |
| Night rotor, headless | 18 checks; clean exit |
| Crash presentation, headless | 44 checks; clean exit |
| Home cache, headless | 18 checks; four ObjectDB exit leaks |
| Helicopter lights, native | 42 checks; two texture exit leaks, 349,524 bytes each |

[Checks and commands](checks.json) retain all diagnostics. Native integration is
not counted as clean; the earlier [reference reproduction](../../heli-updates/README.md)
records the existing texture issue. Home lifecycle qualification also remains
open. This slice does not run full Linux CI, exported packages or pilot acceptance.

## Reproduce

```powershell
python research/visual-quality/heli-canopy-transforms/run.py --godot .tools/Godot_v4.7.2-stable_win64.exe --out tmp/heli-canopy-transforms-reproduction
```

Use a fresh output directory. The runner expands `reference.gd.gz` and compares
the current runtime; `--candidate` selects an external draft. Accepted candidate,
test before/after, parse logs, runtime hashes and evidence manifest are retained.

Primary source consulted 2026-10-15: [Godot Transform3D operator documentation](https://docs.godotengine.org/en/stable/classes/class_transform3d.html#class-transform3d-operator-mul-packedvector3array)
documents bulk packed-array transforms and their advantage over per-element
transforms on larger arrays. Local measurements above determine the accepted gain.
