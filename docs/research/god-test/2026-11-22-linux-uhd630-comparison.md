# Linux UHD 630: PRIMIS and megatron tours, causes and fixes

On 2026-11-22 the three-aircraft [performance tour](../../../tools/godtest/PERFORMANCE_TOUR.md)
ran repeatedly on both Linux Intel UHD 630 hosts with identical source, engine,
native physics and settings. This record compares them, finds the causes behind
the Linux findings of the [2026-11-21 stutter map](2026-11-21-stutter-map.md), and
gives the host setup that now yields clean, complete cases. Each result is one pass
per aircraft: an exploratory screen, not qualification.

| Host | CPU visible to the container | GPU | Container RAM |
| --- | --- | --- | --- |
| PRIMIS CT 405 (test pool host) | i5-9500T, 4 cores | UHD 630 (CFL GT2) | 4096 MiB + 512 MiB swap |
| megatron CT 206 (bench host) | i5-10500, 6 cores | UHD 630 (CML GT2) | 4096 MiB, later 8192 MiB |

Common setup: source `7f4db1b1b` with the harness changes below (identical
9,651-file digest on both hosts), pinned Godot 4.8-beta2 (`34d0599a…`), native
physics, Mesa 25.0.7 ANV, headless Weston 14 at 1920×1080 borderless,
Forward+/Vulkan, Medium detail, no frame cap. megatron ran with Frigate, the other
user of its iGPU, stopped. Both GPUs ran at their 1100 MHz maximum with dual-channel
DDR4-2667 and the CPU governor at `performance`.

## Results

The two hosts behave the same within run-to-run noise.

| Phase | PRIMIS | megatron |
| --- | --- | --- |
| First Home | 6.0–6.7 FPS | 6.1–6.3 FPS |
| Runway circuit, Stik / jet / Corsair | 12.9–13.6 / 8.8–9.1 / 8.7–9.3 FPS | 11.4–12.4 / 8.3–8.7 / 8.0–8.4 FPS |
| Simulation/wall in the circuit | 0.65–0.68 / 0.44–0.45 / 0.43–0.46 | 0.57–0.62 / 0.41–0.43 / 0.40–0.42 |
| Flight loading after both fixes | 6.5 / 9.9 / 11.3 s, worst frame 1.2 s | 5.5 / 7.1 / 9.3 s, worst frame 0.99 s |
| Peak RSS | 1.7–1.8 GB | 1.4–1.9 GB |

Final X11 pass (both hosts): every case exited cleanly. The Stik case is
`data: valid`, `coverage: complete`, with no issues. The jet and Corsair cases stay
ineligible only because their circuit reaches the 300 s phase deadline in slow
motion.

## Causes and fixes

