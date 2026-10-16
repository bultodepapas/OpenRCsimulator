extends SceneTree

const Flight = preload("res://sim/flight_session.gd")
const Maneuvers = preload("res://sim/maneuvers.gd")
const Aero = preload("res://physics/aero.gd")
const GE = preload("res://physics/ground_effect.gd")

func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	var flight := Flight.new()
	flight.input_enabled = false
	flight.setup()
	flight.reset()
	root.add_child(flight)
	flight.set_physics_process(false)
	var maneuver: Dictionary = Maneuvers.all().rudder_doublet
	var trim: Dictionary = flight.trim_at(maneuver.speed, maneuver.mode)
	if not trim.ok:
		quit(1)
		return
	flight.reset()
	print("tick,time,blend,global_Mz,local_Mz,blended_Mz,r_deg_s")
	for tick in 721:
		var state: PackedFloat64Array = flight.sim.state
		var air: Dictionary = flight.air_data(state, flight.sim.time())
		var d: Dictionary = flight._deflections(flight.sim.aux)
		var model: Dictionary = flight.aircraft.model
		var density: float = flight.air_density(state)
		var wake: float = flight.sim.aux[flight.downwash_index()]
		var ge: PackedFloat64Array = GE.factors(state, model, flight._ground_up(state))
		var blend: float = Aero.local_flow_weight(state, air, d, model, wake, ge)
		var global: PackedFloat64Array = Aero._global_loads(state, air, d, model, density, wake, ge)
		var local: PackedFloat64Array = Aero._local_loads(state, air, d, model, density, wake, null, ge)
		var actual: PackedFloat64Array = Aero.loads(state, air, d, model, density, wake, flight._ground_up(state))
		assert(absf(actual[5] - lerpf(global[5], local[5], blend)) < 1e-12)
		print("%d,%.12f,%.12f,%.12f,%.12f,%.12f,%.12f" % [tick, flight.sim.time(), blend, global[5], local[5], actual[5], rad_to_deg(state[12])])
		if tick == 720: break
		var sticks: Dictionary = maneuver.sticks.call(flight.sim.time(), state)
		flight.commands = {roll = sticks.roll, pitch = sticks.pitch, yaw = sticks.yaw,
			throttle = clampf(flight.start.throttle + sticks.throttle_delta, 0.0, 1.0)}
		flight.sim.inputs = flight._inputs()
		flight.sim.step()
	flight.free()
	quit(0)
