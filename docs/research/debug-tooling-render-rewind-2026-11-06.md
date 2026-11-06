# Debug tooling: GPU cost and rewind — 2026-11-06

Scope: the next debug-bridge gaps after [PT1h-R8](debug-tooling-gaps-2026-10-24.md), now that the game is larger and
the [Apple Silicon audit](desktop-delivery-investigations/DT-MAC-00-R4/README.md) names GPU work (ground, clouds) as
the main frame cost. This is dated research. Current usage is in the [debug bridge guide](../../tools/debug/README.md#gpu-cost-and-rewind-pt1h-r9).

## Gaps found

| Gap | Evidence |
| --- | --- |
| No GPU attribution in the running app. `frames` measures wall time only; `perf` gives draw calls for one instant. | The audit's "hide the ground material: −11 ms GPU" figure took a manual campaign. No agent command could reproduce it. |
| SubViewport work was invisible. Root-viewport measurements miss render-to-texture passes. | 8 SubViewports in a flight (projected-shadow silhouettes, magnifier). |
| No way to go back in flight time. `break` stops at a tick, but the moments before it are gone. | Flight logs replay exactly, but they are a separate offline workflow. |
| `break` could not see a crash. Watchpoints ran only on unpaused ticks, and a crash pauses at its own tick. | `break expr="not session.crash.is_empty()"` never fired in a real crash. |
| No viewport debug draw from the shell. | `Viewport.debug_draw` existed, but only the editor exposes it. |

## Inspiration (web research, 2026-11-06)

- Unreal Engine: [show flags](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/FEngineShowFlags?lang=en-US)
  and [view modes](https://dev.epicgames.com/documentation/en-us/unreal-engine/API/Runtime/Engine/EViewModeIndex),
  plus `ProfileGPU` / `stat unit`. Switching features off to find their cost, and naming the bounding thread, became
  `ablate`, `render` and `viewmode`.
  [Console notes](https://ikrima.dev/ue4guide/performance-optimization/notes-from-devs/deprecated-useful-console-commands/)
  carry the caveat that idle time inflates GPU time, which is why `render` compares GPU time with the wall frame
  and the vsync cap.
- Godot: `viewport_set_measure_render_time` must be enabled before measured times are non-zero
  ([godot#75346](https://github.com/godotengine/godot/issues/75346)). No source covered the Compatibility renderer,
  so it was tested here: the GPU time is non-zero and plausible on Windows/NVIDIA.
- Mark Wesley (2K Marin), [Implementing a Rewindable Instant Replay System for Temporal Debugging](https://gdcvault.com/play/1017769/Implementing-a-Rewindable-Instant-Replay),
  GDC 2013, and the [Unity Kinematica snapshot debugger](https://docs.unity3d.com/Packages/com.unity.kinematica@0.8/manual/Debugger.html).
  Both record a bounded state history and restore any recorded moment. That became `rewind`, built on the exact
  session checkpoint that already existed.
- Per-surface force gizmos: [avian_fdm debug render](https://docs.rs/crate/avian_fdm/0.1.0/source/src/debug_render/gizmos.rs),
  [Chaos vehicle debug commands](https://dev.epicgames.com/documentation/unreal-engine/vehicle-debug-commands-in-unreal-engine?lang=en-US),
  [MSFS 2024 aircraft CFD debug](https://docs.flightsimulator.com/msfs2024/flighting/devmode/editors/simobject-editor/debug/debug-aircraft-cfd/index.md).
  Not implemented this round (see next steps).

## What was built (PT1h-R9)

`render`, `layers`, `ablate` and `viewmode` (`app/debug/render_probe.gd`), and `rewind`
(`app/debug/rewind_ring.gd`). GPU timing is always on when a renderer exists, and it feeds `frames` and the hitch
causes. Watchpoints now also see ticks that pause themselves. The client prints tables. Bridge test: 69 → 85 checks.

## Measurements: Windows 11, RTX 3090, Godot 4.8 beta2, Compatibility, 1920×1080, vsync 120 Hz

Ugly Stik, Club field, airborne start, default view. These are short development screens, not qualification
evidence.

**`render`, flying:**

| Measure | Value |
| --- | --- |
| GPU, median | 2.74–2.91 ms: 1.6–1.9 ms root viewport plus about 1.0 ms of SubViewports |
| Frame | 8.95–9.49 ms (105–112 fps) |
| Draw calls | 496–501 (165 canvas) |
| Verdict | frame cap or CPU, not GPU, on this machine |

Earlier, a 60-frame mean on Home reported 20 ms. One stale 971 ms readback caused it, so `render` and `ablate` use
medians.

**`ablate`, flying, frozen.** The baseline was 2.59 ms with a noise of 0.075 ms. Significant savings:

| Target | GPU saved | Share | Notes |
| --- | --- | --- | --- |
| `airplane` | 1.24 ms | 47 % | 280 draw calls |
| `@subviewports` | 1.05 ms | 37 % | |
| `Field` | 0.23 ms | 9 % | |

MSAA, fog and shadows were below the noise. A run while the pause menu covered the view gave a lower baseline
(1.7 ms) and a different ranking, so views must be compared like for like.

**Findings for the owners:**

1. **The aircraft's projected-shadow silhouette** (`ProjectedShadow/Silhouette256`, 256×256, re-requested every
   frame) costs about 0.84–0.92 ms of GPU per frame. That is about a third of the frame's GPU time, and it scales
   with the aircraft's 280 draw calls rather than with the 256² pixels. Candidates: render the silhouette from a
   merged or low-detail mesh, or update it less often. Owner: shadows/graphics.
2. **`@half_res` (3D scale 0.5) made the GPU 76 % slower** in Compatibility on this GPU, because the frame is not
   pixel-bound here. Treat 3D scale as a pixel-bound fix only, per platform. This does not contradict the M1
   result, where the frame is pixel-bound.
3. **`restore_checkpoint()` leaves the session on recorded inputs** (`input_enabled = false`). This is correct for
   replay, but a pilot-flown branch must re-enable input. The bridge does so by default (`inputs=pilot`).
4. **The airborne start opens on the pause menu.** Measurements taken without `close` + `resume` measure a covered
   view.

**`rewind`:**

- A checkpoint costs 0.50–0.60 ms and 2.7 KB, every 60 ticks by default.
- Two branches restored from the tick-60 checkpoint and stepped 480 ticks gave the same state hash.
- A real crash at tick about 643 was rewound 1 s to tick 360, at 26.7 m with no crash. After `resume` and a
  pull-up, the aircraft climbed to 55 m. No engine errors were logged.

**`viewmode`:** in Compatibility, `overdraw` and `unshaded` change the picture. `wireframe` applies only to meshes
created after it was enabled, which was verified by enabling it on Home and then flying.

## Next steps (not built)

- **Per-surface force vectors in 3D**: lift, drag and thrust per aerodynamic surface, with CG, wind and velocity, as
  in avian_fdm and Chaos. They need a read-only per-surface load output from the aircraft evaluators. Today the
  kernel exposes only total `last_loads`. Owner: physics, through the kernel contract, without vehicle branches.
- **GPU pass timing inside a viewport** (opaque, transparent, sky, post) needs Forward+/Mobile and RenderDoc or
  Xcode captures. The Compatibility renderer gives per-viewport totals only.
- **Ablating shader features** (for example cloud shadows on the ground) needs named toggles from their owners.
  `ablate` already accepts any node, and a feature switch could become a new `@flag`.
