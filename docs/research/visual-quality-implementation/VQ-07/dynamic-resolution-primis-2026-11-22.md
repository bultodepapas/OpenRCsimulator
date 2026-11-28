# Primis UHD 630 dynamic resolution screen

VQ-07d · 2026-11-22 · Primis CT 405, Debian 13, Intel UHD Graphics 630 (CFL GT2), Mesa 25.0.7. Godot used Mobile/Vulkan 1.4.305 through Xwayland on a private Weston 14.0.2 headless output. Weston also reported the UHD 630 as its GL renderer. Each case held the host's pool lock until process teardown. [Host guide](../../../tools/primis-testlab.md)

## Completed pixels and fallback

| Compositor output | Internal at 100% | Internal at 85% | Restored internal |
| --- | --- | --- | --- |
| 1920×1080 | 1920×1080 | 1632×918 | 1920×1080 |
| 2560×1440 | 2560×1440 | 2176×1224 | 2560×1440 |
| 3840×2160 | 3840×2160 | 3264×1836 | 3840×2160 |

The experimental Mobile/Vulkan build returned positive, fresh completed GPU samples. In each output the frame IDs advanced 2 → 4 → 6 and configuration generations advanced 3 → 4 → 5. The output stayed constant while the internal dimensions changed.

The official 4.8 beta 2 build kept the configured fixed scale on both Mobile/Vulkan and Compatibility/OpenGL. On the patched Compatibility build the API was present, the renderer reported no support and the controller kept the fixed 100% scale with `completed_gpu_source_unavailable`.

## Test inputs

The source scripts match OpenRC `cfb93aded14b`. The Linux debug template was built in WSL Ubuntu 24.04 from Godot `cafc17a192acf67903910a68aeb3c076c0907a4b` with the completed-frame patch, X11, Vulkan, OpenGL, GDScript and the lightweight text modules. Its SHA-256 was `14a601ab3c452bfd8251b0354131a2b0ace7474cce9feb6dc22361f1d643495f` and was verified again on Primis before use. [Engine and probe guide](../../../../tools/graphics/dynamic_resolution/README.md)

The synthetic shader is the same shader used on the RTX 3090. A fixed-scale calibration on the official engine measured 55.30 callback FPS at 48 iterations, 29.97 at 96 and 20.94 at 144. The calibration selected the stress loads. The completed-frame comparison uses the patched engine and reports its own GPU samples.

## 1080p load and recovery

The stress probe measures process callbacks with VSync disabled and a 240 FPS process cap. A late callback is above 105% of the selected target budget. The measured heavy and recovery phases require uninterrupted focus. GPU durations cover the viewport render.

| Mode | Target FPS | Iterations | Heavy FPS | Frame p95 | Late callbacks |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fixed 100% | 60 | 56 | 48.95 | 22.26 ms | 882 / 882 |
| Adaptive | 60 | 56 | 64.20 | 20.55 ms | 103 / 1156 |
| Fixed 85% | 60 | 56 | 65.13 | 15.95 ms | 0 / 1173 |
| Adaptive | 30 | 56 | 48.76 | 21.17 ms | 0 / 878 |
| Fixed 100% | 30 | 110 | 26.77 | 38.49 ms | 643 / 643 |
| Adaptive | 30 | 110 | 33.94 | 37.68 ms | 165 / 815 |

The 60 FPS adaptive case confirmed 1632×918 internally 2.13 s into heavy load and stayed there for 15.90 s. The late fraction fell from 100% to 8.91%. The probe returned to 1920×1080 internally 10.31 s into recovery with zero late callbacks in that phase. The 85% fixed case stayed at 1632×918 in both phases. At the 30 FPS target, the same 56-iteration load kept the full 1920×1080 internal extent throughout.

With the stronger 110-iteration load and a 30 FPS target, the probe confirmed 1632×918 at 6.17 s into heavy load and restored 1920×1080 at 10.67 s into recovery. The late fraction fell from 100% at fixed 100% to 20.25% in the adaptive case.

These are synthetic workload and virtual-output results. Native-physics flight, aircraft readability and physical display acceptance remain open for the experimental engine. The raw receipts and launcher are retained under `U:/OpenRC-drs-primis-20261122` on the test workstation.
