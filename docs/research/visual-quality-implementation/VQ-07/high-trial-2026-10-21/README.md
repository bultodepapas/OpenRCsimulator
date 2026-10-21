# VQ-07 — temporary High graphics trial

2026-10-21. Owner: VQ with UI/FW/LU. Base: `d20856f48f6b1db97f572dd8bd80698cca3beaa2` plus the source changes identified in `manifest.json`. Implemented opt-in experiment; VQ-07 renderer/profile qualification remains open.

## Delivered behavior

Home **Settings → Graphics → Try High (restart)** launches Forward+ with short-range SSAO, four blended directional-shadow cascades, an 8192-pixel 32-bit atlas, medium soft filtering, 0.53° solar-angle PCSS and sky reflections during flowing time of day. The menu reports the actual renderer/profile. Existing display resolution, MSAA, FPS and VSync controls remain available. [Operation and reproducible tools](../../../../../tools/graphics/README.md).

The switch is deliberately temporary. Keep pending display changes first; otherwise they revert before restart. Flight, ground-vehicle, Workshop and exit-request guards prevent restarting an active session. No renderer preference or retry marker is stored. Restart in Standard or launch normally to recover. There is no claim that a failed GPU initialization automatically falls back successfully on every driver.

The simulation, aircraft data, population and accepted assets are unchanged. This slice uses stock engine features and existing assets; it adds no downloads, GI, temporal AA, motion blur, SSR or volumetric fog. Expected return is better ground contact, shadow edges and material reflections with bounded integration. It is not an FPS optimization or an AAA-quality certification.

## Renderer corrections

- Sky output retains the exact Compatibility encoding; Forward+ receives linear values.
- The shared linear-radiance helper now applies its Compatibility inverse only on that renderer. All 17 consumers are unshaded spatial shaders; this prevents excess brightness in Forward+ stars, aircraft/field lights and weather effects.
- Lake depth reconstruction retains OpenGL's -1..1 NDC and uses 0..1 on RD renderers.
- Five scenery shader consumers normalize authored vertex colors on RD. Exact 1.0 material-tag endpoints remain exact; flower instance petal colors are not decoded twice.
- Native night validation exposed a white, dithered sky at exposure 49,131. Godot RD sky debanding multiplies its ±1/255 noise by exposure, overwhelming dark sky radiance. Per-sky debanding now remains enabled only on Compatibility. This corrects the renderer path without changing night adaptation or physical lighting estimates.

