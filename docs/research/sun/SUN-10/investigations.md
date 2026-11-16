# SUN-10: 28 investigations for sun, clouds and visual response

2026-11-15 · Expanded research · [Sun plan](../../../plans/sun.md) · [Code audit](README.md) · [Engine/source catalog](sources.md) · [Acceptance experiments](experiments.md)

## 1. Scope and evidence

This survey answers **28 separate engineering questions**: eight official Godot investigations, six Godot sky/cloud repositories, five Godot optics/color repositories, and nine rendering-library, production-research or visual-reference investigations. A group of links to the same feature counts as one investigation. Numbers below are local research labels, not additional implementation-track prefixes.

OpenRC's application baseline remains `273a7e4c0617fdf4cacc39c360796fd79afa5f2c`; the preceding documentation commit is `4e1d79704a5b71865e0817d7f18692edea28d171`. The target engine remains **Godot 4.8 beta 2**, `cafc17a192acf67903910a68aeb3c076c0907a4b`. Dates use America/Bogota; some retrievals occurred on the following UTC date. Existing SUN/FW/VQ/CAM/LENS/UI ownership and accepted simulation time remain authoritative.

**Performed:** live source discovery, primary documentation and repository inspection, exact revision selection, license/version checks, relevant shader/script inspection, integration analysis and independent technical review. **Not performed:** addon installation, execution, new screenshots, visual qualification or GPU measurements. Repository compatibility statements are identified as author claims or project markers; none establishes native OpenRC 4.8 beta 2 qualification. Decisions and experiments are recommendations.

Repository license observations describe the inspected files, not a blanket approval of every texture, model, shader attribution or dependency. No third-party code or artwork is included in this change. Papers and visual examples are references; their availability does not grant asset redistribution rights. External pages can move: immutable repository links below preserve the inspected code, while tutorial/paper retrieval limits are stated where material.

### Survey map

| # | Investigation | Outcome / main step |
| --- | --- | --- |
| 01 | Godot sky subpasses and radiance updates | Prototype bounded updates · SUN-11/13 |
| 02 | PhysicalSkyMaterial comparison | Diagnostic reference · SUN-12 |
| 03 | Native glow, tone mapping and exposure | Renderer-specific baseline · SUN-12/14 |
| 04 | Official compositor demo | Preferred compute integration reference · SUN-14 |
| 05 | Official volumetric-fog demo | Optional High experiment · SUN-16 |
| 06 | Directional shadows and contact shadows | Tune existing owner · SUN-15 |
| 07 | Reverse-Z, screen copies and transparency | Required visibility contract · SUN-11/14 |
| 08 | Official profiling and GPU diagnosis | Required evidence method · SUN-10/18 |
| 09 | Sky3D | Selected sky/cloud algorithm prototype · SUN-12/13 |
| 10 | Godot Skydome | Cloud-shape/color reference · SUN-13 |
| 11 | Clay John volumetric-cloud demo | Bounded sky-volume comparison · SUN-17 |
| 12 | GDQuest Stylized Sky | Shape/lighting reference; separate art license · SUN-13 |
| 13 | SunshineClouds2 | Conditional advanced backend candidate · SUN-17 |
| 14 | MangoButtermilch local volumetric renderer | Local-bank reference; reject direct integration · SUN-13/17 |
| 15 | SIsilicon Lens Flare | Image-derived flare reference · SUN-14 |
| 16 | SIsilicon God Rays | Screen-space comparison only · SUN-16 |
| 17 | gtibo lens-flare compositor | Visual/code-reading reference; no reuse clearance · SUN-14 |
| 18 | ARez2 compositor lens effects | Prototype ideas after provenance/technical fixes · SUN-14/16 |
| 19 | CodeNameTwister color-LUT shader | Optional grading/authoring reference · SUN-12 |
| 20 | Bruneton atmospheric scattering | Clear-sky reference and optional LUT comparison · SUN-17 |
| 21 | Hillaire sky/atmosphere implementation | Optional dynamic-atmosphere comparison · SUN-17 |
| 22 | PBRT-v4 volume transport | Numerical reference · SUN-13/16 |
| 23 | Nubis 2017 regional cloud authoring | Shape/weather/lighting design reference · SUN-13 |
| 24 | Nubis³ voxel clouds | Advanced flight-through-cloud inspiration · SUN-17 |
| 25 | FastNoiseLite / Godot noise | Shape-authoring experiment · SUN-13/17 |
| 26 | Blender sky reference workflow | Controlled visual inspiration · SUN-12 |
| 27 | OpenColorIO | Offline color-comparison method · SUN-12/18 |
| 28 | Spencer glare research | Perceived-brightness and contrast reference · SUN-14 |

## 2. Official Godot investigations

The engine sources in this section use the exact beta 2 commit above. Public `/en/4.8/` manual retrieval was unavailable; that does not prove the manual is absent. Versioned 4.5 tutorials explain established techniques and moving `latest` pages provide supplementary guidance. Engine source controls version-specific claims.

