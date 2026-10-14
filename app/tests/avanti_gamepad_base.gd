## AV-17-R2: deterministic pull/release through RcInput and the live FlightSession sampler.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Profile := preload("res://input/controller_profile.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const M := preload("res://physics/math3d.gd")
var hz := 240
var baseline := false
var physics_only := false
var full_rates := false

func run_case(speed: float, pitch: float, hold: float = 2.0) -> Dictionary:
	var flight := Flight.new()
	flight.rate_profile = "full" if full_rates else "normal"
	flight.setup("res://data/aircraft/sebart_avanti_s_a200.json", "sebart-avanti-s-a200-p100rx")
	root.add_child(flight)
	flight.set_physics_process(false)
	flight.sim.set_physics_process(false)
	# Counterfactual uses the same airframe and equations, with only the two R2 additions removed.
	if baseline: flight.aircraft.model.envelope.erase("wing_polar")
	if baseline or physics_only: flight.aircraft.model.controls.erase("gamepad")
	assert(flight.trim_at(speed).ok)
	flight.set_start_altitude(500.0)
	flight.reset()
	flight.crash_auto_restart = false
	flight.radio.connect_device(15, {known = true, name = "Synthetic Xbox"}, Profile.defaults())
	flight.radio.confirmed_gamepad_connection = func(id: int) -> bool: return id == 15
	flight.read_axis = func(_id: int, axis: int) -> float:
		return pitch if axis == 3 and flight.sim.time() >= 0.5 and flight.sim.time() < 0.5 + hold else 0.0
	flight.read_button = func(_id: int, _button: int) -> bool: return false
	for i in 50: flight.radio.poll(flight.read_axis, flight.sim.dt(), flight.read_button, false)
	assert(flight.radio.armed)
	assert(flight.radio.set_rate_throttle_for_start(flight.start.throttle))
	var item := {speed = speed, pitch = pitch, hold_s = hold, alpha_max = 0.0, roll_rate_max = 0.0,
		pull_roll_rate_max = 0.0, beta_max = 0.0, normal_g_max = 0.0, speed_min = speed,
		stall_first = -1.0, stall_max = 0.0, unwanted_command_max = 0.0, finite = true, samples = []}
	for i in 6 * hz:
		flight._physics_process(flight.sim.dt())
		flight.sim.step()
		var state: PackedFloat64Array = flight.sim.state
		var air := Air.compute(state, M.v3(0,0,0), flight.air_density())
		var separation := 0.0
		for strip in Aero.wing_strip_loads(state, air, Aero.deflections_from_surfaces(flight.surface_angles_deg()), flight.aircraft.model, flight.air_density()):
			separation = maxf(separation, strip.stall_weight)
		var g: float = -flight.sim.last_loads[2] / (flight.aircraft.model.mass_kg * flight.sim.gravity)
		var p := rad_to_deg(state[10])
		item.alpha_max = maxf(item.alpha_max, absf(rad_to_deg(air.alpha)))
		item.roll_rate_max = maxf(item.roll_rate_max, absf(p))
		if flight.sim.time() <= 0.5 + hold: item.pull_roll_rate_max = maxf(item.pull_roll_rate_max, absf(p))
		item.beta_max = maxf(item.beta_max, absf(rad_to_deg(air.beta)))
		item.normal_g_max = maxf(item.normal_g_max, absf(g))
		item.speed_min = minf(item.speed_min, air.V)
		item.stall_max = maxf(item.stall_max, separation)
		item.unwanted_command_max = maxf(item.unwanted_command_max, maxf(absf(flight.commands.roll), absf(flight.commands.yaw)))
		if item.stall_first < 0.0 and separation >= 0.5: item.stall_first = flight.sim.time()
		for value in state: item.finite = item.finite and is_finite(value)
		for value in flight.sim.aux: item.finite = item.finite and is_finite(value)
		if i % (hz / 20) == 0:
			item.samples.append([flight.sim.time(), air.V, rad_to_deg(air.alpha), rad_to_deg(air.beta), p,
				rad_to_deg(state[11]), rad_to_deg(state[12]), separation, flight.commands.roll, flight.commands.pitch,
				flight.commands.yaw, flight.surface_angles_deg().elevator, flight.commands.throttle, g, -state[2]])
		if flight.sim.paused or not flight.sim.fault_reason.is_empty() or not flight.crash.is_empty() or not item.finite: break
	item.completed = flight.sim.tick == 6 * hz and flight.sim.fault_reason.is_empty() and flight.crash.is_empty() and item.finite
	var brief := item.duplicate()
	brief.erase("samples")
	print(JSON.stringify(brief))
	flight.free()
	return item
