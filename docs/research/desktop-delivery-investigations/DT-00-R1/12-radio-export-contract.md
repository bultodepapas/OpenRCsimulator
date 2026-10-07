# 12 — USB radio acceptance in the installed application

2026-10-07 · DT-00-R1 · **Code/doc research plus synthetic pure-module probes; real radio acceptance remains pending.**

## Question and method

Can the same downloaded desktop build correctly identify, calibrate and safely resume a real transmitter across OS, firmware and focus transitions? Read the current `rc_input.gd`, `rc_calibration.gd`, `flight_session.gd`, `ui/home.gd` and `main.gd`; extend the earlier [SDL identity investigation](../../menu-investigations/12-identidad-joypads-sdl3.md) with installation/upgrade acceptance. [Probe source](probes/pure_module_probe.py) and [results](probes/pure-module-results.json) use copied production modules, not a connected USB device.

## Findings

| Finding | Evidence | Delivery consequence |
| --- | --- | --- |
| Desktop Godot uses SDL3 for controllers, but not windowing or audio | [Godot controller guide](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html) | A successful SDL input check says nothing about macOS Spaces, native close or audio recovery |
| Home describes the first connected device; session adopts `pads[0]` or the first connection while none is active | Current `home.gd`, `flight_session.gd` | Packaging cannot promise that the user's preferred radio wins over a previously connected gamepad |
| Calibration key uses GUID, VID/PID and name, excluding runtime ID | Executed: identical info at IDs 0 and 1 yields the same key; changing a synthetic GUID yields another key | Preserve calibration files across upgrades, but do not infer that every firmware/backend change finds the same profile |
| Known gamepad + unfamiliar radio name selects the gamepad profile despite EdgeTX VID/PID | Executed synthetic info `1209:4f54`, name `Fixture Joystick`, `known=true` produces `kind=gamepad` | This proves the selection rule, not that an actual transmitter emits that tuple; test VID/PID-based recognition with the input owner |
| Raw axis values are polled at physics rate while actual events come from the input backend | Current `RcInput.poll()` and `_input()` | 240 Hz polling does not establish 240 fresh USB samples/s or measured response latency |
| Flight disables accumulated input | Current `main.gd`; [Input](https://docs.godotengine.org/en/4.7/classes/class_input.html) | Retain the policy unless measured evidence supports change; it is not a complete input-to-display latency guarantee |

EdgeTX distinguishes Classic from configurable Advanced interfaces and publishes Classic's mapping specifically for Windows. Advanced offers Joystick/Gamepad/MultiAxis and requires Apply Changes. The manual recommends disabling RF modules for joystick use. Those details must be captured in a device test record instead of saying merely “EdgeTX supported.” [Official EdgeTX USB guide](https://manual.edgetx.org/color-radios/model-settings/model-setup/usb-joystick).

Godot's [pinned SDL driver](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/sdl/joypad_sdl.cpp) is the relevant integration layer; consult it alongside the [Input API](https://docs.godotengine.org/en/4.7/classes/class_input.html), not just standalone SDL behavior. SDL's [background-input hint](https://wiki.libsdl.org/SDL3/SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS) documents a default, but does not prove the engine uses that default. The app must preserve focus/failsafe holds independently of whether events continue arriving.

## Required acceptance record

For each promoted OS/architecture, record package hash, engine version, transmitter model/firmware, USB mode/interface, channel order, axes used, OS/backend, detected GUID/name/raw name/VID/PID, selected profile and whether a saved calibration was found. Device serials are optional diagnostics and should be omitted/redacted from public evidence unless necessary. Record unknown fields as unavailable.

Use Advanced/Joystick as the initial documented candidate configuration, retaining explicit calibration verification. Test Classic as a compatibility case with actual axis mapping; do not silently assume the same throttle axis or range on all OSes. Preserve the ten-axis engine limit and existing throttle-low arming until the input owner provides evidence for a change.

| Scenario | Required outcome |
| --- | --- |
| Fresh launch, throttle physically high or unmoved | Idle until a genuine low-throttle observation permits arming |
| Home → Fly, then unplug | Selected physical device is identifiable; neutral/idle and pause on loss |
| Reconnect at a different port or with a different runtime ID | Defined selection, explicit pilot resume and correct profile; no automatic uncontrolled handoff |
| Radio + gamepad, two identical radios | Selection/ambiguity is visible; no silent claim of unique persistent identity |
| Fullscreen/Alt+Tab/Cmd+Tab/lock/suspend, sticks moved while away | Focus hold survives; resume cannot reuse a stale unsafe state; test fresh-input policy with its owner |
| Firmware or engine/SDL upgrade | Detect identity/profile change; verify calibration before reuse; no silent family-based reassignment |
| Installer upgrade/uninstall/reinstall | Calibration bytes preserved and real controls still match their channels |
| All menu states and display confirmation | Radio axes/buttons do not move focus, accept Keep, resume or quit |

## Plan integration

**Concurrent-work note:** the input owner added a standalone `--input-report[=path] [--t=seconds]` route during this audit. It runs before ordinary Home/flight routing and records identity, raw input and callback-arrival timing without flying. Reuse and coordinate that diagnostic when it is validated; preserve its argument contract in DT-03. Callback arrival is not USB transfer time or end-to-end latency. This investigation inspected the work in progress and did not run or certify it; the audit snapshot records the observed file hashes.

Add **DT-05b** as installed-radio acceptance coordinated with UI-10a/10b/12 and the input track. Do not take over their device-selection implementation. An existing limitation can narrow the support claim to a tested single-radio configuration; it cannot be silently marked as multi-device support.

**DT-01/DT-12:** a “platform passed” row must include keyboard/mouse GUI acceptance and separately recorded real-radio evidence for the advertised configuration. Fake-input tests remain valuable for pause/arming logic, but never pass USB discovery or physical input latency.

**DT-10:** retain the F6 real-device/high-speed-video method; correlate USB/input events only as supplemental instrumentation. Sample freshness, simulation response and visible presentation are separate timestamps. Changing frame caps or input accumulation requires rechecking latency and arming/focus behavior.

No real device was connected or firmware altered. The probe only demonstrates existing branch/key behavior and does not validate a misclassification on hardware. Concurrent calibration validation work was inspected without modification. Sources were opened on 2026-10-07; earlier source-level hypotheses remain labeled until repeated with the actual export and radio.
