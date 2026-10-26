# Accepted mechanism audio evidence

2026-10-26. Pinned Godot `4.8.beta1.official.4d10419ca`, Windows, Dummy driver. [Manifest](manifest.json) identifies 44 retained artifacts, five promoted source pins and **317 passing checks**. This is a selected source snapshot; it does not freeze every application dependency. Paired physics parity is within the focused real-session process, not a cross-version or full-fleet replay claim.

| Check | Passing assertions |
| --- | ---: |
| Accepted-tick observer: brief motion, ordering, single drain, overflow, clock/pause/reset/rewind | 58 |
| Existing recording playback, voice limits and lifecycle | 103 |
| Existing motion classifier | 36 |
| Existing closed configuration/Workshop migration | 24 |
| Existing ground-audio regression with integrated FlightAudio | 33 |
| Real-session accepted observer, complete checkpoint parity, rejected ticks and rig lifecycle | 35 |
| Existing full-scene P-51/electric Workshop integration | 28 |

All seven checked runs completed with zero failures and zero engine diagnostics. Aircraft provenance messages remain visible in the logs. The focused integration uses actual accepted servo/flap/retract states; 32 neutral settling ticks establish the initial servo endpoint before the brief return gesture. It verifies that render-only endpoint sampling misses that gesture, while the accepted observer preserves it. Rejected physics contributes no accepted sample or cue. Pause/manual step, rewind, reset, deferred bus reconstruction, reconfiguration and final callback/bus cleanup are included.

Three earlier failure receipts are retained separately: a duplicate-tick clock change retained a stale cue before its guard correction; the first integration draft queried a freed typed Node and timed out during harness cleanup; the second started from the aircraft's nonzero trimmed servo angle, so its alleged return gesture did not actually return. The cleanup and fixture were corrected. Earlier candidate sources are not a frozen reproduction checkout. The existing 28-check full-scene baseline passed before the adapter migration and passed afterwards.

The existing `tools/audio/mechanical_benchmark.gd --observe-accepted` now times capture separately. [Accepted benchmark](benchmark-main.json): 1,000 warmup and 10,000 measured calls per scenario, one capture per update. The [default-mode run](benchmark-main-legacy.json) verifies the retained direct playback route; its shorter run is not a controlled performance comparison.

| Scenario | Capture p95, µs/call | Playback p95, µs/update |
| --- | ---: | ---: |
| Idle | 41 | 55 |
| Four moving servos plus retract | 65 | 180 |
| Paused | 34 | 65 |
| Distant | 55 | 23 |
| Duplicate accepted tick | 3 | 79 |

These runs report no capture refusal, queue overflow, object-count growth or voice-pool growth, and restore the scene bus count. Object counts do not measure temporary allocations. Capture timing excludes FlightAudio snapshot construction and signal dispatch; one capture per update does not reproduce the production tick/render ratio. Other sessions shared the host. Native audio, hardware deadlines, listening, acoustic realism and 1080p/whole-flight performance are unqualified by this cohort. The earlier AUD-16 native receipts remain historical.

Reproduce the seven tests with the [checked Godot runner](../../../../../tools/shared.md#one-godot-script), then use the [audio tools](../../../../../../tools/audio/README.md) for the two benchmark modes. Runtime source and test paths are listed in the manifest. Current behavior belongs to the [mechanical audio guide](../../../../../servo-retract-audio-implementation.md).
