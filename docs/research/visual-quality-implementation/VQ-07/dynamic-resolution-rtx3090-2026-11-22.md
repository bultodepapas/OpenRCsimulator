# RTX 3090 dynamic resolution screen

VQ-07d · 2026-11-22 · Windows, GeForce RTX 3090 driver 617.42, Forward+ / Vulkan 1.4.351, interactive 120 Hz display. The probes ran against the patched Godot `cafc17a19` Windows debug template with an isolated profile, inside the queue's manual desktop reservation. [Probe instructions](../../../../tools/graphics/dynamic_resolution/README.md)

## Observed pixel sizes

| Output | Internal at 100% | Internal at 85% | Restored internal |
| --- | --- | --- | --- |
| 1920×1080 window | 1920×1080 | 1632×918 | 1920×1080 |
| 2560×1440 window | 2560×1440 | 2176×1224 | 2560×1440 |
| 3840×2160 fullscreen | 3840×2160 | 3264×1836 | 3840×2160 |

Each completed-frame receipt reported the original output throughout and advanced the configuration generation at both transitions. All three launches exited cleanly and released their reservations.

## Pixel load

The stress probe uses the flight scale owner and a fullscreen shader. VSync is disabled and the process cap is 240 FPS. The standard case uses 3 s of warmup, 18 s of sustained load and 16 s of light recovery. FPS and late frames are process callbacks. A late frame exceeds 105% of the selected frame budget. GPU duration covers the viewport render, and the display refresh is 120 Hz.

| Mode | Target | Shader iterations | Heavy FPS | GPU median | Frame p95 | Late frames |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 1080p fixed 100% | 120 | 64 | 240.04 | 0.69 ms | 4.22 ms | 0 / 4321 |
| 1080p adaptive | 120 | 384 | 240.04 | 1.98 ms | 4.21 ms | 0 / 4321 |
| 1440p adaptive | 120 | 384 | 239.58 | 3.46 ms | 4.34 ms | 0 / 4313 |
| 4K fixed 100% | 120 | 384 | 115.46 | 7.79 ms | 9.34 ms | 686 / 2079 |
| 4K fixed 85% | 120 | 384 | 156.20 | 5.57 ms | 7.10 ms | 0 / 2812 |
| 4K adaptive | 120 | 384 | 147.82 | 5.65 ms | 8.70 ms | 131 / 2661 |
| 4K adaptive | 60 | 384 | 116.80 | 7.67 ms | 9.26 ms | 0 / 2103 |

At 120 FPS, the 4K adaptive pass confirmed 3264×1836 internally 3.22 s into heavy load and spent 14.79 s there. It confirmed full internal resolution 7.32 s into recovery. The late callback fraction was 4.92%, compared with 33.00% at fixed 100%. Fixed 85% stayed at the lower scale across both phases. At the 60 FPS target the same workload stayed at 3840×2160 throughout.

The 1080p and 1440p adaptive runs stayed at the full internal size at the 120 FPS target with the same 384-iteration shader. Their mean callback rates were close to the test cap.

The 40 s 4K repeat averaged 152.07 callbacks per second, with a frame p95 of 8.30 ms and 124 late callbacks out of 6083. It confirmed 85% at 3.23 s and stayed there for the remaining 36.78 s of load. It restored 100% at 9.45 s into recovery. The largest interval in the monitored downstep and upstep windows was 8.35 ms and 13.88 ms, respectively. The pass supports retaining the current dwell for this workload.

At 640 iterations with the 120 FPS target, the probe confirmed 85% at 3.30 s and the 75% floor (2880×1620) at 9.35 s into heavy load. It reported `target_missed_at_floor` during the heavy phase and held the floor. It recovered to 85% at 11.48 s and to 100% at 21.53 s into recovery. The 24 s heavy phase averaged 109.57 FPS. This is the overload and floor check.

The first stress launch exposed an invalid VSync enum. The corrected probe uses `DisplayServer` and checks the effective VSync and fullscreen state in its receipt. After a host status timeout, the launcher stopped repeating the process inventory before reservation and allowed the authority time to finish its own scan. The 60 FPS retry and subsequent runs completed with confirmed teardown.

The shader isolates pixel cost and exercises the production scale writer. Flight qualification still needs a matched native-physics flight on the experimental engine and a moving-aircraft readability comparison. The installed Windows native kernel receipt binds the official Godot binary, and the loader requires a matching executable for a production flight.

Raw receipts and logs are retained on the test host in `D:/OpenRC-drs-win-lab-20261122`. Clean producer cases are `producer-1080p-r4`, `producer-1440p` and `producer-4k`. The stress case directories identify the output, target and shader load. The two Godot executable hashes are recorded in each `experiment.json`.
