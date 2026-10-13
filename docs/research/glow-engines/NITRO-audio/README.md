# NITRO audio consumer

**Status:** procedural consumer implemented; timbre and level are authored. No engine recording, microphone measurement, mounted-vibration capture, or pilot listening has qualified these sounds.

## Interface

[`app/audio/glow_voice.gd`](../../../../app/audio/glow_voice.gd) consumes a detached telemetry dictionary with explicit `family` (`glow_2t` or `glow_4t`), accepted `rpm`, `running`, and `firing_fraction`. The flight adapter adds `max_rpm`, `load`, `throttle`, `blade_count`, and the optional monotonic crankshaft `phase_revolutions` anchor from `FlightSession.glow_state()`. The legacy `glow_prop` label is not treated as a cycle selector.

`GlowVoice.render(rpm, max_rpm, frames)` returns a `PackedVector2Array` and matches the per-voice renderer signature consumed by `AudioStreamGeneratorPlayback`. Call `set_telemetry()` first. `render_telemetry(snapshot, frames)` is the direct offline/test entry point. Each instance owns its phase and missed-fire accumulator; it does not call physics, mutate session state, or use an RNG.

The consumer renders single-cylinder 2T exhaust opportunities at shaft order 1 and true 4T opportunities at shaft order 0.5. It keeps a rich 2T labelled `glow_2t` and schedules its `firing_fraction` as deterministic missed opportunities. The 4T layer adds a cam/valve component at half crank order. Mechanical shaft tone and propeller blade-pass tone are separate: blade-pass frequency is `rpm × blade_count / 60` for both families. A throttle cut fades combustion over 6 ms while shaft and propeller tones continue at the physical RPM; restart restores combustion without resetting their phase.

The 6 ms fade, spectral weights, layer gains, load response, and soundscape level law are authored presentation choices. They are not engine-specific acoustic or vibration measurements. `phase_revolutions` anchors phase when a voice starts; the renderer then advances phase continuously from accepted RPM so adjacent generator blocks do not reset to a new phase.

The soundscape creates a procedural `AudioStreamGenerator` player on the existing aircraft bus for explicit glow-family profiles. Its legacy motor and propeller loops are omitted for those profiles to prevent duplicate firing and blade orders. Electric, turbine, legacy piston, airframe, environment, and wildlife routes remain with their current owners.

`FlightAudio.snapshot()` takes the accepted `FlightSession.glow_state()` telemetry when available and fills remaining presentation inputs from accepted RPM, load, throttle, and the explicit profile family. The generator uses the same aircraft spatial bus, source position, screening, attenuation, and computed Doppler pitch as the other aircraft voices. A throttle cut changes the combustion envelope only; it does not stop the generator or reset shaft phase.

## Software evidence

Run the spectral and lifecycle checks from `app/`:

```powershell
& ..\.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/test_glow_audio.gd
```

The test checks the 2T/4T firing lines, rich-2T subharmonic with unchanged family, equal-RPM blade-pass order, cut/restart separation, bounded samples, and block-to-block phase continuity. Add `-- --write-glow-audio-wavs` to write the direct renderer's native 16-bit mono PCM clips and capture the integrated soundscape with `AudioEffectCapture`; captured output includes full-fire, throttle-cut, restart, and true-4T segments. Artifacts are written under Godot's user-data directory in `glow_audio_artifacts/`. Direct renderer clips do not exercise the mixer; `AudioEffectCapture` checks software mixer output but does not establish speaker output, room propagation, an installed engine, or human perception. A Dummy-driver capture proves only the software path.

The current implementation has no tach-synchronized real-engine recordings. Physical qualification remains open under [the NITRO engine plan](../../../plans/RC_NITRO_ENGINE_REALISM_PLAN.md#evidence-and-calibration-protocol) and [AUD-09](../../../plans/audio-realism.md#aud-09).
