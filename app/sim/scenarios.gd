# Starting conditions for the simulation. 64-bit floats only (guarded).
# Mass and inertia come from the aircraft data file (ROADMAP D1, app/data/aircraft/).
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const AIRCRAFT := "res://data/aircraft/jensen_ugly_stik_60.json"

## C6: thrown across the pilot's view. 60 m north, 40 m to the west, 30 m up, heading east at 15 m/s.
## With gravity only (no lift until Phase D) it is a ballistic arc: ~2.5 s to the ground.
static func throw_across_view() -> PackedFloat64Array:
	return RB.make_state(M.v3(60.0, -40.0, -30.0), M.v3(15.0, 0.0, 0.0), M.q_from_euler(PI / 2.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0))

