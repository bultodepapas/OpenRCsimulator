# VQ-07h: GPU cost of each graphics setting (RTX 3090, 4K)

2026-11-18. One host: Ryzen 9 5900X and RTX 3090 (driver 617.42), official `4.8.beta2`, Windows 11. Fullscreen 3840×2160, VSync off, scripted pilot-view circle.

Each row changes one setting against the defaults: MSAA 4×, Scene detail High, Runway meadow on, Birds normal. In `display.cfg`, MSAA 4× is stored as `msaa_3d=2`, Godot's `MSAA_4X`. [`run_knobs.py`](run_knobs.py) records each run in [`logs/`](logs/) and [`diagnoses/`](diagnoses/), with all values in [`summary.json`](summary.json) and [`summary.csv`](summary.csv). All 27 runs exited 0, logged no engine errors and produced valid diagnoses.

## Results

GPU p50 in ms, from the root-viewport poll; its freshness is unverified. Base is the median of three runs: the base row, the repeat and `msaa4`, which equals the default.

| Setting | Standard (OpenGL) | High (Forward+, Vulkan) | Mobile (Vulkan) |
| --- | --- | --- | --- |
| Base: MSAA 4×, detail High | 2.38 (2.38–2.51) | 3.13 (3.08–3.16) | 2.13 (2.12–2.16) |
| MSAA 2× | 2.53 (≈ base) | 3.12 (≈ base) | 2.14 (≈ base) |
| MSAA off | **1.98 (−17%)** | **2.37 (−24%)** | **1.71 (−20%)** |
| Scene detail Medium | **2.10 (−12%)** | **2.78 (−11%)** | **1.79 (−16%)** |
| Scene detail Low | 2.13 | 2.75 | 1.76 |
| Runway meadow off | 2.32 (noise) | 3.09 (noise) | 2.07 (noise) |
| Birds off | 2.39 (noise) | 3.12 (noise) | 2.14 (noise) |

Render CPU per frame was about 1.1 ms on Standard, 0.34 ms on High and 0.24 ms on Mobile.

## Findings

1. **Enabling MSAA is what costs, not the sample count.** On this GPU, 2× costs the same as 4×, and turning MSAA off saves 17–24%. Shared-memory iGPUs lack the 3090's bandwidth, and vendor guidance (Intel) says MSAA cost grows with samples there. That is not measured here.
2. **Scene detail Medium saves 11–16%.** Low adds nothing at this view.
3. **Meadow and birds are not GPU costs.** Their differences sit inside the base noise of about ±0.07 ms. The meadow's real cost is construction time, which the A33 and meadow-layout changes already reduced.
4. **Mobile is the cheapest renderer** in both GPU and render CPU time. It is still unqualified as a Windows choice because its visuals differ.

## How the defaults use this

[`gpu_capability.gd`](../../../../../app/render/gpu_capability.gd) `first_run_settings()` changes only the first-launch MSAA, and only for integrated GPUs:

| GPU class | Estimated throughput (`rel`) | First-launch MSAA |
| --- | --- | --- |
| Integrated | ≥ 0.10 | 2× |
| Integrated or software | < 0.10 | Off |
| Dedicated or unknown | any | 4× default |

Apple and Adreno GPUs are exempt, because tile-based GPUs resolve MSAA on chip. If the table does not know a Mesa chip codename, the GPU counts as unknown rather than as the generic integrated Radeon row.

Scene detail stays Automatic, driven by the same table. The MSAA values apply only on a fresh install, when neither `settings.cfg` nor `display.cfg` exists. `AppRoot` then writes them to `display.cfg` at once, so detection runs once and its result is stored. Upgraders keep their values. "Restore graphics defaults" returns to this GPU's recommendation, and a saved choice always wins.

## Limits

These numbers come from one high-end discrete GPU and one scripted view. Integrated-GPU behaviour is extrapolated from this and from vendor guidance. Measure an Intel and an AMD iGPU before tightening the thresholds.
