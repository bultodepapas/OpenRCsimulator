# DT-11a — bound the wing light station scan

2026-10-15. `_wing_sections` now searches a sorted copy of its 18 span stations
to find the inclusive interval crossed by each triangle. An index map writes
segments back to their original stations. Output station order, triangle order
within each station, equal-start sorting, normal filtering, edge arithmetic and
upper/lower contour selection remain unchanged.

The index and float64 search coordinates exist only during construction.
Coincident stations retain distinct outputs; negative semispans keep their
original ordering. Non-finite semispans/bounds use the full scan. The native
binary search includes both endpoints, consistent with the
[Godot bsearch contract](https://docs.godotengine.org/en/stable/classes/class_packedfloat64array.html#class-packedfloat64array-method-bsearch)
used in the preceding [belly-station change](../belly-stations/README.md).

## Paired measurement

Five fresh native Godot 4.7.2 `ed1daf0bf` processes on Windows, Compatibility /
OpenGL, RTX 3090 / NVIDIA 610.88, Dummy audio. Each process runs six alternating
reference/candidate pairs per family/workload, reversing the initial order on
even processes. The reference includes all previous wing and belly changes.
Both variants call `wing_skin_lines` once for the two-skin workload; neither
repeats the individual lower/upper extraction in the timed comparison.

Both variants use the same validated model. Extraction and output comparisons
are outside the two-skin timer. Complete-kit timing calls `attach`, including
geometry extraction, materials, lights and crash metadata; teardown is outside
the timer. Medians pool pairs 1–5, **25 samples per variant per family**.

| Family | Two skins, reference → candidate | Complete kit, reference → candidate |
| --- | ---: | ---: |
| Stik | 73.213 → 57.025 ms | 151.537 → 136.966 ms |
| Extra | 41.699 → 35.631 ms | 68.046 → 66.460 ms |
| P-51 | 82.318 → 64.754 ms | 148.333 → 127.262 ms |
| Avanti | 202.260 → 144.901 ms | 356.229 → 301.944 ms |
| Timber | 54.726 → 43.408 ms | 103.358 → 89.495 ms |

Two-skin medians decrease **14.6–28.4%**. Complete-kit pooled medians decrease
2.3–15.2%, but Extra's small difference is mixed across processes: its candidate
is slower in two of five process medians (`extra-per-process.json`). This does
not qualify a reliable full-kit speedup for Extra. The workstation remained
shared with other tracks; these are construction-phase measurements, not
isolated hardware acceptance. Do not add improvements from separate campaigns.

Pair 0 is retained and summarized separately. Models are already built, and kit
timing follows the skin workload, so no sample represents cold application load.
Complete Home/Fly latency, frame pacing, FPS and package qualification remain open.

## Verification

- **300 exact native fleet pairs**: 150 two-skin and 150 complete-kit comparisons.
  Kit snapshots include meshes, material uniforms/shaders, node transforms,
  visibility, shadow flags, light properties and crash-host metadata.
- **256 seeded synthetic cases in each process**, 1,280 evaluations total:
  random and repeated triangles, exact limiting edges, zero-area/steep faces,
  incomplete triangles, positive/negative/zero/signed-zero/tiny/large/non-finite
  semispans. Complete section dictionaries, batched skins and single-skin APIs
  match the reference exactly. Input triangles remain unchanged.
- Three permanent analytical checks cover lower/upper triangle endpoints,
  all coincident station outputs, and left/right order under a negative
  semispan. World/field lights: **78/78 headless**. Night kit: **34/34 headless
  and 34/34 native**, including crash attachment. All three logs are clean.
- Home preview cache: **18/18 assertions pass**. Verbose shutdown still reports
  four audio objects: MP3/WAV streams and their playback objects. The preceding
  [reference/candidate diagnostic](../belly-stations/README.md#verification-and-remaining-diagnostic)
  reproduced these classes on both versions. This remains an open lifecycle
  diagnostic; the current Home run is not counted as a clean shutdown pass.
- A draft regression script needed an explicit `bool` annotation. Its failed
  parse log is retained separately; the corrected test parsed before integration.

No physics, generated assets or flight goldens changed. Full CI, native flight
soak, rendered pilot acceptance and exports were not run.

## Reproduction and identity

Compressed runtime/test sources, isolated diffs, native raw data/logs, check
commands and source hashes are retained here. The five-path guard confirms only
the intended runtime/test paths changed among those paths; it does not freeze
the whole shared repository. The reproduction runner produced all five accepted
processes using the parsed draft, before guarded integration of identical bytes.

```text
python research/visual-quality/wing-light-stations/run.py --godot PATH_TO_GODOT --app app --out tmp/wing-stations-repro
godot --headless --audio-driver Dummy --path app --script res://tests/test_world_field_lights.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_night_kit.gd
godot --audio-driver Dummy --path app --script res://tests/test_night_kit.gd
godot --headless --verbose --audio-driver Dummy --path app --script res://tests/test_ui_home_preview_cache.gd
```

Use an imported project, a native renderer and a fresh output directory.
`--candidate PATH` optionally compares a parsed draft; otherwise it uses the
current app source. `--runs 1` checks a single process. Source identities and
commands are recorded in the output manifest.
