# Sequential decal Workshop investigations 31–60

Research date: **2026-11-19**. Batch 3. Each investigation below informed the next question. Search refinements and source reads within one investigation are not counted again. Findings describe evidence; design consequences are proposals. No native Godot rendering or performance qualification is claimed.

[Research index and staged synthesis](README.md) · [Machine-readable evidence ledger](evidence-ledger.json)

## 31. Screen-depth reconstruction is renderer-specific

**Question:** What must a screen-space alternative get right across Godot backends?

**English search / source query:** `site:docs.godotengine.org advanced post processing reverse z compatibility NDC depth texture reconstruct position`

**Evidence:** [1](https://docs.godotengine.org/en/latest/tutorials/shaders/advanced_postprocessing.html) (official documentation).

**Finding:** Depth samples are nonlinear and reconstruction requires the inverse projection. Godot documents different normalized depth-coordinate ranges for Compatibility versus Mobile/Forward+, and limits depth-texture access to the current viewport.

**Design consequence:** If a screen-space comparison is built, explicitly branch by renderer convention and test near/far planes, camera-inside-volume, orthographic/perspective views and preview versus flight viewport. Keep this complexity outside the default CPU mesh projection unless evidence justifies it.

**Limit:** A working shader in one demo viewport does not validate the pinned engine, another camera projection or cross-viewport sampling.

**Next question:** Verify the camera APIs used for precise placement rays and viewport coordinate conversion.

## 32. Use the preview camera's complete placement ray

**Question:** Will a ray built from camera position work for every editor view?

**English search / source query:** `site:docs.godotengine.org Camera3D project_ray_origin project_ray_normal orthogonal perspective viewport`

**Evidence:** [1](https://docs.godotengine.org/en/4.7/classes/class_camera3d.html) (official API documentation).

**Finding:** Camera3D exposes both projected ray origin and normal from viewport coordinates. These APIs account for the camera projection rather than assuming a fixed origin and a screen-derived direction.

**Design consequence:** Convert pointer coordinates to the actual SubViewport pixel rectangle, then use both project_ray_origin and project_ray_normal. Reject points outside the rendered rectangle and qualify scaling/letterboxing, resized panels and any orthographic preset. Do not reuse outer-window coordinates directly.

**Limit:** This is the API contract; native picking still needs comparison with known geometric hit points on both aircraft families.

**Next question:** Keep sticker rotation stable when the placement normal approaches the editor's chosen up vector.

## 33. Stable roll while moving over a curved surface

**Question:** Why can a sticker suddenly spin when its normal becomes nearly vertical?

**English search / source query:** `site:docs.godotengine.org Basis looking_at up collinear unstable flips vector parallel`

**Evidence:** [1](https://docs.godotengine.org/en/4.5/classes/class_basis.html) (official API documentation).

**Finding:** Basis.looking_at warns that target and up vectors should not be collinear because the roll becomes unstable. Reconstructing orientation from a normal and one fixed global up vector has a singular case.

**Design consequence:** Use the authored receiver tangent as the initial orientation reference; during a continuous gesture, project the previous tangent into the new tangent plane and use a deterministic receiver-axis fallback when degenerate. Persist the accepted local frame and explicit user rotation. Reject abrupt region jumps instead of silently spinning the mark.

**Limit:** This is a proposed continuity rule. It needs a closed-path/pole-crossing fixture and cannot guarantee distortion-free transport over arbitrary surfaces.

**Next question:** Specify opposite-side mapping in authored local coordinates rather than assuming every aircraft mirrors about world X.

## 34. An authored symmetry frame, not a world-axis guess

**Question:** How can opposite-side copy remain correct on imported, rotated or asymmetric parts?

**English search / source query:** `site:docs.blender.org manual mirror modifier local axes mirror object UV flip`

**Evidence:** [1](https://docs.blender.org/manual/en/4.0/modeling/modifiers/generate/mirror.html) (official authoring-tool documentation).

**Finding:** Blender separates the geometry mirror plane, defined in an object's local frame, from UV flipping. Mirroring position does not inherently mean mirroring texture coordinates.

**Design consequence:** Store authored paired-receiver transforms and a defined symmetry plane in the visual companion. Map the placement frame into the paired receiver, rebuild a valid tangent basis, and preserve readable artwork unless the player explicitly selects a permitted UV flip. Offer no paired-copy action when the pairing is absent or incompatible.

**Limit:** This does not infer symmetry from aircraft naming or make every imported part symmetric. Pair mappings require source-pipeline qualification.

**Next question:** Check the actual Godot render-priority API before proposing a dense overlay ordering implementation.

## 35. Bounded material priority is not a depth override

**Question:** Can the proposed 64-layer overlay use a real ordering primitive without hiding occlusion errors?

**English search / source query:** `Godot Material render_priority -128 127 transparent opaque depth testing`

**Evidence:** [1](https://github.com/godotengine/godot/blob/cafc17a19/doc/classes/Material.xml) (exact pinned engine API source; Git blob `e03682acb915cf712700f28e9e8286817027dae6`); [2](https://docs.godotengine.org/en/4.6/tutorials/3d/standard_material_3d.html) (official documentation).

**Finding:** The pinned Material API bounds priority to -128…127 and separates opaque/transparent queues; next_pass does not guarantee immediately adjacent draws. Standard-material guidance states that depth testing overrules priority.

**Design consequence:** The overlay spike should use a deliberately allocated bounded priority range, per-order material wrappers, depth testing enabled, and no decal depth writes. Validate interaction with existing markings and other transparency. Reorder must update all affected ordering/cache dependencies; never disable depth tests to make a layering screenshot pass.

**Limit:** Available priority values make the candidate implementable, not proven correct at grazing angles or across renderers.

**Next question:** Choose an offset strategy that avoids z-fighting without making a stack visibly float above the aircraft.

## 36. Surface bias must not become layer thickness

**Question:** How should an overlay avoid depth artifacts at near and distant views?

**English search / source query:** `site:dev.epicgames.com using mesh decals depth precision LOD offset geometry intersect`

**Evidence:** [1](https://dev.epicgames.com/documentation/unreal-engine/using-mesh-decals-in-unreal-engine?lang=en-US) (official method documentation).

**Finding:** Epic's mesh-decal guidance calls out matching receiver geometry, small depth bias and failures caused by LOD or long-distance precision. Surface proximity is a real constraint even for a dedicated mesh-decal system.

**Design consequence:** Qualify one bounded receiver-scale-aware surface offset for visibility, with layer order handled separately. Do not move layer N outward by N times an epsilon: many layers would float or cross thin parts. Test silhouette, far distance and model-size extremes; reject the candidate if stable appearance requires excessive offset.

**Limit:** Unreal's mesh decal is a specialized renderer path, not equivalent to a Godot transparent mesh. The source establishes a failure mode, not a portable bias constant.

**Next question:** Determine whether merging or instancing stickers preserves the required order.

## 37. Batching must respect compositing dependencies

**Question:** Can repeated sponsor artwork always be combined into one instanced draw?

**English search / source query:** `site:docs.godotengine.org MultiMesh instances individual culling sorting transparency one object AABB`

**Evidence:** [1](https://docs.godotengine.org/en/4.5/classes/class_multimesh.html) (official API documentation).

**Finding:** MultiMesh repeats one mesh efficiently and is spatially treated as one object. That API advantage does not establish arbitrary per-instance layer order or support differently clipped receiver geometry.

**Design consequence:** Share immutable image resources immediately, but batch geometry only after proving compositing equivalence. A layer order A–B–A cannot be regrouped by image as A–A–B when the regions overlap. Prefer contiguous compatible runs or a qualified compositor; record draw-count savings and lost culling granularity.

**Limit:** This is a correctness restriction on optimization, not a claim that all instancing is unsuitable. Nonoverlapping identical geometry may qualify.

**Next question:** Test whether screen coverage, rather than count alone, dominates the worst case.

## 38. Screen coverage and overdraw are independent of layer count

**Question:** Which 64-sticker arrangement is a meaningful worst case?

**English search / source query:** `site:docs.godotengine.org optimizing 3D performance transparency fill rate overdraw screen resolution`

**Evidence:** [1](https://docs.godotengine.org/en/latest/tutorials/performance/gpu_optimization.html) (official performance guidance).

**Finding:** Godot's GPU guidance explains that overlapping blended geometry may shade the same pixel repeatedly and is particularly sensitive to fill rate. Small separated objects and large overlapping ones stress different costs.

**Design consequence:** Benchmark a coverage-by-overlap matrix: tiny separated, large separated, and large stacked marks at fixed counts and actual output pixels. Keep alpha footprints tight where source-safe derivatives allow it, but retain logical image bounds and aspect. A one-draw-call result must still pass GPU time and visual order checks.

**Limit:** No fixed hardware speedup or mobile-device compatibility claim follows from this general guidance.

**Next question:** Check whether compressed image files automatically provide compressed GPU storage.

## 39. PNG file compression does not establish GPU memory usage

**Question:** Can smaller PNG files satisfy the proposed GPU budget for runtime sponsor images?

**English search / source query:** `site:docs.godotengine.org ImageTexture CompressedTexture2D PNG VRAM compression runtime Image create_from_image`

**Evidence:** [1](https://docs.godotengine.org/en/stable/classes/class_compressedtexture2d.html) (official Godot documentation, stable snapshot); [2](https://docs.godotengine.org/en/stable/classes/class_imagetexture.html) (official Godot documentation, stable snapshot).

**Finding:** Godot distinguishes compressed storage from GPU-compressed texture formats. Runtime ImageTexture creation and the import pipeline are different paths; a compact lossless source does not imply a compact resident texture.

**Design consequence:** Keep encoded-byte, decoded-pixel and resident-texture budgets separate. Start runtime artwork estimates with actual RGBA8 dimensions and mip levels; only credit GPU compression after the exact runtime path and logo quality are qualified on each target renderer.

**Limit:** Documentation establishes resource semantics, not the selected 4.8 beta device's allocation or compression quality. Runtime codec support and peak temporary copies remain measurement gates.

**Next question:** Does retaining a ViewportTexture freeze a saved design, or does it remain tied to a mutable render target?

## 40. A live viewport texture is not a frozen saved design

**Question:** Can the Workshop pass a viewport texture directly into a frozen trial or saved thumbnail?

**English search / source query:** `site:docs.godotengine.org ViewportTexture dynamic texture get_image ImageTexture create_from_image scene local`

**Evidence:** [1](https://docs.godotengine.org/en/stable/classes/class_viewporttexture.html) (official Godot documentation, stable snapshot); [2](https://docs.godotengine.org/en/latest/tutorials/rendering/viewports.html) (official Godot documentation, latest snapshot).

**Finding:** A ViewportTexture follows its viewport dynamically. Image capture requires a completed render; conversion to a separate ImageTexture has readback cost. HDR capture also has a different encoding contract.

**Design consequence:** Accepted trial snapshots retain immutable document/assets and owned completed outputs, never the editor's mutable viewport target. If a compositor is selected, capture only at an explicit completion boundary, with known color encoding, and keep the producer alive until consumers release it.

**Limit:** This defines lifetime requirements; it does not mandate CPU readback for every freeze or prove completion timing on the pinned renderer. Measure a retained owned GPU target versus an explicit copy.

**Next question:** Can the engine's JSON parser alone enforce the strict portable-document format?

## 41. Parser success is not strict document admission

**Question:** Does a successful JSON.parse prove that a portable sticker document satisfies the intended canonical format?

**English search / source query:** `site:docs.godotengine.org JSON parser trailing commas invalid unicode newline specification`

**Evidence:** [1](https://docs.godotengine.org/en/latest/classes/class_json.html) (official Godot documentation, latest snapshot).

**Finding:** Godot documents permissive parsing behavior for trailing commas, string control characters, number conversion and some Unicode errors. Successful parsing is therefore a different property from a strict, unambiguous admitted document.

**Design consequence:** For the new format, validate raw-byte/UTF-8/structural limits and duplicate-key policy before information is lost, then exact schema, finite bounded values and identity. Reuse the project's admission conventions; do not silently tighten legacy readers or use native-object deserialization for imported artwork.

**Limit:** Duplicate-key handling and exact parser edge behavior still require pinned-engine cases. This research does not claim a new strict parser already exists or justify replacing legacy serialization.

**Next question:** How do resource-cache modes interact with replacing image files and retained trial references?

## 42. Cache replacement can mutate a resource retained by another consumer

**Question:** Will replacing the image at one path preserve a previously accepted trial's appearance?

**English search / source query:** `site:docs.godotengine.org ResourceLoader CACHE_MODE_REPLACE refresh existing instances CACHE_MODE_IGNORE_DEEP`

**Evidence:** [1](https://docs.godotengine.org/en/latest/classes/class_resourceloader.html) (official Godot documentation, latest snapshot).

**Finding:** Godot's replacement cache mode can refresh existing resource instances in place. Ordinary ignore mode does not recursively isolate external dependencies; deep modes have distinct behavior.

**Design consequence:** Use content-addressed immutable artwork revisions and explicit consumer ownership. A changed logo gets a new identity/cache key; never overwrite accepted bytes or use replacement mode as a universal refresh mechanism. Include processing version and renderer-relevant settings in derived keys.

**Limit:** This does not prohibit sharing immutable textures. Runtime PNG admission can bypass ResourceLoader; the rule still applies to any mutable texture or material retained by multiple consumers.

**Next question:** Which references keep image content alive after deletion from the current visible layer stack?

## 43. Undo and in-flight imports are asset-retention roots

**Question:** When is it safe to reclaim a sticker image after its last visible layer is deleted?

**English search / source query:** `site:git-scm.com docs git gc prune reachable reflogs concurrent processes deletion objects`

**Evidence:** [1](https://git-scm.com/docs/git-gc) (official Git documentation; lifecycle analogy, not game implementation).

**Finding:** Git's content-addressed object cleanup accounts for historical references and warns about objects used by concurrent writers before references are published. This supplies a concrete counterexample to treating the visible current state as the only owner.

**Design consequence:** Define roots for saved documents, current draft, bounded undo/redo history, recovery, frozen trial, in-flight import and generation jobs. Reclaim generated caches separately from original assets; only collect unreferenced originals at a coordinated maintenance boundary with pending jobs protected.

**Limit:** This is an explicit architectural inference. OpenRC does not need Git or its expiration durations at runtime, and a full garbage collector is unnecessary until owned asset storage is implemented.

**Next question:** Which of these image-admission and storage mechanisms already exist in OpenRC's custom-skin implementation?

## 44. Reuse OpenRC's pre-decode admission rather than creating a parallel image loader

**Question:** Which required protections already exist, and what is genuinely new for sticker images?

**English search / source query:** `Repository code inspection: app/aircraft/custom_skin.gd — _png_dimensions, _inspect, _unique_json_keys, _zip_directory, import_file`

**Evidence:** [1](https://github.com/bultodepapas/OpenRCsimulator/blob/0d251cb070a280bab6d6a3251af7955ed0bbec74/app/aircraft/custom_skin.gd) (OpenRC source pinned at branch commit; Git blob `bf01437796b953d45aff600365141f64db776ccc`).

**Finding:** The existing custom-skin path bounds ZIP entries and expanded bytes, checks UTF-8 and duplicate fields, inspects PNG dimensions/chunk bounds and aggregate pixels before decoding, rejects compressed metadata chunks, verifies decoded dimensions, creates mipmaps and publishes immutable archives. Its PNG scan does not explicitly reject APNG control chunks.

**Design consequence:** Extract or reuse a reviewed common admission helper with regression parity for .orskin. Add sticker-specific aggregate resident/temporary allocation limits, explicit still-image policy, bounded concurrency and original-byte identity; cover APNG and critical-chunk/CRC behavior through actual decoder cases.

**Limit:** This is a source audit, not a finding that current imports are exploitable. PNG structural scanning is not a full decoder, and different existing skin limits must not be silently replaced by the smaller sticker policy.

**Next question:** How will a portable sticker design carry a custom .orskin base that the receiving installation does not already have?

## 45. Portable designs must account for custom base archives as well as sticker images

**Question:** Will a sticker design reconstruct its appearance on a fresh installation with no local custom paint?

**English search / source query:** `Repository code inspection: app/workshop/bundle.gd — BUNDLE_KEYS, MAX_BUNDLE_BYTES, decode, import_variant; custom_skin.gd archive identity`

**Evidence:** [1](https://github.com/bultodepapas/OpenRCsimulator/blob/0d251cb070a280bab6d6a3251af7955ed0bbec74/app/workshop/bundle.gd) (OpenRC source pinned at branch commit; Git blob `e3501c768a7333392034be76c5de08ca0b3dd827`); [2](https://github.com/bultodepapas/OpenRCsimulator/blob/0d251cb070a280bab6d6a3251af7955ed0bbec74/app/aircraft/custom_skin.gd) (OpenRC source pinned at branch commit; Git blob `bf01437796b953d45aff600365141f64db776ccc`).

**Finding:** Bundle v1 contains physical base snapshot bytes and a presentation profile, but no custom-paint archive or sticker image payload. The .orskin reader separately permits archives up to 32 MiB. Existing bundles already call the project's StrictJSON helper.

**Design consequence:** Design v2 with explicit visual dependency records: exact .orskin archive hash/bytes when distributable, admitted sticker bytes and built-in revision references. Compute the total before export; a locally valid large skin can still exceed the portable package policy. Distinguish self-contained export from an explicitly dependency-requiring reference, and never silently substitute factory paint. Reuse StrictJSON for new bounded JSON.

**Limit:** No new bundle format or higher byte cap is approved here. Tests must include fresh-install import, unavailable or modified base, oversized combined payload and failure after staging before manifest publication.

**Next question:** Can old customized profiles still pass current source-bound validation after the new decal renderer is added?

## 46. Legacy read compatibility requires preserving source proof paths, not only JSON bytes

**Question:** What implementation route preserves both the identity and usability of old customized profiles?

**English search / source query:** `Repository code inspection: presentation.gd validate/bindings_sha256; aircraft_customization.gd validate_bindings; presentation_sources.gd closed source set; presentation_rebind.gd propose`

**Evidence:** [1](https://github.com/bultodepapas/OpenRCsimulator/blob/0d251cb070a280bab6d6a3251af7955ed0bbec74/app/workshop/presentation.gd) (OpenRC source pinned at branch commit; Git blob `7c47fa9b17bc62a7ce6a212e6a476b6f68b79310`); [2](https://github.com/bultodepapas/OpenRCsimulator/blob/0d251cb070a280bab6d6a3251af7955ed0bbec74/app/render/aircraft_customization.gd) (OpenRC source pinned at branch commit; Git blob `94c0b69236fd118d2609067d4c80d7accdaae49f`); [3](https://github.com/bultodepapas/OpenRCsimulator/blob/0d251cb070a280bab6d6a3251af7955ed0bbec74/app/workshop/presentation_rebind.gd) (OpenRC source pinned at branch commit; Git blob `3c4fe55b24a300594db5418786e82f6bfd0945c9`); [4](https://github.com/bultodepapas/OpenRCsimulator/blob/0d251cb070a280bab6d6a3251af7955ed0bbec74/app/render/presentation_sources.gd) (OpenRC source pinned at branch commit; Git blob `b3d6785caa34588200bb2ab245085597be61dd03`); [5](https://github.com/bultodepapas/OpenRCsimulator/blob/0d251cb070a280bab6d6a3251af7955ed0bbec74/app/addons/aircraft_contract/export_plugin.gd) (OpenRC pinned exporter source; final integration review follow-up; Git blob `0a8f1702dd70ffb5e48d40c87b3e66104f73e29a`); [6](https://github.com/bultodepapas/OpenRCsimulator/blob/0d251cb070a280bab6d6a3251af7955ed0bbec74/app/main.gd) (OpenRC pinned consumer source; final integration review follow-up; Git blob `228728daa62c25ffc8d85543825f84871aa9875b`); [7](https://github.com/bultodepapas/OpenRCsimulator/blob/0d251cb070a280bab6d6a3251af7955ed0bbec74/app/ui/workshop_preview.gd) (OpenRC pinned consumer source; final integration review follow-up; Git blob `1651140f3d4c5ac8e5fae95cc37a5ba09c9badd0`).

**Finding:** The closed presentation proof includes presentation.gd itself as well as the customization renderer. Changing either invalidates existing proof hashes. Current rebind creates a proposal and refuses some smoke-bearing records; it is not universal backward compatibility.

**Design consequence:** Preferred first slice: preserve existing proof-covered source bytes/companions and add a separate v5 envelope/facade, receiver registry and decal renderer. The envelope retains an exact validated v1–v4 base profile, while new visual base/stack identity is separate. Route non-proof-covered store/trial/bundle/UI consumers through the facade and project the embedded legacy profile into unchanged legacy rendering. If that cannot work, require a fully qualified versioned source package before shipping; do not silently rehash or rebind old saves.

**Limit:** This is an implementation proposal requiring a full dependency/call-site audit and exported-package tests. Compatibility with every historical app release is not claimed. Untouched legacy fixtures must remain usable at the audited baseline; missing old dependencies stay explicit. Final review also verified that the existing exporter accepts one legacy source-proof generation; v5 needs a separate marker, and every root-field legacy consumer needs a validated projection. Preserve baseline-admitted records, not an unsupported promise about all historical or older-app readers.

**Next question:** Will separately rendered overlays choose the same automatic LOD as the surface they decorate?

## 47. Matching LOD labels does not synchronize separately rendered surfaces

**Question:** Can an overlay with its own bounds simply use the receiver's LOD names and bias?

**English search / source query:** `site:docs.godotengine.org mesh LOD screen threshold lod_bias MeshInstance3D distance screen size`

**Evidence:** [1](https://docs.godotengine.org/en/latest/tutorials/3d/mesh_lod.html) (official Godot documentation, latest snapshot).

**Finding:** Godot's automatic selection depends on screen-space metrics, per-viewport thresholds and the nearest point of each instance's bounds. An overlay is a different instance with different geometry and bounds; equal labels or bias values do not establish equal selection.

**Design consequence:** Require a concrete shared LOD owner/selection mechanism, or a demonstrated geometry-invariant overlay over every accepted receiver LOD. Do not assert synchronization by copying thresholds. Qualify threshold crossings in both directions, near/far views, output resolutions, quality changes and secondary viewports before exposing the receiver.

**Limit:** The tutorial is not proof that a public per-instance selected-LOD API exists on the pinned beta. Backend/receiver qualification must resolve that implementation detail; fixing the editor to one LOD does not solve flight.

**Next question:** What precisely destroys or repartitions the target meshes when an aircraft becomes a wreck?

## 48. Wreck sections replace mesh owners and reindex their attributes

**Question:** Will a decal child automatically follow the correct wreck fragment?

**English search / source query:** `Repository code inspection: app/render/crash/section_splitter.gd — split, _subset, _find_mapped`

**Evidence:** [1](https://github.com/bultodepapas/OpenRCsimulator/blob/0d251cb070a280bab6d6a3251af7955ed0bbec74/app/render/crash/section_splitter.gd) (OpenRC source pinned at branch commit; Git blob `f14551f99bc7d69a63baabdde0829f22c0c3fe6d`).

**Finding:** The splitter creates sibling meshes with section metadata, copies the source transform and active materials, remaps vertex arrays, then removes and frees the original mesh node. It does not preserve arbitrary children or provide their destination mapping.

**Design consequence:** Own decal lifetime outside the disappearing mesh. Prepare a receiver-to-section mapping and reclip/rebind owned fragments at the wreck transition, before or after splitting at a defined hook with preserved source data. A section-spanning sticker can become multiple fragments sharing one document-layer ID; never infer destination from new vertex indices.

**Limit:** Source reading establishes the replacement event, not the best integration hook. Wreck grouping, bounds, collision consumers and reset teardown need their own tests; applying crash_no_bounds alone is insufficient.

**Next question:** Which exact identity boundary must remain unchanged for a purely cosmetic sticker edit?

## 49. The existing trial already separates visual identity from physical compilation

**Question:** What invariant can prove that placing or rotating a sponsor logo does not change flight behavior?

**English search / source query:** `Repository code inspection: app/workshop/trial.gd — freeze, trial_id, resolved_sha256, presentation_identity; dependencies.gd closed manifest`

**Evidence:** [1](https://github.com/bultodepapas/OpenRCsimulator/blob/0d251cb070a280bab6d6a3251af7955ed0bbec74/app/workshop/trial.gd) (OpenRC source pinned at branch commit; Git blob `4f14a5b09cc3b14f6c0ef24b6b09a5d1f3ad0633`); [2](https://github.com/bultodepapas/OpenRCsimulator/blob/0d251cb070a280bab6d6a3251af7955ed0bbec74/app/workshop/dependencies.gd) (OpenRC source pinned at branch commit; Git blob `82bed6dcd1ade24193c99b070c3a810505481b0f`).

**Finding:** Trial.freeze constructs the physical trial ID from base, recipe, descriptor, family/model, dependency and compiler identities. Presentation profile identity is constructed separately. Physical dependency admission is a closed set rather than a general visual asset bag.

**Design consequence:** Keep logo, receiver and visual-base dependencies in the visual identity path. With the physical recipe and aircraft scale fixed, native metamorphic cases change decal position/size/rotation/flip/order/image or a compatible visual base while compiled raw bytes, trial ID, model hash, solver inputs and crash geometry/grouping remain identical. A changed canonical visual document must change composite identity; require changed pixels only in discriminating visible asymmetric, colored-alpha-overlap or genuinely different-base fixtures. Do not add visual files to the physical dependencies manifest.

**Limit:** Source separation does not prove isolation after new integration. Scene-derived crash bounds or collision construction can still introduce a side effect even if compilation hashes are unchanged.

**Next question:** Which numerical failure cases should the clipping exercises cover beyond ordinary inside/outside triangles?

## 50. Near-degenerate geometry needs explicit numerical policy

**Question:** Can ordinary floating-point signs and one arbitrary epsilon reliably decide clipping boundaries?

**English search / source query:** `Shewchuk robust adaptive precision geometric predicates floating point orientation near zero official`

**Evidence:** [1](https://www.cs.cmu.edu/~quake/robust.html) (author's computational-geometry research page).

**Finding:** Orientation decisions near zero can change under rounding; robust predicates adapt precision to uncertainty. That result cautions against treating all sign/area tests as exact just because ordinary examples pass.

**Design consequence:** Specify tolerances in receiver-local units, reject singular frames and repeated/degenerate output, and exercise on-plane, nearly parallel, grazing and very small/large scale cases. Check 3D area and projected UV area independently. Use exact/rational known cases as oracles; evaluate a robust-predicate dependency only if bounded receiver tests demonstrate a need.

**Limit:** The paper does not solve decal clipping, choose OpenRC tolerances or prove the included float exercises robust for all inputs. No new geometry dependency is selected.

**Next question:** How should authored region membership survive UV seams without welding across physical gaps or hinges?

## 51. Authored face regions are different data from UV seam topology

**Question:** Can paintable-region membership be derived safely from UV islands or coincident vertices?

**English search / source query:** `site:docs.blender.org manual geometry attributes face corner UV map seam attribute domain`

**Evidence:** [1](https://docs.blender.org/manual/en/5.0/modeling/geometry_nodes/attributes_reference.html) (official Blender 5.0 manual); [2](https://docs.blender.org/manual/en/3.1/modeling/geometry_nodes/attributes_reference.html) (official Blender 3.1 attribute-domain explanation; conceptual reference).

**Finding:** The authoring model distinguishes face, point and face-corner attributes; UV data and seam boundaries are separate from physical surface identity. A render-vertex split does not by itself identify an unpaintable boundary.

**Design consequence:** Generate explicit face/triangle region and rigid-owner records from the aircraft's authoring pipeline, with a source identity. Any seam-crossing adjacency must be authored or validated within that region; do not globally weld coincident vertices. Preserve allowed UV-seam crossing while rejecting gaps, opposite skins and hinge neighbors.

**Limit:** This does not assume Blender attributes automatically survive glTF import or procedural regeneration. The pipeline must emit and validate its own companion mapping after export/index changes.

**Next question:** How should selecting an existing sticker behave when its image contains transparent holes?

## 52. Visible-pixel selection and geometric ray hits are different editor behaviors

**Question:** Should a click through a transparent logo corner select that logo or the layer beneath it?

**English search / source query:** `site:discourse.threejs.org raycast transparent texture pixel alpha decals selection`

**Evidence:** [1](https://discourse.threejs.org/t/how-to-get-texture-color-at-intersection-with-raycast/38631) (firsthand developer question and implementation discussion); [2](https://discourse.threejs.org/t/how-to-ignore-the-transparent-part-of-sprite-by-ray-pickup/7773) (firsthand developer forum discussion).

**Finding:** Developers distinguish geometric intersection from evaluating the image's alpha at the hit UV. The forum examples expose an interaction policy decision; a transparent mesh is not automatically absent from picking.

**Design consequence:** Keep surface placement raycasts separate from existing-layer selection. For the latter, define topmost visible-alpha hit behavior using a bounded cached CPU alpha mask and the same UV flips/transforms, plus a layer-list and cycle-selection escape hatch for tiny or fully covered stickers. Avoid per-pointer GPU readback.

**Limit:** These are scoped three.js discussions, not Godot guarantees or a copied implementation. Alpha threshold, filtering tolerance and accessibility behavior need product tests; the exact rendered pixel may differ from a simplified CPU mask.

**Next question:** What input alternatives make the editor usable with a gamepad and without precise dragging?

## 53. Gamepad editing needs discrete actions and visible focus

**Question:** How can game-like placement remain fully usable without holding and dragging precisely?

**English search / source query:** `site:learn.microsoft.com gaming accessibility guidelines input navigation single input remap hold drag`

**Evidence:** [1](https://learn.microsoft.com/en-us/xbox/accessibility/xbox-accessibility-guidelines/107) (official Xbox accessibility guidance); [2](https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/112) (official Xbox UI navigation guidance).

**Finding:** Xbox guidance favors action remapping, equivalent digital alternatives and navigation with single nonsimultaneous inputs. Consistent focus and input behavior matter across menu and in-game controls.

**Design consequence:** Expose Move, Size, Rotate, Flip, Duplicate, Order, Confirm and Cancel as named actions with visible focus and button hints. Provide toggled adjustment modes, numeric fields and discrete nudges; use current input mappings in hints. Test a complete select/place/edit/save/cancel flow with keyboard only and gamepad only.

**Limit:** This is design guidance, not a claim of Xbox certification or support for every device. Reuse OpenRC's existing input system and keep flight input inactive while the editor owns focus.

**Next question:** How should snapping and fine adjustment work without jumping the sticker when a mode changes?

## 54. Snapping, fine speed and numeric input should remain distinct controls

**Question:** How can players make both quick large adjustments and precise small ones without unwanted jumps?

**English search / source query:** `site:docs.blender.org manual snapping increment absolute grid transform precision numeric input`

**Evidence:** [1](https://docs.blender.org/manual/en/3.2/scene_layout/object/editing/transform/control/precision.html) (official Blender 3.2 interaction manual).

**Finding:** Blender distinguishes discrete snapping from fine transform speed, and shows the transform magnitude. These are complementary modes rather than one ambiguous precision toggle.

**Design consequence:** Offer explicit normal/fine step controls, optional angle snapping and editable values. Proposed starting increments: rotation 15°/1°, size 5%/1%, movement receiver-relative with displayed centimeters. Preserve the current transform as the adjustment origin when modes switch; apply one committed gesture to history. Validate step sizes with actual aircraft scales before fixing defaults.

**Limit:** OpenRC values are design proposals, not Blender requirements or usability results. Avoid mandatory modifier chords; snap behavior and camera-independent units must be described in the UI.

**Next question:** Which repeated-logo workflow is worth adopting from real livery editors without expanding the first slice into a full vector-art package?

## 55. Repeated-logo workflows benefit from direct layer commands and stable selection

**Question:** Which friction in real livery editors should the first OpenRC interaction slice avoid?

**English search / source query:** `site:forums.forza.net livery editor group vinyl layers duplicate insert saved vinyl groups tutorial`

**Evidence:** [1](https://forums.forza.net/t/solved-and-explain-easily-move-layers-up-or-down/820136) (firsthand player workflow on official Forza forums); [2](https://forums.forza.net/t/vinyl-editor-qol-improvement-for-groups/813916) (firsthand feature request on official Forza forums).

**Finding:** Players describe indirect copy/delete/insert workarounds for ordering and lost context while editing groups. These reports identify discoverability and selection-state problems, not measured prevalence across the audience.

**Design consequence:** Provide visible Duplicate/Stamp, Move Up/Down, Top/Bottom, Hide and Delete commands with persistent layer selection and thumbnail/name. Duplicate creates a new instance ID but shares immutable image content. Start with independent sponsor instances; treat saved groups, masks and group opacity as a later feature with its own semantics.

**Limit:** The forum posts are individual reports and suggestions, not an official current feature specification. OpenRC should validate the proposed workflow with actual users rather than copy every requested Forza feature.

**Next question:** How should asset files carry provenance and usage metadata without pretending all repository files share one license?

## 56. Binary logo files need per-asset provenance separate from the code license

**Question:** How can original sponsor artwork and generated runtime derivatives retain reviewable provenance?

**English search / source query:** `site:reuse.software specification binary files license sidecar .license SPDX copyright`

**Evidence:** [1](https://reuse.software/faq/) (official REUSE file-metadata guidance); [2](https://reuse.software/spec-3.3/) (REUSE 3.3 specification).

**Finding:** REUSE describes associating licensing information with individual files, including sidecar metadata for binary assets. Repository-level code licensing is not a substitute for records about third-party images.

**Design consequence:** Keep source URL, retrieval date, exact original hash, actual media type, derivative recipe/hash and usage status linked to each catalog entry. Record known terms accurately and leave unknown terms unresolved; never relabel a logo with the project's code license. Runtime catalog promotion remains a deliberate per-asset operation.

**Limit:** This investigation defines metadata practice, not permission to distribute any particular mark. The existing research catalog remains separate from a production-approved sponsor catalog.

**Next question:** Do official brand instructions impose constraints on the requested rotation, flip, recoloring or stretching controls?

## 57. Catalog transform permissions are per asset, not a universal logo switch

**Question:** Can every official logo automatically support the same flip, stretch and recolor operations as a test sticker?

**English search / source query:** `site:openai.com brand guidelines logo rotate stretch alter`

**Evidence:** [1](https://openai.com/brand/) (official brand design guidelines retrieved 2026-11-19).

**Finding:** OpenAI's published example allows proportional wordmark scaling while prescribing unchanged proportions, approved forms and usage conditions. The source does not establish OpenRC's sponsorship status or a blanket permission for a game decal.

**Design consequence:** Keep the generic editor capable of movement, proportional size, rotation and explicit flips, and carry reviewed per-asset capabilities/variants in the catalog. Preserve aspect by default; do not automatically grant recolor, distortion or mirrored lettering to every external brand. Demonstrate unrestricted mechanics with project-owned/test art while production promotion resolves the intended sponsor artwork.

**Limit:** This is a specific example of machine-readable catalog requirements, not legal advice or a conclusion about other brands. Existing private arrangements are neither inferred from public logos nor reproduced in this report.

**Next question:** What should a trusted offline vector-to-raster pipeline preserve so runtime PNGs do not subtly change the logo?

## 58. Pin the offline rasterizer and font inputs for faithful logo derivatives

**Question:** What can make an official SVG render differently on another developer's machine?

**English search / source query:** `site:github.com/linebender/resvg text font database external resources render SVG png deterministic`

**Evidence:** [1](https://github.com/linebender/resvg/blob/main/README.md) (upstream renderer README, dated snapshot; Git blob `97cbd0bc4810baa1cb8b0a1a72c2fd45dec73095`); [2](https://github.com/linebender/resvg/blob/main/crates/resvg/src/main.rs) (upstream CLI source, dated snapshot).

**Finding:** resvg targets static SVG and reproducible rasterization while exposing font-loading controls. Reproducibility requires the same source and rendering inputs; system-font fallback and renderer changes can affect artwork.

**Design consequence:** Keep official vector originals unchanged, rasterize only in a trusted offline build with a pinned tool/version, explicit fonts or approved outlined source, fixed canvas/aspect and no unintended external dependencies. Record transparent padding, color/alpha processing and output hash. Compare the derivative visually with the original before runtime promotion.

**Limit:** No new rasterizer dependency is installed or claimed superior here. The current pack retains original sources; arbitrary player SVG remains outside the first runtime import format.

**Next question:** Can a dynamic visibility-based atlas improve memory without changing saved identity or silently degrading important sponsor logos?

## 59. Visibility-driven atlases are a conditional cache strategy, not a new save format

**Question:** What can OpenRC learn from a developer's large decal showcase without importing its performance claims?

**English search / source query:** `Follow-up to investigation 52: How to draw stuff on stuff — dynamic atlas visibility caching fallback scaling clustered decals`

**Evidence:** [1](https://discourse.threejs.org/t/how-to-draw-stuff-on-stuff/48934) (firsthand implementation showcase, author-reported results).

**Finding:** The author describes visibility-driven atlas residency, worker decoding and downscaling when full, within a custom clustered renderer. The published high-count example uses a flat scene and does not establish OpenRC's renderer, ordered-overlap or aircraft cost.

**Design consequence:** Retain the useful separation of authoritative image bytes from evictable derived residency. If atlas pressure becomes measured, repack into an owned generation and atomically publish all affected UV/material references. Texture tier is explicit and reproducible; saved scale, artwork hash and ordering never change to satisfy a cache policy.

**Limit:** No demo was executed and no reported decal-count or draw-call claim is adopted as an OpenRC benchmark. A clustered renderer replacement remains outside this feature's first slice.

**Next question:** What evidence protocol will distinguish a viable native backend from attractive but noncomparable demos?

## 60. Qualify backend choices with repeatable matched workloads

**Question:** What measurement protocol makes the final renderer decision defensible?

**English search / source query:** `site:google.github.io/benchmark user guide warmup repetitions random interleaving real time`

**Evidence:** [1](https://google.github.io/benchmark/user_guide.html) (official Google Benchmark methodology documentation); [2](https://google.github.io/benchmark/random_interleaving.html) (official benchmark methodology; analogy to native scene runs).

**Finding:** Benchmark guidance separates warmup from measured samples, repeats runs, distinguishes CPU from elapsed time and can interleave alternatives to reduce changing-system-state bias. A single appealing demo or average FPS is insufficient evidence.

**Design consequence:** Use matched empty/decorated aircraft scenes with fixed engine commit, renderer, host, output pixels, camera path, lighting and assets. Report cold construction separately from warmed steady frames, repeat/interleave runs, retain raw samples and p50/p95/p99, CPU/GPU availability, memory peaks and captures. Select the simplest backend passing appearance, lifecycle and budget gates; stop comparison when those gates are resolved.

**Limit:** Google Benchmark is not a Godot GPU profiler and is not added as a dependency. Proposed run counts/durations belong in the native protocol; all GPU/runtime performance claims remain pending.

**Next question:** Integrate the three batches into one implementation contract, verify the offline exercises and publish the reviewable handoff on the existing feature branch.
