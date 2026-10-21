# AFC-07 R1: traffic scheduler contracts

2026-10-20, Godot 4.7.2, Windows. The isolated
[traffic harness](../../../../research/ai-companions/traffic/README.md) implements
runway reservations/physical blockers, activity leases/quotas and fleet-wide
incident opportunities. **These remain draft helpers outside the live game.**
Their tests establish scheduling contracts, not qualified flight paths.

The primary harness passes with zero engine errors/warnings. It checks an
independent runway-priority oracle, age promotion, stale generations, player
incursions, wind-direction dwell, reservation expiry, persistent wrecks,
independent overlapping occupants, quota eligibility/cooldowns, lossless RNG
restore, incident opportunity rates, filtered outcomes and bounded episodes.

Review exposed lost occupancy when a player or foreign wreck overlapped a live
AI. Physical blockers now remain independent by owner/generation, alongside a
separate wreck map. Removing one blocker never releases another, and both
footprint and protected-path clearance are required for normal release.

An additional **20 boundary checks** pass. They cover future request times,
malformed/unknown state and event fields, transactional restore rejection,
pre-grant completion/retirement, duplicate weighted choices, malformed incident
eligibility/identities, bounded family iteration and exact-deadline retry.
The failed initial run is retained: it exposed future grants and a string-to-bool
script error. Later reports establish the fixes; a completion marker alone is
never accepted over engine errors.

`verification.json` records the source hashes and accepted reports. `checks/`
retains original runner diagnostics, including that rejected baseline. Commands
and API semantics have one home in the harness README.

Open integration gates: actual runway/taxi/protected-volume observations,
qualified flight and recovery state machines, current-tick intent submission,
full fleet journal/restore, bounded event consumption and player request UI.
The current production circuits and Incidents Off configuration are unchanged.
