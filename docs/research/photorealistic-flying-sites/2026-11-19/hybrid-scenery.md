# Hybrid scenery: photographic landscapes with OpenRC's 3D assets

2026-11-19. Follow-up to the adversarial review, responding to the request to
combine photographs with existing Blender/3D trees and scenery. This is a
research-backed design and experiment plan, not an implemented photo field.
The [canonical plan](../../../plans/photorealistic-flying-sites.md) remains the
only SC-PHOTO status ledger.

## Recommendation and evidence

Add a **fixed-eye hybrid comparison to SC-PHOTO-02 now**: the same calibrated
photographic background and measured contact inventory, plus a small amount of
real local geometry using OpenRC's existing vegetation and prop pipelines.
Compare it with the simpler photographic method before choosing the first
production field. Moving-eye hybrids remain a separate SC-PHOTO-11 capability.
There is no reason to wait for an entire pure-photo release before investigating
whether two well-integrated 3D trees improve the fixed-pilot experience.

This has direct RC precedent. neXt's official authoring guide combines panoramic
scenery, Blender objects, photographic surfaces and masks. ClearView documents
visible 3D trees, buildings and runways alongside photo fields. Game-production
accounts by The Astronauts, Unity and Epic show how photographic material and
authored geometry can be combined into coherent vegetation and terrain. The
source-inspected GamesNotDeveloped forest demo supplies a concrete Godot example
of a photographed sky with 3D terrain and trees. These examples prove different
parts of the method; none qualifies OpenRC's implementation or full camera
envelope. See the [twelve precedent dossiers](hybrid-precedents.md).

The [reuse audit](hybrid-reuse-audit.md) identifies 30 current vegetation assets,
13 tree forms, an original oak Blender source, matched tree-card tooling,
simulation-time wind, ground materials and parked aircraft. Start there. The
research's [47 retained queries and source register](hybrid-search-log.md)
separate observed prior art, documented APIs, repository facts and proposals.

## Three constructions, with different camera promises

| Construction | Appearance and depth | Camera promise | First use |
| --- | --- | --- | --- |
| Fixed photographic field | Full panorama; measured photo-projected proxies supply selected depth and contact correspondence | One surveyed eye, rotation/tracking/zoom | Existing SC-PHOTO-02 baseline |
| Fixed hybrid field | Same full panorama, with selected real 3D trees, props and local ground; cleaned image where real geometry replaces photographed content | Still one surveyed eye unless separately qualified | New immediate comparison in SC-PHOTO-02; integration in 03–07 |
| Moving hybrid / 3D photographic field | Actual local terrain and objects; photo-derived materials; only sufficiently distant, view-compatible content remains photographic | Explicit measured volume and admitted moving-camera modes | SC-PHOTO-11/12 after geometry, contact and camera proof |

Putting a photograph on a mesh can give it depth for occlusion. It does not
automatically provide correct albedo, unseen sides, view-dependent highlights
or newly exposed content. A photo-projected tree proxy and a normally textured,
lit 3D tree therefore have different contracts even when both are MeshInstances.

## One owner for each visible object

For every meaningful feature, the proposed sidecar/authoring manifest identifies
its appearance role, physical ID where applicable, source/derivative IDs,
transform in the declared field frame, occlusion role, shadow behavior and
allowed animation. These are requirements for SC-PHOTO-03, not invented fields
already accepted by `openrc-field v1`.

| Role | Background treatment | Rendered geometry | Physics and motion |
| --- | --- | --- | --- |
| Photo-baked object | Keep its original pixels and captured shadow | Measured photo-projected proxy if needed for aircraft visibility; special shadow interactions need explicit proof | Stable admitted contact shape; nondestructible first pilot; captured appearance stays static |
| Real 3D addition | Place it in a region with no duplicate photographed object or incompatible baked shadow | Existing source mesh/material; a qualified lower-detail version may replace its appearance | Stable admitted physical identity if reachable; supported wind only; first experiment nondestructible |
| Real 3D replacement | Make a versioned clean background removing the old silhouette and its relevant baked shadow | Real mesh owns the complete replacement, including openings and visible back/side surfaces | Stable measured contact identity; replacement and cleanup admitted together; wind requires clean coverage over its swept outline |
| Decorative distant background | Keep genuinely distant content within the declared view/parallax limits | Photo or selected distant mesh, with one visible owner | Do not imply local support/collision or reachable terrain that has not been surveyed |

