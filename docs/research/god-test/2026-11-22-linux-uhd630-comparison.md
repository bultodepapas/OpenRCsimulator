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

## Host setup that works

- Weston headless with `--xwayland`; Godot on X11 (`DISPLAY` set, `WAYLAND_DISPLAY`
  unset). Packages: `xwayland`, `libxcursor1 libxinerama1 libxrandr2 libxi6
  libxrender1 libxext6`. Xwayland composition cost about 8 % of flight FPS.
- No `pcm null` ALSA default; the runner selects the Dummy driver itself.
- At least ~2 GB RSS headroom for Forward+ and ~3 GB for Compatibility, plus
  iGPU shmem, which is charged to the container.

## Follow-ups

1. Product: let quality presets scale the terrain shader (`ground.gdshader`) and
   MSAA, and consider a render scale for integrated GPUs; the ground alone is
   about a third of Home GPU time on a UHD 630.
2. Product: split the first Home's indivisible 1.7–2.3 s frame, and prepare the
   Compatibility materials before first use (30.9 s cold first-launch freeze).
3. Test pool: rendered pool checks on PRIMIS still use Godot's Wayland backend and
   can hit the same shutdown join.
4. Report the Wayland shutdown join upstream with a reproducer.
