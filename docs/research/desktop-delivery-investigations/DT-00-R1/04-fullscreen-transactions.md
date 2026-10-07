# DT-00-R1-04 — Fullscreen transition contract

2026-10-07 · **Investigation complete; recommendations only.** No app code or shared plan was changed.

## Question and method

How can the app request fullscreen, tell whether the transition is ready, respect explicit launch overrides, and recover if a
display trial is interrupted? I read the current entry route and project settings, the existing DT-00 display audit, Godot 4.7
API documentation, and the official Godot source tag `4.7.2-stable`. I also checked Apple's first-party Spaces and AppKit
lifecycle documentation. The pinned Linux executable is present, but I did not launch it or mutate `app/`; there is no native
Windows, macOS, or Wayland result in this report.

## Findings

1. `app/project.godot` declares a 1280×720 viewport and no display mode. `app/app_root.gd` first recognizes the standalone
   `--input-report[=path] [--t=seconds]` diagnostics route, then sends other app arguments after `--` straight to flight;
   only an empty app-argument list reaches Home. The diagnostic route does not create a flight or read/write preferences. The
   root currently connects Home and pause-menu Quit actions, but does not set a default window mode.
2. Godot exposes `DisplayServer.window_set_mode()` as a `void` request and `window_get_mode()` as a readback. The 4.7 public API
   has no fullscreen-transition-completed signal. A mode readback can confirm the engine's reported window mode; it does not
   prove that a compositor has finished presenting the transition. [DisplayServer
   4.7](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html).
