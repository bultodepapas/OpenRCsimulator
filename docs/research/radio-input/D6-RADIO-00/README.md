# D6-RADIO-00 — radio display and EdgeTX feasibility

Research date: **2026-11-18, America/Bogota**. Scope: current-source inspection,
manufacturer documentation and implementation planning. **No EdgeTX build,
native simulator session, OpenRC runtime test or physical transmitter test was
executed.** The [active plan](../../../plans/radio-display-edgetx.md) owns work,
acceptance and remaining decisions.

## Source identities

| Source | Inspected identity | Evidence scope |
| --- | --- | --- |
| OpenRC | [cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c][openrc] | Current implementation, shared input/session contracts and existing checks |
| EdgeTX stable | [v2.12.5][release], commit 0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99 | Native simulator/plugin and storage code |
| EdgeTX development | [3dd6fe069657fcdb3237dec2df61d01c1b53facc][edgetx-main] | WASM host/API, browser simulator and UI-tree capabilities |
| EdgeTX package-tools | [0d1fc38ebd27e75c5a88549b137a5a4626f9e91f][package-tools] | Scripted simulator documentation and declared license |
| Radio manufacturers | Official pages linked below, checked on the research date | Product/firmware claims; no device qualification |

The stable tag is annotated; its tag object resolves to the commit above.
Development capabilities are deliberately recorded separately. Website claims
can change; these are dated observations, not permanent compatibility guarantees.

## What the continued investigation changed

1. **T18-H7 is more than a supported firmware name:** stable source and the
   Companion build script actually include its native simulator target.
2. **A straightforward channel-signal bridge has a timing limitation:** stable
   Companion checks changed outputs every nominal 50 ms.
3. **OpenRC expects logical commands, not arbitrary individual servo outputs.**
   Feeding an already-mixed elevon or differential-aileron model into those axes
   would apply allocation again.
4. **Telemetry requires a protocol/session contract:** sensor discovery, stream
   validity, missing fields, units and stale readings all affect the result.
5. **RadioLink exposes model backup files.** This is a concrete later import
   research path, but no supported .dat parser or live configuration API was found.

## Radio evidence

| Target | Verified manufacturer/upstream facts | Consequence |
| --- | --- | --- |
| Jumper T18-H7 | Manufacturer has a [T18 H7 page][jumper]; [EdgeTX support][supported] starts at 2.12.5 | Use t18h7, not the older t18 target |
| RadioLink T16D | [Official comparison][radiolink-comparison]: FreeRTOS/LVGL, 16 RF channels, more capabilities than T12D; [manual][t16d-manual] documents USB-C simulator mode with firmware 1.7.1 | Existing visual choice; qualify USB mapping separately; no EdgeTX firmware claim |
| RadioLink T12D | Same official comparison: FreeRTOS/LVGL, 12 RF channels; [manual][t12d-manual] documents USB-C simulator mode | Add a separate appearance; model identity is not a channel-map guarantee |
| T12D firmware 2.0.4 | [Release notes][t12d-firmware], dated 2026-10-15, expand gamepad operation to 16 channels | RF channel count and USB report layout are different facts |

The two RadioLink targets are the current T-series pair selected for this plan.
The evidence supports T16D as the higher-spec option, not a claim that both are
equally high-end flagships or an exhaustive ranking of all newly released radios.

Manufacturer manuals list Windows/macOS simulator operation. Linux and the
exact OpenRC mappings still require native device reports. OpenRC's profile
schema currently declares ten axis slots [O6]; a marketing count of 16 USB
channels does not establish 16 independent Godot axes, nor justify changing
the schema without seeing the reports and button/axis encoding.

## Existing OpenRC reuse

