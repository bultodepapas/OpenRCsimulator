# Cross-axis flights, energy screening and timestep convergence through the real session.
extends SceneTree

const Session := preload("res://sim/flight_session.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Commands := preload("res://input/commands.gd")
const M := preload("res://physics/math3d.gd")
const Modes := preload("res://physics/flight_modes.gd")
const Maneuvers := preload("res://sim/maneuvers.gd")

func _flight(case: Dictionary) -> Dictionary:
	Engine.physics_ticks_per_second = case.get("hz", 240)
	var session := Session.new()
	session.setup()
	root.add_child(session)
	session.input_enabled = false
	if case.get("reduced_rudder", false):
		session.aircraft.model.aero.Cndr *= 0.3
	assert(session.trim_at(case.get("speed", 15.0), case.get("mode", "level")).ok)
	session.set_start_altitude(100.0)
	session.reset()
	var sim: Node = session.sim
	var out := {alpha_peak_deg = 0.0, beta_peak_deg = 0.0, p_peak_deg_s = 0.0, q_peak_deg_s = 0.0, r_peak_deg_s = 0.0, aero_power_peak_W = -1e30, negative_cd_ticks = 0, positive_aero_power_ticks = 0}
	var base_trim := session.trims.duplicate()
	for tick in 3 * Engine.physics_ticks_per_second:
		var t: float = sim.time()
		var c := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = session.start.throttle}
		if t >= 0.5 and t < 1.0:
			c[case.axis] = case.get("amplitude", 1.0)
		if case.get("coordinated", false):
			c.yaw = clampf(10.0 * Air.compute(sim.state, M.v3(0, 0, 0)).beta, -1.0, 1.0)
		session.commands = c
		sim.inputs = session._inputs()
		sim.step()
		var s: PackedFloat64Array = sim.state
		var air := Air.compute(s, M.v3(0, 0, 0))
		var d := Aero.deflections_from_surfaces(Commands.surface_deflections_deg(session.surfaces(), session.throws_deg()))
		var loads := Aero.loads(s, air, d, session.aircraft.model, Air.RHO_SEA_LEVEL)
		var coeff := Aero.coefficients(air, s.slice(10, 13), d, session.aircraft.model.aero, session.aircraft.model.envelope)
		var power := 0.0
		for k in 3:
			power += loads[k] * s[3+k] + loads[k+3] * s[10+k]
		out.aero_power_peak_W = maxf(out.aero_power_peak_W, power)
		out.negative_cd_ticks += int(coeff.CD < 0)
		out.positive_aero_power_ticks += int(power > 1e-6)
		out.alpha_peak_deg = maxf(out.alpha_peak_deg, absf(rad_to_deg(air.alpha)))
		out.beta_peak_deg = maxf(out.beta_peak_deg, absf(rad_to_deg(air.beta)))
		for entry in [["p_peak_deg_s", 10], ["q_peak_deg_s", 11], ["r_peak_deg_s", 12]]:
			out[entry[0]] = maxf(out[entry[0]], absf(rad_to_deg(s[entry[1]])))
	out.altitude_loss_m = 100.0 + sim.state[2]
	out.final_state = Array(sim.state)
	out.trim = base_trim
	out.final_rates_deg_s = [rad_to_deg(sim.state[10]), rad_to_deg(sim.state[11]), rad_to_deg(sim.state[12])]
	out.merge(case)
	session.free()
	return out

func _initialize() -> void:
	var cases := []
	for axis in ["roll", "pitch", "yaw"]:
		for amplitude in [-1.0, -0.25, 0.25, 1.0]:
			cases.append({name = "%s_%s_15" % [axis, amplitude], axis = axis, amplitude = amplitude})
		for speed in [12.0, 20.0]:
			cases.append({name = "%s_full_%s" % [axis, speed], axis = axis, speed = speed})
	for hz in [480, 960]:
		for axis in ["roll", "pitch", "yaw"]:
			cases.append({name = "%s_hz%s" % [axis, hz], axis = axis, hz = hz})
	for reduced in [false, true]:
		cases.append({name = "coordinated_reduced_%s" % reduced, axis = "roll", coordinated = true, reduced_rudder = reduced})
	var results := []
	for case in cases:
		var result := _flight(case)
		results.append(result)
		print("FLIGHT_CASE ", JSON.stringify(result))
	Engine.physics_ticks_per_second = 240
	var session := Session.new()
	session.setup()
	root.add_child(session)
	var modes := Modes.analyze(session.aircraft.model, 13.8)
	modes.erase("trim")
	var spin := []
	for reduced in [false, true]:
		session.aircraft.model.aero.Cndr = -0.1811 * (0.3 if reduced else 1.0)
		var trace: RefCounted = Maneuvers.fly(session, Maneuvers.all().spin_right)
		var peak := 0.0
		for row in range(6*240, trace.row_count()):
			peak = maxf(peak, maxf(absf(trace.value(row, "p_radps")), absf(trace.value(row, "r_radps"))))
		spin.append({reduced_rudder = reduced, recovery_peak_p_or_r_rad_s_after_6s = peak})
	var output := {flights = results, modes_at_13_8_mps = modes, spin = spin}
	print("AUDIT_MODES ", JSON.stringify(modes))
	print("AUDIT_SPIN ", JSON.stringify(spin))
	var out := OS.get_environment("FLIGHT_AUDIT_OUT")
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		var file := FileAccess.open(out.path_join("flights.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(output, "\t") + "\n")
	session.free()
	quit()
