# H15 scratch profiler: per-call cost of every piece of a load evaluation and of Simulation.step bookkeeping. Not a test.
extends SceneTree
const FlightSession := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Commands := preload("res://input/commands.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Slipstream := preload("res://physics/slipstream.gd")
const Ground := preload("res://physics/ground_contact.gd")
const RB := preload("res://physics/rigid_body.gd")
const RK := preload("res://physics/integrator.gd")
const M := preload("res://physics/math3d.gd")

func _initialize() -> void:
	for id in ["jensen-das-ugly-stik-60", "p51d-mustang-120"]:
		var session: Node = FlightSession.new()
		session.setup(Catalog.entry(id).data)
		root.add_child(session)
		session.commands = Commands.neutral_commands()
		session.reset()
		var s: PackedFloat64Array = session.start.state.duplicate()
		var speed := sqrt(s[RB.VEL] * s[RB.VEL] + s[RB.VEL + 2] * s[RB.VEL + 2])
		s[RB.VEL] = speed * M.cos_(deg_to_rad(15.0))
		s[RB.VEL + 2] = speed * M.sin_(deg_to_rad(15.0))
		s[RB.POS + 2] = -150.0
		session.sim.reset(s)
		var sim: Node = session.sim
		var model: Dictionary = session.aircraft.model
		var aux: PackedFloat64Array = sim.aux
		var d: Dictionary = session._deflections(aux)
		var rho := Air.RHO_SEA_LEVEL
		var zero := PackedFloat64Array([0.0, 0.0, 0.0])
		var air: Dictionary = Air.compute(s, zero, rho)
		var rpm: float = aux[0]
		var loads: PackedFloat64Array = session._loads(s, 0.0)
		var k := RB.derivative(s, model.mass_kg, model.inertia, RB.inertia_inverse(model.inertia), M.v3(loads[0], loads[1], loads[2]), M.v3(loads[3], loads[4], loads[5]), 9.80665, PackedFloat64Array([0.0, 0.0, 0.0]))
		var rows := {
			"session._loads": func() -> void: session._loads(s, 0.0),
			"Dynamics.loads": func() -> void: Dynamics.loads(s, model, d, rpm, rho, zero),
			"  Air.compute": func() -> void: Air.compute(s, zero, rho),
			"  Aero.loads": func() -> void: Aero.loads(s, air, d, model, rho),
			"  Propulsion.loads": func() -> void: Propulsion.loads(air.v_air, rpm, model.propulsion, rho),
			"    thrust_torque": func() -> void: Propulsion.thrust_torque(air.v_air, rpm, model.propulsion, rho),
			"  Ground.loads": func() -> void: Ground.loads(s, model.landing_gear, aux[3], session.ground_surfaces),
			"  session._deflections": func() -> void: session._deflections(aux),
			"RB.derivative": func() -> void: RB.derivative(s, model.mass_kg, model.inertia, sim._inertia_inv, M.v3(loads[0], loads[1], loads[2]), M.v3(loads[3], loads[4], loads[5]), 9.80665, zero),
			"RK.axpy": func() -> void: RK.axpy(s, 0.001, k),
			"RK._finish_step": func() -> void: RK._finish_step(s, 0.004, k, k, k, k),
			"state_is_valid": func() -> void: sim.state_is_valid(s),
			"_array_is_finite(13)": func() -> void: sim._array_is_finite(s, 13),
			"_configuration_is_valid": func() -> void: sim._configuration_is_valid(),
			"_refresh_inertia_inverse": func() -> void: sim._refresh_inertia_inverse(),
			"_remember_valid_state": func() -> void: sim._remember_valid_state(),
			"pre_step": func() -> void: sim.pre_step.call(aux, sim.inputs, sim.dt()),
			"stepped.emit": func() -> void: sim.stepped.emit(sim.tick, 0.0, s, loads, sim.inputs, aux),
			"empty lambda": func() -> void: pass,
		}
		if not model.propulsion.get("slipstream", {}).is_empty():
			rows["  Slipstream.loads"] = func() -> void: Slipstream.loads(s, air, d, model, rpm, rho)
		var has_wash: bool = not model.propulsion.get("slipstream", {}).is_empty()
		rows["sequence air+aero+prop(+slip)"] = func() -> void:
			var a2: Dictionary = Air.compute(s, zero, rho)
			Aero.loads(s, a2, d, model, rho)
			Propulsion.loads(a2.v_air, rpm, model.propulsion, rho)
			if has_wash:
				Slipstream.loads(s, a2, d, model, rpm, rho)
		rows["Dynamics._load_components"] = func() -> void: Dynamics._load_components(s, model, d, rpm, rho, zero)
		print("== ", id, " (stall fixture, initial state)")
		for name in rows:
			print("%-28s %7.2f us" % [name, _measure(rows[name])])
		session.free()
	quit(0)

func _measure(body: Callable) -> float:
	for i in 100:
		body.call()
	var samples: Array[float] = []
	for sample in 7:
		var t0 := Time.get_ticks_usec()
		for i in 1200:
			body.call()
		samples.append(float(Time.get_ticks_usec() - t0) / 1200.0)
	samples.sort()
	return samples[3]
