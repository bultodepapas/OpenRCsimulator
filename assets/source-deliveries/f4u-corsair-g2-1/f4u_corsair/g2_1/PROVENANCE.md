# g2.1 provenance

Derived from accepted g2.0; exact g1.24 wheel meshes and propeller/gear maps restored. No new reference imagery or livery was introduced. The original R59 and g1.24/g2.0 baselines remain read-only. See CHANGELOG and checks for scoped modifications and the optional I1 limitation.

# Provenance and source accounting

## Source identity and final package

The geometry master is the user-provided R59 scene, SHA-256 `94edd59b44f578b5a1f7c1fe4004c736dff47a63e2866e4b8a04532851cf4dc3`. The final editable native scene is SHA-256 `312652fe3a19d54e65a398d6090f86295cc74b9103d8d90edb5a1485840d45e9`; the delivered GLB is SHA-256 `48d0a8a3fdac1f3c7c105977183e55927cb2768a30dfb35a3b0b6639da98a173` and 21,868,200 bytes. Blender 5.2.2 LTS and its bundled glTF 2.0 exporter were used. `metadata.json` is authoritative for the final 349,878 triangles, 61 surfaces, 16 materials, frames, transforms, and node inventory.

## Source roster and visibility-led selection

The source roster comes from the g1.24 export map and is verified against the R59 master hash. It contains 8,725 unique names; `export-map.json` has exactly one accounting row per name. Authored proxies are separately listed and add no R59 roster rows.

The visibility snapshot covers ground, flight, deflected, and folded poses. It contains 5,616 mesh rows; the companion CSV is limited to its 475 rows with at least 1,000 source triangles and is not a complete source inventory. The extraction records 302 selected R59 records: 260 runtime geometry contributors and 42 bake-only donors. Each bake-only source is excluded from runtime with the exact reason `bake-only R59 donor`. All measured zero-ray sources are excluded. Three hidden F4U-1D propeller blades are selected to preserve the requested three-blade variant; these are the only selected geometry sources without visibility records, because they are hidden in the active R59 scene. The unchanged g1.24 rig is separately represented by 27 records.

Sixteen visible external `R14 | compuerta curva` skins are retained in `cowl`; cowl-flap mechanisms are excluded. All 413 visibility-tested non-skin R14 mechanism sources are excluded. The 86 unmeasured non-skin R14 roster entries are also excluded, but the visibility study does not establish their type or visibility. The 16 zero-ray `R18 | base palanca` entries are unrelated lever bases and are excluded by their zero-ray status.

## Requested detail and authored additions

| Detail | Existing g1 part or runtime node | Source and qualification |
| --- | --- | --- |
| Front engine heads, barrels, pushrods, ignition ring, reducer, magnetos/distributors | `engine_face` | Selected R59 contributors. Front-row source-name interpretation remains a review note. |
| Seat, panel edge, stick, console tops, harness | `cockpit_interior` | Selected R59 contributors. |
| Gunsight | `cockpit_interior` | Authored proxy at the accepted g1 cockpit station; visually reviewed in the refreshed preview set; historical dimensions are not claimed. It is not an R59 roster source. |
| Main/tail links, struts, brake lines | Existing `gear_*` nodes | Selected R59 sources; brake-line spans use rigid segments at moving joints. Tail-link-to-fork placement remains an inference. |
| Left/right R22 retraction guides and cylinders | `gear_retraction_link_left/right`, children of `gear_fold_left/right` | R59 sources `R22 | guia cilindro {side}` and `R22 | cilindro retractil {side}`. Carrier assignment is in `checks/carrier_assignment.json`. The geometry follows the unchanged fold carriers as a rigid visual approximation, not a solved hydraulic linkage. |
| Main and tail wheels | `gear_wheel_left`, `gear_wheel_right`, `gear_wheel_tail` | Structured revolved retopology fitted to R59 tyre/rim envelopes and accepted g1 axle, radius, and contact data. Main profiles are 32-sided, tail profile 24-sided, with open spokes. Fine fasteners are omitted. These are profile approximations, not exact R59 wheel-detail copies; see `checks/wheel_retopology.json`. |
| Left pitot | `wing_left_fixed` | Authored proxy at an inferred wing-leading-edge position; visually reviewed; historical dimensions are not claimed. It is not an R59 roster source. |
| Intake vanes, dark closures, gun-port plates, and position lights | Existing wing nodes | Selected R59 sources merged into the existing wing sections; the authored left pitot is listed separately. |
| Fold ribs, flush hinge covers, balance tabs, flap lips | Existing wing, aileron, and flap nodes | Selected R59 sources merged into existing skins/control surfaces. |
| Fuselage seams and fasteners | `fuselage_core` | R59 bake-only donors; not raised runtime geometry. |

### Local flap clearance relief

