# L7-R8 Woodland herb variety

2026-11-09 · Landscape **L**. Continues the vegetation audit and [finer fern cards](../L7-R7/README.md).
Two complete downloaded [Poly Haven Shrub 03](https://polyhaven.com/a/shrub_03)
forms provide upright leaves and seed spikes on four existing woodland paths.
Two purple flowering cards remain as color accents; the two existing leafy 3D
shrubs are preserved and become more visible where a broad card previously hid them.
These sources read as herbs rather than rounded shrubs.

The source pipeline preserves supplier geometry, UVs, normals, binary buffers
and double-sided MASK/0.5. It removes only gallery translation and mechanically
packs the separate 16-bit alpha into diffuse RGBA8. **22 independent intake
checks** cover geometry/alpha preservation, deterministic regeneration and damaged
input/output rejection. The original Shrub 01 candidate was rejected for square
card framing because its single node has widely separated geometry; no supplied
geometry was cut apart. [Source pipeline and commands](../../../../tools/landscape/vegetation/README.md#external-woodland-herb-accents-l7-r8).

Each accepted 1024×256 atlas has four unlit source-color views. Independent
Blender 5.2.2 bakes match PNG and manifest bytes. Original models/PBR maps and
conversion proofs remain outside `app/`; the runtime adds only the derived
atlases/manifests/import settings. Its mesh catalog remains unchanged. The two
new decoded RGBA images total **2,097,152 bytes**; this is image storage, not a
measurement of GPU residency or peak process RAM.

Selection uses the last flowering path in each pocket before quality filtering.
East-north/east-south use form A; southwest/northwest use B. Their quads fit the
previous side/height and their visible bases use sampled terrain height. Existing
220 placement IDs, yaw, recipe families, collision/physics inputs and all 18 mesh
plans are preserved. High remains **202 cards + 18 meshes**, **2,656 source
triangles / 13 batches**, within unchanged complete-scene source allowances.
Balanced is a stable subset; Low/custom inputs do not load the new resources.

`OPENRC_WOODLAND_SHRUBS=legacy` restores the previous six flowering cards,
independently of fern and mesh controls. The legacy shader omits the two new
samplers and extra varying at compile time. Missing/invalid optional metadata
retains the original cards. Numeric JSON arrays are compared by value so valid
dimension/azimuth metadata does not silently fall back through int/float types.

The [machine-readable receipt](shrub-review.json) binds sources, checked commands
and native images. Windows evidence uses Godot 4.8-beta2 `cafc17a19`,
Compatibility/OpenGL, RTX 3090/NVIDIA 617.42:

- **17 headless / 26 native shrub checks**: fixed source selection, independent
  original card bounds/grounding, actual GPU instance data, quality subsets,
  invalid-manifest fallback, independent controls and eight source/frame pixels.
- **58 native habitat checks**, **25 native root-lighting checks**, **38 scene
  vegetation checks**, plus **six placement-generator tests**, without changing
  or regenerating placement data.
- **37 matched 1920×1080 still pairs** cover all four pockets, field controls,
  noon, low sun and night. **192 native orbit frames** compare form A and B
  pockets from matching camera poses. A separate root-control capture checks
  the include-aware diagnostic against the production default. All 15 legacy
  controls reproduce the pre-change baseline pixels exactly.
- An isolated exported PCK selects the production shader and both source atlases
  with original PNGs absent; decoded pixels and manifests match the source app.
  Its matching ZIP export inventories resources and contains no new shrub
  model/buffer/PBR-map bundle. This is a fixture export, not a complete release.

Raw PNGs, preview video, logs and packs stay under ignored
`tmp/vegetation-shrub-20261109/`. The first trial selected legacy cards due to a
metadata-type comparison; it is excluded from the accepted source comparison.
The final visual series binds an unchanged source set across all paired runs.
Afterward, a capture-only fallback for an empty Low-detail card subtree was fixed:
an unchanged High control matches exactly, and a native 1080p Low pilot capture
reports zero woodland geometry and no active card shader. The runtime and atlas
inputs are unchanged; the receipt records the separate capture-tool identity.
Source hashes identify the examined implementation across shared-workspace commits;
unrelated release-version edits remain outside this local verification.

The scene retains some stylized grass and purple cards, and all new forms still
use four discrete billboard views. Review is local to these pockets and this GPU;
whole-flight frame time, pilot readability, other hardware and complete release
exports remain unqualified. [Capture and pack controls](../../../../tools/trees/README.md#woodland-herb-card-review-l7-r8).
