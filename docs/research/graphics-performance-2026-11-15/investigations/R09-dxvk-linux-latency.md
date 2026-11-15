# R09 — DXVK on Linux: which latency lessons transfer?

2026-11-15 · External source investigation against application baseline `e488ef7653e8dd0f0a2e7db18e396bb4da0aaccc`. **Decision:** use DXVK as an implementation reference, not as an installation or setting for native Godot Vulkan. Reuse the existing Linux baseline and F6 experiment before considering a native extension. The application selected by the [standard project](../../../../app/project.godot#L60) must first be identified by its actual renderer and API at runtime.

## Sources inspected

| Source and identity | Type and relevant evidence |
| --- | --- |
| DXVK [`D3D11ReflexDevice`](https://github.com/doitsujin/dxvk/blob/71bf4bad427dd6a6a338d6768812110c61bb4503/src/d3d11/d3d11_device.cpp#L3524), [Vulkan presenter](https://github.com/doitsujin/dxvk/blob/71bf4bad427dd6a6a338d6768812110c61bb4503/src/dxvk/dxvk_presenter.cpp#L430), and [configuration](https://github.com/doitsujin/dxvk/blob/71bf4bad427dd6a6a338d6768812110c61bb4503/dxvk.conf#L99), commit `71bf4bad427dd6a6a338d6768812110c61bb4503`, 2026-11-14 | Actual translator, swapchain and sleep implementation; branch snapshot, not an OpenRC dependency. |
| [DXVK 2.6 release](https://github.com/doitsujin/dxvk/releases/tag/v2.6), 2025-03-13 | Maintainer notes on Proton Experimental, D3D11 Reflex and games that do not call the necessary functions. |
| [DXVK issue 5224](https://github.com/doitsujin/dxvk/issues/5224), 2025 discussion; [DXVK-NVAPI issue 323](https://github.com/jp7677/dxvk-nvapi/issues/323), opened 2025-10-24 | Developers dispute limiter placement and report a specific game/driver toggle and cap problem. They provide hypotheses and failure cases, not universal measurements. |

## Implementation findings

DXVK translates D3D8/9/10/11 calls to Vulkan, typically for Wine/Proton. It is not the Vulkan driver used automatically by a native Vulkan application. Native Godot Forward+/Vulkan reaches its own rendering-device and Vulkan backend; it does not invoke DXVK's D3D11 Reflex interface simply because both output Vulkan. Conversely a Windows build running under Wine through a D3D path would be a different experiment and is not evidence for native Linux Godot.

In the pinned DXVK source, `D3D11ReflexDevice::LatencySleep` checks its enabled state and a live swapchain, takes a safe swapchain reference, and forwards the call. Mode and marker calls similarly reach the swapchain. The Vulkan presenter creates a latency-compatible swapchain, applies `VkLatencySleepModeInfoNV`, signals a timeline semaphore through `vkLatencySleepNV`, releases its surface mutex and waits on the signal before continuing. It brackets present with markers and uses frame IDs. Its reported `frameLatencyUs` ends at GPU render completion, using input time or simulation start as its beginning: it is not photon latency.

The same snapshot's config calls the setting `dxvk.enableNvLowLatency2`; it is Auto and the comment says 32-bit defaults to disabled because of pacing problems. Later search-indexed configuration text can use other names, so copy no knobs without matching the exact version. DXVK 2.6 says Reflex required a supporting game, Proton path and driver; in several UE4 D3D11 games required calls were never made and DXVK could not manufacture them. This is direct evidence that translation cannot infer a missing input boundary.

Issue 5224 illustrates the contested tradeoff: one participant argues an external limiter cannot reliably know when a multithreaded game reads input, while another reports a positive result in a particular game. In issue 323, an NVIDIA participant observed expected upper-level calls while corresponding Vulkan calls disappeared in a particular setup after changes; the discussion does not establish a cause for all systems. The useful lesson is to trace the actual frame and mode transition and measure rather than rely on an overlay or a configuration label.

## OpenRC mapping, deliverable and stop

Use [the 1080p validation plan](../06-validation-and-benchmark-plan.md), existing diagnostics and a native Linux build to identify OS, X11/Wayland, compositor, GPU, driver, renderer, monitor/VRR, window, effective present mode and cap. First compare the existing native baseline and a simple cap/VSync alternative in paired CPU- and GPU-limited workloads. This is a measurement of native Godot, not a DXVK mode test. Do not install a DXVK fork or set Wine variables as a prerequisite. A separately scoped Windows/Proton experiment would need its own build and support claim.

If a material and repeatable input-response gap remains, [R10](R10-vulkan-low-latency.md) describes the optional native Vulkan feasibility gate. Reuse the [flight reader](../../../../app/sim/flight_session.gd#L1332) and [optical patch](../../../../app/input/latency_patch.gd#L147): fixed camera and threshold, at least 30 filmed physical transmitter transitions per condition as a screen, target 100 across sessions for p95 with uncertainty, and report stick-to-patch separately from first visible control response and any GPU/PCL estimate. Follow the existing 10-second warmup, 60-second measurement and three alternating A/B pairs where applicable; these are screening minima, not precise tail guarantees.

Acceptance is a reproducible result larger than instrument/session uncertainty with no new input, physics or pacing regression. Stop with the native baseline when hardware, actual presentation, usable input-to-present mapping or optical evidence is unavailable. No Linux hardware test or speedup was established by this source review.