The engine implementation supports these distinctions: [RD sky shader](https://github.com/godotengine/godot/blob/4.7/servers/rendering/renderer_rd/shaders/environment/sky.glsl), [NDC/depth reconstruction](https://docs.godotengine.org/en/stable/tutorials/shaders/advanced_postprocessing.html), [Environment properties](https://docs.godotengine.org/en/stable/classes/class_environment.html), [shadow API](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html), [restart API](https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-set-restart-on-exit). Accessed 2026-10-21. Runtime verification uses pinned Godot 4.7.2, not documentation alone.

## Verification

Native host: Windows, RTX 3090, NVIDIA 617.42, Godot 4.7.2 `ed1daf0bf`; Compatibility OpenGL 3.3 / Forward+ Vulkan 1.4.351. GPU workloads ran serially. Logs and checked-runner receipts are under `checks/`.

| Check | Result and scope |
| --- | --- |
| Launcher | 9 Python tests; renderer/argument boundaries, environment isolation, packaged argv, non-Windows discovery and exit-code forwarding |
| High profile | 44 headless checks; 55 native Forward+ checks, including atmosphere updates and preservation of existing exposure/fog/state |
| Restart/settings | 42 headless checks; 45 native checks with EN/ES captures; pending-preview rollback, unchanged saves, Home/Pause/Workshop guards |
| Real restart | `restart/stage-0..2.json`: three actual processes, Standard → High → Standard, Home present, preferences unchanged; child logs checked |
| Existing regressions | Settings layout 58, advanced graphics 57, UI integration 31, sky 30 and lake 27 checks passed |
| Standard images | 12 fixed native 1920×1080 L4c images exactly match pre-change SHA-256 values; `standard-parity.json` |
| Visual scope | Matched P-51 ground, pilot, clubhouse/pit and lake stills; dusk and native production night diagnostics. Stills do not qualify motion/readability |

The first settings-layout run failed because Graphics overflowed the default page. Combining its action buttons and moving the long MSAA explanation to its tooltip restored the existing no-scroll requirement; `settings-layout-final` passes all 58 checks. The earlier failed receipt is retained.

A broader suite was started then stopped to avoid overlapping GPU measurements; no full-suite pass is claimed. Headless checks do not establish active Forward+ behavior. The restart probe verifies the editor-binary restart path; packaged and macOS relaunch require their own evidence.

The night sky ROI (right half, y=0..599, excluding HUD/terrain) measured mean sRGB luminance 0.986 before the debanding fix versus 0.134 in Standard. The final corrected High image passes mean <0.2 and <1% near-white pixels; see [pixel results](night/pixel-check.json), [Standard](night/standard-world-night.png) and [High](night/high-world-night-final.png). These are visual-regression screens, not photometric validation.

## Initial flight cost

One serial native pair, actual 1920×1080 fullscreen, 4× MSAA, VSync on, no added FPS cap, default Club-field Ugly Stik airborne quick flight with ideal battery. 10 s warmup + 60 s measurement. Both complete, active 240 Hz simulation, no solver fault. These samples precede the final night-debanding correction; retained source hashes identify that revision.

| Mode | p50 ms | p95 ms | p99 ms | Max ms | Measured simulation ticks |
| --- | ---: | ---: | ---: | ---: | ---: |
| Standard | 16.656 | 17.396 | 17.829 | 36.544 | 14,408 |
| High | 16.664 | 18.302 | 20.550 | 41.028 | 14,401 |

High misses the ≤18 ms p95 gate. One pair cannot establish a stable cost estimate or qualify 1080p60. Earlier windowed bare-Forward+ and High diagnostics rendered at 1920×1061 despite a 1080p request; retain them as diagnostics only (`bare-forward-flight-01.json`, `high-flight-01.json`). Do not combine these resolutions or static SubViewport timings into one performance claim. VSync limits average FPS, so this is pacing evidence, not a GPU throughput measurement.

The final source (including both night fixes) was rerun at actual 1920×1080: p50 **16.662 ms**, p95 **18.375 ms**, p99 **20.963 ms**, max **39.102 ms**, 14,400 measured ticks, complete and fault-free. It still misses the p95 gate; `high-final-source-flight.json` is the final-source diagnostic, not a repeated paired qualification.

## Local Windows build

The final manual Windows export succeeds and launches both renderers in native production night captures; the final packaged High Home startup also passes its native smoke check. Packaged Standard matches the source Standard PNG byte-for-byte, and packaged High matches the final source High PNG byte-for-byte. Export/launch receipts are retained. Local build: `D:/OpenRCsimulator-scratch/high-graphics-20261021/release/OpenRC Simulator.exe`, with its adjacent `openrc_ground_vehicle.dll`; identities are in `manifest.json`. This is an unsigned local trial (`export-manual`), not a published release or cross-platform validation. The production restart handler is exercised in source binaries; packaged Home-menu restart remains an open check.

## Remaining gates and known limits

1. Ordinary pilot-camera motion review at 20/50/100 m, transitions, moonlit/moonless flight, all aircraft and both landscapes. A close-up cannot qualify flight readability.
2. Repeat paired full-scene measurements on the final source, attribute the p95 miss, measure memory and input latency, and qualify lower-cost settings separately.
3. Packaged restart/recovery and native macOS/Linux/AMD/Intel coverage. OS names do not determine GPU capability. Ordinary Compatibility startup remains the supported baseline.
4. Forward+ emits `OpVectorExtractDynamic is not supported yet.` and seven Texture-RID shutdown leaks in both bare-Forward+ and High flight/capture diagnostics. No new script/shader errors were detected, but memory-clean shutdown is not established. Existing maple wind and aircraft-inertia warnings remain. Standard night capture also reports the already-open four-object shutdown warning.

No VQ-07a/b/c/g parent gate is marked fully accepted by this trial. The [advanced plan](../../../../plans/advanced-graphics.md) owns the remaining order; the next visible work should address demonstrated motion/lighting defects before adding more effects.
