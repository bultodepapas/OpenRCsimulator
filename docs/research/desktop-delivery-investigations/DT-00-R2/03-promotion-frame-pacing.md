# DT-00-R2-03 — ProMotion, V-Sync, frame caps, and what the logger can prove

2026-10-07 · Research round **DT-00-R2** · Supports DT-01, DT-05, DT-10, DT-10a, DT-11b, and DT-11c.

**Status:** pinned Godot source/API and project/frame-logger audit, with Apple display-spec review; no ProMotion Mac, external variable-refresh display, or presentation-latency test was run.

## Question

How should desktop acceptance distinguish Godot's process callback rate, 240 Hz simulation, V-Sync and an Apple ProMotion display that can refresh adaptively up to 120 Hz?

## What the app currently requests

- `app/project.godot` sets a 240 Hz physics tick and `common/max_physics_steps_per_frame=12`. Godot's scheduler can therefore
  integrate at most 12 ticks during one rendered frame: `240 / 12 = 20` rendered frames per second is the theoretical limit before
  the sim cannot catch up. This 20 Hz scheduling floor is not the 60 Hz process-loop target proposed in DT-10, nor an acceptable
  pilot target or measured rate. At steady 60 Hz the expected average is four physics ticks per rendered frame; at 120 Hz it is
  two.
