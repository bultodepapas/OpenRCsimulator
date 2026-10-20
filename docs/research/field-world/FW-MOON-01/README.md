# FW-MOON-01: moon render-path spike (sky-shader disc or mesh disc)

**Status:** research record, 2026-10-19. No runtime change. It answers the render-path question of the [moon plan](../../../plans/moon.md) (§4 "Render-path choice", §7 FW-MOON-01). **Result: candidate A, the sky-shader disc, updated every frame** (§4), recorded in [DECISIONS](../../../DECISIONS.md). Scripts and the bench project: [research/field-world/fw-moon-01/](../../../../research/field-world/fw-moon-01/). Engine sources: the gitignored `references/moon/code/*-4.7.2.*` (hashes in §7).

All timings come from Mesa llvmpipe (software rendering) under Xvfb on a shared VM with load average 10–50 on 12 cores. They are **relative only**: they show what work runs and how it scales, never what the target GPU will cost.

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

**Paired timing.** The VM's load drifted between 10 and 50 during the record, which moves the separate-process medians by more than the small effects. A second design, [paired.gd](../../../../research/field-world/fw-moon-01/project/paired.gd), runs `static`, `uniform`, `mesh_disc` and `light2` inside **one** process in interleaved 30-frame blocks (6 settle frames, order rotated each cycle). The estimate is the per-cycle difference of block medians against the `static` block of the same cycle.

**Parity.** At a 2° FOV (disc ≈ 185 px), captures A (sky disc), B (mesh disc) and C (no disc) at 32 positions, each also with clouds off. Linear tonemap and brighter clouds for the mask measurement. Per-pixel cloud transmission t = moon signal with clouds / moon signal without clouds. Compatibility blends after its sRGB encode, so B's signal is decode(B − C), while A's is decode(A) − decode(C). The same is repeated for every preset of `weather_presets.json`, with layered arrays from the app's `SkyAppearance.resolve` and `shader_arrays`.

## 3. Results

### 3.1 Radiance: when the engine renders the cubemap (Q1, Q2)

In `rasterizer_scene_gles3.cpp` (4.7.2) `render_scene`, the radiance update is gated by the environment:

```
sky_reflections = reflection_source == SKY || (reflection_source == BG && bg == SKY)
sky_ambient     = ambient_source == SKY    || (ambient_source == BG && bg == SKY)
if (sky_reflections || sky_ambient) _update_sky_radiance(...)
```

- `_setup_sky` marks `reflection_dirty` when a material uniform changes (`uniform_set_updated`), when the material changes, when the shader uses `TIME`, and when the directional-light data seen by the sky changes. A dirty flag only matters inside `_update_sky_radiance`.
- `_update_sky_radiance` is the only caller of the sky shader's `MODE_CUBEMAP` (`AT_CUBEMAP_PASS = true`). The process mode only decides how a dirty cubemap is rebuilt there: QUALITY and REALTIME render and filter it in one frame; INCREMENTAL renders the six faces in one frame and filters one mip level per later frame (a full rebuild on the first frame); AUTOMATIC picks REALTIME for shaders using `TIME` or `POSITION`, INCREMENTAL for shaders with lights, fog sun scatter or any uniform (so ours), and QUALITY otherwise.
- With ambient COLOR and reflections DISABLED, `_update_sky_radiance` is never called. **A per-frame sky uniform costs only the main pass.** The texture itself is still allocated once (`_update_dirty_skys`).
- Reflection probes draw the sky with `_draw_sky` (`MODE_BACKGROUND`, `AT_CUBEMAP_PASS = false`). The lake's `LakeReflection` probe therefore sees the disc whether or not the cubemap pass skips it.

The cost amplifier confirms it (1280×720, one run each, adjacent in time, load 10–12):

| Pair | Wall p50 static → uniform | Δ |
| --- | --- | --- |
| `burn_color_*` (field-world mode) | 52.1 → 54.3 ms | +2.2 ms (+4 %, within run-to-run spread) |
| `burn_sky_*` (radiance used) | 59.6 → 128.4 ms | **+68.8 ms (+115 %)**: the burned cubemap is rebuilt every frame |

Without the amplifier, the radiance re-render under ambient SKY at 1920×1080 cost +49 ms (+54 %) against field-world `static` (one run each). The separate-process 1280×720 medians spread from 53 to 331 ms for the same case under the VM's load drift, so only the amplifier and the paired runs below can separate small effects.

### 3.2 Paired cost (Q1, Q3)

One process, 1280×720, 25 cycles × 4 configurations × 30-frame blocks (24 measured), load 9–14:

