extends SceneTree
const FlightSession := preload("res://sim/flight_session.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")
const RB := preload("res://physics/rigid_body.gd")
const GroundEffect := preload("res://physics/ground_effect.gd")
func _initialize() -> void:
	var session := FlightSession.new()
	session.setup("res://data/aircraft/p51d_mustang_120.json")
	root.add_child(session)
	session.input_enabled = false
	var loop := { mode = "level", speed = 27.0, altitude = 150.0, duration = 8.0, sticks = func(t: float, _s: PackedFloat64Array) -> Dictionary:
		return Maneuvers._pulse(t, 0.2, 8.0, { pitch = 0.7, throttle_delta = 1.0 }) }
	var lt: RefCounted = Maneuvers.fly(session, loop)
	var min_clear := 1e9
	var active := 0
	for r in lt.row_count():
		var alt: float = lt.value(r, "alt_m")
		var s: PackedFloat64Array = session.start.state.duplicate()
		s[RB.POS] = lt.value(r, "north_m")
		s[RB.POS + 1] = lt.value(r, "east_m")
		s[RB.POS + 2] = -alt
		var g: float = session._ground_up(s)
		if not is_nan(g):
			active += 1
			min_clear = minf(min_clear, alt - g)
	var first_crash := -1
	print("crash: ", session.crash, " alt0 ", lt.value(0, "alt_m"), " alt@1s ", lt.value(240, "alt_m"), " start alt ", -session.start.state[RB.POS + 2])
	print("reach %.2f, max terrain %.2f, rows %d, rows with ground sampled %d, min clearance %.2f m, min alt %.1f" % [session._ground_effect_reach,
		preload("res://physics/ground_terrain.gd").max_height_validated(session.ground_surfaces), lt.row_count(), active, min_clear, _min(lt, "alt_m")])
	print("cols ", lt.columns().slice(0, 40))
	for r in range(0, lt.row_count(), 60):
		print("t %.2f alt %.1f V %.1f pitch %.0f roll %.0f q %.2f alpha %.1f p %.2f" % [r / 240.0, lt.value(r, "alt_m"), lt.value(r, "speed_mps") if "speed_mps" in lt.columns() else NAN, lt.value(r, "pitch_deg"), lt.value(r, "roll_deg"), lt.value(r, "q_radps"), rad_to_deg(atan2(lt.value(r, "w_mps"), lt.value(r, "u_mps"))), lt.value(r, "p_radps")])
	quit(0)
func _min(t: RefCounted, c: String) -> float:
	var m := 1e30
	for r in t.row_count():
		m = minf(m, t.value(r, c))
	return m
