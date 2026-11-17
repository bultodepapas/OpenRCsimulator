# D6-ETX-01: EdgeTX airplane controls, phase 1 implementation

Date: 2026-11-17. Scope: software for phase 1 of the [EdgeTX airplane controls plan](../../../plans/edgetx-airplane-controls.md) (D6-ETX-01…04, UI-15-ETX-01/02, HUD-ETX-01…03). Synthetic devices and samples only: **no physical radio** was connected, so OS joystick mappings, rendered layout and pilot use remain open ([F1-ETX-01, F4-ETX-01](../../../plans/edgetx-airplane-controls.md#steps)). Audit and sources: [D6-ETX-00](../D6-ETX-00/README.md).

## What changed

| Step | Behaviour | Code |
| --- | --- | --- |
| D6-ETX-01 | A device with USB `1209:4F54` is a radio unless SDL reports a known gamepad or it claims JETI; family names still pick only the draft. | `app/input/edgetx_radio.gd` (`classifies_as_radio`), `controller_service.gd`, `rc_input.gd` |
| D6-ETX-02 | Preset `edgetx_airplane`: AETR on axes 0–3, restart on CH9 (button 0), no AUX until the switch check. `AIRPLANE_LAYOUT`: gear CH5 SD, flaps CH6 SA, restart CH9 SH, smoke CH10 SE. Controls starts a recognized EdgeTX radio from it when opened for an airplane, from `edgetx_fpv` for the quad. | `controller_profile.gd`, `edgetx_radio.gd`, `controller_setup.gd`, `controller_diagnostics.gd` |
| D6-ETX-03 | Optional `label` (1–24 chars) and `channel` (1–32) on any AUX binding; presentation only. | `smoke_aux.gd` (`valid_metadata`) |
| D6-ETX-04 | Optional `detents: "aircraft"` on the flaps AUX: equal bands of the 0…1 amount map to the aircraft's detents, which `main.gd` pushes when the aircraft loads. Absent field or detents: the linear amount as before. | `smoke_aux.gd` (`snap_to_detents`), `rc_input.gd` (`set_flap_detents`), `main.gd` |
| UI-15-ETX-01 | On that preset the Setup assistant's Switches step lists gear, flaps, smoke and restart with the layout hint; an unbound AUX learns an axis switch (OFF→ON→OFF) or a button pressed after OFF; a control on the layout's channel gets its channel and switch name; flaps get `detents`. Other presets keep their typed captures. | `setup_assistant.gd`, `controller_setup.gd` |
| UI-15-ETX-02 | Help states USB Joystick (Classic) and the layout (A10 fixed); Controls preset help; player paragraph in First launch. | `help_screen.gd`, `controller_setup.gd`, `docs/FIRST-LAUNCH.md` |
| HUD-ETX-01…03 | Control guide: "CH5 · SD" names, throttle-cut and flap-mix-owner rows for radios, "Move SD to OFF to take control" while a bound switch awaits OFF; F1 toggles the guide in the airplane flight. | `controls_guide.gd`, `main.gd`, `controls_reference.gd` |

Also: `_end_capture_state()` no longer passes a null focus owner to `is_ancestor_of()` (an engine error when nothing had focus). New UI messages are in all eight catalogs.

No file under `app/physics/`, `app/sim/` or `app/input/commands.gd` changed, so the flight-log solver identity is unchanged.

## Verification

Godot 4.8-beta2 (`.tools/Godot_v4.8-beta2_win64_console.exe`), headless, Windows, run directly (the checked runner refuses this checkout's linked `app/.godot`):

- `test_edgetx_airplane.gd`: 53 checks, 0 failed.
- `test_edgetx_switch_check.gd`: 12 checks, 0 failed, no engine errors.
- 65 existing controller, JETI, AUX, assistant, Controls, overlay, Help, reference and quad-preset suites, then the 20 that touch the final `controller_setup.gd`, guide and Help text: all exit 0 with no FAIL or engine error. The first pass caught two regressions, both fixed: the longer guide footer overlapped other overlays at 1280×720 (`test_overlay_manager`), and Help had dropped the "gear AUX / Toggle landing gear" sentence (`test_ui_help`).
- `main.gd` parses (`--check-only`).

## Limits

- Channel names are given only when the learned control sits where a raw Classic joystick would carry that channel (axis N = CH N+1, button N = CH N+9); the switch letter is the layout's suggestion, not read from the radio.
- Not done in phase 1: restart-action metadata, F1 in the quad scene and a `controls_help` action, the warnings-bar sync entry, the flight-start banner, 1080p/1440p/4K/720p captures (C: had 2.8 GB free, below the test-queue snapshot need).
