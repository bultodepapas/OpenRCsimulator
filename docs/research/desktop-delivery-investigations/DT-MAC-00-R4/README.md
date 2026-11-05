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
