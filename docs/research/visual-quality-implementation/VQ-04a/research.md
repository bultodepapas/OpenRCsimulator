# VQ-04a: Mesh-derived projected shadow research

Status: Research complete; native implementation and validation recorded in [the evidence report](README.md).

Target: Godot 4.7.2, Compatibility renderer. Selected method: project one merged aircraft proxy surface into a 256×256 isolated `SubViewport`, then sample that mask on the ground with a height-dependent blur. Static field batches use cached 256–1024² targets.

## Selection

Native PCSS would require changing renderer. Native hard shadow maps are supported,
but would change the calibrated lighting/shadow path across aircraft materials.
SSAO improves local creases rather than fixing cast silhouettes. Mesh-derived
projection directly fixes the generic aircraft footprint and adds readable fence,
pilot and scenery silhouettes with bounded targets and no renderer migration.
This is an engineering choice, not a claim that projection replaces general
shadow maps. [Godot renderer feature comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html)

## Findings

- **The projection is supported by spatial shaders.** Godot documents `POSITION` as the final clip-space vertex position. Writing it bypasses the normal projection step, so the shader must produce valid clip coordinates itself; `VERTEX` remains the value passed to `fragment()`. For a ground-plane projection, transform each model vertex to world space, project it along the light direction onto the chosen datum, then map the projected bounds directly into clip space. Keep a minimum downward component for the light direction or clamp/fade the result near the horizon, where projected offsets grow without bound. [Spatial shader reference](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/spatial_shader.html)

- **The render target can be isolated and sampled directly.** A `SubViewport` supports a `ViewportTexture`, a selectable update mode, and an independent 3D world. `own_world_3d` creates a unique copy of its `World3D`; SubViewports capture nodes below them in the scene tree. The proxy therefore needs to be present under that viewport (or explicitly replicated there); the live aircraft mesh outside it will not automatically appear. Sample the `ViewportTexture` in the receiver shader rather than reading it back through `get_image()`, which Godot documents as slow and unsuitable for per-frame conversion. [Viewport reference](https://docs.godotengine.org/en/4.7/classes/class_viewport.html), [Using viewports](https://docs.godotengine.org/en/4.7/tutorials/rendering/viewports.html), [ViewportTexture reference](https://docs.godotengine.org/en/4.7/classes/class_viewporttexture.html)

- **Update mode affects freshness.** `UPDATE_WHEN_VISIBLE` is the default; `UPDATE_ALWAYS` redraws every frame; `UPDATE_ONCE` disables itself after one draw. Start with `UPDATE_ALWAYS` while validating pose and texture synchronization. Then use `UPDATE_WHEN_VISIBLE` if the receiver keeps the texture visible, or explicitly request updates when the aircraft/light changes. Verify fast roll and yaw against the main scene for a one-frame lag. [SubViewport reference](https://docs.godotengine.org/en/4.7/classes/class_subviewport.html)

- **Compatibility supports light shadow maps, but not directional PCSS.** Godot lists directional, omni, and spot shadow mapping in Compatibility. Directional PCSS is only supported by Forward+, so a receiver-shader blur is a custom softness path (inference from the documented limitation and spatial-shader texture sampling). Set `transparent_bg` to produce a transparent mask, and use alpha coverage instead of grayscale intensity; Compatibility renders 3D in LDR sRGB, so this avoids depending on color encoding for mask coverage. [Rendering architecture](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html), [Light3D reference](https://docs.godotengine.org/en/4.7/classes/class_light3d.html), [Viewport reference](https://docs.godotengine.org/en/4.7/classes/class_viewport.html)

- **Godot has GPU timing tools, but viewport counters are not timings.** `Viewport.get_render_info()` reports objects, vertices, and draw calls by render pass. The editor Visual Profiler reports CPU/GPU rendering categories and works with Compatibility except on macOS; it is frame-level, so compare the effect off/on at the same window and viewport resolution. [Viewport reference](https://docs.godotengine.org/en/4.7/classes/class_viewport.html), [Debugger panel / Visual Profiler](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/debugger_panel.html)

## Main risks and checks

1. **Projection and datum:** `POSITION` takes clip-space coordinates, while the model mesh is local-space by default. Use the rendered aircraft transform and the same ground datum/light direction as the field. A fixed plane will drift on sloped terrain; low sun can stretch the silhouette far beyond the map.
2. **Texture axes and UV orientation:** the viewport texture is dynamic content, but the docs do not define its orientation relative to the ground’s world axes. Check with an asymmetric aircraft pose and a known world-axis offset before tuning blur.
3. **Blur clipping and resolution:** convert blur distance in world units to mask texels using the map’s world span; clamp the maximum radius and reserve border padding for both projected silhouette and blur taps. A 256² mask has 65,536 pixels, so edges and narrow features can alias if the world span is large.
4. **Stale or frozen mask:** the default only updates while visible, and `UPDATE_ONCE` stops after one frame. Check startup, camera cuts, pause/resume, and rapid aircraft rotation.
5. **Performance:** a second 3D pass adds raster work even with one merged surface; the receiver’s blur adds texture samples over its visible area. Record the Visual Profiler baseline and effect-on result on the target GPU. Use viewport object/vertex/draw-call counters only as supporting counts, not as GPU milliseconds.

