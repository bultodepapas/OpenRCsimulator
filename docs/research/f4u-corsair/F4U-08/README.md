# F4U-08: ground handling data for the 1/4.5 Corsair

Derived 2026-10-22 for the [F4U plan](../../../F4U-PLAN.md). Software derivation; RC ground measurements (static sag, drop tests, taxi) remain open.

## What changed

| Item | Before | Now | Source |
| --- | --- | --- | --- |
| Contacts | R59 tyre's lowest vertex, 12 mm inboard of the wheel plane | Wheel centre minus radius in each wheel's plane: mains (0.0607, ±0.4311, −0.5307) m, tail (1.4118, 0, −0.1833) m in the le frame | g1.3 compiled rig ([model-geometry.json](../../../../assets/aircraft/f4u-corsair-250/model-geometry.json), F4U-05) |
| Retraction paths | 129 samples through R59's rig | 101 samples of the wheel-bottom point through the delivered g1.3 `GearRetract`, so physics follows what the renderer draws | the same |
| Gear travel | Borrowed from the P-51 (0.12 / 0.105 m) | Mains 0.100 m, tail 0.110 m by the GP-06c rule | [GP-06c](../../ground-physics/GP-06/README.md): 1.05 × the §23.727 reserve-drop peak, rounded up to 5 mm |
| Wheel profile | None | Main radius 0.094 m, tail 0.0389 m (g1.3); inertia from the P-51's wheel masses scaled by radius cubed; 2.0 N·m pneumatic main brakes (about 0.2 g, below the 7.4 N·m friction limit of the static main load); no tail brake | [wheel_profiles.json](../../../../app/data/ground/wheel_profiles.json), estimates as the P-51 (P51-11c) |
| Prop-strike geometry | R59's four-blade visual propeller | The physical 30 in propeller, which the renderer now draws (shaft propellers scale to their physical diameter, as glow propellers already did) | [render/airplane.gd](../../../../app/render/airplane.gd) |

Wheel stiffness and damping stay on the shared E1 rule (heave ω·dt 0.09 at 240 Hz): 21 mm static sag, 6.9 % of the weight on the tail wheel. Tail-wheel steering ±25° linked to the rudder and the 4 s retract cycle remain estimates (no Sierra timing published).

## Reserve drop (app/tests/test_gear_reserve_energy.gd `drop()`)

| Attitude | Sink | Peak compression mains / tail (mm) | Travel (mm) | Load factor |
| --- | --- | --- | --- | --- |
| Mains level | 2.13 m/s (limit) | 78.1 / 69.3 | 100 / 110 | 3.89 |
| Mains level | 2.56 m/s (reserve) | 92.5 / 66.4 | 100 / 110 | 4.62 |
| Three-point | 2.13 m/s | 72.1 / 86.9 | 100 / 110 | 4.08 |
| Three-point | 2.56 m/s | 85.4 / 102.3 | 100 / 110 | 4.84 |

Worst reserve case 93 % of travel (tail, three-point). Three-point attitude 14.4°.

## Limits

The FAR drop rules are a borrowed full-size convention. Stiffness is a numerical rule, not a measured RC gear. The CARF manual's ground-handling notes (full power on take-off lifts the tail beyond the low-rate elevator; land tail-up) are checked in [F4U-12](../F4U-12/README.md), not here.
