# DT-11a — batch accepted shadow triangles

2026-10-21. Adopted: `Projected.append_above()` copies contiguous accepted face
runs with native packed-array operations. Both static and population collectors
use it. The scalar height predicate, face order, incremental bounds, ownership,
range checks and independent output meshes remain unchanged. Aircraft collection
without a cutoff retains its existing direct append. No physics or asset changes.

## Result and scope

Three native Compatibility processes each run ten alternating before/after pairs
on the default field's three nearby caster cells. All **180 workload pairs** have
identical complete surface arrays, serialized bounds and triangle/population
counts. Timing excludes field construction, ownership assignment, comparison,
caster setup and rendering. All ten pairs enter each summary; none are excluded.

| Process | Population caster collection, median ms | Median paired improvement | Static base alone, median ms |
| --- | ---: | ---: | ---: |
| 1 | 36.956 → 31.768 | 14.5% | 8.193 → 7.093 |
| 2 | 42.117 → 38.020 | 11.8% | 10.093 → 8.304 |
| 3 | 34.284 → 30.468 | 10.9% | 8.280 → 7.041 |

Population rows already include static base collection; **do not add the two
columns**. Host variation is substantial, especially in process 2. These are
component construction results, not full field-build, loading or FPS gains.
[summary.json](summary.json) retains every pair and calculation; `integrated-*.json`
retain the per-cell samples. Windows, Godot 4.7.2 `ed1daf0bf`, Compatibility,
RTX 3090 / NVIDIA 617.42. Benchmarks ran serially, without our tests or captures
running concurrently; unrelated host activity was not controlled.

## Verification

Seven integrated suites pass: shadow collection (77), population collection (54),
projected shadow (43), field shadows (59), windsock shadows (22), field integration,
and world presentation context (17). The new fixture covers leading/trailing and
consecutive rejected triangles, alternating runs, exact cutoff equality, empty
streams, source immutability and placement rejection. A disposable `<=` to `<`
mutation produces nine failures. Production files were not mutated.

Native 1280×720 field captures cover flightline, pilot and club views. Flightline
and pilot PNGs are byte-identical in both candidate runs. Club differs from the
baseline at two pixels in the first run and one in the repeat, by at most one
8-bit channel level. The two candidate captures also differ from each other.
No visible change was observed; **pixel-exact parity is not claimed** for club.
[visual-parity.json](visual-parity.json) records the hashes and pixel deltas;
original PNGs and capture reports remain under `captures/`.

Checked logs are under `checks/`. The existing maple-wind warning remains.
All three capture processes report the same four-object exit warning; this
change does not resolve the existing shutdown issue. Full CI, release Home/Fly
timing, flight pacing and physical-display qualification were not rerun.

## Rejected trials and identity

Lazy population mesh reads/copies were rejected: the first variant slowed the
fixture, and moving its copy outside the triangle loop made its gain negligible.
In-place face compaction produced only a small gain. Run batching was retained.
Exploratory logs/samples and frozen scripts remain under `exploration/` and
`provenance/`. A draft Windows-path escaping error and a stale test filename
were corrected; those failed invocations are separate from passing evidence.

Baseline: `e51af959` (full identity in [source-identity.json](source-identity.json)).
Both original runtime files match that commit after LF normalization. The
comparison's reference field script rewrites only its Projected preload to the
frozen reference collector. The integrated runtime changes only the two render
scripts. The comparator's final logging removes an overlapping total and adds
empty-input/output guards; measured runtime and per-cell rows are unchanged.

## Reproduce

Use the pinned native engine and existing imported project. Copy
`provenance/projected-original.gd.txt` to an external `projected-original.gd` and
`provenance/field-original.gd.txt` to `field-baseline.gd`. In that field copy,
replace `res://render/projected_shadow.gd` with the absolute forward-slash path
to the frozen projected script. Keep drafts outside `app/`.

```powershell
& .tools/Godot_v4.7.2-stable_win64.exe --path app --audio-driver Dummy `
  --script "$PWD/tools/shadows/compare_field_collection.gd" -- `
  --reference=D:/scratch/field-baseline.gd `
  --reference-projected=D:/scratch/projected-original.gd `
  --out=D:/scratch/collection.json
```

Run the seven named `res://tests/test_*.gd` scripts through the checked runner;
the world test is `test_world_presentation_context.gd`. Native captures use
`tools/shadows/vq04a_capture.gd -- --field --out=<new absolute directory>`.
The [Godot packed-array reference](https://docs.godotengine.org/en/4.7/classes/class_packedvector3array.html)
documents reference passing and exclusive slice endpoints; exact output is
established by the tests above.