| Source | Verified behavior | Plan implication |
| --- | --- | --- |
| [transmitter.gd][O1] | JETI/T16D art, per-model screen rectangles, animated sticks/trims and custom throttle/aileron/elevator text | Extract catalog data and LCD drawing; no new generic input subsystem needed |
| [overlay_settings.gd][O2], [overlays_dialog.gd][O3] | Validated saved appearance and existing selector | Extend the current setting with stable IDs |
| [overlay_manager.gd][O4] | Numeric updates at 10 Hz; accepted telemetry and battery readings already held | Reuse the existing snapshot; do not tie controller timing to display timing |
| [battery_sensors.gd][O5] | Sampled/quantized voltage, current, consumed capacity, cell and temperature readings; explicit unknowns | Reuse the sensor view rather than expose true internal charge |
| [controller_profile.gd][O6] | EdgeTX presets, rates owner and flap/elevator-mix owner | Keep existing calibration and exactly one owner per transformation |
| [existing EdgeTX plan][O7] | Software phases recorded implemented 2026-11-17, with physical/capture gates open | Extend the current assistant rather than rebuild it |

At this baseline, the documentation registry still described the older EdgeTX
plan as entirely unimplemented. The documentation change reconciles that row
with its authoritative plan while retaining the open hardware gates.

The T16D LCD currently occupies only 56 × 42 logical pixels in its small HUD
drawing [O1]. An enlarged screen is therefore part of usability, not decoration.
A selection change is visual; no channel order can be inferred from the artwork.

## Stable T18-H7 simulator: source-supported, not smoke-tested

The stable [radio CMake targets][E1] include T18H7. Its
[target configuration][E2] selects color graphics, 480 × 272 resources, touch,
rotary navigation and the t18h7 flavor. The
[simulator build][E3] creates the flavor-specific shared simulator when the Qt
prerequisite is present. The [Companion build script][E4] includes t18h7 in
its plugin list and has separate platform packaging paths.

The [stable loader][E5] scans native simulator libraries and resolves the
registration entry point. This supports a local helper wrapping the upstream
simulator. It does not establish that a binary was built successfully or boots
on any particular machine.

An implementation spike should use the stable branch's own native build
instructions and exact dependency versions, then record its resulting binary
and target identity. Resolve Qt development dependencies and optional SDL/audio
behavior from that source, rather than applying current-main build instructions
to stable.

T18-H7 has its own controls and capabilities. Generate or inspect the matching
descriptors; do not duplicate the older T18 definition just because the LCD
resolution matches. Physical control positions, radio source assignments and
aircraft channel roles are separate mappings.

### LCD transfer

