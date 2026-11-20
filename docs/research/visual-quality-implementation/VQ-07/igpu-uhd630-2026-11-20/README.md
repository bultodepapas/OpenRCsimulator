# Intel UHD 630: Compatibility vs Mobile vs Forward+ (VQ-07h A5, 2026-11-20)

This is the first measurement of OpenRC on an integrated GPU. The [automatic-graphics plan](../../../../plans/automatic-graphics.md)
predicted that Mobile would be the efficient renderer for weak and integrated GPUs (its A2 gate). On this Intel iGPU
under Linux/Mesa, **Compatibility is the fastest renderer, and Mobile is not more efficient**.

## Setup

| Item | Value |
| --- | --- |
| GPU | Intel UHD Graphics 630 (CML GT2), i5-10500 host `megatron` (Dell OptiPlex 3080), shared memory |
| Container | LXC CT 206: the render node is shared, there is no passthrough, and 6 of 12 threads are assigned |
| Drivers | Mesa 25.0.7 (Debian 13): iris for OpenGL 4.6 and ANV for Vulkan 1.4.305 |
| Presentation | Headless Weston 14 with its GL renderer on the same iGPU; Godot runs as a Wayland client, so GL and Vulkan both present in hardware |
| Engine | Official Godot 4.8-beta2 (`cafc17a19`), source at `e9fe3f92` |
| Route | `--scripted --frametimes --frame-diagnostics --warmup=10 --t=60`, 1920×1080 windowed, `--max-fps 60`, defaults (Scene detail and grass High, scenery on) |
| Repeats | 3 × 60 s per renderer, interleaved, after a warm-up pass that filled the shader caches |
| Load | Frigate (the other iGPU user on the host) stopped for the measured runs |

## Results

All the runs below completed (`complete=true`) with no errors. The GPU p50 values of the three repeats agree within ±1%.

| Renderer | Frame p50 (ms) | Frame p95 / p99 (ms) | GPU p50 (ms) | Render CPU p50 (ms) | Draw calls | VRAM (MiB) |
| --- | --- | --- | --- | --- | --- | --- |
| **Compatibility (GL)** | **47.6 / 48.1 / 47.8** | 54 / 56 | **46.1 / 46.5 / 46.2** | 1.5 | 235 | 737 |
| Mobile (Vulkan) | 58.4 / 57.6 / 58.0 | 68 / 72 | 56.3 / 56.1 / 56.3 | 0.5 | 177 | 1,046 |
| Forward+ (Vulkan) | 75.4 / 76.3 / 76.0 | 86 / 89.5 | 73.9 / 74.6 / 74.1 | 0.8 | 235 | 1,234 |

- The frame is GPU-bound: GPU time is about 97% of frame time.
- Relative to Compatibility, Mobile costs **+21% GPU time** and Forward+ costs **+60%**.
- The renderers that use the RenderingDevice (Mobile and Forward+) still cut render CPU time by 2–3×, matching the
  RTX 3090.
- Mobile and Forward+ also use 42–68% more VRAM, and on an iGPU that VRAM is system memory.
- No renderer reaches 60 fps at 1080p with these defaults. Automatic would start a UHD-class GPU at Low Scene detail
  instead (`relative throughput < 0.04`).

The warm-up pass ran with Frigate active and showed the same order: 68.0 / 84.6 / 113.4 ms frame p50. With a cold
shader cache, the first Vulkan frames stall for seconds while shaders compile.

## Limits

- **Linux and Mesa only.** A2 asks for the Windows Intel driver (D3D12 or Vulkan). Windows drivers can rank the
  renderers differently, so this result does not settle Windows.
- **One scripted view at default settings.** Low and Medium Scene detail, and an active flight, were not measured.
- **Possible cause, not isolated:** `viewport_color.gd` forces an RGBA16F `use_hdr_2d` buffer on Mobile, which costs
  bandwidth on shared memory. It was not tested separately.
- **No AMD iGPU was measured.**

## Consequence

The plan's hypothesis, Mobile as the efficient renderer for integrated GPUs, fails here. Compatibility stays the right
Standard renderer for Intel iGPUs on Linux. This supports the policy in the
[legacy modes audit](../../../legacy-modes-audit-2026-11-20/README.md): Compatibility is frozen for new look work, but
it remains a supported path, and its performance on weak GPUs is still accepted and fixed. A2 needs a Windows Intel
measurement and a Mobile run without `use_hdr_2d` before Mobile can be adopted anywhere outside Apple Silicon.

## Method and data

- Script: `/opt/openrc/bench.sh` on CT 206. Bench raw data stays outside Git, at `U:\OpenRC\tmp\igpu-bench\`
  (`final/<renderer>-<n>/run.json`, `engine.log`).
- Per-frame values: `frame_deltas_s` and `raw_metrics.render_gpu_ms`, `render_cpu_ms`, `draw_calls` and
  `render_video_memory_bytes`. `frame_diagnose.py` reports every run valid.
- Host log: HomeLab `docs/logbook/entries/2026-11-20-megatron-ct206-openrc-gpu-bench.md`.
