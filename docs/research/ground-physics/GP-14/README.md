# GP-14a — survivable accident classification

2026-10-25 · **Status: bounded P0 classifier slice implemented and unit-checked; complete GP-14 remains open.** Owner: ground physics / UI-FS. Scope follows [masterplan §8.5](../../../advanced-ground-flight-physics-masterplan.md#85-shared-accepted-event-model). Software evidence only; no physical landing, damage or pilot-intent validation is claimed.

## Behavior and boundary

The existing pure [statistics detector](../../../../app/statistics/detector.gd) remains the flight and incident classifier. An accepted gear-up contact emits a semantic `accident` with `kind=gear_up_contact` and increments M7 once per activity generation through the existing `crash` event. Its `terminal=false` value leaves the flight active and physics running. It does not call `FlightSession._crash()`, pause the simulation or infer structural failure.

Persistent scrape ticks and short bounce recontacts retain one accident ID. Confirmed airborne rearm permits a distinct later semantic accident, while the generation M7 latch stays set. A terminal escalation updates the same active incident and closes the flight as `crashed` without another M7 increment. A supported quiet hull stop resolves a failed landing and `damaged_stop` without requiring a successful wheel-stop geometry. Resting persistent contact retains its last incident identity until confirmed departure, preventing idle scrape spam; general independent taxi-incident grouping is not qualified here. Previously earned touch-and-go credit is retained.

The rearm regression exposed an ordering defect: unavailable success geometry took precedence over an already accepted incident, producing an unknown departure. The fix gives the incident precedence, matching damaged-stop behavior. A contact with unavailable geometry and no known incident remains unknown. The new regression failed two assertions before the fix; only the final passing receipts are retained below.

## Accepted physical receipt

The public physical observation is the read-only `FlightSession.accident_observation()` method, with exactly eight keys:

| Key | Contract |
| --- | --- |
| `schema` | `openrc-aircraft-accident-observation` |
| `version` | Integer `1` |
| `tick` | Nonnegative integer accepted contact tick, matching the current simulation tick |
| `generation` | Nonnegative integer `statistics_generation`, matching the current session |
| `gear_up_contact` | Boolean accepted hull contact with installed retractable gear outside its fully-down endpoint |
| `ground_contact` | Boolean current accepted hull support/contact |
| `intended_support` | Boolean authored normal support fact; current legacy hull probes expose `false` |
| `terminal` | Boolean terminal physical-session outcome |

Current gear-up production requires a positive accepted tick, active hull contact IDs, valid retractable-gear auxiliary state, nonempty installed support bindings and actual extension below `1.0`. A command alone does not establish contact. Wheel-less aircraft cannot satisfy that installed-retractable-gear condition. No intended skid/belly role is inferred from missing gear; such future authored support must extend the factual contract explicitly.

The [adapter](../../../../app/statistics/fixed_wing_adapter.gd) rejects stale tick/generation, negative identities, wrong schema/version, extra keys, nonboolean flags and inconsistent gear-up facts. The detector consumes accepted facts and owns accident grouping and timers. The historical five-field `openrc-aircraft-contact-state v1` returned by `contact_events()` and stored in checkpoints is unchanged; the new receipt is not appended to that strict envelope.

`gear_up_contact` describes the observed contact configuration. Whether the gear was deliberately commanded up, failed mechanically or remained in transit is unavailable in this receipt. Damage severity, component breakage and repair need are also unavailable; classification alone does not establish them.

## Versions and historical coverage

`flight-statistics-rules-v2` widens M7 from terminal crashes to the first accepted accident per activity generation. Detector snapshot v2 carries the accident serial, active ID and escalation state separately from the M7 latch. JSON-round-tripped snapshots reproduce the same semantic continuation, and snapshot rollback/retry preserves deterministic IDs.

V1 detector snapshots remain readable without inventing accident state. Existing v1 ledger records keep their terminal-only observation coverage; they are not retallied as if survivable accidents had been observed. The statistics store schema remains v1 because its existing versioned metric fields and bounded metadata hold this slice; a rules version is not a claim of additional historical observations.

## Retained checks

These checked-runner receipts executed the isolated candidate based on `cb2924b3676b72ee49497c92fe742b0b1dcd2d9c` at `tmp/gp-implementation-20261025`, with candidate changes. Exact commands, timestamps, engine output and log SHA-256 values are preserved in the reports. Engine: official Windows Godot `4.8.beta1.official.4d10419ca`, headless. The runner reported complete execution, zero engine diagnostics and success for both checks.

| Check | Result | Evidence |
| --- | --- | --- |
| [test_ground_accidents.gd](../../../../app/tests/test_ground_accidents.gd) | 47 checks, 0 failed | [report](checks/pure-accidents-47/report.json), [engine log](checks/pure-accidents-47/engine.log) |
| [test_flight_statistics_detector.gd](../../../../app/tests/test_flight_statistics_detector.gd) | 67 checks, 0 failed | [report](checks/existing-detector-67/report.json), [engine log](checks/existing-detector-67/engine.log) |

Focused cases cover 100 sliding scrape ticks, 100 persistent rested-contact ticks, continuing unsupported airborne time, same-tick terminal escalation, terminal-first contact, pre-flight ground accident cause, hull rest without landing geometry, failed rearm with unavailable geometry, short-bounce deduplication, new incidents after rearm, prior touch-and-go preservation, v2 JSON restoration, v1 coverage, rollback/retry IDs, duplicate/invalid/gapped ticks and strict packet identity/no-gear exemption. The existing detector suite covers prior takeoff, landing, timing, speed-filter and profile behavior.

These receipts are unit evidence for that candidate run, not complete application integration or latest-source identity receipts. Subsequent combined session/service changes require the integrated checks below. Reproduction uses the canonical [checked script runner](../../../tools/shared.md#one-godot-script); the reports retain the original absolute paths intentionally as historical run identity.

## Remaining scope

The full ten-event vocabulary and shared subscriber bus, nonpersistent semantic observers for technical routes, comprehensive per-accident archive, complete v2 identity/evidence envelope, mechanical/damage causality, general taxi-incident grouping and physically calibrated damage remain deferred. This slice does not qualify the full GP-14 gate, physical realism, audibility, hardware performance or rendered presentation.

## Integrated receipts

The final main-tree [integrated collection](../GP-08/evidence/integration/README.md) retained the latest successful receipt for each of **15 scripts: 841 checks, zero failures** on 2026-10-25. GP-14 pure classification has 55 checks and the live session/service suite has 29, including fixed-gear exemption after an accepted contact tick. The collection also covers the existing detector, lifecycle, reset, store, writer, contact, checkpoint and wheel regressions. [Raw source identities and receipt selection](../GP-08/evidence/integration/report.json) pin base commit `9f12c79e1490c4c72895d450910d9c916743d7b9`, final runtime/test hashes and concurrent unrelated aero/audio/wind changes; [JUnit](../GP-08/evidence/integration/results.xml) verifies 15 passed invocations.

The service now updates terminal escalation by deep-copying and replacing the crash record, preserving the immutable snapshot already handed to the background writer. The [live persistence fixture](../../../../app/tests/test_ground_accident_session.gd) checks that a pre-escalation writer snapshot remains unchanged and that the saved record retains one M7, its original cause, the terminal update and rules version. Persisted accident IDs use the service's activity UUID namespace rather than session-local generation counters; accepted physical receipts continue to use their session tick/generation identity. The final lifecycle checks also preserve the accepted aircraft configuration hash after reload.

The [55-check pure suite](../GP-08/evidence/integration/test_ground_accidents/engine.log) adds atomic rejection of fractional/string snapshot versions and inconsistent v2 serial, M7/incident-latch and terminal-group state. Valid JSON snapshots and historical v1 coverage remain supported. The earlier [candidate numerical replays](../GP-08/evidence/candidate/README.md) have a separate captured source identity: final main detector/service changes are covered by these integrated checks, not by attributing the earlier replay proof to later source. This selected headless collection is not a full suite, physical validation, performance measurement or rendered acceptance.