| Finding | Cause | Evidence | Action |
| --- | --- | --- | --- |
| 36–45 s flight-loading freeze | **Test-host audio setup.** Without a sound device the hosts used an ALSA `pcm null` default. Godot opens ALSA non-blocking and mixes while holding the driver lock. A null device never returns `EAGAIN`, so the mix thread spins and starves the main thread whenever it needs the audio lock | One Godot thread at 99.9 % CPU with ALSA null against ~7 % with the Dummy driver. Home → flight took 13.6–19.0 s against 6.5–6.6 s. The 74 audio samples load in 46 ms headless, yet the freeze fell between consecutive `.wav` loads | The runner launches the Dummy driver on Linux without an accessible playback device; it still mixes in real time. Loading fell from 16–45 s to 5–11 s |
| Forced kill at shutdown (6 of 21 Wayland cases) | **Godot's Wayland backend on a headless compositor.** `WaylandThread::destroy()` sets its exit flag, sends one roundtrip and joins the events thread without a timeout. That thread waits in `poll(fd, -1)`. With no input or frame events from the compositor it may never wake | Hung processes: main thread joining during engine cleanup, `Wayland Events` thread in `poll`, all other threads idle. Same stack with ALSA and with the Dummy driver | Run Godot on X11 through Weston's Xwayland: 0 forced kills in 7 cases |
| Startup phase always ineligible | The Wayland backend marks the window undrawable during any frame longer than about 1 s. The first Home has one indivisible 1.7–2.3 s frame (aircraft build and first 3D draw) | `window_undrawable` exactly at that frame | X11 keeps the window drawable. The frame stays a measured freeze |
| Slow motion below ~15 FPS | Intended: `max_physics_steps_per_frame=12` at 240 Hz keeps real time only above 20 FPS ([project.godot](../../../app/project.godot)) | 12 ticks/frame ÷ ticks needed per frame matches every measured pace | None; see the workload note below |
| 6 FPS Home, slower than flight | **GPU fill rate.** Home GPU time is 97 ms per frame on PRIMIS | Live ablation: the terrain `Field/rough` costs 48 ms (one draw call). Replacing its material with a plain one saves 30 ms, so `render/ground.gdshader` costs ~30 ms. MSAA 2× costs 24 ms; half resolution would save 56 ms. Each optional shader term costs 1–5 ms; anisotropic filtering at the default 4× costs ~2 ms | Product follow-up below |
| Shader-cache cost | Rejected as a cause | Cold and warm `user://` caches: 18.5 s and 22.4 s Home → flight (both with ALSA null) | None |
| PRIMIS container stopped by the node watchdog | Node memory. At 5120 MiB the iGPU's shmem buffers and page cache lowered the node to the 1536 MiB threshold; later in the day the HA VM grew to 4.9 GB and did it again at 4096 MiB | Watchdog log; container `shmem` 2.27 GB, `anon` 1.67 GB | Container at 4096 MiB plus a transient guard that moves cold VM pages into zram while a tour runs |

The Wayland shutdown mechanism is read from Godot's source
(`platform/linuxbsd/wayland/wayland_thread.cpp`); the exact race was not traced
in a symbol build.

## Workload against the product's choice

These GPUs cannot run the tour's fixed Forward+ Medium workload at 20 FPS, so the
jet and Corsair circuits cannot finish in 300 s. Scene detail Low did not help
(13.4 against 13.2 FPS): detail does not scale the terrain shader, MSAA or the
render resolution. On an integrated GPU the product's Automatic mode chooses
Standard (Compatibility/OpenGL) with Low detail
([auto_graphics_policy.gd](../../../app/render/auto_graphics_policy.gd)). That path
needs 2.2–4.1 GB RSS on Mesa iris and does not fit PRIMIS's 4096 MiB container.
On megatron (8192 MiB, X11) it ran as follows:

| Compatibility, Low | Stik | Jet | Corsair |
| --- | --- | --- | --- |
| Circuit FPS, simulation/wall | 22.8, 0.99 | 17.7, 0.88 | 17.5, 0.88 |
| Circuit result | completed in 68 s | completed in 177 s | completed in 156 s |
| Worst startup / loading frame | 30.9 / 10.6 s | 5.5 / 2.1 s | 3.5 / 2.4 s |
| Case data | ineligible (first Home) | ineligible (first Home) | **valid** |

Every circuit completes on that path, so the jet and Corsair tour can pass there.
The large first-case freezes are synchronous OpenGL shader compiles at first use with
a cold Mesa disk cache (later cases reuse it). They are real stalls on a player's first
launch, and they leave the first Home phase without enough drawn frames.

## Is the GPU underperforming?

No fault was found in the driver or container path. Both hosts run Proxmox kernel
7.0 with default i915 parameters (GuC off, as usual for Gen9). Mesa is 25.0.7, and
the containers get the DRM render node directly, so there is no virtualization layer
in the GPU path. Under load PRIMIS held 1100 MHz (its maximum) at 62–69 °C and 29 W
package power, below its 35 W limit. The UHD 630 is a 24-EU integrated GPU of about
0.4 TFLOPS that shares system RAM. Measured Home GPU time per frame on PRIMIS:

