# TT-05 — articulation of the imported model: signs, propeller sense, gear wrappers, clearances

2026-10-12 · **Status: complete.** Owning plan: [Timber integration](../../../TIMBER-INTEGRATION-PLAN.md). Code: `app/aircraft/timber_model.gd`, checks in `app/aircraft/verify_timber.gd` (runs in `app/test.sh`) and `app/aircraft/verify_timber_clearance.gd` (evidence only, about 10 min). Guide: [asset README](../../../../assets/aircraft/turbo-lumber-evolution/README.md).

## Design

- **Hinges** are the imported pivot nodes (`aileron_*_hinge`, `elevator_hinge`, `rudder_hinge`, `flap_*_hinge`) with records `{node, axis, rest, pivot, range_deg, positive, app_sign}`: `axis` is the rest basis' first column (the author's local +X hinge axis in the parent frame), `rest` the imported basis. A deflection sets `basis = Basis(axis, angle) * rest`, zero restores the import bit for bit. `apply_surfaces()` takes the app's degrees (trailing edge up / rudder right) and multiplies by `app_sign` (−1 ailerons, −1 elevator, +1 rudder) because the r1 pivots are positive trailing-edge down; flaps are positive down in both and `set_flaps()` clamps to the authored 0–40°.
- **Euler-driven nodes need wrappers.** `main.gd` writes `propeller.rotation.z`; `render/airplane.gd` and `render/ground_gear.gd` write `gear[*].rotation.x` and `gear.steering.rotation.y`. Those setters replace a node's whole basis, so an imported pivot with a rest rotation (the ±90° axles, the 90° tailwheel steer, the tilted thrust frame) cannot receive them directly. Each gets a mount that carries the rest basis and an identity child that takes the angle: `thrust_frame → propeller_mount (+Z = thrust axis) → propeller → propeller_spin`, `gear_*_suspension → wheel_*_spin_mount (inverse parent basis) → wheel_*_spin (on the axle centre) → wheel_*_axle`, `TurboTimberEvolution → tail_steering_mount → tail_steering → tailwheel_steer → … → wheel_tail_spin → tailwheel_axle`. The pivots keep their world transforms (checked to 1e-6); no mesh is reparented; the moved subtree gives up its scene ownership and the built root clears `scene_file_path` so `Node.duplicate()` (crash wreck) copies the modified tree instead of re-instantiating the GLB.
- **Conventions preserved without a Timber branch:** the exposed wheel nodes rotate about the root +X through the axle centre, so `ground_gear.gd`'s "+X axle, forward rolling = −X" holds; `tail_steering` rotates about +Y with positive = wheel trails right (the author's and the rudder's sense); `propeller.rotation.z = +θ` is a positive rotation about the thrust direction, i.e. clockwise seen from behind as the author declares.

## Proof (verify_timber.gd, 283 checks, PASS)

| Claim | Check |
| --- | --- |
| Aileron/elevator/rudder signs | ±10° per surface moves the aft-most rest vertex of that surface up/down (y) or right/left (x) by more than 3 mm; every other surface stays within 1 µm; the `Commands.surface_deflections_deg` path gives right roll = right aileron up/left down, pull = elevator up, right yaw = rudder trailing edge right |
| Horns, markings, torsion rod follow | For the elevator (4 surfaces) and rudder (3 surfaces), the vertex farthest from the hinge axis of every surface turns by exactly the applied angle (1e-4 rad); the airframe transform is unchanged |
| Pivot fixed, axis invariant, exact return | After full deflections, every hinge origin and `basis.x` equal the rest values; neutral restores `transform == rest` exactly |
| Flaps | `set_flaps(999)` → trailing edge down and the basis equals `Basis(axis, 40°) * rest`; `apply_surfaces` leaves flaps alone; `set_flaps(-30)` → rest |
| Inspector mapping | `apply_controls(1, 1, 1, 30)`: flaps and left aileron down, right aileron and elevator up, rudder right; neutral restores rest |
| Propeller | `propeller` is an identity node under `propeller_mount` under `thrust_frame`; the mount's +Z equals the thrust axis to 1e-6; the blade tip (radial 0.1403 m = measured radius) turned by `rotation.z = 0.3` sweeps +0.3 rad about the thrust direction (1e-5); hub, rotor origin, thrust frame and airframe unchanged; zero restores the rotor transform exactly |
| Wheels | `wheel_left_spin` sits on the measured axle centre; `rotation.x = −0.4` moves the wheel's top vertex forward (−z) with no lateral motion; the axle centre and axis are unchanged; zero restores exactly |
| Steering | `tail_steering.rotation.y = +0.3` moves the tail-wheel centre to +x (trails right) at constant height, turns the fork, and turns the wheel's spin axis by 0.3 rad; the wheel then spins about the steered axle; zero restores fork and wheel exactly |
| Instances | A second build is structurally identical; posing one (surfaces, flaps, propeller, steering) leaves the other at rest; meshes and materials are shared resources |

