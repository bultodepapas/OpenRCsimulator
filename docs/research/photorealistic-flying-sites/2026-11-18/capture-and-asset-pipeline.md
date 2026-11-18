# Capture and asset pipeline

2026-11-18. Proposed authoring workflow; no capture or asset conversion was
performed for this plan. The [source register](sources.md) records tool evidence,
and [validation](validation-and-budgets.md) separates survey accuracy from visual
and software acceptance.

## 1. Define the first site before taking photographs

Prepare a short site brief with the landowner/capture and distribution permission,
author, exact pilot station, runway dimensions/bearing/material, relevant
obstacles, desired aircraft activities, one daylight condition and intended test
hardware. A flat, visually simple RC field is a better first candidate than an
irregular hillside with a lake and dense nearby fencing.

Check representability against current field/start/contact contracts before
committing to the asset. Existing field v1 cannot faithfully describe arbitrary
runway orientation, sloped ground or arbitrary surveyed obstacle input without
the separately owned work in SC-PHOTO-04/04b. Select a compatible site or include
that work explicitly. An attractive photo is not grounds to hide mismatched
physical geometry.

Also check surface material: the current runway contact table is maintained
turf with estimated microrelief. A paved photographic strip needs explicit
site-specific material wiring and qualification; changing its ground image or
field ID does not provide asphalt physics. Record remaining material estimates
even when choosing a turf pilot.

Capture a synthetic calibration fixture first. A generic clearly licensed HDRI
can then test appearance/import, but it cannot supply measured runway or obstacle
truth. The release field needs its own calibration evidence.

## 2. Record a measured reference frame

The source package should distinguish measured, estimated and derived quantities.
Retain raw observations, units, instrument/method and uncertainty, not just the
final fitted numbers.

| Record | Purpose |
| --- | --- |
| Pilot station and lens entrance-pupil height | Fix the viewpoint; distinguish ground elevation from camera eye elevation |
| Runway corners, centerline and threshold positions | Establish length, width, bearing, surface and launch alignment |
| Distributed landmarks, including held-out points | Fit orientation and independently check it; avoid validating on only the fitting points |
| Near obstacle dimensions and distances | Create meaningful visual/physical proxies; photograph alone cannot reveal hidden volume |
| Level reference and compass/geographic basis | Separate actual horizontal from the irregular skyline and avoid flipped/mirrored axes |
| Time, location, sun/shadow direction and lighting references | Match dynamic aircraft light to the captured image, with estimated values labeled |
| For geospatial work: CRS and vertical datum | Preserve map coordinates/elevation before conversion to local NED metres |

Keep absolute geographic coordinates out of ordinary Godot render positions.
Use the declared local NED origin and the existing render conversion. If the
real site needs another basis, transform *all* relevant geometry, headings,
wind/light directions and geographic calculations through an owned contract.
Rotating only the panorama breaks that agreement.

## 3. Capture a panorama from one point

A phone or 360 camera can produce an early appearance test. For the final asset,
judge measured image detail and near-object seams; a stitched still-camera
capture may provide better detail without requiring a new hardware purchase.
Use existing equipment for a small trial first.

