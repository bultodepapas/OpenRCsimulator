# G3b — Responsive procedural engine audio

2026-10-11 · **Status: bounded generator milestone delivered and software-qualified. Physical acoustics, speaker onset and other native drivers remain open.** Existing G3 namespace; main-line audio adapter work.

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

## Qualification results

Host: Windows, Ryzen 9 5900X, pinned Godot `4.7.2.stable.official.ed1daf0bf`; native WASAPI at 48000 Hz, configured latency 15 ms, reported latency 10 ms, no override. Dedicated capture precedes muted Master. Final source-hashed runs after the lifetime correction measured:

| Render FPS | Request → mixer capture | Maximum queue | Steady skips (10 s) |
| --- | --- | --- | --- |
| 30 | 54.41 ms | 50.02 ms | 0 |
| 60 | 53.68 ms | 35.01 ms | 0 |
| 144 | 54.84 ms | 35.01 ms | 0 |

All native runs contain nonzero audio and zero capture loss. Earlier repeats retain phase-dependent results (request → capture 37.9–64.9 ms). The original native baseline measured 192.93 ms and is rejected by the same reader. The 1024-frame spectral window and 256-frame hop limit resolution; reported device latency is an estimate, not speaker onset. Dummy's 98.68 ms reserve produces zero steady skips but deliberately does not qualify the native latency gate. [Mixer artifacts](mixer/).

Warm seven-run elapsed synthesis median: 6.266 ms per second of mono audio, 8.512 ms for the stateful stereo renderer; one-time table preparation 13.008 ms. Earlier baseline medians were 15.490 ms and, under concurrent test load, 24.206 ms. Timings are indicative host measurements; the noisy paired observer deltas do not establish a tick-cost improvement or close the original-target 500 µs gate. All 20 observer benchmark pairs retain exact complete simulation endpoints. [Performance](performance/).

Source lifetime: 50 voices on each driver retain their sources for every still-live playback; all pairs release within two WASAPI / three Dummy render frames, node count returns to baseline, and drained runs have no exit warning. Immediate-quit control reproduces the deferred playback/source warning pair. Dynamic resources are checked with WeakRefs, not ResourceCache counts. [Lifecycle evidence](lifecycle/).

Software checks: **223 focused audio assertions**, five real defects rejected (phase reset, stopped DC, missed endpoint, stale resume, unowned source), and exact complete simulation checkpoints for all four aircraft under 30/60/144 FPS refill grouping. The final frozen app snapshot, including UI-21 and EL2a-P3 integration, passes full `app/test.sh` with exit 0: guards, every-script parsing, unit/UI/input tests, goldens, all-aircraft trim traces, fixed-rate flights, model contracts and ground verification. [Full log](full-suite.log), [focused checks](focused/), [summary and source inventory](verification.json), [owned source hashes](source-sha256.json).

After installation, the current shared tree passes actual Home → Fly → pause/resume → restart → End checks for **legacy/on/off** routes; G3b receives accepted physics samples, AUD remains the default, and off remains silent. Crash presentation is explicitly off in these route fixtures while CR work is active. Shared `main.gd` changes preserve AUD and projected-shadow hooks. [Integration logs](integration/). Later concurrent CR/visual edits are not claimed as part of the frozen full-suite qualification.

Initial mounted-Windows baseline testing stopped at the input-report CLI fixture; native Linux snapshots avoid that environment issue. One later integrated run stopped during UI-help teardown without an engine error; its isolated repeat, final full regression and lifetime stress pass. The diagnostic [stopped run](accepted-suite.log), [isolated repeat](ui-help-repeat.log) and [unmodified baseline exit warning](baseline-e2e-input-verbose.log) remain available. Do not infer physical validation or a universal timing guarantee from these software results.

Reproduce with the [G3b tools](../../../../research/audio/g3b/README.md). Ready commit message: `G3b: qualify target-filled legacy engine audio; proof: full app suite exit 0, 223 assertions, five defects, native FPS response and source-lifetime checks`.
