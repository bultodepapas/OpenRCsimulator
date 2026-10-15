# RCV session persistence audit

**Date:** 2026-10-14. **Scope:** checkpoint validation, recording failure lifecycle, recovery provenance, and replay inputs in `app/sim/ground_vehicle/session.gd`. Discovery started with the indexed `C-DEVELOPMENT-OpenRCsimulator` graph; it had no session-file coverage, so findings were verified against the current source and focused Godot fixtures.

## Findings and fixes

| Severity | Reproduction before the fix | Change |
| --- | --- | --- |
| Low, internal consistency | In the rolling-wall fixture, reach a damaged contact, request throttle 0.8, set `applied_controls_f64_base64` to a valid four-value control blob whose throttle is 0, recompute the public `checkpoint_sha256`, and call `can_restore_checkpoint`. It returned true even though the saved applied throttle was below requested throttle times the saved drive scale. | Checkpoint validation now applies that monotone post-tick lower bound, with a `1e-12` float tolerance. A rehashed under-bound checkpoint is rejected without mutating the session. |
| Medium, run provenance | Call `manual_recovery()`, obtain `checkpoint()`, change `run_valid` to true, and recompute `checkpoint_sha256`. The checkpoint was accepted while carrying a recovery action. Removing its `manual_recovery` event and recomputing both event and checkpoint hashes was also accepted. | A checkpoint with recovery actions cannot claim a valid run, and each action must match one recovery history event by tick and spawn ID. Matching uses counted tick/spawn pairs in linear time, preserving repeated recoveries at one tick while rejecting count mismatches and malformed entries. |
| Medium, recording provenance | Start recording, provide a neutral armed sample, resume, then submit a sample with `throttle = NAN`. The tick failed safely, but `recording` stayed true and metadata still said `run_valid: true`, with zero recorded ticks and one sample. | Fail-safe now interrupts an active recording once, retains the prefix, sets recording metadata invalid, records the fault reason, and emits one interruption. A faulted session cannot start a new recording. The prefix remains exportable. |

The throttle lower bound is an internal-consistency check: drive damage only increases during a run, so the scale before the last tick is at least the saved post-tick scale. It is **not authentication or proof of physical reachability**. Checkpoint hashes are public and can be recomputed. No continuation divergence was established by the original throttle-tamper probe; the defect was that contradictory telemetry was accepted. Damage identity continues to come from `Damage.SNAPSHOT_VERSION` (currently 2, 19 float64 slots); this did not require a checkpoint or recording format bump.

## Verification

The focused regressions are in `app/tests/test_rcv_session.gd` and `app/tests/test_rcv_damage_session.gd`. They cover rejection after rehash, unchanged state/damage on rejection, recovery history consistency (including duplicate same-tick actions/events and a removed duplicate), malformed history entries, interrupted-prefix export, repeated rejected ticks, and refusal to start recording while faulted. The standalone diagnostic is `research/rc-monster-truck/audit/session/applied_control_checkpoint_probe.gd`.

On Windows with Godot 4.7.2, the source and both test scripts parsed with `--check-only`. Hidden bounded headless runs reported `RCV session: 101 checks, 0 failed` and `RCV damage Session: 19/19 checks passed`; the standalone diagnostic passed all three consistency checks. The 19-slot damage snapshot currently identifies as version 2.