Use a stable support, fixed lens/pivot, consistent focus, white balance and
exposure where practical, and adequate overlap. Rotate around the lens's
no-parallax point; moving the camera between shots shifts nearby features
against distant ones ([C02](sources.md#c02), [C03](sources.md#c03)). A dual-lens
360 camera can also have near-seam problems and is not exempt from inspection.
Record the actual height rather than adopting a tutorial's example.

Cover the full horizon, zenith and nadir for a true 360°×180° asset. A wide
horizontal phone panorama is not automatically a full sphere. Plan how to remove
the tripod/nadir obstruction while preserving the original camera station.
Keep moving people, aircraft, flags and clouds from creating duplicate subjects
or mismatched seams. If bracketed HDR capture is used, inspect ghosting and
changing illumination instead of assuming bracketing improves every result.

Record any removed/retouched person, plate, sign or private detail in the
authoring history when relevant. Do not introduce fictional runway/obstacle
geometry through image repair and then present it as surveyed reality.

## 4. Stitch, calibrate and make runtime variants

Use Hugin as the initial open workflow, retaining its project/control points;
PTGui is an optional comparison on the same images ([C01](sources.md#c01),
[C04](sources.md#c04)). Produce a high-quality master plus losslessly retained
calibration values. The runtime source is a full 2:1 equirectangular image for
the first candidate, unless SC-PHOTO-02 proves another representation is needed.

Inspect wrap, poles, near objects, horizon level, exposure steps and duplicate
details. Fit the declared orientation to surveyed directions and then check
held-out landmarks. Correct real stitch errors; do not distort the image to
hide inaccurate physical data. Save actual source resolution and any upscaling;
upscaling does not count as captured detail.

Create controlled 4096×2048, 8192×4096 and, where justified by the source,
16384×8192 variants. Preserve the same crop, orientation and color treatment.
Specify mipmaps, filter/repeat behavior, color space and runtime compression per
target. A TIFF master must be converted to a format supported by the chosen
Godot importer; copying a competitor's authoring format is not a runtime design
([G04](sources.md#g04)).

If a target cannot load the larger image, choose a smaller variant before
allocation. Tiling/cubemap conversion is a separate measured option, with
face orientation, mip gutters and seams checked. It can solve a dimension limit
without solving total-memory cost. Keep visible background resolution separate
from a smaller illumination/reflection resource when appropriate.

## 5. Author visual occlusion and physical contacts separately

In Blender, place measured ground, runway/landmark overlays and simple proxy
geometry in one documented metric frame. Use named survey IDs consistently in
the source, export and physical inventory. The camera-projected photo receiver
and masks describe visual depth. The contact inventory describes supported
physical shapes and responses. Some features need both; distant background
may be explicitly nonphysical outside the admitted area.

Do not assume exporting a Blender collider or Terrain3D collision node makes
it visible to the custom simulator. SC-PHOTO-04 must choose the validated
existing-input route or add the scoped physical-inventory authoring/builder.
Export only accepted shape parameters, materials and stable IDs through that
owner. Collision dimensions do not change with mesh LOD or texture quality.

Preserve the photograph's baked static shadows. Add only the dynamic aircraft
shadow and intentional new-object shadows through the qualified composition
method. Reject double structures, visible proxy edges, hidden physical obstacles
or false collision across open fence/foliage gaps.

## 6. Additional pipeline for the 3D site

Capture overlapping ground and oblique views with enough coverage of runway,
structures and obstacle sides. Retain metadata and well-distributed surveyed
control/check points. OpenDroneMap's capture and GCP guidance is a useful
starting point ([P02](sources.md#p02), [P03](sources.md#p03)); coverage parameters
must be selected for the actual camera and site, not copied without a trial.

Use OpenDroneMap/WebODM initially, or compare a selected alternate reconstructor
on the same small dataset. Retain the textured mesh, orthophoto, point cloud,
processing settings and logs. Request DTM/DSM explicitly when needed. DTM is the
ground model, DSM includes surfaces such as tree/building tops; neither is
automatically a perfect landing surface ([P01](sources.md#p01)). Measure held-out
errors and inspect featureless grass/asphalt, foliage, reflective surfaces,
holes and missing sides.

Use QGIS/GDAL to preserve/correct the map reference, crop and resample at a
deliberate metric spacing ([A03](sources.md#a03), [A04](sources.md#a04)). Carry
CRS, local origin, vertical datum, raster size, pixel-center convention, row
direction, no-data mask, scale and offset in a sidecar. If Terrain3D is selected,
follow its float EXR or R16 guidance and retain real elevation/spacing metadata
([T04](sources.md#t04), [T05](sources.md#t05)). Do not quantize measured heights
to an 8-bit color image or silently assume one pixel equals one metre.

In Blender, repair and simplify landmark meshes, bake sensible material maps,
split spatially useful chunks, preserve scale/pivots, and make LODs. Prefer a
glTF/GLB delivery that the project can import reproducibly
([G05](sources.md#g05)). Retain the high-resolution source outside the ordinary
runtime package. Inspect normals, tangents, alpha, material count, silhouette
and actual texture residency after import.

Orthophotos and scans contain baked shadows/vegetation. Remove or account for
them where dynamic lighting or new 3D trees would duplicate the photograph.
Use a far background containing only scenery valid across the admitted moving
camera volume. A full near-field panorama is not a correct infinite-distance
environment for FPV.

Any new ground-height provider must have the independent CPU/float64 sampling
and physics/replay/native contracts described in the [design](godot-design.md).
Produce visual terrain and physical terrain from one versioned source; do not
sample a frame-dependent GPU-displaced mesh as the physics definition.

## 7. Reproducible package and provenance

| Artifact | Retain / distribute policy |
| --- | --- |
| Original capture and high-resolution scan | Durable source location, immutable hashes and capture/rights record; exclude unnecessarily large binaries from ordinary Git history |
| Stitch/reconstruction/Blender source | Tool versions, source references, parameters and edits; enough to regenerate the accepted runtime result |
| Runtime image/mesh variants | Exact accepted dimensions, formats, hashes and import settings; only variants actually required by supported targets |
| Physical field and inventory | Validated schema version, survey provenance, stable identities and no dependency on graphics preset |
| Presentation descriptor | Asset/field binding, station, orientation, captured light, capabilities and explicit limitations |
| Notices and credits | Per-source license evidence and modifications; required attribution packaged for offline access |
| Acceptance receipt | Source/build/hardware identity, calibration errors, representative captures and metrics, unresolved limits |

Content hashes and generator/tool configuration make changes traceable. A hash
does not prove that a photo is licensed or a runway is accurate. Keep those
independent evidence fields.

## 8. Review the result in the simulator

Import with the pinned engine and inspect the real Home and flight routes.
Compare the captured scene with the calibrated pilot view, then perform
takeoff/landing, edge-of-object occlusion, collision and zoom checks. Use
actual exported packages for final device qualification and clean offline
resource validation. Retain only compact evidence required to assess those
gates; the task does not require filling the Git repository with large images.
