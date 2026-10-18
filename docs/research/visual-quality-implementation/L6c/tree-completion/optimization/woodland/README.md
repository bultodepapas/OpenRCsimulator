# Woodland shrub build optimization

`WoodlandEdges.build` now obtains shrub placements from `Hedge.layout` and creates the four final patch batches directly. This removes the 48 temporary hedge roots and their throwaway `QuadMesh`/`MultiMesh` objects. The final batches still use the hedge manifest frame size, cached impostor material and the existing ground correction, transforms, colors, custom data, bounds, shadow mode and metadata.

The focused regression is `app/tests/test_woodland_edge_habitat.gd`. It checks the pinned high-tier batch counts, final batch settings and independent shrub mesh/MultiMesh ownership in addition to the existing plant, triangle, batch and determinism contracts.

The native-renderer fixture is `research/performance/woodland_build_probe.gd`. It compares complete scene snapshots for low, balanced and high tiers, including per-instance transforms/colors/custom data and buffers, mesh arrays, material/shader/texture settings, custom AABBs, plant metadata and build statistics. It rejects headless rendering because headless MultiMesh readback does not provide accepted instance values. Its report records hashes for the changed runtime, reference, field/scenery/lake, recipe and atlas; `SHA256SUMS.txt` pins the fixture, test and raw reports/logs as well.

The comparison used three serial native Windows processes on Godot 4.7.2 with the NVIDIA GeForce RTX 3090 and OpenGL 3.3.0 / driver 617.42. Each process captured 27 alternating warm pairs (nine per quality); the first-side order was reference, candidate, reference. All nine quality comparisons matched exactly, and resource checks found 16 distinct `MultiMesh` and card-mesh resources across the two implementations with the intended shared cached shrub material.

| Tier | Reference warm median | Candidate warm median | Change |
| --- | ---: | ---: | ---: |
| Low | 4 µs | 4 µs | unchanged |
| Balanced | 9,994 µs | 6,247 µs | 37.5% lower |
| High | 12,686 µs | 8,642 µs | 31.9% lower |

Values are medians of the three per-process medians. The low tier bypasses construction, so its microsecond values are timer noise. First-call diagnostics are in the raw reports, but the two implementations share process-level `Hedge`/`Library` caches; only the warm alternating medians support the construction-time comparison. This measures `build()` calls only and makes no FPS claim. The fixture’s first-call order is selectable with `--first-side reference|candidate`.

Run one probe process from the repository root with the native Godot binary; use a new output path, keep retained evidence immutable and wait for the process to finish:

```powershell
& '.tools\Godot_v4.7.2-stable_win64.exe' --path "$PWD\app" --script "$PWD\research\performance\woodland_build_probe.gd" --audio-driver Dummy -- --reference "$PWD\docs\research\visual-quality-implementation\L6c\tree-completion\optimization\woodland\woodland_edge_habitat_reference.gd" --output "$PWD\tmp\woodland-native-new.json" --first-side reference --warm-samples 9
```

Accepted raw reports/logs are `native-windows-run-01` through `native-windows-run-03`; SHA-256 values are listed in `SHA256SUMS.txt`. The separately labeled WSLg diagnostic is excluded from the aggregate. Exact source/input hashes are in each JSON report; the whole-repository revision was not frozen across the task, so conclusions are scoped to these file and input hashes.

The pinned baseline runtime SHA-256 is `2d407c0957c48b96e7ad563b93ba6401d00fc30374f7e0b09eabef7780dc72b2`; the candidate runtime SHA-256 is `3be7f31aa77046dec10e4e42ab309044f1d886f2329aa2adfc4499ae378bdd0a`.
