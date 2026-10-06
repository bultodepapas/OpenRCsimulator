extends SceneTree

const FlightSession := preload("res://sim/flight_session.gd")
const RB := preload("res://physics/rigid_body.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const DATA := "res://data/aircraft/p51d_mustang_120.json"
const RATES := [240, 480, 960, 1920, 3840]
const DURATION := 0.5


func _initialize() -> void:
	var end_states := {}
	for hz in RATES:
		Engine.physics_ticks_per_second = hz
		var session := FlightSession.new()
		session.setup(DATA)
		root.add_child(session)
		session.input_enabled = false
		var trim: Dictionary = session.trim_at(35.0, "level")
		if not trim.get("ok", false):
			printerr("trim failed at %d Hz: %s" % [hz, trim.get("message", "unknown")])
			quit(1)
			return
		session.set_start_altitude(500.0)
		session.reset()
		session.sim.aux[0] = Propulsion.steady_rpm(0.2, 35.0, session.aircraft.model.propulsion, 1.225)
		session.commands.throttle = 1.0
		session.sim.inputs = session._inputs()
		for _i in roundi(DURATION * hz):
			session.sim.step()
		end_states[hz] = { state = session.sim.state.duplicate(), aux = session.sim.aux.duplicate() }
		print("rate=%d rpm=%.6f V=%.9f alpha=%.9f" % [hz, session.sim.aux[0],
			sqrt(session.sim.state[RB.VEL] ** 2 + session.sim.state[RB.VEL + 1] ** 2 + session.sim.state[RB.VEL + 2] ** 2),
			atan2(session.sim.state[RB.VEL + 2], session.sim.state[RB.VEL])])

	var reference: Dictionary = end_states[RATES[-1]]
	var errors := {}
	for hz in RATES.slice(0, RATES.size() - 1):
		errors[hz] = _distance(end_states[hz].state, end_states[hz].aux, reference.state, reference.aux)
		print("error_to_%dHz[%dHz]=%s" % [RATES[-1], hz, str(errors[hz])])
	for i in range(errors.size() - 1):
		var coarse: int = RATES[i]
		var fine: int = RATES[i + 1]
		print("halving_ratio_%d_to_%d=%s" % [coarse, fine, str(errors[coarse] / errors[fine])])
	for i in range(RATES.size() - 1):
		var coarse: int = RATES[i]
		var fine: int = RATES[i + 1]
		var diff := _distance(end_states[coarse].state, end_states[coarse].aux,
			end_states[fine].state, end_states[fine].aux)
		print("adjacent_state_error_%d_to_%d=%s" % [coarse, fine, str(diff)])
	quit(0)


func _distance(a: PackedFloat64Array, aa: PackedFloat64Array,
		b: PackedFloat64Array, ba: PackedFloat64Array) -> float:
	var sum := 0.0
	for i in a.size():
		sum += (a[i] - b[i]) ** 2
	for i in aa.size():
		sum += (aa[i] - ba[i]) ** 2
	return sqrt(sum)
