# FW-MOON-01: moon render-path spike (sky-shader disc or mesh disc)

**Status:** research record, 2026-10-19. No runtime change. It answers the render-path question of the [moon plan](../../../plans/moon.md) (§4 "Render-path choice", §7 FW-MOON-01). Scripts and the bench project: [research/field-world/fw-moon-01/](../../../../research/field-world/fw-moon-01/). Engine sources: the gitignored `references/moon/code/*-4.7.2.*` (hashes in §9). The DECISIONS row is left to the owner.

All timings come from Mesa llvmpipe (software rendering) under Xvfb on a shared VM with load average 25–50 on 12 cores. They are **relative only**: they show what work runs and how it scales, never what the target GPU will cost.

## 1. Questions

1. Does changing a sky-material uniform every frame re-render the sky radiance cubemap when the environment uses ambient **COLOR** and reflections **DISABLED** (the field-world mode, `atmosphere.gd` `apply_state_to_environment`)? What does a re-render cost when the radiance is used?
2. What does each sky process mode do (QUALITY, INCREMENTAL, REALTIME, AUTOMATIC)?
3. Can Compatibility draw a second, shadowless DirectionalLight3D (moonlight) beside the shadowed light, and at what cost?
4. How far does the moon jump per `FLOW_STEP_SKY_S` (30 s of sky time), in pixels, in the game's cameras?
5. Can a spatial shader evaluate the sky's cloud density for a direction (mesh-disc occlusion), and which uniforms must be mirrored?

## 2. Method

**Source reading.** The 4.7.2-stable tag files (not master) of `rasterizer_scene_gles3.cpp`, `material_storage.cpp`, `light_storage.cpp`, `sky.glsl`, `scene.glsl`, `renderer_scene_render.h` and `renderer_scene_cull.cpp`. FW-MOON-00's master-branch copies differ from 4.7.2 only by a material-lookup refactor in the sky functions; the radiance gating is identical.

**Bench project** ([project/](../../../../research/field-world/fw-moon-01/project/), assembled by [run.sh](../../../../research/field-world/fw-moon-01/run.sh)). The app's `sky.gdshader`, `cloud_field.gdshaderinc`, `cloud_relief.gdshaderinc`, `engine_srgb.gdshaderinc` and `sky_appearance.gd` are read unmodified from commit 780af5e1, so parallel working-tree edits cannot leak in. The environment reproduces `atmosphere.gd` in field-world mode:
- `Sky.PROCESS_MODE_QUALITY`, default radiance size (256), background SKY;
- ambient COLOR, reflections DISABLED, glow off, AgX, exponential fog;
- MSAA 2× (as `app/project.godot`);
- a 4 km ground plane, 25 boxes and one DirectionalLight3D with PSSM 2-split shadows to 300 m;
- the default cloud deck (coverage 0.35, cluster 0.35, cirrus 0.12, relief on), a night sky and a 0.52° moon in view.

**Cases** (one Godot process each, 1280×720):

| Case | What changes |
| --- | --- |
| `static` | Nothing (baseline). |
| `uniform` | Sky `moon_dir` rotated 0.01° every frame (candidate A with per-frame motion). |
| `uniform_incremental` | As `uniform`, `PROCESS_MODE_INCREMENTAL`. |
| `uniform_realtime256` / `uniform_realtime32` | As `uniform`, `PROCESS_MODE_REALTIME`, radiance 256 / 32. |
| `sky_ambient_static` / `sky_ambient_uniform` / `sky_ambient_uniform_rt32` | Control: ambient source SKY, so the radiance is used. |
| `mesh_disc` | Candidate B: no disc in the sky; a moon quad (spatial, unshaded, blend add, depth-tested, no depth write, per-fragment cloud transmission) rotated every frame. |
| `light2` / `light2_shadow` | A second DirectionalLight3D without / with shadows. |
| `burn_*` | Cost amplifier: the sky shader runs 200 extra loop iterations per pixel **only when `AT_CUBEMAP_PASS`**, so any cubemap render, even an occasional one, becomes visible far above the noise. |

**Protocol.** Vsync off, `Engine.max_fps = 0`. Warm-up 120 frames, then 600 measured frames (the `burn_sky_uniform` case: 10 + 40). Per frame: wall time between `_process` calls (`Time.get_ticks_usec`) and `RenderingServer.viewport_get_measured_render_time_cpu/gpu`. Three repetitions with the case order rotated. A 1920×1080 subset ran once (60 + 300 frames).

**Paired timing.** The VM's load drifted between 25 and 50 during the record, which moves the separate-process medians by more than the small effects. A second design, [paired.gd](../../../../research/field-world/fw-moon-01/project/paired.gd), runs `static`, `uniform`, `mesh_disc` and `light2` inside **one** process in interleaved 30-frame blocks (6 settle frames, order rotated each cycle). The estimate is the per-cycle difference of block medians against the `static` block of the same cycle.

**Parity.** At a 2° FOV (disc ≈ 185 px), captures A (sky disc), B (mesh disc) and C (no disc) at 32 positions, each also with clouds off. Linear tonemap and brighter clouds for the mask measurement. Per-pixel cloud transmission t = moon signal with clouds / moon signal without clouds. Compatibility blends after its sRGB encode, so B's signal is decode(B − C), while A's is decode(A) − decode(C). The same is repeated for every preset of `weather_presets.json`, with layered arrays from the app's `SkyAppearance.resolve` and `shader_arrays`.

DRAFT — results pending.
