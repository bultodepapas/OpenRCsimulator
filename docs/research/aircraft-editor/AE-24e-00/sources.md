# Primary sources and retrieval scope

Reviewed 2026-11-18. Current implementation findings use OpenRC commit
`cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c`. Web pages are evidence at review time;
image bytes are independently pinned in the research asset lock. This is a
technical/source inventory, not a new asset license.

## Engine version and rendering

| Source | Specific finding / applicability |
| --- | --- |
| [OpenRC engine pin](../../../../app/get-godot.sh) | Version `4.8.beta2.official.cafc17a19`; OS-specific archive/binary verification already lives here |
| [Godot 4.8 dev 4 release notes](https://godotengine.org/article/dev-snapshot-godot-4-8-dev-4/#rendering-decal-support-for-the-compatibility-renderer) | Introduces Compatibility decals via GH-118070; describes hard eight per surface and a hardware-dependent default 64/frame |
| [Godot 4.8 beta 1](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-1/) and [beta 2](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/) | Beta 1 carries the feature; beta 2 is built from `cafc17a19` and lists subsequent fixes |
| [Exact GLES3 renderer source](https://github.com/godotengine/godot/blob/cafc17a19/drivers/gles3/rasterizer_scene_gles3.cpp) | Directly retrieved through GitHub at the build ref: `pair_decal_instances` bounds `decals_count` at source line 139; lines 3987–3998 set decal indices/count; lines 4676–4677 bound global count by UBO capacity |
| [Exact GLES3 shader](https://github.com/godotengine/godot/blob/cafc17a19/drivers/gles3/shaders/scene.glsl) | Source line 1172 declares the decal-count uniform; line 2474 loops over and applies decals. Confirms an implementation path, not rendered or hardware proof |
| [Exact GLES3 configuration](https://github.com/godotengine/godot/blob/cafc17a19/drivers/gles3/storage/config.cpp) | Reads `rendering/limits/opengl/max_decals`; hardware UBO capacity participates in actual allocation |
| [Using decals, latest](https://docs.godotengine.org/en/latest/tutorials/3d/using_decals.html) | Describes receiver masks, depth, normal fade, camera/AABB sorting, screen-coverage cost, filtering and Compatibility eight-per-mesh/default-64-per-view limits; mutable development documentation |
| [Decal class, stable](https://docs.godotengine.org/en/stable/classes/class_decal.html) and [class XML at the actual build ref](https://github.com/godotengine/godot/blob/cafc17a19/doc/classes/Decal.xml) | Still state no Compatibility support in retrieved text. This is a documentation conflict, resolved for architecture by the exact GLES3 implementation and release line; do not repeat the stale claim |
| [3D rendering limitations](https://docs.godotengine.org/en/latest/tutorials/3d/3d_rendering_limitations.html#transparency-sorting) | Transparent surfaces have sorting limitations; render priority alone is not a substitute for nonintersecting geometry and tested layer composition |
| [StandardMaterial3D / BaseMaterial3D](https://docs.godotengine.org/en/stable/classes/class_basematerial3d.html) | Material alpha, depth, culling, shading and priority are the relevant overlay controls; exact beta behavior must be measured |

GitHub's `4.8-beta2` tag query did not resolve in the connector; querying the
release's actual build ref `cafc17a19` succeeded. Raw-source search pages could
not be fetched by the search service. Direct GitHub source retrieval supplied the
exact implementation evidence. This difference is retained so a later reviewer
does not mistake unavailable retrieval for absent engine support.

## Logo source and relationship evidence

| Source | Use in the handoff |
| --- | --- |
| [OpenRC supporters](../../../../README.md#sponsors-and-supporters) and [BRANDS](../../../../site/BRANDS.md) | Authoritative existing public relationship/scope summaries and original logo provenance |
| [Official Savox downloads](https://www.teamsavox.com/download/), [logo package](https://www.teamsavox.com/TeamSavox-Logos-Package.zip), [brand book](https://www.teamsavox.com/TeamSavox-Brandbook.pdf) | Official image source, variants and presentation rules |
| [Official SonicModell header](https://www.sonicmodell.com/u_file/weblogo/fbb0fc46c2.png) | Source URL recorded with the unchanged tracked mark |
| [Hitec official site](https://www.hitecrcd.com/) and [footer image](https://cdn11.bigcommerce.com/s-gatcxyxclp/images/stencil/original/image-manager/hitec-radio-logo-footer.png) | Source URL recorded with the existing asset; actual signature is WebP despite its URL/path extension |
| [FLYWING](https://flywingrc.com/) | Existing official storefront-logo provenance; grant scope comes from BRANDS |
| [REVOC downloads](https://shop.revoc.eu/telechargement) and [PNG](https://shop.revoc.eu/userdata/public/assets/images/logo/revoc-custom-logo.png) | Official download page explicitly supplies the logo; existing project grant is a supporter credit |
| [OpenAI guidelines](https://openai.com/brand/) and [logo package](https://cdn.openai.com/brand/openai-logos.zip) | Official unchanged wordmark; proportional/context/approval rules; no invented ChatGPT or Codex symbol |
| [JETI original](https://www.jetimodel.com/public/views/assets/img/logo-jeti.png) and [Jumper original](https://www.jumper-rc.com/wp-content/uploads/2020/03/%E6%9C%AA%E6%A0%87%E9%A2%98-22.png) | Existing exact originals and source record in the Avanti sponsor folder |
| [RadioLink T16D image source record](../../../../assets/ui/radiolink-t16d/README.md) | Public source and specific owner-reported simulator imagery context; distinct from editable decal rights |
| [Missing-logo source table](sponsor-register.md#official-source-candidates-for-missing-images) | Official GEMFAN, KONTRONIK, Leomotion, Aloft, RadioLink and GM intake leads; no inferred grant or recreated logos |

The published relationship/source record uses public repository documentation and
official websites. Private correspondence and derived private summaries are not
part of this public handoff. Owner-reported statements already in the repository
remain labeled as such, and source leads do not establish accepted sponsorship.

## Reuse before new dependencies

The implementation reuses Godot's geometry/material APIs and the project's
Workshop store/history, strict JSON, immutable skin source and paint bindings.
The handoff's HTML study uses no external framework. The source pack builder uses
Python's standard library; JSON Schema validation uses the pinned development-only
`jsonschema` version. No runtime SDK, plugin, online service, asset store package
or application dependency was added.
