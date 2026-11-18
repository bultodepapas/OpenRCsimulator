# VQ-07: RTX 3090 renderer, reconstruction and resolution matrix

2026-11-17 · One host, official engine `4.8.beta2.official.cafc17a19`, `main` at `035c43eae` plus the uncommitted VQ-01c status change. Follows the [graphics audit](https://github.com/bultodepapas/OpenRCsimulator/tree/audit/graphics-performance-technologies-2026-11-15/docs/research/graphics-performance-2026-11-15) M0/M1 screens and the earlier [VQ-01c timing note](../../VQ-01c/timing-ownership-2026-11-17/README.md).

**Host:** Windows 11 10.0.26100, Ryzen 9 5900X, GeForce RTX 3090 (driver 32.0.16.1742 / 617.42), 3840×2160 120 Hz display at 150% scaling. No NVIDIA fork package exists on this host, so DLSS, FSR3 and Reflex were not tested.

## Method

[`run_matrix.py`](run_matrix.py) launches Main's direct route, which never reads saved preferences, with `--frametimes --frame-diagnostics`, 5 s warm-up, 20 s sample, audio `Dummy` and VSync disabled unless the row says otherwise. Each run is reduced with `research/performance/frame_diagnose.py`. [`summary.csv`](summary.csv) and [`summary.json`](summary.json) hold every row. [`logs/`](logs/) holds each engine log with its exact command and environment. [`diagnoses/`](diagnoses/) holds each reducer output. Raw per-frame reports stayed outside the repository.

- **Workloads:** `scripted` is the repeatable pilot-view circle with physics off. `static` is the live-input route with no radio: the Stik sits on the runway with the 240 Hz physics running, seen from the pilot station.
- **Profiles:** Standard is `gl_compatibility`/OpenGL. High is `forward_plus` on Vulkan or D3D12. Mobile was forced with `--rendering-method mobile` on Vulkan or D3D12.
- **Fixed settings:** non-temporal rows use MSAA 2×, the direct-route default; FSR2 rows own their AA. Scene detail is `high` unless noted.

All 55 runs exited 0 with no engine errors, every sample was drawable (`render_progress: observed`), and every diagnosis was valid. One run per row, except the four core rows, which ran three times in interleaved order.

## Results

Wall frame interval in ms. The GPU column is the root-viewport poll, whose freshness is unverified.

### Renderer and driver, 1080p Native

| Row | Scripted p50 / p95 | Static p50 / p95 / p99 | GPU p50 (scripted) | VRAM est. |
| --- | --- | --- | --- | --- |
| Standard, OpenGL | 2.04 / 2.44–3.59 (×3) | 4.47 / 7.70 / 10.26 | 1.26 | 0.78 GB |
| High, Vulkan | 1.51 / 1.84–2.62 (×3) | 3.79 / 5.33 / 6.88 | 1.07 | 1.23 GB |
| High, D3D12 | 1.53 / 1.80–2.47 (×3) | 3.94 / 5.43 / 7.18 | 1.10 | 1.46 GB |
| Mobile, Vulkan | 1.39 / 2.02 | 3.63 / 5.01 / 6.81 | 0.77 | 0.99 GB |
| Mobile, D3D12 | 1.51 / 2.15 | 3.51 / 4.63 / 5.92 | 0.77 | 1.26–1.32 GB |

### FSR2 ladder, 1080p (High)

| Mode (nominal input) | Vulkan p50 / p95 | D3D12 p50 / p95 | GPU p50 Vulkan |
| --- | --- | --- | --- |
| Native, MSAA 2× | 1.51 / 1.84 | 1.53 / 1.80 | 1.07 |
| FSR2 Native AA (1920×1080) | 1.73 / 2.33 | 1.79 / 2.62 | 1.41 |
| FSR2 85% (1632×918) | 1.65 / 2.19 | 1.75 / 2.50 | 1.23 |
| FSR2 Quality (1280×720) | 1.53 / 1.83 (×3) | 1.83 / 2.77 | 1.03 |
| FSR2 Balanced | 1.61 / 2.26 | 1.78 / 2.54 | 0.97 |
| FSR2 Performance (960×540) | 1.59 / 2.36 | 1.77 / 2.62 | 0.90 |

### Resolution (scripted, Native unless noted)

| Output | Standard p50 / p95 | High Vulkan p50 / p95 (GPU) | High FSR2 rows |
| --- | --- | --- | --- |
| 1280×720 | 2.02 / 2.42 | 1.47 / 1.69 (0.73) | — |
| 1920×1080 | 2.04 / 2.44 | 1.51 / 1.84 (1.07) | Quality 1.53 / 1.83 |
| 2560×1440 | 2.35 / 3.58 | 2.02 / 2.81 (1.57) | Quality 2.04 / 2.84 |
| 3840×2160 fullscreen | 2.73 / 3.90 | 3.77 / 4.58 (3.09); D3D12 3.37 / 3.82 | 85% 4.35 / 5.19; Quality 3.49 / 4.23; Performance 2.86 / 3.59 |
| 3840×2160 static | 5.23 / 8.05 | 4.17 / 6.75 | — |

### Other dimensions (1080p, High Vulkan unless noted)

| Row | p50 / p95 | Note |
| --- | --- | --- |
| Scene detail low / medium | 1.59 / 2.41, 1.60 / 2.31 | Standard: 2.28 / 3.45, 2.26 / 3.47 |
| Sunset 18:45 / night 22:30 | 1.40 / 1.83, 1.38 / 1.70 | Standard night 1.92 / 2.56 |
| Contact shadows on / sun shadow off | 1.53 / 1.90, 1.45 / 1.86 | — |
| Chase view | 1.86 / 2.62 | Standard 2.07 / 3.30 |
| VSync 120 Hz | all 8.33 p50 | Intervals >12.5 ms in 2,401 frames: Standard 1, High 15, High 4K 12 |

## Findings

1. **No row is GPU-limited at 1080p.** Every 1080p configuration runs at 450–700 FPS, and the GPU poll stays near 1 ms. Dynamic resolution has nothing to regulate on this GPU, so its row stays static-only.
2. **Standard (OpenGL) is the slowest renderer here.** It spends 1.0–1.2 ms of render CPU against about 0.3 ms for Vulkan, D3D12 and Mobile, which makes 1080p p50 about 35% slower than High Vulkan. The only exception is 4K scripted Native, where Standard (2.73 ms) beats High (3.4–3.8 ms) because High pays for its extra effects at 8.3 M pixels. Standard is the shipped Windows default. On a discrete NVIDIA GPU it costs performance and image features, so automatic preset recommendation should use measured hardware, as AGENTS.md requires, rather than a fixed default. Weaker and non-NVIDIA GPUs still need their own rows.
3. **FSR2 is not a speed option at 1080p on this GPU.** Every FSR2 mode lands within ±0.2 ms of Native at p50; Quality matches Native over three repeats. At 4K, Quality saves 7% and Performance 24%, but **FSR2 85% at 4K is 15% slower than Native**: its GPU poll is 3.86 ms versus 3.09 ms. The settings UI should not present FSR2 85% as a performance choice at high output resolutions.
4. **D3D12 roughly ties Vulkan at 1080p, and at 4K it is faster (3.37 vs 3.77 ms p50) but uses about 230 MB more VRAM.** Mobile has the lowest GPU cost and VRAM, at a feature cost.
5. **The live route is CPU-bound by physics, not rendering.** Static rows run 3.5–4.5 ms p50 with fewer draws than scripted. The engine log shows the native kernel was refused (`mirrored source differs from the verified native build: app/app_state/native_package.gd`), so physics ran on the GDScript reference at a median 742 µs per 240 Hz tick, above the ROADMAP's 500 µs Gate P budget. See the native follow-up below.
6. **VSync pacing:** High Vulkan missed more 120 Hz vblanks (15 intervals >12.5 ms in 20 s) than Standard (1). This is one run per row and needs repeats before any swapchain or frame-queue change.

## Native kernel follow-up (2026-11-18)

### Build and gates

- **Build.** The Windows NK-4 build used `OPENRC_NK_TOOL_ROOT=D:/OpenRCsimulator-native/nk`. The exFAT `U:` drive cannot host the root, because Git refuses its ownerless checkout. MinGW g++ 15.2 built the DLL and its mutant, which link only `KERNEL32.dll` and `msvcrt.dll`.
- **Why the first attempt stopped.** The enrolled host's queue refuses checked commands that carry user arguments, so the first gate attempt stopped before Godot started.
- **How the gates ran.** All 19 headless gates ran with `OPENRC_TESTQUEUE_ROOT` set to a private, unenrolled `U:` root. This is the owner-approved convention for this host. No timing gate is involved: `trajectory` uses `skip-timing=true`.
- **Result.** The 18 oracles were bit-identical to the GDScript reference, for example 128,664 of 128,664 stage states. The negative control diverged as required, with 28,315 of 128,664 states differing.

### Installation

Installation first refused, because `app/.godot` is a junction to the relocated import cache on `D:`. The installer now reads a relocated `extension_list.cfg` and refuses only when it would have to remove this kernel's entry; the change is in `research/native-kernel/build.py` and has a test.

The builder hash is part of the build receipt, so the change required a fresh build, mutant and full gate run, which all passed again before installation.

### Native physics results

The `nk-static-*` rows rerun the live-physics route with the installed backend. Every log reports `"backend":"native"`, every run had no errors, and every diagnosis was valid. In the table, "physics step" is the median `physics_step_usec`.

| Row | Wall p50 (ms) | Wall p99 (ms) | Physics step (µs) |
| --- | --- | --- | --- |
| Standard, OpenGL | 4.47 → **3.44** | 10.26 → **5.82** | 742 → **384** |
| High, Vulkan | 3.79 → **2.72** | 6.88 → **4.78** | 742 → **385** |
| High, D3D12 | 3.94 → **2.97** | 7.18 → **5.38** | 736 → **400** |
| Mobile, Vulkan | 3.63 → **2.52** | 6.81 → **4.16** | 742 → **379** |
| Mobile, D3D12 | 3.51 → **2.60** | 5.92 → **4.48** | 719 → **373** |
| Standard, 4K | 5.23 → **3.43** | 9.75 → **5.65** | 767 → **380** |
| High Vulkan, 4K | 4.17 → **2.54** | 8.62 → **3.46** | 755 → **452** |

The physics step halves and now sits inside the ROADMAP's 500 µs Gate P budget. Live-route frame time falls 25–40% at p50 and 30–60% at p99.

### Native follow-up limits

These numbers come from a parked aircraft on one host. The installation is local and ignored by Git. Windows release packages still ship without the native kernel; the [NK guide](../../../../../research/native-kernel/README.md#windows-build-nk-4) keeps releases Linux-only.

## Follow-up: saved graphics mode (VQ-07h, 2026-11-18)

Finding 2 led to the owner's [default-renderer decision](../../../../DECISIONS.md#compatibility-baseline-and-a-windows-nvidia-package). The engine behavior it relies on was checked on this host with official 4.8-beta2. A minimal project set `config/project_settings_override.template="user://renderer.cfg"`, and the file selected `forward_plus`:

| Launch | Result |
| --- | --- |
| Editor binary, `.template` key | `gl_compatibility`/`opengl3`; the file is ignored |
| Editor binary, untagged key | `forward_plus`/`vulkan` |
| Exported release template, `.template` key | `forward_plus`/`vulkan` |
| Exported template running the real `renderer_preference.gd`, no file | 1st process `gl_compatibility`, detected `NVIDIA GeForce RTX 3090`, saved the file and restarted; 2nd `forward_plus`/`vulkan`, no restart; a 3rd manual launch started directly in `forward_plus` |

`app/tests/test_renderer_preference.gd` covers the GPU policy, every startup transition and the file format. The renderer guard and High-restart tests still pass. A full exported game was not launched, and Automatic's GPU list is extrapolated from this one RTX row: other GPUs need their own rows.

## Limits

These are short single-host runs. The scripted circle and parked live route are not active piloted flight, and none of this is pilot, readability or image-quality evidence. GPU polls are cached last readings. The VRAM column is the engine estimate, not driver residency. Weaker GPUs, AMD/Intel, Linux and macOS rows remain open, in the 1080p-first order.
