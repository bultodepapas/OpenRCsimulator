# Immersive audio

2026-10-11 · Revision 3 · **Status: AUD-01…05 delivered; software qualification and stereo-speaker acceptance passed.** Dedicated mixer-thread timing and target-platform qualification remain open limitations. Prefix: AUD-.

Owner: audio integration team. Owns `app/audio/`, `app/assets/audio/soundscape/`, `tools/audio/`, `app/tests/test_soundscape.gd`, `test_wildlife.gd`, and `docs/research/audio/AUD-*`. The user confirmed this is the only active audio team. Existing G3b files and experiments are preserved. The lead owns the bounded `main.gd` hook, export notice filters and time-of-day test cleanup adaptation; concurrent shared-file changes are preserved. Simulation, aircraft data, UI, scenery and world-renderer implementations are unchanged by this track. Legacy engine remains available with `--soundscape=legacy`.

## Steps

| Step | Scope | Status / proof |
| --- | --- | --- |
| AUD-01 | Audit, ownership, free sources, native Godot API and licensing | Complete; [sources](research/audio/AUD-01/sources.md), [audit](research/audio/AUD-01/integration-audit.md) |
| AUD-02 | Original layered source library and provenance | Complete; [14 original PCM assets](research/audio/AUD-02/assets.md), generator and export checks |
| AUD-03 | Read-only dynamic mix, spatial environment and aircraft | Complete; [implementation](research/audio/AUD-03/README.md), 76 focused checks and 5 exact simulation parity pairs |
| AUD-04 | Gameplay mixer capture, regression, profiling and listening | Complete with documented limits: [evidence](research/audio/AUD-04/README.md), nine final native captures, stereo-speaker acceptance, full suite (185 test scripts); dedicated mixer budget unqualified |
| AUD-05 | Varied birds, crows, distant dogs, nocturnal owls and cricket colonies | [Qualification passed](research/audio/AUD-05/README.md): speaker feedback “Natural and nicely spaced”, 111 audio checks, 5 exact physics pairs, 3 rendered WASAPI captures, 29-source export and frozen full suite (189 scripts) |

## Quality targets and budgets

- Aircraft is the foreground cue; environmental beds remain quiet, with occasional localized detail and breathing space. No unrelated flyby one-shots: the flown source produces the pass.
- Independent wind layers follow actual wind/gust speed; foliage follows wind at field tree positions. Day birds/crows give way to owls and warm-night crickets; sparse distant dogs, varied phrases, occasional replies and aircraft disturbance create space between events. Strong wind reduces activity.
- Distinct combustion, propeller, electric and turbine sources. RPM controls pitch; throttle/load estimate and airspeed control timbre. No guessed acoustic calibration is represented as measured physics.
- Continuous gain/pitch/filter transitions; fade pause/resume and restart; bound Doppler and reset its observer on camera cuts. Bounded vegetation screening, not invented building collision.
- Mixer peak at most -1 dBFS with a final safety limiter; typical mix below -6 dBFS. No clipping, dropped captured frames, obvious loop seam, repeated bird phrase back-to-back, or old-flight audio after restart.
- At most 14 voices, 8 MiB decoded source PCM, no runtime sample synthesis, no audio writes into simulation or shared RNG. Update p95 target under 0.5 ms and mixer under 1 ms on this host; report actual conditions, do not claim target-machine acceptance.
- Exact simulation checkpoints with/without audio; native 30/60/144 FPS captures, camera changes, calm/gusts, fleet propulsion, pause/restart/teardown. Actual gameplay listening is mandatory for perceptual acceptance; software meters alone cannot close it.

## Coordination record

Initial dirty-tree audit: UI-21 shell, EL2a-P3 physics, L4c/L9e/VQ-04a landscape, projected shadows and G3b research are in flight. All are excluded from audio ownership. Bounded Luna/max assignments: source/license research, offline original source generation, read-only integration audit; lead reviews all output and owns runtime integration. No commits or staging of others' files.

Delivered controls: default on in normal physics flight; `--soundscape=off` disables flight ambience too; `--soundscape=legacy` selects the preserved engine; `--audio-seed=<integer>` pins ambience variation. [Tool commands](../tools/audio/README.md). Speaker preference and final feedback are recorded in AUD-04.
