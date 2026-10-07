# DT-00-R2-07 — Apple Silicon thermal and energy soak

2026-10-07 · **Source and code review complete; no native Mac measurement.**

## Question and method

What should count as an Apple Silicon baseline, and how can sustained load,
battery mode, focus, minimization, and App Nap be measured without turning a
single Mac result into an architecture-wide claim? I inspected the current frame
logger, flight pause/audio path, and project settings; consulted Godot 4.7 docs
and Apple product, power-mode, App Nap, and thermal-state docs. No Apple hardware
was run.

## Findings

1. **Reference machine (vendor fact):** the 2020 MacBook Air with M1 has an 8-core
   CPU, 7- or 8-core GPU, 8 GB base unified memory (configurable to 16 GB), and
   Apple describes its design as fanless. This makes an exact M1 Air 8 GB SKU a
   useful first laptop baseline; it does not represent every M1, later Air, or Pro
   model. [Apple M1 Air specifications](https://support.apple.com/en-us/111883), [Apple M1 announcement](https://www.apple.com/newsroom/2020/11/introducing-the-next-generation-of-mac/).
2. **No universal chip ranking:** compare any newer Apple Silicon or Pro-chip
   machine as a separate named system. Record model identifier, chip and core
   counts, RAM, macOS build, display topology/refresh, power adapter state,
   battery percentage, and available Energy Mode. Do not convert results from one
   Air/Pro pair into a blanket M1-or-later claim.
3. **Power and thermals (vendor fact):** Low Power Mode reduces energy use;
   available modes vary by Mac and macOS. Apple exposes system thermal states
   (`nominal`, `fair`, `serious`, `critical`) through `ProcessInfo`, with
   notifications for changes. These are host-level state, not a Godot performance
   guarantee. [Apple Power Modes](https://support.apple.com/en-us/101613), [Apple thermal-state API](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum), [Apple thermal guidance](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/RespondToThermalStateChanges.html).
4. **App Nap is heuristic:** Apple says eligibility considers foreground state,
   visible drawing, event handling, audio, and power assertions; Activity Monitor
   exposes App Nap and Energy Impact. A hidden or minimized window is a test
   condition, not proof App Nap started. Do not add an assertion to keep the
   simulator awake for ordinary flying; record observed App Nap instead.
   [Apple App Nap guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html), [Activity Monitor energy columns](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/MonitoringEnergyUsage.html).
5. **Godot screen-on behavior matters:** Godot documents power-saving prevention
   as enabled by default for a running project to address controller input not
   inhibiting sleep. Record the effective `Display > Window > Energy Saving > Keep
   Screen On` setting in every idle/minimized case; do not mistake this setting
   for measured App Nap or introduce another no-sleep mechanism. [Godot controller guide](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html).
6. **Current app load:** live flight runs the 240 Hz physics session, renders the
   field/aircraft each frame, and synthesizes a 22,050 Hz engine stream in
   GDScript with a 0.15 s generator buffer. On pause/focus loss, the simulation
   stops and engine playback is paused. [Frame logger](../../../../app/main.gd), [engine sound](../../../../app/render/engine_sound.gd),
   [focus pause](../../../../app/sim/simulation.gd).
7. **Available telemetry:** `--frametimes` records monotonic wall intervals,
   engine deltas, Godot FPS/process/physics monitors, physics step time,
   simulation tick/time, and raw samples. Its sample limit is 300 seconds and it
   exits after writing; it cannot by itself provide a continuous 30-minute time
   series. A full soak therefore needs host-side logging or a separately scoped
   bounded logger before claims about the whole soak. [FrameSamples](../../../../app/render/frame_samples.gd),
   [sample collection](../../../../app/main.gd), [Godot Performance](https://docs.godotengine.org/en/4.7/classes/class_performance.html), [Godot Time](https://docs.godotengine.org/en/4.7/classes/class_time.html).
8. **Evidence kind:** frame cadence and process/physics time are measured by the
   logger; Activity Monitor Energy Impact is a system indicator, not watts.
   Battery percentage is coarse. Apple thermal state is system-wide and requires
   host tooling or a native bridge; the Godot 4.7 GDScript APIs reviewed here
   expose no Apple thermal-state method.
   Leave unavailable fields blank rather than infer chip temperature or power
   draw.

## Proposed native gate

- Freeze a signed/exported candidate hash and one actual flight setup: aircraft,
  field, visual defaults, 60 Hz display mode, and control method. Keep active
  flight in the foreground; do not use the scripted visual route as a simulation
  workload.
- On the exact M1 Air 8 GB baseline, run matched battery/Low Power and
  adapter/Automatic cases where available. Record 30 minutes of sustained flight
  for DT-12; run a separate short Home/pause/minimized/focus-away sequence and
  record Activity Monitor's App Nap and Energy Impact state. Compare an advertised
  newer/Pro machine only in its own row.
- Retain raw frame and physics samples, simulation ticks per wall second,
  failures, frame-time percentiles, start/end battery percentage, host Energy
  Impact, and any thermal-state observation with its collection method. Compare
  early and late windows under the same workload. Never present a single run as an
  all-model guarantee.
- Check that focus loss still pauses flight and sound, return never resumes
  automatically, and no sleep policy was introduced just to improve the benchmark.
  If the existing five-minute logger is used, report its limited window separately
  from the 30-minute soak.

## Plan integration and limits

DT-01 should name the exact reference Mac and power/display profile. DT-10/10a can
compare the existing frame and physics metrics; DT-11b owns idle/minimized
changes; DT-12 already calls for a 30-minute soak, which should include this Mac
profile if it is a release target. DT-13 acceptance remains per named hardware.
This review establishes vendor APIs and current code paths only; it contains no
measured temperature, energy, sustained rate, native App Nap state, or pilot
acceptance.

## Sources consulted 2026-10-07

- [MacBook Air (M1, 2020) technical specifications](https://support.apple.com/en-us/111883)
- [Introducing the next generation of Mac](https://www.apple.com/newsroom/2020/11/introducing-the-next-generation-of-mac/)
- [About Power Modes on your Mac](https://support.apple.com/en-us/101613)
- [Apple `ProcessInfo.thermalState`](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum)
- [Respond to thermal-state changes](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/RespondToThermalStateChanges.html)
- [Extend App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)
- [Monitor usage regularly](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/MonitoringEnergyUsage.html)
- [Godot 4.7 controller and joystick guide](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html)
- [Godot 4.7 Performance API](https://docs.godotengine.org/en/4.7/classes/class_performance.html)
- [Godot 4.7 Time API](https://docs.godotengine.org/en/4.7/classes/class_time.html)