The two official demos are pinned to [`b761b4cd5718a7118f2c95eb55f181d0a5f004f1`](https://github.com/godotengine/godot-demo-projects/tree/b761b4cd5718a7118f2c95eb55f181d0a5f004f1). Their project files declare Godot 4.7. The [repository README](https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/README.md) and [MIT license](https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/LICENSE.md) were inspected; individual external shader/asset attribution still matters.

### 01. Godot sky subpasses and radiance invalidation

**Question:** can cloud motion become smoother without refiltering sky lighting unnecessarily?

**Evidence:** [sky-shader guide](https://docs.godotengine.org/en/4.5/tutorials/shaders/shader_reference/sky_shader.html), [pinned Sky API](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/Sky.xml), and [RenderingDevice sky implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/servers/rendering/renderer_rd/environment/sky.cpp). The engine distinguishes visible sky, reduced-resolution subpasses and cubemap filtering. Changing time, camera-dependent inputs or uniforms can invalidate radiance even when a shader branch skips its expensive cloud calculation during the cubemap pass. Realtime radiance uses the documented 256-pixel configuration; automatic mode is conditional, not simply “animated means realtime.”

**OpenRC experiment:** extend FW-81-R1 using the current accepted cloud transport. Compare existing one-second publication with reduced-resolution visible clouds and a separately simplified lighting representation. Hold weather/seed fixed while translating and rotating the camera. Record update count, cloud-edge stability, solar-disc sharpness, reflections and total GPU cost at 1080p. A reduced-resolution cloud buffer must not lower the solar-disc resolution accidentally.

**Decision:** prototype on RenderingDevice first. Qualify Compatibility independently; shader parser recognition of a subpass flag is not proof of the same execution or performance path. Adopt only a measured improvement that preserves sky/glare/shadow coherence.

### 02. PhysicalSkyMaterial as a clear-sky comparison

**Question:** what can Godot's native atmosphere reveal about the custom sky's color and horizon behavior?

**Evidence:** [pinned API](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/PhysicalSkyMaterial.xml) and [generated shader source](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/scene/resources/3d/sky_material.cpp). The implementation uses the first sky light and exposes Rayleigh/Mie-related controls, turbidity, solar-disc scale and energy. Its generated shader also makes artistic horizon/ground and output adjustments. It is a useful repeatable engine comparison, not a calibrated radiance oracle.

**OpenRC experiment:** use a small diagnostic scene with the same sun direction, angular scale, exposure and field of view. Compare low, middle and high sun elevations over a limited turbidity sweep, with clouds removed only to isolate the atmosphere. Inspect sky gradients, highlight clipping, circumsolar brightness, horizon continuity and a dark aircraft silhouette. Attribute differences to atmosphere versus exposure before changing presets.

**Decision:** retain as a comparison tool for SUN-12. Transfer a demonstrated palette or horizon improvement through existing Atmosphere/SkyState inputs. OpenRC's limb darkening, flattened low sun, weather, moon and cloud transport remain part of the production design; a whole-material substitution has not earned adoption.

### 03. Native glow, tone mapping and exposure

**Question:** how should the display communicate a brilliant sun on each renderer?

**Evidence:** pinned [Environment](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/Environment.xml) and [CameraAttributes](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/CameraAttributes.xml). Beta 2 includes simplified Compatibility glow using Screen blending, with several glow controls unavailable there. Mobile has different dynamic-range behavior; AgX white behavior also depends on HDR viewport configuration. Native auto-exposure remains Forward+ only, and its processing order is distinct from the local afterimage response.

**OpenRC experiment:** first hold exposure fixed while comparing the solar core, cloud rim and aircraft paint. Then enable the existing `World.adapt` response and test turning toward/away from the sun. Evaluate optional native exposure only in an exclusive-owner Forward+ variant. Record clipping, retained aircraft contrast, global pumping, HUD behavior and effect cost. Do not infer matching output from identical parameter numbers on different renderers.

**Decision:** develop renderer-specific settings within SUN-12. Keep solar radiance, glow, optical veil and afterimage separately measurable, and retain the shared exposure signal required by other presentation code. A new default needs the existing flight-review gate.

### 04. Official compositor demo and GPU optics integration

**Question:** what is the smallest trustworthy starting pattern for a custom GPU visibility/optics pass?

**Evidence:** pinned [demo README](https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/compute/post_shader/README.md), [file-based compositor script](https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/compute/post_shader/post_process_grayscale.gd), [GLSL kernel](https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/compute/post_shader/post_process_grayscale.glsl), and [beta API](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/CompositorEffect.xml). The sample bounds-checks 8×8 workgroups and modifies each color pixel independently in place. A neighborhood blur cannot safely inherit that in-place assumption. The API is experimental, render-thread based and available on Mobile/Forward+, with explicit resolved-buffer requirements under MSAA.

**OpenRC experiment:** implement only a diagnostic mask before glare. Exercise odd-sized viewports, MSAA, resizing, camera cuts and repeated toggles. Use separate buffers for neighbor reads/writes, explicit per-view history and bounded resource ownership. `POST_TRANSPARENT` is before built-in post-processing, so radiance-domain effects need the appropriate color contract.

**Decision:** prefer this small official file-based example as the integration reference for an optional SUN-14 GPU prototype. Keep Compatibility's supported baseline and avoid copying a larger addon solely to acquire a compositor skeleton.

### 05. Official volumetric-fog demo

**Question:** can nearby haze and geometry-shadowed sunlight improve depth and cloud passage?

**Evidence:** pinned [README](https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/3d/volumetric_fog/README.md), [scene/embedded shader](https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/3d/volumetric_fog/volumetric_fog.tscn), [camera controls](https://github.com/godotengine/godot-demo-projects/blob/b761b4cd5718a7118f2c95eb55f181d0a5f004f1/3d/volumetric_fog/camera.gd), and [official guide](https://docs.godotengine.org/en/4.5/tutorials/3d/volumetric_fog.html). The example demonstrates bounded shapes, density modulation, temporal reprojection and directional shadows. Its animated noise uses `TIME` and credits an external shader author. Native fog requires Forward+; reprojection can leave trails around changing lighting.

**OpenRC experiment:** place one low-density volume on a repeatable camera/flight path beside a shadow-casting obstacle. Compare reprojection on/off during pans, cuts and cloud entry. Test zero density and zero source energy. Adapt animation to accepted visual time, and explicitly supply cloud light-path transmission if claiming cloud-driven shafts: the custom sky's cloud mask is not injected automatically.

**Decision:** optional SUN-16 High experiment, with attribution/provenance checked before extraction. Measure the full pass and temporal artifacts before increasing range or density. The sample's colorful demonstration materials are control examples, not prescribed atmospheric settings.

### 06. Directional shadows, cascades and contact shadows

**Question:** which existing shadow controls improve aircraft and landscape lighting through the day?

**Evidence:** pinned [DirectionalLight3D](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/DirectionalLight3D.xml), [Light3D](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/Light3D.xml), [ProjectSettings](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/doc/classes/ProjectSettings.xml), and [lights/shadows guide](https://docs.godotengine.org/en/4.5/tutorials/3d/lights_and_shadows.html). Forward+ provides angular-size PCSS and separate contact-shadow controls. Cascades divide finite shadow resolution across distance. Screen-space contact shadows have visibility and thickness limitations; engine support does not close OpenRC's existing wall-artifact gate.

**OpenRC experiment:** use thin wings, landing gear, walls, foliage and ground at low/high sun elevations. Change range, cascade splits and bias individually through `ShadowSettings`; record attachment, flicker and transitions while crossing cascade boundaries. Test contact shadows separately against their known artifact case. Retain cloud attenuation through the selected sun/moon light handoff.

**Decision:** refine High's already-implemented four-cascade/solar-PCSS path under SUN-15. Keep contact shadows off until their existing gate is resolved. Native directional projectors are unavailable in the pinned engine, so these controls do not solve scene-wide custom cloud shadows by themselves.

### 07. Reverse-Z, screen copies and transparent occlusion

**Question:** what information does a screen-depth glare pass actually have?

**Evidence:** [advanced post-processing](https://docs.godotengine.org/en/4.5/tutorials/shaders/advanced_postprocessing.html), [screen-reading shaders](https://docs.godotengine.org/en/4.5/tutorials/shaders/screen-reading_shaders.html), and the pinned [GLES3 render sequence](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/drivers/gles3/rasterizer_scene_gles3.cpp). Modern reverse-Z maps near/far depth differently from old Godot examples, and reconstruction must respect the renderer's clip-space convention. The ordinary 3D screen copy follows opaque/sky rendering and precedes transparency. Correct depth reconstruction cannot recover opacity never represented in that buffer.

**OpenRC experiment:** move an opaque aircraft, foliage, canopy and actual transparent storm lobe over the sun at different FOVs and pixel sizes. Compare each material's declared transmission, finite-disc sample correlation and stale-view handling. Full coverage should stop new dose along the covered path while earlier afterimage state decays. Inspect actual Canvas/LensStack/HUD ordering separately from 3D buffer ordering.

**Decision:** resolve the shared visibility contract before increasing flare intensity. This directly supports SUN-11/13/14 and experiments E1/E3; a depth-only radial effect cannot stand in for transparent cloud extinction or offscreen visibility.

### 08. Visual profiling and reproducible GPU diagnosis

**Question:** how will a more beautiful sun be qualified without masking expensive frames?

**Evidence:** official [Visual Profiler guide](https://docs.godotengine.org/en/stable/tutorials/scripting/debug/debugger_panel.html#visual-profiler), [GPU optimization guide](https://docs.godotengine.org/en/4.5/tutorials/performance/gpu_optimization.html), pinned [profiler implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/editor/debugger/editor_visual_profiler.cpp) and [command-line implementation](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/main/main.cpp). Rendering CPU time excludes other script/physics work. Platform instrumentation differs; Vulkan shader-debug support is not a promise of identical Metal instrumentation. Transparency and full-screen sampling can be sensitive to pixel count and overlap.

**OpenRC experiment:** reuse the [graphics tools](../../../tools/graphics.md) and frame collector. Hold camera, seed, output/internal resolution and actual renderer fixed across clear, low-sun, cloud-overlap and effect-off cases. Separate cold compilation, warmed timing, profiling captures and sustained clean runs. Report median/p95/p99, hitches, memory and physics catch-up with the plan's named hardware receipts.

**Decision:** make this a SUN-10/18 requirement from the first prototype. Use RenderDoc on supported graphics routes and Apple's tools for native Metal through the existing host workflow. Headless math checks and software-renderer images retain their narrower evidence scope.

## 3. Godot sky and cloud repositories

### 09. Sky3D

**Evidence and intake:** [pinned repository](https://github.com/TokisanGames/Sky3D/tree/81f95aba9693dba805590618c661a51cf524fd91), [README](https://github.com/TokisanGames/Sky3D/blob/81f95aba9693dba805590618c661a51cf524fd91/README.md), [MIT license with third-party exclusions](https://github.com/TokisanGames/Sky3D/blob/81f95aba9693dba805590618c661a51cf524fd91/LICENSE.txt), and [sky shader](https://github.com/TokisanGames/Sky3D/blob/81f95aba9693dba805590618c661a51cf524fd91/addons/sky_3d/shaders/SkyMaterial.gdshader). The author claims Godot 4.3+ and all three rendering routes; the project marker is 4.5. Its Milky Way photograph has a separate [CC BY 4.0 notice](https://github.com/TokisanGames/Sky3D/blob/81f95aba9693dba805590618c661a51cf524fd91/addons/sky_3d/assets/thirdparty/textures/milkyway/LICENSE.md).

**Finding:** cirrus/cumulus and directional scattering provide useful appearance ideas. The addon also manages sky, sun/moon and environment state. Manual cloud processing in its driver does not remove the shader's `TIME` dependency; the inspected sky entry reads it directly. A complete integration would duplicate OpenRC ownership and needs more than a clock checkbox.

**OpenRC experiment:** isolate one cloud-lighting or horizon algorithm in a diagnostic scene, supplying the same accepted sun direction, weather and visual time as the current path. Compare sunrise and broken cumulus at 1080p; inspect paused animation, moon handoff, cloud/ground transmission and reflection changes.

**Decision:** useful SUN-12/13 prototype source for selected algorithms. Preserve Atmosphere, World and SunOptics ownership, replace every relevant time input, and require real cross-renderer evidence before adopting code or settings. Author compatibility claims are not beta 2 qualification.

### 10. Godot Skydome

**Evidence and intake:** [pinned repository](https://github.com/GamesNotDeveloped/godot-skydome/tree/121c7e0bea9ff522ac96ae8647a81b7d22132b48), [README](https://github.com/GamesNotDeveloped/godot-skydome/blob/121c7e0bea9ff522ac96ae8647a81b7d22132b48/README.md), [MPL-2.0 license](https://github.com/GamesNotDeveloped/godot-skydome/blob/121c7e0bea9ff522ac96ae8647a81b7d22132b48/LICENSE), [cloud shader](https://github.com/GamesNotDeveloped/godot-skydome/blob/121c7e0bea9ff522ac96ae8647a81b7d22132b48/addons/gnd_skydome/clouds_2d.gdshaderinc), and [composition](https://github.com/GamesNotDeveloped/godot-skydome/blob/121c7e0bea9ff522ac96ae8647a81b7d22132b48/addons/gnd_skydome/sky_atmosphere.gdshaderinc). The demo declares Godot 4.6 Forward+ and plugin 0.5.1; Compatibility/beta 2 behavior is unqualified. File-level license obligations must be reviewed before extraction.

**Finding:** the project explicitly favors artistic appearance. The inspected shader combines two noise textures on one artistically warped plane, with separate scroll/evolution inputs, sun-relative edge color, cloud attenuation of the solar halo and an optional lower-resolution path. Those inputs are promising adaptation seams, but do not demonstrate two altitude decks. Its global server and weather system would compete with existing ownership.

**OpenRC experiment:** compare its cloud edge/body color ideas against FW-79/80 with fixed sun, coverage and seed. Include thin cover, overcast and low sun; measure direct-light monotonicity, horizon seams, aircraft contrast and update cost. Adapt only the selected calculation through existing snapshots.

**Decision:** reference plus bounded SUN-13 prototype after intake review. Keep its sky server out of the production architecture unless a separate replacement decision is justified. A pleasant sunset image does not establish physical transmission or shared ground shadows.

### 11. Clay John's volumetric-cloud demo

**Evidence and intake:** [pinned repository](https://github.com/clayjohn/godot-volumetric-cloud-demo/tree/6f5ecab924fa1493d5e9eeea6dc7ae5b684eb184), [README](https://github.com/clayjohn/godot-volumetric-cloud-demo/blob/6f5ecab924fa1493d5e9eeea6dc7ae5b684eb184/README.md), [MIT license](https://github.com/clayjohn/godot-volumetric-cloud-demo/blob/6f5ecab924fa1493d5e9eeea6dc7ae5b684eb184/LICENSE.md), and [cloud shader](https://github.com/clayjohn/godot-volumetric-cloud-demo/blob/6f5ecab924fa1493d5e9eeea6dc7ae5b684eb184/clouds.gdshader). The README names a Vulkan demo and its project marks Godot 4.2. Asset and attributed-snippet provenance still need inspection before copying.

**Finding:** 3D noise is raymarched through a cloud shell with extra sun-path samples. The source selects approximately 54–96 view steps; a nonempty step can perform six nested light samples plus one more distant light sample. It uses half-resolution visible sky and quarter-resolution cubemap rendering. Those are workload indicators, not measured cost. `TIME` animates the fields, and a synthetic camera origin does not prove moving-camera/world-shadow agreement.

**OpenRC experiment:** use this compact implementation as a conditional SUN-17 comparison after a deterministic-time adapter. Fix coverage and solar direction; inspect thin wings, cloud gaps, translated views and lake reflections. Record sample counts, internal dimensions, memory, GPU timing and silhouette stability against the enhanced 2.5D baseline.

**Decision:** a useful isolated volume prototype, not a Standard dependency. Prove the actual renderer route rather than inferring Compatibility support from the use of a sky shader. Stop if the visual gain or existing SUN-17 budget is insufficient.

### 12. GDQuest Stylized Sky

**Evidence and intake:** [pinned repository](https://github.com/gdquest-demos/godot-4-stylized-sky/tree/a52b0874b57507474f1b8bbf2db40dc8223f07bf), [README](https://github.com/gdquest-demos/godot-4-stylized-sky/blob/a52b0874b57507474f1b8bbf2db40dc8223f07bf/readme.md), [license](https://github.com/gdquest-demos/godot-4-stylized-sky/blob/a52b0874b57507474f1b8bbf2db40dc8223f07bf/LICENSE), and [shader](https://github.com/gdquest-demos/godot-4-stylized-sky/blob/a52b0874b57507474f1b8bbf2db40dc8223f07bf/sky/stylized_sky.gdshader). The project marks Godot 4.2 Forward+. Its license expressly separates MIT code/scenes from **CC BY-NC-SA 4.0 image textures and models**; the artwork cannot be classified as MIT.

**Finding:** density profiles and directional lighting make cloud silhouettes readable with a deliberate stylized palette. The shader uses 8–32 view samples, up to four nested solar samples and a half-resolution pass; cloud/star motion reads `TIME`. Its art style is a reference choice, not evidence of atmospheric accuracy or free rendering cost.

**OpenRC experiment:** study the height-profile and light-facing shape principles using OpenRC-owned/provenance-cleared inputs. Compare one cumulus preset against existing relief at equal coverage, FOV and exposure. Test accepted-clock pause, sunset, bright/dark aircraft paint, zoom, resize and target GPU cost.

**Decision:** useful SUN-13 shape/lighting reference with optional code-level prototyping after intake. Exclude the noncommercial artwork from the proposed initial implementation. Accept only the features that strengthen OpenRC's realistic visual direction and transmission contract.

### 13. SunshineClouds2

**Evidence and intake:** [pinned repository](https://github.com/Bonkahe/SunshineClouds2/tree/a73a80b08fb37b255f8f10d49debd71e5541bd70), [README](https://github.com/Bonkahe/SunshineClouds2/blob/a73a80b08fb37b255f8f10d49debd71e5541bd70/README.md), [MIT license](https://github.com/Bonkahe/SunshineClouds2/blob/a73a80b08fb37b255f8f10d49debd71e5541bd70/LICENSE), [compositor](https://github.com/Bonkahe/SunshineClouds2/blob/a73a80b08fb37b255f8f10d49debd71e5541bd70/addons/SunshineClouds2/SunshineClouds.gd), and [driver](https://github.com/Bonkahe/SunshineClouds2/blob/a73a80b08fb37b255f8f10d49debd71e5541bd70/addons/SunshineClouds2/SunshineCloudsDriver.gd). README claims 4.4+ and later Metal support; its project marks 4.6 Forward+, with the selected commit addressing a 4.7 camera-layout issue. No native beta 2 result was established.

**Finding:** this is a substantial RenderingDevice/CompositorEffect pipeline with 3D noise, depth, multiple compute stages, temporal accumulation and native/half/quarter/eighth resolution options. Its driver advances motion with frame delta. The README still lists screen-space shadows as outstanding. Its compositor dependency excludes the existing Compatibility route.

**OpenRC experiment:** time-box one optional Forward+ backend comparison under FW-85/SUN-17. Adapt cloud state and accepted transport, inspect history rejection during cuts/fast pans, aircraft depth, inside-cloud views, reflection behavior, disabled resources and peak memory. Verify the advertised Metal route independently if considered.

**Decision:** conditional advanced candidate. Select it only if it beats the enhanced 2.5D baseline on a matched flight within headroom. Its own clouds, shadows and time loop must not become independent competing weather authorities.

### 14. MangoButtermilch local volumetric renderer

**Evidence and intake:** [pinned repository](https://github.com/MangoButtermilch/Godot-volumetric-renderer/tree/9783f079e4672fdfafcad8ac90dd2573f3961cf2), [README](https://github.com/MangoButtermilch/Godot-volumetric-renderer/blob/9783f079e4672fdfafcad8ac90dd2573f3961cf2/README.md), [MIT license](https://github.com/MangoButtermilch/Godot-volumetric-renderer/blob/9783f079e4672fdfafcad8ac90dd2573f3961cf2/LICENSE), and [spatial shader](https://github.com/MangoButtermilch/Godot-volumetric-renderer/blob/9783f079e4672fdfafcad8ac90dd2573f3961cf2/volumetric.gdshader). README targets Godot 4.0; no root project version marker was found. It identifies the implementation as unfinished and documents object-sorting and range limitations. The supplied 3D texture comes from a separate generator and needs asset provenance.

**Finding:** a cube bounds a 3D-texture raymarch, optionally nesting light samples. The performance mode skips those light calculations. `depth_draw_never` does not provide opaque cloud depth. The distinct question is whether a small world-local volume can improve a nearby storm bank; this is different from rendering an entire distant cloud deck.

**OpenRC experiment:** use one isolated bank with near/inside/far camera positions and an opaque aircraft crossing its boundary. Inspect sorting, extinction, world alignment and total sampling cost with deterministic visual state. Reject immediately if aircraft/cloud depth relationships fail.

**Decision:** reference only; reject direct production integration at this revision. The documented limitations make it a useful failure-case study and a local-volume idea, not an accepted SUN-13 solution.

## 4. Godot optics and color repositories

### 15. SIsilicon Lens Flare

**Evidence and intake:** [pinned README](https://github.com/SIsilicon/Godot-Lens-Flare-Plugin/blob/d718b7064855d176a8051ac7f7371fe471931f62/README.md), [MIT license](https://github.com/SIsilicon/Godot-Lens-Flare-Plugin/blob/d718b7064855d176a8051ac7f7371fe471931f62/LICENSE), and [shader](https://github.com/SIsilicon/Godot-Lens-Flare-Plugin/blob/d718b7064855d176a8051ac7f7371fe471931f62/addons/silicon.vfx.lens_flare/lens_flare_shader.tres). The author targets Godot 3.2 and recommends HDR; old GLES2 behavior is described as less effective. No Godot 4.8 compatibility follows from that claim. Bundled dirt/streak textures require separate provenance.

**Finding:** this image-derived approach thresholds bright screen samples, transforms them into ghosts/halos, adds chromatic offsets and modulates optical textures. The shader performs several LOD reads per ghost and wraps sample coordinates with `fract`. It can respond to bright reflections/lamps and to a sun already attenuated by sky-rendered clouds. It cannot independently identify the separate cloud/bank transmission, recover an offscreen source, or see a bank drawn after its screen copy.

**OpenRC experiment:** compare the idea with the existing explicit solar-direction ghost chain in lens mode. Include bright aircraft paint, runway lamps, lake highlights and sun near the frame edge. Measure wrapping artifacts, threshold stability and GPU cost at matched exposure; retain pilot-eye behavior separately.

**Decision:** visual/algorithm reference for SUN-14. An optional modern prototype must use current projection/color contracts; the old plugin itself is not an import recommendation.

### 16. SIsilicon God Rays

**Evidence and intake:** [pinned README](https://github.com/SIsilicon/Godot-God-Rays-Plugin/blob/7a04b002472a05e1e179349328f51c1bb566aea6/README.md), [MIT license](https://github.com/SIsilicon/Godot-God-Rays-Plugin/blob/7a04b002472a05e1e179349328f51c1bb566aea6/LICENSE), and [shader](https://github.com/SIsilicon/Godot-God-Rays-Plugin/blob/7a04b002472a05e1e179349328f51c1bb566aea6/addons/SIsilicon.vfx.godrays/GodRays.tres). It is a Godot 3.2 plugin. Its depth/projection conventions predate the modern reverse-Z path and cannot be transferred unchanged.

**Finding:** a projected light drives screen-space ray steps and opaque-depth obstruction. Optional filtering adds neighboring depth reads. Its cloud panorama uses an alpha threshold of 0.7, which is not OpenRC's layered optical field. This is a radial visibility approximation rather than per-scattering-point integration of a clouded light path, regardless of broad volumetric terminology.

**OpenRC experiment:** use the technique as a visual/cost comparison for SUN-16. Include an offscreen sun, tree blocker, actual storm bank, cloud opening, zero light and rapid pan. Compare against the optional cloud-aware scattering design; explicitly record support loss outside the available screen information.

**Decision:** reference baseline only. A bounded radial effect may be an artistic quality option if its limitations are accepted, but it must not be presented as solving physical cloud shafts or complete offscreen obstruction.

### 17. gtibo Godot 4 lens-flare compositor

**Evidence and intake:** [pinned repository](https://github.com/gtibo/Godot-4-lens-flare-post-process/tree/72051cef9cd8ae2dec2c8afd5ae6df1fec6b65e4), [project config](https://github.com/gtibo/Godot-4-lens-flare-post-process/blob/72051cef9cd8ae2dec2c8afd5ae6df1fec6b65e4/project.godot), [GLSL](https://github.com/gtibo/Godot-4-lens-flare-post-process/blob/72051cef9cd8ae2dec2c8afd5ae6df1fec6b65e4/lens_flare/lens_flare.glsl), and [callback](https://github.com/gtibo/Godot-4-lens-flare-post-process/blob/72051cef9cd8ae2dec2c8afd5ae6df1fec6b65e4/lens_flare/lens_flare_post_process.gd). The project declares Godot 4.4 Forward+. No license was found in the inspected tree/README; public access does not establish reuse permission.

**Finding:** seven sampled flare shapes are driven by projected sun position. Five scene-color alpha samples estimate occlusion; this is not actual cloud transmission or opaque-depth visibility. The main output pixel is bounds-checked, but projected-sun sample coordinates have no equivalent evident guard. Viewport-pixel coordinates versus internal buffer size and scene-singleton access from the rendering callback also require proof.

**OpenRC experiment:** use its presentation as a comparison while independently designing around the official compositor example. Test sun behind camera/offscreen, transparent and opaque blockers, scaling, resize and MSAA. Keep source identity and eye/lens separation from the current system.

**Decision:** no code-reuse recommendation. The repository is a useful inspection of failure risks and flare shape choices; licensing, thread access, coordinate scale and visibility assumptions all block direct adoption.

### 18. ARez2 compositor lens effects

**Evidence and intake:** [pinned README](https://github.com/ARez2/compositor-effect-lens-effects/blob/0ce061271f672f05fbb9aed08a61e019a875c1ad/README.md), [root MIT license](https://github.com/ARez2/compositor-effect-lens-effects/blob/0ce061271f672f05fbb9aed08a61e019a875c1ad/LICENSE), [GLSL](https://github.com/ARez2/compositor-effect-lens-effects/blob/0ce061271f672f05fbb9aed08a61e019a875c1ad/addons/lens_effects/lens_flares.glsl), and [base dispatcher](https://github.com/ARez2/compositor-effect-lens-effects/blob/0ce061271f672f05fbb9aed08a61e019a875c1ad/addons/lens_effects/base_compositor_effect.gd). README claims Godot 4.4+. The code credits an external compositor base and Shadertoy shaders; original-source terms were not retrievable, so root MIT alone does not complete provenance review.

**Finding:** the effect combines analytic flare, nine opaque-depth solar samples and a radial depth blur. Jitter uses `scene.data.time`, not accepted OpenRC time. The inspected workgroup calculation over-dispatches while the kernel lacks a corresponding image-bound guard. Its radial depth mask does not integrate transparent clouds or sun-path extinction through a volume.

**OpenRC experiment:** compare selected visual ideas only after provenance review and a bounded implementation with correct dispatch/bounds, accepted-time jitter, render-thread-safe inputs and explicit MSAA buffers. Exercise odd viewport dimensions, edge/behind-camera sun, fast pans and transparent bank crossings. Include a supported Compatibility fallback.

**Decision:** conditional technique reference for SUN-14/16; direct extraction is blocked by concrete technical and provenance questions. The official compositor skeleton is the preferred initial engineering reference.

### 19. CodeNameTwister color-LUT shader

**Evidence and intake:** [pinned README](https://github.com/CodeNameTwister/godot4-color-lut-shader/blob/24c097f23501170205a152c434cbe34873a869ee/README.md), [MIT license](https://github.com/CodeNameTwister/godot4-color-lut-shader/blob/24c097f23501170205a152c434cbe34873a869ee/LICENSE.md), [shader](https://github.com/CodeNameTwister/godot4-color-lut-shader/blob/24c097f23501170205a152c434cbe34873a869ee/addons/color_grading_lut/filter_node/color_grading_lut.gdshader), and [capture helper](https://github.com/CodeNameTwister/godot4-color-lut-shader/blob/24c097f23501170205a152c434cbe34873a869ee/addons/color_grading_lut/screenshot_tool/color_grading_tool.gd). This Godot 4.4 fork credits original author Thiago Amendola. Included LUT images need their own asset intake.

**Finding:** a canvas screen shader samples a 2D strip representing a 3D color LUT. The helper includes a 16³ identity chart for external grading. The inspected interpolation uses eight explicit `texelFetch` operations and gamma-2.2 approximations; the helper outputs RGB8 under `res://`. Neither cheapness, exact sRGB conversion nor HDR calibration is established by the README's description.

**OpenRC experiment:** use the authoring concept to compare neutral and warm/cool looks while holding World exposure fixed. Test identity behavior, gray ramps, saturated aircraft paint, highlight endpoints, HUD ordering and cross-renderer total cost. Retain original ungraded captures and use existing output paths.

**Decision:** optional artistic reference for SUN-12, distinct from atmosphere scattering and physical cloud transmission. A LUT can refine a look after the lighting is coherent; it cannot recover clipped solar radiance or repair mismatched illumination.

## 5. Rendering libraries, production research and visual references

### 20. Bruneton precomputed atmospheric scattering

**Evidence and intake:** [pinned repository](https://github.com/ebruneton/precomputed_atmospheric_scattering/tree/34f14e745cff948f4ca3157d1b62a445ffa7286f), [BSD-3-Clause license](https://github.com/ebruneton/precomputed_atmospheric_scattering/blob/34f14e745cff948f4ca3157d1b62a445ffa7286f/LICENSE), [author's implementation guide](https://ebruneton.github.io/precomputed_atmospheric_scattering/index.html), [model source](https://github.com/ebruneton/precomputed_atmospheric_scattering/blob/34f14e745cff948f4ca3157d1b62a445ffa7286f/atmosphere/model.cc), and [texture constants](https://github.com/ebruneton/precomputed_atmospheric_scattering/blob/34f14e745cff948f4ca3157d1b62a445ffa7286f/atmosphere/constants.h). This is C++/OpenGL/GLSL reference code, not a Godot addon. Its test/reference dependencies have separate intake requirements.

**Finding:** the revised implementation precomputes atmospheric transmission, scattering and irradiance; it includes ozone/custom density profiles, unit/dimensional checks and CPU spectral comparisons. The author explicitly distinguishes partially implemented light-shaft equations from a missing complete shadow-volume algorithm. Atmospheric lookup tables therefore do not automatically solve OpenRC cloud shadows or cloud-aware shafts.

**OpenRC experiment:** use a fixed-parameter clear-sky reference to examine low sun, horizon gradients and aerial perspective. If SUN-17 proceeds, port only a bounded LUT sampling/generation slice, declare units and RGB conversion, and measure all persistent and temporary textures plus refresh cost. Preserve the current cloud and solar-disc contracts during comparison.

**Decision:** strong numerical/appearance reference and conditional atmosphere-backend candidate. A large precomputed model needs a demonstrated benefit at RC viewing heights and weather changes; its existence is not a reason to replace the current atmosphere immediately.

### 21. Hillaire scalable sky and atmosphere

**Evidence and intake:** [pinned author repository](https://github.com/sebh/UnrealEngineSkyAtmosphere/tree/183ead5bdacc701b3b626347a680a2f3cd3d4fbd), [README](https://github.com/sebh/UnrealEngineSkyAtmosphere/blob/183ead5bdacc701b3b626347a680a2f3cd3d4fbd/README.md), [MIT license](https://github.com/sebh/UnrealEngineSkyAtmosphere/blob/183ead5bdacc701b3b626347a680a2f3cd3d4fbd/LICENSE), [raymarch/scattering source](https://github.com/sebh/UnrealEngineSkyAtmosphere/blob/183ead5bdacc701b3b626347a680a2f3cd3d4fbd/Resources/RenderSkyRayMarching.hlsl), and [author's publications](https://sebh.github.io/publications/). The standalone DX11/HLSL harness compares the 2020 technique with Bruneton and a path tracer. Its dependencies and copied/credited comparison code are not covered by an assumption that every file has identical provenance.

**Finding:** this is useful for separating atmospheric transmittance, scattered radiance and multiple-scattering approximation in a dynamic sky. The inspected integrator accumulates extinction over view segments and handles solar phase direction explicitly. The harness also contains comparison-specific projection/unit choices; HLSL and DX11 buffer conventions cannot be transplanted into a Godot shader unchanged.

**OpenRC experiment:** compare a small LUT-based candidate with the existing atmosphere at noon, sunset and changing aerosol parameters. Measure refresh cost, horizon continuity, target contrast, aerial perspective and reflection consistency. Adopt one atmospheric authority and one exposure conversion; preserve weather/cloud integration.

**Decision:** conditional SUN-17 alternative to investigate alongside Bruneton at design level, then select one bounded implementation experiment. The publisher page/large author PDF had retrieval limits; this card relies on inspected repository code, README and author publication metadata, not a claimed full-paper reproduction.

### 22. PBRT-v4 volume transport and phase functions

**Evidence and intake:** [pinned repository](https://github.com/mmp/pbrt-v4/tree/20e41fd83789f12550e2c31b2047898c9e20e46c), [Apache-2.0 code license](https://github.com/mmp/pbrt-v4/blob/20e41fd83789f12550e2c31b2047898c9e20e46c/LICENSE.txt), [medium implementation](https://github.com/mmp/pbrt-v4/blob/20e41fd83789f12550e2c31b2047898c9e20e46c/src/pbrt/media.h), and the authors' [transmittance](https://pbr-book.org/4ed/Volume_Scattering/Transmittance) and [phase-function](https://pbr-book.org/4ed/Volume_Scattering/Phase_Functions) chapters. The spectral rendering system is an offline/reference tool; book, scenes and third-party libraries have their own terms.

**Finding:** the code separates absorption, scattering and medium density, includes homogeneous/grid/cloud media, and uses an explicit Henyey–Greenstein direction convention. Beam transmission is not cloud display alpha. Its reference methods also illustrate why heterogeneous transport needs a declared approximation/convergence error rather than a single attractive screenshot.

**OpenRC experiment:** first use analytic homogeneous segments to validate E2: zero extinction, increasing optical depth and layered multiplication. Then, only if necessary, compare a small heterogeneous cloud fixture with a converged offline reference and its uncertainty. Match units, source direction, density and phase convention before comparing images.

**Decision:** adopt these numerical principles in SUN-13/16 acceptance, while keeping PBRT outside the game runtime. A converged light-transport reference can evaluate the rendering approximation; it does not establish player recognition or the correct duration of an afterimage.

### 23. Nubis 2017 regional cloud authoring

**Evidence:** [Guerrilla's original talk page](https://www.guerrilla-games.com/read/nubis-authoring-real-time-volumetric-cloudscapes-with-the-decima-engine) and [SIGGRAPH course materials](https://advances.realtimerendering.com/s2017/). The author's description identifies regional authoring, weather simulation, animation, lighting changes and Perlin-Worley construction as production concerns. This survey inspected the primary presentation description and linked material context; it did not run Decima or reproduce the entire presentation's implementation. No asset/code license is inferred from access to slides or noise downloads.

**Finding:** the strongest applicable idea is to design cloud types, their distribution, motion and lighting together. A dense overcast layer, a broken cumulus field and thin cirrus should have different shape/illumination behavior while sharing accepted weather identity. A procedural-noise demo alone does not supply that authored structure.

**OpenRC experiment:** choose three existing weather presets and define a small shape vocabulary: base/height profile, coverage, large-scale clustering, edge detail and light response. Compare them under identical noon/low-sun sequences using the current shared field, including cloud shadows and glare. Prefer distinguishable cloud character with stable transitions over arbitrary extra octaves.

**Decision:** near-term art/architecture reference for FW-79/80 and SUN-13. Treat the talk's original console timings as historical context; no OpenRC hardware budget is derived from them.

### 24. Nubis cubed and flight through voxel clouds

**Evidence:** [Guerrilla's Nubis³ page](https://www.guerrilla-games.com/read/nubis-cubed) and [2023 course materials](https://advances.realtimerendering.com/s2023/). The primary description discusses voxel cloud authoring, flight through volumes, compressed signed-distance acceleration, dense-data upsampling, light-sampling acceleration, dark edges and inner glow. This is a separate investigation from 2017's regional/2.5D authoring question. The inspected evidence is the author/course description, not an imported renderer or completed reproduction of the large slide/asset package.

**Finding:** a cloud that must be entered and viewed from many directions needs stronger spatial representation than a distant backdrop. Empty-space skipping, volume residency and light-path sampling become central design questions. Rich cloud interiors can be useful for onboard/chase views, but imply a substantially larger system and content workload.

**OpenRC experiment:** only if cloud entry becomes an accepted visual goal, compare one bounded volume against the current storm-bank representation from outside, at the boundary and inside. Include an aircraft silhouette, fast camera motion and a source hidden by cloud. Count resident data, history, streaming/update costs and full-scene frame time.

**Decision:** advanced SUN-17 inspiration and a potential future direction. The core ground-pilot sun improvement does not depend on voxel infrastructure. Establish the actual gameplay benefit before adopting the representation or its content pipeline.

### 25. FastNoiseLite and Godot's native noise resource

**Evidence and intake:** [pinned upstream](https://github.com/Auburn/FastNoiseLite/tree/785f37a9ad76e283586a379675085f2063ae03f7), [MIT license](https://github.com/Auburn/FastNoiseLite/blob/785f37a9ad76e283586a379675085f2063ae03f7/LICENSE), [GLSL usage example](https://github.com/Auburn/FastNoiseLite/blob/785f37a9ad76e283586a379675085f2063ae03f7/GLSL/README.md), and [Godot's pinned class definition](https://github.com/godotengine/godot/blob/cafc17a192acf67903910a68aeb3c076c0907a4b/modules/noise/doc_classes/FastNoiseLite.xml). The upstream research pin is not a claim that beta 2 bundles that exact upstream revision.

**Finding:** cellular, Perlin/value-family noise, fractal controls and domain warp offer useful cloud-shape building blocks across CPU/shader implementations. Godot explicitly warns that some cellular modes exceed the usual output range. Noise is not automatically normalized extinction or a physically authored cloud. Replacing OpenRC's current hash/noise changes cloud shapes even when the numerical seed remains the same.

**OpenRC experiment:** use an isolated shape-authoring comparison before changing the runtime field. Record algorithm/version, seed, normalization, tiling and density mapping; test negative coordinates, period seams and CPU/GPU agreement. Reuse accepted transport, and introduce an explicit field/model version if a new algorithm is adopted. Compare shape benefit and sampling/storage cost against existing noise.

**Decision:** practical SUN-13/17 authoring/prototype candidate. Prefer the engine's existing resource where appropriate; a new native dependency is unnecessary until the actual workload demonstrates a need. Preserve the legacy field as the comparison.

### 26. Blender sky models as a controlled visual reference

**Evidence:** official [4.5 Sky Texture manual](https://docs.blender.org/manual/en/4.5/render/shader_nodes/textures/sky.html) and [current Sky Texture manual](https://docs.blender.org/manual/en/latest/render/shader_nodes/textures/sky.html). Indexed primary manual text was retrieved; direct page opens returned a retrieval error. The 4.5 material describes Nishita alongside Preetham and Hosek/Wilkie; the retrieved latest manual labels Single/Multiple Scattering modes and changes some terminology. It also exposes solar angle/size, altitude and atmospheric-density controls. This is a documentation/reference-workflow investigation, not source inspection or a Blender execution.

**Finding:** a repeatable offline sky scene can support art review better than unrelated photographs with unknown exposure and color processing. The exact Blender version, sky model, world strength, exposure and display transform must be frozen. Similar control names across engines do not imply equal physical parameters or an independent ground-truth image.

**OpenRC experiment:** if visual uncertainty remains after native captures, author a small reference set at matched solar elevations and viewing geometry, using original/provenance-cleared content. Retain ungraded outputs and the full color configuration. Compare hue relationships, horizon shape and cloud/aircraft readability, while keeping image-engine differences explicit.

**Decision:** optional SUN-12 visual-reference workflow. No Blender code, stock artwork or new asset is imported. Do not tune OpenRC by matching an undocumented screenshot pixel-for-pixel.

### 27. OpenColorIO for offline color comparisons

**Evidence and intake:** [pinned repository](https://github.com/AcademySoftwareFoundation/OpenColorIO/tree/22dd9c4faa0d1b7cfb3d64d1a6e9cb454acc6cfd), [BSD-3-Clause code license](https://github.com/AcademySoftwareFoundation/OpenColorIO/blob/22dd9c4faa0d1b7cfb3d64d1a6e9cb454acc6cfd/LICENSE), [official usage guide](https://opencolorio.readthedocs.io/en/latest/guides/developing/usage_examples.html), and [ocioconvert source](https://github.com/AcademySoftwareFoundation/OpenColorIO/blob/22dd9c4faa0d1b7cfb3d64d1a6e9cb454acc6cfd/src/apps/ocioconvert/main.cpp). Configurations, documentation and third-party dependencies have their own notices; the inspected README has a separate documentation license marker.

**Finding:** explicit source color spaces, display/view transforms and CPU/GPU processors provide a disciplined way to compare captured values and artistic looks. Processor creation can be expensive and belongs outside per-pixel work. A color-management library does not calibrate a monitor automatically or reconstruct highlights already clipped from an SDR image.

**OpenRC experiment:** only if existing capture analysis leaves a concrete color-space ambiguity, process a retained gray/ramp/highlight fixture with a pinned configuration and known input encoding. Compare identity and chosen display transforms, retaining originals and separating scene-linear measurements from display contrast. Reuse current capture tools; do not transform their evidence silently.

**Decision:** offline analysis reference for SUN-12/18. Keep Godot's established runtime tone/exposure ownership. Evaluate external tools only to answer a defined question, not as a prerequisite for the first sun improvement.

### 28. Spencer and colleagues on perceived glare

**Evidence:** [original Cornell paper link](https://www.graphics.cornell.edu/pubs/1995/SSZG95.pdf), *Physically-Based Glare Effects for Digital Images*, Spencer, Shirley, Zimmerman and Greenberg, SIGGRAPH 1995. Primary indexed PDF text including the abstract and algorithm description was retrieved; a direct open redirected to Cornell's current graphics page. The existing [SUN-00 research](../SUN-00/research-2026-10-19.md) retains the earlier optics context. This is a paper investigation, not an executable library or unrestricted art source.

**Finding:** point-spread glare can communicate source brightness beyond a display's ordinary range and change visibility of nearby image detail. That supports measuring both the sun's apparent brilliance and aircraft contrast. The paper's static glare discussion does not set OpenRC's temporary afterimage duration, validate its current constants, or establish an individual player's response.

**OpenRC experiment:** compare the current CIE-based veil against a bounded alternative light-spread profile while keeping source visibility, exposure and aircraft projection identical. Use effects-off/hidden-model controls and inspect both source brightness and retained detail. Keep eye glare separate from camera ghost styling, then evaluate the temporal response using E4 and owner flights.

**Decision:** conceptual and perceptual reference for SUN-14. Preserve the delivered SunOptics foundation, change one response component at a time, and label normal-play recovery targets as gameplay tuning rather than conclusions from this paper.

## 6. Decisions for OpenRC

### Priority and selection

| Priority | Selected work | Why it comes here |
| --- | --- | --- |
| First | Shared spatial/transmission contracts and reliable capture metadata; investigations 01, 07, 08, 22 | Better effects need consistent cloud/source identity and trustworthy comparisons. This remains SUN-10/11 before richer rendering. |
| Next | Cloud body/rim/shape prototype using ideas from 09, 10, 12, 23, 25 | High visual relevance to sunlight through existing clouds; can improve the current affordable representation without adopting an entire world manager. |
| Next | Solar highlight/exposure comparisons using 02, 03, 28 | Makes the source feel bright while preserving controllable target contrast and a single exposure authority. |
| Targeted prototype | Official compositor skeleton 04 for per-view visibility/history; lessons from 15, 17, 18 | Addresses an actual CPU/GPU visibility boundary. Start with a mask and resource lifecycle, then add optics. |
| Existing-owner refinement | Directional shadows 06 and the SUN-15 receiver inventory | High already has PCSS; local cloud attenuation and receiver coverage still need coherent integration. |
| Optional High | Fog/shafts 05, with 16 as a limited screen-space comparison | Requires explicit cloud transmission and actual temporal/performance evidence. |
| Time-boxed advanced branch | Choose one cloud candidate from 11/13, and one atmosphere feasibility study from 20/21 | Prevents several expensive replacement systems from being developed in parallel before benefit is demonstrated. |
| Reference when needed | Local volume 14, LUT workflow 19/27, offline sky 26, voxel inspiration 24 | Answer specific remaining appearance/representation questions; they do not become mandatory runtime dependencies. |

These priorities refine the existing SUN-10…19 plan. They do not add twenty-eight implementation commitments, change renderer defaults or close existing native/owner gates. The prior estimates remain provisional and should be revised after actual baseline and material-inventory evidence.

### Concrete visual ideas derived from the survey

| Proposed idea | Relevant investigations | Discriminating comparison |
| --- | --- | --- |
| Sunlit cloud edge with a shaded, readable body | 09, 10, 12, 22, 23 | Same silhouette and exposure; edge brightness follows the sun path rather than outlining every edge. |
| Different light response for thin cirrus, cumulus and overcast | 03, 09, 22, 23 | Three existing weather presets with monotonic direct transmission and preserved ambient fill. |
| Smooth cloud motion with bounded lighting refresh | 01, 11, 13 | Pause/wrap/translated camera tests, reflection continuity and measured sky-update cost. |
| A brilliant small solar core with controlled surrounding glow | 02, 03, 20, 21, 28 | Matched angular size, highlight clipping and aircraft contrast at noon/low sun. |
| Brief local dazzle with visible recovery | 04, 07, 28 | Moving 30/60/120 fps trajectory, patch-overlap/off-patch controls and owner reacquisition judgment. |
| Restrained camera ghosts that track the source and obstruction | 04, 15, 17, 18 | Edge/offscreen/behind-camera cases, FOV changes and actual transparent-bank transmission. |
| Moving sun patches across the field and aircraft | 06, 07, 22, 23 | World-position agreement, selected sun/moon source and direct-light-only receiver attenuation. |
| Warm low-sun illumination with cooler sky/shadow fill | 02, 03, 20, 21, 26, 27 | Matched exposure and neutral/colored aircraft surfaces; continuous time transition. |
| Subtle shafts visible through real cloud openings | 05, 16, 18, 22 | Zero-light/density controls, blocked sun paths, rapid pans and explicit quality fallback. |
| Optional near-cloud depth for onboard/chase flight | 11, 13, 14, 24 | Outside/boundary/inside sequence with stable aircraft depth, history and memory cost. |

All are proposed art/engineering outcomes. None is claimed as a new observed image or implemented feature.

## 7. Intake and verification requirements

Before a selected prototype, freeze its source revision, license/asset ledger and dependency versions. Read the current audit queue, renderer profile and tool admission contract. Keep experiments separate from runtime defaults, preserve accepted simulation time and RNG, and use existing SUN/FW/VQ/CAM integration seams. Check project files, native API use, renderer assumptions, uniforms and buffer formats; an addon version label alone is insufficient.

For each adopted slice, retain a matched 1080p baseline/candidate flight or fixture, actual renderer receipt, state/seed/clock, camera and pixel dimensions, controls, original captures, and measured whole-frame CPU/GPU/memory behavior. Reuse the [twelve acceptance cases](experiments.md#4-acceptance-matrix) and [performance method](../../../plans/sun.md#11-acceptance-and-performance). Source inspection, shader parsing, a numerical test, a rendered result and owner flight judgment remain distinct forms of proof.

This research delivery requires document checks: 28 uniquely numbered cards, valid local navigation, immutable repository pins, balanced Markdown, and a final diff restricted to the intended Markdown files. Independent review resolves concrete errors and leaves retrieval/compatibility limits explicit. No addon installation, compilation, application execution or new performance result is part of this branch update.

**Completed delivery checks:** all 28 cards have evidence, an OpenRC experiment and a decision; 18 unique GitHub repositories use one inspected revision each. The expanded document/navigation scope has 74 resolving local links and 15 valid Markdown anchors. All 85 immutable GitHub source/revision links in this survey were checked through the connected repository service and resolved. Markdown fences and whitespace checks passed. Independent review closed after correcting the Skydome plane count, Clay John's additional distant light sample, and the distinction between image-baked cloud attenuation and separately available transparency data.
