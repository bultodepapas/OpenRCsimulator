# GP-14f — accepted restore publication

2026-10-26. Ten production scripts pass **4398 checks**, with exact completion
markers, warnings-as-errors, complete runner receipts and zero engine diagnostics.
This extends the same [start transaction owner](../start-transactions/README.md).
These are headless/Dummy software checks, not a full-suite, physical, native-audio
or performance qualification.

## Contract

`Simulation.restore_checkpoint(candidate, after_commit = Callable())` retains its
existing parser, target arrays and Boolean acceptance. A supplied synchronous
zero-argument hook is validated before commit, then runs after physical acceptance
and before automatic pause, without a stepped sample. An empty hook retains the
frozen legacy checkpoint digest and pause ordering. Reset and restore share one
guarded publication helper; no serializer, force law or checkpoint schema changed.

Session begins its existing transaction before closing-checkpoint capture and
restore validation. A refusal preserves the original protected kernel/model,
declared owner state, holds, commands, resources and open writer, without reset,
pause or generation publication. Failure and weather resources are staged
detached. Accepted restore closes old observers using the explicit old checkpoint
and tick before automatic pause can expose the restored clock to the old writer.
It retains paused replay, disabled live input, unknown launch provenance and one
existing `checkpoint_restore` bookkeeping receipt. The statistics service's
existing noncredit branch prevents restored time from earning flight totals.

Postcommit protected mutation or transition reentry keeps acceptance, restores
the accepted protected frame, and faults/pauses. Pause/fault listeners are guarded;
final repair emits no recursive fault. Session reports the fault diagnostically.
This covers declared kernel/model fields and normal Session entry points, not
arbitrary listener globals. Weather/shaft configuration setters remain unmigrated.

## Baseline and rejected runs

`baseline/reproduction` has seven assertions matching observed defects and a
passing control. A late resetting-listener mass edit refused restore after closing
the old writer and left mass invalid; a validator's Session hold leaked on refusal.
Its successful runner result establishes reproduction, not correct behavior.
Original selected core bytes, observations and three actual recordings are kept.
The direct-kernel pre-change checkpoint SHA is
`02734db2f127b76f3220938e693b4a3ab92f25d25975c679064fa1360fd68032`.

`rejected/malformed-format` retains the Array/String selector engine error.
The probe source is retained; its pre-guard draft core was subsequently edited,
so an exact executed draft snapshot is not claimed. The focused production suite
checks quiet primitive/Array/Dictionary/StringName rejection with an exact String
guard before the existing format parser.

Other rejected receipts retain missing-font-cache failures, failed imports and
three mistyped completion-marker commands. The first import continued after a
tool-host stdout failure; an accidentally overlapping second import was stopped.
The first subsequently crashed in native/scene import. Neither import passed.
After the needed font cache existed, the affected scripts were rerun cleanly;
no successful whole-project import or broad-suite pass is claimed.

## Production checks

| Script | Checks | Receipt |
| --- | ---: | --- |
| Restore publication | 137 | [report](current/checks/restore/report.json) |
| Endpoint transactions | 274 | [report](current/checks/endpoint/report.json) |
| Runway publication | 180 | [report](current/checks/reset/report.json) |
| Common starts/reload | 148 | [report](current/checks/start/report.json) |
| Checkpoint integrity | 149 | [report](current/checks/checkpoint/report.json) |
| Statistics lifecycle | 51 | [report](current/checks/statistics/report.json) |
| Atmosphere/session replay | 114 | [report](current/checks/column/report.json) |
| Six-aircraft logging/replay | 3247 | [report](current/checks/log/report.json) |
| Accepted mechanism audio | 35 | [report](current/checks/audio/report.json) |
| Accepted contact session | 63 | [report](current/checks/contact/report.json) |

The focused suite covers invalid callbacks, all three validation reentry phases,
exact failed-attempt preservation, old recording/footer replay, pause ordering,
committed observer faults, detached failure/weather restoration, 32-tick exact
continuation and actual service noncredit behavior. Four representative current
recordings are retained. Refusal recordings remain open during the assertion and
close only at explicit fixture cleanup; file completeness is not premature closure.

`manifest.json` pins 79 copied artifacts. Six selected source files match before
and after final production checks; nine supporting tests are copied at retention.
This is not every loaded dependency. Original runner paths and timestamps remain
unchanged. Earlier immutable cohorts retain their original source scope.

Selected production SHA-256 identities:

- Simulation: `4b7ed9d9ea8a4bf3349b029505add370d15eed246eb4263b30d44e7f5455b490`
- FlightSession: `d680ba2ef0626b6f3eeae0f8de8d6523955b7da95767f065ede36baac373c964`
- Focused test: `d504edcaf43ab0993d362470991c847f4245333ecefb36406d53ee4ba6f6b021`
