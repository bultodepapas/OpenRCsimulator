# UI-28-R5 — loading presentation and the staged first Home

2026-11-12. Local-source result on the owner's Windows 11 host at 1920×1080, Compatibility (GLES3) renderer, official Godot 4.8-beta2. This is not an exported-release or target-hardware qualification. Decision: [loading bars count completed stages](../../../DECISIONS.md#loading-bars-count-completed-stages-motion-only-shows-activity).

## Problem

The owner reported that loading screens look frozen and do not show that work is happening, especially the startup intro.

- **Intro.** On commit, `startup.gd` called `intro.seek()`, which sets `playing = false` and stops the atmosphere's dust. `AppRoot._ready()` then built the whole Home synchronously. A scratch probe (`HomeScene.new()` cold) measured 4.9 s, then a 0.5–1.8 s first draw. Of that, `Landscapes.build` took 2.9 s cold (1.75 s warm), `AirplaneBuilder.build` for the procedural Stik 1.5 s cold (0.6 s warm) and the rest of `World.build` 0.23 s. Loading `app_root.tscn` on the existing worker thread took 6.5–9.7 s and did not freeze the intro.
- **Flight loading.** A debug-bridge Fly from Home took 7.0 s in 58 checkpoints. Apart from the threaded scene load (3.3 s, frames still drawn), the longest chunks were `Near grass` 418 ms, `Preparing contacts` 411 ms and `Preparing sound` 369 ms. The screen did animate, but only through a flat panel with a 4 px indeterminate bar and rapidly changing stage names.

## Delivered behavior

- `app/ui/loading_bar.gd` is shared by both surfaces. Its value only rises, and owners set it from completed top-level stages. `nudge()` moves it part of the way toward the next stage for each real sub-stage event, without reaching it. A sweep and a pulsing head show activity; the fill eases toward the value. Reduced motion draws the value with no sweep or easing.
- The intro uses `settle()` instead of `seek()` on commit. The logo stays resolved while the clock, dust, two new parallax mote layers and a repeating logo sweep keep running. The live-only decoration is gated by shader uniforms: `seek()` stills, reduced motion and the trailer end card (`tools/trailer/capture_brand.gd`) render as before. The 180 px footer runner is replaced by a centered bar with the current stage under it. The footer keeps the accessible status and Skip.
- When the startup sets `AppRoot.startup_progress`, AppRoot builds the first Home in stages: `HomeScene(staged = true)`, `build_world_staged()` through `World.build_staged`/`Landscapes.build_staged`, then `finish_construction()`. It yields a drawn frame after about 12 ms of work. If the selected aircraft has an imported GLB, it is loaded with `load_threaded_request` alongside the world, always drained, and retained in the existing two-resource broker. Forced frames separate the aircraft build, the 3D view's first draw and the Home menu install. Quit during the build cancels at the next checkpoint, confirms the renderer guard and quits. On this route the debug bridge is created once Home exists, so "the bridge answers" still means a usable route. Other Home rebuilds, tests, headless and argument routes keep synchronous `show_home()`.
- The flight surface keeps its opaque backdrop, now drawn with the brand atmosphere shader, and the shared bar. Its stage table follows the UI-34c order; an optional stage that a route skips is passed over.

## Measurements

Startup probe (scratch `SceneTree` script running `res://ui/startup.tscn` at 1920×1080 with a fresh profile; no screenshots during the run):

| | Before | After |
| --- | --- | --- |
| Longest frozen intro frame | ≈5.5 s (whole Home build) | 1.95 s (procedural Stik build, its stage shown first) |
| Second block | 0.5–1.8 s first draw | 1.75 s first 3D draw (own frame, before the menu) |
| World build | one block | ≈40 stages, most frames under 100 ms (`Preparing field vegetation` 514 ms) |
| Ready to fade | n/a | 16.9 s after launch, of which 9.7 s was the threaded shell load on that run |

