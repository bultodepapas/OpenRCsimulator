extends SceneTree
const FlightSession := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Commands := preload("res://input/commands.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
func _initialize() -> void:
	for id in Catalog.ids():
		var session: Node = FlightSession.new()
		session.setup(Catalog.entry(id).data)
		root.add_child(session)
		session.commands = Commands.neutral_commands()
		session.reset()
		var s: PackedFloat64Array = session.sim.state
		var model: Dictionary = session.aircraft.model
		var d: Dictionary = session._deflections(session.sim.aux)
		var air: Dictionary = Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL)
		var r := [_m(func() -> void: Aero.loads(s, air, d, model, Air.RHO_SEA_LEVEL)),
			_m(func() -> void: Aero.local_flow_weight(s, air, d, model)),
			_m(func() -> void: Aero._global_loads(s, air, d, model, Air.RHO_SEA_LEVEL)),
			_m(func() -> void: Aero.coefficients(air, PackedFloat64Array([0.0, 0.0, 0.0]), d, model.aero, model.envelope)),
			_m(func() -> void: Air.compute(s, PackedFloat64Array([0.0, 0.0, 0.0]), Air.RHO_SEA_LEVEL))]
		print("%-28s trim aero %5.1f = flow_weight %5.1f + global %5.1f (coefficients %5.1f); air %4.1f; blend %.2f" % [id, r[0], r[1], r[2], r[3], r[4], Aero.local_flow_weight(s, air, d, model)])
		session.free()
	quit(0)
func _m(body: Callable) -> float:
	for i in 100:
		body.call()
	var v: Array[float] = []
	for k in 7:
		var t0 := Time.get_ticks_usec()
		for i in 1200:
			body.call()
		v.append(float(Time.get_ticks_usec() - t0) / 1200.0)
	v.sort()
	return v[3]