- The project does not override `display/window/vsync/vsync_mode` or `application/run/max_fps`. Godot 4.7 defaults V-Sync to
  `Enabled` (`1`) and max FPS to `0` (no explicit cap). With V-Sync enabled, the monitor's refresh rate constrains the effective
  maximum rate. Pinned Godot 4.7.2 startup code confirms both defaults. [Godot 4.7
  ProjectSettings](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-display-window-vsync-vsync-mode),
  [max FPS
  behavior](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-application-run-max-fps),
  [Godot 4.7.2 V-Sync default](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp#L2655-L2662), and
  [0 max-FPS default](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp#L2120-L2126).
- Apple lists adaptive ProMotion up to 120 Hz on the 2021 16-inch M1 Pro MacBook Pro and also lists fixed refresh modes from 47.95
  through 60 Hz. ProMotion is a property of a particular panel/configuration; it cannot be inferred from “M1 or later.” Query and
  record the actual screen. [Apple M1 Pro 16-inch technical specifications](https://support.apple.com/en-us/111901).
- Godot's `DisplayServer.screen_get_refresh_rate()` reports the current rate for a screen and returns `-1` when unavailable. Its
  API docs describe the value under enabled V-Sync as the maximum FPS the project can effectively reach; it is useful host
  metadata, not a timestamp for every presented frame. [Godot 4.7
  DisplayServer](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html#class-displayserver-method-screen-get-refresh-rate).
- Godot's renderer comparison marks Adaptive and Mailbox V-Sync unsupported by Compatibility. Its V-Sync API says Adaptive behaves
  as Enabled under Compatibility. The pinned macOS display-server source also maps every OpenGL mode except `Disabled` to the same
  `set_use_vsync(true)` call. For the shipped Compatibility/OpenGL method, treat the selectable behavior as enabled or disabled;
  do not promise adaptive/mailbox behavior. [Godot renderer
  comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html#other-features), [Godot
  VSyncMode](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html#enum-displayserver-vsyncmode), [Godot 4.7.2
  macOS
  implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/display_server_macos.mm#L2631-L2648).

## Existing evidence boundary

`app/main.gd` samples one `Time.get_ticks_usec()` interval per `_process()` call, plus Godot's `delta` and engine performance
monitors. It records a boolean `vsync` (`mode != Disabled`) and the rendering method in `backend`. `app/render/frame_samples.gd`
summarizes monotonic process-loop intervals. This is useful for app cadence, stalls, and comparing simulation progress with wall
time; it is not a display present timestamp.

The callback is sampled before the rest of the app's `_process()` work. Neither it nor `RenderingServer.frame_post_draw` certifies
compositor submission, scanout, a panel's changing refresh, or photons. Godot documents `frame_post_draw` as completion of
RenderingServer viewport updates, not physical presentation. [Godot 4.7
RenderingServer](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html).

The existing DT-10 proposal of process-loop p95/p99 budgets at 60 Hz must retain that label. It does not establish a 120 Hz
experience: 120 Hz offers 8.33 ms per display interval, versus 16.67 ms at 60 Hz. Report each claimed operating mode against its
own refresh interval and disclose missed/repeated presentations with native display evidence. Those durations are arithmetic, not
performance measurements.

## Experiment and gate proposal

1. **DT-01:** identify actual internal and external display modes and refresh capabilities separately from Mac model/SoC. Record
    macOS build, panel/external display, resolution, reported refresh, power state, effective renderer/driver, package hash, and
    whether the run is native Apple Silicon. Include a 60 Hz path and a genuine adaptive/high-refresh path only where the host
    supports one.
2. **DT-10:** use the same packaged build, live flight route, aircraft, field, camera, and display dimensions. Capture repeated
    baseline runs with the current V-Sync default. If evaluating caps, compare explicit candidates (for example 60 and 120 where
    supported) and a V-Sync-disabled diagnostic separately; do not convert a diagnostic into a shipped preference without
    evidence.
3. Keep the existing frame logger as process-loop evidence. Record requested and effective V-Sync mode, explicit `Engine.max_fps`,
    `DisplayServer.screen_get_refresh_rate(SCREEN_OF_MAIN_WINDOW)`, the exact display mode, simulation ticks/wall seconds, and the
    runtime driver name. The current report's boolean V-Sync field loses the enum and the current backend field omits the driver.
4. To claim frames reached the panel at 60/120 Hz, add a native presentation measurement or high-speed camera/photodiode method
    and correlate it to the same run. To claim radio-to-visible latency, use the existing F6 method and label it as end-to-end
    evidence; app callback cadence alone cannot close that claim.
5. **DT-10a:** state the quantile method, interval count, per-run results, and measurement source. Keep process-loop p95/p99
    separate from GPU/render timing and external present cadence. Repeat paired blocks when the observed effect is within run
    variation.
6. **DT-11b/11c:** test minimized, paused, and live-flight caps separately. A low cap while the simulation is held can reduce idle
    load, but restoring focus must not create a physics catch-up jump or resume flight. Any active-flight cap or display setting
    must retain the 240 Hz simulation contract, real-time ratio, control response, and blinded attitude readability.

## Practical interpretation

The 20 Hz value is a theoretical scheduling floor implied by the configured step cap. At that floor every frame may need all
12 catch-up steps, with no scheduling margin. DT-10's proposed 60 Hz process-loop budget remains the operating target; the
earlier plan's 30 FPS wording was not the actual configured scheduler boundary. A lower active-flight profile needs separately
agreed timing and piloting acceptance; a 30 FPS cap cannot satisfy the proposed 60 Hz cadence budget.

An adaptive panel may vary how often it scans out frames, while Godot's Compatibility V-Sync path only exposes enabled/disabled
behavior. A report that logs `screen_get_refresh_rate()` once and samples `_process()` intervals cannot show the actual per-frame
panel cadence. Treat the reported screen rate as configuration metadata and verify visible pacing on a native Mac.

## Limits and sources

No Mac display, GPU, or USB-radio measurements were taken. The engine source confirms its V-Sync API mapping; it does not
establish how every macOS release and panel presents frames. Apple’s product specifications show supported modes but do not
predict the simulator's chosen or instantaneous refresh rate. Godot's performance numbers and simulator-specific budgets remain
local acceptance choices.

Primary sources: [Godot 4.7 DisplayServer](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html), [Godot 4.7.2
V-Sync default](https://github.com/godotengine/godot/blob/4.7.2-stable/main/main.cpp#L2655-L2662),
[ProjectSettings](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html), [renderer
comparison](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html), [jitter/stutter/input-lag
guide](https://docs.godotengine.org/en/4.7/tutorials/rendering/jitter_stutter.html),
[RenderingServer](https://docs.godotengine.org/en/4.7/classes/class_renderingserver.html), [Apple M1 Pro display
specs](https://support.apple.com/en-us/111901), and [Godot 4.7.2 macOS display-server
source](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/display_server_macos.mm). Repository audit:
[`app/project.godot`](../../../../app/project.godot), [`app/main.gd`](../../../../app/main.gd), and
[`app/render/frame_samples.gd`](../../../../app/render/frame_samples.gd). Recheck with `sed -n '14,32p' app/project.godot`, `sed -n '561,650p' app/main.gd`, and `sed -n '95,215p' app/render/frame_samples.gd`.
