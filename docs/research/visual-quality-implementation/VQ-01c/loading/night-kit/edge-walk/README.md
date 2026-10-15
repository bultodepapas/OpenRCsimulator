# DT-11a — avoid temporary edge arrays in light construction

2026-10-15. `_wing_sections`, `belly_line` and `wing_piece` now visit AB, BC and
CA directly. Previously each edge-loop entry constructed an outer array and
three endpoint arrays. The direct three-step loop selects the same Vector3
endpoints in the same order, without those four temporary arrays. Intersection
tests, interpolation, hit collection, segment sorting and contour selection are
unchanged. No persistent cache or new resource ownership is introduced.

## Measurement

Five fresh native Godot 4.7.2 `ed1daf0bf` processes on Windows, Compatibility /
OpenGL, RTX 3090 / NVIDIA 610.88, Dummy audio. Each process runs six alternating
reference/candidate pairs per family/workload; even processes reverse the initial
order. The reference already contains the [bounded wing scan](../wing-stations/README.md).

The contour workload calculates both wing skins, the belly line and the landing
light's wing section. Model construction, triangle/bounds extraction and exact
comparison are outside that timer. Complete-kit timing calls `attach`, including
extraction, materials, lights and crash metadata; teardown is outside the timer.
Both variants use the same validated model. Warm medians pool pairs 1–5,
**25 samples per variant per family**.

| Family | Contours, reference → candidate | Complete kit, reference → candidate |
| --- | ---: | ---: |
| Stik | 62.943 → 59.717 ms | 88.906 → 86.849 ms |
| Extra | 36.850 → 33.441 ms | 45.443 → 41.748 ms |
| P-51 | 72.560 → 67.376 ms | 98.441 → 93.748 ms |
| Avanti | 179.594 → 167.837 ms | 216.253 → 206.664 ms |
| Timber | 53.045 → 48.638 ms | 64.555 → 62.160 ms |

Contour medians decrease **5.1–9.3%**; complete-kit medians decrease **2.3–8.1%**,
saving 2.057–9.589 ms. Per-process medians remain in `summary.json`: one process
each has a slower candidate kit for P-51 and Avanti. These modest reductions are
phase measurements on a shared workstation, not isolated performance qualification.
Do not add gains or compare absolute times across separate campaigns.

Pair 0 is retained and summarized separately. Models are already constructed and
kit timing follows the contour workload, so neither pair 0 nor warm medians
represent cold application load. Full Home/Fly latency, frame pacing, FPS and
exported-package acceptance remain open. Allocation counts above follow the
removed array expressions; heap usage and allocation latency were not profiled.

## Verification

- **300 exact native fleet pairs**: 150 combined contour and 150 complete-kit
  comparisons across five visual families. Kit snapshots include mesh arrays,
  shader source/uniforms, transforms, visibility, shadow flags, light properties
  and crash metadata.
- **256 seeded synthetic cases per process**, 1,280 evaluations total, compare
  section dictionaries, both skins, individual skin APIs, belly lines and landing
  sections. Cases include random/repeated/degenerate triangles, limiting edges,
  positive/negative/zero/signed-zero/tiny/large/non-finite semispans, varied belly
  bounds, non-finite vertices and incomplete triangles. Inputs remain unchanged;
  empty inputs agree with the frozen reference.
- Existing analytical endpoint/order and skin-position regressions pass:
  world/field lights **78/78 headless**, night kit **34/34 headless and 34/34
  native**, including crash attachment. All retained logs are error/warning-free.
- Home preview cache **18/18 headless**, with a clean verbose exit in this run.
  The earlier [four-object audio shutdown diagnostic](../belly-stations/README.md#verification-and-remaining-diagnostic)
  remains open: this slice changes no audio lifecycle code and one clean exit
  does not establish its resolution.

No simulation, generated assets or golden flights changed. Full CI, exports,
native flight soak and visual pilot acceptance were not run.

## Reproduce

Compressed reference/candidate sources, the isolated runtime diff, raw native
JSON/logs, commands and monitored source hashes are retained here. The five-path
guard verifies that only the runtime changed among those paths, not that the
whole shared repository was frozen. The reproduction runner produced all five
accepted processes from the parsed draft before identical-byte integration.

```text
python research/visual-quality/light-edge-walk/run.py --godot PATH_TO_GODOT --app app --out tmp/light-edge-walk-repro
godot --headless --audio-driver Dummy --path app --script res://tests/test_world_field_lights.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_night_kit.gd
godot --audio-driver Dummy --path app --script res://tests/test_night_kit.gd
godot --headless --verbose --audio-driver Dummy --path app --script res://tests/test_ui_home_preview_cache.gd
```

Use an imported project, native renderer and fresh output directory. The runner
compares the retained reference with the current app source, or an explicit
parsed draft via `--candidate PATH`. `--runs 1` checks a single process. The
output manifest records the compared sources and commands.
