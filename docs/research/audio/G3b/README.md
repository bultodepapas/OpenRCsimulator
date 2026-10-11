# G3b — Responsive procedural engine audio

2026-10-11 · **Status: implementation and qualification in progress.** Existing G3 namespace; main-line audio adapter work.

## Audit and scope

Baseline `b5febac`: audio fills a 4095-frame generator at 22050 Hz (185.7 ms) every render frame and evaluates six sine functions per sample. Current menu-stack/UI-21 edits and electric EL2a-P3 work are separate. Own `engine_sound.gd`, new audio-only renderer/adapter, focused tests and this evidence; limit `main.gd` integration to audio creation/refill/restart. No simulation, aircraft data, menus, world or visual assets are changed. Freeze separate baseline/candidate copies for qualification; preserve other contributors' working files.

During qualification, the separate [AUD soundscape track](../../../AUDIO-PLAN.md) appeared and explicitly reserved G3b ownership. Preserve its additive default path and shadow/render hooks. G3b integrates only with the retained **`--soundscape=legacy`** generator route; AUD owns its sample-based default voices. No AUD files are edited. This coordination keeps the implementations and their acceptance claims separate.

Deliver a target-filled generator, efficient phase-continuous synthesis, and detached accepted-tick RPM observation. Retain the existing placeholder timbre and positional attenuation. G3a's full sound history, G3c's calibrated source orders, G3d propagation, electric/turbine acoustics and measured physical sound remain separate.

## Acceptance declared before implementation

- Mixer response to a commanded RPM step below 70 ms at 30/60/144 FPS; distinguish waveform observation from output-device latency.
- Native target queue at most 50 ms plus one sample; no steady-run underruns over ten seconds at each rate after explicit startup warmup. Qualification found that Dummy requires a separate large-burst reserve; this exception is measured below, not native latency acceptance.
- Synthesis below 10 ms CPU per second of 22050 Hz audio on the measured host; report baseline/candidate costs and table initialization separately.
- Preserve fundamental pitch, bounded samples and block continuity; avoid aliasing above Nyquist and DC sound at stopped RPM.
- Pause/resume, flight restart and checkpoint restoration discard stale sound when needed; multiple voices have independent state.
- Read-only accepted-state snapshots; exact simulation state with sound enabled/disabled; full `app/test.sh` regression and real mixer checks pass without engine errors.

## Sources and limitations

The [existing audio investigation](../../roadmap-investigations/10-audio-perception-presentation.md) supplies the project rationale. Godot documents [generator buffering](https://docs.godotengine.org/en/stable/classes/class_audiostreamgenerator.html), [available frames and underrun counters](https://docs.godotengine.org/en/stable/classes/class_audiostreamgeneratorplayback.html), and [driver output latency](https://docs.godotengine.org/en/stable/classes/class_audioserver.html). Queue depth, mixer response and speaker onset are distinct observations. A software mixer cannot establish physical audibility or validate engine timbre. The legacy source model remains a placeholder, especially for turbines; that route excludes electric aircraft. AUD owns the separate electric/default soundscape sources.

Pinned source: [generator](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/audio/effects/audio_stream_generator.cpp), [128-frame resampler](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/audio/audio_stream.h), [4096-frame Dummy burst](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/audio/audio_driver_dummy.h), and [driver period observation](https://github.com/godotengine/godot/blob/4.7.2-stable/servers/audio/audio_server.cpp). The first fixed 50 ms candidate underruns with Dummy; the final adapter measures the driver period and reserves its burst plus one resampler block. Native refills use 35 ms at short frame intervals and return to 50 ms after slower frames. No global audio settings or project settings change.

## Implementation

`engine_voice.gd` owns per-player phase, frequency and amplitude. Seven shared read-only 4096-point tables retain the D5 harmonic weights, with only below-Nyquist harmonics; linear interpolation agrees with the independent analytic waveform within 1e-5. A declared 3 ms presentation ramp smooths RPM/level transitions. Zero RPM decays to silence instead of leaving DC.

`engine_audio.gd` owns queue accounting and a three-scalar accepted-tick RPM observation. It never changes physics arrays, commands, clocks or data. Pause/resume replaces queued sound, including the no-`stepped` checkpoint-restoration route; reset retains the application's stop/play lifecycle. Retain playback identity, not a playback reference, so the adapter does not keep old playbacks alive. Five UI flight cycles retain identical node counts and free all flight/audio nodes. Main integration replaces only audio creation/refill/restart and removes its redundant phase state. Immediate process exit can still report an engine playback warning; the unmodified Windows baseline reproduces it too. It is distinct from sustained-cycle lifetime checks.

The final lifecycle review also found a source-ownership gap: Godot's generator playback stores a raw stream pointer while the server owns an asynchronously retired playback. Each new playback now retains its stream in metadata; the stream does not retain the playback. Weak-reference checks establish both source survival after node removal and release without a cycle, and an unowned-source defect fails that check. This fixes the demonstrated ownership gap. An intermittent integrated UI-help stop is retained as a diagnostic; source inspection suggests this gap could explain it, but a single isolated repeat did not establish causality. Immediate exit can retain both the playback and its pinned source until engine shutdown; sustained-cycle checks must be distinguished from that diagnostic warning.
