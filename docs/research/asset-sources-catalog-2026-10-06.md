<a id="fuentes-de-recursos-y-búsqueda-antes-de-crear"></a>

# Asset sources and search before creating

**Historical source review: 2026-10-06.** This note incorporates the [second submitted catalog](asset-sources-user-input-2026-10-06.txt) into the [visual plan's evidence and acceptance section](../VISUAL-QUALITY-PLAN.md#evidence-and-acceptance) and supplements the [earlier plugin-selection note](visual-quality-supplement-2026-10-06.md). The source checks below describe what was recorded at that date; they are not a fresh verification or a statement of current runtime status. No packs were downloaded, assets imported or tools installed during that review.

The submitted attachment is preserved byte-for-byte. Its SHA-256 is `ec315527c036aa51c0c2b241274f12799663eded8977a0e7d57c06617d99fcdf`. The input retains the recommendations as received; the dated decisions are recorded here and in the visual plan.

The working proposal at the time was to inspect the repository first, then consult a short list of sources for each generic new asset. Choose whether to reuse, adapt or create based on total cost, readability in flight, license and maintainability. Do not replace systems that already meet their tests just to satisfy the search rule.

Current implementation and open work belong to the [visual quality guide](../VISUAL-QUALITY-PLAN.md), [scenery guide](../SCENERY-PLAN.md) and [audio guide](../AUDIO-PLAN.md). For accepted vegetation sources and runtime hashes, see the [landscape provenance record](../../assets/landscape/PROVENANCE.json) and [runtime vegetation catalog](../../app/assets/landscape/vegetation/catalog.json); delivered source packages are indexed in the [source-delivery index](../../assets/source-deliveries/README.md).

<a id="fuentes-nuevas-verificadas"></a>

## Sources reviewed on 2026-10-06

| Primary source | What the review recorded | Proposed simulator use and condition |
| --- | --- | --- |
| [cgbookcase](https://www.cgbookcase.com/textures) | Its catalog declares CC0 1.0 for its textures. The [Grass 01 page](https://www.cgbookcase.com/textures/grass-01) offers several maps, including a DirectX normal map. | A third surface source for L9/VQ-02, after ambientCG and Poly Haven. Select only needed maps, check the normal convention against the documented pipeline, and use a physical scale; start at 1K–2K. Adapt road markings to the field shader or geometry; do not assume Decal support. |
| [Poly Pizza](https://poly.pizza/) and its [terms](https://poly.pizza/docs/tos) | User-submitted low-poly models; the Creative Commons license for each item applies when downloaded. | Search for trees, fences, benches and rocks for L6/L10/L11. Prefer item pages marked CC0 and retain the author and license for the chosen file. Do not describe the whole platform as CC0 or assume all models are available in the same format. |
| [Godot Asset Store](https://store.godotengine.org/), its [official announcement](https://godotengine.org/article/introducing-the-godot-asset-store/) and [roadmap](https://store.godotengine.org/roadmap/) | The store was introduced in 2026 and was still in beta at the time of this review. Its roadmap proposed replacing the Asset Library, which remained necessary for older content. The catalog showed different licenses, including source-available licenses. | Search for new plugins alongside their upstream projects. Review each package's license and contents. A listing on the official platform does not establish Godot 4.7.2 Compatibility or qualification in all three app exports. |
| [Godot Asset Library documentation](https://docs.godotengine.org/en/4.7/community/asset_library/what_is_assetlib.html) | Godot describes free content under a range of open-source licenses. | Use as a complementary search source. Follow links to the code and release; do not import a full demo just because its top-level license appears suitable. |
| [Godot Shaders licenses](https://godotshaders.com/license/) and [shader filters](https://godotshaders.com/shader/) | The site distinguishes CC0, MIT and GPLv3. The selected license covers code or snippets, not images, videos or demo assets. | For VQ-02/04/07 and L9/L15/L19, prefer CC0 or MIT and check version, backend, `TIME` use, depth and required textures. Review the original Shadertoy source when porting; calling something a “port” is not a license. |
| [OpenGameArt FAQ](https://opengameart.org/content/faq) | Licenses vary by item, including CC0 and variants with attribution or other conditions; previews may have different terms. | A complementary source for props, textures, UI and audio. Prefer CC0 where suitable. Record the license for the specific file used when a page offers multiple options. |
| [itch.io Free + 3D + CC0 filters](https://itch.io/game-assets/free/tag-3d/tag-cc0) | These discovery filters and tags exist. A free price and CC0 tag do not review the downloaded file. | Search for L6/L10/L11 or UI assets as needed. Verify the author's page and the pack's license, not just the search-results page. |
| [GitHub guidance on licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository) | A public repository can be viewed and forked on the platform, but public visibility alone does not grant a general reuse license. GitHub provides license search. | Search for candidate implementations and inspect activity and issues. Pin a commit or release and review dependencies and included assets. Project preference: MIT, Apache-2.0 or BSD for code, without assuming a repository license covers every file. |

The review set no catalog-size targets or quality scores: neither decides whether an asset fits the test scene. A free, photogrammetric or low-poly model does not determine its total cost. Measure surfaces/draws, triangles, textures, overdraw, import and export behavior.

<a id="fuentes-ya-presentes-y-fuentes-de-audio-y-animación"></a>

## Sources already present; audio and animation sources

As recorded on 2026-10-06, Poly Haven, ambientCG, Kenney and KayKit were already integrated. The note recommended retaining the small material selection and visual consistency within a prop family instead of mixing styles based on availability. It also retained the per-file/package license check from the [earlier review](visual-quality-supplement-2026-10-06.md#correcciones-de-licencia-y-alcance); this second contribution did not reinstate Quaternius as generally CC0.

[Freesound, CMU and Mixamo](asset-audio-animation-sources-2026-10-06.md) were reviewed separately. The proposal was to consider audio for presentation/sound research only when there is a concrete task; it does not replace engine sound synthesized from RPM. Animated people were conditional on a playtest showing a need for pit activity; L10 could also be completed with static objects. “Free for all uses” or permission for commercial use does not mean CC0 and does not by itself establish that source animation files may be committed to the repository.

<a id="orden-de-búsqueda-aplicable"></a>

## Proposed search order recorded on 2026-10-06

| Need | Initial order, adjustable for style and cost | Intended destination |
| --- | --- | --- |
| Models and nature | Repository inventory → Poly Haven → Kenney → KayKit → Poly Pizza → itch.io CC0 → OpenGameArt CC0 | L6/L8/L10/L11; for simple silhouettes, starting with Kenney or KayKit was also proposed. |
| Textures | Repository inventory → ambientCG → Poly Haven → cgbookcase | L9/VQ-02; avoid normal or displacement maps that do not help at the viewing distance. |
| Plugins and code | Native Godot features and repository → Asset Store → Asset Library → upstream GitHub | Search only to meet an unresolved need; do not migrate radio or physics code just because a plugin exists. |
| Shaders and VFX | Repository shaders → Godot Shaders → Asset Store/Library → upstream source | Keep the same backend, clock and budget; adapt existing work when that requires less change. |
| UI, icons and controls | Repository theme/controls → Kenney → KayKit/itch.io/OpenGameArt pack with suitable license | Menu plan; preserve language, contrast, scale and one visual system. |
| Audio | Synthesis/original files → Freesound CC0 → OpenGameArt CC0 → Kenney | Audio research outside the visual milestone; preserve pause behavior and audible cues. |
| Animation | First determine whether animation is needed → CMU after terms review / KayKit with per-pack license → Mixamo only with documented redistribution permission | Future human content in the pits; prefer an option with documented redistributable files. |

<a id="cómo-cerrar-la-búsqueda-sin-bloquear-la-implementación"></a>

## Proposed way to finish a search without blocking implementation

1. Define the asset, step, apparent size and budget. Check whether the repository already meets the need; record that reference if it does.
2. Initially spend an estimated 30–60 minutes on the most relevant sources and compare up to three candidates. Reuse recent research if requirements and candidate review have not changed. This is not an exhaustive search or a required process for every small fix or feature.
3. In the step evidence, record the need, URL/ID/revision, format/license, adaptation cost and decision: `reuse`, `adapt`, `create` or `defer`. Creating is valid if external options fail on license, silhouette, performance, precision or maintenance; record the reason.
4. For the chosen item, retain its source, license, hashes and recipe. Import a sample, inspect captures and pause/restart behavior if it animates, and test an export from a clean clone according to the plan. Visibility in the editor does not prove that an asset is in the build.
5. Expand to a batch only after the sample passes. Do not increase scene size, dependencies or scope just because a catalog is large.

**Historical L6a proposal (2026-10-06):** search for a suitable existing asset before testing a generator. A reusable family that met the proposed limits (≤1k triangles per mesh, 1K atlas, visual consistency and suitable distribution) could replace the generation stage while keeping baking, provenance, import and tests. If none qualified, the proposal retained a limited ez-tree trial and Kenney as an alternative. It proposed no search plugin or new asset manager. Later source selection and current work belong to the [landscape guide](../LANDSCAPE-PLAN.md) and [tree/forest quality plan](../plans/tree-forest-quality.md).
