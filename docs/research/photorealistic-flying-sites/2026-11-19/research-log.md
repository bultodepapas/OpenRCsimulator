# Review research log and evidence boundaries

2026-11-19. This is a focused adversarial follow-up to the
[original research](../2026-11-18/README.md), its ordered
[ten-plus-ten searches](../2026-11-18/search-rounds.md), and its
[24 free-resource dossiers](../2026-11-18/free-resources.md).
Those earlier investigations and 86 stable source records remain intact.

This pass retained **25 exact search strings** across optical/rendering and
asset-delivery reviews, followed by direct opening of primary documentation.
It adds a new dated source register; some pages revisit earlier references.
Do not add the record counts together and call the result unique websites or
newly adopted dependencies. The architecture review was source inspection,
not another set of internet searches.

## Search questions and order

The lead first checked panorama projection, camera FOV, calibration and GPU
measurement concepts. Two independent read-only reviewers then investigated
specific rendering and resource-delivery failure mechanisms while a third
reviewed repository integration. The lead reopened the primary references used
for the integrated conclusions. Unlike the earlier explicitly ordered 10+10
campaign, these follow-ups were parallel; no artificial total ordering is claimed.

| ID | Exact retained query | Purpose |
| --- | --- | --- |
| L01 | `site:paulbourke.net panorama equirectangular perspective field of view` | Pinhole/spherical projection |
| L02 | `site:docs.godotengine.org/en/stable/classes/class_camera3d.html keep_aspect fov project_position` | Actual FOV interpretation |
| L03 | `site:hugin.sourceforge.io panorama control points optimization lens distortion field of view` | Calibration and independent checks |
| L04 | `site:docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html overdraw texture bandwidth` | GPU cost interpretation |
| V01 | `site:docs.godotengine.org Godot 4 shadow to opacity material alpha transparent shadows depth draw mode` | Shadow receiver/composition |
| V02 | `site:docs.godotengine.org Godot 4 color space tonemapping panorama image sRGB exposure` | Color pipeline |
| V03 | `site:docs.godotengine.org/en/4.6 Camera3D fov vertical keep height project_ray_normal unproject_position` | Projection and zoom |
| V04 | `site:docs.godotengine.org/en/stable "source_color" "Compatibility" renderer shader textures linear` | Renderer color differences |
| V05 | `site:github.com/godotengine/godot equirectangular panorama seam mipmap texture gradient` | Seam/mip failure mechanism |
| V06 | `site:registry.khronos.org textureGrad discontinuous texture coordinates mipmap wrap repeat derivative` | Explicit gradients |
| V07 | `site:docs.godotengine.org "textureGrad" "shader" gradient` | Shader API |
| V08 | `site:docs.godotengine.org 4.7 camera near far depth buffer z fighting reversed z` | Clipping and precision |
| V09 | `site:pauldebevec.com view-dependent texture mapping photograph geometry depth visibility` | Geometry-backed photographs |
| V10 | `site:docs.godotengine.org gpu profiler frame time vsync debug profiler CPU GPU frame` | Timing validity |
| V11 | `site:developer.apple.com gpu performance profiling frame time CPU GPU timing vsync` | Metal timing and frame limits |
| A01 | `site:docs.godotengine.org/en/4.5 "KTX" "images" import Godot` | Standalone image intake |
| A02 | `site:github.com/godotengine/godot "KHR_texture_basisu" "ktx2" Godot glTF` | Embedded compressed route |
| A03 | `"godotengine/godot" "EXT_meshopt_compression" "KHR_meshopt_compression"` | Extension-specific support |
| A04 | `site:docs.godotengine.org "FileAccess" "imported" "source file" export resources image` | Runtime hash/loader domain |
| A05 | `site:docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html "Export all resources" "not linked"` | Shipped versus resident variants |
| A06 | `site:docs.godotengine.org "get_rendering_device" "gl_compatibility" null` | Compatibility preflight |
| A07 | `site:docs.godotengine.org "LIMIT_MAX_TEXTURE_SIZE_2D" "limit_get"` | Device limit versus memory estimate |
| A08 | `site:docs.godotengine.org "load_threaded_request" "cancel" ResourceLoader` | In-flight ownership |
| A09 | `site:docs.godotengine.org/en/4.7/tutorials/export/exporting_pcks.html "Security concerns" script` | Deferred pack trust boundary |
| A10 | `site:docs.godotengine.org "resource pack" "replace_files" "loaded" cache` | Mounting/override limitations |

These strings are a retained research record, not a complete raw search-response
transcript. Direct opens, code reads and follow-up finds are not counted as extra
investigations. Search snippets alone do not establish a capability.

## Primary-source register

All entries were reviewed on 2026-11-19. Versioned Godot documentation is method
guidance; it does not qualify the repository's 4.8.beta2 binary. Moving
`stable`/GitHub pages need exact-version checks during implementation.

### H01

