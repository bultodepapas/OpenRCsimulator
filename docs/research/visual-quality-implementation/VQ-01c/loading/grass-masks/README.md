# DT-11a — discard distant grass masks once per build

2026-10-14. `ImportedNearGrass.layout()` now filters the exclusion list against the
validated placement area's bounds before testing its 6,000 rows. The default
world retains five of twenty masks. Plant selection, quality limits, dimensions,
source meshes/materials, transforms, color and custom instance data stay exact.
No physics, polygon test, shader, asset or persistent cache changes.

## Decision and correctness

Every checksum-validated placement lies inside a circle of radius 30 m around
the current pilot. Its enclosing square is a conservative bound. Drop a mask
only when its existing AABB, expanded by the same 0.4 m clearance, is strictly
separated from that square. Boundary equality and indeterminate comparisons stay
with the original point/polygon predicate. The filtered list is local to each
call, so pilot or exclusion changes cannot reuse stale acceptance results.

The initial candidate ranked all rows before checking clearance and stopped once
each asset quota was full. Its 72 comparisons preserved output and improved the
default case, but sparse/all-blocked cases regressed from roughly 10–13 ms to
55 ms. **Rejected.** Its source and measurements remain under `rejected/`.
The adopted filter keeps the original selection order and avoids that sorting
overhead; it does not assume which rows will be accepted.

## Measurements and parity

Source is the previous frozen `5f7f4ad529940743bdc16e3d9691243a8a1c6cd8`
archive/import snapshot plus the accepted [ground-image cache](../ground-image/README.md)
in both variants. The original `imported_near_grass.gd` is text-identical to the
current pre-change file after line-ending normalization. Only that file is the
treatment. Windows / Godot 4.7.2 `ed1daf0bf`, Ryzen 9 5900X, RTX 3090, NVIDIA
610.88. Other work was active on this shared host; no idle-host, refresh, power,
OS/import/driver-cache or release qualification is claimed.

[Layout report](layout-parity.json): 72 alternating pairs across six field/mask
cases and four quality names, including the high fallback for an unknown name.
Every complete returned array/dictionary is byte-identical. High-tier medians:

| Layout case | Original | Filtered |
| --- | ---: | ---: |
| Default scenery + lake masks | 166.775 ms | 107.286 ms |
| No masks | 79.416 ms | 78.022 ms |
| Shifted pilot | 174.805 ms | 72.665 ms |
| Sparse rough surface | 21.177 ms | 21.230 ms |
| All blocked | 14.494 ms | 15.788 ms |
| Pilot outside the field | 124.047 ms | 22.191 ms |

The [native constructor report](build-verified.json) makes six alternating pairs
per quality and six full-field pairs; exclude pair zero from timing summaries.
All 18 grass-builder pairs preserve complete GPU-facing MultiMesh buffer bytes,
source mesh arrays, material references, node properties and metadata after
normalizing intentionally fresh resource identities.

- High-quality grass construction: median **212.276 → 123.677 ms**, about 42% less.
- Complete field construction: median **846.624 → 822.227 ms**, only 2.9% in this
  noisy campaign. This does not establish a 5% complete-field improvement.

These are synchronous construction measurements, with readback/parity outside
the timed interval. They are not frame time, FPS, process-cold startup or pilot
readability results. The layout's small all-blocked increase is retained rather
than described as zero overhead. The useful finding is removal of repeated
distant-mask checks with exact output; complete-load qualification remains open.

## Validation and limitations

The new `test_grass_mask_bounds.gd` checks all four inclusive edges, strict gaps,
source-row bounds, moved pilots, missing/malformed values, NaNs, unmodified
inputs and point-predicate agreement over four 61×61 squares plus clearance-edge
points. Draft parsing and **23/23** checks passed before integration.
The integrated shared-tree test also passes 23/23. Six focused suites on the
frozen comparison source pass **167 checks**: imported grass 27, near grass 38,
LU-18 ground 27, field surfaces 19, field integration 39 and presentation context
17. Their logs contain no engine errors or warnings.

A disposable mutation changing strict separation to inclusive separation fails
exactly the four edge checks. The first mutation harness accidentally doubled
Windows carriage returns and failed parsing; its failed attempt is retained.
The corrected UTF-8 harness reaches the four intended assertions and restores
the candidate bytes afterward. No mutation was applied to the working app.

The native full-build comparison initially compared freshly allocated Mesh and
MultiMesh identities. That harness rejected equivalent output. The corrected
probe compares complete mesh/instance bytes and the associated material bindings,
and normalizes only the metadata's MultiMesh references. Both attempts are kept;
the failed run is not used as passing evidence. Godot's official
[MultiMesh buffer API](https://docs.godotengine.org/en/stable/classes/class_multimesh.html#class-multimesh-property-buffer)
was checked on 2026-10-14; the pinned native runtime verifies the actual readback.

Home/Fly reports under `pairs/` retain the complete five-pair attempt. All ten
processes complete cleanly; 14 of 20 first draws are active and six are paused.
None of the five pairs has both runs entirely active, so this campaign is
**not eligible for interactive-loading
acceptance**. No automatic resume or focus-safety override was added. Do not pool
these reports with the preceding ground-image campaign or claim a loading/FPS
gain from their medians. The exact exit/active-draw ledger is in `pairs/campaign.json`.
Paused observations have tick zero and 908 flight nodes; active observations have
tick 12 and 879. Every return has 549 Home nodes and zero reported orphans.
The cause of the paused first draws is not established by this campaign.

Focused regression and mutation results are retained under `checks/`; the
[manifest](evidence-manifest.json) pins sources and raw artifacts. The full app
suite, fresh exports, visual flight suite, clean-account lifecycle, 30-minute
soak and native Linux/macOS display qualification remain open. No goldens changed.

## Reproduce and continue

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script res://tests/test_grass_mask_bounds.gd
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy `
  --script res://tests/test_imported_near_grass.gd
```

For paired attribution, decompress the retained `.gd.gz` probes and reference
outside `app/`. The layout probe takes `--reference=<reference.gd>` and
`--output=<new.json>` after `--`; the build probe additionally needs
`--field-reference=<field_reference.gd>` and a native renderer. Replace the
retained absolute grass-reference preload in that field copy with its new path.
Keep identical imported `app/` and sibling `assets/` trees for both variants.
The [loading guide](../../../../../../research/performance/README.md#homefly-loading-and-lake-geometry)
owns the real Home/Fly probe contract.

Next: attribute remaining initial Home/first-Fly work on a consistent current
snapshot, and reserve foreground display/host time for eligible loading and
active-flight measurements. Appearance changes and profile qualification retain
the [global plan's order](../../../../../plans/global-performance-visual-quality.md).
