# OPEN RC SIMULATOR — Triangle and Geometry Budget Audit

**My conclusion: we should improve how we measure and enforce geometry budgets before broadly increasing them.** The project already supports fairly detailed aircraft and has useful LOD controls. Its main weaknesses are that the limits serve different purposes, the principal scenery budget is based on an older 720p fixture, and hardware selection relies on GPU names rather than measured performance.

There is also a consequential finding: **changing Scene detail can change the scenery collision inventory in the next flight.** That needs to be considered when designing hardware presets.

I audited repository snapshot **[`f47d1dc6`](https://github.com/bultodepapas/OpenRCsimulator/tree/f47d1dc6cccb141936407d0217eafdc465558190)**. The project pins **Godot `4.8.beta2.official.cafc17a19`**. This review combines current source inspection, retained project benchmarks, and primary documentation. **I did not run a new hardware benchmark or change any game limits.** [Engine pin](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/get-godot.sh).

## 1. What limits we actually have

### Aircraft: there is no universal triangle ceiling

The aircraft pipeline uses individual asset policies and exact checks for accepted models.

| Aircraft | Full-detail triangles recorded or pinned in current source | Material surfaces | Current policy |
|---|---:|---:|---|
| **F4U Corsair g2.2** | **337,664** | **57** | Target 300,000–350,000; preflight rejects above **450,000** |
| **Vantage Jet / Avanti asset** | **146,652** | **105** | Exporter and compiler require **strictly fewer than 150,000** |
| **Turbo Lumber Evolution** | **42,519** | **49** | Exact accepted-asset regression checks; authoring guidance targets 30,000–50,000 |
| **MoonRunner X99** | **38,504** | **24** | Exact accepted-asset regression checks; no separate numeric maximum found in the inspected shared admission path |

These are current source records and assertions, rather than a fresh recount of loaded GPU resources. Sources: [Corsair verification](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/aircraft/verify_f4u.gd), [Avanti manifest](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/assets/aircraft/avanti-s-a200/source-manifest.json), [Timber verification](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/aircraft/verify_timber.gd), [MoonRunner verification](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/aircraft/verify_moonrunner_x99.gd).

Two practical observations follow:

- **The Corsair is already below its 350,000 target.** Increasing its 450,000 ceiling would provide permission for a future asset change; it would not improve the current model or frame rate.
- **The Avanti has fewer than half the Corsair’s triangles but almost twice as many surfaces.** That makes it a useful candidate for investigating material and draw submission cost. Triangle count alone cannot rank their rendering expense.

There is an enforcement distinction inside the Corsair preflight: exceeding the triangle ceiling is a **failure**, while exceeding its 70-surface or 16-material targets produces **warnings**. The `generic` profile does not apply the Corsair triangle budget. The Avanti’s `<150000` check exists independently in both its exporter and compiler. [Corsair preflight](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/research/f4u-corsair/F4U-04/preflight_glb.py), [Avanti exporter](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/assets/aircraft/avanti-s-a200/export_blender.py), [Avanti compiler](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/assets/aircraft/avanti-s-a200/compile_blender.py).

**Recommendation:** retain aircraft-specific budgets. A trainer, a detailed warbird, and a distant parked aircraft have different visual requirements.

### Scenery: the principal budget measures rendered workload

The current `scene_budget.json` contains these limits:

| View class | Maximum corrected rendered primitives | Maximum draw calls |
|---|---:|---:|
| Pilot | **1,307,000** | **360** |
| Ground | **1,062,000** | **395** |
| Aerial | **827,000** | **405** |

It also specifies:

- **160,000 source triangles** for the permitted real-time shadow casters.
- **495 MiB** for the renderer’s texture-memory estimate.
- A requirement to provide generated LODs or a recorded exception for relevant full-detail surfaces exceeding **5,000 triangles**.

These values belong to a **High-detail, 1280 × 720 development fixture**. They are not a global runtime switch that stops Godot drawing additional triangles. The budget tool measures the scene, compares the results, and reports failures. [Budget definition](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/tools/scenery/scene_budget.json), [budget checker](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/tools/scenery/attribution_report.py).

The units matter:

- The primitive totals include rendering work such as shadow passes.
- The 160,000 shadow allowance is a source-geometry inventory, not a per-frame shadow primitive cap.
- The texture figure is an estimate sampled after the first view, not measured peak GPU residency.
- Subsystem maxima can come from different camera views, so adding them together does not reconstruct one observed frame.

### Source geometry: separate subsystem allowances

The scenery tests additionally limit full-detail geometry before LOD:

| Subsystem | Source triangle allowance |
|---|---:|
| Population: people, cars, furniture | 380,000 |
| Parked aircraft | 350,000 |
| Procedural scenery cells | 175,000 |
| Imported vegetation | 150,000 |
| Botanical habitats | 90,000 |
| Pit shelters | 13,000 |
| Airfield detail | 5,000 |
| Other scenery | 8,000 |

The counting rule includes `MultiMesh instance count × mesh triangles`. This is useful as a content-growth indicator, but it is **not an exact memory calculation**: instances can share mesh buffers. These allowances also cover a particular scenery subtree, not every object in the complete flight. [Source allowances](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/tests/scene_source_budget.gd).

### Some components do have runtime rejection limits

These checks affect construction of individual scenery components:

| Component | Limit | Behavior when exceeded |
|---|---:|---|
| Downloaded near grass | **50,000 source triangles** | Reports an error and returns an empty layout |
| Runway meadow | **160,000 source triangles** | Reports an error and returns an empty layout |
| Countryside | **14,000 source triangles** | Rejects excessive or inconsistent source data |
| Woodland-edge habitat | **472 triangles** | Rejects excessive generated geometry |

Sources: [near grass](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/imported_near_grass.gd), [meadow](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/runway_meadow.gd), [countryside](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/landscape_upgrade/countryside.gd), [woodland edges](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/woodland_edge_habitat.gd).

Lowering these constants indiscriminately can therefore make an entire component disappear. They are admission checks, not progressive quality controls.

Other constants, including botanical and hedge allowances, are recorded as metadata and checked by tests. A constant named “budget” does not, by itself, establish runtime enforcement.

### The proposed 200,000-triangle importer limit is a different policy

The retained Aircraft Creator plan proposes **200,000 instantiated triangles and 600,000 expanded vertices**, together with file-size, image, memory, and concurrency limits. It explicitly labels these as development ceilings awaiting qualification.

I did not find that proposed general-purpose importer enforcement in the audited production paths. It should not be presented as today’s global aircraft limit—or retroactively applied to the approved Corsair. [Aircraft Creator plan, §7.2](https://chatgpt.com/library?file_id=libfile_fde3_f-093ff2da9de48191914938f8127899d9_ac5d15b10f548191b3cb750779cf7c10&account_id=personal).

## 2. The most important audit findings

### Finding 1 — Our main scenery gate does not qualify the complete flight at 1080p

The attribution fixture builds the default world and its own camera. **It does not add the active aircraft or run the complete flight session.** Its runner requests OpenGL3 at 720p, while the repository identifies **1920 × 1080 as the primary acceptance resolution**. [Fixture](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/tools/scenery/attribute_views.gd), [runner](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/tools/scenery/budget.sh), [resolution policy](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/AGENTS.md).

That fixture remains useful for detecting scenery growth. It cannot establish the cost of:

- The selected aircraft and its moving parts.
- The complete simulation and presentation loop.
- Other landscapes and activity configurations.
- Native Metal or Forward+ execution.
- The current 1080p player experience.

**My recommendation:** preserve this scenery diagnostic and add a separate complete-flight budget at 1080p. Give each a clear scope rather than silently treating the existing fixture as a whole-game performance gate.

### Finding 2 — The budget already records unresolved excess

The budget’s own explanatory text records a November 3 measurement of **1,362,894 pilot primitives and 362 draws before the meadow**, against limits of **1,307,000 and 360**. It says an allocation or matching reduction remained necessary.

That is **retained historical evidence**, not a new measurement from this audit. Nevertheless, it shows that exceeding the policy was already known. Raising the JSON values would acknowledge a larger allowance; it would not make that workload cheaper. [Recorded budget basis](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/tools/scenery/scene_budget.json).

A revised budget needs an explicit decision: accept the cost on qualified hardware, reduce another subsystem, or move the additional content to a higher preset.

### Finding 3 — Scene detail affects some collision obstacles

This is the most consequential behavioral finding.

`SceneDetail` supplies the default scenery tier. `CollisionSetup` then filters ornament placements using that tier before creating collision proxies. The tests explicitly expect different collision-world identities and retained proxy IDs for High and Low.

Field-tree collision is deliberately retained across presets, but some decorative props follow the rule that the visible placement also determines whether it collides. [Scenery options and filtering](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/scenery.gd), [collision construction](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/collision_setup.gd), [collision tests](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/tests/test_landscape_collision_setup.gd).

The solver equations and 240 Hz timestep do not change, but **the environment encountered by the aircraft can change**. Because Automatic chooses different detail levels for different GPUs, this can also become a hardware-dependent world difference.

The existing design avoids invisible decorative obstacles. For future scaling, I recommend separating:

1. **World and collision content**, fixed for the session.
2. **Visual representation**, which can become simpler while retaining a visible representation of collidable objects.

Until then, a performance comparison must record the collision-world identity as well as the graphics settings.

### Finding 4 — Primitive counters require careful interpretation

The project already compensates for an instanced-LOD counting problem. The correction uses measured contributions from individual `MultiMesh` nodes rather than assuming the raw counter includes every instance.

Inspection of the pinned Godot source supports the concern: the inspected LOD counter branches omit the instance multiplication present in their non-LOD branches. These are source-level observations, not a new renderer experiment. [Pinned Compatibility implementation](https://github.com/godotengine/godot/blob/cafc17a19/drivers/gles3/rasterizer_scene_gles3.cpp), [pinned Forward+ implementation](https://github.com/godotengine/godot/blob/cafc17a19/servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp).

There are two remaining reporting risks:

- Total and subsystem primitives are corrected, while the sun-shadow primitive column uses raw counters.
- The checker validates resolution, preset, format, and view coverage, but does not bind acceptance to the recorded engine, renderer, adapter, and scene identities.

**Keep raw counters and corrected estimates as separately named metrics.** Revalidate the correction on each supported renderer and after engine upgrades. Do not divide an already converted primitive count by three again. [Correction and validation logic](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/tools/scenery/attribution_report.py).

### Finding 5 — We have known geometry that does not respond usefully to automatic LOD

The budget records full-detail exceptions for several meshes, including procedural scenery, barriers, lake geometry, some vegetation surfaces, and parked aircraft surfaces.

Increasing the viewport LOD threshold cannot simplify a surface that has no usable LOD chain. This limits how much Low can save and explains why “turn down model detail” may produce a smaller improvement than expected. [Recorded exceptions](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/tools/scenery/scene_budget.json).

## 3. How triangle limits affect performance

We need to track several quantities independently:

| Quantity | What it tells us |
|---|---|
| Source triangles | Asset complexity and a useful authoring constraint |
| Imported vertices | Vertex processing and buffer requirements, including duplicated vertices |
| Surfaces and materials | Potential draw submission and state-change cost |
| Submitted primitives | Geometry workload after LOD/culling, including applicable passes |
| Shaded pixels and overdraw | Fragment-shader, transparency, and bandwidth pressure |
| CPU and GPU frame times | Whether the complete workload meets its performance target |
| Memory and loading time | Whether the content remains practical to load and retain |

Godot’s optimization guidance explicitly distinguishes CPU submission, GPU geometry, pixel shading, and material costs. Reducing polygons helps when geometry is a limiting factor; it can have little effect when the expensive work lies elsewhere. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html?utm_source=chatgpt.com)

For OPEN RC, the practical consequences are:

**More triangles can improve close views.** Wing leading edges, canopy outlines, wheels, cowl curvature, and visible mechanisms can justify geometry. Rivets or hidden mechanisms often provide less value.

**More triangles do not guarantee better appearance.** Normals, winding, shading, UVs, and simplification quality matter. Our historical Corsair study found that an inside-out fuselage was a major visual defect independent of its triangle budget. That was a historical defect subsequently addressed, not a claim about the current aircraft. [Corsair detail study](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/f4u-corsair/F4U-18/README.md).

**LOD reduces drawn work without necessarily reducing resident memory proportionally.** Simplified index buffers can continue referencing the original vertices. Loading a detailed asset and displaying a low LOD are separate costs. [meshoptimizer.org](https://meshoptimizer.org/?utm_source=chatgpt.com)

**A distant aircraft is not automatically cheap.** RC cameras can use strong zoom. Screen-space LOD responds to field of view and viewport resolution, so a distant object under telephoto magnification may legitimately retain detail. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html?utm_source=chatgpt.com)

**A rendering overload can affect simulation responsiveness without changing the flight equations.** The project runs at 240 Hz with up to 12 catch-up physics steps per frame. Sustained operation below approximately 20 rendered frames per second exceeds that configured catch-up capacity. Geometry optimization must preserve the simulation contract while recovering frame-time headroom. [Current physics configuration](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/project.godot).

### Our own Corsair measurements are particularly instructive

The retained October 24 study used **Godot 4.7.2 Compatibility, 1080p, an RTX 3090, and a Ryzen 9 5900X**. It rendered an isolated aircraft benchmark:

| Variant | Source triangles | Surfaces | Recorded close-view frame time |
|---|---:|---:|---:|
| g1.21 game asset | 99,729 | 57 | 0.82–0.85 ms |
| Derived ×6 variant | 449,809 | 53 | 0.81–0.85 ms |
| R59 merged by material | 5,658,772 | 97 | 0.98–1.31 ms |
| R59 as authored | 5,658,772 | 5,723 | 15.0–20.0 ms |

These are historical benchmark results, not current whole-game performance. Batching and generated LOD also affect the actual submitted workload, so equal source triangles do not mean equal rendered work. [Benchmark method and results](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/f4u-corsair/F4U-18/README.md).

The useful conclusion is that **object/surface organization and LOD were decisive on that machine**. It does not establish that millions of triangles are affordable on an M1 Air or an older integrated GPU.

The later g2.1 benchmark also recorded higher loading and memory costs despite similar short frame times: approximately **1.25 seconds and 247 MB reported video memory**, versus **0.61 seconds and 161 MB** for g1.24 in that run. Those figures describe the benchmark’s reported totals, not isolated mesh-buffer allocations. [g2.1 benchmark](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/f4u-corsair/F4U-19/checks/bench-g2_1-timing-1080p.md).

## 4. What expert projects and engine authors recommend

| Primary source | Relevant guidance | Application to OPEN RC |
|---|---|---|
| **Godot** | Reduce unnecessary draw submission, use LOD, and investigate the actual bottleneck. | Track surfaces, passes, CPU time, and GPU time alongside triangles. |
| **Google / Arm geometry guidance** | Budgets depend on the device and simultaneous content. Spend geometry on silhouettes and foreground objects; avoid dense tiny triangles. | Preserve aircraft recognition and attitude readability; simplify detail that contributes little at flight distance. |
| **Epic’s UE4.27 mobile guide** | Its often-quoted 500,000-triangle figure is tied to 30 FPS on iPad 4/iPad Air, with a separate 700-draw guideline. | Treat published numbers as examples of hardware-specific qualification. |
| **Terrain3D** | Its performance guidance emphasizes texture configuration, foliage, LOD, and shadow cost. | Large flight environments need texture, vegetation, and shadow budgets as well as geometry budgets. |
| **meshoptimizer** | Simplification is constrained by error, topology, and attribute seams. A requested reduction ratio is not guaranteed. | Inspect the generated LOD chain and its appearance rather than assuming a checkbox produced sufficient reduction. |

Sources: Godot [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/performance/optimizing_3d_performance.html?utm_source=chatgpt.com); Google/Arm [developer.android.com](https://developer.android.com/games/optimize/geometry?hl=en\&utm_source=chatgpt.com); Epic [Epic Developer Community](https://dev.epicgames.com/documentation/unreal-engine/performance-guidelines-for-mobile-devices?application_version=4.27\&utm_source=chatgpt.com); Terrain3D [Terrain3D 1.2.0 documentation](https://terrain3d.readthedocs.io/en/latest/docs/performance.html?utm_source=chatgpt.com); meshoptimizer [meshoptimizer.org](https://meshoptimizer.org/?utm_source=chatgpt.com).

Terrain3D’s named controls belong to that plugin; they are comparative guidance, not settings I found in our terrain implementation.

There are also genuine engine structure limits that should not be confused with performance budgets. Godot documents **256 surfaces per mesh** and a Compatibility setting of **65,536 renderable elements**, where elements refer to mesh surfaces. Neither is a “maximum triangles per aircraft” setting. Increasing those limits would not address the budget problems identified here. [docs.godotengine.org](https://docs.godotengine.org/es/4.x/classes/class_renderingserver.html?utm_source=chatgpt.com)

## 5. How to configure or change the current limits

### Start with the existing Scene detail profiles

The project already implements:

| Scene detail | Scenery tier | Detailed field-tree coverage | Viewport LOD threshold |
|---|---|---|---:|
| **Low** | Low | Cards instead of the detailed field-tree ring | **4 px** |
| **Medium** | Balanced | Cards instead of the detailed field-tree ring | **2 px** |
| **High** | High | Detailed trees within a ±60° sector | **1 px** |
| **Extreme** | High | Entire nearby ring, ±180° | **1 px** |

Defined in [`app/render/scene_detail.gd`](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/scene_detail.gd).

**High and Extreme use the same automatic mesh LOD threshold.** Extreme primarily expands detailed tree coverage. It is therefore quite possible for the difference to be modest from the pilot position and much larger from an aerial or ground camera.

The control is **Settings → Graphics → Scene detail**. Override precedence is:

1. `--scene_detail=<level>` after the engine’s `--`.
2. `OPENRC_SCENE_DETAIL`.
3. Saved preference.
4. Default behavior.

The LOD threshold updates immediately; scenery and tree population changes apply when the world is rebuilt. The saved setting resides in `user://display.cfg`. Explicit lower-level scenery overrides can take precedence over the preset’s scenery tier. [Preference implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/app_state/display_preferences.gd), [scenery overrides](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/scenery.gd).

For a developer launch from the repository root:

```bash
OPENRC_AUDIT_GODOT="$(./app/get-godot.sh)"
"$OPENRC_AUDIT_GODOT" --path app --resolution 1920x1080 -- --scene_detail=medium
```

### “High graphics” and “High scene detail” are separate choices

The High graphics profile selects Forward+ and enables associated presentation features. Scene detail controls scenery selection and LOD.

Standard currently resolves to Compatibility on the usual x86 desktop paths, with an ARM64 override to Mobile for the Apple Silicon package. Changing the graphics renderer requires startup/restart handling; changing the Scene detail profile is a separate operation. [Project renderer settings](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/project.godot), [High graphics implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/high_graphics_profile.gd).

For comparisons, record **both** settings and the actual renderer selected.

### Use the correct Godot LOD controls

| Control | Effect |
|---|---|
| Import: `meshes/generate_lods` | Creates LOD data for supported imported geometry |
| Runtime: `Viewport.mesh_lod_threshold` | Higher values select reduced detail more aggressively |
| Per object: `GeometryInstance3D.lod_bias` | Values above 1 retain more detail farther away |
| Visibility ranges / HLOD | Can replace groups with simpler distant representations |
| `ReflectionProbe.mesh_lod_threshold` | Controls detail used by probe rendering separately |

Each viewport has its own threshold. Setting the threshold to zero disables automatic mesh LOD; it does not request the cheapest level. Runtime meshes need LOD data for these controls to have an effect. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html?utm_source=chatgpt.com)

The Corsair already imports with `meshes/generate_lods=true` and `meshes/create_shadow_meshes=true`. The next useful check is the actual LOD distribution and visual result, not simply enabling those options again. [Corsair import settings](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/assets/aircraft/f4u-corsair-250/f4u_corsair.glb.import).

HLOD can additionally reduce draw calls by replacing several distant objects with one representation. Spatially partitioned MultiMeshes help avoid submitting a large distribution merely because part of its combined bounds remains visible. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/3d/visibility_ranges.html?utm_source=chatgpt.com)

### Where a developer should change each policy

| Intended change | Owning location |
|---|---|
| Change Low/Medium/High/Extreme behavior | `app/render/scene_detail.gd`, `PROFILES` |
| Change Automatic’s GPU classification | `app/render/scene_detail.gd`, `recommend()` |
| Change Corsair preflight ceiling | `research/f4u-corsair/F4U-04/preflight_glb.py`, `BUDGETS` |
| Change Avanti ceiling | Both `assets/aircraft/avanti-s-a200/export_blender.py` and `compile_blender.py` |
| Change per-view scenery allowances | `tools/scenery/scene_budget.json` |
| Change source-geometry test allowances | `app/tests/scene_source_budget.gd` |
| Change near-grass or meadow admission | Their respective scenery builders and corresponding validation expectations |
| Change an aircraft’s actual geometry | Its owning source/export pipeline, followed by regeneration and validation |

These are different operations. Raising a checker threshold changes acceptance policy. Changing LOD selection changes rendered detail. Increasing source geometry changes the asset.

Generated aircraft data and identity manifests must be regenerated through their owning pipelines. Imported assets and sidecars are hash-bound; a manual edit can invalidate that identity chain. [Aircraft contract](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/AIRCRAFT_CONTRACT.md).

## 6. How the policy should differ across hardware

### What Automatic does today

Automatic classifies GPU name/vendor strings:

| Detected category | Current automatic Scene detail |
|---|---|
| Software rasterizers | Low |
| Adreno, Mali, PowerVR, Tegra markers | Low |
| Entry/older GeForce markers | Medium |
| Recognized dedicated GeForce/RTX, Radeon RX, Intel Arc, etc. | High |
| Recognized integrated Intel/Radeon and Apple M-series | Medium |
| Unknown GPU or no reported GPU | High |
| Extreme | Never selected automatically |

This is a startup heuristic. It does not measure frame time, memory headroom, resolution, power mode, or sustained temperature. [Detection rules](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/scene_detail.gd).

Consequently, very different Apple M-series configurations enter the same category, and a broad discrete-GPU name can select High without demonstrating that the full scene meets the target.

### My recommended qualification matrix

These are **starting configurations to test**, not certified hardware capacities:

| Hardware class | Starting point | Main qualification concern |
|---|---|---|
| Older integrated graphics | Low or Medium; existing Standard renderer | Submission cost, shared memory, vegetation and pixel shading |
| Base Apple Silicon, especially constrained-memory machines | Medium with the existing Mobile/Metal path | Sustained complete-flight performance and memory pressure |
| More capable Apple Silicon configurations | Start from the existing Medium default; qualify High explicitly | Actual output resolution and renderer-specific behavior |
| Entry or midrange discrete GPU | Compare Medium and High at 1080p | GPU model variation, shadows, materials and full-scene cost |
| High-end discrete GPU | High; evaluate Extreme in ground and aerial views | Worst-view density, CPU submission and higher-resolution cost |
| Unknown hardware | Prefer a conservative initial choice with a user override | Current High fallback may be too optimistic |

Godot’s own guidance emphasizes that bottlenecks and relative optimization benefits vary by hardware, so measurements should cover multiple devices. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/performance/general_optimization.html?utm_source=chatgpt.com)

I would replace broad name matching gradually with **named, measured device profiles**, retaining user overrides. A first-run benchmark can help, but it should exercise representative flight views rather than a simple empty scene.

### Resolution must be part of the profile

By pixel count:

- 1080p contains **2.25×** as many pixels as 720p.
- 1440p contains approximately **1.78×** as many pixels as 1080p.
- 4K contains **4×** as many pixels as 1080p.

Those ratios do not predict frame time directly. They explain why a 720p pass cannot establish 1080p performance, and why rendering scale can help a pixel-heavy workload without proportionally reducing all other costs.

Follow the project’s established priority: **1080p first, higher resolutions next, 720p as a fallback**. Hardware budgets should identify output resolution, internal rendering scale, renderer, antialiasing, and shadow settings.

For a 60 Hz target, one frame has approximately **16.67 ms**. At 120 Hz it has **8.33 ms**. The same triangle count can fit one target and miss the other.

## 7. What I would change first

### Priority 1 — Establish a complete-flight 1080p baseline

Use the existing tools rather than introducing another overlapping framework. The debug bridge already exposes `frames`, `render`, `layers`, and `ablate`; the frame-diagnosis path also exists. [Debug tools](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/tools/debug/README.md), [frame diagnosis](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/tools/graphics.md).

The minimum useful workload should cover:

- Pilot view with ordinary and strong zoom.
- Close-up aircraft and gear views.
- Low flight over dense vegetation.
- Aerial views exposing the detailed tree ring.
- Club/pits/parked aircraft.
- Representative lighting, shadows, and effects.

Use the Corsair, Avanti, and a simpler aircraft so geometry and surface count vary independently. Record source and engine revisions, actual renderer, device, viewport, settings, and collision-world identity.

Report median, p95, p99, worst hitches, loading time, and memory. Run an uncapped comparison to expose headroom, followed by a normal presentation test.

The current debug bridge explicitly treats GPU timestamps as potentially delayed and unverified. Its raw readings are useful diagnostic context, but they should not alone establish a GPU bottleneck or claimed percentage saving.

### Priority 2 — Make budget meanings and enforcement consistent

Retain separate fields for:

- Authoring target.
- Hard admission ceiling.
- Exact accepted-asset count.
- Per-view rendered workload.
- Memory/loading constraints.
- Hardware qualification result.

Give them versioned ownership and a reason for each exception. Keep the existing subsystem structure; the problem is ambiguity and coverage, not a lack of constants.

### Priority 3 — Spend geometry where it improves the simulator

My immediate recommendations are:

- **Keep the Corsair’s 450,000 ceiling** pending new evidence. Its current model is below the target.
- **Inspect Avanti’s 105 surfaces** before granting a larger triangle budget.
- **Address high-cost no-LOD exceptions** using measured views.
- **Improve distant parked aircraft and grouped scenery representations** where draw calls remain high.
- **Preserve aircraft silhouette, control-surface identity, and attitude readability** during simplification.
- **Separate visual scaling from collision-world selection** before introducing dynamic automatic preset changes.

### Priority 4 — Raise a limit only with an identified benefit and measured cost

A useful limit-change request should answer:

1. What visible defect or missing feature requires additional geometry?
2. How many source triangles, imported vertices, and surfaces are added?
3. What happens to the actual LOD chain?
4. What changes in the complete flight on the weakest supported target?
5. What happens to loading, memory, shadows, and frame-time tails?
6. Are collision, articulation, and replay identities preserved or deliberately revised?

**The audit supports keeping detailed aircraft while making scenery and hardware qualification more rigorous.** The strongest next investment is a current 1080p complete-flight baseline, followed by targeted work on surface count, ineffective LODs, and scenery cost.

Verification completed here was source inspection plus **five passing synthetic tests for the attribution-report logic**. Those tests support the report arithmetic; they do not qualify a GPU or establish a new safe triangle ceiling.
## Second-pass findings: where the next improvements should come from

The deeper audit points to **three priorities: preserving LODs through runtime mesh modifications, reducing the aircraft’s projected-shadow geometry, and improving the parked fleet’s distant representations.** These are concrete opportunities in the current implementation.

I also found a compatibility constraint that matters before changing the aircraft pipeline: **some custom-paint identities include hashes of the source code itself.** A visually equivalent optimization can therefore invalidate existing paint files unless compatibility is handled deliberately.

This pass inspected the same current repository commit, [`f47d1dc6`](https://github.com/bultodepapas/OpenRCsimulator/tree/f47d1dc6cccb141936407d0217eafdc465558190), checked relevant behavior against Godot’s pinned `cafc17a19` source, and reviewed earlier experiments to avoid recommending work already completed or rejected. The findings below are source and retained-evidence findings; I have not run new GPU benchmarks or changed production code.

### Priorities at a glance

| Priority | Opportunity | Evidence strength | Main potential benefit |
|---|---|---|---|
| **1** | Preserve imported LODs through Turbo Lumber’s visual repair | Confirmed code path; actual affected LOD counts need runtime inspection | Restore distance-based geometry reduction |
| **2** | Give the flying aircraft a simpler projected-shadow proxy | Confirmed full-detail collection path; existing measurements establish the workload | Reduce shadow redraw cost during maneuvers |
| **3** | Improve parked Stik and Avanti distant representations | Checked-in geometry and surface counts | Reduce distant geometry and material submissions |
| **4** | Qualify shadow allocations independently of scene detail | Current settings are explicit and substantially different | Reduce shadow memory, bandwidth, and rendering cost |
| **5** | Extend foliage filtering and batching experiments selectively | Existing successful and rejected experiments provide a useful baseline | Improve distant stability and efficiency |
| **6** | Reduce unnecessary custom-paint vertex expansion | Confirmed mechanism, but narrower applicability than it initially appeared | Reduce vertex storage and processing for eligible surfaces |

These priorities reflect the specificity of the evidence and the size of the implementation boundary. They are not measured rankings of FPS gains.

---

## 1. Turbo Lumber can lose its imported LODs during visual repair

This is the strongest newly identified pipeline issue.

### What the current code does

Turbo Lumber’s import settings request generated mesh LODs and shadow meshes. During the normal aircraft construction path, the application then runs `TimberVisualDetails.apply()`—before the custom-livery branch.

When its paint-seam repair modifies a mesh, it creates a new `ArrayMesh` and rebuilds its surfaces. Those calls to `add_surface_from_arrays()` do not pass the original LOD dictionaries. The cached reconstruction path does the same.

Consequently, **any imported LODs on those rebuilt surfaces are discarded**, including on surfaces whose base geometry was copied unchanged. The replacement mesh also does not carry over an original `shadow_mesh`.

Sources: [normal aircraft construction](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/airplane.gd#L173), [visual repair](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/aircraft/timber_visual_details.gd#L204), and [cached reconstruction](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/aircraft/timber_visual_details.gd#L330).

This matters because Godot’s LOD data is supplied separately from the base vertex arrays. Copying `surface_get_arrays()` does not copy that data automatically. The API’s LOD argument defaults to an empty dictionary. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html?utm_source=chatgpt.com)

### How it can affect the simulator

The import configuration can say “Generate LODs: enabled,” while the mesh actually used in flight no longer contains them.

That creates a gap in the current audit approach:

- Source triangle counts can remain correct.
- The aircraft can look correct up close.
- Paint-repair tests can pass.
- Distance-based reduction can still have disappeared downstream.

The qualification is important: an enabled importer option does not prove that every input surface received useful generated LODs. We need to inspect the imported and final runtime resources to quantify the affected geometry. The loss mechanism itself is clear from the code.

### The improvement I recommend

Start with **preserving LODs on unchanged surfaces**. That is the smallest useful boundary.

For surfaces that are split across materials or have their normals modified, the repair needs a separate treatment. Copying the original indices blindly would be incorrect because the destination surfaces and vertex indexing have changed. Those LODs need valid remapping or regeneration.

The cache must evolve with the change. Its current content hash covers the base arrays, but not the LOD data. Once the cache retains LODs, its identity must distinguish meshes with different LOD contents and relevant formats. Otherwise, a cached reconstruction could return the wrong representation. [Cache implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/aircraft/timber_visual_details.gd#L258).

**Acceptance should compare the imported mesh with the final repaired mesh**, on both the first build and a cache hit. The existing procedural-skin test compares LOD geometry after this repair, so it cannot by itself detect a loss that already happened earlier.

### A compatibility requirement before implementation

The paint identity includes the procedural adapter’s source hash. For Lumber, it additionally includes the visual-details source hash.

Changing those files can make the paint template fail its identity check. Updating the current kit’s hash alone would not make previously created `.orskin` archives match.

A safe change therefore needs an explicit compatibility decision, backed by geometry/UV evidence and rejection tests for genuinely incompatible skins. The existing strict validation should remain meaningful. Sources: [paint identity construction](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/aircraft/procedural_skin.gd#L57) and [stock-template validation](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/aircraft/custom_skin.gd#L245).

---

## 2. The projected aircraft shadow still deserves its own geometry budget

The project already made a valuable optimization here: it reuses a previously rendered shadow mask until attitude, light direction, or blur changes sufficiently.

The remaining opportunity is **the geometry rendered when a redraw is necessary**.

### What is rendered today

`Projected.collect()` gathers the visible, non-propeller aircraft meshes using `get_faces()`, expands their full-detail triangles into a merged, non-indexed mesh, and submits that mesh to a **256×256 viewport with 4× MSAA**.

This custom path does not acquire a coarse representation merely because the imported aircraft has automatic LODs or an optimized shadow mesh. [Projected-shadow implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/projected_shadow.gd#L35).

The retained November 6 development evidence makes the maneuver dependence clear:

| Flight condition | Frames that redrew the mask |
|---|---:|
| Hands-off flight | 2.3% |
| Gentle climbing turn | 3.9% |
| Active roll | 85.5% |

Those are historical observations from the documented RTX 3090 campaign, not new measurements. They show why steady-flight averages can conceal a substantially different workload during aerobatics. [Recorded fix and measurements](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/game-findings-debug-tooling-2026-11-06.md#fix-log-pt1h-r12).

### The next improvement

Create an optional, separately validated **silhouette proxy for the flying-aircraft cue**.

Its geometric requirements should come from what the mask and its blur can actually resolve. Preserve the wing outline, tail, wheels, meaningful gaps, and low-sun silhouette; remove internal structure and detail that cannot change the resulting shadow meaningfully.

Keep the existing attitude cache. The two optimizations address different costs:

- The cache reduces how often the mask is rendered.
- The proxy reduces the work required for each render.

I would start with one aircraft, using the existing source pipeline and retaining the current collection path as a fallback.

### A Godot distinction that prevents a bad implementation

`ArrayMesh.shadow_mesh` is intended for a representation with fused vertices and reduced vertex attributes while retaining the required positions. It is not a general slot for an arbitrarily decimated silhouette. Godot explicitly requires matching vertex positions, including relevant LOD positions. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/classes/class_arraymesh.html?utm_source=chatgpt.com)

The separate projected-mask path is a more appropriate place for this experiment.

The validation views should include low-altitude takeoff and landing, banked flight, knife-edge attitudes, low sun, and rapid rolls. A proxy that looks acceptable directly from above can still lose an important wing or landing-gear contour at an oblique light angle.

---

## 3. The parked fleet contains a particularly clear optimization target

I extracted the current checked-in metadata for the assembled parked-aircraft assets.

These are **parked representations**, not the flying models from the first audit. They describe the stored assets before optional runtime quality-dependent merging.

| Parked aircraft | Near triangles | Last stored LOD triangles | Geometry retained | Stored surfaces |
|---|---:|---:|---:|---:|
| **Ugly Stik** | 21,178 | 19,228 | **90.8%** | **39** |
| **Avanti** | 20,474 | 10,094 | **49.3%** | **24** |
| Turbo Lumber | 17,902 | 3,214 | 18.0% | 16 |
| P-51 | 29,683 | 2,863 | 9.6% | 29 |
| Extra 300S | 19,470 | 1,604 | 8.2% | 15 |

Source: [parked-aircraft metadata](https://github.com/bultodepapas/OpenRCsimulator/tree/f47d1dc6cccb141936407d0217eafdc465558190/app/assets/scenery/aircraft). Retention percentages are calculated from those records; they are not frame-time measurements.

### Why the Stik stands out

Its last stored LOD retains almost all of the near representation’s triangles. The available distant geometry reduction is therefore limited, even when the engine selects that level.

The Avanti is a second candidate: its last stored level still retains about half its near triangles.

There is also a separate submission issue. **Changing an index LOD does not merge material surfaces.** An object can become much cheaper geometrically while retaining many surface submissions.

### What is already optimized

The current implementation already:

- Shares parked mesh resources.
- Uses MultiMeshes for repeated aircraft.
- Separates east and west shelter batches for independent culling.
- Disables their native engine shadow casting.
- Merges selected Stik engine-detail materials below the High scenery tier.

Those decisions are visible in the [fleet batching](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/scenery.gd#L705) and [parked-aircraft adapter](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/parked_aircraft.gd#L31).

The improvement should build on that structure.

### The experiment I would prioritize

Give one parked model a **distant representation with fewer surfaces as well as fewer triangles**, preserving its close representation.

The Stik is the first candidate. Identify which surfaces resist useful simplification, then determine whether distant engine details can be represented with fewer materials and simpler geometry.

Keep the shelter groups separate. Combining the entire fleet into one batch would sacrifice useful culling.

This is also where Godot’s importer behavior explains why changing a global threshold may disappoint. In the pinned source, simplification preserves material boundaries, considers attribute compatibility, and stops when it cannot achieve sufficient reduction. A larger LOD threshold cannot select a coarse level that the asset pipeline never produced. [Pinned LOD generation](https://github.com/godotengine/godot/blob/cafc17a19/scene/resources/3d/importer_mesh.cpp#L650).

For the active aircraft, distant geometry must preserve attitude cues. Parked aircraft can have a different policy, provided their identity, ground contact, and visible obstacles remain clear.

---

## 4. Foliage needs separate decisions for geometry, batching, and filtering

The deeper review confirmed that several apparent “inefficiencies” are intentional protections against visual degradation.

### A. Smaller MultiMesh cells are not automatically better

Godot selects one LOD for the instances in a MultiMesh using the nearest point of the whole batch’s bounding box. Individual instances also cannot be culled independently. This makes spatial grouping important. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html?utm_source=chatgpt.com)

OpenRC already uses different policies:

- Close club vegetation defaults to unsplit groups.
- Field-detail trees use 256 m cells.

Earlier project experiments support keeping those populations separate:

- Splitting the compact close-tree population increased one car-park view from **84 to 88 draws**, with a small increase in reported primitives.
- A different field-tree experiment found that **128 m cells saved about 5% of tree primitives** in one zoomed view, while adding six draws.

Those are different historical workloads, not contradictory results. Sources: [close-tree experiment](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/visual-quality-implementation/L6a-R1/README.md) and [field-tree experiment](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/visual-quality-implementation/L8a-R1/README.md).

The useful next experiment is a **target-hardware comparison of existing cell sizes**, using the same placements and camera routes. A submission-limited machine and a geometry-limited machine may prefer different tradeoffs.

### B. Bark and leaves should retain different LOD policies

The field-tree work already relaxes bark geometry more aggressively while preserving leaf coverage. Earlier trials showed that more aggressive leaf settings visibly thinned crowns and pines.

The current builder also discards excessively reduced leaf LODs and limits coarse alpha mip selection for specific assets. These protections address actual recorded defects. [Current vegetation implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/scenery/imported_vegetation.gd).

I would investigate the remaining expensive leaf representations by source asset, rather than apply another global reduction. The useful questions are:

- Can the same crown silhouette and gaps be represented with better-arranged cards?
- Are overlapping transparent regions doing unnecessary work?
- Does a distant representation reduce geometry without increasing expensive pixel coverage?
- Does wind remain inside the declared bounds?

Google/Arm’s material guidance emphasizes measuring transparency and overdraw alongside geometry. A lower triangle count can still leave the GPU doing more work on overlapping pixels. [developer.android.com](https://developer.android.com/games/optimize/materials?utm_source=chatgpt.com)

### C. Extend the existing alpha-coverage workflow carefully

Godot 4.8 provides coverage-preserving mipmaps, and **OpenRC already uses them for the maple leaf atlas**. That is completed work, not a missing feature.

The retained maple experiment compared unmipped, ordinary-mip, and coverage-preserved versions at actual 1080p and 1440p. At 256 m and 1080p, the reported silhouette-area change was approximately **−35.8% with ordinary mips versus −7.5% with preserved mips**. Those are image-sampling metrics, not FPS or pilot-readability results. [Maple evidence](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/docs/research/engine-upgrade/GDU-11/README.md).

The opportunity is to extend that existing workflow selectively to another foliage texture or impostor atlas.

There is a specific interaction to test: the far-tree shader already increases alpha with mip footprint to recover coverage. Adding coverage preservation while retaining that compensation could make distant crowns too full. [Current compensation](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/treeline.gdshader#L92).

Start with one import-only comparison. If shader compensation then needs adjustment, evaluate it separately. Coverage preservation addresses filtering losses; it cannot restore leaves removed from the mesh.

---

## 5. Shadow settings are a substantial hardware lever

The shadow configuration deserves its own hardware qualification, independent of the scene-detail level.

### Current allocations

The current policy defines these tiers:

| Shadow setting | Atlas dimensions | Requested depth precision | Cascades | Nominal depth payload* |
|---|---:|---:|---:|---:|
| Low | 2048² | 16-bit | 2 | 8 MiB |
| Medium | 4096² | 16-bit | 2 | 32 MiB |
| High | 4096² | 32-bit | 4 | 64 MiB |
| Ultra | 8192² | 32-bit | 4 | 256 MiB |
| **Current under the High graphics profile** | **8192²** | **32-bit** | **4** | **256 MiB** |

\*Calculated as width × height × depth bytes for one atlas. This is not a measurement of actual GPU allocation or total shadow memory; backend formats, auxiliary resources, and driver behavior can differ. Cascades share the atlas, so these figures should not be multiplied by the cascade count.

Source: [shadow settings and resolution policy](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/shadow_settings.gd#L19).

A useful UI and benchmarking detail follows: **“Current” is relative to the graphics profile.** Under High graphics, explicitly selecting shadow quality High requests a smaller atlas than Current.

### Recommended direction

Qualify shadow settings as a combination of:

- Atlas size.
- Depth precision.
- Cascade count.
- Shadow distance.
- Filtering and PCSS behavior.
- Caster selection.
- The separate projected aircraft cue.

Godot’s own guidance identifies resolution, precision, and filtering as significant costs, and recommends evaluating lower allocations for constrained hardware. [Godot Engine (stable) documentation in English](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html?utm_source=chatgpt.com)

For OpenRC, the visual checks must include landing-gear contact, moving wing shadows, low sun, thin structures, and shadow stability during zoom. Reducing atlas size without reconsidering shadow distance can make useful shadows much less stable.

The current Scene Detail profiles primarily change scenery selection, tree coverage, and mesh-LOD thresholds. They do not constitute a complete hardware performance profile. A qualified preset should compose the existing settings coherently while keeping their effective values visible. [Scene-detail profile definitions](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/scene_detail.gd#L23).

---

## 6. Custom-paint vertex expansion is real, but its benefit is narrower

The procedural paint adapter currently allocates one output vertex per base triangle corner. It maintains a map keyed by source vertex and projection face, but only uses that map for reuse while processing LODs.

For an indexed surface, repeated source vertices on the same projection face can therefore become unnecessary duplicates. The adapter could reuse those entries for the base geometry as well. [Adapter implementation](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/aircraft/procedural_skin.gd#L186).

However, further inspection narrowed the recommendation:

- This adaptation runs for **custom liveries**, not every default aircraft.
- The Stik exits before the six-view projection path.
- Extra and P-51 procedural builders already emit separate triangle corners in relevant geometry.
- Lumber’s repaired surfaces can also already be expanded.

A source-index map cannot deduplicate vertices that were already assigned different source indices. A broader deduplication would need to compare all relevant attributes and preserve intended seams.

There is a useful recorded Lumber example: its left aileron white surface has **1,020 vertices and 928 triangles**, showing that indexed input exists in an eligible paint target. That does not establish the achievable reduction, because the projection-face assignments also matter. [Recorded mesh measurements](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/assets/aircraft/turbo-lumber-evolution/mesh-measurements.json#L299).

I would keep this behind the first three priorities. It can improve vertex memory and processing without changing triangle count, but needs actual array measurements before its value is clear.

Its tests must compare projected UVs, normals, tangents, colors, secondary UVs, and retained custom attributes for both base and LOD triangles. It also carries the custom-paint identity compatibility requirement described earlier.

---

## 7. Hardware optimization should follow the observed bottleneck

The same geometry change will have different value on different machines.

For the next qualification pass, I would organize experiments around the measured limitation:

| Observed limitation | First experiments | Useful evidence |
|---|---|---|
| CPU submission cost | Fewer material surfaces; selective batching; distant parked representations | CPU render time, draw submissions, frame percentiles |
| GPU geometry cost | Restore lost LODs; improve parked LODs; simplify projected-shadow proxy | Corrected primitive counts and GPU time by affected pass |
| Pixel or bandwidth cost | Foliage overdraw, shadow allocation, shader sampling, reconstruction | GPU time, internal resolution, screen coverage |
| Memory pressure | Texture formats, vertex duplication, resource lifetime, qualified streaming | Peak memory and resource inventory |
| Loading or transition stalls | Mesh construction, repair caches, resource preparation | Phase timing and worst-frame behavior |

Terrain3D’s own performance guidance similarly treats texture configuration, foliage materials, geometry, and shadows as separate concerns. Its advice is useful here as an experienced Godot project’s checklist; its plugin-specific settings are not automatically OpenRC settings. [Terrain3D 1.2.0 documentation](https://terrain3d.readthedocs.io/en/latest/docs/performance.html?utm_source=chatgpt.com)

### Reconstruction needs a precise label

At a 1920×1080 output, the current FSR/DLSS Quality scale corresponds nominally to **1280×720 internal rendering**; Performance corresponds to **960×540**. Temporal reconstruction also changes the active anti-aliasing path. [Current reconstruction policy](https://github.com/bultodepapas/OpenRCsimulator/blob/f47d1dc6cccb141936407d0217eafdc465558190/app/render/reconstruction.gd#L27).

Those can be useful modes, but their acceptance should explicitly identify output resolution, internal resolution, and actual provider execution.

For this simulator, the critical visual test is a moving aircraft that occupies relatively few pixels: wingtip continuity, tail separation, roll direction, propeller behavior, and contrast against trees. A still screenshot or a 1080p output label cannot establish those properties.

### Texture streaming is conditional on the renderer

I checked the new texture-streaming feature against the exact engine pin.

**Compatibility explicitly rejects streaming**, and `StreamedTexture2D` falls back to full-resolution mip 0 on that renderer. Sources: [streaming startup](https://github.com/godotengine/godot/blob/cafc17a19/modules/texture_streaming/texture_streaming.cpp#L279) and [resource fallback](https://github.com/godotengine/godot/blob/cafc17a19/scene/resources/streamed_texture.cpp#L577).

A future Forward+/Mobile experiment needs actual streamed texture resources; enabling a global flag does not convert ordinary imported textures automatically. The feature’s introduction describes that separate import path. [Godot Engine](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-5/?utm_source=chatgpt.com)

I would begin any such experiment with large opaque environment textures. Existing foliage coverage, embedded aircraft textures, and custom texture-coordinate calculations need individual qualification.

---

## The implementation sequence I recommend

The next work can be divided into small, reviewable changes with clear acceptance criteria.

| Order | Work package | Acceptance evidence |
|---|---|---|
| **1** | Inspect and preserve Lumber LODs through visual repair | Imported versus final runtime LOD inventory; cold/cache-hit parity; paint compatibility; close and distant captures |
| **2** | Trial one simplified aircraft projected-shadow proxy | Reduced redraw cost during active maneuvers; preserved silhouette and landing cues |
| **3** | Improve the parked Stik’s distant representation | Lower geometry and/or surface submissions; preserved close appearance, ground contact, and culling groups |
| **4** | Compare existing shadow allocations on named hardware | GPU and memory measurements; low-sun, zoom, and contact-shadow review |
| **5** | Extend one foliage filtering or cell-size experiment | Same placements and collision identity; moving 1080p review; measured frame-time result |
| **6** | Optimize eligible custom-paint vertex reuse | Actual vertex reduction; complete attribute/UV parity; existing skin compatibility |

For each experiment, use the existing debug bridge, flight measurement, shadow, and tree tools. Record the complete flight workload at actual 1080p, then test higher resolutions. Include steady flight **and** the relevant stress case—especially rolls for the projected shadow and narrow-FOV views for trees.

The budget report should follow the asset through the whole pipeline: **imported geometry → runtime-modified geometry → selected LOD → visible and auxiliary passes**. It should record triangles, vertices, surfaces, memory, and frame timing separately. Godot’s generated LODs normally reuse the original vertex arrays through alternative index buffers, so a large reduction in rendered triangles does not imply the same reduction in resident mesh memory. [Pinned importer implementation](https://github.com/godotengine/godot/blob/cafc17a19/scene/resources/3d/importer_mesh.cpp#L830).

**My first implementation choice is the Lumber LOD-preservation work, including its paint-compatibility handling. The next measured prototype should be the aircraft shadow proxy, followed by the parked Stik.** Those three have the clearest connection between a specific current mechanism, a bounded change, and evidence that can establish whether the change is worthwhile.