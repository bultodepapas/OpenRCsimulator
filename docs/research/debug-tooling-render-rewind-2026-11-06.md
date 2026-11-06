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

## Round 2 (same day): flight gizmos and BugIt (PT1h-R10)

The aircraft had no physics overlay, while the RC truck has one (`vehicles/ground/contact_debug.gd`). Bug reports
also had no way to carry an exact flight state.

**Inspiration:**

- X-Plane's flight-model lines: force vectors on the aircraft, cycled with a key
  ([X-Plane Mobile help](https://x-plane.helpscoutdocs.com/article/83-x-plane-mobile-flight-model-lines),
  [AVSIM discussion](https://www.avsim.com/forums/topic/385778-see-how-it-flies/)).
- Unreal's [`BugIt`](https://dev.epicgames.com/documentation/unreal-engine/API/Runtime/Engine/GameFramework/UCheatManager/BugIt?application_version=5.4):
  location and screenshot in one command, then `BugItGo` to return there.
- The free [Debug Draw 3D](https://godotengine.org/asset-library/asset/edit/14507) addon was considered and not
  adopted:
  - it is a native GDExtension binary for each platform, an extra pinned dependency for Web and macOS;
  - its listings disagree on the licence (MIT or AGPLv3);
  - the repository already draws debug lines with `ImmediateMesh` in the truck overlay.

**Measurements** (Windows, RTX 3090, 1080p, Ugly Stik):

- The gizmo label agreed with the independent HUD: 26.3 m/s against 59 mph, 41.5 m against 136 ft.
- In level flight, the aerodynamic + propulsive force was 1.02 g upward, and lift balanced gravity at n = 1.00 g.
- The first version cost about 1 ms per frame and was unreadable from the pilot's ground camera: arrows about 1 m
  long on an aircraft 150 m away, and a fixed-size label magnified by the zoomed field of view. The current version
  takes about 0.3–0.4 ms. It draws the trail once instead of five times, caches the camera, scales arrows ×5.9 at
  that range, and corrects the label size for the field of view.
- `bugit` in flight wrote a report, a screenshot and a checkpoint. `home`, then `bugitgo`, restored tick 799 in
  2.6 s, with the same state hash as before.

## Round 3 (same day): agent ergonomics and MCP (PT1h-R11)

Measured friction while driving the app as a fresh agent would:

- Settings' option buttons were listed by their current value ("Automatic", "Automatic (Off)"), not by their field.
  `labels=true` showed the labels, but only as separate rows.
- Lookups needed internal node names such as `WindowResolution`.
- Flight overlays showed four identical "×" buttons.
- The AppRoot setters (`set_landscape`, `set_time_of_day`, …) ignore invalid values silently.
- Valid ids had to be guessed from errors.
- Flight screens such as overlays opened only from the pause menu, and the error said nothing more.

**Inspiration:**

- [Playwright MCP](https://playwright.dev/mcp/introduction): accessibility snapshots with element refs, actions by
  ref, and a snapshot after each action.
- [AltTester](https://alttester.com/docs/sdk/pages/commands.html): game UI selectors by name, text and path.
- The [MCP tools specification](https://modelcontextprotocol.io/specification/2025-06-18/server/tools.md): typed
  tools with `inputSchema`, image content, and `isError` for failures inside a tool.

**Built:**

- `look`, with refs, roles, field names, values, options and next steps;
- `choose`; `catalog`; `setup` (validated and read back);
- `open` through the pause menu inside a flight;
- a stdio MCP server with 17 tools.

**Evidence** (Windows, headless):

- Settings now read `"Window resolution" = "Automatic"`. `choose field="Window resolution" value="1920 × 1080"` and
  `field="Text size" value=125%` changed both values, and Revert restored them.
- `setup` with an unknown landscape changed nothing. The Vantage jet asked for `hand_launch` came back `airborne`,
  and `differs` reported it.
- The flight's close buttons read `× (Close · Flight data)` and so on.
- One MCP session, through a stdio client, went from launch to stop with no step needing a second call.
- Root cause of the intermittent bridge-test failures: another agent's concurrent checks on this machine shared
  the test's fixed port. The test now picks a free port.

Game bugs and opportunities found along the way, with owners: [game findings](game-findings-debug-tooling-2026-11-06.md).

## Next steps (not built)

- **Per-surface force vectors in 3D**: lift, drag and thrust per aerodynamic surface, with CG, wind and velocity, as
  in avian_fdm and Chaos. They need a read-only per-surface load output from the aircraft evaluators. Today the
  kernel exposes only total `last_loads`. Owner: physics, through the kernel contract, without vehicle branches.
- **GPU pass timing inside a viewport** (opaque, transparent, sky, post) needs Forward+/Mobile and RenderDoc or
  Xcode captures. The Compatibility renderer gives per-viewport totals only.
- **Ablating shader features** (for example cloud shadows on the ground) needs named toggles from their owners.
  `ablate` already accepts any node, and a feature switch could become a new `@flag`.
