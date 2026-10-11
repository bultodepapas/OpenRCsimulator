# Immersive audio

2026-10-11 · Revision 1 · **Status: implementation and qualification in progress.** Prefix: AUD-.

Owner: audio integration team. Owns `app/audio/`, `app/assets/audio/soundscape/`, `tools/audio/`, `app/tests/test_soundscape.gd`, and `docs/research/audio/AUD-*`. Main-line G3b retains `app/render/engine_sound.gd`, `engine_audio.gd`, `engine_voice.gd` and its experiments. Do not modify simulation, aircraft data, UI, scenery, or world renderers. The lead owns a minimal, additive `main.gd` hook; preserve concurrent changes and re-read before applying it. Legacy engine remains available for G3b qualification with `--soundscape=legacy`.

## Steps

| Step | Scope | Status / proof |
| --- | --- | --- |
| AUD-01 | Audit, ownership, free sources, native Godot API and licensing | In progress; [sources](research/audio/AUD-01/sources.md) |
| AUD-02 | Original layered source library and provenance | In progress; [assets](research/audio/AUD-02/assets.md) |
| AUD-03 | Read-only dynamic mix, spatial environment and aircraft | In progress |
| AUD-04 | Gameplay mixer capture, regression, profiling and listening | Pending; human perceptual acceptance remains distinct from software verification |

## Quality targets and budgets

- Aircraft is the foreground cue; environmental beds remain quiet, with occasional localized detail and breathing space. No unrelated flyby one-shots: the flown source produces the pass.
- Independent wind layers follow actual wind/gust speed; foliage follows wind at field tree positions. Birds vary phrase, timing, pitch and position, decrease in strong wind and at night.
- Distinct combustion, propeller, electric and turbine sources. RPM controls pitch; throttle/load estimate and airspeed control timbre. No guessed acoustic calibration is represented as measured physics.
- Continuous gain/pitch/filter transitions; fade pause/resume and restart; bound Doppler and reset its observer on camera cuts. Bounded vegetation screening, not invented building collision.
- Mixer peak at most -1 dBFS with a final safety limiter; typical mix below -6 dBFS. No clipping, dropped captured frames, obvious loop seam, repeated bird phrase back-to-back, or old-flight audio after restart.
- At most 14 voices, 8 MiB decoded source PCM, no runtime sample synthesis, no audio writes into simulation or shared RNG. Update p95 target under 0.5 ms and mixer under 1 ms on this host; report actual conditions, do not claim target-machine acceptance.
- Exact simulation checkpoints with/without audio; native 30/60/144 FPS captures, camera changes, calm/gusts, fleet propulsion, pause/restart/teardown. Actual gameplay listening is mandatory for perceptual acceptance; software meters alone cannot close it.

## Coordination record

Initial dirty-tree audit: UI-21 shell, EL2a-P3 physics, L4c/L9e/VQ-04a landscape, projected shadows and G3b research are in flight. All are excluded from audio ownership. Bounded Luna/max assignments: source/license research, offline original source generation, read-only integration audit; lead reviews all output and owns runtime integration. No commits or staging of others' files.
