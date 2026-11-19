# Sequential decal Workshop investigations 01–10

Research date: **2026-11-19**. Batch 1. Each investigation below informed the next question. Search refinements and source reads within one investigation are not counted again. Findings describe evidence; design consequences are proposals. No native Godot rendering or performance qualification is claimed.

[Research index and staged synthesis](README.md) · [Machine-readable evidence ledger](evidence-ledger.json)

## 01. Native decal limits across the actual renderer family

**Question:** Can the current native node satisfy persistent dense sponsor stacks?

**English search / source query:** `Godot 4.8 Compatibility decals GH-118070 eight surface 64 limit`

**Evidence:** [1](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-4/) (official release notes); [2](https://github.com/godotengine/godot-proposals/discussions/12903) (upstream maintainer discussion).

**Finding:** Compatibility support was introduced in 4.8 dev 4, with a hard eight-per-surface bound and hardware-constrained view capacity, defaulting to 64. An upstream maintainer clarifies that additional decals on one mesh are culled; Mobile has the same receiver limit.

**Design consequence:** Retain native decals as a bounded comparison/placement ghost. Do not evict a player's saved stickers like temporary bullet holes, split aircraft geometry merely to evade the cap, or change global renderer to qualify the feature.

**Limit:** This confirms the engine-family constraint; it is not a runtime/performance measurement of OpenRC's pinned beta.

**Next question:** Investigate whether ordering is stable even below those capacity limits.

## 02. Layer ordering is a separate qualification gate

**Question:** Does selecting a layer order guarantee that order under camera motion?

**English search / source query:** `Godot decals sorting camera AABB order overlapping decals render priority issue`

**Evidence:** [1](https://docs.godotengine.org/en/stable/tutorials/3d/using_decals.html) (official documentation); [2](https://docs.godotengine.org/en/stable/tutorials/3d/3d_rendering_limitations.html) (official documentation); [3](https://github.com/godotengine/godot/issues/108248) (upstream reproduced issue).

**Finding:** Native decal sorting depends on camera distance and bounds. Transparent mesh ordering also has limitations. Issue 108248 reports and confirms a Forward+ ordering failure above 32 scene decals in older engine builds, even when only two overlap on the affected mesh.

**Design consequence:** Make deterministic layer order a release gate independent of capacity. Compare 2, 8, 9, 32, 33 and 64 overlapping instances under camera motion; never treat a sorting offset alone as proof.

**Limit:** The issue is an older-version reproduction, not a confirmed defect in the pinned beta. Mesh overlays need their own ordering qualification.

**Next question:** Inspect a real clipped-geometry implementation to learn which guarantees it actually supplies.

## 03. Six-plane clipping from three.js

**Question:** What reusable algorithm actually turns a projector into attached mesh geometry?

**English search / source query:** `site:github.com/mrdoob/three.js DecalGeometry.js clipGeometry plane projectorMatrixInverse normalMatrix`

**Evidence:** [1](https://github.com/mrdoob/three.js/blob/dev/examples/jsm/geometries/DecalGeometry.js) (upstream source; Git blob `c5d139ff563b001c356ccc40bb5ef74215cec60a`); [2](https://github.com/mrdoob/three.js/blob/dev/examples/webgl_decals.html) (upstream example).

**Finding:** The implementation transforms indexed or unindexed triangles into projector space, clips against six planes, interpolates positions and normals, derives UVs, then emits world-space geometry. Its example uses explicit render order and disables depth writes. The geometry routine alone does not select a connected surface region.

**Design consequence:** Use the algorithm as a reference for an original receiver-local implementation. Add topology/normal filtering before clipping, re-normalize interpolated normals, and test winding, finite output and nonuniform transforms. Keep any adapted-code license notices if code is later ported.

**Limit:** The example is not a persistent livery editor and does not establish Godot layer sorting or frame costs.

**Next question:** Look for an implementation that explicitly handles rear-facing triangles and local attachment.

## 04. Local attachment and backface rejection in Babylon.js

**Question:** How can a decal move with its receiver without appearing on the back of a thin part?

**English search / source query:** `Babylon.js CreateDecal cullBackFaces localMode captureUVS source decalBuilder`

**Evidence:** [1](https://doc.babylonjs.com/features/featuresDeepDive/mesh/decals) (official documentation and examples).

**Finding:** Babylon separates local attachment from backface rejection. Its texture-map alternative requires unique UVs and offers no selective erase without reconstructing the texture; UV-island edge blending adds work.

**Design consequence:** Persist editable instances as the source of truth. Filter candidate triangles by qualified receiver, connected region, facing and bounded depth; backface rejection alone cannot distinguish two nearby forward-facing surfaces. Treat baked images only as rebuildable caches.

**Limit:** Babylon's performance claims and skinning support are not measurements or supported features of OpenRC's proposed rigid-receiver implementation.

**Next question:** Compare another production engine's receiver filters and rendering-method costs.

## 05. Receiver filtering has a rendering cost

**Question:** Can a screen-space projector be adopted without platform or receiver-filter costs?

**English search / source query:** `Unity 6 URP Decal Renderer Feature reference DBuffer Screen Space DepthNormal prepass`

**Evidence:** [1](https://docs.unity3d.com/6000.0/Documentation/Manual/urp/renderer-feature-decal-reference.html) (official versioned documentation).

**Finding:** Unity URP distinguishes DBuffer and screen-space methods. DBuffer requires a depth/normal prepass and does not support OpenGL/ES; enabling decal rendering layers can also introduce a prepass.

**Design consequence:** Do not copy a screen-space technique while assuming its mask is free or portable to OpenRC's Compatibility path. Qualify receiver selection and total pass cost together, including native-resolution Apple Silicon runs.

**Limit:** These are Unity constraints; they motivate questions and do not directly describe Godot's implementation.

**Next question:** Check how a production engine treats overlapping material channels and sort order.

## 06. Material channels and explicit order in Unreal

**Question:** Which parts of a production decal system should the first sponsor implementation include?

**English search / source query:** `site:dev.epicgames.com documentation decal materials DBuffer overlapping sort order only one decal displayed`

**Evidence:** [1](https://dev.epicgames.com/documentation/en-us/unreal-engine/decal-materials-in-unreal-engine) (official documentation); [2](https://dev.epicgames.com/documentation/unreal-engine/decal-actors-in-unreal-engine?lang=en-US) (official documentation).

**Finding:** Unreal exposes receiver material responses and explicit actor sort order, while warning that many distinct orders impede state sorting. Its custom DBuffer material-expression reconstruction has a specific overlap limitation; this is not a blanket claim that all Unreal decals cannot blend.

**Design consequence:** Start with lit color/alpha sponsor art and an explicit ordered stack. Defer normal/metallic/emission authoring. Benchmark worst-case overlapping layers rather than assuming material batching preserves the player's order.

**Limit:** Godot's overlay must implement and qualify its own material behavior; Unreal's renderer features are comparisons, not drop-in APIs.

**Next question:** Determine how to obtain the right receiver triangles efficiently in Godot.

## 07. Build topology once, update only affected decals

**Question:** Should each pointer movement reconstruct the complete receiver topology?

**English search / source query:** `site:docs.godotengine.org MeshDataTool ArrayMesh slower edges faces surface arrays triangle mesh procedural`

**Evidence:** [1](https://docs.godotengine.org/en/latest/tutorials/3d/procedural_geometry/meshdatatool.html) (official documentation); [2](https://docs.godotengine.org/en/latest/tutorials/3d/procedural_geometry/index.html) (official documentation).

**Finding:** MeshDataTool calculates face and edge relationships and supports triangle meshes. Godot recommends direct ArrayMesh arrays when the additional topology is unnecessary.

**Design consequence:** Cache validated CPU triangle arrays and adjacency per receiver revision. Use adjacency for connected-region selection, then emit only the changed decal's clipped ArrayMesh. Do not rebuild the entire aircraft or every saved decal during a drag.

**Limit:** The relative API guidance is not an OpenRC latency measurement; memory and rebuild cost still need instrumentation.

**Next question:** Check how an established acceleration library invalidates its spatial index when geometry changes.

## 08. Spatial-query acceleration and cache invalidation

**Question:** When can a local-space picking acceleration structure be reused safely?

**English search / source query:** `site:github.com/gkjohnson/three-mesh-bvh README raycastFirst local space refit index buffer changes`

**Evidence:** [1](https://github.com/gkjohnson/three-mesh-bvh/blob/master/README.md) (upstream repository documentation); [2](https://github.com/gkjohnson/three-mesh-bvh/blob/master/API.md) (upstream API documentation).

**Finding:** The library supports nearest-hit and spatial queries in geometry-local coordinates. Building its BVH may modify indices; refitting changed positions is distinct from changing indexed topology.

**Design consequence:** Key any OpenRC picking index by receiver geometry revision and build it from owned snapshot arrays. Invalidate on topology changes. Transform rays into receiver space and compare candidate hits in a common world-distance metric, especially with nonuniform scale.

**Limit:** No new JavaScript dependency is proposed for Godot. Start with bounded triangle queries, then add a BVH only if measured drag latency requires it.

**Next question:** Resolve how one drag becomes one undo action without replaying every pointer event.

## 09. Gesture transactions and runtime undo

**Question:** How should a long drag remain one reversible player operation?

**English search / source query:** `site:docs.godotengine.org UndoRedo create_action MERGE_ENDS execute commit_action runtime drag`

**Evidence:** [1](https://docs.godotengine.org/en/latest/classes/class_undoredo.html) (official API documentation).

**Finding:** Godot supports grouped do/undo operations, explicit action commits and optional execution on commit. EditorUndoRedoManager is specifically for editor-plugin history rather than an in-game Workshop.

**Design consequence:** Keep OpenRC's shared Workshop history authoritative. Capture before-state on gesture start, preview transient state during movement, validate on release and commit one before/after action. Cancel restores the original without a history entry; a no-op does not consume history.

**Limit:** Do not replace the project's existing history implementation just to use this API. Preserve the existing 32-entry product policy, distinct from the 2D study's history.

**Next question:** Find whether a bake fallback can run on demand without GPU readback on every edit.

## 10. Event-driven baking without continuous readback

**Question:** How can a future compositor update without creating a permanent per-frame bake cost?

**English search / source query:** `Godot SubViewport UPDATE_ONCE ViewportTexture get_image GPU performance every frame`

**Evidence:** [1](https://docs.godotengine.org/en/latest/tutorials/rendering/viewports.html) (official documentation); [2](https://docs.godotengine.org/en/4.7/classes/class_texture2d.html) (official API documentation).

**Finding:** SubViewport can render once and retain its texture. Texture2D.get_image creates a CPU copy from GPU data and is explicitly discouraged every frame.

**Design consequence:** If the compositor is needed, dirty only the changed receiver chart, debounce its rebuild, reuse GPU textures and reserve readback for explicit export or measured checkpoints. Use revision tokens so an old bake cannot overwrite newer edits.

**Limit:** A SubViewport does not generate a unique UV layout or solve alpha blending by itself; those remain separate qualifications.

**Next question:** Synthesize the first ten findings, then investigate failure boundaries before expanding feature scope.
