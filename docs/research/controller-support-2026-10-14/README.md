# Controller support research

2026-10-14. Source snapshot: `22b3e4825ec97289b76666ca9e942eaa7a8f703d` plus the existing working tree. Scope: Xbox, PlayStation DualSense and other controllers, with Windows prioritized by the owner. The [implementation plan](../../plans/controller-support.md) owns proposed work and acceptance; this report owns the dated findings and sources.

## Current application

The graph located the input seams, but some indexed function ranges were stale. Findings below were checked against current source. They are source inspection findings, not physical controller results.

| Area | Observed implementation | Consequence |
| --- | --- | --- |
| Engine | [Engine pin](../../../app/get-godot.sh), official 4.7.2-stable; native API probe reports `ed1daf0bf` | Retain this baseline; an engine change needs separate qualification. |
| Gamepad flight | [RcInput](../../../app/input/rc_input.gd), `GAMEPAD_PROFILE`, `poll`, `_shaped`: known non-radio devices use right stick roll/pitch, left stick yaw/rate throttle; deadzone 0.08, expo 0.3, throttle rate 0.5/s | Basic gamepad flight already exists; device-specific compatibility has not been established by these defaults. |
| Radio behavior | `connect_device` gives saved calibration precedence; otherwise name heuristics override `is_joy_known`. Unknown devices fall back to the radio profile | An unknown gamepad may acquire an unsuitable absolute-throttle mapping; explicit device purpose is needed. |
| Calibration defect | [FlightSession](../../../app/sim/flight_session.gd) `start_calibration` accepts any connected device. [RcCalibration](../../../app/input/rc_calibration.gd) initializes `kind = "radio"` and validates only radio profiles; completion saves it | Running K calibration on a gamepad can replace its rate-throttle/deadzone/expo semantics with radio semantics, including on later launches. This is a confirmed source path, not a hardware reproduction. |
| Rates and expo | `rates_active` / `flown_commands` apply aircraft normal travel to gamepads, but pass `with_expo = false`; [Commands](../../../app/input/commands.gd) honors that flag | No double expo was found. Preserve the [D6e](../radio-input/D6e/README.md) boundary and trims after rates. |
| Selection | `FlightSession._ready` adopts the first enumerated device; `_on_joy_connection_changed` adopts a connection if none is active | No explicit device choice, no selection of an already connected alternative, and new connection during keyboard flight can change the source without a selection hold. |
| Disconnect | `_failsafe` idles throttle, neutralizes commands and pauses; reconnect does not itself resume | Keep this working protection. Gamepad auto-arming in `poll` still needs its own fresh-neutral policy. |
| Menus | [UiInput](../../../app/ui/ui_input.gd) removes all joypad events from `ui_*`; startup invokes it. [Main](../../../app/main.gd) flight shortcuts use keyboard events | Radio isolation is deliberate. Replace it with selected-gamepad routing, preserving radio isolation. |
| Home instructions | [Home](../../../app/ui/home.gd) `_update_control` tells non-radio controllers to lower throttle to arm | Does not describe the gamepad's spring-centered rate throttle or current auto-arming. |
| Buttons | `RcInput.on_button` forwards to smoke AUX only | Pause, camera and other flight actions need a semantic command layer. |
| Helicopter | [Helicopter session](../../../app/sim/helicopter_flight_session.gd) shares RcInput and calibration; connection pauses and preserves gamepad collective for explicit resume | Share device infrastructure, while keeping collective and throttle/engine policy distinct. The calibration defect also needs coverage here. |
| Ground vehicle | [Ground sampler](../../../app/input/ground_vehicle_input.gd) validates values and requires neutral before driving; [ground scene](../../../app/vehicles/ground/ground_scene.gd) reads left X and two triggers | Useful existing behavior to preserve; it is a separate input path, not fixed-wing trigger support. |
| Diagnostics | [F1](../radio-input/F1/README.md) records connection sessions and axes, not button transitions; values are after Godot mapping and intervals are callback spacing | Extend F1 rather than creating a second reporter; do not label these values raw HID or physical latency. |
| Tests | `test_rc_input.gd` uses synthetic known gamepads; `test_e2e_radio.gd` covers radio disconnect/arming; `test_ui_input.gd` asserts joypad UI isolation | Existing tests prove contracts, not Xbox/DualSense USB/Bluetooth compatibility. |

## Current upstream findings

