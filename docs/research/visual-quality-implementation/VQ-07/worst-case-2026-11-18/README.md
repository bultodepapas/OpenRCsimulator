# Worst-case scene on the RTX 3090 (VQ-07h-A5, 2026-11-18)

First run of the [automatic graphics plan's](../../../../plans/automatic-graphics.md#a5-measurement-loop-and-hardware-lab) worst-case scene protocol. The aim is to price the A4 "Ultra" tier from a measured heavy scene instead of the default day scene.

**Machine:** Windows 11, Ryzen 9 5900X and RTX 3090, Godot 4.8-beta2 official, editor binary. Each row ran the direct frame-time route with 5 s warmup and 20 s of samples, VSync off, Native reconstruction and the default MSAA 4×. Raw reports are in `U:/worst-case` and are not retained. [`run_worst.py`](run_worst.py) reproduces every row; [`summary.json`](summary.json), [`summary.csv`](summary.csv) and `logs/` hold the results.

## Protocol

- **Base:** High detail, the default day scene and the scripted pilot-view circle.
- **Worst:** Extreme Scene detail, 22:30 night, airfield lights forced on, the campfire, the `electrical_storm` sky, Ultra lens rain at 50 mm/h, and `OPENRC_LAKE_REFLECTIONS=planar` (High only).
- `-noplanar` drops only the planar lake, `-high` uses High detail, `-live` parks the Stik on the runway with 240 Hz physics instead of the scripted circle, and `-compat` uses Standard (Compatibility).
- 1080p and 1440p are windowed; 2160p is full screen. The core pairs were repeated three times, interleaved.

## Results

Milliseconds. Repeated rows give the range of the three runs.

| Row | Wall p50 | Wall p95 | Wall p99 | GPU p95 | Render CPU p95 | Draws | Primitives | VRAM |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| base-1080 (×3) | 1.64–1.73 | 2.23–2.36 | 2.68–2.87 | 1.39 | 0.54–0.62 | 233 | 288k | 1.2 GB |
| worst-1080 (×3) | 2.16–2.19 | 3.76–3.81 | 4.23–4.68 | 1.56–1.58 | 0.59–0.65 | 280 | 399–408k | 1.2 GB |
| worst-1080-noplanar | 2.03 | 2.70 | 3.40 | 1.56 | 0.66 | 280 | 384k | 1.1 GB |
| worst-1080-high | 2.19 | 3.91 | 4.80 | 1.54 | 0.65 | 278 | 353k | 1.2 GB |
| worst-1080-live | 2.56 | 6.58 | 7.96 | 1.30 | 0.71 | 208 | 347k | 1.1 GB |
| base-1440 | 1.81 | 2.50 | 2.99 | 1.90 | 0.63 | 233 | 318k | 1.5 GB |
| worst-1440 | 2.94 | 4.40 | 5.01 | 2.37 | 0.74 | 280 | 418k | 1.4 GB |
| base-2160 (×3) | 4.22–4.23 | 4.80–4.82 | 5.06–5.12 | 3.81–3.82 | 0.73–0.78 | 232 | 321k | 2.1 GB |
| worst-2160 (×3) | 5.27–5.29 | 6.18–6.74 | 7.52–7.78 | 4.52–4.59 | 0.80–0.87 | 280 | 444k | 2.1 GB |
| worst-2160-noplanar | 5.08 | 5.58 | 5.92 | 4.58 | 0.92 | 280 | 419k | 2.0 GB |
| base-1080-compat | — | 3.04 | — | 2.35 | 1.67 | — | — | — |
| worst-1080-compat | — | 3.42 | — | 2.58 | 1.80 | — | — | 0.8 GB |

Render CPU is the root viewport's render CPU plus frame setup, the same signal the calibration now uses.

## Findings

1. **The worst case costs the GPU 13–25% more than the base scene:** ×1.13 at 1080p, ×1.25 at 1440p and ×1.19 at 4K. At 4K the 3090 keeps a wall p99 of 7.5–7.8 ms, so above 128 fps.
2. **The planar lake costs about 1 ms of wall time and none of the root GPU time.** At 1080p it adds 1.1 ms to the wall p95; at 4K, 0.6–1.2 ms. The mirror renders at half resolution in a SubViewport outside the root viewport's GPU query, as the [planar study](../planar-lake-2026-10-22/README.md) warned. The calibration therefore keeps refusing to raise detail while SubViewports are active.
3. **Extreme Scene detail costs no measurable GPU time on the 3090 at 1080p** (1.56 against 1.54 ms GPU p95). It adds about 45k primitives and two draw calls. Its cost is therefore on the CPU and draw side, as the plan assumed, and is small on this CPU.
4. **The live route is CPU-bound by the simulation,** not by rendering. Its wall p95 is 6.6 ms with only 1.3 ms of GPU time. Render CPU stays under 1 ms on every Forward+ row.
5. **Compatibility spends about 1.7× Forward+'s GPU time and 2.7× its render CPU** on the same scene (2.35 against 1.39 ms GPU, 1.67 against 0.62 ms CPU at 1080p base). This is consistent with the renderer matrix, and Standard's worst case adds only +10% GPU.
6. **Nothing here limits the 3090.** All Ultra candidates (Extreme, night lights, storm, lens rain, planar lake) fit a 60 Hz budget at 4K with more than 2× headroom.

## What this supports, and what it does not

- **Supported for A4:** a worst-case factor of about 1.25 over the predicted base High GPU time, plus about 1 ms × (1 / `rel`) for the planar lake, priced against the frame budget. This lets the Ultra tier be admitted by prediction.
- **Not established:**
  - Behaviour on weaker, bandwidth-bound or tile-based GPUs. The planar mirror and night lights may scale differently there, so A5 lab machines must repeat this protocol.
  - The visual application of the night, storm and lens-rain flags was not confirmed by a screenshot. Managed debug launches on this host refused the run because `app/.godot` is a link, and the bridge requires a test-queue handle. Their application is inferred from the flags' parsers and from the +45 draw calls and +65k primitives at equal Scene detail (`worst-1080-high` against `base-1080`). The first Compatibility worst-case run picked up a half-edited calibration script and was discarded and rerun.
  - Real flight. The scripted circle and the parked live route are not a flight route; the plan's live route with a flying companion remains open.
