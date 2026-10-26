# GP-14d — accepted runway reset publication

2026-10-26. Production headless/Dummy evidence for the prepared runway reset route.
The selected seven scripts pass **3882 checks**, with complete checked-runner
receipts and zero engine diagnostics. These are software lifecycle/replay checks,
not physical validation, native audio, full-suite or performance qualification.

## Contract and scope

All refusal-capable candidate/context/endpoint checks precede physical commit.
The optional synchronous zero-argument `before_sample` hook then notifies the
owner before `stepped(0)`. Default empty-hook checkpoint bytes retain the frozen
baseline digest. A legitimate post-commit presentation hold may pause the new
flight. Forbidden protected kernel/model edits or transition reentry restore
the committed protected frame and fault/pause; the physical reset remains accepted.
Session reports `observer_fault`, `committed=true`, `ready=false`, and advances
the existing statistics generation once. Ordinary successful result dictionaries
retain their prior keys. This guard does not roll back arbitrary listener globals
or data captured by bound Callables, and asynchronous hooks are outside the API.

Session closes the old flight with a detached closing checkpoint/tick captured
**before** command/aux/continuous staging. Context exists only during synchronous
notifications; unavailable old checkpoints are explicit. FlightLog pause events
and footer retain that old boundary even when the main hold listener precedes the
writer. FleetRecord alignment uses the resetting member's old tick. The existing
Incident archives its stored old assessment before its ledger is cleared; no
new damage or physics is inferred. Session preparation guards also reject helper,
configuration, hold/release/resume reentry from endpoint validators, including a
call armed only for final commit validation.

**Only the prepared runway route is migrated.** Historical airborne/reload/restore
and weather/shaft reset emitters are not automatically fixed. This does not enable
advanced aircraft contact or alter a force law, checkpoint schema, aircraft data,
landing classifier or audio asset. Public runway helpers now issue one existing
physical lifecycle receipt; a committed observer fault cannot trigger airborne
fallback. The historical explicit fallback after a true runway rejection also
records its accepted physical generation.

## Original defect and discarded harness

`baseline/check` is the original actual Session + FlightLog reproduction. Its
fourteen assertions intentionally match the **defective** behavior: callback
`hold("companions-reset")` or mass mutation made commit refuse after resetting,
yet Session returned converged success, kept old body/tick2 with new aux/cleared
contacts, closed the writer and lost a full checkpoint. Its runner `ok=true`
means the defect was reproduced, not that this behavior passed correctness.
Original recorder outputs and selected source bytes are retained without rewriting
the baseline. `baseline/default-byte-sentinel` records the pre-promotion legacy
checkpoint digest used by the current regression.

`discarded-harness-parse` retains an intermediate test syntax failure. It did not
run the transaction assertions and is not counted as physics evidence or a failed
baseline. Later production results below use corrected test syntax.

## Current checks

| Script | Checks | Receipt |
| --- | ---: | --- |
| Reset publication, including real Log/Fleet/Incident consumers | 180 | [report](current/checks/main-focused-01/report.json) |
| Generic endpoint transactions | 274 | [report](current/checks/main-endpoint/report.json) |
| Existing runway transaction | 32 | [report](current/checks/main-runway/report.json) |
| Statistics lifecycle | 51 | [report](current/checks/main-statistics/report.json) |
| Accepted aircraft contact session | 63 | [report](current/checks/main-contact/report.json) |
| Existing six-aircraft flight logging/replay | 3247 | [report](current/checks/main-log/report.json) |
| Accepted mechanism audio adapter | 35 | [report](current/checks/main-audio/report.json) |

Each report has its engine log alongside it and retains the original command,
absolute paths, timestamps and log digest. New tests are discovered by `app/test.sh`;
the existing RejectCommit test override has the matching optional hook signature.
The focused actual recording has an exact old full-checkpoint footer and complete
numeric replay. It checks no phantom flight/M7, one generation, rejected candidate
silence and open recorder, precommit-only/final-validator reentry, postcommit
faults, bounded fleet final alignment and explicit missing closing checkpoint.
Its terminal Incident and companion agent fixtures are software fixtures, not
physical crash or AI decision validation.

`manifest.json` hashes every retained artifact and marks its source scope. The
selected changed production sources were copied around the current runs and
byte-verified unchanged at retention. Supporting existing test copies are labeled
at retention. This is not every source file loaded by the app; preserve the ORFL
headers' recorded identities when replaying. The earlier intended-hull and event
cohorts remain immutable. Do not attribute this reset correction to their sources.