The [T18-H7 HAL][E6] declares a 480 × 272, 16-bit display.
[Companion's LCD widget][E7] uses RGB565-compatible RGB16, with a 960-byte row:
**261,120 bytes for one full frame**, calculated as 480 × 272 × 2.

The native API returns a buffer pointer and signals LCD changes [E8].
Companion copies the buffer before acknowledging that it has been consumed.
The proposed helper must similarly own a complete copied frame before allowing
firmware reuse; a pointer into another process is not a transport.

Carry width, height, stride, pixel format and frame sequence explicitly.
Convert to a suitable Godot texture format at the rendering boundary. A single
latest-frame slot can bound backlog; validate color order and image orientation.
These are design proposals, not tested throughput or rendering measurements.

### Channels and latency

The [stable run loop][E9] checks outputs on every fifth 10 ms event-loop cycle:
a **nominal 50 ms notification cadence**, with event-loop jitter. It is not the
firmware mixer frequency and not a measured end-to-end input latency.

Its final channels use 1024 for 100% travel; extended output limits can be 1536.
Keep that scale explicit. Dividing by the currently advertised limit would
silently change control gain when extended limits are enabled. Admission must
define clamping or reject unsupported travel, rather than reinterpret units.

Use the stable signal path to prove functionality and training behavior.
Before flight admission, compare a coherent faster snapshot path against the
development WASM channel-copy API. Measure freshness, jitter and actual
stick-to-accepted-input latency against the project's input gates. Sampling the
same old value at 240 Hz does not make it a 240 Hz controller.

### Thread ownership

[Companion][E10] assigns the simulator to an event-loop thread; firmware tasks
also execute independently. A helper should marshal API calls to the owning
thread and expose copied snapshots. Godot's main/physics threads must not block
on a firmware operation. Preserve the LCD copy/acknowledgment handshake and
qualify start, stop, crash and recovery behavior.

## Telemetry is a real protocol boundary

The [stable interface][E8] accepts FrSky SPORT, Hub and Crossfire telemetry
buffers. It does not accept a dictionary of sensor names. T18-H7's target
configuration enables a CRSF internal-module default [E2], making CRSF a
reasonable initial experiment, not a requirement for every radio.

The [Crossfire decoder][E11] distinguishes these wire values:

| Value | CRSF candidate | Interpretation to preserve |
| --- | --- | --- |
| Battery voltage/current/used capacity/remaining | Battery frame, 0x08 | Voltage and current in tenths; capacity in mAh; percentage is a declared sensor estimate |
| Barometric altitude | 0x09 | Encoded altitude with range-dependent representation; define the simulated datum |
| Airspeed | 0x0A | Tenths of km/h; use air-relative speed |
| GPS ground speed/position/altitude | GPS frame, 0x02 | Ground speed differs from airspeed; requires a defined simulated geographic frame |
| Link/session validity | Link statistics, 0x14 | Virtual connection status, never a measured physical RF-quality claim |

The decoder requires an active telemetry stream. A valid nonzero link-quality
update refreshes that stream; supplying only ordinary sensor frames is
insufficient. Any generated link state is explicitly simulated.

Battery and GPS frames bundle values. The inspected decoder consumes their
constituents; zero or arbitrary sentinel values must not stand in for unknown
measurements. Admit a frame only when its required fields have defined meaning,
or select another verified sensor protocol. GPS can remain deferred while
airspeed and barometric altitude work independently. [E11]

The [sensor insertion path][E12] updates configured sensors and discovers new
ones only when discovery is enabled. The spike therefore needs a matching model
and a discovery/configuration check before claiming telemetry is visible.
[Sensor aging][E13] allows old values to persist: stopping a frame does not
immediately blank the actual radio LCD. OpenRC's wrapper should distinguish
missing/stale input from the last value retained by the firmware.

The [Companion CRSF provider][E14] uses a simulator-specific direct frame path.
Its CRC shortcut must not be represented as physical CRSF transport support.
Validate lengths, ranges and the selected module before injecting any frame.

Reuse OpenRC's sampled battery readings [O5]. Do not populate a radio's own
transmitter-voltage input with the aircraft's flight-pack voltage. In the first
prototype, use a fully defined electric-model battery frame, discover the
sensor, change its value and verify the LCD. Then add one speed/altitude sensor
and a stale-data case. No such prototype has run here.

## Flight controls: logical inputs before independent servos

[FlightSession's input boundary][O8] consumes roll, pitch, yaw, throttle and
optional equipment demands. It adds the current trim policy; the aircraft owns
allocation and actuator behavior. [ControlSurfaces][O9] generates opposite
aileron demands with aircraft-specific down throw, or calculates clipped
pitch-plus/minus-roll elevons.

Therefore, use a verified logical AETR EdgeTX model first, with learned AUX,
one rate/expo owner and one flap/elevator-compensation owner. Unsupported
surface-mixed model files can be viewed or exercised inside the radio simulator
without being admitted for flight. This is a supported subset proposal, not
lossless execution of every imported radio configuration.

Virtual-flight admission binds the model/configuration identity, mapping, signs,
ranges and ownership, and is invalidated by changes. Initial virtual flight
admits neutral EdgeTX pilot trims with OpenRC owning pilot trim; solved launch
trim and rigging offsets remain intact. Physical USB calibration cannot detect
or undo arbitrary transmitter mixing, so it must not be described as enforcing
that same configuration admission automatically.

The [independent-surface candidate][O9] and its [test fixture][O10] do not
establish a ready-made hardware channel route. A future servo mode needs
per-aircraft bindings, endpoint geometry, trim/mix/slew ownership, and declared
checkpoint/replay semantics. Inverting an already clipped mix does not recover
the original independent servo dynamics.

The current external driver [O8] accepts logical commands in a separately
configured controllerless session mode; it also selects simulator-owned flap
compensation. It is not a drop-in live EdgeTX adapter. A helper must enter an
explicit input/session boundary and retain ControllerService ownership.

The [flap-mix test][O11] also shows why settled-output agreement alone is limited:
simulator-owned compensation follows actual flap travel; transmitter-owned
compensation follows the transmitter's timing. Qualify the chosen transient
behavior as well as the final value.

## Pause, failure, reset and replay

Keep this proposed helper contract outside the renderer:

| Event | Required behavior |
| --- | --- |
| Ordinary flight tick | Consume a complete admitted snapshot without blocking the kernel |
| Menu/configuration pause | No flight advance or shared navigation/flight action; explicitly show whether firmware timers continue |
| Helper/device loss or stale control source | Existing pause/disconnect policy; require valid fresh input before taking control again |
| Resume | Recheck source identity/readiness and relevant low-throttle/fresh-OFF gates; discard queued setup actions |
| Accepted restart/restore/aircraft transition | Move to the new session generation; ignore packets from the previous generation |
| Refused reset | Preserve the existing session/helper association; do not reset the helper speculatively |
| Recorded-flight playback | Use recorded post-conditioning inputs and ownership; never query the live firmware clock |

These recommendations follow the session's accepted-tick and transaction
boundaries [O8], [AUX hold checks][O12], and
[flight-log replay implementation][O13]. They are not implemented helper features.

A message sequence and session generation are necessary to tell “unchanged
control” from “old control.” Heartbeat/liveness alone does not prove freshness.
The stable API's change-only channel notifications need an explicit snapshot
and freshness design, especially around reconnect and paused UI interaction.
A steady stick is a required acceptance case: no changed event is not proof of
a stalled runtime. Combine liveness with coherent snapshot age and retain
fresh-low-throttle/fresh-OFF recovery gates.

Exact firmware lockstep is unresolved. Preserve OpenRC's recorded-input replay
contract rather than claim that rerunning wall-clock EdgeTX reproduces it.
If future lessons require synchronized firmware time, investigate it as a
separate capability with explicit clock/reset evidence.

## Configuration import and guided operation

Stable [.etx storage][E15] is ZIP-backed, and its
[bare-YAML importer][E16] contains source-board conversion limitations. A file
that looks like radio settings is not interchangeable with a model YAML file.
Current development reorganizes storage; reuse a parser matched to the selected
target/version rather than combine code and schemas from different branches.

The stable simulator's setRadioData/readRadioData methods are present in its
interface but their inspected implementations are empty [E9]. Do not build the
import flow around their names: use the copied SD/settings paths and prove
actual loading and persistence in the spike.

First produce a read-only report from a copied model: source identity,
inputs/mixes/outputs, curves, endpoints, switches, flight modes and unsupported
fields. Import is not flight admission. A bounded archive/file reader and a
private simulator data directory protect the original model from conversion or
training edits. No automatic firmware flashing or write-back is proposed.

[Package-tools scripting][P1] provides buttons, rotary/touch actions, switches,
analog inputs, channel/mixer queries, screenshots and stdin-driven test scripts.
Its documented channel getter is one-based and RESX-scaled; hardware analog
inputs use a different scale. An adapter must preserve these distinctions.
This is a useful development harness; it supplies neither a Godot streaming
bridge nor an automatically correct lesson.

The [development simulator API][E17] adds asynchronous JSON snapshots of the
color-screen LVGL UI tree. It is unavailable on monochrome targets and is not
the stable 2.12.5 API. Inspect advertised capabilities at startup, and bind
lessons to a radio/firmware identity.

For each of four initial lessons, retain the starting model, action sequence,
expected settings change and channel checks. Examples: channel reversal, expo,
a gear/flap switch and flight-mode selection. A screenshot demonstrates a
screen state; output assertions establish behavior. Extend the already existing
stick/switch setup assistant [O7]. This is an observe–act–verify workflow, not a
claim that an AI automatically understands arbitrary transmitter firmware.

## RadioLink configuration research lead

Official [T12D release notes][t12d-firmware] describe model files accessible in
USB drive mode, with user/system copies and a .dat example. The
[T16D upgrade guide][radiolink-files] identifies the Model directory and tells
users to preserve it. This makes an offline, read-only configuration viewer a
plausible follow-up.

Still unknown: field schema, versioning, checksums, documented parsing rights,
and whether a supported simulator or configuration API exists. Preserve a copied
backup and its firmware identity before attempting interpretation. Do not equate
Lua external-module support or a FreeRTOS/LVGL base with published radio firmware.

The searched manufacturer material verifies USB control and physical receiver
telemetry, but not a PC API to mirror the physical screen or send arbitrary
OpenRC telemetry to it. Those are separate research tasks. No device data was
downloaded, changed or flashed during this investigation.

## Backend choice and distribution

| Candidate | Strength | Remaining cost / gate |
| --- | --- | --- |
| Stable native simulator in local helper | Known target, matching stable configuration/UI, existing LCD/input/telemetry API | Qt/native packaging, channel notification cadence, thread/snapshot correctness |
| Development WASM hosted locally | Direct channel/frame copy exports, shared upstream browser/native work, optional UI tree | Threaded WASI/WAMR, version churn, schema/runtime matching and native packaging qualification |
| Browser simulator embedded as UI | Upstream browser UI and target catalog already exist | OpenRC ships native Godot; browser embedding and cross-origin/thread requirements add another integration boundary |

Recommendation: stable exact-target functionality spike, then a measured runtime
decision for virtual flight. Reuse the same Godot-facing boundary if the backend
changes. Upstream [development build documentation][E18] and [web README][E19]
prove that the WASM/browser implementation exists; they are not proof of OpenRC
compatibility or a released stable backend.

OpenRC declares MIT [O14]; core EdgeTX declares GPL-2.0 [E20]; package-tools
declares GPL-3.0-only [P2]. Keep provenance and assess the actual redistribution
and combination before including code/binaries. The helper boundary is an
engineering choice, not an automatic license exception. New radio images also
need their own provenance and redistribution permission.

## Verification status and next experiments

**Completed here:** source pinning, code-path inspection, official radio/firmware
checks, plan/evidence authoring and independent architecture review. The branch
publication receipt and documentation-only checks are reported with the commit.

**Not completed:** compiling/running either EdgeTX backend, measuring latency or
frame throughput, replaying a virtual-radio flight, importing a real user's model,
and testing physical devices or exported packages.

Independent review corrections were incorporated: distinguish held controls from
stalled output, bind virtual admission to configuration identity, preserve solved
aircraft trim while assigning pilot-trim ownership, and avoid claiming that USB
calibration detects incompatible transmitter mixes. The lead checked the relevant
session, allocation and upstream simulator code before accepting those changes.

Use these existing checks when implementation begins; they were inspected or
identified, not executed in this investigation:

- EdgeTX airplane/switch/rates and profile/calibration tests.
- Flap-mix ownership, control-surface and elevon-model tests.
- Controller integration/pause recovery and AUX pause retention.
- Flight-log inputs and replay integrity.
- Existing overlay checks and the debug bridge for visible/lifecycle inspection.

The [tool index](../../../tools/README.md) and owning plans specify test execution
and shared-host admission. Hardware results must name the radio, firmware, USB
mode, OS, application build and observed mapping.

The smallest next experiments are: exact-target boot/LCD/one-channel/one-sensor;
cadence/freshness comparison; accepted logical AETR input; then paused setup and
disconnect/restart/replay checks. Each produces a separate receipt. Source
support alone cannot close any of those runtime gates.

## Primary source ledger

All GitHub links below are pinned. Manufacturer pages are dated observations.

[openrc]: https://github.com/bultodepapas/OpenRCsimulator/commit/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c
[release]: https://github.com/EdgeTX/edgetx/releases/tag/v2.12.5
[edgetx-main]: https://github.com/EdgeTX/edgetx/tree/3dd6fe069657fcdb3237dec2df61d01c1b53facc
[package-tools]: https://github.com/EdgeTX/edgetx-package-tools/tree/0d1fc38ebd27e75c5a88549b137a5a4626f9e91f
[jumper]: https://www.jumper-rc.com/t18-h7/
[supported]: https://edgetx.org/supportedradios/
[radiolink-comparison]: https://www.radiolink.com/en/comparison_of_aircraft_transmitters
[t16d-manual]: https://www.radiolink.com/en/t16d_manual
[t12d-manual]: https://www.radiolink.com/en/t12d_manual
[t12d-firmware]: https://www.radiolink.com/en/t12d_firmwares
[radiolink-files]: https://www.radiolink.com/en/tutorial_for_T16D_firmware_upgrade
[O1]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/app/render/overlays/transmitter.gd
[O2]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/app/render/overlays/overlay_settings.gd
[O3]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/app/ui/overlays_dialog.gd
[O4]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/app/render/overlays/overlay_manager.gd
[O5]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/app/render/overlays/battery_sensors.gd
[O6]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/app/input/controller_profile.gd
[O7]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/docs/plans/edgetx-airplane-controls.md
[O8]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/app/sim/flight_session.gd
[O9]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/app/physics/control_surfaces.gd
[O10]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/app/tests/test_control_actuators.gd
[O11]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/app/tests/test_flap_mix_ownership.gd
[O12]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/app/tests/test_aux_pause_retention.gd
[O13]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/app/tools/flight_log_cli.gd
[O14]: https://github.com/bultodepapas/OpenRCsimulator/blob/cf03e401fdb3e2af5eb32f91a56462f2ca69ff1c/LICENSE
[E1]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/CMakeLists.txt
[E2]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/targets/t18h7/CMakeLists.txt
[E3]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/targets/simu/CMakeLists.txt
[E4]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/tools/build-companion.sh
[E5]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/simulation/simulatorinterface.cpp
[E6]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/targets/t18h7/hal.h
[E7]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/simulation/widgets/lcdwidget.cpp
[E8]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/simulation/simulatorinterface.h
[E9]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/targets/simu/opentxsimulator.cpp
[E10]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/simulation/simulatormainwindow.cpp
[E11]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/telemetry/crossfire.cpp
[E12]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/telemetry/telemetry_sensors.cpp
[E13]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/radio/src/telemetry/telemetry_sensors.h
[E14]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/simulation/telemetryprovidercrossfire.cpp
[E15]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/storage/etx.cpp
[E16]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/companion/src/storage/yaml.cpp
[E17]: https://github.com/EdgeTX/edgetx/blob/3dd6fe069657fcdb3237dec2df61d01c1b53facc/radio/src/targets/simu/simulib.h
[E18]: https://github.com/EdgeTX/edgetx/blob/3dd6fe069657fcdb3237dec2df61d01c1b53facc/docs/building/index.md
[E19]: https://github.com/EdgeTX/edgetx/blob/3dd6fe069657fcdb3237dec2df61d01c1b53facc/web/README.md
[E20]: https://github.com/EdgeTX/edgetx/blob/0ebe2e98b2085e2251ad6773b26c8a7ab8dd3e99/LICENSE
[P1]: https://github.com/EdgeTX/edgetx-package-tools/blob/0d1fc38ebd27e75c5a88549b137a5a4626f9e91f/docs/Scripting.md
[P2]: https://github.com/EdgeTX/edgetx-package-tools/blob/0d1fc38ebd27e75c5a88549b137a5a4626f9e91f/Cargo.toml
