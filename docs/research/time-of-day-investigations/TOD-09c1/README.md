# TOD-09c1 — Progressing visual history and checkpoint contract

**Status:** implemented and software-verified. Visible progression is not enabled by this slice.

## Boundary

TOD-09a supplies exact solar anchors; TOD-09b updates lighting in place. Before a live controller can combine them, recordings must distinguish the currently resolved civil time from the configured start selection used by Restart. Rate changes must retain fractional ticks rather than round to a whole second.

This slice adds an explicit v2 visual timeline and paired checkpoint. Existing v1 timelines and checkpoints keep their fixed-time semantics. No physics payload, weather model, preferences, UI, CSV columns or live lighting cadence changes.

## Contract

- Solar history uses the existing `openrc-solar-clock v1` at 240 Hz with rates 0/1. Timeline events are ordered by tick; array order resolves equal ticks.
- Explicit configuration edits reset the fraction and establish the next restart selection. Rate edits preserve the resolved civil instant and fractional phase without replacing that selection.
- Serialized rate events must agree with the preceding clock. A valid configuration hash alone cannot authorize a hidden time jump.
- A v2 paired checkpoint verifies the solar frequency against the physics snapshot's `simulation.dt`, preserves native physics bytes, and rejects future visual events.
- Envelope and timeline versions must agree. Old physics-only artifacts retain explicit legacy fallback.
- The current Main controller refuses v2 restoration before changing physics, lighting, recording or input ownership. TOD-09c2 will remove that guard when it implements progression, configured-start restart behavior and calendar-limit handling together.

## Next integration

TOD-09c2 owns the live 1× controller, Home/Pause/CLI rate selection, restart and recording integration, explicit stop/reselection behavior at the calendar limit, and measured lighting-update scheduling. Its acceptance includes pause/focus/crash behavior and equal-tick frame-rate parity. Target-GPU and pilot acceptance remain separate.

## API and serialization

`VisualTimeline.create(config, anchor_tick)` still creates v1. `create_progressing(config, anchor_tick, rate)` explicitly creates v2. `append_rate_edit(timeline, tick, rate)` promotes a v1 history without discarding prior selections. `append_config_edit`, `validate` and `evaluate` dispatch by the serialized version.

The v2 timeline contains `format`, `anchor_tick`, `ticks_per_second`, `initial` and `events`. The initial record contains a solar `clock`, normalized `config_sha256` and lighting `profile`. Each event adds `tick` and `kind` (`config` or `rate`) to those fields. Evaluation returns the resolved config, profile, rate, tick, timeline anchor, `subsecond_ticks`, and `configured_start`. The latter is derived from the latest explicit selection, not stored as a second mutable copy.

The v2 checkpoint keeps the same native envelope fields and SHA-256 payload binding as v1, with an explicit new format. Only v2 timelines use v2 envelopes. The physics owner's full checkpoint validator still governs physical state restoration; this envelope validates visual compatibility and timestep agreement without rewriting simulation data. Native Variant serialization remains required for exact physics bits; timeline JSON round-trips support trace metadata.

At the supported calendar boundary, clock evaluation and edits that require an out-of-range prior instant fail explicitly. This slice does not clamp time or invent a controller recovery policy.


## Verification

Pinned engine: Godot 4.7.2 (`ed1daf0bf`). Focused suites pass:

| Suite | Checks | Purpose |
| --- | ---: | --- |
| `test_time_of_day_timeline.gd` | 55 | v2 history, mixed JSON round-trip, calendar transitions, forged events, ordering and v1 promotion |
| `test_time_of_day_checkpoint_v2.gd` | 36 | native v2 envelope, phase/restart state, frequency and version rejection |
| `test_visual_timeline.gd` | 53 | existing fixed-time history contract |
| `test_visual_checkpoint.gd` | 40 | existing paired/legacy compatibility |
| `test_time_of_day_checkpoint.gd` | 48 | real Main restore behavior and atomic refusal of both running and stopped v2 histories |
| `test_time_of_day_clock.gd` | 1,656 | exact solar clock and independent calendar fixtures |

Full `app/test.sh` passed with exit 0: all 159 GDScript test programs, model contracts, trace/CLI regressions, trimmed flights, 30/60/144 FPS state equality, and ground-contact checks. See [full-regression.log](full-regression.log). A final [resource import](import.log) also passed without engine errors. These checks establish serialization and restoration boundaries; they do not establish live progression cadence, target GPU performance or pilot acceptance.

Focused output is retained in [focused-tests.log](focused-tests.log). An independent read-only review found no additional correctness issues in v1 compatibility, v2 transition continuity, schema handling, timestep binding or Main's pre-mutation refusal. During implementation review, the top-level frequency validator was corrected to accept the exact numeric value 240 after JSON parsing, consistent with the clock validator; mixed-event JSON regression coverage protects that boundary.
