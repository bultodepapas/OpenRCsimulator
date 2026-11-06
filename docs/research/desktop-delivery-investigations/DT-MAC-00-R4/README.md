# DT-MAC-00-R4 — Apple Silicon optimization research refresh

2026-11-05 · Research and planning only. The lead read the current Apple plan,
background and DT-MAC-02 evidence, then checked web sources and engine source.
The repository getter now pins **4.8-beta2** (`cafc17a192acf67903910a68aeb3c076c0907a4b`).
The round-6 M1 evidence used 4.8-beta1 (`4d10419cacd6d3009976e8f9fd3abd970fd58018`).
Findings S1, S3–S5 and S9 were checked at both commits and are unchanged.
No runtime, engine, export or measurement change was made. The M1
was not reachable: the ignored `tmp/apple-m1-access/` key directory is absent
from this Linux checkout (SSH returns `Permission denied`; the host itself
answers). The [master plan](../../../plans/apple-silicon-performance.md#next-campaign-dt-mac-00-r4)
owns the resulting work order.

## Starting point (from DT-MAC-02 round 6)

| Fact | Value | Consequence |
| --- | --- | --- |
| Host / config | MacBookAir10,1 M1 8 GiB, Mobile/Metal, 2560×1600 reported viewport, 4× MSAA, Medium, uncapped | 4.10 MP internal: **1.98×** the 1080p primary target's 2.07 MP |
| Optimized sustained rate | 35.5–36.1 FPS, p95 31.2–31.8 ms, >50 ms frames 167–201 per 30 min, max 122–150 ms | Misses p95 ≤18 / p99 ≤25 ms by about 1.7× |
| Shader-only bundle | +17.6–23.2 % sustained FPS | Per-pixel fragment work is a material cost |
| Default product renderer | `gl_compatibility` (Apple's deprecated OpenGL layer) | Same old shaders: GL p95 54.1 ms vs Metal 38.1 ms; GL sim/wall 0.962 failed the 0.99 floor |
| App + helper CPU (GL screen) | ≈ 530 CPU-ms/s | About half of one core in total; whole-process CPU is not saturated, but main-thread saturation is unmeasured |

No run has yet separated GPU time from CPU/main-thread time (DT-MAC-03b open).

## Pinned-engine source findings

File references are at beta1 unless noted. Beta2 changed some of these files but none of the cited lines.

| # | Finding | Source | Consequence |
| --- | --- | --- | --- |
| S1 | Only `metal3_*` drivers exist in the pin, **4.7-stable, 4.7.2-stable and master**. The 4.7 docs sentence "Since Godot 4.7, Metal 4 is now used when supported" is not backed by any released source (R2 noted the same gap). | `drivers/metal/` listings via GitHub API | DT-MAC-10 stays parked; no pin bump buys Metal 4. |
| S2 | Barrier synchronization is the Metal 3 default (PR #121392, merged 2026-08-31, before the pin). The author reports it as fast as or faster than hazard tracking on A12/A18/M1/M4, with less CPU. `GODOT_MTL_SYNC_MODE=none` restores hazard tracking. | `rendering_device_driver_metal.cpp` constructor; [PR #121392](https://github.com/godotengine/godot/pull/121392) | One cheap diagnostic A/B, not a product setting. |
| S3 | Mobile subpasses do **not** stay in tile memory on Metal. SPIRV-Cross runs with `use_framebuffer_fetch_subpasses = false`, and `render_next_subpass()` ends the encoder and opens a new one. | `rendering_shader_container_metal.cpp`, `metal3_objects.cpp` | The Mobile renderer's main TBDR advantage is absent on this backend. Attachment store/load behaviour decides bandwidth. |
| S4 | Memoryless storage is used for `TEXTURE_USAGE_TRANSIENT_BIT` textures when the highest Apple family is ≥ Apple2 and < Mac1. On M1 `highestFamily` scans Apple9→Apple1 only, so it is Apple7 and memoryless is eligible. | `rendering_device_driver_metal.cpp` texture creation; `metal_device_properties.cpp` | Transient MSAA is possible. Whether OpenRC's buffers are transient must be read from a trace, not assumed. |
| S5 | `global_surface_data.screen_texture_used` / `depth_texture_used` become true when **any** instanced material reads screen/depth, and nothing clears them. With MSAA, a set depth flag forces `resolve_depth_buffer` **every frame**, and the separate post-pass pipeline variants are prepared. Visibility of the material does not matter. | `render_forward_mobile.cpp` `_render_scene` and `_geometry_instance_add_surface_with_material` | OpenRC has three such shaders (below). Their presence alone can impose a 4× MSAA depth resolve per frame. |
| S6 | When a visible material reads screen/depth, the opaque and transparent passes split, followed by a screen copy. | same, `merge_transparent_pass` / `_render_buffers_copy_screen_texture` | At 2560×1600 4× MSAA, one store and reload of RGB10A2 colour plus 32-bit depth samples is ≈ 262 MB. Adding resolves and copies gives an **estimated** 0.3 GB/frame. At M1's ≈ 68 GB/s theoretical bandwidth, that is several ms of a ≈ 28 ms frame. This is an arithmetic upper-bound hypothesis, not a measurement. |
| S7 | Compatibility on macOS can use ANGLE over Metal: `rendering/gl_compatibility/driver.macos` accepts `opengl3_angle`, and `fallback_to_angle` exists. | `main/main.cpp` | A zero-shader-change control for the shipped renderer. Template inclusion and look parity must be verified natively. |
| S8 | Master has no Metal or Mobile renderer performance commit after beta2 through 2026-11-05. Beta2 contains the universal release/debug template fix (`3129d5ed10`); the repository already labels the beta1 workaround historical. | GitHub commits/compare API for `drivers/metal`, `forward_mobile`, `platform/macos` | The beta1 M1 results need a beta2 rerun before comparison. No Metal speedup is expected from the version change itself. |
| S9 | Other diagnostic env knobs: `GODOT_MTL_SHADER_LOAD_STRATEGY=lazy`, `GODOT_MTL_DISABLE_ARGUMENT_BUFFERS=1`, `GODOT_MTL_DISABLE_IMAGE_ATOMICS=1`, `GODOT_MTL_ARCHIVE_FAIL_ON_MISS=1`, `MTL_CAPTURE_ENABLED=1`. | Metal driver sources | Use for attribution and capture only. Not product settings. |

OpenRC shaders that set the S5/S6 flags:

| Shader | Reads | Note |
| --- | --- | --- |
| [water.gdshader](../../../../app/render/lake/water.gdshader) | screen + depth | Lake refraction and depth tint |
| [sun_glare.gdshader](../../../../app/render/landscape_upgrade/sun_glare.gdshader) | depth | Occlusion test for a point-like sun |
| [sun_afterimage.gdshader](../../../../app/render/sun/sun_afterimage.gdshader) | screen with `filter_linear_mipmap` | Mipmapped screen copy when visible |

## Apple platform findings

| Topic | Finding | Source |
| --- | --- | --- |
| M1 GPU | 7- or 8-core variant (Air base is 7-core, about 2.3 TFLOPS FP32). LPDDR4X, 128-bit, ≈ 68 GB/s shared with the CPU. Third-party derived figures: verify the core count with `system_profiler`. | [Notebookcheck](https://www.notebookcheck.net/Apple-M1-7-Core-GPU-GPU-Benchmarks-and-Specs.504540.0.html) |
| Game Mode | On Apple-silicon Macs (macOS 14+), it gives the game "the highest priority access to your CPU and GPU", lowers background tasks, and "doubles the Bluetooth sampling rate". It activates in macOS full-screen mode for apps whose `LSApplicationCategoryType` is a games category. The editor runs as Godot.app, so only an exported build qualifies. | [Apple support HT213658](https://support.apple.com/HT213658), [Apple forums](https://developer.apple.com/forums/thread/739387), [Godot forum](https://forum.godotengine.org/t/enable-gaming-mode/128557) |
| Metal HUD logging | `MTL_HUD_ENABLED=1` with `MTL_HUD_LOG_ENABLED=1` writes about once per second to the unified log (filter `metal-HUD`): present interval and GPU time. `MTL_HUD_ENCODER_TIMING_ENABLED=1` adds per-encoder time. Works without Xcode, Metal only. Diagnostic, not a benchmark setting. | [Apple: monitoring Metal performance](https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance) |
| Metal System Trace / counters | `xcrun xctrace record --template 'Metal System Trace' --attach <pid> --time-limit 10s`, then `xctrace export --toc`. Requires **full Xcode**; the M1 currently lists only Command Line Tools. Export details vary by Xcode version. | [xctrace(1)](https://keith.github.io/xcode-man-pages/xctrace.1.html) |
| CPU stacks without Xcode | `/usr/bin/sample <pid> 10` and `spindump` ship with macOS. | macOS base system |
| Shader baker | Godot 4.5+ export option. Forward+/Mobile only; Metal baking needs a macOS-hosted export. Godot reports a 20× TPS-demo load-time reduction on Metal/D3D12. Device-specific final pipeline compilation still exists. | [Godot pipeline guide](https://docs.godotengine.org/en/4.7/tutorials/performance/pipeline_compilations.html), [GameFromScratch](https://gamefromscratch.com/godot-4-5-released/) |
| Retina | Godot documents Retina as a GPU-load multiplier; `scaling_3d_scale` is the documented discriminator. "If performance doesn't increase much when decreasing resolution scale … the bottleneck is likely elsewhere." | [Godot resolution scaling](https://docs.godotengine.org/en/4.1/tutorials/3d/resolution_scaling.html), [troubleshooting](https://github.com/godotengine/godot-docs/blob/master/tutorials/troubleshooting.rst) |
| Known risks | Metal black viewport in Apple paravirtual VMs since 4.8 beta1 (VM only; M1 unaffected per the issue). 4.4-era report of Metal slower than MoltenVK on M1, since superseded by later driver work. | [#124859](https://github.com/godotengine/godot/issues/124859), [#103723](https://github.com/godotengine/godot/issues/103723) |

## Conclusions for planning

1. **First discriminate, then optimize.** The cheapest decisive test is a 3D resolution sweep plus Metal HUD GPU time on the frozen round-6 candidate. The app already applies bilinear `scaling_3d_scale` through [reconstruction.gd](../../../../app/render/reconstruction.gd).
2. If the sweep shows pixel-bound behaviour, the largest lever aligned with product priority is **1080p-class internal 3D on Retina panels**: scale 0.75 on 2560×1600 gives 1920×1200, with UI at native size. Pass structure (S3–S6) and MSAA come next.
3. The shipped Mac default runs on deprecated OpenGL and failed sim/wall in the old-shader screen. Moving Apple Silicon to Mobile/Metal (or, as a control, ANGLE) with recovery is the largest user-facing change. It remains gated by the existing DT-MAC-05b/05c recovery and parity work.
4. Game Mode metadata and the Metal shader baker are cheap export-side candidates. Both need a native exported build to verify.
5. Metal 4, NK-3 ARM64 and engine forks stay conditional. Nothing found here gives them an entry trigger.

## DT-MAC-03b-a attribution sweep (2026-11-05)

Source `a57af99aad7c1e7bb6831e47231f97c2f8ee59c4` (clean). Official
`4.8.beta2.official.cafc17a19` editor via the getter. MacBookAir10,1, M1 with
a **7-core GPU** (`system_profiler`), 8 GiB, macOS 27.0.1, AC power, built-in
2560×1600 panel. Research copy, Mobile/Metal, Medium scenery, pilot camera,
uncapped, sustained circuit fixture. Each cell is **one** 10 s warmup + 20 s
screen with the new `--sustained-render-scale` / `--sustained-msaa` options.
All eight runs passed collection, active-flight and checked-runner gates.
Single short runs screen for attribution only: they are not a speedup claim,
a sustained result or a beta1/round-6 comparison.

| Run | 3D scale | MSAA | Internal MP | FPS | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| default | 1.00 | 4× | 4.10 | 38.3 | 25.55 | 31.18 | 41.09 |
| scale0.75-msaa2 | 0.75 | 4× | 2.30 | 55.1 | 17.92 | 20.75 | 31.27 |
| scale0.5-msaa2 | 0.50 | 4× | 1.02 | 89.6 | 11.06 | 12.04 | 23.82 |
| scale1.0-msaa1 | 1.00 | 2× | 4.10 | 39.0 | 24.95 | 29.50 | 40.07 |
| scale1.0-msaa0 | 1.00 | off | 4.10 | 42.2 | 23.01 | 27.93 | 37.30 |
| scale0.5-msaa0 | 0.50 | off | 1.02 | 101.5 | 9.55 | 10.75 | 22.86 |

FPS is frames counted over the 20 s sample. Sim/wall ratio was 0.987–1.000.
The three full-resolution cells at 0.987–0.993 sit below the frozen 0.99 floor
for longer runs.

**Attribution: GPU, proportional to pixels.**

- FPS(0.5)/FPS(1.0) = **2.34**, above the plan's 1.7 GPU-track threshold.
- p50 frame time fits roughly 6.3 ms + 4.7 ms per internal megapixel.
- `/usr/bin/sample` during a default run shows the main thread in
  `-[IOSurfaceSharedEvent waitUntilSignaledValue:timeoutMS:]` for 2,246 of
  3,966 samples (57 %), waiting for GPU completion.
- MSAA is a minor term: off versus 4× gained 10 % at full resolution, and 2× gained 2 %.

**Product reading.** On this host, 1920×1200 internal 3D (scale 0.75) reaches
p50 17.9 ms. The p95 of 20.8 ms still misses the 18 ms screen. The fit predicts
about 16 ms p50 for 1920×1080. Per-pixel work therefore remains the lever after
choosing 1080p-class pixels; the CPU is not the limiter.

**Tool finding.** With `MTL_HUD_LOG_ENABLED=1`, the unified log's public part
carries only the frame counter and two memory figures (≈ 1,328 / 2,132 MB here).
The GPU timing sits in a `<private>` field that the log redacts. Use Xcode
`xctrace` for GPU time instead of the HUD log.

Raw evidence (outside Git): `tmp/m1-20261105T153146Z/` on Linux, including
`sweep-r7/` runs with summaries, the preflight and the research preparation
receipt. The Mac workspace `/Users/gius/OpenRC-m1-work/m1-20261105T153146Z/`
is kept for the next screens. The driver `tmp/apple-r7/sweep.sh` has SHA-256
prefix `9ac6b5a98bc0`. Frame report prefixes:

| Run | `run-1.json` SHA-256 prefix |
| --- | --- |
| default | d98b76251632 |
| scale0.75-msaa2 | d5b696072cc0 |
| scale0.5-msaa2 | c6fb60672efe |
| scale1.0-msaa1 | ac30a93c905a |
| scale1.0-msaa0 | 896ae5d4a57e |
| scale0.5-msaa0 | 6e2b4933a16e |

## DT-MAC-03b-c GPU pass and ground-shader attribution (2026-11-05)

Same host, engine, research copy and workload as the sweep above. Godot's engine
flag `--gpu-profile` prints per-task GPU time once per second. Each value below is
the median of the 21 one-second blocks after startup and warmup, from **one**
10 s + 20 s run per case. Profiling and visual removal perturb the frame; these
are attribution diagnostics, never timing results. The fixture's diagnostic
options (`--sustained-hide-shader`, `--sustained-shader-param`) make the
checked-runner reconciliation refuse every such run. Fixture SHA-256 prefixes:
hide runs `9e853286e3c62a2c`, parameter runs `ce6772a7fa40f58c`.

**Passes at native 2560×1600, 4× MSAA:** total 28.42 ms. Render Opaque took
22.34 ms (79 %) and scaled 0.63× at scale 0.75. Transparent took 1.56 ms,
tonemap 0.80 ms, particles 0.38 ms and sky setup 0.35 ms; everything else was
below 0.35 ms.

**Hidden material groups:**

| Hidden | Instances | GPU total ms | Δ ms |
| --- | ---: | ---: | ---: |
| none | — | 28.42 | — |
| `ground` | 1 | 17.34 | **−11.08** |
| `near_grass` | 0 | 28.42 | 0.00 |
| vegetation (treeline, woodland cards, imported vegetation/grass, bush impostors) | 36 | 28.36 | −0.06 |
| landscape surfaces (countryside, ridge haze, crop, gravel, woodland floor) | 30 | 30.06 | +1.64 (exposes ground beneath) |

**Ground-shader stages forced off** (values read back from the material). The
pre-run values were: lake mask 1, cloud shadow 0.22, relief on, 2 surface
rectangles, turf detail 1.0, club detail on, photo grass on; anti-tiling and
parcels at shader defaults.

| Stage off | Δ ms |
| --- | ---: |
| cloud shadow (`cloud_shadow_strength=0`) | **−3.55** |
| near detail (`turf_detail_strength=0`, `grass_photo_enabled=0`) | −1.25 |
| micro-relief (`terrain_relief_enabled=0`) | −1.20 |
| surfaces + club + parcels | −1.06 |
| anti-tiling | −0.80 |
| lake mask | −0.39 |
| all of the above | −7.01 |

**Rejected exact candidate:** for power-of-two periods, a bit mask replaced the
two integer modulos in `cloud_field_wrap`. The GPU cloud probe's atlases were
byte-identical on Linux (two repeats). The M1 profile was 28.40 ms against
28.42 ms, so there was no gain. The change was reverted on Linux and the Mac.
The probe tool requires `xvfb-run` and does not run on macOS.

**Consequence:** the ground cloud shadow's five-octave noise is the single
largest removable term, at about 12 % of the GPU frame. It is evaluated per
pixel, yet its finest octave (≈ 16 m) is close to the physical penumbra of a
1.5 km cloud deck (≈ 14 m for the 0.53° sun). The next candidates change
appearance and need owner visual acceptance; see the plan.

## DT-MAC-06b C2 cloud-shadow tile candidate (2026-11-05)

The ground and near-grass shaders spent ≈ 3.6 ms per frame on five octaves of
cloud noise per pixel. The base deck repeats every 64 cells, so one 2048²
RGBA8 tile (16 MiB) holds the fbm and cluster noise for the whole world.
[cloud_shadow_map.gd](../../../../app/render/cloud_shadow_map.gd) renders that
tile once per seed in a `SubViewport`. The shaders then read it through
[cloud_shadow_map.gdshaderinc](../../../../app/render/cloud_shadow_map.gdshaderinc).
Drift, sun projection, coverage, cluster strength and thresholding stay per
pixel. The candidate runs only with `OPENRC_CLOUD_SHADOW_MAP=1`; unset, no
node is created and no material uniform changes. For any seed other than the
tile's, the shader falls back to `cloud_density()`.

| Check | Result |
| --- | --- |
| Density agreement ([probe](../../../../tools/atmosphere/README.md#cloud-shadow-tile-agreement-dt-mac-06b-c2)) | A 1024² tile failed, with error saturating the probe's 0.0625 range. At 2048², Linux llvmpipe passed and M1 Mobile/Metal passed, with max 0.038–0.043 and mean ≤ 0.0029 density. At the default 0.22 shadow strength, that is ≤ 1 % light at edge pixels. |
| Focused tests | New `test_cloud_shadow_map.gd`: 16 checks, 0 failures. `test_atmosphere` (149 checks), `test_shadow_settings` (60) and `test_ground_image_cache` (18) pass. A headless 480-tick flight with the tile enabled had no engine errors. |
| M1 GPU profile, one 10 + 20 s run each, `--gpu-profile` on | Tile off: 28.09 ms GPU, 34.5 FPS, p95 34.1 ms. Tile on: **25.72 ms**, 38.4 FPS, p95 28.9 ms. Removing the shadow outright gave 24.87 ms. |
| Native Metal stills, 1920×1080, `capture.gd --view=all` | Tile on versus off differed by at most 9/255 in the pilot and aircraft-ground views, with 0.1–0.5 % of pixels above 2/255. Two tile-off runs were identical in those views. The lake view varied run to run by itself (31.6 % of pixels above 2/255), so it is excluded. |

One pair per role is a screen, not the five-pair adoption protocol. Moving
shadows, other weather presets and owner acceptance remain open, and the
default stays off. Candidate file SHA-256 prefixes: `ground.gdshader`
3b709ef362d1, `near_grass.gdshader` fa018122e1ce, `atmosphere.gd` c7c9bde16370,
`cloud_shadow_map.gd` afa5b9467a0b, `.gdshader` e63b834efcb5, `.gdshaderinc`
b51c95ecfb34. The probe was revised after the M1 run to prefix its uniforms.
Raw stills and the comparison image are outside Git in
`tmp/m1-20261105T153146Z/c2cap-*`.

## DT-MAC-06b C1 Retina input-scale screen (2026-11-05)

These runs answer the plan's open MetalFX "effective execution" question
indirectly. On the same M1 setup, a new fixture option
`--sustained-reconstruction=<mode>` (with `OPENRC_METALFX_TRIAL=1`) selects the
product's existing MetalFX Spatial presets. The table shows one 10 s + 20 s
`--gpu-profile` run each at 2560×1600 output, with the C2 tile off:

| Mode | Internal 3D | GPU ms | Opaque ms | Tonemap ms | FPS | p50 ms | p95 ms |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Native | 2560×1600 | 28.26 | 22.39 | — | 34.5 | 28.43 | 33.22 |
| MetalFX Spatial 85 % | 2176×1360 | 25.36 | 17.15 | — | 39.0 | 25.15 | 27.91 |
| MetalFX Spatial 67 % | 1707×1067 | 18.68 | 11.78 | 2.89 | 52.2 | 18.94 | 20.72 |
| Bilinear 67 % | 1707×1067 | 16.87 | 11.80 | 0.74 | 59.0 | 16.67 | 18.11 |

**Execution.** At an equal input scale, MetalFX added 2.16 ms inside Godot's
Tonemap stage, where 3D upscaling runs, while the opaque cost was unchanged.
This is consistent GPU-time evidence that the MetalFX spatial scaler executed
on this M1. The policy label stays `unverified_trial`, and failure and
substitution reporting remain open (DT-MAC-07a).

**Readability.** `capture.gd --scale` (new) took 2560×1440 Metal stills.
Zoomed crops of the distant Stik in the pilot view show the trade-off. Bilinear
at 67 % visibly softens the wire gear and tail. MetalFX at 67 % stays close to
Native, with slightly sharpened edges. Static stills only; moving-aircraft review
and owner acceptance remain open. Stills and the crop composite are outside Git
in `tmp/m1-20261105T153146Z/c1cap-*` and `c1-compare-crops.png`. Fixture
SHA-256 prefix: `e8a00ab28348c344`; `capture.gd`: `39d0ea5a5679ad70`.

**Reading.** On a 2560×1600 Retina panel, MetalFX Spatial at 67 % is the
quality-preserving form of C1. It costs ≈ 1.8 ms more than bilinear and saves
≈ 9.6 ms of GPU against Native. Combined with C2 it is the first measured
configuration near the p95 18 ms screen on this M1. It requires the Mobile or
Forward+ renderer on Metal: the shipped Compatibility default cannot use
MetalFX. That makes the product route DT-MAC-05b/05c (Apple renderer selection
with recovery) plus DT-MAC-07a (honest execution status).

## DT-MAC-06b D1 ground `discard` removal and combined screen (2026-11-05)

Apple's TBDR guidance warns that `discard` in opaque materials defeats
hidden-surface removal and early depth: order opaque before alpha-test or
discard draws, and use discard only where needed
([WWDC20 Apple GPU transition](https://developer.apple.com/videos/play/wwdc2020/10602/),
[Metal by Example](https://metalbyexample.com/translucency-and-transparency/)).
The ground shader carried a shoreline `discard` for the lake mask. Disabling
the mask uniform never executed it and saved only 0.06 ms, but removing the
statement saved 2.2 ms. Its presence alone was the cost.

**Implementation.** `ground.gdshader` has no `discard`.
[horizon.gd](../../../../app/render/horizon.gd) `with_hole()` clips the bank
polygon from the ground mesh with `Geometry2D.clip_polygons`, re-triangulates
crossing triangles, interpolates height and normal barycentrically and keeps
the source winding. [lake_world.gd](../../../../app/render/lake/lake_world.gd)
applies it to every mesh using the field's ground material. A failed cut is an
engine error, never a silent overlap. The ground is flat at the lake, so
interpolated attributes are unchanged. The shoreline becomes geometric with
4× MSAA coverage instead of a per-pixel cut. The basin's bank shader keeps its
own small-area mask.

**Checks.** `test_lake_world.gd` gained cases on the production horizon mesh at
a non-origin placement: one mesh is cut, no triangle centroid remains inside
the polygon, removed area equals the bank area within 0.1 %, and winding is
preserved. All 32 checks pass. Field integration (all), staged build (43),
field surfaces (19), lake planar reflection (75), probe ambient (8), world sky
(38) and cloud shadow map (16) pass. A headless production-field flight
reported no engine errors.

**M1 screen.** One 10 s + 20 s `--gpu-profile` run each, 2560×1600 output:

| Configuration | GPU ms | FPS | p50 ms | p95 ms | p99 ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Native, shoreline discard | 28.09 | 34.5 | 28.35 | 34.08 | 42.28 |
| Native, D1 | 25.75 | 38.2 | 25.72 | 28.28 | 39.41 |
| C1 MetalFX 67 % + C2, with discard | 17.17 | 57.2 | 17.18 | 18.47 | 30.23 |
| **C1 + C2 + D1** | **16.10** | **61.0** | **16.13** | **17.28** | 29.11 |

**Images.** 1920×1080 Metal stills of D1 against the discard build differed in
≤ 0.03 % of pixels in deterministic views, all on shoreline edge rows. The lake
view differed in 0.08 %. That view's water renders brighter only in the first
capture of a session (31.6 % run-to-run difference), so compare it only with a
later capture.

C1 + C2 + D1 is the first measured configuration under the p95 18 ms screen
on this M1. p99 still misses 25 ms. These are single profiled screens, not the
five-pair or sustained protocol, and moving review remains open. Candidate
SHA-256 prefixes: `ground.gdshader` 248c287daef3, `horizon.gd` 67ca60bc8a42,
`lake_world.gd` 25412795252d.

**Research notes for later work.** SPIRV-Cross's MSL backend ignores
`RelaxedPrecision`, so Godot `mediump`/`lowp` never become `half`; Apple's FP16
rate advantage is unreachable from Godot shaders without engine work. The
pinned Metal driver already compiles with fast math (`MathModeFast`). Godot
documents no variable-rate shading on Apple GPUs.

## DT-MAC-03b-b / E1 one-second sky hitch (2026-11-05)

**Symptom.** Every M1 frame stream had one 20–35 ms frame per wall second.
The phase was locked to run start, and the cause was not the measurement:
a clean run without resource sampling or `--gpu-profile` showed 20 spikes in
20 s. Godot's per-second `TIME_PROCESS` maximum (`process_time_s`) sat near
18 ms, while frames were 9 ms. A headless fixed-fps run showed no effect at
simulated-second boundaries, so the cost needed a real renderer.

**Cause.** Clouds drift in `Spec.ATMOSPHERE.cloud_update_s` = 1 s steps. Each
step changes sky uniforms, and the sky used `Sky.PROCESS_MODE_QUALITY`, which
refilters the whole radiance cubemap in one frame. Godot's
[Sky documentation](https://docs.godotengine.org/en/stable/classes/class_sky.html)
says QUALITY "should not be used if you plan on changing the sky at runtime".
It recommends INCREMENTAL (same importance sampling, spread over
`roughness_layers` frames) for "a sky that updates slowly".

| One 10 s + 20 s run, Metal, scale 0.5, no MSAA | p50 ms | p99 ms | p99.9 ms | frames > 2× p50 | max `_process` per s (median) |
| --- | ---: | ---: | ---: | ---: | ---: |
| QUALITY (baseline) | 8.97 | 10.68 | 22.08 | 20 | 18.0 ms |
| Cloud drift frozen (diagnostic) | 8.95 | 10.21 | 21.59 | 3 | 7.7 ms |
| INCREMENTAL | 9.02 | 11.62 | 15.86 | 2 | 9.7 ms |

On Compatibility/OpenGL (the shipped Mac default; one run each), INCREMENTAL
lowered the maximum and p99.9 from 100.8 to 46.5 ms. p99 was unchanged at
29.2 versus 29.5 ms, so the GL gain is weak evidence.

**Implementation.** `Atmosphere.SKY_PROCESS_MODE` is `PROCESS_MODE_INCREMENTAL`
for the standard sky. Flowing High worlds keep their REALTIME path. World flow
writes already skip non-REALTIME radiance, so no per-frame sky writes appear.
Tests updated: `test_world_moon_flow` (33 checks). `test_high_graphics_profile`
(78), `test_time_of_day_render_update` (94), `test_world_sky` (38),
`test_atmosphere` (149), `test_sky_render` (46) and `test_time_of_day_render`
(203) pass. 1920×1080 Metal stills after settling were byte-identical to the
previous build in the pilot, aircraft-ground and lake views; the others stayed
within their run-to-run noise. Candidate SHA-256 prefixes as measured: `atmosphere.gd`
47a68aa0da55 (a later edit changed one comment only), `high_graphics_profile.gd` ca574e6dbf21.

## DT-MAC-05a Standard-profile renderer parity screen (2026-11-05)

**Engine facts (beta2 source).** `display_server_macos.mm` maps a Mobile or
Forward+ Metal request on Intel (`x86_64`) to Vulkan/MoltenVK. If the
RenderingDevice context fails to initialize, `fallback_to_opengl3` (default
true) switches to Compatibility/OpenGL. A crash or hang after initialization
is not covered: that is the remaining DT-MAC-05b recovery scope. OpenRC
persists no renderer choice; High is a session-only restart with
`--rendering-method`.

**Images.** `capture.gd --view=all` at 1920×1080 on the M1 with the same
research copy and Standard profile. Compatibility/OpenGL, Mobile/Metal and
Forward+/Metal were each captured once:

| View | Mean linear luminance, GL | Mobile | Forward+ | Mobile vs Forward+ pixels > 8/255 |
| --- | ---: | ---: | ---: | ---: |
| pilot | 0.300 | 0.288 | 0.288 | 0.9 % |
| aircraftground | 0.294 | 0.250 | 0.250 | 1.0 % |
| flightline | 0.229 | 0.230 | 0.231 | 2.5 % |
| pavilion | 0.250 | 0.242 | 0.243 | 5.3 % |
| windsock | 0.330 | 0.321 | 0.321 | 3.4 % |

Mobile/Metal matches Forward+/Metal, the renderer family of the High look.
Compatibility differs: it renders sunlit grass brighter and more saturated
(−15 % luminance on Metal in the aircraft-ground view, with 65 % of pixels
changed by more than 8/255). `shadow_energy_compat` (0.85) darkens GL, so it is
not the cause. The lake view is excluded because of its first-capture state.
Comparison composites are outside Git in
`tmp/m1-20261105T153146Z/parity-*.png`.

**Consequence.** Making Mobile/Metal the Apple Silicon default would change
the Standard look on those Macs to the RenderingDevice look. This is an owner
and VQ appearance decision; no performance measurement can settle it. The
options are to accept the RD look, add an RD-side calibration toward the GL
look (which would also move High), or keep Compatibility.

## DT-MAC-05b Apple Silicon default renderer and recovery (2026-11-05)

The owner accepted the RenderingDevice look on Apple Silicon (see the parity
screen above).

**S1 default.** `project.godot` gains `renderer/rendering_method.arm64="mobile"`.
Godot resolves feature overrides with `OS.has_feature`, and `arm64` matches
only the universal Mac package's Apple Silicon slice: OpenRC ships Linux and
Windows x86_64 only, and Intel or Rosetta Macs stay on Compatibility.
`HighGraphics.standard_rendering_method()` reads the resolved project value, so
a Settings restart into Standard keeps Mobile on Apple Silicon.
`test_high_graphics_restart` asserts the override and the per-architecture
Standard method. It passed on Linux x86_64 and natively on the M1 (43 checks
each). Launched with no renderer argument, the M1 app reported renderer
`mobile` on "Apple M1 (Apple7)" through the debug bridge `perf` command.

**S2 recovery.** [renderer_guard.gd](../../../../app/app_state/renderer_guard.gd)
runs only on the normal Home route, and only when the running renderer is the
RD Standard default and not a High restart. It writes a per-build pending
marker beside the preferences. The marker clears after 120 frames and 3 s of
stable processing (independent of the unfocused Home pause), on a clean quit
or on a deliberate graphics restart. If a launch finds its own build's marker
unconfirmed, it records a failure and restarts once with `--rendering-method
gl_compatibility`. Compatibility sessions write nothing, so no loop is
possible, and a new build retries Metal once. Inert launches never touch the
file.

`test_renderer_guard` (20 checks) covers the decision table, persistence,
headless inertness and confirmation while the tree is paused.
`test_quit_audio_retirement`, `test_ui_home_span`, `test_sky_routes`,
`test_ui_input` and `test_high_graphics_restart` pass.

**Native M1 check.** A pending marker written for the actual build identity
(`0.1.10||4.8-beta2 (official)`) made a normal launch log *"Renderer guard:
the previous mobile launch of this build never confirmed rendering;
restarting with gl_compatibility"* and relaunch with that argument. Without a
marker, a clean launch confirmed and left no pending record. The first native
attempt found the confirmer stalled by the unfocused Home pause; it now runs
with `PROCESS_MODE_ALWAYS`.

The research copy's `project.godot` received the same arm64 line for these
checks. Candidate SHA-256 prefixes: `project.godot` 541e856bd482,
`high_graphics_profile.gd` 4cc764c4c6c9, `app_root.gd` a7f0a2432fa9,
`renderer_guard.gd` bd8b5465b2e6.

**Open.** An exported, signed and quarantined package on Apple Silicon;
Intel-Mac and Rosetta confirmation that Compatibility is kept; MetalFX
promotion (DT-MAC-07a); and the five-pair and sustained runs of the final
product configuration.

## DT-MAC-05c five-pair Compatibility versus Metal campaign (2026-11-05)

This campaign used the same candidate source and research copy (with D1, E1
and the arm64 default), the M1 on AC power and the built-in 2560×1600 panel
at native scale with 4× MSAA. Settings were Medium scenery, pilot camera and
uncapped frames, with no resource sampler, profiler or MetalFX. Five
alternating pairs (GL first in odd pairs) ran a 10 s warmup and a 20 s sample
each, about 7.6 minutes in total. All ten runs passed collection and
active-flight qualification. `performance_pass` is false only because of the
absolute 18/25 ms pacing screen.

| Pair | GL FPS | Metal FPS | Gain | GL p95 ms | Metal p95 ms | GL p99 ms | Metal p99 ms |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 30.2 | 40.0 | +32.3 % | 35.27 | 27.41 | 38.04 | 32.06 |
| 2 | 30.1 | 40.0 | +32.9 % | 35.51 | 27.95 | 38.34 | 32.36 |
| 3 | 30.1 | 39.9 | +32.2 % | 34.95 | 28.48 | 37.54 | 33.28 |
| 4 | 29.6 | 40.1 | +35.5 % | 35.91 | 27.39 | 36.98 | 30.86 |
| 5 | 29.4 | 40.1 | +36.3 % | 36.06 | 27.23 | 36.65 | 29.74 |

The median paired gain was +32.9 %, and the slowest Metal run exceeded the
fastest GL run by 32.0 %, passing the ≥ 5 % adoption screen beyond run
variation. Sim/wall ratios were 0.9995–1.0001. These are short screens, not
the three 30-minute sustained runs. The first reduction lacked the
checked-runner receipt beside each report; it was restored from each run's
`checks/` directory, and `tmp/apple-r7/cleanrun.sh` now copies it. Raw data
is outside Git in `tmp/m1-20261105T153146Z/pairs-r7/`.

## DT-MAC-07a MetalFX Spatial promotion and guard (2026-11-05)

[metalfx_policy.gd](../../../../app/render/metalfx_policy.gd) no longer
requires `OPENRC_METALFX_TRIAL` for Spatial on supported Metal; Temporal still
does. The beta2 `metal_fx.cpp` stores `newSpatialScaler`/`newTemporalScaler`
without a null check, and its encode callback dereferences the scaler. The
renderer guard therefore arms a per-build `metalfx_pending` marker whenever a
MetalFX provider is applied. The marker clears after stable frames, on a clean
quit or when MetalFX is turned off. An unconfirmed marker blocks both
providers for that build (`metalfx_failed_previously`, shown with the existing
translated "unavailable" text). Stable RD rendering confirms only its own
marker.

`test_renderer_guard` (28 checks), `test_metalfx_policy` (54),
`test_reconstruction` (118), `test_advanced_graphics_settings` (146),
`test_quit_audio_retirement` (11) and `test_high_graphics_restart` (43) pass.

Native M1 checks, without the trial variable:

- Spatial was available and Temporal reported `metalfx_trial_disabled`.
- A saved `metalfx_spatial_quality` preference armed the guard ("MetalFX
  active") and confirmed during a normal launch.
- A simulated unconfirmed marker produced "MetalFX did not confirm in a
  previous session of this build; it stays off" and recorded the failure.

The default reconstruction remains Native. Candidate SHA-256 prefixes:
`renderer_guard.gd` cfdea2cd9713, `metalfx_policy.gd` 6142533e4c9a,
`settings_screen.gd` 1a43396806dd, `app_root.gd` de8d50166c2b.

## DT-MAC-03b-d sky cloud cost and rejected C5 relief tile (2026-11-05)

`--sustained-shader-param` now also reaches the `WorldEnvironment` sky
material. It writes only when the value differs, because a redundant sky write
would refilter radiance every frame. The table shows one `--gpu-profile` run
each on the same M1 candidate, Mobile/Metal at native 2560×1600. This flight
uses the single-deck sky path (`cloud_coverage` 0.35, default relief):

| Sky change | GPU ms | Δ ms |
| --- | ---: | ---: |
| none | 27.21 | — |
| `cloud_relief_strength=0` | 24.87 | −2.34 |
| clouds off (`cloud_coverage=0`, layers 0, relief 0) | 19.62 | −7.59 |

Sky clouds cost about 28 % of the GPU frame. `cloud_relief` evaluates three
extra five-octave densities on every cloudy pixel.

**Rejected candidate C5.** The three relief samples read the C2 noise tile,
while the silhouette density stayed per pixel. With C2, GPU time fell from
26.12 to 22.40 ms (37.9 → 45.4 FPS), about −1.3 ms of it from C5. The images,
however, changed inside clouds: pilot-view maximum 46/255, with 0.59 % of
pixels above 8/255 while two tile-off runs were identical. Clouds lost visible
interior relief. The shoulder term amplifies the difference between the exact
`body` and an interpolated neighbour, so a ≤ 0.05 density tile error becomes
visible shading. C5 was reverted; `sky.gdshader` matches HEAD again.

**Viable design for later.** Tile only octaves 0–2 (and the cluster noise),
packed 16-bit across two 8-bit channels so bilinear interpolation stays linear,
and evaluate octaves 3–4 per pixel. That replaces 15 noise evaluations per
relief with 3 fetches and 6 evaluations, keeping the high-frequency detail
that drives the shoulder term. It needs the same probe and image gates.

## DT-MAC-06b C5b float noise tile, corrected C5 diagnosis and default-on (2026-11-05)

**Correction.** The C5 rejection above blamed tile interpolation, and that was
wrong. A low-octave variant (C5b) with three times smaller density error
produced the same flattened clouds on Metal. The same comparison on Linux
Compatibility gave a maximum of 2/255. A 3D probe mode (spatial quad: exact
density in R, tile density in G) confirmed that spatial shaders read the tile
correctly on both backends. The sky shader on Mobile/Metal read the
`ViewportTexture` as black. Separately, an 8-bit `ViewportTexture` and its
`get_image()` copy differed by 1–2 LSB, so bytes split across channels are
not exact.

**Implementation.** [cloud_shadow_map.gd](../../../../app/render/cloud_shadow_map.gd)
renders each seed's tile once into a half-float SubViewport (`use_hdr_2d`).
It copies the image into a stable RG16F `ImageTexture`, 2048² and 16 MiB, then
frees the viewport. The readback was bit-exact, 0 difference against the
viewport, and the texture RID never changes. R holds the five-octave fbm for
C2 ground and near-grass shadows; G holds the sum of octaves 0–2 for C5b. The
16-cell cluster noise is now evaluated per pixel only when clustering is on.
`cloud_relief` uses `cloud_detail_density`: octaves 0–2 come from the tile and
octaves 3–4 are computed per pixel, so the cloud silhouette stays exact.
Headless never bakes. The feature is on with a renderer;
`OPENRC_CLOUD_SHADOW_MAP=0` disables it, and `=1` forces it for headless tests.

**Accuracy** (`shadow_map_probe.gd`, 2D and new 3D modes). On Linux GL, C2
reached a maximum of 0.035–0.042 density and C5b 0.015–0.020; 3D C5b had at
most 0.02 % of pixels above 4/255. On M1 Metal, C2 reached 0.034–0.040 and C5b
0.014–0.020; 3D C5b had 0.3–0.6 % of pixels above 4/255, with Mobile's output
encoding amplifying the difference.

**Images.** On M1 Metal at 1920×1080, tile on versus off differed by at most
2/255, with 0 % of pixels above 2/255, in the pilot and aircraft-ground views.
The other views stayed within their run-to-run noise. On Linux GL at 1280
wide, the maximum was 2/255 (pilot) and 1/255 (aircraft ground).

**Performance** (M1, Mobile/Metal, native 2560×1600, one `--gpu-profile`
run each):

| Configuration | GPU ms | FPS |
| --- | ---: | ---: |
| tile off | 26.20 | 37.9 |
| C2 + C5b on | 23.45 | 44.4 |
| default (no variable) | 23.44 | 44.2 |

That is a 2.75 ms (10.5 %) GPU saving. A default Home-to-flight session
through the debug bridge stopped cleanly with no crash and 0 leaked objects.
Tests: `test_cloud_shadow_map` (21 checks), `test_atmosphere`,
`test_sky_render`, `test_world_sky`, `test_lake_world`,
`test_field_staged_build`, `test_world_moon_flow` and
`test_time_of_day_render` pass with no engine errors.

## Optimization help follow-up (2026-11-05)

**Scope.** Reviewed both sections of the root `optimization help.md` against
`a6ccffaa7a72d14d296e27a08a20cde2285893d2`. Implemented the reproducible integrity
and lifecycle repairs plus the first bounded cloud-density experiment. The
[master plan](../../../plans/apple-silicon-performance.md#next-campaign-dt-mac-00-r4)
records the remaining experiments and promotion gates. The later section of the
input guide supersedes its earlier flattened-cloud diagnosis; its numerical
operation savings are not measured frame-rate gains.

**Delivered.** Pinned-editor UID sidecars; analytic rendering until a validated
HDR tile is published; two bounded bake attempts; independent ground/sky cache
selection; weak consumer lifetime and material-copy publication; explicit
readiness/failure diagnostics. Renderer recovery now owns MetalFX confirmations
by activation token and describes its process-responsiveness limit accurately.
Lake ground cuts are prepared before publication; a failed cut leaves meshes and
materials unchanged and rejects both fixed-wing and ground-vehicle startup.
Unindexed triangles are handled without script errors; contained interior holes
remain an explicit refusal, not newly supported geometry.

The sustained fixture binds the visible application resource tree, requested and
observed renderer/provider/scale/MSAA, cache state and actual bound sky variant.
The reducer rejects mismatches, fallback/backend failure, changing or unready
consumers and `--gpu-profile` runs. Existing MetalFX's unknown execution cannot
pass an effective-provider claim. Older receipts lack this new evidence; they
are not retrospectively declared incorrect. Commands and observation limits
remain in the [performance guide](../../../../research/performance/README.md).

**Opt-in candidate.** `OPENRC_CLOUD_DENSITY_BOUNDS=three|two_three` selects a
compile-time sky variant. It exits only when remaining octave contributions
cannot change zero/full density, with the guide's empirical `1e-5` guard; all
ambiguous samples retain the original accumulation. Default `off` preserves the
reference. Layered clouds use it on ordinary analytic decks, while stretched
decks remain unchanged. A cache-ready base seed does not imply layered relief
cache hits: mismatched layer seeds remain analytic.

**Verification.** Windows native, RTX 3090, NVIDIA 617.42,
`4.8.beta2.official.cafc17a19`. Compact receipts, hashes and limits are in
[optimization-help-checks.json](optimization-help-checks.json); images and raw
logs remain in ignored `tmp/optimization-help-*`.

| Check | Result and boundary |
| --- | --- |
| Focused GDScript | 665 assertions passed across variants, cloud lifecycle, renderer guard, atmosphere/sky/time, staged field construction, lake and real Main water checkpoint suites |
| Offline regressions | 71 benchmark-reducer and 10 release-preflight tests passed |
| UID/import | Pinned editor import passed; sidecar gate passed against a temporary candidate index without modifying the user's staging area |
| GPU numeric matrix | Six runs: cache / three / two-three on Compatibility/OpenGL and Mobile/Vulkan; canvas, spatial and actual sky consumers passed at 512² |
| Cache accuracy | Original C2 maximum/mean limits 0.05/0.003 and C5b 0.025/0.0015 retained; blank-texture controls detected in every consumer |
| Bounded density | Eight ordinary cases per variant/renderer; amplified difference signal zero; deliberate mutation detected. This is finite sampled agreement, not a universal floating-point proof |
| Production captures | Final classic-noon and layered-broken 18:00 pairs at actual 1920×1080, Mobile/Vulkan: `off` versus `two_three` byte-identical. Stills do not qualify motion/readability |
| Fixture execution | Post-import 240-tick headless diagnostic completed; 4,559 visible input hashes unchanged, renderer/cache validators passed and bound variant `three` observed. Timing report deliberately incomplete/ineligible |
| Product regression | Debug-bridge smoke passed: 52 steps, Home/flight/Workshop routes, seeded UI walk and Fly/Home soak; no growing counters or leaked objects at exit |

The review caught and repaired two intermediate regressions: disabled cache
registration retained WeakRefs during cancelled field construction, and copies
made before publication could stay analytic. The extended GPU probe also closes
the analytic-versus-itself false pass with blank-tile controls. Mobile's encoded
R/G threshold reached 0.57% above 4/255 in the full-tile C5b case even though its
linear maximum was 0.02034. Spatial/sky acceptance now tests the original linear
maximum inside the shader; encoded differences remain reported, and the canvas
mean gate is unchanged. No density tolerance was increased.

**Open.** No M1 key was available at the documented Windows/WSL locations; no
native Metal, new FPS, sustained pacing, memory trend, moving-aircraft or package
claim is made. The complete app/visual CI suites were not run. Half-resolution
sky, lattice atlas, aircraft crop, native Metal rate maps and the other
measurement-gated proposals remain explicit next steps. No shader experiment,
renderer preset, MSAA tradeoff or physics rewrite was promoted by these checks.
