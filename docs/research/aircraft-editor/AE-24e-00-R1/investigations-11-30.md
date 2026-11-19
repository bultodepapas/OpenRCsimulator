# Sequential decal Workshop investigations 11–30

Research date: **2026-11-19**. Batch 2. Each investigation below informed the next question. Search refinements and source reads within one investigation are not counted again. Findings describe evidence; design consequences are proposals. No native Godot rendering or performance qualification is claimed.

[Research index and staged synthesis](README.md) · [Machine-readable evidence ledger](evidence-ledger.json)

## 11. Corner distortion is not solved by clipping

**Question:** Will clipping alone preserve a sponsor's shape around a sharp edge?

**English search / source query:** `site:github.com/mrdoob/three.js/issues/21187 decal projections without distortions corners`

**Evidence:** [1](https://github.com/mrdoob/three.js/issues/21187) (upstream firsthand reproduction); [2](https://github.com/mrdoob/three.js/blob/dev/docs/pages/DecalGeometry.html.md) (upstream documentation).

**Finding:** A three.js reproduction shows duplicated/distorted projection around a shoulder; the current addon documentation still warns about corner distortion. A clipped projector can include an adjacent face and its planar UV mapping can stretch at oblique angles.

**Design consequence:** Define receiver-specific maximum facing angle and sharp-edge/connected-region rules. Show a placement boundary and refuse invalid scale/depth rather than silently wrapping a wordmark. Add a curved-versus-creased geometry exercise with an independent distortion metric.

**Limit:** This is evidence against an unconditional wrap-anywhere promise, not proof that every curved body is unsuitable.

**Next question:** Verify normal transforms and reflected orientation before defining those facing tests.

## 12. Nonuniform transforms and reflected winding

**Question:** Can point, direction and normal transforms share the same formula?

**English search / source query:** `glTF negative determinant winding normals inverse transpose transform; Godot Basis inverse transposed normal non uniform scale`

**Evidence:** [1](https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html) (official specification); [2](https://registry.khronos.org/OpenGL/specs/es/1.1/es_full_spec_1.1.pdf) (official specification); [3](https://docs.godotengine.org/en/4.7/classes/class_basis.html) (official API documentation).

**Finding:** The glTF specification ties reflected transforms to winding. Normal vectors use inverse-transpose transformation, unlike positions or tangents; singular bases cannot be inverted.

**Design consequence:** For receiver linear basis B: local normal to world is normalize(B^-T n); world normal to local is normalize(B^T n). Transform tangents with the corresponding direction matrix, orthogonalize, and account for determinant sign in emitted winding. Refuse near-singular transforms and store positive sizes with separate UV flips.

**Limit:** These equations are a mathematical contract; imported engine winding conventions and actual scene parenting still require tests.

**Next question:** Determine whether transparent receivers can preserve a sticker's intended opacity.

## 13. Transparent canopies require a separate feature contract

**Question:** Can an opaque sticker simply inherit the behavior of a transparent canopy?

**English search / source query:** `site:docs.godotengine.org Decal cannot affect underlying material transparency opaque alpha canopy`

**Evidence:** [1](https://docs.godotengine.org/en/4.5/classes/class_decal.html) (official versioned API documentation).

**Finding:** Godot documents that native decals do not change the receiving material's transparency. A nominally opaque image can therefore remain translucent when applied to a transparent receiver.

**Design consequence:** Keep the first playable receiver allowlist opaque. Mark canopy/glass, propeller blur and deforming surfaces unavailable with a clear UI explanation. Transparent receiver support must later prove independent sticker opacity and front/back sorting.

**Limit:** The documented behavior is a specific native-decal constraint; an overlay could behave differently but is not qualified merely by choosing a different node.

**Next question:** Define the exact alpha-compositing reference for layered sponsor artwork.

## 14. An independent alpha-order oracle

**Question:** What numerical result should overlapping semi-transparent stickers produce?

**English search / source query:** `site:w3.org TR compositing source over premultiplied alpha formula co alpha`

**Evidence:** [1](https://www.w3.org/TR/2024/CRD-compositing-1-20240321/) (official specification).

**Finding:** Source-over compositing has explicit premultiplied color and alpha equations. Order generally changes the result, so a layer-order check can compare actual pixels with independently calculated values.

**Design consequence:** Add a small mathematical exercise using distinct red/blue half-alpha inputs, transparent edges and an opaque base. Declare straight-versus-premultiplied boundaries and apply alpha once. Use the resulting expected values for an unlit native render fixture before lighting comparisons.

**Limit:** The equations do not choose the working color space or prove a GPU implementation. Native readback comparisons must allow only a declared quantization tolerance.

**Next question:** Choose and verify the color-space boundary so correct alpha math does not still change sponsor colors.

## 15. Explicit color-space boundaries

**Question:** How do we avoid washed-out or double-converted sponsor colors?

**English search / source query:** `site:docs.godotengine.org shading language source_color Compatibility Forward Mobile sRGB textures washed out`

**Evidence:** [1](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html) (official versioned documentation).

**Finding:** Godot distinguishes color textures from data textures with source_color. The requirement varies by renderer and HDR 2D, but the documentation recommends retaining the hint across configurations.

**Design consequence:** Declare source artwork as sRGB color plus linear coverage alpha. Record each conversion in the derivative pipeline. Compare unlit swatches and half-alpha edges across Compatibility/Mobile and 2D/3D previews; never use a browser screenshot alone as the native color oracle.

**Limit:** Lighting and tone mapping legitimately change displayed colors. Qualification must separate texture decoding/compositing errors from expected scene illumination.

**Next question:** Check transparent borders and mip generation, where correct colors can still acquire dark fringes.

## 16. Transparent edges and mipmaps

**Question:** How can small or oblique logos stay clean without black outlines or excess memory?

**English search / source query:** `site:docs.godotengine.org importing images fix alpha border premult alpha mipmaps memory 33 percent`

**Evidence:** [1](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html) (official documentation).

**Finding:** Godot documents alpha-border repair, a distinct premultiplied-alpha path and mipmap overhead. Alpha-test coverage preservation is intended for scissor materials, not arbitrary alpha blending.

**Design consequence:** Generate derivatives from preserved originals with a declared border/alpha policy and matching material blend mode. Check light/dark backgrounds and oblique views. Include mip levels in memory estimates; do not apply alpha-test coverage correction to the proposed blended sticker path.

**Limit:** A source-image importer setting does not automatically apply to runtime Image loading. Runtime admission must reproduce the chosen processing explicitly.

**Next question:** Investigate unique UV generation for a compositor without modifying the stock paint atlas.

## 17. Separate decal charts from the original paint UVs

**Question:** Can unique decal UVs be generated while retaining source correspondence?

**English search / source query:** `site:github.com/jpcy/xatlas README new vertices same number indices chart packing original vertex xref`

**Evidence:** [1](https://github.com/jpcy/xatlas/blob/master/README.md) (upstream repository documentation); [2](https://github.com/jpcy/xatlas/blob/master/source/xatlas/xatlas.h) (upstream source contract).

**Finding:** xatlas separates chart generation from packing and returns source-vertex references. Adding unique UV seams can increase vertex count even while index count remains the same.

**Design consequence:** If a compositor is selected, generate a versioned decal-only mesh/UV companion offline through the aircraft source pipeline. Preserve original material UVs and verify source correspondence and unique coverage; do not unwrap during a pointer gesture or silently repack an accepted cache.

**Limit:** This is a candidate tool and data strategy, not an installed dependency or proof that the project's custom materials accept another UV channel.

**Next question:** Determine what chart padding must protect against at distant mip levels.

## 18. Atlas gutters are part of the sampling contract

**Question:** Is a tightly packed base-level atlas sufficient for distant sticker quality?

**English search / source query:** `site:developer.nvidia.com texture atlas mipmaps bleeding gutters padding texture atlas`

**Evidence:** [1](https://developer.nvidia.com/docs/drive/drive-os/archives/6.0.4/linux/sdk/common/topics/graphics_content/Textures124.html) (hardware vendor documentation).

**Finding:** NVIDIA's atlas guidance requires borders wide enough that mip generation does not mix neighboring subimages. Atlas packing reduces some state changes but introduces sampling constraints.

**Design consequence:** Specify chart-edge dilation and per-mip isolation, permitted mip range and anisotropic footprint together. Add saturated neighboring-chart fixtures and inspect every retained mip, including tiny lettering. A universal one-pixel gutter is not an acceptance rule.

**Limit:** No fixed padding size is claimed before chart resolution, filtering and maximum mip level are selected.

**Next question:** Check how LOD simplification changes the geometry onto which a cached sticker was projected.

## 19. LOD topology cannot reuse arbitrary triangle IDs

**Question:** Will a sticker projected on the high-detail mesh still match a simplified receiver?

**English search / source query:** `site:github.com/zeux/meshoptimizer README simplification seams borders attributes LOD topology`

**Evidence:** [1](https://github.com/zeux/meshoptimizer/blob/master/README.md) (upstream algorithm documentation); [2](https://github.com/zeux/meshoptimizer/blob/master/src/meshoptimizer.h) (upstream source contract).

**Finding:** Simplification changes index topology and treats attribute seams according to algorithm/options. Some modes may merge disconnected nearby features; even preserved source vertices do not imply preserved triangle identity.

**Design consequence:** Bind saved placements to semantic receiver IDs and canonical local frames, with explicit geometry/LOD revisions. Regenerate or load a qualified decal representation for each LOD; never persist a transient triangle number as the sole attachment identity.

**Limit:** No meshoptimizer option is being changed in OpenRC. The lesson applies to any generated/imported topology change.

**Next question:** Verify that per-aircraft appearance resources can remain isolated when meshes or materials are shared.

## 20. Per-instance material and texture ownership

**Question:** Can editing an appearance accidentally mutate another aircraft or a frozen trial?

**English search / source query:** `site:docs.godotengine.org Resource resource_local_to_scene duplicate deep shared materials runtime instances`

**Evidence:** [1](https://docs.godotengine.org/en/stable/classes/class_resource.html) (official API documentation).

**Finding:** Godot resources can be shared. Scene-local duplication happens during instantiation, and shallow copies retain nested references; toggling scene-local behavior after instantiation does not retroactively isolate existing instances.

**Design consequence:** Define owned mutable material wrappers and immutable shared source images. A frozen revision pins its own accepted output handles; new edits never write into those textures. Add two-aircraft and Workshop-versus-trial isolation cases instead of assuming duplicate() isolates every nested resource.

**Limit:** The exact source-material and custom-skin graph must be audited at integration. Blind deep-copying every resource can violate the memory budget.

**Next question:** Resolve who owns pointer and keyboard input while a decal gesture is active.

## 21. Input routing before camera arbitration

**Question:** How do we prevent a slider, sticker drag and camera orbit from reacting to the same event?

**English search / source query:** `site:docs.godotengine.org input event order Control accept_event _unhandled_input SubViewportContainer mouse_filter`

**Evidence:** [1](https://docs.godotengine.org/en/latest/tutorials/inputs/inputevent.html) (official documentation); [2](https://docs.godotengine.org/en/latest/classes/class_control.html) (official API documentation).

**Finding:** Godot separates GUI handling and unhandled scene input. Accepted GUI events stop later propagation; SubViewports need explicit forwarding or a SubViewportContainer.

**Design consequence:** Route scene gestures through one owner state: idle, place, transform or orbit. Let GUI fields consume events first, suppress scene shortcuts while text entry owns focus, and explicitly convert preview-container coordinates. Focus loss/cancel must release ownership and restore the gesture start state.

**Limit:** accept_event cannot undo work already performed in an earlier _input callback. Integration must inspect and reroute the current camera handler, not merely add another listener.

**Next question:** Find interaction alternatives for players who cannot precisely drag a tiny sticker.

## 22. Precise editing without drag-only controls

**Question:** What alternatives make tiny and densely layered decals operable?

**English search / source query:** `site:w3.org WAI WCAG22 Understanding dragging movements single pointer alternative keyboard dragging`

**Evidence:** [1](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements) (primary accessibility guidance); [2](https://www.w3.org/WAI/WCAG22/Understanding/keyboard) (primary accessibility guidance).

**Finding:** W3C distinguishes keyboard access from a single-pointer alternative to dragging. Numeric controls, selection followed by destination, and activation buttons can provide alternatives without precise held-pointer movement.

**Design consequence:** Provide layer-list selection, click-to-place, labeled move/rotate/scale increments, numeric fields, keyboard nudges and accessible reorder buttons. Keep visual gizmo hit targets large even when the sticker is tiny; do not enlarge the actual printed image to make it selectable.

**Limit:** This applies accessibility principles to a native game; it does not claim WCAG certification or completed native assistive-technology testing.

**Next question:** Compare these controls with a shipped game's official livery editor workflow.

## 23. A shipped livery editor separates copy from mirror

**Question:** Which game-like editing conventions fit sponsor logos and repeated placements?

**English search / source query:** `site:gran-turismo.com gt7 manual livery editor decals flip duplicate projection depth angle`

**Evidence:** [1](https://www.gran-turismo.com/gb/gt7/manual/liveryeditor/03) (developer's official game manual).

**Finding:** Gran Turismo 7 exposes part selection, layers, fine movement, direct numeric editing, angle/depth limits and distinct opposite-side copy versus symmetric flipped copy. Some supplied logos restrict modification.

**Design consequence:** Adopt the distinction between readable opposite-side copy and deliberate artwork flip. Offer an authored part/camera shortcut, fine-adjust modifier and visible layer list. Put advanced projection limits behind receiver-safe ranges; display asset-specific allowed transformations rather than guessing from brand names.

**Limit:** The manual documents player behavior, not the game's rendering algorithm or transferable performance limits.

**Next question:** Define bounded image admission so a user-supplied sticker cannot exhaust memory before validation.

## 24. Validate image bounds before decode

**Question:** Is checking dimensions after Image.load_png_from_buffer early enough?

**English search / source query:** `libpng user limits chunk cache decompression limits; Godot Image load_png_from_buffer memory`

**Evidence:** [1](https://www.libpng.org/pub/png/libpng-1.4.0-manual.pdf) (historical library documentation); [2](https://github.com/godotengine/godot/blob/cafc17a19/drivers/png/png_driver_common.cpp) (exact pinned engine source; Git blob `7a3fe7c940b6d9d7896b34a57a42389d0f81149f`).

**Finding:** The pinned Godot PNG reader obtains header properties, allocates a decoded buffer, then finishes decoding. A post-decode application dimension check therefore cannot prevent that allocation. Libpng separately documents dimension and ancillary-chunk controls.

**Design consequence:** Before invoking the decoder, bound encoded bytes, parse signature/IHDR with checked arithmetic and validate the chunk envelope/counts and animation policy. Bound total decoded pixels and concurrent jobs; then fully decode and verify again before publishing. Keep original input separate from normalized derivatives.

**Limit:** A header preflight is not a replacement PNG decoder or a complete defense against decoder defects. Use the supported patched engine and bounded admission; no new importer is implemented here.

**Next question:** Calculate transport expansion before adding image bytes to the current bounded JSON bundle.

## 25. Portable bytes must fit the whole package

**Question:** Do sixteen individually valid image files necessarily fit the existing bundle cap?

**English search / source query:** `site:rfc-editor.org rfc4648 base64 24 bit 4 characters padding canonical encoding`

**Evidence:** [1](https://www.rfc-editor.org/rfc/rfc4648.html) (official specification).

**Finding:** Base64 encodes each three-byte group as four characters, with padding. Therefore encoded length is 4*ceil(n/3), before JSON structure or any other bundled assets.

**Design consequence:** Budget the final serialized package, aggregate image bytes and decode peak independently. Sixteen 1 MiB files require about 21.33 MiB of Base64 alone; that is not a promise they fit a 24 MiB bundle containing other data. Include each unique admitted image once and verify its content hash on a clean-install import.

**Limit:** The current closed bundle v1 has no decal-byte collection. A separately versioned bundle extension and existing-format compatibility remain implementation work.

**Next question:** Define stable visual hashes without relying on incidental JSON key order or float spelling.

## 26. Canonical visual identity and old-version preservation

**Question:** How can equal designs hash consistently while reordered layers remain different?

**English search / source query:** `site:rfc-editor.org RFC 8785 JSON canonicalization duplicate properties NaN Infinity numbers sorting`

**Evidence:** [1](https://www.rfc-editor.org/rfc/rfc8785.html) (official specification).

**Finding:** JCS defines deterministic object sorting and number serialization, rejects non-finite numbers and duplicate names, and preserves array order. A generic JSON serializer is not automatically a canonicalizer.

**Design consequence:** Reuse OpenRC's versioned identity rules, extending them explicitly for new visual data. Preserve decal array order; exclude selection/hover/cache handles. Specify finite numeric ranges, negative-zero/rotation normalization and test vectors across export/import. Keep v1–v4 bytes and historical source pins intact; create a new revision for migration.

**Limit:** This research does not mandate replacing existing hashes with JCS or claim that the study's serializer implements RFC 8785.

**Next question:** Specify what happens if a save stops halfway through publishing images and the document.

## 27. Save atomicity must be tested at failure boundaries

**Question:** What does an all-or-nothing multi-asset save need to demonstrate?

**English search / source query:** `site:sqlite.org atomiccommit crash testing atomic commit file flush directory sync`

**Evidence:** [1](https://www.sqlite.org/atomiccommit.html) (database authors' engineering documentation); [2](https://www.sqlite.org/howtocorrupt.html) (database authors' engineering documentation).

**Finding:** SQLite distinguishes atomic consistency from durable persistence and tests failures at different write stages. Renaming a file or returning from a high-level write is not itself evidence of every crash/power-loss guarantee.

**Design consequence:** Extend the existing save boundary: stage and verify admitted immutable images, then publish the referring revision only when complete. Inject failures before/after each publication step and reopen in a fresh process. Preserve the last accepted revision and raw unresolved draft; report the exact durability guarantee actually demonstrated.

**Limit:** No SQLite dependency or replacement save system is proposed. Process-crash tests alone must not be described as power-loss proof.

**Next question:** Specify worker and GPU output ownership so a late job cannot alter an accepted revision.

## 28. Revision tokens require owned outputs

**Question:** Can checking a revision number at completion prevent every stale bake write?

**English search / source query:** `site:docs.godotengine.org thread safe APIs active scene tree resources textures GPU synchronization threads`

**Evidence:** [1](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html) (official documentation).

**Finding:** Godot warns against active-scene-tree operations and concurrent mutation of shared resources from worker threads. GPU interaction can synchronize and stall even when scheduled away from the main logic.

**Design consequence:** Workers receive immutable CPU snapshots and return owned results. Each bake target belongs to one job/revision; never let an obsolete job write a texture reused by the next revision. Publish completed accepted handles on the owning thread, then retire old output only after consumers release it. Bound queue depth and temporary buffers.

**Limit:** Revision tokens alone only guard publication, not writes already made into shared GPU storage. GPU completion/lifetime behavior needs native qualification.

**Next question:** Define measurements and arithmetic that can reject impossible texture budgets before a runtime spike.

## 29. Measure full edit cost and reject impossible budgets

**Question:** Which measurements distinguish a cheap flight draw from an expensive editor pipeline?

**English search / source query:** `site:docs.godotengine.org performance monitors video memory draw calls GPU profiler compatibility visual profiler`

**Evidence:** [1](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/debugger_panel.html) (official documentation); [2](https://docs.godotengine.org/en/4.6/classes/class_performance.html) (official API documentation); [3](https://docs.godotengine.org/en/latest/tutorials/assets_pipeline/importing_images.html) (official texture guidance).

**Finding:** Godot separates rendering CPU/GPU profiling from script/physics profiling and warns that viewport resolution affects comparisons. Texture mip chains add memory beyond the base level.

**Design consequence:** Record steady flight, active drag, commit, bake/upload, save and reopen separately with frame-time tails and peak allocation. Arithmetic already rejects sixteen resident uncompressed 1024-square RGBA8 mip chains under a 32 MiB target: they require about 85.33 MiB before geometry. Sixteen 512-square chains use about 21.33 MiB, leaving limited room for other feature resources.

**Limit:** The memory figures are calculations, not profiler results; compression and actual rectangular dimensions can change them. GPU timings unavailable on a platform must be labeled unavailable, never zero.

**Next question:** Challenge the candidate renderer against a community implementation claiming very large decal counts.

## 30. A high-count community decal plugin is a different tradeoff

**Question:** Does a one-draw-call thousand-decal demo remove the need for our renderer spike?

**English search / source query:** `site:github.com/antzGames/Godot-Compatibility-Decal-Node stencil unshaded limitations MultiMesh decal`

**Evidence:** [1](https://github.com/antzGames/Godot-Compatibility-Decal-Node) (author repository and reported demo); [2](https://github.com/antzGames/Godot-Compatibility-Decal-Node/blob/main/addons/decal_compatibility/decal_instance.gdshader) (upstream source; Git blob `0554cb3c393538c75189364380666342347847dd`).

**Finding:** The author reports large instanced counts, but the inspected shader reconstructs a screen-depth position and renders unshaded with stencil exclusion. The repository limits receivers to opaque materials and does not provide normal/roughness/metallic/emission maps.

**Design consequence:** Retain it as an adversarial comparison for a bounded screen-space option, not a production dependency. A sponsor livery needs illumination, chosen receiver isolation, arbitrary image/order combinations and immutable attachment; same-image instanced bullet marks do not prove those properties.

**Limit:** The reported draw counts are the author's demo results. No OpenRC benchmark, shader correctness pass or engine-version compatibility test was performed.

**Next question:** Synthesize 11–30, then target the remaining rendering, lifecycle and product failure cases in the final thirty investigations.
