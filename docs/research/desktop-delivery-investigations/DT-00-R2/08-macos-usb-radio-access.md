# DT-00-R2-08 — macOS USB radio access and identity

2026-10-07 · **Source and code review complete; real radio acceptance remains pending.**

## Question and method

Which macOS gates sit between an EdgeTX radio and OpenRC's channel reader, and
which privacy prompts are actually justified? I inspected the current Godot input
and radio paths and standalone input report; consulted Godot 4.7, SDL 3, Apple
accessory/privacy, and EdgeTX documentation. No Mac or transmitter was connected.

## Findings

1. **Engine layer (vendor fact):** since Godot 4.5, desktop Windows/macOS/Linux
   controller support uses SDL 3; SDL is only the controller layer, not Godot's
   windowing or audio backend. Godot calls specialized HOTAS devices less tested,
   so RC-radio support still needs device evidence. [Godot 4.7 controller guide](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html).
2. **Apple Silicon laptop accessory gate (vendor fact):** macOS may ask the user
   to allow a new or unknown USB/Thunderbolt accessory on an Apple Silicon Mac
   laptop. A locked Mac must be unlocked to approve it; choosing Don't Allow
   prevents recognition/data, even though charging can continue. The default is
   Ask for New Accessories, with other policies in Privacy & Security.
   [Apple accessory approval](https://support.apple.com/en-us/102282).
3. **Keep OS approval separate from SDL mapping:** the path is cable/adapter/hub
   and accessory approval → macOS USB/HID enumeration → SDL device discovery →
   Godot axes/events → OpenRC profile/calibration. A radio missing at one stage
   does not diagnose the next. Test a direct cable, the actual USB-C adapter,
   powered hub/dock, and reconnect after approval as separate topologies.
4. **No broad input permission inferred:** Apple's Input Monitoring setting is for
   apps monitoring keyboard, mouse, or trackpad input while other apps are used.
   This project reads normal Godot `Input` joypad devices and uses in-window
   keyboard controls; it has no global event tap or accessibility integration.
   **Inference:** a normal SDL USB-radio route should not require Input Monitoring
   or Accessibility permission. Verify on a clean Mac account; do not add an
   entitlement, privacy request, or setup instruction unless a reproducible prompt
   and a concrete API dependency prove it necessary. [Apple Input Monitoring](https://support.apple.com/en-us/guide/mac-help/mchl4cedafb6/mac), [Godot Input API](https://docs.godotengine.org/en/4.7/classes/class_input.html),
   [current flight input](../../../../app/sim/flight_session.gd).
5. **EdgeTX modes change the test object:** its manual distinguishes Classic
   (radio output channels in numeric order, with published default mapping for
   Windows) from configurable Advanced mode. Advanced mode may require
   disconnect/reconnect after its configuration changes; record firmware, USB
   mode/interface, channel order, axis count, and chosen channels rather than
   promising a generic "EdgeTX" mapping. [EdgeTX USB Joystick](https://manual.edgetx.org/color-radios/model-settings/model-setup/usb-joystick), [Advanced mode setup](https://manual.edgetx.org/edgetx-how-to/configure-advanced-joystick-with-edgetx).
6. **Identity has two meanings:** Godot exposes an SDL-compatible GUID plus
   platform device info; SDL describes its GUID as a platform-dependent
   device-class identifier, while an instance ID is for the current connected
   instance and changes on remove/reinsert. Do not persist the runtime ID as radio
   identity. [Godot Input](https://docs.godotengine.org/en/4.7/classes/class_input.html), [SDL joystick API](https://wiki.libsdl.org/SDL3/CategoryJoystick).
7. **Current profile key:** OpenRC's calibration key is
   `guid|vendor_id:product_id|name`; it omits the runtime ID. It selects the first
   connected device when none is active, polls axes at physics rate, and
   pauses/fails safe on disconnect. Whether EdgeTX metadata or GUID remains stable
   across USB mode/firmware/SDL changes is unmeasured. [Radio reader](../../../../app/input/rc_input.gd),
   [session selection and disconnect](../../../../app/sim/flight_session.gd).
8. **Useful diagnostic is already present:** `--input-report[=path.json]
   [--t=seconds]` captures OS/Godot version, GUID, name/raw name, VID/PID,
   observed axes/ranges, and callback-arrival spacing. The report explicitly says
   event timing is not USB report interval or end-to-end latency; it does not fly
   or save calibration. [Input report](../../../../app/input/input_report.gd), [report data](../../../../app/input/input_report_data.gd), [R1 radio contract](../DT-00-R1/12-radio-export-contract.md).

## Proposed native gate

1. On a clean Apple Silicon laptop account, connect the owner's radio while
   unlocked and while locked; capture whether macOS asks for accessory approval
   and verify the radio is visible only after Allow. Repeat with the documented
   security default and no Input Monitoring/Accessibility grant. Record OS build,
   laptop model, radio/firmware, cable/adapter/hub/dock, and decision.
2. Run the input report for EdgeTX Classic and Advanced configurations that the
   owner actually uses. Save redacted identity and axis evidence; omit serial
   numbers. Exercise each stick end-to-end, compare the chosen axis/channel map,
   then unplug/reconnect on the same and another port. Confirm the profile is
   selected or calibration is visibly requested.
3. In the installed app, verify throttle-high/unseen remains idle, a real low
   observation arms, disconnect neutralizes and pauses, and reconnect does not
   resume flight automatically. Confirm radio controls never operate menus. Repeat
   after macOS focus loss and return.
4. If no HID appears, record the failure boundary using macOS System
   Information/USB device listing and the standalone report; never ask users to
   grant unrelated global input permissions as a blind workaround.

## Plan integration and limits

DT-01 records Apple Silicon OS/build and the physical path; DT-05b owns
device/firmware/mode claims and calibration/reconnect behavior; DT-12 must repeat
with the downloaded candidate and real radio. Use the existing `--input-report`
route without changing its event-timing disclaimer. This report does not establish
compatibility for any radio model or prove that no macOS permission prompt can
occur on every supported OS.

## Sources consulted 2026-10-07

- [Godot 4.7 controller guide](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html)
- [Godot 4.7 Input API](https://docs.godotengine.org/en/4.7/classes/class_input.html)
- [SDL 3 joystick API](https://wiki.libsdl.org/SDL3/CategoryJoystick)
- [Apple: Allow USB and other accessories to connect](https://support.apple.com/en-us/102282)
- [Apple: Control access to Input Monitoring](https://support.apple.com/en-us/guide/mac-help/mchl4cedafb6/mac)
- [EdgeTX USB Joystick manual](https://manual.edgetx.org/color-radios/model-settings/model-setup/usb-joystick)
- [EdgeTX Advanced Joystick setup](https://manual.edgetx.org/edgetx-how-to/configure-advanced-joystick-with-edgetx)
