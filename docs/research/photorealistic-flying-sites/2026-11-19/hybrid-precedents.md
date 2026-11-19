# Hybrid scenery: people and projects that already did parts of it

2026-11-19. Twelve evidence dossiers for the
[hybrid design](hybrid-scenery.md). These are not twelve Godot photo-field
implementations. They include direct RC practice, production methods for 3D
worlds, a source-inspected Godot composition, and a negative/control example.
The distinctions determine what OpenRC can reasonably reuse.

**Evidence labels:** official authoring documentation; first-person creator
account; source-inspected configuration/code; documented design. No external
project was executed, and no binary asset was downloaded for this follow-up.
The [source register](hybrid-search-log.md#primary-source-register) gives exact
URLs and retrieval limits; the [reuse audit](hybrid-reuse-audit.md) connects the
ideas to OpenRC rather than introducing another scenery stack.

## HP01 — neXt / Eiperle CGM

**Evidence:** official scenery-construction guide, [HS01](hybrid-search-log.md#hs01).
Its Blender template places the camera inside a panoramic cube and includes
textured boards, a stake and a table. It also describes photographic ground
mapping and alpha-masked foreground work.

**Transfer:** the closest documented workflow for a fixed-eye photo field with
visible authored props: use photographs for distant appearance and selected
geometry for local depth. **Boundary:** template downloads and conversion
services are not redistribution permission. Its capture/coordinate conventions
are not OpenRC's measured eye or NED frame. Adopt the authoring distinction and
test our own projection, occlusion and contacts; do not copy the scene or its
simulator-specific security geometry. Applies to HM01/HM03/HM06 and HX01/HX03.

## HP02 — ClearView RC Flight Simulator

**Evidence:** official collision/scenery authoring documentation,
[HS02](hybrid-search-log.md#hs02). `loadObjects` adds visible 3D houses, trees,
runways and helipads to photographic scenery. The guide treats `controls.ac`
collision objects separately and walks through a FarmField fence example.

**Transfer:** separate visible additions from hidden/contact geometry and keep
their transforms reviewable. This directly supports the user's proposed mix of
photo scenery with existing trees. **Boundary:** a visually matched fence is not
an independently surveyed obstacle. OpenRC still needs stable physical IDs,
damage policy, zoom/depth qualification and strict field admission; ClearView's
file format is not a runtime dependency. Applies to HM01 and HX01/HX05.

## HP03 — RealFlight G3 / developer account `jaafit`

**Evidence:** a first-person development account in a dated 2005 discussion,
[HS03](hybrid-search-log.md#hs03), especially posts 6 and 8. It describes visible
objects—including moving trees, windsocks, buildings and runways—in PhotoFields,
alongside invisible collision/occlusion objects and sun alignment.

**Transfer:** photo fields can contain both visible dynamic scenery and invisible
depth proxies; the two roles should not be confused. **Boundary:** this is
historical G3 evidence, not a current Evolution plugin specification or proof of
today's APIs. The accompanying panorama-authoring discussion is a useful shadow/
proxy example, not permission to reuse photographs. OpenRC's captured background
remains static even when an admitted real tree moves. Applies to HM01/HM07/HM09.

## HP04 — aerofly creators `jparia` and `momentmal`

**Evidence:** first-person posts on the official community forum,
[HS04](hybrid-search-log.md#hs04). In November 2024 `jparia` described putting
tables, a radio, tank and flag into an RC7 panorama, initially reporting trouble
with newer versions. In December the same thread reports RC10 object conversion
and integration progress; `momentmal` discusses Blender export/material issues.

**Transfer:** visible local props are practical, and authoring/export details
matter as much as the panorama itself. **Boundary:** do not freeze the thread at
its initial failure, or turn later creator reports into an official, complete
RC10 SDK contract. This is additional RC precedent with incomplete portability
and no OpenRC asset rights. It reinforces generated-asset provenance, separate
material roles and packaged-resource tests. Applies to HM01/HM06 and HX05.

## HP05 — PicaSim / Danny Chapman

**Evidence:** the project's parallax-panorama design and current README,
[HS05](hybrid-search-log.md#hs05). The design uses scene-depth-dependent stereo
offsets with expanded cubemap tiles and boundary correction.

**Transfer:** depth-aware photographic backgrounds need explicit edge and
discontinuity treatment; simply drawing a sphere is insufficient. **Boundary:**
the reviewed document is design/source guidance, not our runtime validation or
a guarantee of arbitrary movement and hidden-surface reconstruction. PicaSim's
own application/framework code is under PolyForm Noncommercial; bundled
third-party code has its own licenses and images/models have separate
permissions. It is not a generic permissively licensed scenery donor. Keep this
as a later SC-PHOTO-13 comparison, not a prerequisite for the fixed hybrid.
Applies to HM12 and HX06.

## HP06 — Valve / Source SDK 3D skyboxes

**Evidence:** source inspection at
`e1f1fd42271805072f052051c26c21caa2c87b04`,
[HS06](hybrid-search-log.md#hs06). `sky_camera` exposes a scale; the skybox view
transforms the camera origin, renders world/opaque/translucent geometry and
arranges a depth clear before the main scene. Fog distances are also scaled.

**Transfer:** distant geometry can have a different rendering budget and view
transform from the local scene. **Boundary:** the inspected code proves a
configurable scale, not a universal 1:16 constant. It is engine-specific distant
geometry, not photographic local depth. The SDK license is scoped to modified
Valve games on Source 1; no implementation is copied into Godot. Ordinary distant
meshes are the simpler OpenRC baseline before a separate skybox pass is justified.
Applies to HM11 and HX06.

## HP07 — The Vanishing of Ethan Carter / The Astronauts

**Evidence:** production accounts by **Adam Bryla** on foliage and
**Andrzej Poznański** on photogrammetry,
[HS07–08](hybrid-search-log.md#hs07). The foliage account combines real plant
photographs, authored plant elements and vertex-driven motion, with attention
to scale, species composition and ground intersections. The photogrammetry
account describes photo-derived 3D assets.

**Transfer:** preserve photographic richness while using selective authored
geometry and material work to make a coherent site. OpenRC can select matching
existing species and ground palettes before making new trees. **Boundary:** this
is a 3D-world production method, not evidence that a full photographic panorama
can support free movement. The articles grant no right to ship game assets.
Applies to HM05/HM08 and HX01/HX03.

## HP08 — Book of the Dead / Unity Demo Team

**Evidence:** **Zdravko Pavlov** describes scanned lower trunks joined to authored
upper trees and reorganized scan-derived foliage atlases. **Julien Heijmans**
describes wind, scene construction and optimization;
[HS09–10](hybrid-search-log.md#hs09).

**Transfer:** a tree can combine capture and modeling instead of choosing one
exclusive technique. Use a matching trunk/crown/atlas workflow only when OpenRC's
existing assets fail the site reference. **Boundary:** the production used its
own tools, shaders and asset agreements. A free Unity sample does not establish
Godot redistribution rights. The separately published DeLightingTool is an old
authoring-tool candidate ([HS11](hybrid-search-log.md#hs11)), not a runtime
panorama-relighting solution. Applies to HM05/HM07/HM08 and conditional asset work.

## HP09 — Epic Open World / Kite production

**Evidence:** Epic's account by **Harrison Moore**, with a related production
discussion by **Min Oh**, [HS12](hybrid-search-log.md#hs12). The workflow captures
objects and lighting references, removes captured light from asset textures,
repairs incomplete geometry, and prepares optimized meshes, materials and LODs.

**Transfer:** capture lighting evidence separately and treat scan cleanup and
game-asset preparation as real production work. **Boundary:** an HDR lighting
panorama in this workflow is not the fixed-pilot photo field itself. Article
availability and a free asset collection do not establish unrestricted Godot
use of the collection. Use our own/cleared imagery and the existing import
pipeline. Applies to HM05/HM07 and SC-PHOTO-07/11.

## HP10 — Microsoft Flight Simulator 2020 SDK

**Evidence:** official SDK overview,
[HS13](hybrid-search-log.md#hs13). It describes photogrammetric tiles, elevation
plus aerial imagery, and elevation plus synthesized ground textures, with
scenery/package tooling for other content.

**Transfer:** mix different source representations according to coverage and
quality rather than demanding one universal technique. For OpenRC, that means
surveyed local ground/objects and a clearly bounded distant appearance.
**Boundary:** this is large-world pipeline precedent, not a cheap way to acquire
the simulator's proprietary imagery, a fixed-eye photo field, or justification
for adding global streaming/geodesy to the first site. Applies to HM03/HM11 and
the later 3D-site comparison.

## HP11 — GamesNotDeveloped / Godot Procedural Forest Demo

**Evidence:** source-inspected commit
`623212ffeb4efbf4c95323a4a6a57e726be4f6e9`,
[HS14](hybrid-search-log.md#hs14). The actual main-scene UID resolves to
`levels/test_biomes.tscn`. Its environment/sky chain binds Poly Haven's Autumn
Field Pure Sky EXR; the same scene uses procedural terrain, real tree scenes,
grass and generated distant billboards. The scripts build ArrayMesh/MultiMesh
geometry. The near/far tree code explicitly disables visibility fading.

**Transfer:** a concrete Godot composition using photographic sky plus actual
ground and plants, with inspectable asset and LOD plumbing. **Boundary:** it
declares Godot 4.6/Forward Plus and includes environment/compositor features
requiring separate portability work. It proves neither a full photo-ground
join nor OpenRC performance. Its layered sky adds animated clouds/sun and does
not separate visible/radiance samples. Check per-asset licenses: the inspected
pine is credited to **evolveduk** under CC BY 4.0; that says nothing about every
other model. Learn from the composition while retaining OpenRC's existing
vegetation, time and World owners. Applies to HM04/HM07/HM10 and HX01/HX04/HX06.

## HP12 — Navier8 / Godot stereoscopic panorama control

**Evidence:** repository README, `world.tscn` and shader,
[HS15](hybrid-search-log.md#hs15). The panorama is mapped to an inward-facing
sphere. The matching glTF node is explicitly invisible in the reviewed scene;
the author describes the sphere-depth limitation.

**Transfer:** useful as a negative/control example when checking claims of
photo/3D integration. **Boundary:** a panorama demo containing a model file is
not evidence that the model and panorama are visibly integrated. It does not
qualify physical depth, moving views or a real photographed source. Do not count
this as a successful full hybrid field. A separate
[Rokojori scene source](hybrid-search-log.md#hs16) does wire a PanoramaSkyMaterial,
ground and a GrassPatch together, but the retrieved text did not establish
whether that sky is a photograph or clear the asset license. Applies to HM12
and source-evidence discipline, not an adoption decision.

## What to reuse first

The most direct first-field authoring lessons come from **neXt and ClearView**.
The most useful vegetation-production lessons come from **The Astronauts and
the Unity Demo Team**. The **Godot forest demo** gives an inspectable scene-level
example and concrete warnings about renderer assumptions. The later stereo,
distant-geometry and world-generation cases remain options with explicit limits.

The [six proposed experiments](hybrid-experiments.md) turn those lessons into
reviewable decisions using existing OpenRC assets. No simulator screenshot,
marketing description or sample download is treated as measured proof for
OpenRC or as a blanket asset license.
