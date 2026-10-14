# UI-05-R2 — fast return to recent aircraft previews

2026-10-14. Implemented in `app/ui/home_scene.gd`, with an optional precomputed-shape argument in `app/render/shadow.gd`. Regression: `app/tests/test_ui_home_preview_cache.gd`.

## Delivered behavior

Home retains **at most three visual models**, including the visible selection, in least-recently-used order. Returning to a retained aircraft reuses its model and neutral shadow geometry. Inactive models are hidden and processing-disabled; there is only one active projected shadow. Eviction removes the model and geometry, and freeing/replacing Home frees all retained models. Lighting changes and returning from Workshop already replace Home's backdrop, creating a fresh cache.

The shadow shape is captured before the night kit is attached, so repeated selection neither adds duplicate lights nor includes those fittings in the silhouette. Ordinary flight callers still collect their own geometry through the existing two-argument shadow API. Flight models/data are built and validated independently; this cache is exclusively a fixed Home presentation snapshot.

## Measured responsiveness

Native Windows, Godot 4.7.2 (`ed1daf0bf`), Compatibility, RTX 3090 / NVIDIA 610.88, 1280×720. The actual `AppRoot.set_aircraft` route updates the card, preview and saved selection. One native process runs five cycles of Stik → Extra → jet for each version; the first cycle is excluded. Each table cell is the median of four retained-model selections.

| Aircraft | Original selection handler | Cached selection handler | Original → cached, through rendered frame |
| --- | ---: | ---: | ---: |
| Stik | 371.91 ms | 4.87 ms | 387.89 → 13.22 ms |
| Extra | 211.77 ms | 5.88 ms | 225.44 → 13.10 ms |
| Ventage Jet | 1296.44 ms | 5.21 ms | 1357.16 → 12.44 ms |

Card and preview IDs match every requested selection. “Through rendered frame” ends at `RenderingServer.frame_post_draw`, not physical display presentation or input-device latency. This is a small local campaign, reference before candidate, on a shared development host; it is not a hardware support or FPS claim.

**First visits and evicted models still build synchronously.** In this campaign the candidate's first Extra/jet selections took 355/1415 ms. This repair specifically removes repeated construction when browsing back and forth; it does not solve cold loading or rapid traversal of the entire fleet.

The smaller preview-only campaign covers day/night and four warm cycles, with retained-model medians of approximately 3.3–3.9 ms. Its timing scope differs from the complete selector above. `benchmark.json` also records static-memory observations; these include engine/resource caches and are not isolated cache or VRAM measurements. The three-model scene had 563 nodes versus 345 with one model. The memory tradeoff is explicit and bounded by model count, not a byte budget.

## Verification

- Preview cache: **18/18 headless and native** on the fixed source; integrated headless also passes. Checks cover model identity/pose, disabled hidden models, three-entry bound, least-recently-used eviction, retained geometry versus a fresh model, airplane/helicopter transitions and freeing every retained root.
- Existing integrated projected-shadow regression: **37/37**; geometry collection: **77/77**; actual aircraft-selection/launch route: **46 checks pass**. This includes saved choices, keyboard selection, matching previews and matching flight models/physics.
- Six day/night native reference/candidate image pairs: Extra is pixel-identical; other pairs differ in **5–38 of 921600 pixels**. Reference self-rebuilds differ in 3–51 pixels in those cases. These small aircraft-region differences are retained and reported, not described as exact parity. The day jet capture was visually inspected; no broad image change is observed.
- One early integrated native regression logged four ObjectDB instances at shutdown. A verbose repeat was clean. The test now releases its measured mesh reference before teardown; the final native result and original warning are both retained. This is not a general production shutdown qualification.

The performance/visual campaign uses frozen commit `1da001f376b704da72e8c68b0c156a22869641ba`, plus the candidate, rather than a changing working tree. A live-tree attempt was discarded after concurrently edited aircraft data failed validation. `snapshot.json` and `sources.json` identify the accepted baseline; imported resources were copied from the local import cache, with source assets unchanged. Integrated checks separately exercise the working tree. No full `app/test.sh`, export, controller-hardware or whole-fleet soak acceptance is claimed.

## Evidence and reproduction

`selection.json` / `selection-run.json` contain complete-selector observations and commands. `benchmark.json` / `benchmark-run.json` contain preview-only timings, image results and memory observations. `pixel-comparison.json` includes self-repeat comparisons. PNGs, logs, compressed source/probe scripts and `runtime.patch` are hashed in `manifest.json`.

Use a checkout of the pinned commit, import with the pinned engine, and apply `runtime.patch`. Decompress `reference.gd.gz`, `candidate.gd.gz` and `bench.gd.gz` into a disposable directory outside `app/`. Run the engine with `--path app --audio-driver Dummy --resolution 1280x720 --script <bench.gd> -- <directory>`. The retained candidate uses the integrated shadow API; the external reference retains the original Home implementation. Run `res://tests/test_ui_home_preview_cache.gd` headless and native for the lifecycle regression. Timing runs must not deliberately overlap other Godot workloads.

## Next responsiveness work

1. Attribute the remaining **first-visit** model cost, including imported texture transcoding and presentation validation, before adopting another cache or loader.
2. Measure rapid full-fleet traversal and changes of time/conditions; consider coalescing obsolete preview requests only with explicit last-selection and immediate-Fly tests.
3. Keep synchronous correctness and bounded ownership. Do not move scene-tree/model construction blindly onto worker threads, preload the entire fleet during interaction, or disable aircraft validation for speed.

UI-22…29 theme/display work remains separate; this repair adds no animation or delay to mask the cost.
