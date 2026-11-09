# L7-R5 Woodland grass root contrast

2026-11-09 · Landscape **L**. Addresses the root/contact review in `external Audits/VEGETATION.MD`, using the existing downloaded short- and tall-grass cards. The [previous groundcover evidence](../L6c/tree-completion/groundcover-transition/README.md) documented their conspicuously dark baked roots; fresh native 1080p views reproduced the repeated black bases.

The woodland shader now lifts only dark grass-root albedo toward an authored, restrained green floor. The contribution fades out over the bottom **30% of plant height**. The material derives each grass's height/frame ratio from its source manifest, excluding transparent bake padding. Instance tint remains in use. The upper blades, fern and flowering-shrub materials, alpha cutoff, view-frame selection, normals and transforms retain their treatment.

The selected strength is **0.75**, after comparing 0.50, 0.75 and 1.00. Independent visual review found 0.50 nearly black and 1.00 increasingly flat/olive on the large northwest clump. The result is a modest contrast reduction: tall grass still has a dark rectangular base. It is not exact local turf/litter matching, a replacement for better source silhouettes, or a solution to forest depth.

This is a material-only change. High retains **220 plants, 472 source triangles and five batches**; balanced remains a stable subset and low omits the decoration. No source asset, atlas, generated placement, collision or physics change is involved. The shader adds no texture sample; zero strength skips the correction branch.

## Evidence

[Receipt](root-review.json), including checked-run identities, source hashes, effective material values and image comparisons. Native Windows, Godot `4.8.beta2.official.cafc17a19`, Compatibility/OpenGL, RTX 3090, NVIDIA `617.42`:

- The focused native regression passes **25 checks: 23 framebuffer checks and two material-binding checks**, using a 128² diagnostic viewport. Real atlases retain the upper 70% pixels and exact alpha coverage. A separate source-sampling shader and four-frame atlas with internal transparency exercise zero-strength color, holes and view selection. A disposable shader with the root branch disabled fails the expected three root-color assertions. Headless execution explicitly skips framebuffer checks.
- The existing native habitat test passes **33 checks**, including stable quality subsets, no collision objects, independent geometry counts, source immutability and four-view/yaw readback. The placement generator and **six Python tests** pass without regenerating the recipe.
- **26 matched pairs at 1920×1080** cover all four pockets from eye height, above and reverse, plus noon, low sun, dusk and night controls. Camera, field inputs, material resources and draw/primitive counters agree within each pair. Relevant source hashes are unchanged across the capture campaign. Both night pairs are pixel-identical. These are static SDR snapshots with zero wind.
- The correction-off control matches the original shader's pixels in all three initial views. The selected 0.75 trial and the final production default also match in those three views. The initial 0.50 trial predates proper serialization of Godot's Color-valued shader default, so its recorded root color is null; that run is retained as a qualitative trial, not a complete uniform-binding proof.

Raw PNGs, reports and logs are under ignored `tmp/vegetation-contact-20261109/`; no capture image is added to Git. [Reproduction commands and capture controls](../../../../tools/trees/README.md#woodland-grass-root-review-l7-r5).

These images do not qualify moving-flight readability, full-world moon/sky behavior, other GPUs/renderers, exported packages or frame-time cost. Unchanged geometry and texture counts are not a performance measurement. Unrelated shared-workspace aircraft/physics work was preserved and is outside this verification.
