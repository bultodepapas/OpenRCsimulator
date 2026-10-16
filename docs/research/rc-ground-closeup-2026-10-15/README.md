# RC ground close-view audit

2026-10-15. Scope: read-only production-material audit, primary-source research and two fresh native static captures. No production shader, texture, physics or camera changes. Implementation is owned by the [L9d improvement plan](../../plans/rc-ground-closeup.md).

## Evidence and findings

Windows, Godot 4.7.2 official, OpenGL Compatibility, NVIDIA GeForce RTX 3090, 1280x720. The existing [activity capture tool](../../../research/rc-monster-truck/visual/capture_activity.gd) loaded the production scene with audio disabled, normal supported spawns and zero driving ticks. Both retained final runs exit 0; logs contain no script/shader errors or cleanup warnings. This proves static rendering only, not motion quality, physics realism or frame-time budgets.

- [Dirt current view](dirt-current.png), [state/renderer receipt](dirt-current.png.json), [log](dirt-current.log).
- [Grass current view](grass-current.png), [state/renderer receipt](grass-current.png.json), [log](grass-current.log).
- [Audit manifest](audit-manifest.json): exact commands, process outcomes and hashes before/after of the inspected production sources. Concurrent unrelated work existed in the tree; this is not a clean-commit or release qualification.

The dirt view shows an oversized-looking lattice of soft brown patches, a very uniform surface response and green shoulder bands distinct from the adjacent turf. The grass view shows dense bright linear strokes on a flat surface. These are visual observations of the retained pixels, not inferred performance failures. The runway deliberately has short grass; adding tall blades over the runway would be incorrect.

| Priority | Source evidence | Implication |
| --- | --- | --- |
| P0: dirt detail | [Track builder](../../../app/vehicles/ground/airfield_track_view.gd) selects [gravel shader](../../../app/scenery/gravel.gdshader), strength 0.72. Two procedural grain frequencies (23/m, 6/m), fixed roughness 0.88 and 0.6 mm nominal bump; no downloaded maps. | The visible pattern is procedural lattice noise, not an undersized dirt photograph. Increasing a texture-import size cannot fix this path. Replace one material with coherent downloaded soil maps. |
| P0: shoulder seam | Builder lerps palette colors using coverage; alpha stores `1 - coverage`. Gravel then remaps `(1 - alpha) * 2`. The shoulder does not evaluate shared turf shading. | A smoother color lerp alone will not match the grass's fine detail, normals or lighting. Preserve coverage semantics while unifying the material boundary. |
| P1: grass appearance | [Ground builder](../../../app/render/ground.gd): 256-square procedural color tile; [grass include](../../../app/render/grass_surface.gdshaderinc): 6 m world repeat plus anti-tiling/macro variation. [Turf provenance](../../../app/assets/landscape/turf/PROVENANCE.json): generated 1024-square 2 m slope/tone tile, 18,000 artistic blades. | The current surface already has fine shading; the next comparison must test the character/scale of detail, not simply add another noise layer. |
| Preserve existing filtering | [Turf include](../../../app/render/turf_detail.gdshaderinc) uses two explicit-gradient anisotropic samples, major-footprint fade 0.015–0.08 m and distance fade 60–110 m. Import generates mips and intentionally avoids normal-map compression for packed slopes. | These channels are not a conventional RGB normal map. Keep the current generated data contract intact when evaluating an alternative. |
| P1: physical blades near the car | [Near grass](../../../app/render/near_grass.gd) places up to 6,000 seven-triangle clumps within 30 m of the pilot. [Shader](../../../app/render/near_grass.gdshader) fades against both pilot and camera. Circuit starts north of 36 m; [track evidence](../rc-monster-truck/RCV-track/README.md) confirms it lies outside this region. | Moving the camera does not populate the circuit. Increasing texture resolution cannot supply grass silhouettes. Extend bounded placement only after the material comparison. |
| P1: bank mapping | Track arrays contain positions, normals, colors and indices, but no UV/tangents. Vertices sample the physical road at 0.10 m spacing plus 2 mm. | Normal-map integration needs a correct projected frame, including banks; retain existing geometry/contact agreement. |
| P2: lighting and scope | [Ground shader](../../../app/render/ground.gdshader) has custom fog/cloud diffuse lighting, roughness 1 and specular 0. Gravel has a different material response. | Inspect low sun/headlights and boundaries. A generic PBR substitution across the entire field risks changing flight visibility. |

