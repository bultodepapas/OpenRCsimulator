# AFC-01-R2 / AFC-03-R2: accepted controls and restore lifecycle

2026-11-09. Follow-up to the external companion audit and
[AFC-04-R9](../AFC-04-R9/README.md). Windows x86_64 and the pinned official Godot
`4.8.beta2.official.cafc17a19`; Linux is additionally checked for the publication
fixtures. [Verification](verification.json) records commands, source identities,
checked logs, deliberate failures and qualification receipts. The [195 flight
inputs](source-manifest.json) stayed unchanged during the final checks. Parallel
economy, scenery and localization edits were preserved.

`FlightSession.step_external_tick()` now runs ordinary contact/crash guards before
publishing attempted controls. Ordinary paused/held/refused steps preserve the
last accepted commands, raw controls, gear, flaps and brake. A precommit kernel
fault restores these before pause/fault notifications and retains the kernel's
validated recovery inputs. A committed tick keeps its controls even if a later
observer faults. The precommit `before_step` signal still exposes attempted input;
it is not an accepted-frame notification. Crash countdown/reset and terminal
contact facts retain their existing ownership. Nested prepare/step calls refuse
atomically while an attempt is active. Session commit `84b52ce7a`
contains this repair and its 63-check real-session regression.

Accepted start, checkpoint restore, pending weather and pending shaft publications
now have detached `last_transition()` receipts with a monotonic generation and
explicit kind. Rejected staging emits no receipt. The existing `resetting` signal,
old closing context and physical checkpoint schemas are unchanged.

Main rebuilds companions only for the latest accepted start from the same Session.
Stale callbacks cannot release its successor's hold or resume a restored flight.
Remove wins over still-queued roster creation. Explicit pause and application
focus loss survive completion, including a restart while already unfocused.
Main's paired checkpoint facade continues to refuse an active roster; accepted
technical/debug restores through Session remove it immediately so clocks cannot
diverge. Removal disconnects observers and clears the roster synchronously;
agents executing a callback are disposed after their stack unwinds. The manager
exits cancelled advance/damage-mirroring work without crediting the old cohort.

The real pre-fix Main scene reproduced two failures in six checks: tick-zero
restore respawned the removed roster and lost recorded-input pause. A real old
Session from commit `5b72d04e`, tested without method mocks, reproduced six
failures in sixteen paused/precommit-fault checks, including mismatched controls
in pause/fault notifications. Those negative receipts are retained separately.

| Final check | Result |
| --- | --- |
| New real Session rejection/transition regression | 63 checks, zero failures |
| New real Main lifecycle regression | 36 checks, zero failures |
| Existing companion Session / failures | 65 / 24 checks, zero failures |
| Reset publication / common reset transaction | 215 / 148 checks, zero failures |
| Restore publication | 137 checks, zero failures |
| Manager / recording / observation / strict profiles | 53 / 156 / 21 / 44 checks, zero failures |
| Lifecycle/resource checks | 653 checks; 50 headless and 10 visual/audio cycles |
| Home/Pause/Restart shell | Zero failures |
| Paired time-of-day Main checkpoint regression | 57 checks, zero failures |
| Weather / shaft publication, each Windows and Linux | 313 / 214 checks, zero failures per host |

Two old source pins initially refused the weather/shaft fixture: this Session
change and an already-changed wheel-profile reader. The [typed comparison](fixtures/typed_comparison.json)
matches four complete capture JSONs byte for byte against retained reference
captures: 300 typed checkpoints, configuration bytes and event arrays across both
hosts. [Promotion audit](fixtures/promotion_audit.json) confirms the historical
family blobs, original digests and reference commit are unchanged. Only the named
source identity/base/overlay metadata and helper fixture hash were renewed; the
18-source guard is unchanged. A disposable Session comment mutation still causes
the expected source-identity failure. The retained event arrays are empty, so this
does not qualify event-producing maneuvers. The [original fixture methodology](../../release-readiness/PT1-CI-00/ci-audit-fixtures-2026-11-08.md)
remains the reproduction authority.

The [solver rebind](../AFC-02/rebinds/2026-11-09-896989e0-to-b0a074e4.json)
uses the documented full-baseline route because Main now consumes the new Session
receipt API. All nine retained 2,881-row tape CSVs are byte-identical on accepted
and candidate snapshots. The normalized source pin is renewed from `896989e0`
to `b0a074e4`, with the solver revision committed before admission renewal. No
controller, aircraft data, physics law or golden was retuned. The earlier R9
two-minute matrix remains dated evidence on its preceding Session source;
this campaign verifies the affected Session/fleet boundaries and tape parity.

The complete common-tick capture closes both streams at tick 24; both [25-row
replays](captures/exact-player.json) are exact, complete and solver-unchanged.
The deliberately interrupted agent-callback restore closes an incomplete cohort
explicitly rather than claiming aligned replay. Their [summaries](captures/common-tick-summary.json)
and source/log hashes are retained; raw recordings remain in the checked run's
ignored output directory.

[Normal app admission](live/live-admission.json), without test overrides, observes
three active airborne companions through 8,978 ticks without faults/crashes.
The debug checkpoint route advances to 9,218, then restores tick 8,978: the roster
is empty, input remains recorded and the flight stays paused with no queued
companion restart. An explicit restart admits three again, observed through
156 ticks. [Shutdown](live/live-stop.json) is unforced with zero leaked objects
and no crash; the launcher exit code is unavailable. The run is headless and
does not qualify rendering, native backends, physical realism or 1080p performance.

Use the [checked runner](../../../../tools/godot/README.md) for
`test_companions_external_rejection.gd` and `test_companions_restore.gd`; exact
arguments for all checks are retained in verification. The [baseline subset](baseline_external.gd.txt)
expects `git show 5b72d04e:app/sim/flight_session.gd` extracted to
`tmp/afc-r10/legacy_session.gd`. The [companion rebind guide](../../../../tools/companions/README.md),
[flight-log workflow](../../../FLIGHT-LOGGING.md) and
[debug bridge](../../../../tools/debug/README.md) own their commands.
The remaining audit roadmap and existing narrow aircraft/weather/activity limits
remain in the [AFC plan](../../../plans/ai-flight-companions.md).
