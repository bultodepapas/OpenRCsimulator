# DT-00-R1-06 — Native close, suspend, focus, and audio lifecycle

2026-10-07 · **Investigation complete; recommendations only.** No app code or shared plan was changed.

## Question and method

Do native quit requests reach the app's trace-save guard? What can desktop focus/sleep notifications guarantee, and what should
happen to simulation state and generated engine audio when the OS or an output device changes? I inspected `app/app_root.gd`,
`app/main.gd`, `app/sim/trace.gd`, `app/sim/recorder.gd`, the simulation pause path, and Godot 4.7 documentation. I checked the
Godot 4.7.2 macOS close/termination implementation, Apple AppKit lifecycle docs, and the GDScript-facing AudioServer API.
Existing menu/audio research was read for prior measurements. No app process, native close, sleep/wake, or real audio device was
exercised.

## Findings

1. `SceneTree.auto_accept_quit` defaults to `true`. Godot's desktop quit guide says window-manager close requests are accepted
   by default; to own the quit sequence the app must set `auto_accept_quit` false and handle `NOTIFICATION_WM_CLOSE_REQUEST`.
   `Window.close_requested` is another explicit signal route for native Window nodes. [Godot quit requests 4.7](https://docs.godotengine.org/en/4.7/tutorials/inputs/handling_quit_requests.html), [SceneTree 4.7](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html), [Window 4.7](https://docs.godotengine.org/en/4.7/classes/class_window.html#signals).
2. Current `app_root.gd` handles only `NOTIFICATION_APPLICATION_FOCUS_OUT`. Home Quit calls `get_tree().quit()` directly;
   pause-menu Quit calls `quit_app()`. The root has no close-request handler and does not disable auto-accept. Thus a title-bar
   close or Alt+F4 currently bypasses `quit_app()`.
3. On macOS, the pinned Godot window delegate translates a window close into `WINDOW_EVENT_CLOSE_REQUEST`. The application
   delegate also turns AppKit's `applicationShouldTerminate` request (including normal Quit menu/Command-Q handling) into a
   main-window close request and cancels the direct AppKit termination. This gives the app a common Godot close hook, but
   current OpenRC does not use it. [Godot 4.7.2-stable window
   delegate](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/godot_window_delegate.mm#L1070-L1079),
   [application
   delegate](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/godot_application_delegate.mm#L1384-L1401).
4. The existing `quit_app()` is the only app-root route that tries to save an active recorder before quitting.
   `_trace_saved_or_discarded()` stops the recorder, writes its buffered `Trace` rows, and returns false with a message on
   failure. That message is shown only if a pause menu exists. An OS close bypasses this entire guard and loses an in-memory
   active trace.
5. Even if native close were naively redirected to `quit_app()`, a failed trace save while flying without a pause menu would
   have no visible error surface. Since the recorder is already stopped after a failed save, the next quit call passes through
   and exits without retry. Route close through a visible app-owned decision state and make save retry/discard explicit; do not
   hide a failure behind a native close request. [Current root](../../../../app/app_root.gd),
   [recorder](../../../../app/sim/recorder.gd), [trace writer](../../../../app/sim/trace.gd).
6. `Trace` stores rows in memory and writes CSV only from `save()`; `Recorder.stop()` is the current persistence boundary. A
   hard process kill, power loss, or OS termination that skips this call cannot be described as a saved trace. The scope is to
   handle normal close requests and report the limits of abrupt termination, not to add periodic journaling here.
7. `Simulation._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)` pauses the physics state. `app_root` then defers
   `open_pause()` for interactive flight, and that menu adds the session hold `"menu"`. On return, there is no automatic resume;
   the pilot must choose Continue. A focus transition should therefore preserve a paused session and must never interpret
   `FOCUS_IN` as permission to fly. [Simulation](../../../../app/sim/simulation.gd),
   [session](../../../../app/sim/flight_session.gd), [entry](../../../../app/app_root.gd).
8. The simulation stores pause as one boolean; the session's `holds` dictionary tracks menu holds, while focus is delivered
   separately as a simulation notification. Keep fullscreen/focus events idempotent and avoid clearing another pause cause when
   the display transition finishes. Native focus order and transient focus changes still require per-platform evidence. [Godot
   MainLoop notifications](https://docs.godotengine.org/en/4.7/classes/class_mainloop.html).
9. Godot documents `NOTIFICATION_APPLICATION_PAUSED` and `NOTIFICATION_APPLICATION_RESUMED` as Android/iOS-only. Desktop has
   application focus notifications, but the public MainLoop docs do not promise a separate suspend/resume callback for Windows,
   macOS, or Linux sleep. Do not make trace persistence or safe flight state depend on a desktop suspend notification arriving.
   [Godot MainLoop 4.7](https://docs.godotengine.org/en/4.7/classes/class_mainloop.html#constants).
10. macOS exposes AppKit active/resign-active and termination callbacks to native applications. Godot maps app deactivation to
   its application focus notification, but a system sleep/wake test is still necessary to learn whether the app receives a
   usable focus sequence on the supported Mac/build. Apple says an app delegate can cancel or defer normal termination; that
   does not protect against sudden termination. [Apple
   NSApplicationDelegate](https://developer.apple.com/documentation/appkit/nsapplicationdelegate), [Apple
   applicationShouldTerminate](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate%28_%3A%29).
11. OpenRC's engine sound is a generated `AudioStreamPlayer3D` created with the flight scene. `main.gd` pauses its stream when
   `sim.paused` and updates it during active `_process`; the app currently has a test that checks silence on pause using Godot's
   Dummy driver. That proves engine mixing behavior in the test, not audible output recovery after unplugging a physical device.
   [Engine sound](../../../../app/render/engine_sound.gd), [flight renderer](../../../../app/main.gd), [existing audio
   investigation](../../menu-investigations/19-audio-ajustes-pausa.md).
12. Godot's public AudioServer exposes `output_device`, output-device lists, and a setter. Its documented signals are bus-layout
   and bus-rename events; there is no GDScript `output_device_changed`/hot-plug signal in the 4.7 API. `"Default"` follows the
   system-wide default output by contract, while device enumeration/set behavior alone does not prove a running driver recovers
   after a USB headset is removed. [AudioServer 4.7](https://docs.godotengine.org/en/4.7/classes/class_audioserver.html).

## Proposed changes to DT steps

- **DT-05:** add one application-owned native close path for title-bar close, Alt+F4, and macOS Command-Q. For Home, close
  through the normal Quit action. During flight, pause and present the trace outcome before exit; prove the save-error path is
  visible and a user can retry or explicitly discard.
- **DT-05:** add normal close tests with no trace, a healthy active trace, a failing trace destination, repeated close, and
  close from both Home and flight. Assert that the CSV exists and is complete before process exit, or that an explicit discard
  was selected.
- **DT-05/DT-12:** add OS sleep/wake while Home, in flight, paused, and recording. On wake, flight stays paused until pilot
  action; inspect physics tick continuity, inputs, displayed pause state, trace row count, sound, and exit logs. Document that
  forced power loss cannot be guaranteed to flush an in-memory trace.
- **DT-12:** add physical output tests for headset disconnect/reconnect and system default-device switching while Home, flying,
  paused, and returning from sleep. Keep the sound device on OS `Default` unless a native test demonstrates a real product need
  for a selectable device.

- Keep simulation pause policy with its session owner and sound mixing changes with the UI/audio
  owner. DT owns package-level proof; no native extension or second lifecycle controller is justified by this source review.

## Required proof and limits

For each claimed platform, record OS/build, package hash, backend, route, trace path/result, exit code, and logs. On macOS
include both window close and Command-Q. On Windows include title-bar close and Alt+F4. On Linux test X11 and native Wayland
separately. Trigger a real system sleep/wake and physical output removal; do not substitute a synthetic focus notification or
Dummy audio driver for those cases. The source/API audit proves a current normal-close gap and defines the public Godot
notification behavior. It does not prove platform delivery of close/focus events in every compositor, nor does it prove USB
audio hot-plug recovery. A forced kill/power loss can bypass app code. No native lifecycle or acoustic test ran here.

## Sources accessed 2026-10-07

- [Godot handling quit requests 4.7](https://docs.godotengine.org/en/4.7/tutorials/inputs/handling_quit_requests.html)
- [Godot SceneTree 4.7](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html)
- [Godot Window 4.7](https://docs.godotengine.org/en/4.7/classes/class_window.html)
- [Godot MainLoop 4.7](https://docs.godotengine.org/en/4.7/classes/class_mainloop.html)
- [Godot AudioServer 4.7](https://docs.godotengine.org/en/4.7/classes/class_audioserver.html)
- [Godot 4.7.2-stable macOS window
  delegate](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/godot_window_delegate.mm)
- [Godot 4.7.2-stable macOS application
  delegate](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/godot_application_delegate.mm)
- [Apple NSApplicationDelegate](https://developer.apple.com/documentation/appkit/nsapplicationdelegate)
- [Apple
  applicationShouldTerminate](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminate%28_%3A%29)
