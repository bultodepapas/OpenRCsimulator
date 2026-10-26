# GP-19c: accepted contact audio

2026-10-26. Fixed-wing ground audio now captures every accepted simulation endpoint and plays retained cues during render updates. The [production collection](main-checks/) passes **202 checks across five invocations**, with warnings treated as errors, exact completion markers and zero engine diagnostics. An [independent review](review/report.json) adds 11 passing adversarial checks. [Report](report.json) and [source identities](promotion.json) define the scope.

The existing contact sound classifier was extracted into `GroundAudioMotion` and reused by both legacy render callers and accepted capture. Its force hysteresis, airborne window, approach threshold and cooldown are unchanged. A frozen 100-endpoint trace preserves complete legacy classifier state, rolling envelopes and impact counts byte exactly. These thresholds govern sound cues, not physical support, damage or flight statistics.

`FlightAudio` shares its existing accepted-step, pause and reset connections. Its contact snapshot still re-evaluates the legacy contact law read-only at the accepted state; this is not yet an adapter for the advanced solver's impulse/work receipt. Capture creates no audio players, touches no buses and uses no shared random state. It retains at most eight contact states and 64 detached cues. Playback retains the existing eight contact slots and 32-player ceiling. Overflow drops the oldest cue with a counter; cues older than 0.25 accepted simulation seconds expire rather than replaying a long stalled interval. Capture rejects malformed or oversized snapshots without accepting partial history.

Repeated ticks cannot replace history. Pause, missing ticks, rate changes, reset and detach prime or discard history. The first render after rewind resets playback while preserving valid cues already captured in the new interval. Cue aging uses the captured simulation rate. Rolling pitch remains render-owned and cannot alter accepted contact history. All recordings, volume laws and surface-material selection remain with their existing owners.

| Check | Assertions | Evidence |
| --- | ---: | --- |
| Accepted contact state, bounds, invalid inputs, lifecycle and frozen legacy trace | 93 | [receipt](main-checks/accepted/report.json) |
| Actual Stik drop and paired full checkpoints | 18 | [receipt](main-checks/actual/report.json) |
| Existing ground audio | 33 | [receipt](main-checks/legacy/report.json) |
| Existing accepted mechanical flight adapter | 35 | [receipt](main-checks/mechanical/report.json) |
| Solid-support material routing | 23 | [receipt](main-checks/materials/report.json) |
| Independent side-effect, normalization, rewind and clock review | 11 | [receipt](review/check/report.json) |

The actual-session fixture starts the Stik with 0.4 m wheel clearance, 3 m/s forward speed and 0.2 m/s sink, with its engine disabled. The first contact cue arrives at tick 67. Three cues survive until the first render at tick 79. Audio-observed and reference sessions retain identical full checkpoints at every tested tick. A rejected step creates no new cue. This synthetic drop exercises the existing contact physics; it does not calibrate bounce, gear strength or acoustic realism.

The main run's 79 duplicate endpoint captures measured 158 microseconds median and 221 microseconds p95, including contact/material snapshot construction. Concurrent host load, the duplicate-call fixture and Dummy output prevent treating this as a native mixer, production frame or 1080p budget qualification.

The initial actual-session test used an incorrect catalog ID and failed; its [rejected receipt](development/rejected-identity-fixture/report.json) remains intact. The corrected fixture explicitly asserts aircraft admission. An initial summary command targeted the wrong temporary directory depth; canonical receipt pairs are flattened without editing their bytes and the canonical five-invocation summary passes. The old [baseline](development/legacy-control/report.json) and independent [legacy byte capture](development/legacy-byte-capture/report.json) remain separate.

Advanced accepted wheel/slip/work observations, suspension and scrape/damage layers, native output, listening and combined performance qualification remain open. This cohort changes no aircraft data, physical forces, solver, statistics event or audio asset. [Inventory](manifest.json) and [fresh-checkout receipt](transport.json) bind the retained source and report bytes; it is a selected source snapshot, not a full application export.
