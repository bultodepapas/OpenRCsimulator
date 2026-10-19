extends SceneTree
const MainScene := preload("res://main.tscn")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var main: Variant = MainScene.instantiate()
	main.set("accident_reports_enabled", false)
	main.set("aircraft_id", "stik-glow-61fx-2t")
	root.add_child(main)
	await process_frame
	var session: Variant = main.get("session")
	var director: Variant = main.get("_crash_director")
	session.input_enabled = false
	session.set_physics_process(false)
	var initial: float = session.aircraft.model.propulsion.glow.initial_fuel_kg
	session.sim.continuous[1] = 0.25 * initial
	var s: PackedFloat64Array = session.sim.state.duplicate()
	var hull: PackedFloat64Array = session.aircraft.model.crash_hull
	var deepest := -INF
	for i in range(0, hull.size(), 3):
		deepest = maxf(deepest, M.q_rotate(RB._att(s), hull.slice(i, i + 3))[2])
	s[RB.POS + 2] = -deepest + 0.001
	var v_body := M.q_rotate(M.q_conj(RB._att(s)), PackedFloat64Array([0.0, 0.0, 20.0]))
	for k in 3:
		s[RB.VEL + k] = v_body[k]
		s[RB.RATE + k] = 0.0
	var before := s.duplicate()
	before[RB.POS + 2] -= 0.05
	session.sim.state = s
	session.sim.previous = before
	session.sim.set_paused(false)
	session._physics_process(session.sim.dt())
	director.update(session.sim.dt())
	var live: Dictionary = session.mass_properties()
	print("director_active=", director.active, " crash=", session.crash.get("why", ""))
	print("live_remaining_kg=", live.get("fuel_remaining_kg", -1), " authored_full_kg=", initial)
	print("report_fuel_kg=", director.report.get("fuel_kg", -1), " report_fuel_kind=", director.report.get("fuel_kind", ""))
	print("report_energy_sources=", director.report.get("energy_sources", {}), " director__fuel_kg=", director.get("_fuel_kg"))
	main.queue_free()
	await process_frame
	quit(0)
