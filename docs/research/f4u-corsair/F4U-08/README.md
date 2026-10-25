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

## F4U-08-R1: retracting tyre support, 2026-10-25

The earlier contact generator subtracted the wheel radius along model up at every extension. The Corsair's main wheels turn through 90° during retraction: when stowed, the resulting points were **63.9 mm below the visible tyres**. The shared unlocked-gear collision law could therefore report contact before the tyre reached the ground. The existing verifier checked wheel centres during retraction and contacts only when downlocked, so it missed this defect.

`compile_model.py` now measures the lowest vertices of each frozen g2.2 tyre mesh through all 101 sampled carrier poses. It averages tied support vertices after removing material/seam duplicates. The existing downlocked wheel-plane point is retained after checking its height against the mesh. `derive_physics.py` consumes these paths; the model manifest, Workshop descriptor and customization proofs are regenerated normally. No GLB, rig pose or shared solver code changes.

The three downlocked positions, all stiffness/damping/travel/steering values, wheel profiles, mass and aerodynamics retain their previous values. Only unlocked path coordinates and their descriptions change in the aircraft data. The Corsair is not a baked parked-aircraft entry, so no parked asset depends on its manifest.

### Verification

Windows, Godot 4.8-beta1. [Source hashes, checked-runner reports and results](checks/contact-review-2026-10-25.json).

| Check | Result |
| --- | --- |
| `verify_f4u.gd` | 53/53. The imported tyres are measured independently at 101 samples plus 100 midpoints. Maximum vertical contact/mesh error: 0.0331 mm on each main wheel, 0.0194 mm on the tail wheel |
| Unlocked contact boundary | At each of the 200 unlocked poses per wheel, the production collision law stays clear 2 mm above the measured tyre bottom and detects contact 2 mm below it. Each wheel is isolated from other supports and the hull for this check |
| Negative control | The same verifier against a disposable copy of the old aircraft data fails exactly four checks: vertical agreement and premature contact for each main wheel; worst errors 63.8759/63.8749 mm |
| `test_gear_reserve_energy.gd` | 19/19. Corsair reserve peaks remain 92.5 mm at the mains and 102.3 mm at the tail, within 100/110 mm travel |
| `test_aircraft_liveries.gd` | 179/179, including all thirteen production builds and bindings |
| Source pipeline | Model compiler, physics derivation, model manifests, Workshop descriptors and customization `--check` all pass |

A new [baseline recording](checks/contact-baseline-2026-10-25.orfl) was captured before the data change with the existing F4U-12 2,400-tick airborne tape and its maneuver markers. Its [exact replay](checks/contact-exact-2026-10-25.json) completed with `solver_changed: false`. The [candidate replay](checks/contact-candidate-2026-10-25.json), using the new aircraft and the same input tape, also completed with the solver unchanged; [comparison](checks/contact-comparison-2026-10-25.json) has zero difference in every channel. Both CSVs are byte-identical to the already retained [F4U-12 CSV](../F4U-12/baseline.csv), SHA-256 `33214fffbfd3b5acda3997033b4314f9b31f9801f604d6f35306e832b42eb859`.

This establishes airborne preservation and the tested contact boundary, not physical validation. The shared law still uses sampled points in the body/model frame; it does not continuously solve tyre contact geometry for arbitrary attitude, steering, tyre deformation or terrain normals. The hull probes are unchanged. The full application suite and export were not rerun.