Never keep the photographed crown and add a second 3D crown on top, hide a
collidable trunk by lowering visual quality, or let a photo object break while
its pixels remain. For the first hybrid all selected obstacles remain
nondestructible under C05. A later wholly 3D object may use another existing
damage policy only after its background, shadows, reset and physical state have
been qualified together.

## Twelve technique investigations

### HM01 — a few visible 3D additions in a photo field

**Evidence:** neXt and ClearView support this composition directly
([HS01–02](hybrid-search-log.md#hs01)).
**OpenRC proposal:** place one existing LandscapeLab pine and one Fagus outside
the clear landing corridor, in image regions without a photographed duplicate.
Use `ImportedVegetation` with a declared source, size and physical counterpart.
The objective is credible depth, aircraft occlusion and local presence, not a
new procedural forest. **Failure condition:** the trees float, disagree with
the photograph's scale/light, hide the aircraft incorrectly, or only look good
at a wide angle. [HX01](hybrid-experiments.md#hx01--fixed-eye-hybrid-control)
compares the actual choices.

### HM02 — replace a photographed tree through a clean background

**Evidence:** Blender's Clone brush/paint wrapping and GIMP's wrapped offset
support the necessary editing operations, not automatic reconstruction of hidden
content ([HS20–22](hybrid-search-log.md#hs20)).
**Proposal:** preserve the original master; author a separate clean derivative
using additional site images where possible, with an explicit repair mask.
Remove the old silhouette, visible fragments through the crown and incompatible
baked shadow. Replace the complete appearance with the real asset. Cover the
allowed wind sweep and view envelope, not just the still tree outline.
**Limit:** a generative or cloned fill is invented visual content, never survey
evidence. It must not erase real contact hazards or justify a moving viewpoint.
Use a known synthetic scene first in HX02 so hidden geometry has a reference.

### HM03 — a small real ground patch joined to the photograph

**Evidence:** the RC authoring guides distinguish photographic ground and local
objects; game foliage workflows emphasize ground/plant color and intersection
matching ([HS01–02, HS07](hybrid-search-log.md#hs07)).
**Proposal:** use the existing ground-material pipeline on a bounded, measured
local patch, with a deliberately designed transition to the photographed ground.
Compare a photo-projected opaque patch with a lit material patch rather than
assuming one texture can serve both purposes. A terrain rise or vegetation can
hide a join only if it exists in the admitted geometry and does not obscure
flight-critical cues. **Limit:** vertex-color/material masks can blend color,
roughness and detail; they cannot fix wrong ground height, duplicated light or
missing depth. Ordinary material blending is the first cross-renderer candidate;
no decal-only dependency is required. HX03 checks the joins and receivers.

### HM04 — near meshes, matched cards and photographic distance

**Evidence:** OpenRC already has source trees plus matched cards; the Godot
forest demo has explicit near/far MultiMeshes ([reuse audit](hybrid-reuse-audit.md),
[HS14](hybrid-search-log.md#hs14)).
**Proposal:** assign each tree one logical appearance owner and physical
identity; retain the same contact data across tiers. A qualified transition may
overlap mesh and card with controlled complementary coverage, without duplicate
color/shadow contribution. Select transitions using projected
silhouette error, crown coverage and aircraft readability at actual FOVs.
**Limit:** distance alone is insufficient when zoom reaches 1°. OpenRC's current
600 m pilot-sector selection is not a universal threshold or a moving-camera
LOD system. Both current far cards and the pilot-sector detailed-tree wrapper
disable real-time casting; direct vegetation-factory builds enable it by default.
Choose that policy explicitly in the experiment. A transition also
needs shadow continuity or a declared fixed representation; a generic fade does
not solve that. HX04 preserves existing recipes before any optimization.

### HM05 — scanned trunks with authored crowns and leaf atlases

**Evidence:** Zdravko Pavlov's Book of the Dead account combines scanned lower
trunks with generated upper trunks and assembled scan-derived needle atlases;
Adam Bryla describes photo textures plus authored plant elements in Ethan Carter
([HS07, HS09](hybrid-search-log.md#hs09)).
**Proposal:** if an existing tree cannot match a prominent site feature, retain
its reviewed source or capture a site-specific trunk, then author an optimized
crown in Blender using rights-cleared foliage textures. Bake appearance onto
the game asset and preserve source/derivative provenance. **Limit:** the lessons
transfer; proprietary project trees, plugins and texture collections do not
become available for Godot merely because an article or demo is free. A new tree
is conditional on a failed existing-asset comparison, not the first milestone.

### HM06 — photo projection and baking with the correct camera model

**Evidence:** Blender UV Project is perspective/orthographic projection; Project
from View is planar; baking requires destination UVs and a selected image target
([HS17–19](hybrid-search-log.md#hs17)).
**Proposal:** for offline authoring, use calibrated rectilinear image sectors
with known pose/FOV, or an explicitly implemented spherical lookup. Bake the
chosen result into a derived asset when that is appropriate. Preserve the
runtime C01 per-fragment spherical convention for the fixed-eye proxy path.
**Limit:** dropping an entire 2:1 panorama into a perspective projector distorts
it. Low-poly perspective UV interpolation, vertices behind the camera, seams
and occluded surfaces need deliberate handling. Subdivision can reduce a planar
projection artifact; it does not supply unseen photography or solve a wrong
projection model.

### HM07 — separate the visible photograph from lighting intent

**Evidence:** Godot's sky shader distinguishes visible and cubemap passes;
environment settings control ambient and reflection sources
([HS23–24](hybrid-search-log.md#hs23)).
**Proposal:** first use fixed exposure, a matched directional sun and a measured
ambient reference. If a foreground-heavy photo gives unsuitable radiance,
compare a custom sky shader using `AT_CUBEMAP_PASS` for a separate clean lighting
panorama. The visible photo and lighting source remain bound to one World owner.
**Limit:** this is a capability-based candidate, not a beta2-tested implementation.
Setting ambient to Color does not independently replace Sky reflections. A
cleaned LDR panorama is not calibrated HDR, and duplicating a captured sun in
image-based light plus a strong directional light can overlight the trees.
HX03 uses both matte and glossy diagnostic objects.

### HM08 — coherent species, scale and ground contact

**Evidence:** The Astronauts' foliage account stresses observed plant composition,
scale and ground intersections; Unity's environment account describes asset
matching and scene assembly ([HS07, HS10](hybrid-search-log.md#hs10)).
**Proposal:** make a site reference sheet before scattering assets: characteristic
tree shapes, maturity, crown/trunk ratios, color family, season, canopy density,
ground cover and measured sizes. Select from the current catalog, then allow
small documented material adjustments in derived/runtime material instances.
**Limit:** random green trees, oversized grass and uniform tints can make a
technically detailed scene less convincing. Do not alter supplier source pixels
or geometry in place to force a match. Ground scale and silhouette matter more
than an arbitrary polygon target.

### HM09 — portable foliage edges and transitions

**Evidence:** Godot distinguishes alpha scissor/hash/blend, import-time alpha
coverage, MSAA alpha-to-coverage, visibility fades and dithered material fades
([HS25–29](hybrid-search-log.md#hs25)).
**Proposal:** retain each existing asset's accepted material/import baseline.
If a measured defect remains, compare one alternative at a time across dark and
bright photographic backgrounds, at normal and extreme zoom. Inspect coverage,
halos, shimmer, aircraft visibility and shadows over temporal sequences.
**Limit:** an alpha threshold that fixes a still can erase distant branches;
dithering can replace popping with noise. A proposed shader/material path must
compile and pass on the actual renderer; naming a Godot API does not prove
Compatibility behavior.

### HM10 — batch only the repeated work that benefits

**Evidence:** MultiMesh instances share draw submission and are culled as a
whole object; OpenRC and the forest demo both use spatial groups
([HS30](hybrid-search-log.md#hs30), [reuse audit](hybrid-reuse-audit.md)).
**Proposal:** use the current vegetation factory for the initial small inventory.
Only profile individual meshes versus existing batches and alternative cells
when a measured bottleneck appears. Bind the same visible/physical placements
to every comparison. **Limit:** giant batches can retain offscreen trees; tiny
cells add submissions and management. Additional LOD images also consume import,
resident and transient memory. A one-tree microbenchmark cannot qualify the
complete photo field, switching behavior or simulation headroom.

### HM11 — authored distant geometry beyond the local scene

**Evidence:** Valve's source implements a separately rendered, configurable-scale
3D skybox; flight-simulator SDK documentation combines different terrain and
object data sources ([HS06, HS13](hybrid-search-log.md#hs06)).
**Proposal:** for moving views, prefer ordinary optimized distant terrain meshes
and a sky-only panorama before considering a separate distant rendering pass.
Reuse OpenRC's bounded field frame; keep distant decoration out of contacts
unless deliberately admitted. **Limit:** Source's depth-clear/scale/fog model is
engine-specific, not a Godot drop-in or proof of local occlusion. Its SDK license
is not a general code-reuse permission. A second camera/pass is conditional on a
measured limitation of the simpler geometry baseline.

### HM12 — depth-aware panoramas for a later bounded comparison

**Evidence:** PicaSim describes depth-driven stereo panorama shifts and seam
correction; Navier8's example documents the limits of a textured sphere
([HS05, HS15](hybrid-search-log.md#hs05)).
**Proposal:** retain depth-aware/stereo work as a later comparison under
SC-PHOTO-13, using independently measured scene depth and explicit camera bounds.
**Limit:** no hidden surface appears merely by shifting UVs. Depth discontinuities,
thin foliage, newly exposed pixels and eye-specific visibility still need proof.
PicaSim's current source/data licenses are restricted; learn from the method
without importing its code or scenery. This is not a shortcut to six-degree-of-
freedom flight, FPV or a freely walkable photographic field.

## Renderer and color boundaries

These are documentation-based expectations to verify on the exact pin. Latest
Godot manuals can describe development behavior; they are not test receipts.

| Mechanism | Compatibility | Mobile / Metal | Forward+ | Planning decision |
| --- | --- | --- | --- | --- |
| Ordinary meshes, source materials, alpha-scissor foliage | First comparison path | Separately qualify | Separately qualify if admitted | Reuse current asset baselines; source-specific exceptions remain |
| MSAA alpha-to-coverage | Latest renderer table says unsupported | Documented support with suitable MSAA | Documented support with suitable MSAA | Optional per-renderer treatment; never a universal first-site dependency |
| Preserve Alpha Test Coverage during texture import | Distinct texture-processing feature, already used for OpenRC maple | Same source recipe still needs actual import/runtime proof | Same qualification requirement | Do not confuse it with alpha-to-coverage; docs advise against enabling it for Alpha Hash |
| Built-in visibility-range alpha fades | Current class docs describe hard switches with hysteresis disabled for these modes | Same documented restriction | Documented fade support | Keep ordinary disabled-fade hysteresis or test a separate dither recipe; do not promise portable smooth fades |
| Two-object material dither recipe | Candidate, unqualified | Candidate, unqualified | Candidate, unqualified | Compare noise, shadows and cost; differs from built-in visibility fades |
| Separate visible/radiance sky samples | Proposed sky-shader path | Proposed sky-shader path | Proposed sky-shader path | Prove C03 color and update behavior; do not copy a demo's WorldEnvironment wholesale |

Keep photo-projected surfaces in the captured-appearance path and actual PBR
objects in the lit path. Validate both against independent references, not just
against each other. The photo's exposure, white balance, shadow direction and
ground palette constrain the local 3D lighting. Extra fog must not be applied
twice to distance already hazed in the image; any added volumetric/screen-space
effect is conditional on renderer support and a demonstrated visual benefit.

The forest demo's source is especially instructive: it has a photographed sky,
3D geometry, ambient Color, a moving layered-cloud shader and Forward+-specific
environment/compositor features. It does not implement independent visible and
radiance panoramas. Copying its `TIME`-driven sky would also conflict with OpenRC's
captured-scene/accepted-time policy and can trigger repeated sky-radiance updates.

## Shadows, reflections and animation need their own composition

The existing [C04 shadow contract](implementation-contracts.md#c04--one-aircraft-to-ground-shadow-owner)
remains the starting point: one aircraft-ground cue owner, with native
self-shadowing distinguished from ground receiving. A true 3D tree adds more
interactions, which cannot be solved merely by disabling photo-object casters.

| Interaction | Required hybrid treatment |
| --- | --- |
| Photo-baked tree → photographed ground | Keep the captured shadow; avoid casting it again |
| New real tree → local real ground | Qualify a matched shadow or explicitly restrict the initial scene/light condition; existing aircraft projection does not automatically provide tree shadows |
| New real tree → photographic ground | Needs a proven photographic receiver/composition or a real patch containing the relevant shadow footprint. If neither passes, move the proposed addition to a suitable authored area or reject that composition |
| Photo-baked tree → aircraft / new real prop | Requires an admitted proxy shadow/lighting approximation that does not double-darken photographed ground. Initially select a clear corridor with no required overhanging-photo shadow interaction |
| Aircraft crosses real/photo ground boundary | One resolved owner or a proved partition with continuous weights; no duplicate shadows, gaps or second shadow subsystem |
| Native reflection probe sees local geometry plus a panorama | Check wrong-eye projection, duplicated trees and missing surfaces; a pilot-correct photo proxy is not automatically probe-correct |

The first synthetic scene should have no reflective lake and no unavoidable
photographed canopy over the landing corridor. Test a small glossy diagnostic
object to expose sky/probe errors before admitting glossy scenery. Reuse the
existing reflection owner; a material visibility mask or alternate probe
representation is a future explicit choice with missing-reflection limits, not
an assumed solution. An aircraft may itself be glossy, so the reflection check
cannot be skipped just because no shiny prop is shipped.

Photo-baked trees remain frozen. Supported real 3D trees may use the existing
accepted-time wind within their admitted geometry/material/envelope. A static
photographed shadow under a moving replacement can still expose the illusion:
cleanup and receiver proof must include the motion. Pause/reset/site switching
must restore both rendering and physical identity without a free-running shader
clock or stale World policy.

## Why there is no universal near/far radius

For an initially centered point at forward depth `D`, a sideways camera shift
`T` at unchanged orientation moves its true image by `f × T / D` pixels, where
`f = H / (2 tan(v/2))`. A direction-only panorama cannot supply that shift.
This ideal pinhole derivation uses output height `H`, vertical FOV `v` and square
pixels. It is not a whole-scene error bound.

The [calculation](../../../../research/photorealistic-flying-sites/hybrid_parallax_review.py)
and [receipt](../../../../research/photorealistic-flying-sites/hybrid_parallax_receipt.json)
use a **hypothetical 25 cm translation** and **illustrative 2-pixel limit** at
1080 output pixels high. These are a design example, not a new camera allowance
or replacement for Q02's critical-feature thresholds.

| Vertical FOV | Minimum forward depth for this 2 px example | Missing parallax at 1 km |
| --- | ---: | ---: |
| 60° | 116.91 m | 0.23 px |
| 30° | 251.91 m | 0.50 px |
| 15° | 512.71 m | 1.03 px |
| 6° | 1,287.98 m | 2.58 px |
| 1° | 7,734.73 m | 15.47 px |

The fixed-eye proposal has `T = 0`; this table explains why simply unlocking
translation later is unsafe. It also shows why a fixed distance threshold is
insufficient for LOD: an imposed 5 cm transverse shape error at 100 m projects to
about 0.47 px at 60° but 30.94 px at 1°. That is a hypothetical geometric error,
not a measured error for an OpenRC tree or Godot's LOD implementation.

For moving views use full camera projection, real depth, disocclusion tests and
the actual output/internal/upscale configuration. On Apple Silicon Retina use
native-panel evidence. A calculated distance limit does not reconstruct hidden
branches, qualify stereo, admit an unsurveyed hillside or solve reflections.

## Concrete production workflow if the experiments pass

1. **Choose the field and camera envelope.** Use an admissible runway/contact
   layout, fixed station, clear landing corridor and independently measured
   ranges. Record image rights, tree species, size references and light direction.
2. **Assign representation ownership.** Label every selected feature as retained
   photo, 3D addition, 3D replacement or distant decoration. Bind contacts and
   shadow roles before building the scene.
3. **Prepare photographic derivatives.** Preserve masters; calibrate/stitch;
   create a clean version only where replacement requires it; retain repair masks
   and additional reference images. Prepare lighting evidence separately.
4. **Stage existing 3D assets.** Select catalog IDs, fit measured sizes, retain
   source notices and current filtering. Use the Blender/generator workflow for
   any accepted derived change; export reviewed GLB/glTF resources, not `.blend`
   files for runtime loading.
5. **Integrate one World presentation.** Combine background, local geometry,
   shadow/occlusion roles and fixed camera capabilities using C01–C07. Reuse
   resource-loading, field/contact, time and reflection owners.
6. **Qualify appearance and normal use.** Execute the selected HX cases and their
   Q01–Q12 gates: zoom, independent color/depth, shadow joins, wind, pause/reset,
   collision identity, failure recovery, exact-renderer timing and offline export.
7. **Scale only the accepted representation.** Expand asset count or survey area
   after measuring the first field. Move to a real 3D-ground/sky-only distant
   design for translated views when that route is explicitly selected.

The [experiment plan](hybrid-experiments.md) defines the comparison and stop
conditions. It proposes no new engine, terrain addon, asset purchase or wholesale
forest-demo import as a prerequisite. The result sought is a more convincing
first field with a known cost and camera envelope, not a larger list of effects.
