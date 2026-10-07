# DT-00-R1-05 — DPI, viewport scale, and pilot-view readability

2026-10-07 · **Investigation complete; recommendations only.** No app code or shared plan was changed.

## Question and method

How should Windows scaling, Retina, mixed-DPI monitors, and fullscreen aspect ratios affect UI size and the visible RC airplane
without applying scale twice or changing the pilot-view contract? I inspected `app/project.godot`, the current pilot camera and
its math test, UI-09 research, the Godot 4.7 Window/DisplayServer/Camera3D references, and the official 4.7.2 API source tag
where relevant. No render capture or GUI run was performed. The current working tree includes another developer's dirty physics
files; the project settings, camera, and UI plan cited here were read without changes.

## Findings

1. `app/project.godot` sets a 1280×720 viewport. It does not set `display/window/stretch/mode`, `content_scale_size`, or a
   runtime scale. Godot's root `Window.content_scale_size` defaults to the project viewport dimensions; Godot documents this as
   a virtual content size, distinct from the actual window size in physical pixels. [Window
   4.7](https://docs.godotengine.org/en/4.7/classes/class_window.html#class-window-property-content-scale-size).
2. Godot exposes separate concepts: `content_scale_size` is the virtual base, `content_scale_factor` is an additional
   user-adjustable scale, and `content_scale_mode` determines whether/how CanvasItems are scaled. A factor can be added on top
   of the automatic size-derived scale. Avoid computing `content_scale_factor = user_scale × screen_scale × size_scale`; that
   can count the same DPI or resolution change twice. [Window scale
   properties](https://docs.godotengine.org/en/4.7/classes/class_window.html#class-window-property-content-scale-factor),
   [multiple resolutions](https://docs.godotengine.org/en/4.7/tutorials/rendering/multiple_resolutions.html).
3. The multiple-resolution guide says Godot projects are DPI-aware by default and advises keeping `allow_hidpi` enabled when
   possible; disabling it can break fullscreen on Windows. This setting affects Windows and macOS, and is ignored on Linux.
   `screen_get_scale()` does not mean the same data is available everywhere. [Godot multiple resolutions:
   hiDPI](https://docs.godotengine.org/en/4.7/tutorials/rendering/multiple_resolutions.html#hidpi-support).
4. In Godot 4.7, `DisplayServer.screen_get_scale()` reports 2.0 on Retina and 1.0 otherwise on macOS. On native Wayland it is
   accurate for `SCREEN_OF_MAIN_WINDOW`; asking by screen index rounds a fractional value such as 1.25 upward to 2.0. On Windows
   and X11 it returns 1.0, so it cannot drive a Windows scale choice by itself. [DisplayServer
   4.7](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html#class-displayserver-method-screen-get-scale).
5. Godot's `screen_get_dpi()` is implemented on Windows, but the API documentation warns that it can be inaccurate for
   fractional display scaling on macOS. Do not infer that `DPI / 96` is a universal scale or compare DPI values across platforms
   as if they were physical pixel density. A preference plus captured native evidence is safer than a platform guess.
   [DisplayServer DPI
   reference](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html#class-displayserver-method-screen-get-dpi).
6. The public Godot 4.7 `DisplayServer` API exposes a screen count, primary-screen index, current-window screen, position, pixel
   size, usable rectangle, scale, and refresh rate. It exposes no screen name or stable monitor identifier. Treat a stored
   integer screen index as a transient hint; after unplug/reorder, choose a currently valid display or let the window manager
   place the window. The tuple of position/size/scale can aid diagnostics, but it is not a stable ID. [DisplayServer
   methods](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html).
7. On Wayland, Godot cannot reliably set a window's position or choose a target display. This means a monitor selector and
   remembered window coordinates cannot be acceptance requirements on native Wayland. The compositor decides where the window
   appears; native tests should check that the app remains visible and recoverable. [Pinned Wayland
   driver](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/linuxbsd/wayland/display_server_wayland.cpp#L1129-L1147),
   [Wayland/X11 guide](https://docs.godotengine.org/en/4.7/tutorials/platform/linux/wayland_x11.html).
8. The pilot camera sets vertical FOV to 50°. Godot's `Camera3D.KEEP_HEIGHT` preserves vertical FOV while wider aspect ratios
   add horizontal view. This is a good starting contract for 16:9, 16:10, and ultrawide: the airplane should not be stretched to
   fill the screen. [Camera3D 4.7](https://docs.godotengine.org/en/4.7/classes/class_camera3d.html#enum-camera3d-keepaspect).
9. OpenRC's auto-zoom computes FOV from wing span, camera distance, viewport height, and a 30-pixel target;
   `test_pilot_aids.gd` checks at least 30 pixels from 20 to 150 m at a 720-pixel viewport, while a fixed 50° view projects
   about 11.8 pixels at 100 m. `auto_fov()` clamps between the base 50° FOV and minimum 6° FOV, so the target is not exact in
   every case. These are raster-pixel contracts, not a human readability result. [Current
   camera](../../../../app/render/pilot_camera.gd), [spec](../../../../app/spec.gd), [math
   test](../../../../app/tests/test_pilot_aids.gd).
10. The configured target is 30 pixels: that is 4.17% of a 720-pixel viewport or 1.39% of a 2160-pixel viewport if achieved.
    Those are target ratios, not guaranteed projected sizes. For the current 1.524 m span at 100 m and 2160-pixel height, the
    50° base FOV projects about 35.3 face-on pixels; the target calculation asks for a wider FOV, so the base-FOV clamp leaves
    the airplane larger than 30 pixels. At very long distances, the 6° minimum-FOV clamp can leave it below target. This
    camera-model arithmetic is not a human readability result or a claim about every 4K image. A fullscreen migration therefore
    needs projected-size and pilot readability checks at native viewport heights, not only a 1280×720 screenshot.
11. The current airplane readability track already separates projected-size calculations from blinded attitude recognition and
   keeps native GPU cost pending. Desktop work must reuse those cases and results; do not change aircraft span, FOV, auto-zoom
   target, or graphics quality under the label of DPI support. A different camera contract belongs with the visual/model owners
   and requires its own human evidence. [Ugly Stik readability plan](../../../../docs/UGLY-STIK-PLAN.md), [visual
   plan](../../../../docs/UGLY-STIK-VISUAL-PLAN.md).
12. UI-09a already proposes a 100/150/200% user scale using `Window.content_scale_factor`, reflow, and a minimum captured text
   height. Desktop delivery should accept that UI contract across DPI and fullscreen combinations. Scaling CanvasItems must not
   silently change the 3D camera projection, simulation scale, RC input, or 240 Hz timing.

## Proposed changes to DT steps

- **DT-05:** split display-pixel size, virtual content size, user UI scale, OS DPI mode, and 3D render scale into separate
  logged fields. Record window/viewport dimensions in native captures; never report `screen_get_scale()` as a portable DPI
  value.
- **DT-05:** add mixed-monitor move/unplug cases: Windows 100→150% and 150→100%, macOS Retina↔external display, Wayland
  fractional scale using `SCREEN_OF_MAIN_WINDOW`, and X11. Require layout/readability recovery; do not require persisted monitor
  identity on any platform.
- **DT-10/11c:** compare fullscreen costs at matched physical resolutions and preserve the existing flight readability suite. If
  render scaling is offered, keep it independent from UI scale and require paired performance and blinded orientation evidence
  before retaining it.

- Keep UI sizing changes with UI-09a and 3D camera/readability changes with the visual/model owners.
  Desktop acceptance owns only the package-level evidence.

## Required proof and limits

For each native test, record OS build, display backend, monitor model, OS scale setting, Godot-reported screen scale/DPI,
physical window size, root viewport size, `content_scale_size`, `content_scale_factor`, rendered text height, and aircraft
projected span. Capture 1280×720, 1080p, 1440p, 4K, 16:10, and ultrawide. Repeat the current 20/50/100 m level/banked attitude
cases on the target GPU and ask pilots the existing orientation questions; automated pixel counts alone do not pass readability.
The target-ratio arithmetic and 35.3-pixel 4K example follow the current projection formula and FOV clamps; they do not establish
the airplane's achieved pixels in every flight view or how a pilot sees it on a particular screen. Godot API docs do not establish
stable monitor identity or prove mixed-DPI behavior on the owner's machines. No native capture, layout check, or pilot test was
run.

## Sources accessed 2026-10-07

- [Godot Window 4.7](https://docs.godotengine.org/en/4.7/classes/class_window.html)
- [Godot DisplayServer 4.7](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html)
- [Godot multiple resolutions and hiDPI 4.7](https://docs.godotengine.org/en/4.7/tutorials/rendering/multiple_resolutions.html)
- [Godot Camera3D 4.7](https://docs.godotengine.org/en/4.7/classes/class_camera3d.html)
- [Godot 4.7.2-stable Wayland display
  server](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/linuxbsd/wayland/display_server_wayland.cpp)
- [UI-09a scale/readability contract](../../../MENU-PLAN.md)
