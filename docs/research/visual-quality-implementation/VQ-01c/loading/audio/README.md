# DT-11a / DT-12 — distinguish audio retirement from retained scene state

2026-10-14. Follow-up to the [night-kit/package lifecycle run](../night-kit/README.md).
The two exit warnings were reproduced independently using the lake's actual MP3 and
an `AudioStreamPlayer3D`. The loading probe now verifies audio retirement after its
timed samples instead of quitting after an arbitrary two process frames. Production
audio, application quit behavior, physics and rendering are unchanged.

## Attribution

The isolated probe creates and frees 30 successive lake ambience players, observes
their streams/playbacks through weak references, and records every cycle. Three fresh
processes per variant on Windows / Godot 4.7.2 / Dummy audio gave:

| Teardown variant | Exit-warning processes | Live stream/playback references after final two frames | After extra 200 ms |
| --- | ---: | --- | --- |
| Queue free only | 2/3 | 6, 2, 6 | Not sampled |
| Stop, clear stream, queue free | 3/3 | 8, 4, 2 | Not sampled |
| Queue free, then allow mixer retirement | 0/3 | 6, 4, 4 | 0, 0, 0 |

All nine processes exited zero without engine errors. At most ten weakly observed
objects were alive at a sample boundary across 30 cycles; the delayed checks released
every tracked object. The exit warning can differ from the immediate reference count
because the mixer continues concurrently. The fixed 200 ms delay is an attribution
experiment only, not the implemented shutdown policy.

This matches the asynchronous playback retirement described in Godot's confirmed
[issue #76745](https://github.com/godotengine/godot/issues/76745): stopping a player
requests deferred audio-server cleanup, which may still be pending at process exit.
The MP3-specific [issue #95484](https://github.com/godotengine/godot/issues/95484)
reports the same object types. These are supporting upstream reports, not proof that
every exit warning or leak has this cause. Both were reviewed 2026-10-14; no engine
upgrade or local engine patch was introduced.

## Implemented verification

`research/performance/loading_probe.gd` now:

- Collects weak references to the current playback of each audio player in its owned
  scene, queues the scene for deletion and polls until those references expire, with
  a one-second deadline. It does not retain stream/playback objects itself.
- Adds a `shutdown` record to the existing v1 report. None of the existing timing
  boundaries changes. Teardown happens after the last measured Home return.
- Marks incomplete cleanup as `complete: false` and exits nonzero; it does not filter
  log warnings or treat a timeout as success.
- Frees the scene and removes its successfully created settings sidecar on failure,
  as well as success. Existing reports/settings are left intact.

The regression script tests real MP3 playback, failure after scene/settings creation,
an intentionally retained playback that reaches the timeout, and rejected invocations
with existing files. All four cases pass on Windows and Linux using the pinned engine
with Dummy audio. The intentional retention remains detectable; the test releases its
own injected reference afterward. The initial test-fixture attempt failed parsing due
to an inferred Variant; `cleanup-tests.log.gz` retains that failure, and explicit WeakRef
typing resolved it before the passing runs.

The official [AudioStreamPlayer3D API](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html)
provides `has_stream_playback` and `get_stream_playback`. The probe observes the latest
playback per player, not every voice of arbitrary polyphonic audio. It is therefore a
focused diagnostic and does not replace resource/RSS tracking or a complete memory audit.

## Artifact and reproduction

Three fresh packaged processes completed without engine errors or exit leak warnings:

| Run | Home/Fly cycles | Audio retirement (ms) | Remaining observed playbacks | First-draw state |
| --- | ---: | ---: | ---: | --- |
| `pack-2a` | 2 | 366.624 | 0 | Both unpaused, tick 12 |
| `pack-2b` | 2 | 316.184 | 0 | Both unpaused, tick 12 |
| `pack-50` | 50 | 293.077 | 0 | 49 unpaused at tick 12; cycle 9 paused at tick 0 |

Each shutdown observed one current playback and removed its settings sidecar. Every
return had 550 Home nodes and zero orphan nodes. The 50-cycle run had 880 flight nodes
except cycle 9 (909 while paused). That transient pause is retained rather than bypassed;
its trigger was not separately instrumented. The 50-cycle count is exercised, but this
is **not** acceptance of 50 uninterrupted interactive flights. `complete` means the
probe finished its sequence and cleanup, not that timing/interaction gates passed.
The existing workload still preserves normal focus and pause callbacks.

The [package command ledger](package-checks.json) and individual reports retain every
sample. These are lifecycle checks, not an alternating performance campaign; concurrent
development/checks were not excluded from host load. No loading speedup is claimed.

The application under packaged tests is the exact unchanged Windows artifact from
the preceding report; only the external loading probe changes. The pinned editor
engine beside the exported DLL loads the embedded pack and executes that probe.
This is packaged lifecycle verification, not release-template GUI or audio-device
qualification. Logs, commands, raw JSON, original probe and source hashes are retained
in [manifest.json](manifest.json). Current commands and teardown semantics have their
authoritative home in the [performance tool guide](../../../../../../research/performance/README.md#homefly-loading-and-lake-geometry).

The isolated `lifecycle_probe.gd.gz` accepts `free`, `stop` or `drain` and a new output
path. Extract it outside `app/` and use the pinned engine with `--headless --path app
--audio-driver Dummy --verbose --script <probe> -- <mode> <output.json>`. It uses the
actual lake source rather than synthesizing or downloading replacement audio.

No full `app/test.sh`, production shutdown fix, real-audio-device acceptance, Workshop/
reset coverage, 30-minute soak or native frame-pacing qualification is claimed. Cold
Home/first-Fly budgets remain open. Earlier failed/leaked logs remain valid historical
observations and are not overwritten by the corrected measurement tool.
