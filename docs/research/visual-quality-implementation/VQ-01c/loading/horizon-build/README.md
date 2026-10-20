# DT-11a — reuse azimuths and preallocate horizon indices

Follow-up, 2026-10-19: [ring invariant hoisting](rows/README.md) reduces complete
native construction by a further 12.3% on its own baseline, with 40 exact mesh
comparisons and 103 regression checks. Campaigns are separate; do not add gains.

2026-10-14. `Horizon.mesh()` evaluates the 1,440 azimuth directions once per build
instead of repeating them for 30 rings, and fills one preallocated index array
instead of constructing 43,200 small packed arrays. Temporary direction tables
use float64 (23,040 bytes total), preserving scalar trigonometric precision until
the existing render-vector boundary. No persistent cache or shared mesh is added.

Profile validation still runs before construction on every call. Vertex and
triangle order, normal accumulation/normalization, the 1,500 m flat disk and the
40 km square boundary stay unchanged. No profile, generated geometry file,
physical terrain, shader or quality setting changes.

## Measurements and exact output

Five fresh native processes, eight alternating reference/candidate pairs each,
with the initial order reversed between processes. Godot 4.7.2 `ed1daf0bf`,
Windows Compatibility, RTX 3090 / NVIDIA 610.88, Ryzen 9 5900X. Shared-host load,
CPU/GPU power and OS caches are uncontrolled.

| Horizon mesh construction | Original median | Adopted median |
| --- | ---: | ---: |
| Pairs 1–7, 35 samples per variant | 68.721 ms | 55.027 ms |
| First call per variant/process, 5 samples | 80.768 ms | 64.113 ms |

The warm median improves **19.9%**, and each of the five per-process medians
improves. Timings include reading/checking the profile and creating the ArrayMesh;
GPU readback/parity is outside timing. First calls exclude process and script
loading, so they are not a cold-start measurement. [Summary](summary.json) keeps
per-process medians and the separate exploration results.

The exploratory run compared angle reuse alone (55.749 ms), index preallocation
alone (51.162 ms), and both (46.014 ms), against 58.949 ms for the original.
Its 24 comparisons pass; do not pool its timings with the five-run campaign.

All **40 campaign pairs** preserve complete surface arrays (43,201 vertices,
normals and 254,880 indices), primitive type, material and serialized AABB.
Every pair checks distinct mesh identity. The 84,960 triangles keep their winding
and order, including the periodic seam. Both versions use the same committed
profile and project settings, verified unchanged throughout timing. Relevant
source hashes and the starting HEAD are in [source-before.json](source-before.json).
This is a targeted working-tree comparison, not a frozen release qualification.

## Regression and native shutdown finding

The existing suites pass **94 headless assertions**: horizon 19, field surfaces
19, field integration 39 and world presentation 17. Horizon coverage checks the
complete height grid, upward normals, winding, manifold topology, periodic seam,
outer footprint, flat flight area and rejection of a checksum-corrupted temporary
profile. No new duplicate unit suite was added.

An isolated mutation changes the temporary direction tables to float32. All eight
native equality comparisons then fail, without engine errors. This demonstrates
why the adopted tables retain float64 precision. Production files are never
mutated for this check.

The native `test_horizon.gd` assertions also pass 19/19, but shutdown reports four
OpenGL texture leaks (349,524 bytes each). The unchanged reference reproduces
the same errors. A disposable deferred runner that releases local scope and waits
two frames still reports them, so that attempted test-lifecycle fix is **not
adopted**. Raw failing logs and its source remain in this evidence directory.
The exact leak cause is unresolved; do not describe it as fixed, harmless or a
new horizon regression. The mesh-only native campaign has no errors or warnings
and creates no atmosphere textures. No production teardown workaround or test
suppression was added.

This slice establishes a narrower construction improvement, **not total field
loading, Home/Fly loading, FPS or GPU frame-time improvement**. The native combined
horizon/atmosphere test is not clean. Full app CI, exports, visual flight coverage,
foreground loading, soak and native Linux/macOS qualification remain open.

## Reproduce and continue

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script res://tests/test_horizon.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script res://tests/test_field_surfaces.gd
```

For paired measurements, decompress `reference.gd.gz`, `candidate.gd.gz` and
`probe.gd.gz` outside `app/`, use the pinned profile/project/engine, and run the
probe natively with `-- --directory=<scripts> --output=<new.json>`. `--reverse`
changes the first variant; `--explore` additionally uses `angles.gd` and
`indices.gd`. [Manifest](evidence-manifest.json) pins commands, artifacts, source
and the runtime diff. The profile remains authored through its existing pipeline.

Continue the [global plan](../../../../../plans/global-performance-visual-quality.md):
attribute remaining initial Home/first-Fly work on a consistent current snapshot,
reserve foreground host time for loading/pacing, and isolate the reproduced
native atmosphere-texture shutdown issue before claiming clean native acceptance.
