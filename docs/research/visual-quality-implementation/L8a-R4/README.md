# L8a-R4 Fagus foliage backlighting

2026-11-09 · Landscape **L**, coordinated with SC/LU. Implements the bounded leaf-lighting comparison from investigation 1 of the supplied 24-investigation supplement. [Tree plan](../../../plans/tree-forest-quality.md), [material contract](../../../../tools/landscape/vegetation/README.md), [capture commands](../../../../tools/trees/README.md#native-imported-tree-comparisons).

## Change

The existing Fagus foliage gets a restrained neutral backlight color, `Color(0.35, 0.35, 0.35)`, on its duplicated effective material. Godot's lighting subsequently colors this contribution with the original leaf albedo, so leaf color/detail remain visible. Bark, pine, oak, saplings and the four protected maples retain their treatment. No texture, mesh, placement, wind amplitude, culling bound or collision rule changed. Regenerating woodland edges changed only the imported-material source hash.

The qualified wind adapter now mirrors StandardMaterial backlight color and optional texture. Separate compiled variants isolate this feature; existing bark/feature-off variants do not activate the backlight lighting path. The adapter still rejects subsurface scattering/transmittance and other unsupported material modes. Source resources stay immutable and cached materials are not edited after conversion.

The pinned [Godot material generator](https://github.com/godotengine/godot/blob/cafc17a19/scene/resources/material.cpp) adds the RGB backlight color and texture; it does not multiply them. The color has `source_color` conversion, while the texture is sampled as data with a black fallback. The [Compatibility renderer](https://github.com/godotengine/godot/blob/cafc17a19/drivers/gles3/shaders/scene.glsl) then multiplies the diffuse contribution by albedo. The new adapter preserves those semantics, UV1 transforms, filtering and repeat/clamp behavior.

This is an authored appearance approximation. The [Habel et al. leaf-translucency paper](https://www.cg.tuwien.ac.at/research/publications/2007/Habel_2007_RTT/Habel_2007_RTT-Preprint.pdf) motivates separating leaf reflection/transmission and studying spatial structure; this delivery does not implement its measured thickness maps or physically based scattering model. It adds no transmission texture.

## Evidence

Native Windows, Godot `4.8.beta2.official.cafc17a19`, Compatibility/OpenGL, RTX 3090, NVIDIA driver `617.42`:

- **30 synthetic source/wind pixel comparisons, zero channel error:** three cull/repeat variants × feature-off, missing-texture, color-only, texture-only and combined treatments × direct-light/ambient-only. The complete native script reports **65 checks, 0 failures**. The controlled fixture keeps wind zero and avoids distant alpha/LOD differences. [Pixel receipt](pixel-parity.json).
- **43 complete 1920×1080 captures:** fixed-camera/exposure front/side/rear/ambient illumination of the production 15 m Fagus; gust/repeat/wrap controls; opposite tree viewpoints with material off/on under production noon, positive low sun, sunset and night SDR snapshots. Every image size/hash and unique case was checked. These viewpoint names do not imply the same light incidence at every time of day. [Capture receipt](lighting-review.json), [off/on measurements](lighting-comparison.json).
- The neutral ambient-only images are byte-identical to baseline. The production snapshot off/on pairs respond at noon and low sun (solar elevation **6.849°**); sunset (**−0.832°**) and night have no changed pixels. Thus the tested treatment does not behave as emission when direct light is absent. Gust/repeated-time/1024-second-wrap frames match exactly.
- The production pilot and car-park views were captured at 1080p and inspected. The treatment retains branch openings and does not add a uniformly glowing crown. Source albedo, normal maps and roughness 0.85 remain in use.
- Headless checked passes: `test_imported_tree_backlight.gd` (19 scope/guard checks), `test_imported_tree_rendering.gd`, `test_imported_vegetation.gd`, `test_field_tree_detail.gd`, `test_woodland_edge_habitat.gd` (29 checks), generator `--check`, and final import. Geometry/placement/proxy consumers remain unchanged.
- A disposable copy forced the final PNG write to fail. The tool exited nonzero and published no completion report. Failed captures abort before the unique-case/completion receipt can be written. [Validation and negative-check references](validation.json).

The native pixel comparisons are retained **manual rendered evidence**, not a registered visual CI gate. The headless test explicitly skips pixels; its pass establishes scope/material-guard checks only. Full logs and PNGs are under ignored `tmp/vegetation-backlight-20261109/`; no capture image was added to Git.

The native JSON receipts are byte-preserved in Git. A [fresh sparse-clone check](checkout.json) with `core.autocrlf=true` and `false` retained their exact hashes and the nine normalized source identities. Validation retains both raw capture-host source hashes and UTF-8/LF-normalized text hashes: identical code can have different raw checkout bytes. This is not a complete simulator package test.

The initial whole-tree static/wind comparison has small pre-existing pixel differences, also present before backlighting, from the production render paths. This delivery proves exact parity in the isolated material fixture and records the production comparisons; it does not claim whole-tree bit equality.

## Limits

The SDR snapshots do not qualify Field World's moonlit/flowing sky. Full CI/export, lower-end hardware, aircraft attitude recognition and the five alternating whole-flight performance pairs remain open. Separate feature variants avoid adding this shader path to unchanged materials, but do not establish a frame-time saving or the shared +0.5 ms allowance. Tree-card lighting still uses its separate approximation; broader mesh/card lighting agreement, foliage normal filtering and richer woodland composition remain separate work.

The session started at `1094aded3b7a339a99ca27299d765217caa3ba7e`. Other shared-workspace activity advanced HEAD and committed this implementation alongside unrelated work during verification; the validation receipt identifies the observed HEAD and actual source hashes. This delivery makes no scoped-commit or full-tree verification claim for those unrelated edits.
