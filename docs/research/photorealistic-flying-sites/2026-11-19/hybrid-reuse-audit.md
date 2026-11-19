# Hybrid scenery: what OpenRC already owns

2026-11-19. Read-only source audit for the [hybrid proposal](hybrid-scenery.md).
Planning baseline: `f5dbf743f3e5229687688149fcda3215b8228a70`.
Main observed during this follow-up: `99e5a5ac024935c32028e5332d31a3e09da4dc42`.
The relevant rendering, scenery, landscape, vegetation, tree-tool and engine-pin
paths were unchanged in the comparison; this is not a rebase or a whole-project
qualification. Text sources, manifests and the Git inventory were inspected.
No Blender file, model, texture or running simulator was opened for this audit.

The [canonical SC-PHOTO plan](../../../plans/photorealistic-flying-sites.md)
owns status. The items below are existing components to reuse, with the missing
photo-site integration stated explicitly.

## Asset inventory and provenance

The current [vegetation catalog](../../../../app/assets/landscape/vegetation/catalog.json)
contains **30 runtime assets, including 13 tree forms**. The introductory count
of 28 assets/11 trees in the older
[pipeline guide](../../../../tools/landscape/vegetation/README.md) is stale.
Use the catalog and generators when selecting a source, not that count.

| Source family | Existing tree forms | Reuse and rights boundary |
| --- | --- | --- |
| Quaternius Standard | Four broadleaf forms and three pines | CC0 source notices; useful low-cost controls, but their stylized shapes may not match a real site |
| OpenGameArt oak | `oak_tree` | CC BY-SA 3.0 source; original `quercus_A_packed_v1.blend` is tracked under `assets/landscape/vegetation/source/opengameart_oak_tree_lod_2026/`. Source and derived notices must travel together |
| LOLIPOP maple | `maple_tree` | CC BY 4.0 source; retained source is an FBX pack, with a reviewed conversion. Do not describe every imported tree as a project-authored Blender model |
| LandscapeLab | `landscapelab_quercus`, `landscapelab_pine`, `landscapelab_fagus`, `landscapelab_quercus2` | CC BY-SA 4.0 source notices, with a separate Fagus leaf-photo notice. Retained originals are GLBs. These are the best first candidates for comparing existing near meshes with matched far cards |

The oak's reviewed retained mesh has 5,303 triangles and one surface; the
pipeline intentionally excludes its supplied LOD1/LOD2. Do not manufacture an
unreviewed low-detail source by editing the shipping GLB. License statements
here describe retained repository evidence, not a new legal clearance for
different downloads or a promise that every asset in an upstream collection
has the same terms. Check the individual notices and proposed derivative/export
inventory under C07/Q10 before publishing an implementation.

The [Blender workflow](../../../../.agents/skills/openrc-blender/SKILL.md)
preserves original source deliveries and requires generator-led derived assets.
Its old Godot version note is not the runtime pin: this branch's actual target
remains `4.8.beta2.official.cafc17a19`, as established by the project/bootstrap
source and the [architecture audit](../2026-11-18/current-architecture.md).
No engine or Blender upgrade is proposed here.

## Reuse map

| Existing component and source | What it actually does | Proposed hybrid use and missing work |
| --- | --- | --- |
| [ImportedVegetation](../../../../app/scenery/imported_vegetation.gd): `get_parts`, `fit_to_height`, `queue`, `build` | Resolves catalog IDs, fits uniform scale, grounds source parts, shares materials and builds MultiMesh batches; supports per-object damage IDs and optional spatial cells | Build a few explicitly placed 3D additions using existing assets. It is a batch factory, not a generic runtime Blender/glTF file importer or a ready-made surveyed-photo placement format |
| [Treeline](../../../../app/render/treeline.gd) and [tree tooling](../../../../tools/trees/README.md) | Three crossed quads per instance, lit alpha-scissor material, sector grouping and existing atlas generation. Stable slots `CommonTree_1`, `CommonTree_3`, `Pine_1` now represent LandscapeLab Quercus, Fagus and pine | Compare the matching source tree and card from the same geometry family. Existing cards have no real-time cast shadows and are a deliberately limited representation, not volumetric trees |
| [FieldTreeDetail](../../../../app/render/field_tree_detail.gd) | Replaces selected treeline cards with source trees in the pilot-facing sector, using 256 m cells and an 8-pixel bark LOD setting; disables native casting | Reuse asset identity/material decisions; do not copy the selection radius or shadow policy into the photo-site specification without tests |
| [ShaderClock](../../../../app/render/shader_clock.gd) and the imported-tree wind shaders | Updates `sim_clock` and `wind_vec` from accepted simulation/world flow; wraps time over 1,024 seconds | Animate admitted real 3D trees consistently through pause/reset. Do not introduce wall-clock wind or animate a photographic tree still baked into the background |
| [Field rendering](../../../../app/render/field.gd) and [ground tooling](../../../../tools/ground/README.md) | Existing runway, mown/rough ground and close turf detail | Start a real local ground patch with known scale and materials. Its visual blend into photographed ground is new work; it does not change the support surface or friction |
| [Scenery prefabs](../../../../app/scenery/prefabs.gd) | Existing shelters, sheds, farm structures, turbines and pylons | Reuse selected visible props only after composition, scale and contact admission; do not scatter the default field into an unrelated real photo |
| [Parked aircraft](../../../../app/scenery/parked_aircraft.gd) and [scenery tools](../../../../tools/scenery/README.md) | Reusable static aircraft bakes, instanced placement, material LOD and contact-shadow handling; separate CC0 vehicle/livestock sources also exist | A parked aircraft or shelter provides a useful second composition test after trees. Existing prop shadows are not a generic native shadow receiver for photographic terrain |

