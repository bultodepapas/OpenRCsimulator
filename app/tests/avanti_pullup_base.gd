## AV-17-R1: keyboard dive recovery, through the real per-tick flight sampler.
extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const M := preload("res://physics/math3d.gd")
const Trim := preload("res://physics/trim.gd")
const Commands := preload("res://input/commands.gd")
const RB := preload("res://physics/rigid_body.gd")
var hz := 240
var output := ""
var candidate_rate := 0.0
var legacy_keyboard := false

func run_case(speed: float, hold: float) -> Dictionary:
	var flight := Flight.new()
	flight.rate_profile = "normal"
	flight.setup("res://data/aircraft/sebart_avanti_s_a200.json", "sebart-avanti-s-a200-p100rx")
	root.add_child(flight)
	flight.set_physics_process(false)
	flight.sim.set_physics_process(false)
	flight.crash_auto_restart = false
	var trimmed: Dictionary = flight.trim_at(speed)
	assert(trimmed.ok)
	flight.set_start_altitude(500.0)
	flight.reset()
	var initial: PackedFloat64Array = Trim.state_for(speed, float(trimmed.alpha), deg_to_rad(-45.0), 0.0, M.v3(0,0,-500))
	assert(flight.sim.reset(initial))
	var record := {speed_mps = speed, hold_s = hold, peak_alpha_deg = 0.0, peak_g = 0.0, peak_stall_weight = 0.0,
		first_stall_s = -1.0, first_deep_separation_s = -1.0, recovered_s = -1.0, samples = [], completed = false}
	flight.read_raw = func() -> Dictionary:
		# Repeated key taps are a scripted pilot, not a runtime flight assist. Release after reaching level path.
		var press: bool = flight.sim.time() < hold if hold >= 0 else fmod(flight.sim.time(), 0.6) < 0.45 and record.recovered_s < 0
		return {roll = 0.0, pitch = 1.0 if press else 0.0, yaw = 0.0, throttle = 0.0}
	for tick in 4 * hz:
		# Candidate experiment changes only keyboard slew; accepted runtime is untouched.
		var old_pitch: float = flight.commands.pitch
		flight._physics_process(flight.sim.dt())
		if candidate_rate > 0.0 or legacy_keyboard:
			flight.commands.pitch = Commands.rate_limit(old_pitch, flight.raw.pitch,
				candidate_rate if candidate_rate > 0.0 and flight.raw.pitch != 0.0 else 4.0, flight.sim.dt())
			flight.sim.inputs = flight._inputs()
		flight.sim.step()
		var state: PackedFloat64Array = flight.sim.state
		var air: Dictionary = Air.compute(state, M.v3(0,0,0), flight.air_density())
		var attitude := M.quat(state[6],state[7],state[8],state[9])
		var velocity := M.q_rotate(attitude, M.v3(state[3], state[4], state[5]))
		var gamma := rad_to_deg(atan2(-velocity[2], sqrt(velocity[0]*velocity[0]+velocity[1]*velocity[1])))
		var d := Aero.deflections_from_surfaces(flight.surface_angles_deg())
		var weight := 0.0
		for strip in Aero.wing_strip_loads(state, air, d, flight.aircraft.model, flight.air_density()):
			weight = maxf(weight, strip.stall_weight)
		var g: float = -flight.sim.last_loads[2] / (flight.aircraft.model.mass_kg * flight.sim.gravity)
		record.peak_alpha_deg = maxf(record.peak_alpha_deg, rad_to_deg(air.alpha))
		record.peak_g = maxf(record.peak_g, g)
		record.peak_stall_weight = maxf(record.peak_stall_weight, weight)
		if record.first_stall_s < 0.0 and weight >= 0.5: record.first_stall_s = flight.sim.time()
		if record.first_deep_separation_s < 0.0 and weight > 0.9: record.first_deep_separation_s = flight.sim.time()
		if record.recovered_s < 0.0 and gamma >= 0.0: record.recovered_s = flight.sim.time()
		if tick % (hz / 20) == 0:
			record.samples.append([flight.sim.time(), air.V, rad_to_deg(air.alpha), gamma, g,
				flight.commands.pitch, flight.surface_angles_deg().elevator, weight, -state[2]])
		if not flight.sim.fault_reason.is_empty() or not flight.crash.is_empty() or flight.sim.paused: break
	record.completed = flight.sim.tick == 4 * hz and flight.sim.fault_reason.is_empty() and flight.crash.is_empty()
	record.fault = flight.sim.fault_reason
	print("V %.0f hold %.2f alpha %.2f g %.2f stall %.2f recovered %.3f complete %s" %
		[speed, hold, record.peak_alpha_deg, record.peak_g, record.peak_stall_weight, record.recovered_s, record.completed])
	flight.free()
	return record