| Setting | Forward+ | Mobile |
| --- | --- | --- |
| Tour settings (MSAA 2×, 3D scale 1.0) | 101.5 ms | 105.8 ms |
| MSAA off | 72.4 ms | 65.6 ms |
| MSAA off, 3D scale 0.75 | 49.4 ms (20 FPS) | — |

Mobile in flight with MSAA off reached 21.5 FPS. The tour's fixed workload uses
MSAA 2× at native 1080p; the product's Automatic mode on this GPU starts without
MSAA and at Low detail.

A minimal product profile in `display.cfg` changes this a lot: MSAA off, Low detail,
birds, runway meadow and RC track off, static flags, shadows off (technique, aircraft
cue, clouds), lens effects off, aircraft lighting Low without VFX. Measured on
PRIMIS (X11, 1920×1080, Stik, day, Club Field). These were debug-bridge sessions,
not the tour. Each one froze the flight 5 s after an airborne start, so every
variant renders the same view:

| Profile and renderer | 3D scale 1.0 | 0.75 | 0.67 |
| --- | --- | --- | --- |
| Tour settings, Forward+ (MSAA 2×, Medium) | 13.9 FPS | — | — |
| Minimal, Forward+ | 19.0 FPS | 29.7 FPS | — |
| Minimal, Mobile | 24.3–24.8 FPS | 38.5–39.1 FPS | **45.6 FPS** |
| Minimal, Compatibility (the product's iGPU renderer) | 26.2–26.5 FPS | **40.0 FPS** | — |
| Minimal, Mobile, SMAA 1x | — | 35.4 FPS | — |
| Minimal, Mobile, one-texture ground shader | 26.8 FPS | 42.8 FPS | — |

The 3D scale was a bilinear `scaling_3d_scale` set live. In the flight view a
one-texture ground shader saves only 1.8–3.7 ms. The ground's ~30 ms cost appears
in Home, whose camera sees much more ground. Disabling the depth prepass made no
difference in Forward+ (18.8 against 19.0 FPS). Minimal Forward+ with FSR2 Quality
did not reach Home within the launch timeout: it was still compiling shaders. Home
manages its own 3D scale (`home_render_budget.gd`). The product offers no plain
bilinear render scale: its reconstruction modes are native, FSR2/FSR3, DLSS and
MetalFX. An earlier pass of these sessions used the profile's default time of day,
which rendered at night. Those numbers are superseded.

Host findings that do cost performance on megatron:

- **Memory:** a 16 GB and a 4 GB DIMM, both at 2400 MT/s. With unequal sizes only
  4 + 4 GB run dual-channel; the other 12 GB are single-channel, and the iGPU uses
  system RAM. This plausibly explains megatron's 8–12 % lower flight FPS than PRIMIS
  despite its faster CPU (PRIMIS: two 8 GB DIMMs at 2667 MT/s, dual-channel).
- **Cooling:** 92 °C package and up to 94 °C per core at only 39 W with Frigate
  alone (i5-10500, 65 W TDP, 100 °C limit). The cooler, fan, paste or airflow needs
  attention; a GPU tour runs close to thermal throttling there.
- **Sharing:** Frigate keeps the same iGPU at its maximum clock continuously.

## Optimization options from published sources

Web research on 2026-11-22 found no driver-side speed-up for a GPU-bound Gen9 GPU.
Mesa has no performance switch for Gen9: its `INTEL_DEBUG` flags are diagnostics
that slow it down, and `mesa_glthread` only reduces OpenGL CPU overhead. The i915
driver keeps GuC/HuC off before Gen12, and `xe` starts at Tiger Lake. The UHD 630
stays on i915. The levers are memory, cooling and the game's own pixel cost:

| Lever | Expected effect | Source |
| --- | --- | --- |
| Matched dual-channel DIMMs on megatron | Iris Xe: +19–38 % FPS single→dual, flex only +10 %; UHD 620: +33 % average | [flex vs dual](https://tpongo-afk.github.io/posts/2026/01/13/how-does-flex-memory-mode-compare-to-dual-channel-mode/), [UHD 620 RAM upgrade](https://mattgadient.com/faster-gaming-on-intel-uhd-620-kaby-lake-r-by-upgrading-ram) |
| Plain bilinear 3D scale option (all renderers) | Our measurement: 0.75 took minimal Mobile flight from 25 to 39 FPS (Compatibility 26 to 40). FSR1/FSR2 are Forward+ only and may cost more than bilinear on slow GPUs | [Godot resolution scaling](https://docs.godotengine.org/en/latest/tutorials/3d/resolution_scaling.html) |
| MSAA off, SMAA 1x or FXAA on iGPU tiers (Mobile/Forward+ only) | MSAA 2× cost us 24–30 ms; FXAA "very low" and SMAA "low" cost | [Godot anti-aliasing](https://docs.godotengine.org/en/latest/tutorials/3d/3d_antialiasing.html) |
| A lighter ground-shader variant behind `#if` | Intel: gradient sampling (`textureGrad`) runs at a quarter of normal throughput. The ground uses four per pixel plus value noise and a 32-rectangle loop. Baking the surface mask and noise into textures removes most of that ALU work | [Intel Gen11 optimization guide](https://www.intel.com/content/www/us/en/developer/articles/guide/developer-and-optimization-guide-for-intel-processor-graphics-gen11-api.html) (Gen11; Gen9 by inference), [Godot shader preprocessor](https://docs.godotengine.org/en/latest/tutorials/shaders/shader_reference/shader_preprocessor.html) |
| Mobile before Forward+ on integrated GPUs | Forward+ uses RGBA16F buffers and has the highest base cost; Mobile uses RGB10A2. We measured 22 against 17 FPS | [Godot renderers](https://docs.godotengine.org/en/latest/tutorials/rendering/renderers.html) |
| Hide FSR2/TAA on iGPUs | FSR2 is high cost and did not finish compiling in about 2 min here | Godot anti-aliasing page |
| Warm materials and pipelines behind the loading surface; keep the pipeline cache enabled | Prevents first-use stalls. The shader baker skips only the GLSL→SPIR-V step (Forward+/Mobile). Compatibility relies on the Mesa disk cache plus drawing each material once while loading | [Godot pipeline compilations](https://docs.godotengine.org/en/latest/tutorials/performance/pipeline_compilations.html), [Mesa env vars](https://docs.mesa3d.org/envvars.html) |
| A/B test: depth prepass off for the ground | Unknown; Intel is not in Godot's default disable list | [ProjectSettings](https://docs.godotengine.org/en/latest/classes/class_projectsettings.html) |
| Frame-time-driven dynamic resolution in flight | Not built into Godot 4; a small script on `scaling_3d_scale` | [proposal #917](https://github.com/godotengine/godot-proposals/issues/917) |

Not useful on the UHD 630: variable-rate shading (ANV exposes it from Gen11), GuC
submission, raising the GPU minimum frequency (it already holds its maximum), and
`vblank_mode` (frames are already slower than the refresh rate). Published UHD 630
results are consistent with ours; for example Tom's Hardware measured 10.6 FPS in
Civilization VI on a dual-channel UHD 630.

## Host setup that works

- Weston headless with `--xwayland`; Godot on X11 (`DISPLAY` set, `WAYLAND_DISPLAY`
  unset). Packages: `xwayland`, `libxcursor1 libxinerama1 libxrandr2 libxi6
  libxrender1 libxext6`. Xwayland composition cost about 8 % of flight FPS.
- No `pcm null` ALSA default; the runner selects the Dummy driver itself.
- At least ~2 GB RSS headroom for Forward+ and ~3 GB for Compatibility, plus
  iGPU shmem, which is charged to the container.

## Implemented: GFX-IGPU-01 and the playable result

- **3D render scale:** a player option (Settings → Display: Native, 85, 75, 67 or 50 %).
  It is applied by `Reconstruction` as a bilinear scale with Native reconstruction in
  every renderer; FSR, DLSS and MetalFX keep their own scales.
- **Automatic graphics:** recognized integrated or software GPUs below the Low
  threshold now also start at 75 %. In the regenerated decision snapshot, 165 of
  1,558 decisions changed. Unidentified GPUs keep full resolution.
- **GOD TEST:** `--graphics automatic` runs the tour with the first-run recommendation
  for the actual GPU.

Validation on 2026-11-22: tour with `--graphics automatic`, Compatibility, Low, X11.
The bundle applied was MSAA off, projected Low shadow, Few birds, no runway meadow
and 75 % scale, as recorded in `identity.graphics`:

| Aircraft | PRIMIS circuit | megatron circuit | Simulation/wall | Case data |
| --- | --- | --- | --- | --- |
| Stik | 50.6 FPS, 1 % low 32.8 | 47.4 FPS, 1 % low 33.7 | 1.00 | ineligible: first Home |
| Jet | 40.7 FPS, 1 % low 27.3 | 38.0 FPS, 1 % low 26.6 | 1.00 | **valid** |
| Corsair | 40.2 FPS, 1 % low 27.0 | 38.2 FPS, 1 % low 26.5 | 1.00 | **valid** |

Every circuit finished in real time, and all six cases exited cleanly. Peak RSS was
2.0–2.5 GB, so Compatibility now fits PRIMIS. Home ran at 22–30 FPS against 6 FPS for
the fixed workload. The remaining defect is first-use OpenGL shader compilation with
a cold Mesa cache. The first case froze for 8.8–12.3 s at startup and 6.9–7.4 s while
loading; later cases froze for 1.0–4.9 s. That freeze also starves the first Home
phase of drawn frames.

## First-use freezes: cause and GFX-IGPU-02

The long freezes are a first-launch cost. Godot's Compatibility renderer caches
compiled programs in `user://shader_cache` (83 MB here), and Mesa keeps its own disk
cache. Each tour case starts with a fresh profile, so it always measures Godot's cache
cold. A second launch with Godot's cache warm took 18.6 s to Home and 7.6 s
Home → flight, against 19.1 s and 8.4 s cold; Mesa's cache was already warm in both.
A timestamped verbose launch with warm caches showed no freeze above 3.5 s: the
first 3D Home draw. The remaining time is CPU work spread over script, resource and
shader loading on the 35 W i5. OpenGL compiles on the main thread, so a loading
thread or warm-up pass cannot hide the cold-cache compile; it can only move it.

GFX-IGPU-02 explains the wait instead
([graphics_preparation.gd](../../../app/render/graphics_preparation.gd)). The
notice appears with the Compatibility renderer or on an integrated or software GPU,
never headless. On the first start the startup screen says "Preparing graphics for
this computer. Only the first start takes this long." The first flight's loading
panel says the first flight takes longer. A per-stage marker records the engine,
renderer, adapter, driver and game version, so the notice returns only after one of
them changes. A rendered PRIMIS session showed both notices and wrote both markers.

## Follow-ups

1. Product: let quality presets scale the terrain shader (`ground.gdshader`); the
   ground is about a third of Home GPU time on a UHD 630.
2. Product: split the first Home's indivisible frame (3.5 s with warm caches on PRIMIS).
3. Product: let the first-flight calibration also lower the render scale when even Low
   misses its budget, covering weak GPUs missing from the capability table.
4. Test pool: rendered pool checks on PRIMIS still use Godot's Wayland backend and
   can hit the same shutdown join.
5. Report the Wayland shutdown join upstream with a reproducer.
