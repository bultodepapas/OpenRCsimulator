# GP-14i: accepted pending-shaft publication

2026-10-26. Shaft selection now uses the existing guarded Session transaction
and Simulation publication boundary. A validated pending mode and its existing
propulsion callbacks are installed before reset listeners run. The old detached
checkpoint closes the previous recording. The subsequent explicit reset still
constructs the selected physical layout and alone credits a new generation.

The baseline reproduces an accepted selection whose reset listener sets aircraft
mass to zero. The fix protects the declared kernel state/model and rejects owner
transition reentry. An observer fault retains the accepted pending selection and
old physical arrays, pauses, and reports the fault. Preparation refusal preserves
the old owner and recording without notification. Same-mode selections remain
silent; pre-setup selections have no installed flight to notify. Finite propulsion
still rejects split mode. This is not a sandbox for arbitrary Session internals.

## Verification

Seven production scripts pass **4,017 checks**, all complete, with required markers,
warnings-as-errors and zero engine diagnostics:

| Suite | Checks |
| --- | ---: |
| Shaft publication | 155 |
| Existing coupled shaft | 99 |
| Weather publication | 196 |
| Restore publication | 137 |
| Common start/reload | 148 |
| Flight logs | 3,247 |
| Accepted FlightAudio | 35 |

The focused suite preserves two pre-change complete 25-endpoint checkpoint traces
for opposite split/coupled selections followed by reset. It verifies actual old
recording footers, unavailable closing context on repeated pending choices, no
duplicate notification for an unchanged choice, no credit before physical reset,
manual-step refusal while pending, reset recovery, malformed/live rejection, and
mutation/reentry from reset/pause/fault observers. The original 55-check baseline
and 147/155-check draft plus 99-check coupled draft receipts remain separate.

[Independent review](development/independent-review.md) verifies source identity,
callback ordering, normal consumers and the checked draft receipts. It ran no
additional tests and adds no assertion count. The extracted callback installer
preserves existing stage, substep and event selection order. No force law,
coefficient, source integrator or checkpoint schema changed.

`checks/` retains original production reports/logs; `recordings/` the actual focused
ORFLs; `development/` the original source, reproducible draft/capture and promotion
identities. `source/` pins eleven selected files, not every loaded dependency.
`manifest.json` hashes payloads. `transport.json` verifies a disposable cohort-only
Git/fresh-clone transfer with Windows automatic line-ending conversion enabled;
the actual repository was not staged or committed.

Stock advanced contact, full-suite, physical and hardware-performance qualification
remain separate masterplan gates. Live changed-field recording identity is also
outside this pending-configuration correction.
