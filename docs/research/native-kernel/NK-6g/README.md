# NK-6g — ground-level lake reach and the guard's published collapse

2026-11-27. Windows 11 x86_64, pinned Godot 4.8-beta2, MinGW-w64 GCC 15.2.0, the [NK-4](../NK-4/README.md) build route
and its nineteen installer gates. Plan: [F1 per-tick cost](../../../plans/optimization-priorities.md#frame-stalls-and-sustained-fps).
Follows [NK-6f](../NK-6f/README.md).

## Why

A headless profile of a Corsair at idle on the runway after NK-6f ranked two ground costs that repeat work already
answered elsewhere in the same tick:

- The contact resolution ran `LakeCollision.first_hit_sampled` on every tick (`_first_hit_core` about 47 µs
  profiled), although the lake lies about 100 m from the runway. The [NK-5d](../NK-5d/README.md) native reach proof
  is vertical only: it compares the probes' lowest point with the highest possible water, and it never holds at the
  datum. The sweep itself rejects such ticks horizontally, after validating its inputs and measuring its probe radius.
- The pre-tick guard's `gear_collapsed(sim.state)` evaluated `Ground.compressions` in GDScript (about 53 µs profiled
  with the terrain microrelief), although the contact observer had just measured the same endpoint's compressions
  ([NK-5e](../NK-5e/README.md)).

## Change

- `nk_contact_reach.hpp`: `reach_clear` takes the lake bank's bounds (`LakeCollision._polygon_bounds`, north then
  east). The sweep tests its swept probe box (the CG path widened by its probe radius) against them with
  `_aabb_overlaps`. That box lies inside the proof's superset box (three times a larger radius plus rounding margins),
  so a superset box that misses the bank also proves a null sweep. `nk_kernel.cpp`: `contact_reach` passes them.
- `flight_session.gd`:
  - `_lake_bank_bounds` computes the bounds once per lake dictionary.
  - The pre-tick guard asks `published_gear_collapsed(sim.state)`, which follows `Ground.collapsed`'s checks in its
    order. It reads the compressions published for this endpoint while the state and aux bits are unchanged, and
    evaluates them itself otherwise.
  - Test hooks: `lake_bank_proof_enabled`, `guard_published_collapse_enabled`.
- `native_stage.gd`: `contact_reach` forwards the bounds.

## Evidence

- `app/tests/test_native_ground_guard.gd`: 21 checks, none failed, for the Corsair, Ugly Stik 60 and Turbo Lumber.
  - 4,000 ground-level tick pairs per aircraft at random distances from the bank box, one in three over the water:
    every lake proof (1,778–1,813 per aircraft, all from the bank box) matches a null `LakeCollision` sweep, and none
    lies over the water. `test_native_contact_reach.gd` (NK-5d) also checks every proof against the sweep, among
    real lake hits.
  - A full-power takeoff roll, a slow taxi along the bank and a hard landing fly byte-identical with both shortcuts on
    and both off, checkpoint by checkpoint. The hard landings of the Corsair and the Stik end in the same gear travel
    limit crash on the same tick.
- All nineteen installer gates are identical for binary
  `0ddbdc1a23cf9ea9a65f88618bf66937b53b48bfe33428bb18c97bf96399630f`, and the mutant build still fails. Accepted
  results (tool root, not in Git):
  - `stage-20261127T060813477636Z.json` `ce7359b3d769fcd6f237d818cc3fe3df5001dfd96d7af97f0d0aeb764692fc8d`
  - `stage_mutant-20261127T060840608865Z.json` `c8cc188726c50682b49de734d9cd844892034b608e2ed3cf38f940324e249cec`
  - `trajectory-20261127T060907866067Z.json` `9d837a3221703a2dc55f3c6871cebb94384f03961451b0a307dc384fe0257de9`
  - `liquid-stage-20261127T061114662106Z.json` `3ca2443e0a7236c434861441245a7a37c03c50a3700ca56b7c6bd41ffe47c23c`
  - `legacy-ground-20261127T061258299525Z.json` `a91b414a14326a8a16a056c3bb6273c045668fbd51eca3327db438a71f8b42d6`
- With the native stage installed, 200 affected suites pass:
  - all native suites and every contact, crash, hull, lake and ground suite;
  - gear, strike, runway, retract and statistics suites;
  - replay integrity and policy, reset publication and golden flights.

  `test_fixed_gear_brake_input` needs the checked runner's legacy oracle.

## Gain

Headless, alternating 120-tick blocks of the same flight with both shortcuts on and off (whole tick: session input
and `Simulation._physics_process`):

| Aircraft | On the runway | Airborne |
| --- | ---: | ---: |
| Corsair | 506 → 455 µs | 335 → 322 µs |
| Ugly Stik 60 | 368 → 302 µs | 180 → 176 µs |
| Turbo Lumber | 384 → 328 µs | 214 → 212 µs |

## Limits

- Windows only was built and installed locally; CI's three native-kernel jobs requalify each platform on push.
