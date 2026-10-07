# F1 — Standalone controller input report

**Status:** implemented, 2026-10-07; physical-radio validation remains open. No M2 simulation or physics files changed.

## Use

```bash
$(app/get-godot.sh) --path app -- --input-report=input-report.json --t=20
```

Move every stick through its full range. The app writes JSON and exits after the observation window. `--input-report` alone prints JSON to stdout (alongside Godot's banner); `--t` defaults to 10 seconds and accepts a finite positive duration of at most 3600 seconds, rounded to at least one microsecond. Output directories must exist. Invalid/duplicate options, combinations with flight modes and write failures exit nonzero.

The explicit diagnostic branch in `app_root.gd` precedes Home/direct-flight routing. It creates no field, aircraft, simulation, audio, preferences or calibration. Other entry routes retain their existing behavior. Event accumulation is disabled for the measurement and restored on completion or teardown.

## Report contract: `openrc-input-report v1`

| Field | Meaning |
| --- | --- |
| `os`, `os_version`, `godot`, `build` | Platform/engine and existing `BuildInfo.current()` identity. Source runs say `development`; they do not invent a commit. |
| `requested_duration_s`, `observed_duration_s` | Requested window and actual monotonic elapsed time. The last process callback can overrun the request. |
| `devices[]` | One entry per connection session, including initially connected devices, hotplug and disconnected devices. Reused device IDs start new sessions. |
| `guid`, `name`, `raw_name`, `vendor_id`, `product_id`, `is_joy_known` | Godot-reported identity/mapping. Missing platform-specific fields are `null`. No serial numbers are collected. |
| `axes_seen`, `axes_moved` | Seen means at least one event; moved means the observed minimum differs from the maximum. Neither lists all physical hardware capabilities. |
| `axes[]` | Godot axes 0–9, with event count, min/max, first/last callback time and zero-spacing event count. No polling-derived startup zeros. |
| `mean_event_spacing_usec` | `(last_callback - first_callback) / (events - 1)` for one axis and session; `null` with fewer than two events. Interleaved axes never share intervals; batched equal timestamps count as zero. |
| `rejected_events` | Events for unknown/disconnected IDs, invalid axes/values or backward sample clocks. They do not change statistics. |

Times ending in `_usec` are relative to the start of this report. Statistics are bounded aggregates per session/axis, not an unbounded list of raw events. An empty device list or untouched controller is a successful diagnostic observation. Early process termination does not create a completed report.

## Measurement correction

The old F1 row equated mean event spacing with USB report interval. That inference is invalid: `InputEventJoypadMotion` exposes axis/value and device, not a hardware timestamp; the collector timestamps the callback with `Time.get_ticks_usec()`. Engine dispatch, mapping, unchanged values and batching affect the observation. Turning off accumulation does not establish a hardware sampling rate.

The pinned SDL backend also returns VID/PID as decimal **strings**, not integer Variants. The report normalizes valid 16-bit decimal identifiers to JSON numbers; absent or malformed values remain `null`. Tests use the backend's string shape, as well as integers, rather than assuming an integer-only fake device.

Accordingly, the report labels callback timing explicitly. It neither infers RF-module state nor estimates stick-to-screen latency. Actual report timing requires an external capture such as OS input tooling; F6 requires its independent latency experiment. The research's proposed `> 2 ms` RF warning was corrected in the same change.

## Verification

- [53 pure known-answer checks](data.log): independent devices/axes, exact interval means, null/unseen behavior, duplicate connection signals, same-ID replacement, malformed samples and immutable snapshots.
- [18 real-dispatch/route checks](e2e.log) use `Input.parse_input_event` and connection signals with fake metadata providers: initial enumeration, hotplug, reconnect, completed JSON, clock-based deadline and listener/settings cleanup. No real `Input.get_joy_*` query is made for a fake ID.
- Real app-root route with a deliberately missing field path: only a diagnostic node exists, preferences stay untouched, no flight starts.
- [31 Linux CLI checks](cli.log) in separate Godot processes: stdout/file modes, invalid arguments, old artifact preservation on invalid arguments, directory output and `/dev/full` failures. [Example with no devices attached](example-no-device.json) is plumbing evidence, not a compatibility result.
- Full isolated `app/test.sh` passed: 88 GDScript test programs, four aircraft's contracts/trimmed traces, identical 30/60/144 FPS states and no engine errors. [Log](suite.log); exact tested-file hashes: [verification.json](verification.json). This excludes other developers' uncommitted M2/landscape work while retaining the preceding D6b-R1 repair.

The owner's radio/OS/firmware/USB-mode observations still supply D6d/F4 acceptance. Fake devices prove software behavior only.

## Sources and implementation

- Godot [`Input.get_joy_info`](https://docs.godotengine.org/en/stable/classes/class_input.html#class-input-method-get-joy-info): platform-specific raw name and USB IDs; mapping and event accumulation APIs on the same page.
- Godot [`InputEvent`](https://docs.godotengine.org/en/stable/classes/class_inputevent.html) and [`InputEventJoypadMotion`](https://docs.godotengine.org/en/stable/classes/class_inputeventjoypadmotion.html): exposed event fields. Signatures also checked against the local pinned 4.7.2 API cache.
- Godot [4.7.2 SDL backend](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/sdl/joypad_sdl.cpp#L157-L162): decimal-string USB identifiers; independently rechecked after the read-only review caught the original fake-device type assumption.
- [Existing radio/latency knowledge base](../../roadmap-investigations/06-radio-input-servos-latency.md), especially the input chain and independent measurement limits.
- [Collector](../../../../app/input/input_report_data.gd), [runtime/CLI](../../../../app/input/input_report.gd), [entry point](../../../../app/app_root.gd).
