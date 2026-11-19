# On-screen radios and EdgeTX integration

Status: **planned; initial source inspection complete; runtime, device and further research gates open**.
Research date: **2026-11-18 (America/Bogota)**.
Baseline: [OpenRC cf03e40](https://github.com/bultodepapas/OpenRCsimulator/commit/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c).
[Dated findings and primary sources](../research/radio-input/D6-RADIO-00/README.md).

The request's “HTX” is interpreted as **EdgeTX**. This plan extends the existing
[flight overlays](flight-overlays.md) and [EdgeTX controls](edgetx-airplane-controls.md).
It does not claim that firmware simulation or the new radio artwork already ships.

## The simple plan

1. **Choose a radio.** Extend the current Radio appearance selector with Jumper
   T18-H7 and RadioLink T12D; retain JETI DS-24 II and the existing RadioLink T16D.
2. **Read its screen.** Show model name, timer and useful simulated telemetry.
   Let the pilot enlarge the screen.
3. **Operate EdgeTX.** Run the actual T18-H7 firmware simulator in a local helper
   and place its real LCD image inside the radio.
4. **Understand configurations.** Import a copy of an EdgeTX model, explain its
   settings, and add small verified setup exercises.
5. **Extend support.** Add other EdgeTX targets through the same interface; give
   other firmware families their own verified capabilities.

The first usable delivery is steps 1–2. Firmware research can proceed alongside
that work without making a radio appearance change depend on an emulator.

## Radio targets

| Radio | Appearance | Display and firmware scope |
| --- | --- | --- |
| Jumper T18-H7 | New definition and redistributable artwork | First real EdgeTX target; separate identity from older T18 variants |
| RadioLink T16D | Existing artwork and selection | Improve simulated telemetry; RadioLink firmware integration remains research |
| RadioLink T12D | New definition and redistributable artwork | Simulated telemetry; existing input path subject to device/OS/USB-mode qualification |
| JETI DS-24 II | Existing option | Preserve its saved identity and behavior |

T18-H7 is listed upstream from EdgeTX 2.12.5 and its target exists in that pinned
source; native runtime and physical qualification remain open. RadioLink T16D/T12D use the
manufacturer's FreeRTOS/LVGL software, not EdgeTX. T16D is the higher-spec option;
the evidence does not establish two equally high-end RadioLink flagships.
The [source report](../research/radio-input/D6-RADIO-00/README.md#radio-evidence)
records the product and firmware distinctions.

## Build on the existing code

The [transmitter overlay](../../app/render/overlays/transmitter.gd) already draws
JETI/T16D, moves sticks and trims, and paints a small OPENRC SIM display.
[Overlay settings](../../app/render/overlays/overlay_settings.gd) persist the
selection; the [dialog](../../app/ui/overlays_dialog.gd) exposes it.

Replace the two-model drawing branches with a small versioned catalog:
stable ID, label, artwork, canvas size, gimbal/trim/switch positions, LCD rectangle,
firmware family and compatible target IDs. An appearance definition does not
establish USB mapping or firmware compatibility. Unknown saved IDs fall back
without rewriting the controller profile. Adding one radio should require an
asset and catalog entry, not another renderer branch.

Use a display provider for either OpenRC telemetry or an actual firmware
framebuffer. The firmware choice must match the selected radio's capabilities.
EdgeTX menus must never appear as if they were RadioLink firmware.

## Telemetry and readability

Reuse [overlay snapshots](../../app/render/overlays/overlay_manager.gd) and
[battery sensor readings](../../app/render/overlays/battery_sensors.gd).
The compact screen shows a few values; the enlarged view adds channels and
settings. Useful initial fields are OpenRC aircraft name, flight timer, aircraft
battery voltage, consumed mAh, altitude with an explicit datum, and named airspeed
or ground speed. A firmware model name is separate and shown only when known.

Keep unknown values unavailable. Do not substitute transmitter battery voltage,
invent RSSI, or present internal true battery charge as a measured sensor.
Show a small SIM indication for simulation data. The same data feeds an EdgeTX
telemetry encoder later; select units and sensor identities explicitly.

The real-firmware bridge also needs configured/discovered sensors and a defined
virtual-link state. Some protocols bundle several readings and retain old values;
omit unsupported frames and explain stale data rather than substituting zero.
Any generated link-quality state represents the virtual connection, not measured RF.

Numeric presentation uses the existing 10 Hz cadence. Input sampling, firmware
execution and output channels must not inherit that slow display rate.
Repaint actual firmware LCD frames when supplied, independently of telemetry.
HUD reads accepted simulation state and never writes flight controls.

Clicking the screen opens an enlarged, keyboard-accessible view. Configuration
interaction uses the existing pause/menu ownership so a navigation gesture cannot
also fly or restart the aircraft. Verify the repository's primary display policy,
including the Apple Retina exception, and EN/ES readability.

## Real EdgeTX: a bounded first integration

Evaluate the **stable 2.12.5 T18-H7 native simulator** first. Source code defines
the target and loader, but no native build or runtime smoke has been executed
for this investigation. The first gate is to boot that exact target, copy its
LCD, move one control, read one channel and inject one telemetry value.

The stable Companion adapter emits changed channel values on a nominal 50 ms
cadence. It is a useful screen/training starting point, but that signal path is
not yet qualified for flight control. Measure freshness and latency; evaluate a
coherent faster snapshot API or the development WASM channel-copy interface
before admitting virtual-radio flight.

A proposed local helper owns the EdgeTX runtime, its event loop and a private
copy of SD/settings data. Godot exchanges versioned control, channel, telemetry,
status and LCD messages with it. This bridge is new work. Pin the source commit,
radio target, settings version and binary identity; run a mismatch check before
starting. Disable the optional runtime when unused.

Keep these paths explicit:

| Mode | Control authority |
| --- | --- |
| Physical USB radio | Existing calibrated ControllerService/RcInput path; channels may already contain rates, expo and mixes |
| Virtual EdgeTX training | Raw virtual sticks/switches enter EdgeTX; admitted logical outputs enter the normal session input boundary |
| Telemetry-only display | The display is read-only; the existing selected flight controls may remain active |

Preserve the existing rates/expo and flap-mix ownership rules. **The first virtual
flight integration admits only a verified restricted logical AETR configuration**
with explicit mapping, signs, ranges and independent AUX demands. Invalidate and
recheck that admission when the model or its configuration changes. It rejects
unknown mixing and arbitrary elevon, differential, V-tail or flap-to-aileron
surface outputs as roll/pitch commands: OpenRC currently allocates those surfaces
itself. Preserve that allocation and its actuator dynamics. Unsupported mixed
models remain available for inspection/training without flight admission.

For the first virtual-flight subset, OpenRC owns pilot trim and EdgeTX pilot
trims must be neutral. Preserve OpenRC's solved launch trim and aircraft rigging
offsets; they are not duplicate pilot-trim controls. EdgeTX trim exercises stay
in training until an explicit radio-owned pilot-trim mode is qualified.

The physical USB path cannot infer or undo arbitrary mixes from calibration.
Its setup must explain the logical-AETR requirement and single ownership of
rates/mixes. Never feed its already-processed channel values into virtual
EdgeTX as if they were raw gimbal positions.

Helper failure or stale outputs must enter the existing pause/disconnect recovery
path. Use separate liveness and coherent-snapshot freshness evidence; a steady
stick must not time out merely because no value-change event occurred. Recovery
retains fresh-low-throttle and fresh-OFF AUX checks. Pause, restart, aircraft
changes and resume need explicit behavior:
do not resume with stale channels or a held setup action. EdgeTX timers run in
their own runtime; exact firmware lockstep is unproven. Record admitted flight
inputs and ownership for replay; playback must not query a live helper.

Current EdgeTX development also has native WASM hosting and a browser simulator.
Evaluate that as a separate backend after the stable gate or if a demonstrated
stable limitation justifies it. Keep runtime and UI-tree capabilities versioned;
do not label development-only behavior as stable 2.12.5.

## Configurations and learning

First add a **read-only** viewer for copied .etx/model YAML data. Keep source
radio, firmware version and file identity. Explain inputs, mixes, outputs,
rates/expo, endpoints, trims, flight modes and switches; mark unsupported settings.
Viewing a model does not certify flight compatibility. Bare model YAML may not
identify its source board, so require the missing context before conversion.

Extend the existing setup assistant, which already calibrates sticks and learns
switches by movement. Add four small lessons: reverse a channel, change expo,
assign a switch and select a flight mode. Each lesson checks the resulting
screen/configuration and channel behavior. Version lessons by target/firmware.

EdgeTX package-tools' scripted simulator is a reference for this observe–act–check
loop. It is not an existing Godot integration. Development EdgeTX additionally
exposes a color-screen UI tree; stable training can use screenshots and channel
observations. Start with copied models; changes stay in the training copy.

RadioLink USB model backups provide a later read-only import research lead.
Their .dat schema and a PC-to-physical-LCD telemetry API are unverified. USB
joystick support alone establishes neither. Physical transmitter updates or
telemetry return are outside this delivery.

## Work and acceptance

All implementation rows are pending.

| ID | Work | Proof / status |
| --- | --- | --- |
| D6-RADIO-00 | Current-source and upstream feasibility research | This plan and linked dated evidence; source inspection only |
| HUD-RADIO-01 | Catalog and existing selector extension | Saved choices survive; all four appearances work; calibration/bindings unchanged |
| HUD-RADIO-02 | Telemetry display and enlarged view | Accepted values/units, unavailable-data/reset cases, readable EN/ES captures; no input or physics change |
| D6-RADIO-01 | Exact T18-H7 runtime spike | Boot, LCD, input→channel, telemetry→LCD, stop/restart; record source/build/OS identity |
| D6-RADIO-01b | Channel freshness and runtime choice | Measure native event cadence; qualify a coherent snapshot path and input latency before flight admission |
| D6-RADIO-02 | Helper transport and admitted virtual control path | Single rate/mix owner; reject mixed-surface misuse; bounded queues, stale-data pause and lifecycle/replay checks |
| UI-15-RADIO-01 | Copied-model configuration viewer | Matching-board/version fixtures, unsupported data clearly reported, original files untouched |
| UI-15-RADIO-02 | Guided EdgeTX lessons | Four reproducible lessons with screen/configuration and channel assertions |
| F4-RADIO-01 | Native/package/device qualification | Separate Windows, Linux and macOS receipts; physical T18-H7/T16D/T12D mapping checked per OS/firmware |

Reuse the existing controller, overlay, flap-mix, surface-allocation, pause and
flight-log checks identified in the source report. Run focused checks for each
increment; full runtime qualification belongs to the later integration steps.
Documentation checks do not satisfy the runtime or physical-device gates.

## Ownership and delivery boundaries

| Owner | Planned scope |
| --- | --- |
| HUD / UI | Radio catalog/assets, transmitter display, overlay settings/dialog, enlarged view and translations |
| D6 input / session | Optional firmware adapter, admitted logical input mapping, freshness, ownership and lifecycle |
| UI setup | Configuration viewer and lessons extending the existing assistant |
| DT / release | Helper builds, target/version manifests, licenses and native package checks |

Shared files remain with their existing track owners. Proposed helpers belong
under a dedicated tools/runtime directory selected at D6-RADIO-01; this plan
does not introduce a new physics kernel or replace ControllerService.

Use original or redistributable radio artwork. OpenRC is MIT; core EdgeTX is
GPL-2.0 and package-tools declares GPL-3.0-only. Keep code provenance and resolve
distribution obligations before bundling; a separate process alone is not a
license-compatibility conclusion.

**Next implementation increment:** HUD-RADIO-01 and HUD-RADIO-02, with the
D6-RADIO-01 runtime spike kept separately reviewable.
