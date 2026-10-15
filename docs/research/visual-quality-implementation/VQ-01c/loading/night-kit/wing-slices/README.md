# DT-11a — share upper/lower wing light cuts

2026-10-15. The fixed-wing night-kit constructor now calculates wing-plane
intersections once for both skins. `_wing_sections` stores each segment's chord
interval and lower/upper height, and sorts each station once from the original
triangle order. Two read-only selectors produce independent lower and upper
lines. `underwing_lines` keeps its single-skin API; `wing_skin_lines` supplies the
combined construction path used by `attach`.

Normal filtering, intersection arithmetic, station order, chord merging, tie
behavior and continuation rules are unchanged. Sections live only within the
call. One extra height value per segment replaces the repeated scan/sort; no
persistent cache, scene reuse, asset edit or physics change is introduced.

## Measurements

Five fresh native Godot 4.7.2 `ed1daf0bf` processes, Windows, Compatibility/OpenGL,
RTX 3090 / NVIDIA 610.88, Dummy audio. Each family/workload has six alternating
reference/candidate pairs; the starting order reverses on even processes. Both
variants share the same validated aircraft model within each process. Geometry
extraction and exact-output comparison are outside the timed two-skin workload;
the complete-kit workload calls `attach` and includes extraction, materials,
lights, placement and crash metadata. Teardown is outside the timer.

Warm medians pool pairs 1–5: **25 samples per variant per family**. The reference
already contains the preceding [native transform repair](../transforms/README.md).
Do not add percentages or absolute times from separate campaigns.

| Family | Two skins, reference → candidate | Complete kit, reference → candidate |
| --- | ---: | ---: |
| Stik | 142.695 → 70.460 ms | 281.438 → 210.399 ms |
| Extra | 87.325 → 46.795 ms | 138.458 → 93.327 ms |
| P-51 | 184.233 → 95.955 ms | 330.372 → 231.628 ms |
| Avanti | 465.465 → 246.562 ms | 748.574 → 527.516 ms |
| Timber | 112.231 → 56.947 ms | 200.540 → 137.986 ms |

Two-skin construction decreases **46.4–50.6%**; complete-kit medians decrease
**25.2–32.6%**, saving 45.131–221.058 ms. Raw pairs, including pair 0, and first-pair
medians remain in the JSON evidence. Kit timing follows the skin workload, so
neither first-pair timing nor these warm medians represent cold application load.

The workstation remained shared: other tracks ran headless parsing/checks and
edited unrelated files. This is phase attribution under host variation, not the
isolated DT loading gate. Full Home/Fly latency, frame pacing, FPS and package
qualification remain unmeasured here.

## Verification

- **300 exact native fleet pairs**: 150 two-skin output comparisons and 150 full
  kit comparisons, including surface arrays, material uniforms/shader source,
  node transforms, visibility, light properties and crash-host metadata.
- **256 seeded synthetic cases per process**, 1,280 cases total: random geometry,
  repeated/tied segments, station boundaries, steep and collapsed faces, trailing
  incomplete triangles and positive/negative/zero semispans. Combined results and
  both single-skin APIs agree with the frozen reference. Empty inputs agree and
  source triangles remain unchanged.
- Three permanent field-light checks verify grouped/single equivalence, section
  immutability and independence from selection order, plus mutation isolation
  between lower/upper outputs and later construction. Existing analytical skin
  position and sloped-face checks remain intact.
- Field/world lights: **75/75 headless**. Night kit: **30/30 headless and 30/30
  native**, including catalog placement, modes and wreck attachment. Home preview
  cache: **18/18 headless**. All retained final check logs are error/warning-free.

No full CI, export, native flight soak or visual pilot acceptance was performed.
The separate helicopter texture shutdown diagnostic is not closed by these tests.

## Reproduce

Runtime/test sources before and after, monitored source hashes, five native
JSON/log pairs and final check logs are retained here. The hash guard covers five
named paths, not the whole concurrently edited tree. A separate runner check is
retained under `runner-check/` and excluded from the table.

```text
python research/visual-quality/wing-light-slices/run.py --godot PATH_TO_GODOT --app app --out tmp/wing-light-slices-repro
godot --headless --audio-driver Dummy --path app --script res://tests/test_world_field_lights.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_night_kit.gd
godot --audio-driver Dummy --path app --script res://tests/test_night_kit.gd
godot --headless --audio-driver Dummy --path app --script res://tests/test_ui_home_preview_cache.gd
```

Use an imported project and a new output directory. The comparison requires a
native renderer. `--runs 1` checks the runner and output contract.