[Paul Bourke — equirectangular to perspective projection](https://paulbourke.net/panorama/sphere2persp/index.html).
Supports the ideal projection model and FOV calculations. The paper/site
description is a geometry reference; availability of code there is not a grant
to import it as a free project dependency.

### H02

[Godot Camera3D reference](https://docs.godotengine.org/en/stable/classes/class_camera3d.html).
FOV/keep-aspect, projection and near/far API guidance. OpenRC's actual 1° limit
comes from CameraRig source, not this page.

### H03

[Hugin control-point workflow](https://hugin.sourceforge.io/docs/manual/Hugin_Control_Points_tab.html).
Supports distributed matching observations. Independent held-out survey checks
are this plan's additional acceptance requirement.

### H04

[Hugin photos/calibration workflow](https://hugin.sourceforge.io/docs/manual/Hugin_Photos_tab.html).
Orientation, FOV and optimization context. A successful stitch is not an
independent obstacle-range measurement.

### H05

[Hugin lens correction model](https://hugin.sourceforge.io/docs/manual/Lens_correction_model.html).
Lens/FOV/radial-shift model context. Retain actual calibration settings instead
of assuming an arbitrary 360 camera is distortion-free.

### H06

[Debevec, Borshukov and Yu — Efficient View-Dependent Image-Based Rendering with Projective Texture-Mapping](https://www.pauldebevec.com/Research/VDTM/).
Original 1998 projective image/geometry method. It supports the technique,
not a Godot addon or a promise that one photograph determines range.

### H07

[Godot 4.6 material reference](https://docs.godotengine.org/en/4.6/tutorials/3d/standard_material_3d.html).
Depth/blend/shadow material concepts. Receiver ownership and baked-shadow
overlap are reasoned integration cases requiring actual captures.

### H08

[Godot 4.7 shading language](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/shading_language.html).
Color-source hints, interpolation and shader representation. It does not
validate copying OpenRC's historical Compatibility compensation into a new path.

### H09

[Godot 4.6 Environment reference](https://docs.godotengine.org/en/4.6/classes/class_environment.html).
Environment operation/output-transform context. A matching proxy/background
join alone is not proof of correct source-photo color.

### H10

[Godot 4.4 shader functions](https://docs.godotengine.org/en/4.4/tutorials/shaders/shader_reference/shader_functions.html).
Documents explicit texture gradients. Exact shader compilation and filtering
remain renderer/pin experiments.

The integrated review also checks exact atan cardinal/polar behavior and how
ordinary shader materials achieve horizontal repeat with vertical clamp at each
mip. CPU math and a single repeat hint do not qualify those cases.

### H11

[Khronos EXT_shader_texture_lod specification](https://registry.khronos.org/webgl/extensions/EXT_shader_texture_lod/).
Explicit LOD/gradient control reference, not a proposal to add WebGL to OpenRC.
The branch-cut remedy is an engineering inference requiring a seam fixture.

### H12

[Godot 4.7 rendering limitations](https://docs.godotengine.org/en/4.7/tutorials/3d/3d_rendering_limitations.html).
Texture/depth constraints and near-plane tradeoffs. General platform wording
does not identify the actual framebuffer/depth format on a tested device.

### H13

[Godot 4.7 project export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html).
All-resources mode and non-resource filters. OpenRC's actual preset contents
were inspected separately.

### H14

[Godot 4.7 import process](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/import_process.html).
Imported-resource remapping and ResourceLoader versus FileAccess boundaries.
Separating authoring and exported identities is this review's design decision.

### H15

[Godot 4.7 ResourceLoader](https://docs.godotengine.org/en/4.7/classes/class_resourceloader.html).
Threaded request/status/get, polling and blocking-get behavior; the documented
interface has no cancellation method. Retirement behavior still needs pin tests.

### H16

[Godot RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html).
Global device query returns null on OpenGL/headless. Used-resource statistics
are not a reservation of free physical video memory.

### H17

[Godot RenderingDevice](https://docs.godotengine.org/en/stable/classes/class_renderingdevice.html).
Limits/timing/resource API context; unavailable with Compatibility. No
implementation in this branch calls it.

### H18

[Godot 4.4 optimization guidance](https://docs.godotengine.org/en/4.4/tutorials/performance/general_optimization.html).
Measurement/profiler and synchronization guidance. The proposed paired-run
statistic and noise decision are project-specific engineering choices.

### H19

[Apple — improving graphics performance and settings](https://developer.apple.com/documentation/Metal/improving-your-games-graphics-performance-and-settings).
The HTML initially exposed a JavaScript shell; its official
[Markdown representation](https://developer.apple.com/documentation/metal/improving-your-games-graphics-performance-and-settings.md)
was opened. CPU/GPU timing and delivered frame limits are distinct.

### H20

[Godot resource packs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_pcks.html).
Packs can include executable project content and override paths. Downloaded-pack
authentication/isolation is a deferred feature, not a new pilot prerequisite.

### H21

[Khronos glTF extension rules](https://github.com/KhronosGroup/glTF/blob/main/extensions/README.md).
Distinguish extension use, requirement and fallback. Inspect the exported
document and consumer, not only the optimizer's exit status.

### H22

[Khronos KHR_texture_basisu](https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_texture_basisu/README.md).
Embedded texture-extension semantics. It does not establish standalone KTX
import support or support in the pinned Godot release.

### H23

[meshoptimizer gltfpack guide](https://github.com/zeux/meshoptimizer/blob/master/gltf/README.md).
Conditional optimization/preservation controls. Preserve required names,
materials and extras with verified output; flags alone are not that proof.

### H24

[Godot 4.7 GLTFDocument](https://docs.godotengine.org/en/4.7/classes/class_gltfdocument.html).
Registered extension inspection and import context. Successful fallback loading
must not be misreported as an accepted compressed extension.

### H25

[Godot GPU optimization](https://docs.godotengine.org/en/stable/tutorials/performance/gpu_optimization.html).
Hardware-dependent draw, bandwidth and overdraw costs. No plugin/demo throughput
is substituted for the full OpenRC workload.

## Repository audit and current-main comparison

The planning baseline is
[`0dac71fc`](https://github.com/bultodepapas/OpenRCsimulator/tree/0dac71fc8a829a8a9ea33fd62c4e45703f4021ca).
The fetched main revision is
[`1188f1d4`](https://github.com/bultodepapas/OpenRCsimulator/tree/1188f1d4a1e31fd8263336b645db86535bca062f).
No rebase or merge of unrelated runtime changes was needed for this
documentation/analysis revision.

| Source seam inspected | Fact relevant to the review |
| --- | --- |
| `app/render/camera/camera_rig.gd`, `pilot_camera.gd`, `app/spec.gd` | Final 1°–120° pilot FOV; repeated near-plane assignment and existing far distance |
| `app/render/shadow_settings.gd`, `shadow.gd`, `projected_shadow_receiver.gdshader` | Requested/effective shadow logic, sun-range handoff and alpha receiver |
| `app/render/world/world.gd`, `engine_srgb.gdshaderinc` | Global presentation ownership and version-scoped color workaround |
| `app/sim/scenery_damage.gd`, `scenery_collision.gd`, `app/render/crash/scenery_damage.gd` | Broken-group collision removal versus mesh-only visual damage |
| `app/app_state/preferences.gd`, `app/app_root.gd`, `app/ui/field_error.gd` | Saved landscape, cold startup, staged transitions and Quit-only field failure |
| `app/ui/home.gd`, `app/scenarios/scenario_config.gd`, `natural_random.gd` | Shared runway flag versus default-field-only scenario validation |
| `app/physics/ground_surfaces.gd`, `ground_terrain.gd` | Outside-region rough catch-all and material/relief coupling |
| `app/sim/environment.gd`, `flight_session.gd`, `flight_log.gd`, `app/tools/flight_log_cli.gd` | Live registry provenance versus raw-array numerical replay |
| `app/scenery/collision_world.gd`, `app/sim/flight_log.gd` | Bounded bins and whole-world log packet admission |
| `app/export_presets.cfg`, `app/export.sh`, `app/tests/check_field_pack.gd` | All-resources exports, non-resource filters, host-side pack inspection versus target execution, and final archive/sidecar assembly |
| `app/tests/test_optional_resource_loading.gd` | Existing unselected/released resource-cache test seam |
| `tools/trees/package.json`, `tools/ground/`, tool/graphics guides | Preserve existing pinned intake and diagnostic workflows |

Blob comparisons found the originally cited source files unchanged between the
two revisions except `app/app_root.gd`. The lead fetched and reviewed that diff:
the changes concern telemetry/error reporting and Home note handling; the
startup and Natural Random guard mechanisms described here remain present.
The integrated delivery review additionally inspected `app/export.sh`; its
main-branch change adds telemetry configuration validation, leaving the cited
host-side package inspection and final archive assembly unchanged.
The wider scoped comparison also showed telemetry-related settings/telemetry
screen changes. No new current-main fix for the identified photo-site seams
was found in that scoped inspection. This is not a claim to have audited every
main-branch change.

## Retrieval limitations and counterevidence

Direct web retrieval of exact pinned Godot source at
`cafc17a192acf67903910a68aeb3c076c0907a4b` failed during the helper reviews.
Master engine source, older docs and issue reports cannot fill that evidence
gap. Therefore this review makes no new exact-pin codec, framebuffer or shader
support claim. Those are future Q01/Q04/Q10 target experiments.

The plan already treated codecs and addons conditionally, retained the adopted
maple mipmap history, warned about noncancelable loading, separated visual and
physical worlds, and required global rollback. The review preserves those
correct decisions and narrows its criticism to the remaining mechanisms and
proof gaps. A stronger plan must not obtain apparent findings by ignoring
existing safeguards.

## Work actually executed in this follow-up

Read-only GitHub/source review, the retained web investigations, primary-page
verification, documentation revision and a dependency-free analytical script
were performed. The arithmetic receipt exercises the proposed coordinate
convention and reproduces the zoom/memory estimates.

No panorama was captured, no third-party asset adopted, no addon installed,
no engine changed, and no simulator, import/export, GPU capture or hardware
benchmark was run. The new tests and budget numbers are proposals, not measured
performance or implementation completion. Documentation and independent-review
verification are recorded in this pack's [README](README.md).
