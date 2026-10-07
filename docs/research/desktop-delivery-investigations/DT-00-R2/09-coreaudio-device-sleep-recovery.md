# DT-00-R2-09 — CoreAudio device switching and sleep recovery

2026-10-07 · **Source and code review complete; audible route/sleep behavior is unmeasured.**

## Question and method

What does the current Godot/CoreAudio path expose when macOS switches outputs or
sleeps, and what should the native acceptance test measure for generated engine
audio and clock continuity? I inspected the sound generator, frame pump,
simulation pause path, and DT-00-R1 lifecycle audit; consulted Godot 4.7 APIs, the
pinned 4.7.2 CoreAudio source, and Apple Core Audio/App Nap docs. No physical
output, Bluetooth headset, or sleep/wake cycle was tested.

## Findings

1. **Pinned macOS backend:** Godot 4.7.2 uses CoreAudio for macOS audio. Its
   CoreAudio driver registers a listener for the system default output device and,
   when OpenRC uses `Default`, calls `set_output_device("Default")` on a
   default-output change. The driver code attempts a route change, not proof that
   sound resumes cleanly on each output. [Godot feature list](https://docs.godotengine.org/en/4.7/about/list_of_features.html), [pinned Godot 4.7.2 callback](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/coreaudio/audio_driver_coreaudio.mm#L58-L67).
2. **Sample-rate observation:** the pinned driver reads the initial default
   device's nominal sample rate and uses it as its mix rate; it derives its output
   buffer frames from configured latency. Its default-device callback changes the
   current output device. Whether a switch to a device with a different
   rate/latency updates every relevant stream property smoothly must be measured;
   the source alone does not certify this. [Pinned CoreAudio initialization](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/coreaudio/audio_driver_coreaudio.mm#L78-L164).
3. **GDScript metrics:** `AudioServer` exposes current driver name, selected
   output name/list, server output mix rate, and effective output latency.
   `get_output_latency()` is driver/OS-dependent and should not be sampled every
   frame. Godot's documented `AudioServer` signals are bus-layout and bus-renamed;
   there is no GDScript output-device-changed signal. Record system Audio MIDI
   Setup's selected device and rate separately; `AudioServer.get_mix_rate()` is
   the engine output mix rate, not independent proof of the device's physical
   rate. [Godot AudioServer 4.7](https://docs.godotengine.org/en/4.7/classes/class_audioserver.html), [Apple audio hardware](https://developer.apple.com/documentation/coreaudio/audiohardwaredevice).
4. **Generator metrics:** `AudioStreamGeneratorPlayback.get_skips()` counts
   generator-buffer underruns and resets at playback start.
   `get_frames_available()` is free generator-buffer capacity; `can_push_buffer()`
   reports whether a requested push would overflow. Godot exposes no corresponding
   CoreAudio/device underrun counter here. A zero skip count cannot prove that an
   output endpoint never muted, dropped, or delayed audio. [Godot playback API](https://docs.godotengine.org/en/4.7/classes/class_audiostreamgeneratorplayback.html).
5. **Current sound pump:** OpenRC fixes generator rate at 22,050 Hz and buffer
   length at 0.15 s. Every active rendered frame, GDScript fills all frames
   reported available; pause sets `stream_paused` and stops draining/updating it.
   This creates a testable hypothesis that queued samples and phase may be stale
   at resume; it is not an observed Mac defect. [Engine sound](../../../../app/render/engine_sound.gd), [flight sound update](../../../../app/main.gd),
   [Godot generator docs](https://docs.godotengine.org/en/4.7/classes/class_audiostreamgenerator.html).
6. **Focus and simulation time:** focus-out pauses the simulation, and the
   interactive root opens the pause menu; the pilot must explicitly continue after
   return. The fixed-step simulation clock is `tick * dt`; trace samples arrive on
   steps. Do not assume macOS sleep always sends a usable desktop suspend callback
   or that `Time.get_ticks_usec()` includes time spent asleep: Godot documents
   monotonic/nondecreasing behavior, not sleep semantics. [Simulation](../../../../app/sim/simulation.gd),
   [app root](../../../../app/app_root.gd), [trace writer](../../../../app/sim/trace.gd), [Godot Time](https://docs.godotengine.org/en/4.7/classes/class_time.html), [R1 lifecycle audit](../DT-00-R1/06-native-close-suspend-audio.md).
7. **App Nap is not a substitute for a pause test:** Apple may throttle a
   nonforeground app based on visibility, drawing, event, audio, and assertion
   state. Record Activity Monitor's observed App Nap/Energy Impact in the
   minimized/focus-away case; don't assert wake prevention to hide the result. A
   minimized window, focus loss, lid close, and explicit system sleep are distinct
   cases. [Apple App Nap guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html).

## Proposed native gate

- On the same frozen app hash, record OS build, driver,
  `AudioServer.output_device`, output list, mix rate, effective latency
  before/after each transition, `AudioStreamGeneratorPlayback.get_skips()`,
  generator free frames, simulation tick/time, and trace row count. Sample
  effective latency at case boundaries, not each frame. Record actual hardware
  rate/device in Audio MIDI Setup where available.
- Compare built-in speakers, a wired 3.5 mm or USB output, and Bluetooth
  headphones. Switch the system default while Home, live flight, and paused flight
  are open; test unplug/replug and return to `Default`. Repeat at ordinary device
  rates only, recording the actual selected rate rather than assuming 44.1/48 kHz.
- Exercise active flight → focus away → focus return, minimize/restore, and
  explicit sleep/wake separately. Before and after, compare an external wall-clock
  interval with `Time.get_ticks_usec()`, `sim.tick`, `sim.time()`, and trace rows.
  Require the app to remain paused until Continue, with no physics catch-up jump
  or uncontrolled throttle. Record audible gap, stale pitch, silence, crackle, and
  time until sound is restored; optional external recording is needed to quantify
  acoustic onset/latency.
- A `get_skips()` increase is evidence of a generator underrun only. An unchanged
  counter plus audible output failure is still a failure; no GDScript metric
  certifies Bluetooth codec delay or CoreAudio endpoint continuity.

## Plan integration and limits

DT-05a owns native focus, sleep/wake, output-switch, and trace lifecycle behavior;
DT-10a qualifies app clocks and sampling; DT-11b owns minimized idle policy; DT-12
repeats the package cases during its soak. No native extension or user-selectable
output setting follows from this source review. The pinned CoreAudio callback
improves the implementation hypothesis over a no-hotplug assumption, but only a
real Mac and physical device establish recovery.

## Sources consulted 2026-10-07

- [Godot 4.7 feature list](https://docs.godotengine.org/en/4.7/about/list_of_features.html)
- [Godot 4.7 AudioServer](https://docs.godotengine.org/en/4.7/classes/class_audioserver.html)
- [Godot 4.7 AudioStreamGenerator](https://docs.godotengine.org/en/4.7/classes/class_audiostreamgenerator.html)
- [Godot 4.7 AudioStreamGeneratorPlayback](https://docs.godotengine.org/en/4.7/classes/class_audiostreamgeneratorplayback.html)
- [Godot 4.7 Time](https://docs.godotengine.org/en/4.7/classes/class_time.html)
- [Godot 4.7.2 CoreAudio driver: output change](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/coreaudio/audio_driver_coreaudio.mm#L58-L67)
- [Godot 4.7.2 CoreAudio driver: initialization](https://github.com/godotengine/godot/blob/4.7.2-stable/drivers/coreaudio/audio_driver_coreaudio.mm#L78-L164)
- [Apple Core Audio device API](https://developer.apple.com/documentation/coreaudio/audiohardwaredevice)
- [Apple App Nap guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)
- [DT-00-R1 native close, suspend, focus, and audio lifecycle](../DT-00-R1/06-native-close-suspend-audio.md)