3. Ordinary `WINDOW_MODE_FULLSCREEN` fills one display without changing its video mode. On macOS it uses a new desktop Space.
   Exclusive fullscreen is materially different: it can trigger a Windows black transition, bypass the X11 compositor, and is
   equivalent to ordinary fullscreen on Wayland. The project should keep ordinary fullscreen as its one-click mode.
   [DisplayServer window
   modes](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html#enum-displayserver-windowmode).
4. The macOS implementation explicitly brackets full-screen entry with `windowWillEnterFullScreen` and
   `windowDidEnterFullScreen` and tracks an internal transition flag. That asynchronous native lifecycle is not surfaced as a
   GDScript completion signal. Wait for mode/size readback and RenderingServer draw completion rather than saving when the
   setter returns; separately require native visible-frame evidence. Draw completion does not establish compositor presentation.
   [Pinned macOS window
   delegate](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/godot_window_delegate.mm#L1112-L1184).
5. Apple's Spaces guide says full-screen apps appear in their own Space and users switch Spaces through Mission Control,
   trackpad gestures, or Control+arrow. A transition may therefore look like an app focus loss. Godot also documents that
   `NOTIFICATION_APPLICATION_FOCUS_OUT` fires on desktop when focus leaves the app. [Apple
   Spaces](https://support.apple.com/guide/mac-help/work-in-multiple-spaces-mh14112/mac), [Godot MainLoop
   notifications](https://docs.godotengine.org/en/4.7/classes/class_mainloop.html).
6. The existing app treats focus loss as a safety pause: `simulation.gd` pauses, and `app_root.gd` defers opening the pause menu
   for an interactive flight. Do not let a transition's focus event instantly roll a pending display change back. Keep the
   flight paused and make the mode choice reachable after the transition; resumption remains an explicit pilot action. [Current
   entry](../../../../app/app_root.gd), [simulation](../../../../app/sim/simulation.gd).
7. Wayland delegates placement to the compositor; the pinned Godot Wayland driver does not support application-selected window
   position or screen. Do not make a saved monitor index or requested geometry a prerequisite for recovery. Let the compositor
   place the recovery window and verify that it is visible. [Godot Wayland driver, pinned
   source](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/linuxbsd/wayland/display_server_wayland.cpp#L1129-L1147),
   [Wayland/X11 guide](https://docs.godotengine.org/en/4.7/tutorials/platform/linux/wayland_x11.html).
8. Engine CLI switches are parsed before `--`; app-owned arguments are after it. Other than the recognized standalone
   `--input-report` route, the app sends post-separator arguments directly to flight. A recovery launch should use the engine's
   `--windowed --resolution 1280x720` switches before the separator and must not accidentally add a flight-app user argument.
   [Command-line
   tutorial](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html), [current
   route](../../../../app/app_root.gd).
9. `--windowed` must win over the interactive fullscreen default and a saved fullscreen preference. It is an explicit recovery
   action, not a new preference; launching with it must leave the player's confirmed setting unchanged. The same precedence
   table should specify an explicit `--fullscreen` request if that engine switch remains in the supported launch contract.
10. A later settings trial needs a durable distinction between the last confirmed display mode and the pending trial. Only Keep
   should confirm the new mode. A crash, force quit, or OS restart during the trial must choose a safe mode on the next launch.
   Keep that pending display transaction separate from general preference-write behavior; the shared preference durability
   investigation owns the storage design. See [DT-00-R1-10 — settings durability](10-settings-durability.md).
11. First-run fullscreen has no previous confirmed mode to restore. If the first transition fails its deadline/readback or the
   next launch finds an interrupted first trial, fall back to a visible windowed Home using safe geometry. Do not force a modal
   trial on first launch.
12. The current 15-second Keep/Revert proposal is a product timeout, not a Godot guarantee. It should use monotonic elapsed time
   and keep running while the simulation is paused; focus changes and macOS Space animation must not consume the user's entire
   decision window before controls are available.

## Proposed changes to DT steps

- **DT-03:** add a precedence table for default first-run mode, confirmed mode, `--windowed`, `--fullscreen`, `--input-report`,
  and flight automation after `--`. Assert that only interactive routes read or write display preferences.
- **DT-04:** define engine-side readiness as (a) mode readback matches the requested ordinary mode, (b) viewport geometry is
  within the current display's usable bounds where the platform supports that query, and (c) a draw-completion event occurs.
  `RenderingServer.frame_post_draw` means viewport updates finished; it does not prove compositor presentation. Require native
  visible-frame evidence separately. Use a bounded timeout and visible windowed fallback; the setter returning is not success.
- **DT-05:** treat the display trial as pending until Keep; an interrupted pending mode recovers to the last confirmed or safe
  windowed mode. A mode transition may pause the session, but may not resume it or discard the pending trial.

- Keep the
  recovery command documented per package as `--windowed --resolution 1280x720` before `--`; verify that it reaches Home and
  preserves the confirmed preference.

## Required proof and limits

Add a route test table for clean first launch, saved windowed/fullscreen, each engine override, standalone `--input-report`,
flight automation with `--`, malformed display state, and interrupted first/later trials. In native tests, record requested mode,
`window_get_mode()`, window/viewport size, time to draw completion, separate visible-frame evidence, focus notifications, and
visible fallback on Windows 11, macOS
(including the Space animation), Linux X11, and native Wayland where claimed. Repeat with a removed external monitor and a
windowed recovery launch. Headless tests can verify parsing and decision logic. They cannot prove that a compositor acknowledged
fullscreen, a macOS Space finished animating, or the pilot can see the fallback. No app launch or native transition was executed
here. Godot documents intended behavior; the pinned source corroborates implementation details, not end-user OS acceptance.

## Sources accessed 2026-10-07

- [Godot DisplayServer 4.7](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html)
- [Godot command-line tutorial 4.7](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html)
- [Godot MainLoop 4.7](https://docs.godotengine.org/en/4.7/classes/class_mainloop.html)
- [Godot Wayland/X11 guide 4.7](https://docs.godotengine.org/en/4.7/tutorials/platform/linux/wayland_x11.html)
- [Godot 4.7.2-stable macOS window
  delegate](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/godot_window_delegate.mm)
- [Godot 4.7.2-stable Wayland display
  server](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/linuxbsd/wayland/display_server_wayland.cpp)
- [Apple: Work in multiple Spaces on Mac](https://support.apple.com/guide/mac-help/work-in-multiple-spaces-mh14112/mac)
