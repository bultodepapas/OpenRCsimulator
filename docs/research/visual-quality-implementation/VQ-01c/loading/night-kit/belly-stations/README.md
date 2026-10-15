# DT-11a — bound the fuselage light station scan

2026-10-15. `aircraft_lights.belly_line` previously visited all 14 longitudinal
stations for every triangle. It now finds the inclusive station interval with
two native binary searches and visits only that interval. The triangle's
zero-depth rejection also runs once instead of once per station.

Station coordinates remain float64. Triangle order, edge interpolation, crossing
order, nearest-height ties, continuity and final vertices are unchanged. Both
endpoints and duplicate station values are included. Descending or non-finite
station arrays, and non-finite triangle bounds, retain the original scan. This
follows the sorting/NaN constraints in the official
[PackedFloat64Array.bsearch documentation](https://docs.godotengine.org/en/stable/classes/class_packedfloat64array.html#class-packedfloat64array-method-bsearch)
(accessed 2026-10-15). No persistent cache or asset change is needed.

## Measurements

Five fresh native Godot 4.7.2 `ed1daf0bf` processes, Windows,
Compatibility/OpenGL, RTX 3090 / NVIDIA 610.88, Dummy audio. Each process uses six
alternating reference/candidate pairs for each of five families and two
workloads. Even processes reverse the initial order. Both variants use the same
validated model. Extraction, serialization and teardown are outside the contour
timer; `attach` times complete kit construction, including extraction, materials,
light placement and crash metadata.

Warm medians pool pairs 1–5: **25 samples per variant per family**. The frozen
reference includes the preceding [shared wing cuts](../wing-slices/README.md).
Do not combine results from different campaigns.

| Family | Belly contour, reference → candidate | Complete kit, reference → candidate |
| --- | ---: | ---: |
| Stik | 75.954 → 32.391 ms | 190.389 → 146.418 ms |
| Extra | 31.396 → 15.953 ms | 91.715 → 77.644 ms |
| P-51 | 75.198 → 35.890 ms | 199.511 → 156.520 ms |
| Avanti | 180.349 → 84.311 ms | 451.344 → 354.579 ms |
| Timber | 57.784 → 24.971 ms | 140.724 → 109.773 ms |

Contour medians decrease **49.2–57.4%**; full-kit medians decrease **15.3–23.1%**,
saving 14.071–96.765 ms. Pair 0 is retained in raw JSON and summarized separately.
It is not cold application loading: models are already built and the kit
workload follows contour measurements. This shared-workstation campaign measures
construction phases, not isolated performance qualification. Complete Home/Fly
latency, frame pacing, FPS and exported-package acceptance remain open.

## Verification and remaining diagnostic

- **300 exact native fleet pairs**: 150 contours and 150 complete kits. Snapshots
  include surface arrays, shader source/uniforms, transforms, visibility, shadow
  flags, light properties and crash metadata.
- **256 seeded synthetic cases per process**, 1,280 evaluations total: random
  triangles, a continuous floor, repeated geometry, endpoint contacts, zero-area
  faces, incomplete triangles, ascending/descending/coincident/tiny/outside
  station ranges and non-finite inputs. Outputs match the frozen reference and
  triangle inputs remain unchanged; empty geometry also returns an empty line.
- Four permanent analytical checks cover both inclusive triangle endpoints with
  coincident stations, a continuous floor with descending stations, and stations
  outside the mesh. Night kit: **34/34 headless and 34/34 native**, clean logs.
  World/field lights: **75/75 headless**, clean log.
- Home preview cache: **18/18 assertions pass**, but shutdown reports **four
  ObjectDB leaks**. Verbose runs with both the reference and candidate identify
  `AudioStreamMP3`, `AudioStreamPlaybackMP3`, `AudioStreamWAV` and
  `AudioStreamPlaybackWAV`. The reference run redirects Home → World → aircraft
  lights through disposable script copies; production files are not swapped.
  This is a reproduced audio shutdown diagnostic, not a clean lifecycle pass or
  proof of its root cause. No audio repair is claimed.
- The initial comparison harness assigned the bounds dictionary to an AABB.
  It was corrected to use `.all` before the five accepted runs. The failed log
  is retained as `harness-type-error.log`, excluded from measurements.

No physics, golden flights or generated geometry changed. Full CI, visual flight
acceptance, exports and soak tests were not run. Separate helicopter texture
shutdown diagnostics remain open.

## Reproduce

Compressed before/after sources, the isolated runtime/test diffs, commands,
raw logs/JSON and source hashes are retained here. The monitored source guard
covers five paths, not the whole concurrently edited repository. A one-process
runner check is retained separately and excluded from the table.

```text
python research/visual-quality/belly-light-stations/run.py --godot PATH_TO_GODOT --app app --out tmp/belly-stations-repro
godot --headless --audio-driver Dummy --path app --script res://tests/test_world_field_lights.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_night_kit.gd
godot --audio-driver Dummy --path app --script res://tests/test_night_kit.gd
godot --headless --verbose --audio-driver Dummy --path app --script res://tests/test_ui_home_preview_cache.gd
```

Use an imported project, a native renderer and a fresh output directory.
`--runs 1` checks the runner. Reproduction compares the retained reference with
the current app source; the manifest records both identities.
