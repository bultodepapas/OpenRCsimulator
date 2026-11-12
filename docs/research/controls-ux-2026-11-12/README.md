# Controls setup UX audit and references (2026-11-12)

Dated evidence for the [Controls setup UX plan](../../plans/controls-setup-ux.md). It records the current-source audit, the native screenshots taken and the external patterns that justify the plan. Current behavior lives in [First launch: controller settings](../../FIRST-LAUNCH.md#controller-settings-current-source); controller contracts and hardware gates live in [controller support](../../plans/controller-support.md).

## Method

- Source read of `app/ui/controller_setup.gd` (3,339 lines), `app/ui/radio_calibration_setup.gd`, `app/ui/calibration_card.gd`, `app/input/rc_calibration.gd`, `app/input/controller_actions.gd`, `app/input/keyboard.gd`, `app/input/multirotor_input.gd`, `app/ui/controller_prompts.gd` and the controller plans, at `f0ce04633`.
- Native Windows run through the debug bridge (`sim_launch`, 1920×1080, muted, no controller connected): Home → Controls, every tab. Screenshots stay outside git (`tmp/debug-bridge/mcp/`, ignored); they are not repository evidence.
- Independent read-only Good Enemy review of the same sources; web research for game and RC-simulator patterns. No physical controller was connected, so nothing here qualifies a device.

## Current state (what works)

The logic is stronger than its presentation. Keep it:

- Radio calibration auto-detects each channel by movement and measures both endpoints, inversion and throttle direction (`rc_calibration.gd`, steps rest → throttle → roll → pitch → yaw), and verifies throttle FULL→LOW before use (`radio_calibration_setup.gd:150-160`).
- V2 profiles with draft/Save/Cancel, connection generations, capture-release consumption, field-level conflict errors, Mode 1/Mode 2/trigger presets, scalar deadzone/expo/invert, typed AUX (axis, button, 2/3-position switch groups) and Learn axis.
- Kenney CC0 glyphs for Xbox/PlayStation/Nintendo/generic with automatic family detection (`controller_prompts.gd`), Jeti physical switch labels, verified radio menus and redacted diagnostic export.

## Findings (presentation and flow)

| # | Finding | Evidence |
| --- | --- | --- |
| A1 | Calibration is text-only. The pilot reads "Radio axes: +0.12 −0.98 …" and prompts such as "Hold the AILERON stick fully RIGHT"; no stick picture, no progress graphic, no per-axis motion feedback. | `radio_calibration_setup.gd:143`, `calibration_card.gd:74`, `rc_calibration.gd:12-23` |
| A2 | Axis mapping is a numeric SpinBox "Source axis 0–9" per channel. Pilots must know Godot axis indices; there is no "move the stick to assign" outside the radio wizard. | Flight axes tab capture; `controller_setup.gd:1945` |
| A3 | Live preview is four thin horizontal bars plus "Axis N". No two-dimensional gimbal view, no endpoint envelope, no deadzone/expo curve. | `controller_setup.gd:846-880` |
| A4 | The Controls modal tops out at 1160×780 px: about 60 % × 72 % of a 1080p screen, so Buttons shows four rows at a time and long help text is ellipsized ("Availability depends on the…", "Switch name (o"). | `controller_setup.gd:976`, `:1003-1006`; Extra channels capture |
| A5 | Calibration is hidden: it appears on Devices only after a radio is selected and a radio profile is chosen ("Choose radio profile" → "Calibrate selected radio"). No first-connection assistant. | `controller_setup.gd:466-488`, `:1136-1160` |
| A6 | Profile tab shows "Gamepad preset: Mode 2 · rate throttle" while the flight controller is Keyboard; Buttons shows gamepad bindings for a keyboard session. The selected device is not the visual subject of the screen. | Profile and Buttons captures |
| A7 | The keyboard flight layout is fixed (arrows/WASD, physical keys) and flight shortcuts are hard-coded; it can be viewed, not remapped. | `keyboard.gd:9-15`, `controls_reference.gd:11-30` |
| A8 | The FPV quad arms from a radio switch only if that switch is bound to the **Landing gear** AUX; the flight-mode switch is keyboard/gamepad-only. A pilot looking for "Arm" will not find it. | `multirotor_input.gd:23-28`, `:283-285` |
| A9 | Remap rows expose buttons named only "Clear" and "Remap" to assistive technology (the debug-bridge accessibility tree lists dozens of identical names). | `sim_look` on Buttons |
| A10 | Calibration exists twice with different presentations: a preflight modal and an in-flight card over the HUD. | `radio_calibration_setup.gd`, `calibration_card.gd` |
| A11 | Close and Esc emit `close_requested` with no dirty-draft check, discarding remaps and a just-finished calibration; Close and Cancel behave the same. | `controller_setup.gd:203-216` |
| A12 | Action rows are filtered only by category, not by the active vehicle's capabilities; about 38 rows show for every vehicle. | `controller_setup.gd:2487` |
| A13 | Save rejection joins raw identifiers ("Binding conflict: camera_cycle and trim_left") into a footer clipped to 1–3 lines; conflicts are rejected, not offered as a swap. Field-level messages are good. | `controller_setup.gd:3110-3123`, `:952-953`, `:985` |
| A14 | Terminology and prompts disagree: AILERON/ELEVATOR/RUDDER and "press Enter" in the wizard; Roll/Pitch/Yaw and a "Next" button in the UI. Flight-axes bars fill from the minimum, so a centred stick reads half full. | `rc_calibration.gd:13-22`, `controller_setup.gd:41`, `:867-873`, `radio_calibration_setup.gd:68` |
| A15 | With no device, setup shows a default gamepad Mode 2 profile; AUX axes and endpoints are SpinBoxes without "move to detect" (Learn axis exists for actions only). Uncertain, needs F1 evidence: a radio that SDL reports as a known gamepad cannot become a radio profile. | `controller_setup.gd:1602-1611`, `:686-694`, `app_root.gd:1837-1840` |

A15's last point and the Good Enemy's suspected stale `labeled_by` links after table/compact reflow (`accessible_labels.gd:40`) are unconfirmed. The Good Enemy also checked the contracts and seams that the plan lists under "Contracts the redesign must keep" and UI-15-UX-03.

## External patterns

Ranked by value for an RC simulator. Items marked *unverified* were not confirmed from a primary source during this review.

| Pattern | Who does it | Source |
| --- | --- | --- |
| Pick transmitter mode first; a stick diagram shows the requested position per step; Next per step; then sweep switches while a channel monitor shows movement | PX4 / QGroundControl radio setup | https://docs.px4.io/main/en/config/radio.html |
| Fixed USB-joystick order: CH1–8 → X, Y, Z, rX, rY, rZ, Dial, Slider; CH9–32 → buttons 1–24 (Classic). Advanced mode can tag channels as Sim Ail/Ele/Rud/Thr. Turn RF off for joystick use. | EdgeTX manual | https://manual.edgetx.org/color-radios/model-settings/model-setup/usb-joystick.md |
| Radio-side calibration: centre first, then extremes; verify in Channel Monitor | OpenTX 2.2 manual | https://doc.open-tx.org/manual-for-opentx-2-2/software-overview/radio_menus/radio_calibration |
| Search controls by pressing an input; per-axis sensitivity curve with live response dot; named presets | Microsoft Flight Simulator | https://flightsimulator.zendesk.com/hc/en-us/articles/360016018600 |
| Axis tune: deadzone, saturation, curvature, invert, "slider" for one-ended throttle | DCS World (community sources) | https://forum.dcs.world/topic/138265-question-on-axis-saturation/ |
| Calibration wizard under Options › Controls; radio presets | Liftoff, VelociDrone (third-party guides; steps *unverified*) | https://www.velocidrone.com/downloads/VelocidroneMobileManual.pdf |
| Remap any action, invert per stick, glyphs follow remaps, sensitivity range, single-press navigation of the remap UI | Xbox Accessibility Guidelines 107 | https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/107 |
| Presets plus custom mapping; separate mappings per mode (on foot / vehicle) | Game Accessibility Guidelines | https://gameaccessibilityguidelines.com/allow-controls-to-be-remapped-reconfigured/ |
| Per-device glyphs with a generic fallback | Steam Input best practices | https://partner.steamgames.com/doc/features/steam_controller/steam_input_gamepad_emulation_bestpractices |

Conflict swap dialogs, "hold to clear", controller pictures with leader lines and reset-per-category are common in console games (for example Forza, Gran Turismo 7 and the Xbox Accessories app); their exact behaviour was not verified from primary sources and is used here only as a generic convention.

## Free resources

| Resource | License | Use |
| --- | --- | --- |
| Kenney Input Prompts 1.5 (already vendored as a 46-SVG subset; [provenance](../../../app/assets/input_prompts/PROVENANCE.md)) | CC0 | Extend the subset from the same pinned archive: triggers, stick directions and keyboard keys. https://kenney.nl/assets/input-prompts |
| Controller Icons addon (rsubtil) | MIT | Reference only: OpenRC already resolves glyph families in `controller_prompts.gd`; adopting the addon would duplicate it. https://github.com/rsubtil/controller_icons |
| Xelu controller prompts | CC0 (trademark caution for PlayStation shapes) | Not needed while Kenney covers the families. https://opengameart.org/content/free-keyboard-and-controllers-prompts-pack |
| SDL GameControllerDB | zlib | Not part of this plan: hardware mapping stays with SDL/Godot ([controller plan risks](../../plans/controller-support.md#risks-dependencies-and-rollback)). https://github.com/mdqinc/SDL_GameControllerDB |

## Implementation (2026-11-12)

Delivered in source under the [plan's](../../plans/controls-setup-ux.md) step IDs; physical devices were not available, so nothing here qualifies a controller, radio or exported build.

| Step | Delivered | Main files |
| --- | --- | --- |
| UI-15-UX-01 | One calibration view for the preflight modal and the in-flight card: Mode 1/2 gimbals with target zones, six-stage progress, channel monitor with the moving axis and assigned functions, EdgeTX/OpenTX/JETI checklist, FULL→LOW verify panel. Wizard thresholds and transitions unchanged; prompts no longer name a key. | `app/ui/controls/{calibration_view,stick_gimbal_view,channel_bar}.gd`, `app/ui/radio_calibration_setup.gd`, `app/ui/calibration_card.gd`, `app/input/rc_calibration.gd` |
| UI-15-UX-02/02b/02c | Unique accessible names, focusable **?** popovers for clipped help, plain-language validation messages, unsaved-changes guard (Save / Discard / Keep editing; Cancel stays immediate; `close_without_prompt` for owners), vehicle-aware action and AUX rows with "show all". | `app/ui/controller_setup.gd`, `app/input/controller_actions.gd` (`action_applies`, `aux_applies`) |
| UI-15-UX-03/04/08 | Full-screen workspace at ≥1500×880 effective px (rail of device cards, live device picture with focus/hover highlight, pages); compact fallback below. Binding chips with conflict badges; gimbals and a large response curve for the focused channel; keyboard pages read-only. | `app/ui/controls/{controls_workspace,device_picture,device_card,binding_chip,response_curve}.gd` |
| UI-15-UX-05/06 | **Detect** per flight channel (largest deviation held 0.25 s, ambiguity/noise rejection, inversion), **Move the control** for AUX axes, in-panel capture overlay with countdown, Swap / Replace / Cancel on conflicts (validated whole-draft candidates; Replace never for Back/Pause), **Find control** (baseline travel ≥ 0.5 so a resting radio throttle cannot answer), Reset per category or all. Axis numbers moved under Advanced. | `app/ui/controller_setup.gd`, `app/ui/controls/capture_overlay.gd` |
| UI-15-UX-07 | Six-step Setup assistant, opened from **Set up this device…**; a one-time hint for devices needing setup, never auto-opened. Wired through a bridge to the draft paths; Cancel restores profile, calibration state, menu evidence and menu device. Reverse is relative to the preset (a Mode 2 throttle shows OFF) and locked for radios. Calibration requests for non-radios are refused, and `app_root` now always answers a calibration request. | `app/ui/controls/setup_assistant{,_host,_bridge}.gd`, `app/app_root.gd` |
| D6-UX-01 | AUX channels `arm` and `flight_mode` for the FPV quad; legacy gear-bound arming kept; a bound mode switch overrides M/RB; the toggle latch resets when the arm source changes. Controls receives multirotor capabilities when the quad is flying or selected. | `app/input/{controller_actions,controller_profile,rc_input,controller_diagnostics,multirotor_input}.gd`, `app/app_root.gd` |

All new user-visible strings were added to the eight catalogs (about 250 messages). The 1080p screenshots reviewed during the work were kept outside git.

### Verification

Headless suites through `tools/godot/run_checked.py` on Godot 4.8-beta2, Windows, sequentially, on the combined tree: new `test_setup_assistant_wiring` 36, `test_setup_assistant` 128, `test_controls_assign` 98, `test_controls_workspace` 106, `test_controls_components` 98, `test_controls_widgets` 37, `test_calibration_view` 71, `test_controls_setup_p0`, `test_multirotor_arm_mode_aux` 61; existing controller, radio, JETI, AUX, menu, pause and language suites (46 in total) pass, including `test_controller_responsive` 18,748/18,748, `test_controller_extended_actions` 1,451, `test_controller_capture_scroll` 1,344 and `test_mr_flight_log` (quad replay unchanged). Native 1080p review through the debug bridge covered the workspace, every Controls page, the capture overlay, the Swap question and the assistant's steps.

The final Good Enemy review found a blocking path (the assistant could wait forever when calibration could not start), Reverse voiding radio calibration, an incomplete Cancel restore, Find answering on a resting radio axis, a stale quad arm latch after unbinding an arm switch, focus loss after a cancelled Confirm OFF and unthrottled assistant polling; each is fixed with a regression check. Open, by decision: the capturing device's own Back is ignored while a Confirm OFF step waits (keyboard Escape and the overlay's Cancel work); the hidden legacy `ConfirmationDialog` behind Confirm OFF stays as a test seam; the radio Advanced view truncates the live-preview text at 1080p.
