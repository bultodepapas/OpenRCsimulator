# D6-ETX-00: EdgeTX airplane controls — audit and sources

Date: 2026-11-17. Scope: what OpenRC does today when an EdgeTX/OpenTX radio is connected over USB, what EdgeTX actually sends, and which conventions a preconfigured airplane mapping (sticks, retractable gear, flaps, smoke, dual rates) and in-flight help should follow. Source reading and code inspection only: **no radio was connected** (no `1209:4F54` device present on the host), so every OS-specific axis/button claim below is inference until [F1-ETX-01](../../../plans/edgetx-airplane-controls.md#steps) records hardware. Plan: [EdgeTX airplane controls](../../../plans/edgetx-airplane-controls.md).

## 1. EdgeTX facts (primary sources)

Firmware: EdgeTX `main` at `54df93de52a87f18bd77273ac0f31438a03d82d4` (2026-11-17), `radio/src/usb_joystick.cpp`. SD card: `EdgeTX/edgetx-sdcard` `master` at `841fd18b9055e04249ab8c648721e10f30bb4061`, `sdcard/color/TEMPLATES/1.Wizard/lib/fixed-wing.lua`. Both GPLv2: cite, do not copy code.

| # | Finding | Evidence | Confidence |
| --- | --- | --- | --- |
| E1 | Classic mode is a HID **Game Pad** (usage 0x05) with 8 axes in the order X, Y, Z, Rx, Ry, Rz, **Slider (CH7), Dial (CH8)**, 0…2047 (11 bit), and 24 buttons. Its report layout is frozen at the 2.10.6 form because strict HID parsers (PS4 + Liftoff) reject changes. | `usb_joystick.cpp` L85-115 | High (source) |
| E2 | Classic axis value = `limit(0, channelOutput + 1024, 2047)`: the sim receives the **channel outputs after the radio's inputs, rates, expo, mixes, trims and limits**, not raw sticks. | L617; [radio input investigation](../../roadmap-investigations/06-radio-input-servos-latency.md) | High |
| E3 | Classic buttons 1–24 = CH9–CH32, pressed when the channel output is **> 0**. A 3-position switch on one button channel therefore reads only "on/off". | L70-72, L603-609 | High |
| E4 | Advanced mode, button "Normal" with *n* positions: one button per position, exactly one set (`setBtnBits(btn, 1 << pos, n)`). This matches OpenRC's existing maintained-switch group (2–3 buttons, one active; [D6-JETI-03](../D6-JETI-01/README.md)). "SW-Emu" toggles one button on each upward transition; "Companion" sends 3 positions as 2 buttons (centre = none). | L700-765 | High (source); hardware unverified |
| E5 | Linux: the kernel maps Game Pad buttons to `BTN_GAMEPAD…`, and SDL then auto-maps Classic as a **gamepad**: X/Y → axes 0/1, Rx/Ry → 2/3, Z/Rz → triggers 4/5 (0…1); Slider/Dial (CH7/CH8) have no output. Advanced with interface "Joystick" (0x04) avoids this. | [Joypad identity investigation §6](../../menu-investigations/12-identidad-joypads-sdl3.md) | Medium (code reading) |
| E6 | Windows: EdgeTX's developer page states DirectInput reverses CH7/CH8 (sliders), and its Advanced page says the pre-2.9 Classic table differed (both Slider). SDL3's DirectInput backend numbers sliders by data offset, which predicts the reversal. Which SDL3 Windows backend claims an EdgeTX radio is unverified. | [Mapping for game developers](https://manual.edgetx.org/edgetx-how-to/joystick-mapping-information-for-game-developers); [Advanced joystick](https://manual.edgetx.org/edgetx-how-to/configure-advanced-joystick-with-edgetx); SDL `SDL_dinputjoystick.c` | Medium-low |
| E7 | Every EdgeTX radio in joystick mode reports USB `1209:4F54`, manufacturer "OpenTX", product `<Maker> <Model> Joystick`; Godot returns VID/PID as decimal strings. | [Identity investigation §2, §5](../../menu-investigations/12-identidad-joypads-sdl3.md) | High (code) |
| E8 | Godot 4.8 reads joypads through SDL3; raw joysticks keep SDL's axis index (`JoyAxis` max 10, buttons 128), so Classic's 8 axes fit. | Godot `drivers/sdl/joypad_sdl.cpp`, `core/input/input_enums.h` | High |

### EdgeTX's own airplane convention (Plane wizard)

`fixed-wing.lua` (lines are for the commit above):

| Function | Wizard default | Where it acts | Lines |
| --- | --- | --- | --- |
| Motor safety | **SF** down → Special Function "override motor channel −100" | Radio | 77-83, 849-865 |
| Dual rates | **SC**: three input lines per axis, weights 100 / 75 / 50 %, expo 30 on aileron and elevator | Radio (Inputs) | 676-678, 766-783 |
| Flaps | source **SA**, output CH8 (CH9 for a second servo); off by default | Radio mixer | 315-327, 812-819 |
| Retracts | source **SD**, output CH7; off by default | Radio mixer | 581-589, 841-847 |
| Smoke | none | — | — |

The wizard puts gear and flaps on CH7/CH8, the two channels E5/E6 make fragile for a simulator. Its switch letters are useful defaults; its channel numbers are not.

### Simulator precedent

The ArduPilot InterLink-emulation page (an OpenTX layout that mimics RealFlight's InterLink controller) assigns CH1–4 AETR, **CH5 dual rates (SC), CH6 flaps (SD), CH7 smoke (SA)**, CH8 mode (SB), CH9–11 SH/SF/SG ([page](https://ardupilot.org/dev/docs/interlink-emulation.html), read 2026-11-17). In that convention the simulator, not the radio, applies dual rates. Other simulators (Aerofly RC 10, PicaSim, ClearView, Phoenix, Liftoff, VelociDrone): no primary evidence was found for EdgeTX auto-detection, presets, rate ownership or on-screen help; treat any claim about them as unverified.

## 2. OpenRC today (source audit at `3db34a8a3`)

| # | Finding | Evidence |
| --- | --- | --- |
| A1 | The only EdgeTX preset is the FPV quad (`edgetx_fpv`: CH5 arm on axis 4, CH6 flight mode on axis 5, CH9 restart on button 0). Radio profiles start with every optional action unbound and no airplane AUX; standardized-gamepad automatic buttons never apply to radios. | `app/input/controller_profile.gd:17-26, 89-94`; `app/input/controller_actions.gd:108-114, 196-200` |
| A2 | The EdgeTX starting draft is chosen only when the registry kind is already `radio`. That kind comes from JETI identity or from name tokens (`RcInput.RADIO_NAMES`); the `1209:4F54` matcher is used only inside Controls. If Godot's device name is only `<Maker> <Model> Joystick`, radios from makers outside the token list (Fatfish, iFlight, HelloRadioSky) become `joystick` and get an unconfigured custom draft; if SDL adds the USB manufacturer ("OpenTX"), the existing "opentx" token catches them. Inference pending F1-ETX-01, which records Godot's `name` and `raw_name`. | `app/ui/controller_setup.gd:2430-2440`; `app/input/controller_service.gd:153-166`; `app/input/rc_input.gd:33, 95-97`; `app/input/edgetx_radio.gd` |
| A3 | Fixed axis indices assume the Windows raw order. Under E5 (Linux Classic) axis 4 is CH3 throttle as a trigger, so the FPV preset's arm AUX would overlap the calibrated throttle and be removed by calibration merge (fail-safe, but unassigned), and SDL's "known gamepad" flag would classify the radio as a gamepad when its name lacks a token. Inference pending F1-ETX-01. | `app/input/controller_profile.gd:207-248`; `app/input/controller_registry.gd:166` |
| A4 | Dual rates: rate ownership is implied by the profile kind. A `radio` profile always passes through unshaped ("Radios supply transmitter-shaped commands"); keyboard, gamepads and calibrated `joystick` profiles get the aircraft's manual rates (`controls.rates.normal`, sport, full). There is no `rates` AUX channel: the press action `rates_toggle` toggles normal ⇄ high, a maintained switch position cannot select a rate, and a radio is refused. | `app/sim/flight_session.gd:4169-4204, 4241-4260`; `app/main.gd:1955-1961`; `app/input/controller_actions.gd:13`; [FIRST-LAUNCH rates](../../../FIRST-LAUNCH.md) |
| A5 | Flap-to-elevator compensation already has explicit ownership (`flap_elevator_mix_owner`: simulator or transmitter), recorded per interval for replay. It is the model for any other "radio or simulator" choice. | `app/input/controller_profile.gd:9, 198-203`; `app/sim/flight_session.gd:4309-4325`; [DECISIONS AV-17-R5](../../../DECISIONS.md) |
| A6 | A radio flap AUX is continuous: a 3-position switch gives 0 / 0.5 / 1 (asserted by `test_jeti_runtime.gd:163`), while keyboard detents use the aircraft's take-off fraction (P-51 1/3, Vantage 0.4). | `app/sim/flight_session.gd:3110-3122`; `app/main.gd:1974-1980` |
| A7 | Two AUX channels may never share a physical control, so one radio profile cannot hold the quad's CH5/CH6 (arm, mode) and an airplane's CH5/CH6 (gear, flaps). Profiles have no vehicle field. | `app/input/controller_actions.gd:259-268`; [controls UX out of scope](../../../plans/controls-setup-ux.md#explicitly-out-of-scope) |
| A8 | Gear and flaps keep their last accepted request until the switch is seen at OFF (fresh-OFF arming); smoke stays off. The pilot gets no cue that a switch must be cycled. | `app/input/rc_input.gd:474-482`; `app/sim/flight_session.gd:3114-3122` |
| A9 | The in-flight control guide (HUD-11-R2, shown in the default Pilot overlay preset) lists radio controls as "Axis N" / "Button N"; physical names exist only on switch-group bindings. Rates row: "The radio sets its own rates." No hotkey opens it (reopen: Esc → Flight overlays); F1 is unbound. | `app/render/overlays/controls_guide.gd:118-206, 289-300`; `app/input/smoke_aux.gd:220-222`; `app/render/overlays/overlay_settings.gd:33-48` |
| A10 | Contradictory EdgeTX guidance: Help says "select Advanced Joystick in Model setup"; calibration and the Setup assistant say "USB Joystick (Classic)". | `app/ui/help_screen.gd:229`; `app/ui/controls/calibration_view.gd:25`; `app/ui/controls/setup_assistant.gd:77` |
| A11 | Wheel brake, wing fold, canopy and tailhook are keyboard-only (B, O, U, Y); the status line still names keyboard H/J for smoke. | `app/ui/controls_reference.gd:34-38`; `app/main.gd:1842-1846` |
| A12 | Aircraft with the equipment: retractable gear and flaps on P-51D, F4U Corsair and Vantage (Avanti, the only one with a non-zero flap-elevator mix, 0.2); `controls.rates` on most of the fleet but not all; smoke depends on the aircraft's smoke profile. | `app/data/aircraft/*.json`; `app/main.gd:1903-1909` |

## 3. Consequences for the plan

1. **Bind switches by movement, not by fixed indices.** Channel numbers are a recommendation to the pilot; the controller binds whatever axis or button actually moves (E5, E6, A3). This also respects the contract that a recognized family name never implies channel order.
2. **Keep the must-have functions off CH7/CH8.** Gear and flaps on CH5/CH6 (axes on every OS), restart and smoke on button channels (CH9, CH10). The optional simulator-rates switch is the only CH7 user.
3. **Offer both rate owners.** EdgeTX's wizard owns rates on the radio; RealFlight's InterLink convention leaves them to the simulator, which knows each aircraft. OpenRC already has per-aircraft manual rates and an ownership pattern (A5).
4. **Help must name the radio's own switch** ("CH5 · SD") and say which side applies rates and the flap mix.

## 4. Not verified

SDL3's Windows backend and the real CH5–CH8/button indices per OS; Advanced-mode descriptors on hardware; radios' physical switch types (2- vs 3-position) per model; an EdgeTX model YAML schema that would be portable across radios; any third-party simulator behaviour beyond the InterLink page.
