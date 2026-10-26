# GP-14e — common accepted start transactions

2026-10-26. Nine production scripts pass **4066 checks**, with completion markers,
warnings-as-errors, complete runner receipts and zero engine diagnostics. This
extends the [GP-14d runway foundation](../reset-publication/README.md); that cohort
is unchanged. Headless/Dummy software checks do not establish physical realism,
native audio, full-suite coverage or performance qualification.

## Contract

One Session transaction starts before trim selection/model staging, captures the
old closing boundary, and commits through the existing generic kernel hook.
Runway, airborne/half-power, hand-launch, explicit fallback and reload reuse the
same owner and unchanged state builders/force laws. On refusal the original
kernel/model reference, Session context, commands, failure resource/RNG and old
recording survive without notifications or generation changes. Rollback does not
reset or evaluate the old model. The obsolete reload reset/restore fallback is
removed.

Reload consumes an explicit commit receipt: a quiet candidate rejection cannot
be called reloaded or credited; an accepted observer fault cannot roll back or
claim previous aircraft retained. It stays paused/nonready and advances one
generation. Existing public success strings/result keys remain compatible.
The legacy requested-runway Boolean still returns false after its distinct
intentional airborne fallback, whose physical commit is recorded separately.
An accepted fallback observer fault has explicit nonready metadata. Initial
invalid initialization may still park an inert failed start; it must not replace
an already valid flight on rejection. `_reset_airborne_start` keeps its Boolean
technical-probe interface by delegating to the same receipt helper.

Restore and weather/shaft configuration publication are **not migrated** here.
Their reproduced late-listener failures remain open. This bounded owner capture
does not sandbox arbitrary external callback globals. No new integration kernel,
force law, checkpoint schema, aircraft authoring or classifier was added.

## Baseline and historical fixture

`baseline/audit` reproduces the old failures: late failed reload closes the writer;
quiet refused runway reload claims success with a generation but no sample;
accepted runway observer fault is rolled back by reload; airborne/fallback refusal
loses the old flight; invalid trim selection invalidates the accepted start. Its
48 assertions intentionally match observed defective behavior and controls. Runner
success means reproduction, not correct lifecycle behavior. Restore/weather
listener failures are retained as open findings. The unsupported stock Stik shaft
selection and successful intentional fallback are passing controls.

`historical-fixture-mismatch` retains the original statistics 51-check/four-failure receipt.
That test's former resetting-listener mass edit now intentionally occurs after an
accepted physical commit. The corrected fixture injects one candidate evaluator
refusal before commit and retains **all original failed-reload invariants**. The
new 148-check suite separately checks accepted observer faults and one generation. Its
original production fixture is retained; the failed run used an import-rewritten
draft copy later edited, so exact executed draft source is not claimed retained.

## Current production checks

| Script | Checks | Receipt |
| --- | ---: | --- |
| Common Session starts/reload | 148 | [report](current/checks/common-reset/report.json) |
| Existing runway publication | 180 | [report](current/checks/runway-publication/report.json) |
| Endpoint transactions | 274 | [report](current/checks/endpoint/report.json) |
| Statistics lifecycle | 51 | [report](current/checks/statistics/report.json) |
| Accepted contact session | 63 | [report](current/checks/contact/report.json) |
| Start-choice routes | 36 | [report](current/checks/starts/report.json) |
| Six-aircraft logging/replay | 3247 | [report](current/checks/log/report.json) |
| Accepted mechanism audio | 35 | [report](current/checks/audio/report.json) |
| Existing runway transaction | 32 | [report](current/checks/runway-transaction/report.json) |

Engine logs accompany reports. The new suite covers pure-load/trim refusals,
refit and final-validator owner reentry, reload preparation, original model/failure
resource preservation, turbulent RNG, exact old recorder footers, actual gearless
X8 hand launch, both fallback outcomes, Boolean probe compatibility, initial
invalid parking and 32 accepted ticks of exact observed/unobserved continuation.
It does not author a stock X8 landing-support role or grant landing credit.

`manifest.json` pins every copied artifact. Selected source bytes match the main
tree before/after final checks; supporting existing tests are labeled at retention.
This is not all loaded application source. Original absolute paths/timestamps and
old source scopes are preserved. Refused recordings that remained open during an
assertion are closed only by explicit fixture cleanup; file completeness alone
must not be mistaken for premature runtime closure. Existing immutable hull,
event, audio and GP-14d evidence is not relabeled as this source revision.
