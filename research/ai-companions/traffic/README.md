# AFC traffic scheduling draft

This isolated Godot 4.7.2 harness contains deterministic scheduling groundwork
for AFC-07, AFC-13/17 and AFC-19. It is research code; none of these classes is
connected to the production flight or companion runtime.

`RunwayCoordinator` accepts same-boundary requests through `submit_request()` and
grants one after `resolve()`. `enter_runway()` requires the returned ticket and
exact owner generation. `observe_player()` handles advisory requests, approach
priority and implicit player occupancy. `update_wind()` accepts a signed headwind
component (positive favors direction +1), crosswind and gust magnitudes; direction
changes require 2,400 consistent ticks and remain locked while occupied or while
a committed arrival waits. Each request carries a finite, nonnegative
`max_tailwind_mps` (last optional argument, default zero). Tailwind is checked
against the effective request direction at grant time and whenever wind changes;
an invalid reservation is revoked and queued immediately, even during direction
hysteresis. An occupied runway remains physically blocked. The caller must use
an aircraft's qualified envelope; this helper does not establish one. Snapshot
version v4 requires this bound explicitly. `report_clearance()` requires both swept-footprint and
protected-path clearance. `report_runway_wreck()` retains every blocker until
`clear_wreck_and_occupancy()` commits removal of the matching wreck identity.
Reservations expire; occupied and blocked states do not. Request, queue, wreck,
event and snapshot sizes have hard bounds.

`ActivityQuotaScheduler` provides seeded weighted activity selection, one queued
request per pilot generation, quota-key leases, minimum duration, completion
cooldown, mandatory grant-time eligibility rechecks and explicit safety
preemption. Before each `resolve()`, the caller supplies a strict boolean
`eligible` result keyed by every pending request ID; a missing or malformed
entry rejects the whole boundary without changing scheduler state. Its leases
reserve intent only; route feasibility and flight control remain with their
owners.

`FleetIncidentScheduler` uses fixed-step exponential waiting times for fleet-wide
rates: Off 0, Rare 1/20, Occasional 1/8 and Lively 1/3 opportunities per simulated
minute. The first opportunity follows the 60-second grace period. Timing, pilot
selection and crash-prone family selection have saved independent RNG states.
Each opportunity requires a snapshot at its exact tick; a missed snapshot is
rejected without mutation, so present eligibility is never applied to past
opportunities. Started episodes have a bounded 30-second deadline; timeout emits
a cancellation with a recovery-required signal and does not claim recovery.
Episode choices are classified `{family_id, crash_prone}` records; crash-prone
families remain opt-in and capped at 25% of eligible starts.

All three classes expose versioned snapshots made only from primitive serializable
values. Their event buffers, queues, leases, cooldown history and tracked pilot
sets are bounded. Future runtime adoption still needs flight-owner review and the
plan's own integration and replay gates.

These snapshots are native Godot Variants. Use lossless binary Variant transport
for the signed 64-bit RNG states; JSON number serialization is not a supported
checkpoint transport for this draft.

Boundary validation also rejects future grants, malformed runway event snapshots,
duplicate weighted activity IDs, coerced eligibility and fractional incident
identities. Invalid incident roster snapshots preserve the exact opportunity
deadline and RNG state for a corrected retry. An incident snapshot is limited to
128 distinct pilot/owner-generation pairs and 64 families per pilot. The runtime
clock owner must still submit current, ordered facts; these helpers do not prove
their geometry or physical feasibility.

Run the independent runway and filtered-incident oracles, fairness,
stale-generation, wind, player-incursion, wreck, quota, eligibility, replay-state
and Poisson checks from the repository root:

```powershell
python tools/godot/run_checked.py --warnings-as-errors --timeout 90 --require-text "PASS traffic scheduler draft checks" -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path research/ai-companions/traffic --audio-driver Dummy --script res://test_traffic_schedulers.gd
python tools/godot/run_checked.py --warnings-as-errors --timeout 60 --require-text "scheduler boundaries: 20 checks, 0 failed" -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path research/ai-companions/traffic --audio-driver Dummy --script res://test_scheduler_boundaries.gd
python tools/godot/run_checked.py --warnings-as-errors --timeout 60 --require-text "runway tailwind: 19 checks, 0 failed" -- .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path research/ai-companions/traffic --audio-driver Dummy --script res://test_runway_tailwind.gd
```

The source-bound review receipt is [AFC-07 R1](../../../docs/research/ai-companions/AFC-07-R1/README.md).
