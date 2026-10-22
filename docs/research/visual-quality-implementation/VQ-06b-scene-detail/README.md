# VQ-06b Scene detail preset

2026-10-22 · Visual quality **VQ-06b**, with landscape **L** (trees) and scenery **SC-24**. The owner asked for graphics options in tiers ("Extreme, a bunch of tree detail; High a lot; Medium less") so that the scene budget becomes a choice. Settings > Graphics gains **Scene detail**: Low, Medium, High (default) or Extreme.

## Research

Twelve web searches, 2026-10-22, before design:

| Finding | Consequence here | Source |
| --- | --- | --- |
| Godot has no built-in quality presets; projects define their own bundle and store it in `user://` | One preset in the existing `display.cfg` store, not a second preferences system | [Godot forum](https://forum.godotengine.org/t/graphic-settings-in-godot-3-1/24483), [3D Graphics Settings demo](https://godotengine.org/asset-library/asset/2738), [ConfigFile](https://docs.godotengine.org/en/4.2/classes/class_configfile.html) |
| `mesh_lod_threshold` is the per-viewport LOD knob; 1 px is "perceptually lossless", higher values switch sooner | High and Extreme keep 1 px; Medium 2 px, Low 4 px | [Mesh LOD](https://docs.godotengine.org/en/4.2/tutorials/3d/mesh_lod.html) |
| `lod_bias` is the per-node counterpart | The L6c-R1 world-unit LOD bias stays | same |
| Visibility-range "Self" fades force transparency; "Disabled" uses hysteresis | No fades added to foliage here | [Visibility ranges](https://docs.godotengine.org/en/4.5/tutorials/3d/visibility_ranges.html) |
| A MultiMesh is culled whole; lowering `visible_instance_count` drops the last instances | Tiers choose trees by rule, never by truncating counts | [Using MultiMesh](https://docs.godotengine.org/zh-tw/4.3/tutorials/performance/using_multimesh.html), [forum](https://ask.godotengine.org/140712/set-multimesh-visible-instance-count) |
| Compatibility has no automatic instancing | MultiMesh batches remain the structure | [Optimizing 3D performance](https://docs.godotengine.org/es/4.5/tutorials/performance/optimizing_3d_performance.html) |
| Commercial practice: choose a preset, then fine-tune; foliage and view distance are separate knobs | One preset now; per-option overrides later | [Train Sim World](https://support.dovetailgames.com/hc/en-us/articles/29719662434962-Train-Sim-World-Graphical-Settings-Guide), [PUBG](https://support.pubg.com/hc/en-us/articles/115004170033-What-do-all-the-graphic-settings-mean) |
| No Godot GPU auto-detection; Unreal benchmarks (`scalability auto`) | Default stays High; a first-launch benchmark is later work | [Tom Looman](https://www.tomlooman.com/auto-detect-graphics-settings-ue4) |
| Shadow atlas and filter quality cost frame time steeply | A later tier knob, not in this step | [Lights and shadows](https://docs.godotengine.org/en/4.1/tutorials/3d/lights_and_shadows.html) |

## Presets

`app/render/scene_detail.gd` maps the level onto existing knobs:

| Level | Scenery tier (SC-24) | 3D field trees (L8a-R1) | Viewport LOD threshold |
| --- | --- | --- | --- |
| Low | `low`: landmarks and standard props | none, all cards | 4 px |
| Medium | `balanced`: half the ornaments, a fixed seeded half | none, all cards | 2 px |
| **High** (default) | `high` | the 127 trees within ±60° of the runway | 1 px |
| Extreme | `high` | the whole near ring, 480 trees | 1 px |

Precedence: `--scene_detail=<level>` after `--`, then `OPENRC_SCENE_DETAIL`, then the saved choice, then High. An explicit `--scenery_quality` still wins for the scenery tier. The LOD threshold applies at once; trees and props follow at the next flight.

**Collision.** Field-tree collision ignores the preset: every preset collides with the High rule, so a tree is never added or removed from the simulation. Ornament props follow the existing LU-05 rule that what is drawn is what collides, as `--scenery_quality` already did; an invisible obstacle would be worse. The flight log stores the collision world, so replays stay exact.

**Settings.** One row on the Graphics page, with Spanish text. It previews and is kept like text size, without the 15-second display trial, because it cannot blank the screen. Restore graphics defaults returns it to High. To fit the page at 1080p without scrolling (UI-23-R4), the "High is a temporary experiment" note moved from its own label into the Try High button's tooltip.

## Cost per level

Scene budget at 1280×720, primitives counted per instance ([LU-34-R1](../../landscape-upgrade/LU-34/README.md#revision-lu-34-r1-instanced-lod-meshes-were-undercounted)), one run per level with `OPENRC_SCENE_DETAIL=<level> tools/scenery/budget.sh` ([summaries](budget/); High is the [L8a-R1 run](../L8a-R1/budget/summary-720.md)). [`fixtures/preset_cost_table.py`](fixtures/preset_cost_table.py) builds the table and fails if a run was taken at another level or a level draws more than the one above it:

| Level | Pilot worst view: primitives / draws | Ground worst view | Aerial worst view | Pilot median | 3D field trees, pilot worst |
| --- | ---: | ---: | ---: | ---: | ---: |
| Low | 756,608 / 297 | 811,001 / 327 | 551,768 / 335 | 405,042 | 0 |
| Medium | 856,360 / 333 | 904,675 / 362 | 636,113 / 372 | 435,348 | 0 |
| **High** | 1,295,621 / 350 | 1,058,511 / 369 | 774,886 / 374 | 816,151 | 379,224 |
| Extreme | 1,321,436 / 349 | 1,624,964 / 388 | 1,288,039 / 403 | 817,912 | 481,986 |

- **Medium to High is the big step** (pilot worst +51%, median +87%): the 3D front trees. Medium is the setting for weaker GPUs.
- **Low saves 12% more than Medium** in the pilot worst view, through fewer props and a 4 px LOD threshold. The gain is modest because that view is a 10° telephoto: club trees (43%) and people and cars (25%) stay at full detail even at 4 px, and the ground (11%) and fence (10%) have no LODs. The proposed [L6c-R2](../../../plans/tree-forest-quality.md#follow-ups-2026-10-21) bark LOD error for club trees targets the largest share.
- **Extreme adds 2% in pilot views,** which already face the front trees, but 54% in ground views and 66% from the air, where the whole ring of 480 trees is in view.
- Draw calls change little (297–403), so the levels differ in geometry, not in submissions.

The budget in `scene_budget.json` guards High; the other levels are measured and reported, not capped. llvmpipe counts are workload, not frame time.

### What each level shows

[`fixtures/preset_capture.gd`](fixtures/preset_capture.gd) renders the production world at each level with the preset applied as in the app ([views](fixtures/preset_views.json)); each image shows Low, Medium, High and Extreme.

| View | Four levels |
| --- | --- |
| Pilot, 50° north | ![](pilot-north.jpg) |
| Pilot, 20° north-west | ![](front-zoom20-nw.jpg) |
| Pilot, 50° east | ![](pilot-east.jpg) |
| Club, from the flight line | ![](club-south.jpg) |
| From 120 m | ![](aerial-120m.jpg) |

- Low drops people and ornament props, Medium a fixed seeded half of them (SC-24 tiers); landmarks, buildings, fences and tree positions stay.
- High turns the front woods 3D; Extreme also the side and rear woods (east view, aerial).
- From the air, the 3D woods read paler and bluer than the cards beside them. The proposed [L8a-R2](../../../plans/tree-forest-quality.md#follow-ups-2026-10-21) card colour match addresses this.

## Checks

`test_scene_detail.gd`: levels match the saved values; each level costs no less than the one below; precedence and fallback; the viewport threshold applies at once; save, reload, refusal and pre-existing files; the Settings row selects, keeps and restores; each level draws the expected 3D trees with all 1,680 positions; field-tree collision is identical across levels.

Mutations on a disposable copy, each caught: the field ignores the preset (Low, Medium and Extreme counts fail); the scenery ignores the preset; `apply` skips the LOD threshold; collision follows the preset.

Existing UI tests pass: `test_settings_ui` (pages fit at 1080p), `test_advanced_graphics_settings`, `test_ui_settings_integration`, `test_high_graphics_restart`, `test_ui_language`, `test_ui_pause`, `test_display_preferences`.

## Open

- Frame time on native hardware for each level (VQ-06's acceptance); llvmpipe counts are workload, not timing.
- Per-option overrides (trees, props, LOD) under the preset, and a first-launch recommendation.
- Shadow quality as a tier knob.
