# CR-02a — Bounded sample-based crash audio

2026-10-11 · **Status:** implemented and native-tested; production-scene integration and combined Master capture passed in [CR-22a](../CR-22a/README.md). Evidence belongs to **CR-02a**.

## Runtime contract

[`crash_audio.gd`](../../../../app/render/crash/crash_audio.gd) owns one dedicated `OpenRC Crash FX` bus routed to Master. It has a `-1.25 dBFS` hard limiter and eight spatial voices: seven pooled one-shots plus one fire loop. The module does not alter Master or shared soundscape buses. Its public calls are `setup()`, `impact(position, severity, turbine)`, `secondary(position, strength)`, `update(delta, paused, fire_strength)`, `reset()` and `shutdown()`.

`impact` requires `valid=true` and accepts the severity result's class, normalized severity and surface label. Those fields choose a presentation mix only; `energy_j` is not converted into physical loudness or structural damage. A turbine flag selects an authored rundown layer. The caller supplies fire strength separately from fuel/ignition physics; impact class alone never starts fire. Secondary hits are rate-limited to one per 75 ms. `paused` means user/menu pause, not the post-crash hold; active one-shots are paused and muted, while the fire loop fades toward silence.

## Verification

- Godot **4.7.2.stable.official.ed1daf0bf** parsed and ran the focused test without engine errors.
- WASAPI native capture with a current camera/listener recorded **147,456 frames**, peak **0.865965 linear (-1.25 dBFS)** after the dedicated crash-bus limiter ([log](../CR-22a/evidence/crash-bus-native.log)). The capture contained the layered event. The separate CR-22a production captures measured the sum at Master with other soundscape buses.
- The native run passed **18 checks**: bus isolation, limiter, surface aliases, invalid-event gating, layer count, primary-event bound, pause/resume, separate fire input, secondary voice bound, reset/shutdown and captured peak.
- The headless `Dummy` driver passed **12 setup/lifecycle checks**. It explicitly skips playback and peak capture because Dummy does not render event audio.
- `python research/crash-damage/cr-02a/generate_assets.py --verify` reproduced the WAV bytes and all manifest hashes.
- The WAVs and mix have not been listened to or judged for realism.

Run the native evidence on Windows with an available WASAPI output device:

```powershell
.tools/Godot_v4.7.2-stable_win64_console.exe --audio-driver WASAPI --path app --script res://tests/test_crash_audio.gd
```

The headless setup/lifecycle check is:

```powershell
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script res://tests/test_crash_audio.gd
```

## Sources and limits

All included assets are original and MIT-licensed; details and hashes are in [`research/crash-damage/cr-02a/README.md`](../../../../research/crash-damage/cr-02a/README.md) and `app/assets/audio/crash/sources.json`. Kenney's [Impact Sounds pack](https://kenney.nl/assets/impact-sounds) was checked as a CC0 alternative, but no third-party audio was selected. Engine behavior was checked against the official [Godot 4.7 AudioStreamPlayer3D](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer3d.html), [AudioEffectHardLimiter](https://docs.godotengine.org/en/4.7/classes/class_audioeffecthardlimiter.html), [AudioEffectCapture](https://docs.godotengine.org/en/4.7/classes/class_audioeffectcapture.html), [AudioServer](https://docs.godotengine.org/en/4.7/classes/class_audioserver.html) and [AudioStreamWAV](https://docs.godotengine.org/en/4.7/classes/class_audiostreamwav.html) references. The repository pins Godot 4.7.2; its [official maintenance release notes](https://godotengine.org/article/maintenance-release-godot-4-7-2/) report no known compatibility break from 4.7.1.

These sounds are presentation cues, not an acoustic model of a particular RC airframe. This focused peak evidence covers the dedicated bus; CR-22a records combined Master-bus headroom for four production-scene crash scenarios.