## Clearance sweep (verify_timber_clearance.gd)

Each control surface against the merged airframe mesh with the EX-04 pair checker (edge–triangle crossings both ways, vertex-inside parity, closest-distance gap): ailerons at ±34.5° (manual), elevator at ±17.8° (manual) and ±22° (authored limit), rudder at ±18.1° (manual) and +30° (authored limit), flaps at 36.6° (manual full) and 40° (authored limit).

| Result | Value |
| --- | --- |
| Penetrations | none in 14 pose/surface pairs |
| Gap at the hinge cove | 0.1 mm (ailerons, flaps at 36.6°, elevator); 0.0 mm = seam contact (rudder at every pose, flap at the 40° limit) |
| Cost | 1,000–4,100 nearby airframe triangles per pair, 13–90 s per pair, 636 s for the sweep on the dev VM |

The author modelled tight hinge coves: the control-surface noses sit inside recesses 0.0–0.1 mm from the skin, so the procedural models' 0.5 mm minimum does not apply; the script reports gaps below 0.5 mm as seam contact and fails only on penetration. The first run used the 0.5 mm rule and reported those 14 gap failures with no penetration; the committed script was then changed to the no-penetration criterion and rerun: `verify_timber_clearance: 14 checks, 0 failed, smallest gap 0.0000 m (643770 ms)`, same gaps per pair. Flap/aileron noses touching the skin at the authored limits are a visual-model property, not a mechanical claim.

## Review finding: propeller sense across the catalog

An independent review (2026-10-12) probed every propeller aircraft with `propeller.rotation.z = +0.3` and measured the blade-tip sweep about each airplane's forward axis: Stik −0.300, Extra −0.300, P-51 −0.300, Timber +0.300 rad. The Timber turns clockwise seen from behind, which is the author's declaration and the simulator's rotor convention (`sim/flight_session.gd` "J_p·ω along body +x (clockwise seen from behind)", `physics/dynamics.gd`, `rotor_sense +1`); the three procedural models' `propeller` nodes are root-aligned (+Z aft), so the same positive phase turns them counter-clockwise seen from behind. The Timber keeps the physically consistent sense; the contract is now stated in `render/airplane.gd`, and whether the three procedural propellers should be mirrored is the model owner's decision (plan §11). The review's other points were applied: `build_geometry.py` refuses an r2 whose hinge axes no longer point +X/+Y before emitting `app_sign`; `verify_timber.gd` compares the full world basis of every pivot (wrapped ones included) with the declared parent's basis times the imported rest basis (296 checks); the inspector's full pose uses the manual's 35 mm flap conversion (36.6°); `manifest.py` ignores `__pycache__`, `.pyc` and editor leftovers; the catalog test's preview check now ties `has_propeller` and visibility to the meshes under the node.

## Limits

Signs are proven against the app's conventions and the author's declarations, not against the real aircraft's linkage. Suspension stays at rest; cosmetic cables do not follow a leg. The clearance checker treats the merged airframe as one closed mesh set; coplanar seam contacts register as zero gap without a crossing. Live gear animation, steering sign against the simulator and flap flight behaviour are TT-11/TT-14.
