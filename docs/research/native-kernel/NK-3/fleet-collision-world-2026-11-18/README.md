# NK-3 fleet: live-configuration pins after the DR-19e collision-world change (2026-11-18)

**Symptom.** From commit `3c91936ab` (DR-19e: round-bale core boxes and a stepped pit-shelter roof in `app/scenery/collision_world.gd`), the NK-3 fleet policy (`research/native-kernel/test_fleet.gd`) failed 16 checks on Linux: "actual bounded reference failure retains the observed typed state" and "paired bounded proof requires both reference-owned reset outcomes" for the eight observed crosswind runway refusals (P-51D, Avanti, Turbo Lumber pack and ideal, both hull settings). It blocked the required NK-3 Linux job, and with it the release `export`.

**Bisection.** `git bisect run` on Linux (WSL, official 4.8-beta2 Linux editor, LF clone) between `c6e81947b` (last green CI) and `d407acd9d`: `f8c4ad8d` passes 598/0, `3c91936ab` fails 16. Windows runs are not usable for this: the GDScript reference differs across the Linux and Windows engines ([NK-4](../../NK-4/README.md)).

**Cause.** The fleet pins each refusal's live configuration, which includes the detached collision world's typed digest (index 7) and the checkpoint configuration (index 2), which embeds the world identity. The new proxies changed both. The runway behaviour did not change.

**Evidence.** Linux reference captures of the eight rows (`fleet_capture.gd`) are retained compressed:
- baseline at `f8c4ad8d`, raw SHA-256 `fbee9413…d54ad914`; all eight rows reproduce the V5 pins;
- candidate at `88d5a4e21`, raw SHA-256 `31502762…50e429ab`.

[`compare_fleet.gd`](compare_fleet.gd) is the [A35 recipe](../../../project-audit-2026-11-09/remediation/compare_fleet.gd) with indices 2 and 7 allowed. It passes **460 typed checks with zero failures** ([receipt](fleet-comparison.json)):
- the rows, refusal reasons, physical frame, setup, outcome and ownership fields are exact;
- only live indices 2 and 7 change, and both are valid changed hashes.

**Renewal.** `research/native-kernel/fleet.gd` gains `RUNWAY_LIVE_CONFIG_V6` with the candidate hashes, and `_fleet_start_proof_valid` uses it. `fleet_campaign.py` mirrors the same pins, and `test_fleet_campaign.py` checks the V6 producer. V5 stays as the retained baseline.

**Results.**
- Linux fleet policy: 598 checks, 0 failed.
- Fleet campaign Python tests: 67 passed.

To repeat, decompress each capture into a fresh scratch path and run the recipe with `OPENRC_AUDIT_LEFT`, `OPENRC_AUDIT_RIGHT` and a new `OPENRC_AUDIT_COMPARISON` path on the Linux editor.

This renews software pins after a collision-geometry change. It is not physical validation of the runway starts.