The current treeline detail choice is a **pilot-relative selection made during
construction**: a front sector and maximum radius of 600 m. It is not an
automatic camera-following mesh-to-impostor transition. Its contact selection
uses the default policy independently of graphics quality. A new hybrid must
keep that physical independence even if it chooses a different visual layout.

The current loader admits treeline positions only at 250–1,500 m with additional
runway-corridor clearances. `Treeline.identity` hashes position into species,
height and yaw; `FieldTreeDetail` does not accept an arbitrary named tree/height.
The close, explicitly chosen HX01 trees therefore use `ImportedVegetation`
directly in a non-flyable rendering fixture. A playable site needs representable
validated placements or the reviewed SC-PHOTO-04 extension. Direct factory builds
enable native cast shadows, unlike the distant-tree wrapper; set the intended
per-batch policy explicitly and qualify it with HX03. A chosen `TreeAssets` card
and production `Treeline` share source families but use different material/
instance plumbing, so matching species is not proof of pixel identity.

Existing distant mountains use an SRTM crop and two CC0 material sources;
their visual geometry begins about 1.6 km away and is not a terrain contact
solver. Existing placement/skyline estimates are reference material, not a
survey of a newly photographed field. The hybrid's distant photo can replace
that visual role, but the default mountains/treeline must not remain behind it
and reappear through fog, reflections or a site switch.

## What the accepted vegetation work already resolved

**Wind is source-specific.** `TREE_WIND_LEAN_LIMITS_M` admits the four
LandscapeLab forms with crown-top bounds of 0.12 m (Quercus), 0.22 m (pine),
0.13 m (Fagus) and 0.15 m (Quercus2). The existing material/transform checks
and collision envelope remain necessary. Unlisted trees, including the maple,
and unsupported materials such as the oak's blended foliage keep the static
fallback. Leaf-normal flutter is shading, not independently moving collision
geometry. These facts do not qualify an arbitrarily scaled new placement.

**Foliage filtering is not a fresh invention.**
[GDU-11](../../engine-upgrade/GDU-11/README.md) already adopted
coverage-preserving mipmaps for the maple leaf texture, at import threshold
0.5 with authored material cutoff 0.5. Its retained evidence is Godot 4.8-beta1,
Windows, RTX 3090, Compatibility, at 1080p and 1440p. It neither proves beta2
Mobile/Metal nor measures every visual/performance property. Older prose saying
that this maple is still deliberately unmipped is historical, not the current
recipe. Preserve the adopted recipe as the baseline.

For LandscapeLab, the current factory scales batch LOD bias by the largest
instance, retains foliage LODs with at least 25% of source triangles and clamps
the wind-shader foliage texture to mip 6. These were responses to thinning
crowns. The static fallback differs. Start with these recorded choices; isolate
any new alpha/filter/LOD change in [HX04](hybrid-experiments.md#hx04--foliage-detail-wind-and-batching).
Alpha-test coverage preservation is distinct from MSAA alpha-to-coverage; the
[renderer analysis](hybrid-scenery.md#renderer-and-color-boundaries) explains why
that distinction matters.

**Prior impostor failures are useful evidence.** The
[L8b review](../../visual-quality-implementation/L8b/2026-10-18/README.md)
rejected a particular candidate: 24.75% bad pixels against a 10% limit, with
42.331 MiB of two-atlas image data for one form on its Godot 4.7.2/Windows test.
That is neither a universal rejection of impostors nor permission to repeat the
same experiment as a new optimization. A future attempt needs a specific cause
and changed design, a matched source, and a better result under the current
camera/platform envelope. Smaller cells and extra LOD tiers also need measured
benefit; they are not automatically faster.

## New integration that still has to be built

Existing ground rectangle/material blending is also not photo reprojection or
a photographic shadow receiver. Default-field detail/layout dependencies must
not be inherited accidentally. Likewise `Prefabs.build` supplies geometry and
moving parts; its caller owns placement, batching, motion, shadow and damage
bookkeeping. These boundaries matter when a small diagnostic becomes a site.

The first hybrid needs an explicit, validated placement/appearance sidecar,
captured-world integration, clean photographic background where an object is
replaced, photo/3D grounding, and qualification of every admitted camera and
renderer. Those are SC-PHOTO work, not functionality already supplied by the
vegetation catalog.

`FieldLoader` remains strict and `CollisionWorld` consumes supported field,
prefab and world inputs. Neither is a general imported scan or surveyed Blender
mesh collider pipeline. A `collides: false` visual record cannot erase a
separately built physical-world obstacle. A real tree inserted for appearance
also needs an admitted contact volume if it is reachable in the supported flight
area; conversely, lowering visual quality must not leave an invisible trunk
collider. Keep one deterministic surveyed inventory and the existing
[C05 physical contract](implementation-contracts.md#c05--stable-physical-semantics-and-honest-coverage).

The first source choice is therefore one LandscapeLab pine and one Fagus,
using the current factory, materials and notices. A preserved original oak
Blender source can support a later controlled authoring exercise. A purchased
vegetation package, a new terrain engine and a new general-purpose importer are
not prerequisites for this comparison.