Graph discovery was attempted first; the indexed `grass_material` snippet had stale line ranges and no useful RC capture nodes. Current source was read to verify findings. The [previous VQ texture inventory](../visual-quality-implementation/VQ-02a/README.md) explicitly leaves ground-vehicle coverage open; its fixed-wing inventory is not RC validation.

## Free asset shortlist

Primary pages checked 2026-10-15. These are candidates, not adopted runtime assets. No source package was downloaded or repainted in this audit. Pin exact source files, hashes and license evidence during L9d-02. Supplier dimensions describe tile coverage, not a measurement of this simulated field.

| Candidate | Verified supplier metadata | Proposed role / selection caution |
| --- | --- | --- |
| [Dirt, Poly Haven](https://polyhaven.com/a/dirt) | CC0; 2 m width; 1K–8K; diffuse, GL/DX normal, roughness, AO/ARM and displacement. | First dirt trial. Reject conspicuous human-footprint repetition or oversized stones under the truck. |
| [Sparse Grass, Poly Haven](https://polyhaven.com/a/sparse_grass) | CC0; 2 m; 1K–8K; diffuse, GL/DX normal, roughness, AO/ARM, displacement and mask. | Worn edge / exposed soil trial. Its damp-soil appearance may be unsuitable for a dry runway. |
| [Grass 001, ambientCG](https://ambientcg.com/view?id=Grass001) | Approx. 1.4 x 1.4 m; 1K–8K JPG/PNG PBR packages; short/lawn tags. Author labels the source procedural. | Downloadable short-grass candidate, not a claim of photographed/measured grass. Inspect package channels before conversion. |
| [Sandy Gravel 02, Poly Haven](https://polyhaven.com/a/sandy_gravel_02) | CC0; 2.5 m; 1K–16K; diffuse, normal GL/DX, roughness, AO/ARM and displacement. | Alternative compacted aggregate; verify pebble size against wheels. |
| [Gravel 022, ambientCG](https://ambientcg.com/view?id=Gravel022) | Approx. 1.5 x 1.5 m; 1K–8K PBR JPG/PNG packages. | Secondary gravel path candidate; inspect actual map channels. |

[Poly Haven license](https://polyhaven.com/license) and [ambientCG license](https://docs.ambientcg.com/license/) identify CC0 assets. Do not assume a material pack's maximum advertised resolution is the appropriate runtime resolution. Current source vegetation is already catalogued under `app/assets/landscape/vegetation/`; audit/reuse it before introducing any new grass mesh.

## Technical research and recommendation

Godot's [image import guide](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html) recommends mipmaps for 3D and documents GPU compression and OpenGL normals. Its [shader language reference](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html) distinguishes sRGB color from normal/roughness data and provides sampler hints. Use albedo `source_color`, linear data maps, mipmaps and angle-aware filtering. Preserve world-space scale; evaluate a 2K candidate against 4K before deciding.

The [material guide](https://docs.godotengine.org/en/4.7/tutorials/3d/standard_material_3d.html) describes opaque materials, normal/height mapping and triplanar projection. Cosmetic normal/height detail does not supply tire collision geometry. The [BaseMaterial3D filter reference](https://docs.godotengine.org/en/4.7/classes/class_basematerial3d.html) explains anisotropy for grazing views. The [renderer comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) separates Compatibility from Forward+ features: do not confuse ordinary material normal maps with access to the Forward+ normal/roughness screen buffer.

Recommended order: downloaded dirt at correct scale; shoulder continuity; downloaded short-grass detail; bounded nearby grass; then any separately evidenced mud/gravel refinement. Keep deep parallax, renderer migration, field-wide dense vegetation and deformable soil outside this material delivery. The plan specifies the required same-state visual, motion, frame-cost, memory and packaging gates.
