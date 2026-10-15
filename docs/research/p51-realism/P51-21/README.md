# P51-21: P-51 qualified for the product runway start

2026-10-14 · Revision 1 · **Status: implemented and software-verified; pilot taxi/takeoff review and measured wheel breakaway remain open.** Prefix: P51-21. [Plan](../../../P51-REALISM-PLAN.md)

## Finding

Players could start the P-51 only in the air. The runway start solves a stiction-anchored equilibrium at the field threshold, and it was limited to the aircraft in `FlightSession.RUNWAY_AIRCRAFT_IDS` that carry `landing_gear.breakaway_factor`. The solver already supports taildraggers (`GroundStart._aft_tricycle_support_pose`), which is how Timber qualified in TT-11. The P-51 had a wheel profile but no stiction data, so its tests built a ground pose by hand. Without stiction, the parked idle case crept 4.3 m with 8° of yaw in 10 s.

## Change

| Path | Change |
| --- | --- |
| `research/p51/p51-05/derive_physics.py` → `app/data/aircraft/p51d_mustang_120.json`, Workshop descriptor | `landing_gear.breakaway_factor` 1.25, `estimated`: the shared E3b1 value and bracket (1.0–1.5, unmeasured), as for the Stik and Timber. |
| `app/sim/flight_session.gd` | `p51d-mustang-120` added to the qualified list. Home, preferences and capture already consume that list. |
| `app/tests/p51_envelope_base.gd` | Ground cases start from the product runway start, and its solved anchors are kept. Airborne cases keep the airborne reset's sliding anchors, the same state the session uses for any landing. A hand-built ground pose with stiction is refused. |
| `app/tests/test_runway_start.gd`, `app/tests/test_ui_runway.gd` | The P-51 moved from the refused list to a positive check: it enables the Home runway selector. The Extra stays refused. |
| `research/p51/p51-15/ground_probe.gd` | Same fixture change, so the P51-15 ground probe keeps working with stiction. |

`test_prop_strike.gd` iterates over the qualified list, so it now checks P-51 clearance at rest and a 2 s full-throttle run without a propeller strike. From the data, the four-blade 26-inch tips clear the ground by 0.31 m in the 14° three-point attitude and by 0.18 m tail-up.

## Evidence

Godot 4.7.2, native Windows, at `HEAD` `b09aa200` plus this change ([logs](tests/)).

- **Runway equilibrium:** three contacts, pitch 14.26°. The static wheel loads are solved by `GroundStart` with stiction anchors.
- **Idle on the mown runway with the stick back:** 0.000 m and 0.0° in 10 s, against 4.3 m and 8.0° with the old pose and no stiction. Idle thrust is 18.8 N; the hold is 1.25 × rolling resistance.
- **Takeoff from the product start, heading-hold pilot:** lift-off 4.52 s, 49.1 m, 25.18 m/s; rudder-free heading change −38.7° (left swing). 240/480 Hz agree within 0.4 %.
- **Lifecycle:** checkpoint replay exact (maximum delta 0) with anchors included; the deliberate crash restarts exactly after 1.5 s. Probe reports: [240 Hz](runway-ground-240.json), [480 Hz](runway-ground-480.json).
- **Passing tests:** `test_runway_start` 18/18, `test_prop_strike` 34/34, `test_ui_runway` all, `test_trace_metadata` 341, `test_aircraft_catalog` 98, `test_checkpoint` 92, `test_flight_log` 3247, `test_aircraft_data` 87, `test_ground_effect` 50, `test_crash_proportional` 49, and the coupled-shaft suites.
- **Unrelated failures:** `test_start_choice` fails the same three generic refusal checks at `HEAD` without this change ([log](tests/test_start_choice-head.log)).
- **Unchanged P-51 failures:** the lift-off band and the loop are the [P51-22](../P51-22/README.md) regression; stall recovery is P51-19.

## Limits

The 1.25 breakaway factor is a shared estimate; a luggage-scale pull on a built model would measure it. A real quarter-scale P-51 usually has wheel brakes with its retracts, but brakes are not modelled for this aircraft. Taxi feel, takeoff swing correction and the three-point visual still need a pilot's review.