| Config | Wall p50 | Paired Δ wall vs `static`: median (IQR) | Δ / static |
| --- | --- | --- | --- |
| `static` | 70.2 ms | 0 | 0 |
| `uniform` (A, moon moved every frame) | 68.4 ms | −1.9 ms (−5.6 … +3.1) | −2.7 % |
| `mesh_disc` (B) | 72.1 ms | +3.7 ms (−1.6 … +7.9) | +5.2 % |
| `light2` (second shadowless light) | 72.7 ms | +3.5 ms (−0.6 … +6.4) | +4.9 % |

The measured CPU and GPU render times give the same picture (`uniform` −1.5 ms, `mesh_disc` +2.1–3.0 ms, `light2` +2.0–3.0 ms). Moving A's disc every frame costs nothing measurable. B and the second light lean positive, as expected from an extra transparent draw with its own cloud evaluation and an extra light term per fragment, but their IQRs include zero on this machine.

### 3.3 Stepping (Q4)

[stepping.py](../../../../research/field-world/fw-moon-01/stepping.py) uses the FW-MOON-00 Python port of `ephemeris.gd`. The moon moves 0.106–0.120° per 30 s step along its daily circle (Earth's rotation minus the moon's orbital motion, times cos δ; the plan's 0.125° ignored the orbital motion).

| Camera (1080 px high) | Vertical FOV | Jump per step | Disc |
| --- | --- | --- | --- |
| Pilot base, close-up | 50° | 2.4 px | 11 px |
| Chase | 55° | 2.2 px | 9 px |
| Orbit | 45° | 2.7 px | 12 px |
| Pilot auto-zoom, Stik 60 at 200 m | 15.6° | 8.2 px | 36 px |
| Pilot auto-zoom, Stik 60 at 300 m | 10.4° | 12.3 px | 54 px |
| Pilot auto-zoom floor (`AUTO_ZOOM.min_fov_deg`) | 6° | 21.5 px | 94 px |
| Pilot narrowest (`PILOT_FOV_MIN`) | 1° | 129 px | 562 px |

At ×20 a step comes every 1.5 s of flight; the smooth motion would be 0.24 px per frame at the 6° floor (60 fps). **The pilot camera's zoom makes the steps visible**: the moon must move every frame, whichever candidate draws it. The stars (`World.flow_to` turns their basis per step) and the moonlight direction step the same 0.12°; the stars sit next to the disc, so they need the same per-frame motion, while 0.12° moves a 17 m low-moon shadow tip by 4 cm.

### 3.4 Second directional light (Q3)

Captures at 1280×720 ([bench.gd](../../../../research/field-world/fw-moon-01/project/bench.gd) `--mode=lights`), mean ground luma:

| Lights | Ground luma | Draw calls |
| --- | --- | --- |
| Shadowed moon only | 0.0773 | 58 |
| Shadowless twilight light only | 0.0270 | 26 |
| Both, second without shadows | 0.1051 (sum 0.1043) | 58 |
| Both, second with shadows | 0.1074 | 114 |
| None | 0.0000 | 26 |

- Compatibility adds a shadowless second directional light into the same pass: the light sums, and the draw calls stay at 58. `MAX_DIRECTIONAL_LIGHTS` is 8.
- A second shadowed light renders its own shadow pass and doubles the draw calls (58 → 114). FW-MOON-06's hand-off must keep one shadowed light at a time; the plan's "second, shadowless DirectionalLight" works.

### 3.5 Cloud occlusion (Q5)

- **Default deck** (32 positions, 8 partly occluded, 151 860 disc pixels): |t_A − t_B| p50 0.0000, p99 0.013, max 0.032. Mean transmission per position agrees within 0.001.
- **Every preset** (8 positions each, 286 895 pixels): p50 0.0008, p99 0.012, max 0.035.

| Preset | Decks | Partly occluded positions | Max \|Δt\| | Max \|Δ mean t\| |
| --- | --- | --- | --- | --- |
| classic, clear | legacy / none | (default-deck test above) | | |
| cirrus | 1 | 6 / 8 | 0.035 | 0.0022 |
| fair_cumulus | 1 | 2 / 8 | 0.029 | 0.0015 |
| broken | 2 | 8 / 8 | 0.027 | 0.0019 |
| overcast | 2 | 8 / 8 (t ≈ 0.02) | 0.007 | 0.0003 |
| prestorm | 3 | 8 / 8 | 0.012 | 0.0007 |
| distant_storm | 2 | 0 / 8 (clear above the bank) | 0.000 | 0.0000 |
| electrical_storm | 3 | 1 / 8 (t ≤ 0.02) | 0.006 | 0.0008 |

A spatial shader can reproduce the sky's occlusion through the shared `cloud_field.gdshaderinc`, but only by mirroring 14 sky uniforms (legacy deck, cirrus, eight-layer arrays, seeds, density) and re-sending them on every cloud update. Its disc is also 7–8 % brighter in 8-bit at the same linear input (centre 190/194/201 against 183/182/182), because Compatibility adds it after the tonemap and sRGB encode; A shares the sky's tonemap. The terrain, treeline and storm-bank depth occlusion B would add is already given to A by drawing order: the sky is the background.

## 4. Decision

The plan's rule: pick A only if measurement shows no radiance re-render, or a cost below 0.05 ms. Both the engine source (§3.1) and the cost amplifier show **no radiance re-render** in field-world mode, so:

1. **Candidate A: the disc stays in `sky.gdshader`** (`moon_disc.gdshaderinc`), with clouds, tonemap and occlusion for free and no mirrored uniforms. Candidate B's quad and its 14 mirrored uniforms are not shipped.
2. **The moon moves every frame.** Its direction and orientation are interpolated in float64 between the current flow step and the next, as a pure function of the simulation clock; the stars turn with it. Steps stay as they are for everything slow (light colour, sky table, exposure, moonlight direction).
3. **Guard:** per-frame moon uniforms are written only while the environment's radiance is unused (ambient not SKY/BG-sky, reflections not SKY/BG-sky). Field-world flow always qualifies. A route that keeps sky ambient or reflections (today the calibrated Day and the TOD snapshot, both moonless) would rebuild the cubemap every frame, so it must step, or route its night through the field world (M-D7).
4. **The disc skips `AT_CUBEMAP_PASS`.** Today no radiance-using route draws a moon, so this changes no picture; it keeps a bright sub-texel disc out of any future ambient or reflection cubemap.
5. **Moonlight:** at most one shadowed directional light; a second one, shadowless, is free in draw calls (FW-MOON-06).

Implementation is FW-MOON-03b (items 2–4); the lake moon road refreshes with the light signature at step cadence and is checked in FW-MOON-08.

## 5. Limits

- llvmpipe timings are relative. The 0.15 ms p95 moon budget is checked on the target GPU in FW-MOON-14.
- The bench reads the sky shaders at 780af5e1, before FW-MOON-03/05 textured the disc. The textured disc adds per-pixel work inside the disc's few hundred pixels at most; the radiance gate and the parity method do not depend on it.
- Cloud parity covers the sky's decks only. The storm bank is a mesh (FW-84) and hides a sky disc by depth.

## 6. Reproduce

```
research/field-world/fw-moon-01/run.sh OUT parity; run.sh OUT lights; run.sh OUT bench
CASES="burn_color_static burn_color_uniform burn_sky_static burn_sky_uniform" REPS=1 run.sh OUT bench
RES=1920x1080 REPS=1 WARMUP=60 FRAMES=300 CASES="static uniform sky_ambient_uniform mesh_disc light2" run.sh OUT bench
run.sh OUT profiles; run.sh OUT paired
python3 -I research/field-world/fw-moon-01/analyze.py OUT
python3 -I research/field-world/fw-moon-01/stepping.py
```

The record ran on 2026-10-19 in two sessions (bench, parity, lights; then profiles and paired), all from the same `run.sh` and identical inputs (sources at 780af5e1, same `inputs.sha256`). Each Godot process needs about 2 GB of RAM; run one at a time. The [results/](results/) folder keeps the analyzer's [summary.md](results/summary.md), per-run CSV, per-case summary, the parity, lights, profile and paired JSON, and the load log; captures and per-frame run files stay out of the repository.

## 7. Engine source hashes (SHA-256, 4.7.2-stable)

| File | SHA-256 |
| --- | --- |
| `godot-gles3-rasterizer_scene_gles3-4.7.2.cpp` | `6d0719c9cd2caf685a9825028183bdf058081d7bc92d4b27ed2587f39b081221` |
| `godot-gles3-material_storage-4.7.2.cpp` | `8fa1b214a67605a5e3deeed941711933c4f4e6ccd96691ac55e78f993ffefcd7` |
| `godot-gles3-light_storage-4.7.2.cpp` | `2aaae89b4d75abb1c91d5de3a85f094cc2d06a5f23fdcd288c78e22f3a8a3d24` |
| `godot-gles3-sky-4.7.2.glsl` | `c730ba29e262768134143d346fa25f2499fc143c8a78eae8277233f1d7ea20f3` |
| `godot-scene-4.7.2.glsl` | `2c77be0c85b7ab1a85ed8009c77cdb6216f1494d43083592213ad68f9e812977` |
| `godot-renderer_scene_render-4.7.2.h` | `837ddd498991466d69ac90082246265ea75c3c3be898fa48c41a9669caa68151` |
| `godot-renderer_scene_cull-4.7.2.cpp` | `62658efa156d6b080a4d24eab9812f9f596a41b5998f077ae0fcb82976df933e` |
