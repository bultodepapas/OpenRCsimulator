# L7-R7 Finer woodland fern cards

2026-11-09 · Landscape **L**. Continues [woodland plants with depth](../L7-R6/README.md)
and the vegetation audit's source/silhouette work. **22 fern cards** now show the
existing downloaded **Poly Haven Fern 02 A**, with finer fronds and gaps instead
of the broad, dark Quaternius cutout. Six flowering-shrub cards retain their color.
No model was created or downloaded, and the supplier meshes/maps remain unchanged.

The 1024×256 atlas contains four unlit source-albedo/alpha views. Two independent
Blender 5.2.2 bakes produced identical PNG and manifest bytes. The baker now resolves
each asset's supplier notice and records all external buffers/images; this fern's
four dependencies match their catalog pins. It refuses
unreviewed BLEND conversion; this pass uses the fern's existing MASK/0.5 source.
The derived manifest binds the Poly Haven CC0 notice, source geometry and textures.
[Rebuild and verification](../../../../tools/landscape/vegetation/README.md#woodland-fern-cards-l7-r7).

Each card uses the new source's measured height/frame ratio to keep its visible
base on the sampled ground. Its square side and plant height cannot exceed the
previous card's envelope. Mesh selection still receives the original records, so
the two 3D ferns and all other mesh placements remain byte-identical. The default
High layout remains **202 cards + 18 mesh plants**, **2,656 source triangles** and
**13 batches**; the complete-scene source allowances are unchanged. Balanced keeps
its stable subset, and Low/custom inputs skip the new manifest and texture.

`OPENRC_WOODLAND_CARDS=legacy` restores the previous fern appearance.
`OPENRC_WOODLAND_MESHES=off` independently selects the 472-triangle/five-batch
all-card layout, using 24 new fern cards unless legacy appearance is also selected.
Normal source mode does not construct the legacy fern material. Both fern atlases
are lossless, unmipped RGBA8 at the same dimensions: **1,048,576 decoded bytes** each.
This is base-image storage, not measured GPU residency.

The [machine-readable receipt](fern-review.json) binds checked commands, sources,
camera pairs and native image hashes. Evidence uses Godot 4.8-beta2
`cafc17a19`, Windows Compatibility/OpenGL, RTX 3090/NVIDIA 617.42:

- **54 headless / 58 native habitat checks**, including the existing frame/yaw
  readback, source-card bounds/grounding, cold Low/custom caches, original mesh
  plans, geometry counts and independent quality subsets.
- **38 complete-scene vegetation checks**, **25 native root-lighting checks**,
  and **six placement-generator tests**; no placement data regeneration.
- **33 matched 1920×1080 still pairs** across the four pockets, wider field
  controls, noon, low sun and night; **192 native orbit frames** compare two
  pockets. Fourteen legacy controls match the pre-change baseline exactly; the
  pilot control differs in two pixels, with a maximum channel change of 1/255.
- A separately exported, isolated fixture PCK selects source ferns with the
  original PNG absent. Its decoded atlas pixels and manifest match the source
  app, and explicit legacy fallback works. This caught and fixed a source-file
  existence check that would miss an exported texture remap.
- Four damaged staged manifests and an unreviewed BLEND source are rejected.
  The old fern atlas's `--check` also passes.

The visual campaign has matching before/after source seals. A subsequent change
from `FileAccess.file_exists` to `ResourceLoader.exists` fixes packed-resource
selection; the final runtime passes 58 native checks and all 15 repeated source
views remain pixel-identical. The receipt preserves both source identities.

Raw images, logs, the lossy side-by-side preview and the isolated export remain
under ignored `tmp/vegetation-fern-20261109/`; only the required runtime atlas is
added to Git. [Capture and pack probe](../../../../tools/trees/README.md#woodland-fern-card-review-l7-r7).
Cards still lack true overhead depth and use discrete view changes. The broad
flowering shrubs and some grass cards remain stylized. These local checks do not
qualify complete exports, other GPUs, pilot flight readability or whole-flight
frame time; no performance improvement is claimed.