1. **Use the existing desktop backend.** Godot uses SDL 3 for Windows, Linux and macOS controller input from 4.5. Specialized HOTAS/pedals/wheels have less coverage. The pinned engine vendors SDL 3.2.28. Keep SDL device mapping separate from OpenRC command assignment. [Godot controller guide](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html), [pinned third-party manifest](https://github.com/godotengine/godot/blob/4.7.2-stable/thirdparty/README.md#sdl).

2. **Identity is evidence, not a permanent device key.** Godot exposes connection IDs, names, GUID and extra metadata; connection order can change. The pinned SDL driver supplies VID/PID as decimal strings and passes SDL's GUID through. This conflicts with the API documentation's blanket `__XINPUT_DEVICE__` statement. Treat IDs and metadata defensively; never use GUID/name alone as a unique physical instance. [Input reference](https://docs.godotengine.org/en/4.7/classes/class_input.html), [pinned SDL driver](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/sdl/joypad_sdl.cpp). The earlier [identity investigation](../menu-investigations/12-identidad-joypads-sdl3.md) explains firmware/backend and identical-radio ambiguity.

3. **There are two mapping layers.** The pinned driver opens recognized devices as SDL gamepads and suppresses their raw joystick events; other devices retain joystick events. Godot's connection path bypasses its mapping lookup when the driver handles mapping, while `add_joy_mapping` updates Godot's own database. Therefore, an application remap should assign the events actually received to flight actions. An SDL hardware correction needs a separate backend-specific experiment; do not promise that a runtime Godot mapping fixes every SDL-recognized pad. [SDL driver](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/sdl/joypad_sdl.cpp), [Input implementation](https://github.com/godotengine/godot/blob/4.7.2-stable/core/input/input.cpp). Reuse the maintained [SDL controller database](https://github.com/mdqinc/SDL_GameControllerDB) and upstream tools for missing hardware mappings, with pinned provenance.

4. **Analog semantics matter.** Godot's `get_vector` applies circular deadzone and limits vector length. That suits paired movement but is not automatically the right contract for independent aircraft control channels. Global Input polling is also unaffected by GUI event consumption. The implementation plan therefore specifies scalar channel shaping and explicit input-context gates. [Input reference](https://docs.godotengine.org/en/4.7/classes/class_input.html).

5. **USB and Bluetooth need separate DualSense rows.** Sony documents Windows support over both connections. Its advanced haptic-feedback support requires compatible games and USB on PC; adaptive triggers also require game support. This is different from standard rumble and from reading analog triggers. [Sony DualSense PC support](https://www.playstation.com/en-us/support/hardware/pair-dualsense-controller-bluetooth/).

6. **Windows modes can change the available channels.** Microsoft's XInput/DirectInput comparison documents combined triggers and missing vibration through the legacy DirectInput path for XUSB devices. Test both triggers held simultaneously and record the exposed mode; do not infer independent triggers from a product name. This does not mean every device observed through Godot uses that legacy path. [Microsoft comparison](https://learn.microsoft.com/en-us/windows/win32/xinput/xinput-and-directinput).

7. **Godot 4.7.2 already exposes useful optional features.** Native reflection confirms rumble capability/start/stop, light capability/setter, and joypad motion-sensor APIs. Motion APIs are marked experimental in the reference. They are optional capability probes, not a reason to install a second input backend. No generic adaptive-trigger API was identified in the reviewed public Input interface. SDL has a low-level controller-effect API, which is not itself a Godot feature. [Controller features](https://docs.godotengine.org/en/4.7/tutorials/inputs/controller_features.html), [pinned Input interface](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/Input.xml), [SDL effect API](https://wiki.libsdl.org/SDL3/SDL_SendGamepadEffect).

8. **Steam emulation changes the identity presented to the game.** Valve provides APIs to translate emulated Xbox actions into physical controller glyphs. A standalone build should allow a manual glyph choice and avoid claiming that an emulated XInput device proves Xbox hardware. Direct SDL and Steam-emulated qualification remain separate. [Steam Input emulation guidance](https://partner.steamgames.com/doc/features/steam_controller/steam_input_gamepad_emulation_bestpractices).

9. **There is a relevant Windows engine risk.** [Godot #121539](https://github.com/godotengine/godot/issues/121539) reports a GameSir T4n disconnect hang, closed through [SDL update #120373](https://github.com/godotengine/godot/pull/120373) for milestone 4.8. It does not establish that 4.7.2 contains the fix, or that Xbox/DualSense are affected. Reproduce on the affected hardware before choosing an engine upgrade/backport. [Initial joystick throttle issue #105676](https://github.com/godotengine/godot/issues/105676) remains open in the checked page; a zero polling result is insufficient fresh arming evidence.

10. **Reuse free assets and native UI.** Kenney's Input Prompts includes Xbox, PlayStation, Nintendo and generic glyphs under CC0. Record archive version/hash/license when imported. Godot's focus-neighbor and initial-focus mechanisms support menu navigation; they still need application-specific routing and testing. [Kenney Input Prompts](https://kenney.nl/assets/input-prompts), [Godot focus guide](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_navigation.html).

## Reproducible engine check

[probe_api.gd](probe_api.gd) reads API presence, enum limits and default UI bindings without loading application code or changing preferences. [api-windows.log](api-windows.log) records a successful native Windows headless run, exit 0, no script errors:

```powershell
$ControllerGodot = '.\.tools\Godot_v4.7.2-stable_win64_console.exe'
& $ControllerGodot --headless --quit-after 3 --script docs/research/controller-support-2026-10-14/probe_api.gd
```

The output confirms six standardized axes, ten supported axis slots and 128 button slots. Default `ui_accept` and `ui_cancel` have no joypad bindings in this run; directional actions do. `ignore_joypad_on_unfocused_application` defaults to false. The application subsequently removes all joypad UI bindings.

The older investigation-12 probe was also attempted. Its API section ran, but its repository-root load of RcInput now fails because RcInput preloads `res://input/smoke_aux.gd`; that legacy invocation does not use the application resource root. It was stopped and is not counted as a passing app check. The standalone probe above avoids that dependency.

No physical Xbox, DualSense, generic controller, transport, firmware or end-to-end latency was validated during this review. Runtime behavior remains unchanged. Hardware rows in the implementation plan start as untested.
