# NK-6j — the pre-tick guard's gear collapse from the native stage

2026-11-27. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6g](../NK-6g/README.md).

## Why

Real timers put the pre-tick guard's gear collapse check at 6–16 µs per tick, airborne too. It was
`published_gear_collapsed` since NK-6g. Most of that time went to its GDScript around the reused compressions:
retractable gear posing, lake validation and the byte comparisons of state and aux.

## Change

- `nk_kernel.cpp`: `stage_guard_collapsed(s, aux)` compares `stage_compressions(s, aux)` with each posed contact's
  `max_compression`. That is the same answer NK-5i's endpoint facts give. `stage_compressions` already refuses
  whatever it cannot answer exactly: an invalid state, an unmatched retraction pose, an invalid surface table or an
  invalid lake. The function returns 1 or 0, or -1 for the reference.
- `native_stage.gd`: `guard_collapsed`.
- `flight_session.gd`: `_guard_gear_collapsed` asks only for the last publication's natively measured endpoint
  (`_native_facts_tick == sim.tick`), without an RC track, for this class. Resets and restores drop that tick. Test
  hook: `native_guard_collapse_enabled`.

## Evidence

- `app/tests/test_native_ground_guard.gd`: 30 checks, none failed, for the Corsair, Ugly Stik 60 and Turbo Lumber.
  - 3,000 perturbed states each, from clear of the ground to past the gear's travel: every native answer equals
    `gear_collapsed`. Between 1,742 and 1,940 of them are collapsed.
  - Takeoff rolls, a bank taxi and hard landings fly byte-identical with the guard shortcuts on and off. The native
    guard answered 1,439 of 1,440 rolling ticks. The hard landings end in the same gear travel limit crash on the
    same tick.
- All nineteen installer gates are identical for binary
  `a97aba654464f90d7620d56050fec840a6192e108366be0159a11d48149940a3`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T080321352114Z.json` `6ba573e9b5633d01c337bd25b08a9e54a7ef60693546ddac55b70a81ef021eff`
  - `stage_mutant-20261127T080347504245Z.json` `c0edd1e5b10f65112d65e358de663f3526a18b08429383e69448d2ae21679ae3`
  - `trajectory-20261127T080413645514Z.json` `eff5d6214b85278b1d4e3f2798afccab19b9b07822d541c44bc8c4a63ed7b566`
  - `legacy-ground-20261127T080754150259Z.json` `a0d8195430ca06e06187edce112a238ee7064fe96f905f603e2fa4c23973b5e1`
- With the native stage installed, 115 of 116 affected suites pass:
  - native, crash, gear, retraction, ground, hull, contact, strike and lake collision suites;
  - golden flights, replay integrity and policy, and reset publication.

  `test_fixed_gear_brake_input` needs its legacy-engine gate (`tools/godot/fixed_brake_legacy.py`). That gate failed
  locally on a Windows file lock in its temporary engine folder, as it did before this change.

## Gain

Headless, alternating 120-tick blocks with the native collapse on and off (whole tick):

| Aircraft | Airborne | On the runway |
| --- | ---: | ---: |
| Corsair (retractable gear) | 368 → 335 µs | 378 → 367 µs |
| Ugly Stik 60 | 165 → 159 µs | 289 → 288 µs |
| Turbo Lumber | 210 → 211 µs | 341 → 336 µs |
