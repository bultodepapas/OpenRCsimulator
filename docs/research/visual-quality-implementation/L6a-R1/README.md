# Downloaded trees, woodland placement and imported-tree wind

2026-10-17 local / 2026-10-18 UTC. Implementation evidence for L6a-R1, the source-fidelity slice of L6b-R2, L7-R1, the batching experiment in L7-R2 and L15b-R1. [Plan](../../../plans/tree-forest-quality.md), [research](../../tree-forest-quality-2026-10-17.md), [source pipeline](../../../../tools/landscape/vegetation/README.md).

The production scene now selects seven downloaded mature tree forms, uses irregular far-woodland patches at the existing population, and animates the qualified imported trees with session wind. No tree geometry was modeled. This is an incremental improvement of the established stylized family; it is not a photorealism or pilot-readability acceptance claim.

## Implemented selection

| Item | Result |
| --- | --- |
| Close source forms | `CommonTree_1/2/3/4`, `Pine_1/2/3` from the retained Quaternius Standard CC0 archive |
| Library | 19 assets, seven trees; 39,966 triangles for one copy of each library asset |
| Placed close trees | Same 17 positions, headings, seeds and heights; seven source forms instead of three; the seven scaled broadleaf saplings retain their previous two forms |
| Close-tree source geometry | 80,673 → 80,177 triangles across the 17 instances |
| Complete scenery | 648,925 source triangles, below the existing 650,000 ceiling; no budget increase |
| Field forest | Same 480 near + 1,200 far cards; same three card identities and eight sector MultiMeshes |
| Far composition | `habitat-v1`, seed 610617; twelve unequal anisotropic patches, irregular margins and gaps; 55–173 trees per patch |
| Wind | Imported trees use shared `sim_clock` / `wind_vec`; separate field-card behavior and physical wind are unchanged |
| Spatial cells | 0/64/128/256 m available for imported trees; default remains 0; no density increase |

The new forms add branching/full, sparse-crowned, broad-conical and open-trunk silhouettes. Existing bark/leaf textures are shared; the four additional forms require no additional texture images. Source meshes, indices, positions, normals, UVs, units and transforms are retained.

The original glTF colors contain 43,282 components slightly above one, up to `1.0001678466796875`. The existing card adapter already recognizes this upstream precision defect. The vegetation generator now applies the same narrow policy to runtime tree buffers: clamp only float `COLOR_0` values in `(1, 1.0002]`; reject unsupported excursions. It leaves every other buffer byte and the original archive unchanged. Each catalog row records changed-component counts and source/output buffer hashes. This is a reproducible data repair, not new geometry or a painted texture.

[Khronos validation](validation.json): eight glTFs, **zero errors**, zero unresolved resources, 13 unsuppressed tangent-generation warnings. Seven warnings concern the retained trees; six concern the Poly Haven comparison source. Native import generates the missing tangent basis; the gallery and shader tests explicitly retain the bark normal maps. Validator success alone does not establish visual suitability.

## Realistic source comparison

