# NK-3 fleet: live-configuration pins after the FPV tree descriptors (2026-11-25)

**Symptom.** From commit `3cd6efa05` (FPV frame obstacle contact and tree profiles), the NK-3 fleet policy
(`research/native-kernel/test_fleet.gd`) failed 16 checks on Linux. The failures were "actual bounded reference failure
retains the observed typed state" and "paired bounded proof requires both reference-owned reset outcomes" for the
eight observed crosswind runway refusals (P-51D, Avanti, Turbo Lumber pack and ideal, both hull settings). It failed
the required NK-3 Linux job at "Require paired native runtime-domain refusal proofs". The failure stayed hidden while
the CI preflight failed for an unrelated reason and skipped every native job (fixed in `ec0e4e1e0`).

**Cause.** `3cd6efa05` adds an `fpv_tree` descriptor to each tree proxy in `app/scenery/collision_world.gd`. The fleet
pins each refusal's live configuration, which includes the detached collision world's typed digest (index 7). It is
the only scenery change between the last green NK-3 Linux run (`0b4a3998b`) and `065e21263`. Unlike the
[18 November renewal](../fleet-collision-world-2026-11-18/README.md), the checkpoint configuration (index 2) does not
change.

**Evidence.** Linux reference captures of the eight rows (`fleet_capture.gd`, official 4.8-beta2 Linux editor under
WSL, LF checkouts) are retained compressed:

- baseline at `0b4a3998b`, raw SHA-256 `d2972b4d…02886d9e`; all eight rows reproduce the V6 pins;
- candidate at `065e21263`, raw SHA-256 `6bbc922b…44930562`.

[`compare_fleet.gd`](compare_fleet.gd) is the [A35 recipe](../../../project-audit-2026-11-09/remediation/compare_fleet.gd)
with only index 7 allowed to change and index 2 required to stay identical. It passes **460 typed checks with zero
failures** ([receipt](fleet-comparison.json)):

- the rows, refusal reasons, physical frame, setup, outcome, ownership and checkpoint configuration are exact;
- only live index 7 changes, to a valid hash.

**Renewal.** `research/native-kernel/fleet.gd` gains `RUNWAY_LIVE_CONFIG_V7` with the candidate hashes, and
`_fleet_start_proof_valid` uses it. `fleet_campaign.py` mirrors the same pins, and `test_fleet_campaign.py` checks the
V7 producer. V6 stays as the retained baseline.

**Results.**

- Linux fleet policy (`test_fleet.gd`, verified native library absent locally): 598 checks, 0 failed.
- Fleet campaign Python tests: 67 passed.

To repeat, decompress each capture into a fresh scratch path and run the recipe with `OPENRC_AUDIT_LEFT`,
`OPENRC_AUDIT_RIGHT` and a new `OPENRC_AUDIT_COMPARISON` path on the Linux editor.

This renews software pins after a collision-data change. It is not physical validation of the runway starts.
