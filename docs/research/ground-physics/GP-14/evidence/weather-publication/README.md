# GP-14h: accepted pending-weather publication

2026-10-26. `setup_weather` now installs a validated **pending** configuration
before notifying old observers through the existing guarded publication helper.
The prior detached checkpoint closes the old recording. No tick, physical reset,
new generation or statistics credit is emitted; callers still invoke `reset()`
to build the selected start. Pre-setup selection has no installed flight to notify.

The original GP-14g configuration audit reproduced a reset listener setting mass
to zero during weather selection. This change protects the declared Simulation
state/model and rejects Session transition reentry during preparation/publication.
An observer fault preserves the accepted pending choice and old physical frame,
pauses with a fault, and cannot turn accepted selection into rollback. This is a
bounded owner guard, not a sandbox for arbitrary mutable Session/WeatherField
internals. Shaft pending-configuration migration remains separate.

## Verification

Seven production scripts pass **3,915 checks**, all complete with unique required
completion markers, warnings-as-errors and zero engine diagnostics:

| Suite | Checks |
| --- | ---: |
| New pending-weather publication | 196 |
| Wind flight | 51 |
| Spatial-weather session | 101 |
| Restore publication | 137 |
| Common start/reload | 148 |
| Flight logs | 3,247 |
| Accepted FlightAudio | 35 |

The focused suite preserves four frozen complete 25-endpoint checkpoint traces
(calm, gusty, turbulent and dense air), actual old recording footers, refusal
silence, manual-step rejection while pending, subsequent explicit-reset recovery,
and mutation/reentry from reset, pause and fault observers. It verifies that only
the subsequent physical reset advances the existing statistics generation.

An independent **19-check** consumer review passes on the behavior-identical
draft. It covers successive pending selections, explicit unavailable closing
checkpoint on the second selection, immutable getter copies and pause-observer
reentry. Production differs from that reviewed runtime draft only by an explanatory
comment. The pre-change 108-check trace capture and three rejected development
parse/compile runs are retained; those rejected runs are not passing evidence.

`checks/` contains the original report/log pairs; `development/` retains the
before source, drafts and capture. `recordings/` contains the actual focused
production recordings. `source/` pins twelve selected current files, not every
loaded dependency. `promotion.json` under development pins both changed payloads.
`manifest.json` hashes payloads; `transport.json` records a disposable cohort-only
Git/fresh-clone byte check with Windows automatic line-ending conversion enabled.
The real repository was not staged or committed by this work.

No force law, weather parameter, checkpoint schema, source integrator, stock
advanced-contact activation, full-suite or performance qualification changed.
The ongoing masterplan and GP-14 guide own remaining work.