[Poly Haven Pine Sapling Small](https://polyhaven.com/a/pine_sapling_small) was actually downloaded under [CC0](https://polyhaven.com/license): 21,891,339 bytes, eight verified source files, three intact forms and 398,144 source triangles. Original URLs, authors, API MD5 and local SHA-256 are retained in the [source manifest](../../../../assets/landscape/vegetation/source/polyhaven_pine_sapling_small/download-manifest.json) and [inspection](../../../../assets/landscape/vegetation/source/polyhaven_pine_sapling_small/INSPECTION.md).

The [source gallery](captures/realistic-source/source_gallery.json) isolates each supplied A/B/C node, keeps source materials and metre scale, and captures front/back/underside at fixed 1.65 m orthographic framing. These are roughly one-metre saplings, not mature trees. Their geometry stays outside `app/`; placing the full-resolution set would consume most of the complete scenery budget before any other scenery. No supplier LOD or wind channel was found.

The planned LOLIPOP Pine/Maple download could not be completed through the available unauthenticated Sketchfab access; no download token or archive was available. Pine Tree 01 was rejected before download after its official metadata showed about 958 MB and 17.18 million triangles; Jacaranda metadata also exceeded its listing's quoted count. The small verified Poly Haven source provides a real material/silhouette comparison while mature realistic-source/LOD qualification remains open.

![Downloaded realistic sapling at its original scale](captures/realistic-source/a-front.png)

## Placement, contact and identity

The generator preserves the frozen 480-point near prefix (`9b42b61f…c722875`), total count, 0.25 m grid, 600–1,500 m far range, minimum 4.5 m far spacing, crown-cleared sight gaps and runway/mown flight corridor. Patch counts are 55, 64, 72, 82, 88, 92, 96, 102, 110, 124, 142 and 173. [The pipeline](../../../../tools/trees/README.md#l6bl7-placement-and-rendering) documents the canonical recipe and explicit historical control. These are artistic habitat estimates, not ecological simulation or surveyed geography.

Changed placement and selected mesh envelopes intentionally produce a new collision world. With the same normalized field/scenery inputs and lights omitted, the identity changes from `faef6caa…6fddcce` to `5dd45231…f62b3ca`, at the same 4,958 proxies. [Full candidate inventory](candidate-inventory.json) records exact identities, source choices and dimensions. This delivery must not be labeled an exact replay of the old world. Contact tests derive sweep lengths from actual crown bounds and exercise all seven sources. All 17 close trees remain visible at low, balanced and high scenery quality.

![Previous circular far groups](captures/baseline/forest_overview.png)
![Irregular groups at the same tree count](captures/candidate/forest_overview.png)

## Wind and material evidence

The tree-only shader supports the reviewed single-mesh, two-surface trees. It preserves albedo, normal maps, UV transforms, vertex colors, roughness/metallic/specular scalars and alpha scissor. Unsupported packed maps, material features, transforms or independently modeled stem/crown parts retain source materials. A separate shared bend frame is required before multi-part trees can opt in.

The height-squared displacement fixes the root, limits source-space sway, follows the horizontal session wind and corrects normals and the tangent frame analytically. Culling and reported bounds include maximum displacement. Per-build material copies isolate wind controls; tree regrouping preserves source transforms, phase, tint and damage IDs. No per-instance shader uniform is required by Compatibility. The legacy all-role wind entry point remains available; the production call enables trees only.

[Native checks](capture-checks.json) pass on all seven forms: calm source/wind images are byte-identical, the wind-off clock control is static, a repeated time is byte-identical, 1024-second clock wrap matches time zero, and forward/reversed wind produces different images. These checks establish deterministic rendering, not botanical motion realism. Source and wind-on capture manifests retain image hashes and renderer identities.

![Close trees before](captures/baseline/car_park.png)
![Seven-form selection after](captures/candidate/car_park.png)

## Verification and performance scope

Native renderer: Godot `4.7.2.stable.official.ed1daf0bf`, OpenGL Compatibility, RTX 3090, NVIDIA 617.42. Matched field/gallery captures use 1280×720 and 4× MSAA. Baseline runtime is frozen from `5b1773fe76a21ba1bedb06421e15b3238377660e`; the candidate overlays this tree implementation. [Build identities](build-identities.json) distinguish it from concurrent grass work and identify 18 additional newline-only differences in source model text. Those differences do not change geometry/materials; Git attributes now preserve the hash-bound source bytes across checkouts.

The [eleven focused native headless tree/vegetation/collision suites](verification.json) pass, including 28,626 treeline checks. A native Compatibility run also passes 31,986 treeline checks, including GPU-owned instance data. The first isolated lifecycle attempt lacked the external aircraft authoring identities; restoring those exact baseline files resolved it. The final native [20-cycle Home/Fly/End-flight probe](candidate-native-lifecycle.json) completes with zero orphan nodes and stable Home/flight node counts. This checks lifecycle behavior; timings were collected while other CPU verification ran and are not loading-performance acceptance.

The source generator and its five contract tests also pass against a [clean Git-tree archive extracted on Linux](source-verification-linux.log), identified by the [snapshot receipt](source-snapshot.json). Exact-byte attributes preserve downloaded model/license files, while the generated catalog uses LF. Two upstream license copies now retain their original CRLF and trailing spaces; altering those bytes would invalidate the retained source hash. No source wording was changed.

The final combined-mode test also passes headlessly and under native Compatibility: wind with 64/128/256 m cells retains per-tree phase/tint/transform data, expanded bounds and damage hide/restore. Native checks read actual MultiMesh buffers; Dummy returns empty buffers, so the headless path checks CPU records and configuration. This strengthened test was added after the timed runs; runtime source is unchanged.

A [Windows-preset PCK smoke check](pack/summary.json) passes from an otherwise empty project root. It loads all seven tree forms, 14 source material surfaces, seven bark normal maps, the catalog and exact CC0 license. Decoded image hashes for all four shared textures match the source project; the 19-asset vegetation contracts also pass from the pack. The initial app-only export lacked external aircraft authoring JSON; restoring the exact baseline identities outside `app/` resolved the exporter error. This is packaged-resource verification, not a complete Windows/Linux/macOS release qualification.

The texture inventory reveals **no mipmaps in either the frozen source import or its pack**. The export preserves the observed source data; it did not drop mip levels. Source/calm image equality therefore does not establish mip coverage or freedom from shimmer. L6b-R1/R2 must compare ordinary Godot mip generation and foliage coverage in motion before adopting an import change; this delivery does not silently enable it.

The unmodified full Linux `app/test.sh` was attempted in a fresh clone. It stops at the unrelated AUD-12 audio-bus freshness check: editor import adds a resource UID while the checker compares exact serialized text. The same check fails on the untouched baseline. The original failure log is retained; it is not reported as a passing full suite. An [auxiliary remainder audit](linux-remainder-stop.json), bypassing only that check in the disposable clone, passed the full script-parse phase and progressed through unrelated aircraft tests without engine/script errors before being intentionally stopped. Its log, patch, exact snapshot differences and incomplete status are retained. It does not qualify the final complete application; final tree-specific native checks cover the repaired buffers and later combined-mode test separately.

The [five-pair native measurement](profiles/summary.json) alternates AB/BA order, with 10 s warmup and 60 s measurement in each fresh process, at the fixed car-park camera. VSync is disabled and no application frame cap is requested. Every sample and engine log is retained; [exact measurement fixtures](fixtures/quality_capture.gd) preserve the code used before later diagnostic metadata additions.

| Static wall-frame metric | Baseline median across runs | Candidate median across runs |
| --- | ---: | ---: |
| p50 | 4.976 ms | 4.919 ms |
| p95 | 15.886 ms | 15.814 ms |
| p99 | 17.740 ms | 17.214 ms |
| Visible-counter draws | 68 | 84 |
| Visible-counter primitives | 230,369 | 241,793 |

The **median paired p95 difference is +0.048 ms** (pair differences +0.048, −0.399, −0.053, +0.157, +0.162 ms). This differs from subtracting the two independent medians. Median paired GPU-p95 difference is −0.043 ms; these small changes do not establish a speedup. More source variants increase submissions and camera-visible geometry despite the slightly lower complete source-triangle total.

The [batch/shadow controls](batch-shadow-controls.json) keep all 17 close trees. At 64 m there are 12 tree batches; 128/256 m give ten, compared with seven at 0. At the matched car-park view, all three split choices increase the visible draw counter from 84 to 88 and primitives from 241,793 to 245,884; image hashes also change. Instance transforms/damage identities pass CPU equivalence checks, but rendering is not pixel-identical. Godot selects one LOD per MultiMesh using its bounding box, so regrouping can change representation as well as culling; this is a relevant mechanism, not an attribution proof for every changed pixel. [Godot 4.7 mesh LOD documentation](https://github.com/godotengine/godot-docs/blob/4.7/tutorials/3d/mesh_lod.rst). These results do not justify enabling cells for this compact population; default remains 0.

Turning off only imported-tree casting reduces the draw counter to 62 while the directional light still casts shadows. Disabling all engine shadows also gives 62 draws but a different image. This distinguishes caster selection from global shadow configuration without claiming a shadow-time speedup.

Static viewport samples exclude aircraft physics, UI, audio, live camera inputs and simulation/wall acceptance. They cannot close the shared +0.5 ms visual budget or the 60 Hz flight gate by themselves. GPU residency is unmeasured; engine static CPU memory and construction duration are reported separately in each raw run. Raw shadow draw counters report zero in this Compatibility fixture even when directional shadows are enabled; do not interpret that counter as proof that shadows are disabled. The independent shadow controls record the actual light setting.

## Remaining gates and controls

- Keep spatial batching at 0 and population unchanged until measurements justify a different setting. Density and the 650k source-geometry ceiling are not silently increased.
- Mature realistic-source integration, source-texture mip/alpha-coverage qualification, near/far palette matching, temporal 720p/1080p fly-throughs, independent aircraft-attitude readability and owner preference remain open.
- Optional L8 mesh/card transitions and octahedral impostors are not implemented merely because a library exists. The current card and imported populations have no new LOD transition between them.
- Native flight profiling requires the existing `--frametimes` workflow and a controlled live-input route. The existing `.orfl` replay is headless numerical replay; it cannot render the old route against the changed forest.
- Full release/export, RC views and the shared visual/performance owner gates remain separate. No physical flight validation is claimed.

Disable only the new imported-tree motion with `--tree_wind=off`. Restore the prior layout only with the historical generator recipe, and restore source selection/catalog/buffers together if rolling back the close trees; the corresponding collision identity changes again. Current operational commands live in the two linked pipeline READMEs.
