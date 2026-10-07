# 05 — macOS Spaces, Retina transitions, and keyboard delivery

2026-10-07 · DT-00-R2 · **Godot source and API review; no native Mac interaction test.**

## Question and scope

What Mac-specific behavior can affect fullscreen confirmation, notched-display layout, Retina transitions, and keyboard controls? The general
fullscreen transaction, cross-platform DPI model, focus pause, and close handling remain in
[DT-00-R1-04](../DT-00-R1/04-fullscreen-transactions.md), [DT-00-R1-05](../DT-00-R1/05-dpi-camera-readability.md), and
[DT-00-R1-06](../DT-00-R1/06-native-close-suspend-audio.md). This report narrows those contracts to AppKit, Spaces, and Mac keyboard conventions.

## Findings

1. Godot 4.7.2 implements ordinary macOS fullscreen with AppKit's `toggleFullScreen:`. The request is asynchronous: Godot sets its internal
   `fullscreen` value immediately, while AppKit's later `windowDidEnterFullScreen` callback ends the transition and updates the window. An immediate
   `window_get_mode()` readback can therefore report the requested mode before the new Space is usable. [Pinned display
   server](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/display_server_macos.mm#L2248-L2293), [window
   delegate](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/godot_window_delegate.mm#L86-L120).
2. Apple system fullscreen creates a separate Space. Users can also enter/exit through the green title-bar control or Control-Command-F, and move
   between Spaces with Mission Control or Control-arrow gestures. Test these routes against the app's own window-mode state and focus-pause
   behavior. [Apple fullscreen guidance](https://developer.apple.com/design/human-interface-guidelines/going-full-screen), [Mac
   Spaces](https://support.apple.com/guide/mac-help/work-in-multiple-spaces-mh14112/mac).
3. Apple's HIG recommends system fullscreen and letting people choose when to enter it. The desktop plan explicitly requests fullscreen on first
   interactive launch; keep that as a product decision and test a quick, visible exit/recovery path rather than treating it as Apple's default
   recommendation. [Going full screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen), [desktop
   plan](../../../DESKTOP-DELIVERY-PLAN.md#product-decisions-proposed-for-implementation).
4. Godot's public `get_display_safe_area()` is implemented for Android/iOS; other platforms fall back to `screen_get_usable_rect()`.
   `get_display_cutouts()` reports Android cutouts and returns empty elsewhere, so neither API exposes a Mac camera-housing shape. [DisplayServer
   4.7](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html#class-displayserver-method-get-display-safe-area),
   [cutouts](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html#class-displayserver-method-get-display-cutouts).
5. Apple says system fullscreen automatically places window contents inside `NSScreen.safeAreaInsets`; a custom fullscreen implementation must honor
   safe insets and camera-housing areas itself. `NSScreen.visibleFrame` excludes the housing but does not expose the side areas beside it as a
   layout API. Keep critical HUD/menu controls away from the top corners and verify the exported app on a notched Mac. [NSScreen safe
   area](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets), [visible
   frame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe).
6. In Godot 4.7.2, `windowDidChangeBackingProperties` observes an AppKit backing-scale change, updates the layer and window size, emits
   `WINDOW_EVENT_DPI_CHANGE`, and forces a resize. `Window.dpi_changed` is available on macOS. Test the actual rendered layout and controls after
   moving between built-in Retina and external displays; a signal alone does not prove correct pixels or UI bounds. [Pinned
   delegate](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/godot_window_delegate.mm#L223-L250), [Window
   signal](https://docs.godotengine.org/en/4.7/classes/class_window.html#signals).
7. The same source deliberately keeps `screen_get_max_scale()` cached across display reconfiguration and uses it to scale `NSScreen.visibleFrame`
   into Godot's usable rectangle. `screen_get_scale()` reads each current screen's `backingScaleFactor`. Record both values and test Retina-to-1x
   movement and hot-unplug; do not assume screen topology refreshes every cached size. This is a source observation, not a demonstrated defect.
   [Pinned display server](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/display_server_macos.mm#L1490-L1531).
8. OpenRC's keyboard adapter reads physical arrow keys for roll/pitch and physical A/D, W/S for rudder/throttle. Its flight shortcuts in `main.gd`
   also match physical key codes and do not filter Command/Control/Option modifiers. Verify system chords cannot trigger an unintended restart,
   trace, calibration, or control input. [Keyboard adapter](../../../../app/input/keyboard.gd), [flight
   shortcuts](../../../../app/main.gd#L317-L350).
9. Apple keyboard function keys default to system features; Fn/Globe or a Keyboard setting sends standard F-key events. F3 may invoke Mission
   Control, while OpenRC uses F3 for performance data and F5 for aircraft-data reload. A fullscreen escape path or essential control must not depend
   on pressing F3/F5/F11 without Fn. [Apple function-key guidance](https://support.apple.com/en-za/guide/mac-help/mchlp2596/mac), [OpenRC
   controls](../../../../app/ui/controls_reference.gd).
10. The app's Control-arrow interaction deserves a specific check: macOS uses Control-arrow for Space navigation, while the simulator polls arrow
   state as flight input. Confirm that Space switching pauses the simulation and that the pilot cannot resume until the app is active and explicitly
   continued. No modifier chord should accidentally change aircraft state while the OS handles a Space gesture.
11. Apple HIG reserves Command-modified shortcuts for familiar app/system actions. Add a visible in-app display control and preserve the system
   fullscreen shortcut; treat any simulator keyboard mapping that receives Command-modified letters as a candidate for modifier filtering. Keep
   keyboard mapping changes coordinated with the input/menu owners. [Apple keyboard
   guidance](https://developer.apple.com/design/human-interface-guidelines/keyboards).

## DT mapping

- **DT-04:** on an M1, test first launch, enter/exit by the app, green button, and Control-Command-F; confirm the separate Space transition
  completes before calling fullscreen usable. Keep a windowed recovery route that does not require a function key.
- **DT-05 / UI-09a:** capture logical window size, backing/render pixel dimensions, current screen scale, usable rectangle, UI bounds, and aircraft
  readability on built-in Retina, external 1x/Retina, and after display disconnect. Reuse DT-00-R1-05's scale contract.
- **DT-05 / UI-09b / input owner:** test F-row behavior with and without Fn, Mission Control, Control-arrow Space navigation, and Command-modified
  app keys. Preserve native system shortcuts and ensure focus return does not resume flight.
- **DT-05a:** reuse DT-00-R1-06 for native close/Command-Q and trace-save behavior; this report adds no second close policy.

## Native acceptance — UNRUN

These commands and interaction cases were not run in this Linux audit. Use the exact exported app on a physical M1 and record macOS build, keyboard,
displays, app hash, and process architecture.

```sh
system_profiler SPHardwareDataType SPDisplaysDataType
APP="/Applications/OpenRC Simulator.app"
open -a "$APP" --args --windowed --resolution 1280x720
```

Record `Engine.get_architecture_name()` from the running app; Godot reports the binary architecture, not the host CPU. On an M1, `arm64` means the
app selected its native slice and `x86_64` means it runs translated. Apple also documents checking `sysctl.proc_translated` via `sysctlbyname`
inside the target process; an external `sysctl` command reports its own process state, not the launched app. [Godot
Engine](https://docs.godotengine.org/en/4.7/classes/class_engine.html#class-engine-method-get-architecture-name), [Apple
Rosetta](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment).

Manually exercise fullscreen routes and Mission Control; move the window between Retina and external screens, disconnect the active display, and
inspect HUD reachability after each transition. Test F3/F5 both with and without Fn, Control-arrow during flight, and Command-modified letters.
Capture a native screen recording and the app's layout/scale log; headless tests cannot establish these behaviors.

## Sources and limits

Godot API documentation describes the supported public methods; implementation details above are pinned to `4.7.2-stable`. Source inspection
predicts how the engine requests AppKit transitions and reacts to a backing-scale notification; it does not prove the user's macOS version, monitor
arrangement, native UI layout, key delivery, or focus order. The first-run fullscreen proposal remains explicit in the desktop plan even though it
differs from Apple's user-choice guidance.

Sources accessed 2026-10-07: Godot 4.7 [DisplayServer](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html),
[Window](https://docs.godotengine.org/en/4.7/classes/class_window.html), [Engine
architecture](https://docs.godotengine.org/en/4.7/classes/class_engine.html#class-engine-method-get-architecture-name), Godot 4.7.2-stable [macOS
display server](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/display_server_macos.mm) and [window
delegate](https://github.com/godotengine/godot/blob/4.7.2-stable/platform/macos/godot_window_delegate.mm), Apple [Going full
screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen),
[Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards), [NSScreen
safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets) and
[visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe), Apple Support [Function
keys](https://support.apple.com/en-za/guide/mac-help/mchlp2596/mac), and
[Spaces](https://support.apple.com/guide/mac-help/work-in-multiple-spaces-mh14112/mac).