The final geometry uses buried, local flap-seat relief from the six R57 continuous upper flap-lip sources: `R57 | flap izquierda/derecha 1/2/3 labio superior continuo`. Their existing source-map rows remain included and map to the matching six flap nodes. The two included R22 sources `R22 | techo curvo pozo izquierda/derecha` remain mapped to `wing_center_fixed`; local relief is limited to the wheel-well roof areas intersected by the swept main-flap envelopes. These fit edits are inside existing moving/fixed meshes, add no separate runtime nodes, and leave the g1.24 rig unchanged.

`previews/clearance.json` records a clear sampled sweep for all six flap hinges at 0°, 1°–5°, and 10°–50°, plus clear aileron, elevator, and rudder samples. The method uses sampled BVH triangle intersections; it is not continuous collision detection and contact counts are not penetration-depth measurements. The local native 101-pose motion and gear-reference comparison also passes. The closure-face audit reuses existing section-owned surfaces and adds zero triangles; it does not claim that every merged mesh edge is manifold.

## Geometry, UVs, and surface detail

Final geometry has 349,878 triangles, within the 300,000–350,000 target; 61 mesh/material surfaces; and 16 materials. No LOD meshes are authored. Visible relief at or above 3 mm uses geometry; smaller seams, fasteners, and panel detail are baked. Reduction is per part using planar reduction/limited dissolve and structured retopology, without global collapse Decimate or subdivision.

All painted parts share the 2048 × 2048 `UVMap` with broad dominant-axis charts. The 2048 pixel-centre audit found zero multiply-covered pixels and a painted UV area sum of 0.304303. The 130 tiny projected-overlap triangles were isolated in the reserved gutter; the finite-resolution audit does not prove absence of all subpixel overlaps. Tangent-space normal and AO maps were baked selected-to-active from full evaluated R59, isolated by part, with a 2-pixel margin. Weighted corner normals were applied to the six flap meshes. Shared maps support the Naval 308 default livery in this g2 package.

The final sampled R59 deviation report has a maximum of 3.53 mm, localized to the buried flap-seat fit relief. It is a sampled nearest-surface report, not a certified continuous Hausdorff bound. Front/side/top silhouette IoU is 99.2978%, 99.7909%, and 99.9127%, with the top camera widened to 3.8 m so the complete tail remains inside the frame. All 19 refreshed Eevee views, including the actual exploded-section view, were visually reviewed. Visual review does not replace external acceptance.

## Reference history and rights

No new external references were consulted specifically for g2. The g2 geometry and paint are derived from R59/g1.24 and project-generated visibility, deviation, and review evidence; Blender 5.2.2 documentation was used for Blender authoring/export behavior. The inherited R59/g1 reference history is recorded in [g1.24 provenance](../g1_24/PROVENANCE.md): it distinguishes the Royal RC F4U-1D plan, manually sampled/digitized for proportions and stations, from the CARF manual, photographs, museum, and archive material consulted for context. No plan scans, reference photographs, or third-party image pixels are packed into the g2 native scene or GLB. `LICENSE.txt` states the project's authorship and that no license is granted; it does not grant third-party rights.

The g2 runtime package contains Naval 308 only. Other g1 liveries are outside this g2 Revision 4 request-B package. This does not declare the separate all-livery g1 fuselage correction to be part of g2.

## Derivation and editing workflow

The full derivation is machine-local and requires the R59 blend, `work/rev4_sources/selected_sources.json`, `work/rev4_B/extraction.json` and other working snapshots, paint-rasterization inputs, and the sibling `g1_24` source blend and gear reference. The documented stages are:

1. `extract_r59.py` applies the visibility-led source selection and creates the 260 working-geometry contributors and 42 exact bake donors recorded in the extraction manifest.
2. `build_geometry.py` builds the selected R59 parts against the g1.24 node/rig contract using local planar reduction and structured retopology; local R57 flap-seat and R22 roof relief is applied within the existing parts.
3. The UV/paint stage creates and verifies the shared broad-chart layout and rerasterizes Naval 308. `bake_r59.py` bakes the R59 tangent normal and AO maps selected-to-active, part-isolated, at 2048 × 2048 with a 2-pixel margin.
4. Paint refinement and `finalize_g2.py` assemble the authoritative editable `source/aircraft_game.blend`, pack the runtime maps, and write the final metadata and source map.
5. `export_g2.py` exports the packaged native at frame 100 with the gear stowed. This standalone re-export needs no R59; the packaged `.blend` is the editable source for manual revisions and re-export.

Local validation passed: native Blender audit 22/22, GLB preflight, Godot 4.7.2 import 16/16, sampled motion/clearance, deviation and silhouette reports, and standalone re-export checks. The standalone re-export had exact geometry, UV, normals, indices, image payload, and glTF JSON; 11 tangent float components differed by at most 0.000100017 under the 0.00011 tolerance because bundled MikkTSpace export rounds across processes. The re-export is therefore numerically validated but not byte-identical. See `checks/standalone_reexport.json` and the final check files under `checks/`.

**Local validation is complete; external acceptance remains pending.**
