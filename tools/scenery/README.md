# Scenery tools

Offline tools of the scenery track ([SCENERY-PLAN](../../docs/SCENERY-PLAN.md)). Layout and legacy JSON generators check committed output bytes with `--check`. The parked-aircraft checker validates resource contents, source identities, textures and ground contact. Placements use integer hashes rather than runtime RNG.

| Tool | What it does | Command |
| --- | --- | --- |
| `place.py` | Lays out the default field's scenery and writes `app/data/scenery/default.json` (`openrc-scenery v1`). Stdlib Python, integer hashes. It rebuilds the L6b treeline's tree heights and skyline so that landmarks go where the pilot can see them (`--report` prints the visibility table) | `python3 tools/scenery/place.py [--check] [--report]` |
| `bake_countryside.py` | LU-28 crop parcels, roads and yards; static spatial batches follow the existing visual horizon. Run after `place.py`. Layout is estimated and supplies no physical terrain or tire friction. | `python3 tools/scenery/bake_countryside.py [--check]` |
| `bake_models.gd` | Converts the third-party CC0 models (Quaternius cars, cow, sheep) into `openrc-scenery-model v1` JSON in `app/data/scenery/models/`. Checks each download's SHA-256, poses skinned meshes at their rest, puts the front to −Z, scales to the catalog size, reduces with meshoptimizer, and marks the car paint | `godot --headless --path app --script $PWD/tools/scenery/bake_models.gd -- --src=<downloads> [--check]` |
| `bake_parked_aircraft.gd` | Production parked fleet: snapshots five current aircraft and the Stik maintenance configuration, preserves authored materials and generates static mesh LODs plus matching collision metadata. Re-run after a source model changes. Requires a real renderer to retain texture image data. | `godot --rendering-driver opengl3 --path app --script $PWD/tools/scenery/bake_parked_aircraft.gd [-- --check]` |
| `bake_fleet.gd` | Legacy vertex-colour snapshots retained for model-format checks; the Club field uses the material-preserving resources above. | `godot --headless --path app --script $PWD/tools/scenery/bake_fleet.gd` |
| `scenario.sh` + `scenario_report.py` | The runway scenario (`app/scenery/runway_scenario.gd`, pilot in `takeoff_pilot.gd`): airplane at the threshold, scripted takeoff, five cameras × 12 instants, manifest, sync checks, comparison with the previous run (heatmaps, verdict), filmstrips, `report.html`, history timeline. Also run by `app/capture.sh` | `tools/scenery/scenario.sh [root] [-- --aircraft=<id> --scenery=off]` |
| `capture.sh` | Renders every view of `app/scenery/postcards.gd` with scenery off and twice on, then `check_views.py` checks per-view budgets (pilot views: ≤ +40 draws, ≤ +150 k primitives; 0 shadow-pass draws) and byte repeats | `tools/scenery/capture.sh [out-dir]` (needs `xvfb-run`) |
| `budget.sh` + `attribute_views.gd` + `attribution_report.py` | [LU-34](../../docs/research/landscape-upgrade/LU-34/README.md) scene budget: renders every postcard view at 1280×720, then again without each subsystem and without sun shadows, attributing drawn primitives and draw calls (shadow pass included) per subsystem. Godot's counter counts an instanced mesh with LODs once per draw, so each such MultiMesh in view is also measured alone and its primitives are counted per instance ([LU-34-R1](../../docs/research/landscape-upgrade/LU-34/README.md#revision-lu-34-r1-instanced-lod-meshes-were-undercounted)). It also records full-detail (no-LOD) meshes, shadow casters and renderer texture memory, and checks `scene_budget.json`. Source-triangle allowances per subsystem live in `app/tests/scene_source_budget.gd` | `tools/scenery/budget.sh [out-dir]` (about 40 min on llvmpipe); `OPENRC_SCENE_DETAIL=<level>` measures another Scene detail preset, which the budget (High) reports but does not cap |
| `landscape_metrics.py` | The landscape-improvement metrics on two capture folders (before, after): grass hue/saturation, far-band spread, pilot box, top-down repetition (three off-runway views), crown seam, front-lit vs backlit crowns ([evidence](../../docs/research/landscape-improvement-2026-10-07/implementation/README.md)) | `.tools/visual-venv/bin/python tools/scenery/landscape_metrics.py <before> <after>` |

**Downloads for `bake_models.gd`.** They are listed with their URLs in [assets/scenery/PROVENANCE.json](../../assets/scenery/PROVENANCE.json), and their SHA-256 values are in `app/scenery/models.gd`. They are never committed: only the baked derivatives are.

**The rest of the scenery is procedural:** buildings, people, trees, hedges, flowers and landmarks are built in `app/scenery/prefabs.gd` and `ground_features.gd`.

**Default:** scenery is on in normal Home and flight launches (SC-02a, owner's request, 2026-10-11). `app/run-landscape.sh` also forces it on if the environment disables it. Opt out with `OPENRC_SCENERY=off` (Home and flight) or `-- --scenery=off` on the direct route. CLI takes precedence over the environment. Evidence: [SC-02a](../../docs/research/scenery-implementation/SC-02a/README.md).

**Options:**
- `--scenery_theme=temperate|summer|autumn`
- `--scenery_quality=low|balanced|high`
- `--scenery_audio=off`
- `--scenery_birds=off` (birds are on by default since UI-06d)

Each option has an `OPENRC_SCENERY_*` environment-variable twin.

LU-28 checks: `python3 tools/scenery/test_countryside.py` verifies tree clearance,
road/driveway connections, farm gates, winding and protected flight-area geometry.
`res://tests/test_countryside.gd` checks the shared field integration and lighting.
Native views in `capture_landscape_upgrade.gd` include `plain_overview`,
`plain_east`, `plain_farm`, `plain_farm_gate`, `plain_village`, `plain_highway`
and `plain_crop`. [Captures, research and measured cost](../../docs/research/landscape-upgrade/LU-28/README.md).

SC-09-R1 parked placements use the existing `fleet` group with optional unit-tagged
`scale` (`1`, 0.25–1.5) and `elevation` (`m`, 0–1.5), plus `configuration`
(`assembled`, or `service` for the Ugly Stik). Heights are receiver tops above field
datum: grass 0, shelter slab 0.10, worktable 0.90, foam supports 1.12 m.
The same normalized placements drive the visible mesh and float64 collision inventory.
The legacy `collides: false` field keeps rendering nodes passive; it does not disable
the simulator contacts built separately by `collision_world.gd`.
Each generated mesh is static, shared between copies, and has no aircraft controller.
Copies are grouped by aircraft, configuration and shelter in eight MultiMesh batches.
Embedded textures use S3TC for the existing desktop export targets, with shared identical
image payloads and unchanged texture dimensions. Re-run the native resource checker after baking.
Grass and slab contact shadows follow sun updates; bench shadows are clipped to the worktop.
The generated JSON under `app/assets/scenery/aircraft/` must remain in all export filters.
Capture views `hangar_west`, `hangar_east`, `hangar_micro`, `hangar_bench` and
`hangar_service`, `hangar_ready` and `hangar_east_bench` are available through
`app/scenery/capture_views.gd`.
