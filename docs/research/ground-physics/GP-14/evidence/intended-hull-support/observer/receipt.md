# GP-14 optional flat-solid hull observation

2026-10-26. Implemented and promoted the model-pinned ContactContract binding,
read-only session packet, explicit hull profile and adapter consumption. Stock X8
has no authored role and remains unavailable for landing credit. No forces, state,
detector/service/Event, timers or stock aircraft files were changed by this slice.

The new packet uses accepted contact tick/IDs and the actual declared flat hull
normal/height `[0,0,-1]`/0 m. Lake-enabled scope is explicitly unavailable. Mixed
and wrong-pose IDs disqualify even when a valid restored contact frame has no event
detail. Empty wheel maps cannot vacuously satisfy stop. Existing five-field contact
and eight-field accident envelopes remain exact; checkpoint configuration already
pins the prepared policy through the normalized model.

**2037 passing checks:** focused session 53; resource/pipeline 174; contact contract
1466; fleet detector 111; checkpoint integrity 149; statistics lifecycle 51; live
accident sessions 33. All passing reports are complete/ok, exit 0, with zero engine
diagnostics. Existing aircraft provenance warnings remain in their logs.

The focused fixture is synthetic optional authoring, not stock calibration. It
performs a real 35 cm drop through the current kernel to a controlled full stop,
keeps M7 zero, and compares optional/unopted complete physics bytes over 1200 ticks.
It also checks detached observations, wrong pose/mixed contact, strict packets,
checkpoint continuation and rejected-step rollback. No interval peak or independent
physical T&G trajectory qualification is claimed; existing classifier regressions
remain the T&G rule coverage. Model revalidation is correctness-first and has no
production performance qualification.

Machine-readable report and full hashes:
`tmp/gp14-hull-observer-checks/integration-receipt.json`.
Latest focused receipt:
`final-loaded-source/godot-rec82pvk/report.json`.
Its log captures seven actual loaded Script UTF-8 hashes, avoiding a later workspace
file hash being mistaken for tested code. They matched current files at collection.

The original absence baseline was **not rewritten**. Its later strict run has
101 checks/11 failures, all input byte-identity changes external to this slice;
all 32 absent contact-description byte comparisons pass. Both the original hashes
and later input hashes are retained in the machine report, with the full failure
receipt under `retained-original-baseline-mismatch/godot-n__8h06o/`. This establishes
description compatibility, not a same-input whole-physics baseline comparison.
The paired noninterference test uses the same current source in both sessions.

Loaded source SHA-256 (full values also in JSON):

- ContactContract: `853dd541e179b393f36abb08501ff3431a1c6ecf35ac8eac7254325516e52b12`
- FlightSession: `08765ae4f72e3bab00e9dc2bc94ed315122f03ea30a6e98e903297426d398f62`
- profile: `f34856af99d353154c93b893473b60b0252f6ff778db0962fe650f441be8694a`
- adapter: `5ea8de929aebbca752f37243b6f73e915945a1d21de584b43b35eeef165c2366`
- focused test: `6086a0f37c557c2297a1e93aed05f0ccf25926d01b4930d571bff134ab5ff133`

No files staged or committed by this specialist. Existing GP-14 shared-events and
event-validation evidence and the root's final README paragraph were untouched.