The two remaining blocks are indivisible at this seam. The Stik is procedural geometry, and moving its builder to a worker needs the purity study required by the [§12 policy](../../../plans/menu-redesign.md#12-home-to-flight-loading-ui-34c-and-dt-11a). The first draw is Compatibility shader and texture preparation (UI-34c-R6 owns warmup).

A flight launched after the change took 4.4 s (scene not prefetched), with no errors in the bridge log. Native screenshots of both surfaces were inspected and are kept outside Git.

## Verification

Checked runner, headless, Godot 4.8-beta2:

- New `test_startup_loading.gd`: 44 checks. Covers the bar contract, intro `settle()`/`seek()`, the bar inside 720p/1080p/4K above the footer, trailer hiding, startup and flight stage mapping, and a staged-Home node tree identical to the synchronous Home. It also checks that `World.build_staged` reports the stage names both surfaces expect, and that a cancelled staged build never builds the aircraft.
- Existing suites pass: `test_brand_startup` (182 checks), `test_flight_loading_surface`, `test_flight_loading` (56), `test_ui_home`, `test_home_presentation`, `test_ui_home_preview_cache` (118), `test_ui_change_aircraft`, `test_loading_start_label` (45), `test_ui_home_span` and `test_home_launch_summary` (109).
- Headless tests do not reach the staged route. The rendered route was exercised with the probe above and with debug-bridge launches, where launch returned at Home and Fly loaded normally.

## Independent review

A read-only Good Enemy review found four defects in the first candidate. All are fixed, and the probe was rerun afterwards: Home ready at 12.4 s, longest block 1.6 s (aircraft), then 1.4 s for the first 3D draw.

- **Renderer guard (P1, RD/MetalFX hosts).** The guard confirmer clears the pending marker after 120 frames and 3 s. Under the staged build those frames were 2D intro frames, so a crash on the first Home 3D draw would not have triggered the Compatibility fallback. `RendererGuard.confirm_hold` now restarts the confirmers' window until Home's first 3D frame is drawn. Covered by `test_startup_loading` and the unchanged `test_renderer_guard` (40 checks).
- **Script error during the build.** A second close request now quits. An aborted coroutine (`null` result) or a non-cancel failure falls back to the synchronous `show_home()`.
- **Field-error route.** It now also starts the update check, as before.

Not changed: the 12 ms yield budget was measured on a 120 Hz display only. At 60 Hz VSync each yield can cost up to one refresh, so time to Home there is unmeasured.

Open: exported-package check, Forward+ comparison, macOS RD launch with a pending guard marker, and owner visual review on the target display.

## UI-28-R5b — returning to Home and changing landscape (2026-11-12)

**Problem.** End flight, End ground vehicle and a landscape change in Home each rebuilt Home synchronously. The last frame stayed frozen and the menu ignored input. A windowed scratch probe timed `HomeScene.new()` for the club field at 3.7 s cold and 1.8 s warm, and for green paradise at 0.5 s.

**Behavior.**

- **Shared surface.** On rendered routes these three paths push the flight loading surface in Home mode (`configure_home`). It has the title "Preparing home…", the landscape as summary and no Cancel, because the activity has already ended. Construction follows the same `World.build_staged` stages as the startup through the shared `_build_home_staged`, or `_rebuild_home_scene_staged` for a landscape change.
- **Landscape change.** The change is accepted at once, as the existing busy-preparation branch already did. The surface is see-through: the previous view stays visible, dimmed to 80 % atmosphere, under a solid card that fades in over 0.18 s. A short rebuild therefore reads as a transition, not a full-screen flash. The synchronous rebuild also kept the previous world alive until the replacement existed, so peak memory is unchanged. Focus returns to the landscape selector. If construction fails, the previous landscape is selected again through the immediate refresh path.
- **Requests during a build.** Rebuild requests made during a build (time of day, sky, a queued landscape) are recorded and applied once the build ends. A vehicle or livery changed meanwhile is requested on the new world. Flights, ground vehicles, the blimp and the quad cannot start while Home is being built. A landscape change deferred by Home's flight preparation is staged too.
- **Stage text.** Both surfaces keep the top-level stage on a stable line and show sub-stages ("Near grass", "Building field scenery") on a dimmer line beneath. The text no longer flickers through chunk names several times a second.
- **Skip.** The intro hides Skip once Home is being prepared, because nothing is left to skip. Skip inputs are still held.
- **Headless and tooling.** Headless routes stay synchronous. Rendered routes yield through `_flight_loading_draw()`, so tests that enable the rendered path in headless mode do not wait for draws that never come. `start_flight` refuses while Home is being built. The debug bridge's `home` and `setup` commands wait for the staged Home instead of failing after 120 frames.

**Measurements** (debug-bridge session at 1920×1080 on the reference host):

| Transition | Before | After |
| --- | --- | --- |
| End flight → Home | one synchronous block (≈1.8 s warm build, plus menu and first draw) | 2.5 s with the surface animated; longest frame 716 ms. Repeated three times: 0 orphans, node count unchanged |
| Landscape → club field | 1.8–3.7 s frozen Home | Surface animated; longest frame 447 ms |
| Landscape → green paradise | 0.5 s frozen Home | Surface for about 0.8 s; longest frame 432 ms |
| Landscape → club field (see-through) | as above | 2.6 s with the dimmed view and solid card; longest frame 555 ms; focus back on the selector |

**Independent review.** A second read-only review found these defects; all are fixed.

- **P1.** A time-of-day change landing during a landscape build ran the synchronous rebuild and left the opaque surface up for good. Rebuild requests now wait for the build.
- **P2.** Lost keyboard and controller focus after a landscape change.
- **P2.** Selection changes dropped during a build.
- **P3.** A quit during the return route skipped draining Home's preparation workers.
- **P3.** A failed landscape build left the selection on the new landscape.
- **P3.** Vehicle routes could start mid-build.
- **UX.** A full-screen flash for a 0.5 s rebuild, answered with the see-through mode.

**Verification.**

- New `test_home_staged_routes.gd` (12 checks) drives the rendered routes headless:
  - a landscape change with a time-of-day request in flight;
  - focus restoration;
  - a return from an activity with its debrief after Home exists;
  - a close request during a build.
- `test_loading_start_label.gd` now waits for the staged landscape before flying, as a player would.
