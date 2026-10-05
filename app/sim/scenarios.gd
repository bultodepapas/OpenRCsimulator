# Starting conditions for the simulation. 64-bit floats only (guarded).
# Mass and inertia come from the aircraft data file (ROADMAP D1, app/data/aircraft/).
extends RefCounted

const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const Trim := preload("res://physics/trim.gd")

const AIRCRAFT := "res://data/aircraft/jensen_ugly_stik_60.json"

## C6: thrown across the pilot's view. 60 m north, 40 m to the west, 30 m up, heading east at 15 m/s.
## With gravity only (no lift until Phase D) it is a ballistic arc: ~2.5 s to the ground.
static func throw_across_view() -> PackedFloat64Array:
	return RB.make_state(M.v3(60.0, -40.0, -30.0), M.v3(15.0, 0.0, 0.0), M.q_from_euler(PI / 2.0, 0.0, 0.0), M.v3(0.0, 0.0, 0.0))



## D4: trimmed power-off glide across the pilot's view (no engine until D5). Same place and heading as the throw.
## Returns the Trim result; its pitch_command is the elevator trim the pilot needs (like a radio trim tab).
static func trimmed_glide_across_view(model: Dictionary, g: float, max_elevator_rad: float, speed := 15.0) -> Dictionary:
	var t := Trim.solve("glide", speed, model, g, max_elevator_rad)
	t.state = Trim.state_for(speed, t.alpha, t.gamma, PI / 2.0, M.v3(60.0, -40.0, -30.0))
	return t
