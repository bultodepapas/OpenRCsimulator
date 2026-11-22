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
PRIMIS (X11, 1920×1080, Stik, debug-bridge sessions rather than the tour):

| Profile and renderer | Home | Flight |
| --- | --- | --- |
| Tour settings, Forward+ | 9.8 FPS | 12.3–12.9 FPS |
| Minimal, Forward+ | 14.0 FPS | 16.7–17.0 FPS |
| Minimal, Mobile | 14.2 FPS | 22.3–22.4 FPS |
| Minimal, Compatibility (the product's iGPU renderer) | 19.8 FPS | 25.2–27.6 FPS |
| Minimal, Mobile, 3D scale 0.75 (bilinear, set live) | 15.6 FPS | **34.7–35.2 FPS** |

Minimal Forward+ with FSR2 Quality did not reach Home within the launch timeout: it was
still compiling shaders. Home manages its own 3D scale (`home_render_budget.gd`), so
the live scale reached only the flight. The product offers no plain bilinear render
scale: its reconstruction modes are native, FSR2/FSR3, DLSS and MetalFX.

Host findings that do cost performance on megatron:

- **Memory:** a 16 GB and a 4 GB DIMM, both at 2400 MT/s. With unequal sizes only
  4 + 4 GB run dual-channel; the other 12 GB are single-channel, and the iGPU uses
  system RAM. This plausibly explains megatron's 8–12 % lower flight FPS than PRIMIS
  despite its faster CPU (PRIMIS: two 8 GB DIMMs at 2667 MT/s, dual-channel).
- **Cooling:** 92 °C package and up to 94 °C per core at only 39 W with Frigate
  alone (i5-10500, 65 W TDP, 100 °C limit). The cooler, fan, paste or airflow needs
  attention; a GPU tour runs close to thermal throttling there.
- **Sharing:** Frigate keeps the same iGPU at its maximu