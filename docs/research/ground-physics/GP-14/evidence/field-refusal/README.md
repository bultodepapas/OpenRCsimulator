# GP-14g — refused field replacement preserves the installed flight

2026-10-26. Four production suites pass **3409 checks**, with exact completion
markers, warnings-as-errors, complete receipts and zero engine diagnostics.
This is a refusal-only correction to `FlightSession.set_field`; accepted
installation retains its existing no-reset semantics. No kernel transition,
recording event, force law, physical state or checkpoint key was added.

## Contract and scope

The existing surface-table/field builders run before installation. A refused
replacement of an already successfully installed field now preserves its wheel
and hull tables, observational registry, hull binding, field/runway description,
checkpoint, model, commands, holds, recorder, tick and generation. It emits no
reset, pause, stepped sample or statistics receipt. `field_update_error` describes
the rejected request without setting the active blocking `surface_error`.

The private installed-field marker recognizes valid empty field descriptions and
empty IDs; it is not physical/checkpoint state. Existing transaction guards block
staging reentry into this setter, so no new owner rollback capture is needed.
Initial invalid field installation retains its previous fail-closed behavior.
Successful correction clears both diagnostics. Successful installs preserve their
existing statement order and no-reset behavior.

Accepted live changes can still alter active physics/configuration. This slice
adds no recording boundary and makes no claim that a deliberately changed live
flight replays under its old recording header. Weather/shaft pending-configuration
publication remains a separate migration. No stock hull-support role, statistics
classifier or advanced contact activation changed.

## Original reproduction and rejected harness command

`baseline/reproduction` completes 15 assertions matching observed defects and
controls. At tick3 with an installed field and an open writer, a missing-table
replacement returned false but cleared 24 wheel and 20 hull table scalars, erased
the field/runway description, paused and invalidated the full checkpoint while
the writer stayed open. A separate weather-listener mutation also reproduced an
open publication defect; **that weather defect is not fixed here**. Live-weather
refusal and accepted same-field no-reset behavior are passing controls.

Five original selected source snapshots, source identities, observations and four
actual recordings are retained. A successful reproduction runner means the
observations were confirmed, not that defective behavior passed correctness.

`rejected/wrong-marker` retains the initial surface regression command rejected
for a mistyped completion marker, despite 29 passing assertions. The exact rewritten
test is retained. The corrected production command below passes with its exact
29-check marker; the failed receipt remains failed.

## Production checks

| Suite | Checks | Receipt |
| --- | ---: | --- |
| Field replacement | 70 | [report](current/checks/focused/report.json) |
| Existing surface laws/initial refusal | 29 | [report](current/checks/surfaces/report.json) |
| Accepted contact session | 63 | [report](current/checks/contact/report.json) |
| Six-aircraft logging/replay | 3247 | [report](current/checks/log/report.json) |

The focused suite exercises missing/invalid tables and an unsupported authored
surface under both held and moving conditions. It compares complete active
context bytes, original model reference, registry/hull binding and writer events;
then verifies 32 accepted ticks against an untouched paired session and checks the
actual recording footer. Initial refusal, correction, valid empty descriptions,
empty IDs, accepted changed-field no-reset behavior and caller-copy detachment
are covered. Representative held/moving recordings are retained; they close only
at explicit fixture cleanup after continuation.

`manifest.json` pins 38 copied artifacts. Six selected production files remain
byte-identical between promotion and completed checks; three supporting test
sources are copied at retention. This is not every loaded dependency. Original
absolute runner paths and timestamps remain unchanged. Prior immutable cohorts
retain their historical source scope. These headless/Dummy software checks do not
establish a broad-suite pass, physical realism, native audio or performance.

Selected production SHA-256 identities:

- FlightSession: `9b6de6144a1af3c8bf042e04173b3485196954da94b40fdd73c9f309802d0802`
- Focused test: `837fc003e566b30cd1f462e22a70d63cf1cfd9e83fb2c3da625c74d4eeebabe4`
