# D6-ETX-01: EdgeTX airplane controls, implementation (phases 1–3)

Date: 2026-11-17. Scope: software for phases 1–3 of the [EdgeTX airplane controls plan](../../../plans/edgetx-airplane-controls.md). Synthetic devices and samples only: **no physical radio** was connected, so OS joystick mappings, rendered layout and pilot use remain open ([F1-ETX-01, F4-ETX-01](../../../plans/edgetx-airplane-controls.md#steps)). Audit and sources: [D6-ETX-00](../D6-ETX-00/README.md). Owner decisions for phases 2 and 3: [DECISIONS D6-ETX](../../../DECISIONS.md).

## What changed

| Step | Behaviour | Code |
| --- | --- | --- |
| D6-ETX-01 | A device with USB `1209:4F54` is a radio unless SDL reports a known gamepad or it claims JETI; family names still pick only the draft. | `app/input/edgetx_radio.gd` (`classifies_as_radio`), `controller_service.gd`, `rc_input.gd` |
| D6-ETX-02 | Preset `edgetx_airplane`: AETR on axes 0–3, restart on CH9 (button 0), no AUX until the switch check. `AIRPLANE_LAYOUT`: gear CH5 SD, flaps CH6 SA, optional rate switch CH7 SC (simulated rates only), restart CH9 SH, smoke CH10 SE. Controls starts a recognized EdgeTX radio from it when opened for an airplane, from `edgetx_fpv` for the quad. | `controller_profile.gd`, `edgetx_radio.gd`, `controller_setup.gd`, `controller_diagnostics.gd` |
| D6-ETX-03 | Optional `label` (1–24 chars) and `channel` (1–32) on any AUX binding; presentation only. | `smoke_aux.gd` (`valid_metadata`) |
| D6-ETX-04 | Optional `detents: "aircraft"` on the flaps AUX: equal bands of the 0…1 amount map to the aircraft's detents, which `main.gd` pushes when the aircraft loads. Absent field or detents: the linear amount as before. | `smoke_aux.gd` (`snap_to_detents`), `rc_input.gd` (`set_flap_detents`), `main.gd` |
| D6-ETX-05 | An AUX control may carry one quad channel and one airplane channel; same-vehicle sharing, AETR overlaps and action/AUX conflicts stay errors. | `controller_actions.gd` (`aux_channels_share_vehicle`) |
| D6-ETX-06 | A learned gear/flaps axis also becomes the quad's arm/flight-mode axis when that quad channel is unbound, with the quad's own endpoints; an existing quad binding is never moved. Either EdgeTX preset, flown as an airplane, gets the airplane switch check. | `edgetx_radio.gd` (`QUAD_SHARED_AUX`), `controller_setup.gd` (`_share_with_quad`), `setup_assistant.gd` |
| D6-ETX-07 | `rates_owner`: `transmitter` (radio default, rates native on EdgeTX) or `simulator`; a `rates` AUX channel (low normal, middle sport, high full); Controls picker *Dual rates and expo* with a checklist for each choice; assistant rate-switch row when simulated. | `controller_profile.gd`, `controller_actions.gd`, `rc_input.gd` (`rate_switch_profile`), `rc_calibration.gd`, `controller_setup.gd`, `setup_assistant*.gd` |
| D6-ETX-08 | The session admits simulated rates for radios, reads the rate switch beside flaps and gear (not paused, fresh OFF only), emits `rate_profile_changed` once per change; a bound switch refuses the toggle; guide and notes follow the owner. | `app/sim/flight_session.gd`, `main.gd`, `controls_guide.gd` |
| UI-15-ETX-01 | On an EdgeTX preset the Setup assistant's Switches step lists gear, flaps, smoke (and the rate switch when simulated) and restart with the layout hint; an unbound AUX learns an axis switch (OFF→ON→OFF) or a button pressed after OFF; a control on the layout's channel gets its channel and switch name; flaps get `detents`. Other presets keep their typed captures. | `setup_assistant.gd`, `controller_setup.gd` |
| UI-15-ETX-02 | Help states USB Joystick (Classic) and the layout (A10 fixed); Controls preset help; player paragraph in First launch. | `help_screen.gd`, `controller_setup.gd`, `docs/FIRST-LAUNCH.md` |
| HUD-ETX-01…03 | Control guide: "CH5 · SD" names, throttle-cut and flap-mix-owner rows for radios, rates row by owner, "Move SD to OFF to take control" while a bound switch awaits OFF; F1 toggles the guide in the airplane flight. | `controls_guide.gd`, `main.gd`, `controls_reference.gd` |

Also: `_end_capture_state()` no longer passes a null focus owner to `is_ancestor_of()` (an engine error when nothing had focus). New UI messages are in all eight catalogs.

**Solver identity.** D6-ETX-08 edits `app/sim/flight_session.gd`, so the flight-log solver identity changes and older logs report `solver_changed`. The installed native kernel receipts (Windows and Linux) were already stale before this change: 10 of their 135 mirrored sources, including `flight_session.gd`, had been edited by other tracks, so flights already used the GDScript reference. Native requalification stays with NK.

## Dual rates research

Question (owner, 2026-11-17): keep dual rates simulated in OpenRC, or off in OpenRC with EdgeTX doing them natively. Findings:

- **EdgeTX native rates** are stacked Input lines per stick, each with a switch condition, weight ("rates"), expo/curve, trim and flight-mode filter ([Inputs](https://manual.edgetx.org/color-radios/model-settings/inputs-mixes-and-outputs/inputs.md)); the Plane wizard writes SC 100/75/50 %, expo 30 ([D6-ETX-00](../D6-ETX-00/README.md#edgetxs-own-airplane-convention-plane-wizard)). Outputs (subtrim, limits, curves) follow ([Outputs](https://manual.edgetx.org/color-radios/model-settings/inputs-mixes-and-outputs/outputs.md)), and the USB joystick carries channel outputs, so a "linear" radio for simulated rates needs Inputs weight 100 %, expo 0, no switch or flight-mode lines, and Outputs ±100 %.
- **A switch on a spare channel** is one mix line with the switch as source (CH7 = SC, weight 100). The −100/0/+100 values of a 3-position switch are not stated in the manual; OpenRC does not rely on them, because the switch check measures OFF and ON and bands the middle.
- **Simulators.** SeligSIM / FS One applies per-aircraft rates, expo and mixes itself and asks for a plain radio, with a separate "use your own programming" path ([manual](https://www.seligsim.com/manual/getting_started.html)); the RealFlight InterLink layout puts Dual Rates on a channel the simulator reads ([ArduPilot](https://ardupilot.org/dev/docs/interlink-emulation.html)). RealFlight, Aerofly RC 10, Phoenix, PicaSim, ClearView and Heli-X rate behaviour with generic radios could not be verified.
- **Detection.** No source describes a simulator detecting radio-side rates. Possible warnings (not implemented): a full-stick endpoint well below 100 %, a half-stick reading far from 50 %, an endpoint that changes when the rate switch flips.

Decision: offer both; default `transmitter` for every radio, because EdgeTX pilots usually already have D/R and expo and silent double expo is the worst, least detectable failure. `simulator` is an explicit choice with its checklist.

## Verification

Godot 4.8-beta2 (`.tools/Godot_v4.8-beta2_win64_console.exe`), headless, Windows, run directly (the checked runner refuses this checkout's linked `app/.godot`):

- Phase 1: `test_edgetx_airplane.gd` and `test_edgetx_switch_check.gd`; 65 existing controller, JETI, AUX, assistant, Controls, overlay, Help, reference and quad-preset suites, then the 20 that touch the final Controls, guide and Help text: all exit 0 with no FAIL or engine error. The first pass caught two regressions, both fixed: the longer guide footer overlapped other overlays at 1280×720 (`test_overlay_manager`), and Help had dropped the "gear AUX / Toggle landing gear" sentence (`test_ui_help`).
- Phases 2–3: `test_edgetx_rates.gd` 34 checks, `test_edgetx_airplane.gd` 55, `test_edgetx_switch_check.gd` 16, all 0 failed. `test_multirotor_arm_mode_aux.gd` (62 checks) updated deliberately: arm + landing gear on one button is now valid, same-vehicle conflicts still rejected.
- Final broad regression on the finished tree: 89 suites (EdgeTX, controller, JETI, AUX, assistant, Controls, overlays, Help, flaps, rates, retractable gear, flight log, replay, golden, end-to-end radio/input, quad rates/presets) exit 0 with no FAIL or engine error.
- A Good Enemy review of the phase 2–3 diff found one defect and three risks, all fixed: an inert rate switch (radio-owned rates) showed "waiting for OFF"; a re-learned gear/flaps switch left the derived quad binding on the old axis (it now follows; a pilot's own quad binding never moves); recalibration dropped `rates_owner` and `flap_elevator_mix_owner` (now kept); the rates note keyed on profile kind instead of the owner.
- AI companions: `main.gd` is a declared behavior source, so its hash in `app/data/ai/companions/behavior-manifest.json` and the manifest hash in the Ugly Stik companion profile were renewed after review (the changes are input routing, F1, notes and HUD state, not companion admission or launch). `tools/companions/rebind.py` (report mode, workspace on U:) replayed the 9 qualification tapes on the accepted and current solver: all identical. The solver pin itself is re-pinned with `rebind.py --accept` **after the commit**, as the tool requires; until then `test_companions_profiles` and `test_companions_behavior_manifest` report the solver mismatch.
- `main.gd` parses (`--check-only`).

## Limits

- Channel names are given only when the learned control sits where a raw Classic joystick would carry that channel (axis N = CH N+1, button N = CH N+9); the switch letter is the layout's suggestion, not read from the radio.
- Open: restart-action metadata, F1 in the quad scene and a `controls_help` action, the warnings-bar sync entry, the flight-start banner, a recorded radio flight with a mid-flight rate switch replayed exactly, native requalification, and 1080p/1440p/4K/720p captures (C: had 2.8 GB free, below the test-queue snapshot need).
