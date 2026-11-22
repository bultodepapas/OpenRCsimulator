# Angela M1 dynamic resolution screen

VQ-07d · 2026-11-22 · Apple M1, macOS 27.0.1, built-in 2560×1600 Retina at 60 Hz, on AC. Each rendered case held the Mac pool lock and required a focused fullscreen window. The configuration used Mobile with the Metal 3 backend and barrier synchronization. [M1 host guide](../../../tools/macos-m1.md)

## Display and completed pixels

The first fullscreen launch observed the desktop's 1440×900 logical mode and 2880×1800 Metal surface. It confirmed 2880×1800 → 2448×1530 → 2880×1800 internally while the output stayed at 2880×1800. The native-panel comparison uses a second, independently observed output.

The test helper temporarily selected the app-only 1280×800 logical mode with 2560×1600 Retina backing. It then verified the original mode again after exit. Godot reported a 2560×1600 viewport and Metal surface. The surface receipt records the reported extent. Individual drawable acquisitions are unmeasured. [Core Graphics app-only configuration](https://developer.apple.com/documentation/coregraphics/cgconfigureoption/forapponly)

| Step | Internal 3D pixels | Viewport output | Completed frame | Generation |
| --- | --- | --- | ---: | ---: |
| Full | 2560×1600 | 2560×1600 | 2 | 3 |
| 85% | 2176×1360 | 2560×1600 | 4 | 4 |
| Restored | 2560×1600 | 2560×1600 | 6 | 5 |

The official Godot 4.8 beta 2 control used Metal and held the fixed 100% scale with `completed_gpu_source_unavailable`.

## Test inputs

The rendering probes use the source scripts from `cfb93aded14b`. The renderer-only debug template was built natively on Angela from Godot `cafc17a192acf67903910a68aeb3c076c0907a4b` with the completed-frame patch, SDK 27.0 and Metal. The first build failed to find the toolchain C++ headers. Passing the installed SDK's libc++ include path completed the build. The executable SHA-256 was `17a347aaeda82ef64de195b761bc8db36114faff6a2c7b2d1e7434ab9ef722de`. [Engine and probe guide](../../../../tools/graphics/dynamic_resolution/README.md)

The stress probe uses the same synthetic shader as the Windows and Primis screens. A fixed-scale calibration on the official engine measured 57.94 callback FPS at 48 iterations, 30.72 at 96 and 20.89 at 144. The matched runs use 56 iterations for the 60 FPS target and 110 for the 30 FPS pressure case.

## Native-panel load and recovery

The stress probe used VSync off, a process cap of 240 FPS and 60 Hz output. FPS are process callbacks. A late callback exceeds 105% of the selected frame budget. All reported steady phases required uninterrupted focus and complete Metal samples.

| Mode | Target FPS | Iterations | Heavy FPS | Frame p95 | Late callbacks |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fixed 100% | 60 | 56 | 50.36 | 20.13 ms | 907 / 907 |
| Adaptive | 60 | 56 | 63.22 | 19.97 ms | 212 / 1138 |
| Fixed 85% | 60 | 56 | 67.13 | 15.12 ms | 0 / 1209 |
| Adaptive | 30 | 56 | 50.29 | 20.28 ms | 0 / 906 |
| Fixed 100% | 30 | 110 | 26.91 | 37.75 ms | 646 / 646 |
| Adaptive | 30 | 110 | 34.17 | 37.31 ms | 161 / 821 |

At the 60 FPS target, the adaptive case confirmed 2176×1360 internally 4.23 s into the heavy phase and spent 13.79 s there. The late callback fraction fell from 100% to 18.63%. It confirmed full internal size again 10.39 s into recovery with zero late callbacks in that phase. Fixed 85% used 2176×1360 in both phases.

At the 30 FPS target, the lighter load held the full internal extent. Under the 110-iteration load, the controller confirmed the 85% step after 6.00 s and recovered to full resolution 10.38 s after the load ended. The heavy-phase late fraction fell from 100% to 19.61%.

The nine accepted probe receipts and the original scaled-mode attempt are retained in `U:/OpenRC-drs-angela-20261122/evidence/angela-receipts.tar.gz`. The stress batch exited cleanly, the Mac pool was free and the initial desktop mode had been restored. The test used a synthetic scene. Aircraft flight, readability and package qualification remain open.
