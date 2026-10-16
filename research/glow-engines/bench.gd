extends SceneTree

const TwoStroke := preload("res://physics/glow/two_stroke.gd")
const FourStroke := preload("res://physics/glow/four_stroke.gd")
const Profile := preload("res://physics/glow/profile.gd")
const GlowSource := preload("res://physics/glow/source.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Rotor := preload("res://physics/rotor_coupling.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Sim := preload("res://sim/simulation.gd")

const ROTOR_INERTIA_KG_M2 := 8.0e-5
const AIR_DENSITY_KG_M3 := 1.18
const DEFAULT_HZ := 240
const DEFAULT_TICKS := 600
const DEFAULT_SAMPLE_EVERY := 24
const DEFAULT_RPM := 5000.0
const DEFAULT_PROP_DIAMETER_M := 0.30
const DEFAULT_CARRIER_MASS_KG := 0.25

var _engine := "4t"
var _parameters: Dictionary = {}
var _profile_model: Dictionary = {}
var _input_identity: Dictionary = {"kind": "synthetic_test_fixture"}
var _propeller: Dictionary = {}
var _dry_density_kg_m3 := AIR_DENSITY_KG_M3
var _mixture := 1.0
var _max_rpm := 16000.0
var _sample_every := DEFAULT_SAMPLE_EVERY
var _prop_diameter_m := DEFAULT_PROP_DIAMETER_M
var _carrier_mass_kg := DEFAULT_CARRIER_MASS_KG
var _low_admission := 0.3
var _last_stage_failure := ""


func _initialize() -> void:
	var options: Dictionary = _parse_options(OS.get_cmdline_user_args())
	if not options.get("ok", false):
		_fail(str(options.get("message", "invalid command line")))
		return
	var configured: Dictionary = _configure(options)
	if not configured.get("ok", false):
		_fail(str(configured.get("message", "configuration failed")))
		return
	var report: Dictionary = _run(int(options["hz"]), int(options["ticks"]))
	var encoded: String = JSON.stringify(report, "\t", true, true)
	print(encoded)
	var out_path: String = str(options.get("out", ""))
	if not out_path.is_empty():
		var file := FileAccess.open(out_path, FileAccess.WRITE)
		if file == null:
			_fail("cannot write benchmark JSON: " + out_path)
			return
		file.store_string(encoded + "\n")
		file.close()
	quit(0 if report.get("ok", false) else 2)


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var options := {
		"engine": "",
		"profile": "",
		"out": "",
		"ticks": DEFAULT_TICKS,
		"hz": DEFAULT_HZ,
		"sample_every": DEFAULT_SAMPLE_EVERY,
		"prop-diameter-m": DEFAULT_PROP_DIAMETER_M,
		"carrier-mass-kg": DEFAULT_CARRIER_MASS_KG,
		"low-admission": 0.3,
	}
	for argument: String in arguments:
		if not argument.begins_with("--") or not argument.contains("="):
			return {"ok": false, "message": "expected --name=value, got " + argument}
		var separator: int = argument.find("=")
		var name: String = argument.substr(2, separator - 2)
		var value: String = argument.substr(separator + 1)
		if not options.has(name):
			return {"ok": false, "message": "unknown option --" + name}
		options[name] = value
	for key: String in ["ticks", "hz", "sample_every"]:
		if typeof(options[key]) == TYPE_STRING:
			var parsed: int = String(options[key]).to_int()
			if parsed <= 0 or str(parsed) != String(options[key]):
				return {"ok": false, "message": "--%s must be a positive integer" % key}
			options[key] = parsed
	if int(options["ticks"]) > 10000000 or int(options["hz"]) > 10000:
		return {"ok": false, "message": "requested run exceeds the supported CLI limits"}
	var raw_diameter: Variant = options["prop-diameter-m"]
	var prop_diameter_m: float
	if typeof(raw_diameter) == TYPE_STRING:
		var diameter_text: String = str(raw_diameter)
		if not diameter_text.is_valid_float():
			return {"ok": false, "message": "--prop-diameter-m must be a finite positive number"}
		prop_diameter_m = diameter_text.to_float()
	else:
		prop_diameter_m = float(raw_diameter)
	if not is_finite(prop_diameter_m) or prop_diameter_m <= 0.0:
		return {"ok": false, "message": "--prop-diameter-m must be a finite positive number"}
	options["prop-diameter-m"] = prop_diameter_m
	var raw_carrier_mass: Variant = options["carrier-mass-kg"]
	var carrier_mass_kg: float
	if typeof(raw_carrier_mass) == TYPE_STRING:
		var carrier_mass_text: String = str(raw_carrier_mass)
		if not carrier_mass_text.is_valid_float():
			return {"ok": false, "message": "--carrier-mass-kg must be a finite positive number"}
		carrier_mass_kg = carrier_mass_text.to_float()
	else:
		carrier_mass_kg = float(raw_carrier_mass)
	if not is_finite(carrier_mass_kg) or carrier_mass_kg <= 0.0:
		return {"ok": false, "message": "--carrier-mass-kg must be a finite positive number"}
	options["carrier-mass-kg"] = carrier_mass_kg
	var raw_low_admission: Variant = options["low-admission"]
	var low_admission: float
	if typeof(raw_low_admission) == TYPE_STRING:
		var low_admission_text: String = str(raw_low_admission)
		if not low_admission_text.is_valid_float():
			return {"ok": false, "message": "--low-admission must be finite and between zero and one"}
		low_admission = low_admission_text.to_float()
	else:
		low_admission = float(raw_low_admission)
	if not is_finite(low_admission) or low_admission < 0.0 or low_admission > 1.0:
		return {"ok": false, "message": "--low-admission must be finite and between zero and one"}
	options["low-admission"] = low_admission
	if not str(options["engine"]).is_empty() and str(options["engine"]) not in ["2t", "4t"]:
		return {"ok": false, "message": "--engine must be 2t or 4t"}
	options["ok"] = true
	return options


func _configure(options: Dictionary) -> Dictionary:
	_profile_model.clear()
	_parameters.clear()
	_input_identity = {"kind": "synthetic_test_fixture", "description": "Independent benchmark-only kernel fixture"}
	_dry_density_kg_m3 = AIR_DENSITY_KG_M3
	_mixture = 1.0
	_max_rpm = 16000.0
	var requested_engine: String = str(options["engine"])
	var profile_path: String = str(options["profile"])
	if not profile_path.is_empty():
		var loaded: Dictionary = Profile.load_file(profile_path)
		if not loaded.get("ok", false):
			return {"ok": false, "message": "profile load failed: " + str(loaded.get("errors", loaded.get("message", "unknown error")))}
		_profile_model = loaded["model"]
		var family: String = str(_profile_model.get("family", ""))
		var profile_engine: String = "2t" if family == "glow_2t" else "4t" if family == "glow_4t" else ""
		if profile_engine.is_empty():
			return {"ok": false, "message": "profile has unsupported glow family"}
		if not requested_engine.is_empty() and requested_engine != profile_engine:
			return {"ok": false, "message": "--engine does not match the selected profile family"}
		_engine = profile_engine
		_parameters = _profile_model["parameters"]
		_input_identity = loaded.get("input_identity", {}).duplicate(true)
		_input_identity.merge(_profile_model.get("identity", {}), true)
		var operation: Dictionary = _profile_model["operation"]
		_dry_density_kg_m3 = float(operation["reference_dry_density_kg_m3"])
		_mixture = float(operation["nominal_mixture"])
		_max_rpm = float(operation["max_rpm"])
	else:
		_engine = "4t" if requested_engine.is_empty() else requested_engine
		_parameters = _fixture_parameters(_engine)
	if not _parameters.has("displacement_m3"):
		return {"ok": false, "message": "selected model has no displacement"}
	_prop_diameter_m = float(options["prop-diameter-m"])
	_carrier_mass_kg = float(options["carrier-mass-kg"])
	_low_admission = float(options["low-admission"])
	_propeller = _estimated_propeller(_prop_diameter_m)
	_sample_every = int(options["sample_every"])
	return {"ok": true}


func _run(hz: int, ticks: int) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var sim: Node = _new_sim()
	if not sim.fault_reason.is_empty():
		var reset_error: String = sim.fault_reason
		sim.free()
		return {"ok": false, "error": "simulation reset failed: " + reset_error}
	var initial_body: PackedFloat64Array = sim.state.duplicate()
	var initial_continuous: PackedFloat64Array = sim.continuous.duplicate()
	var initial_energy: float = _total_energy(sim, initial_body, initial_continuous)
	var initial_momentum: float = _axial_momentum(initial_body, initial_continuous)
	var samples: Array[Dictionary] = []
	var max_rpm_seen: float = DEFAULT_RPM
	var min_rpm_seen: float = DEFAULT_RPM
	var max_thrust_n := 0.0
	var max_prop_torque_nm := 0.0
	var max_inflow_mps := 0.0
	var fault := ""
	var first_sample: Dictionary = _sample_point(sim, sim.time())
	if not first_sample.get("ok", false):
		fault = str(first_sample.get("error", "initial sample failed"))
	else:
		samples.append(_sample_record(sim, first_sample))
	var started_usec: int = Time.get_ticks_usec()
	for _index: int in ticks:
		sim.step()
		if not sim.fault_reason.is_empty():
			fault = sim.fault_reason
			if not _last_stage_failure.is_empty():
				fault += ": " + _last_stage_failure
			break
		var rpm: float = float(sim.continuous[0])
		max_rpm_seen = maxf(max_rpm_seen, rpm)
		min_rpm_seen = minf(min_rpm_seen, rpm)
		var point: Dictionary = _sample_point(sim, sim.time())
		if not point.get("ok", false):
			fault = str(point.get("error", "sample evaluation failed"))
			break
		max_thrust_n = maxf(max_thrust_n, float(point["thrust_n"]))
		max_prop_torque_nm = maxf(max_prop_torque_nm, float(point["prop_torque_nm"]))
		max_inflow_mps = maxf(max_inflow_mps, float(point["inflow_mps"]))
		if sim.tick % _sample_every == 0 or sim.tick == ticks:
			samples.append(_sample_record(sim, point))
	var elapsed_usec: int = maxi(1, Time.get_ticks_usec() - started_usec)
	var final_body: PackedFloat64Array = sim.state.duplicate()
	var final_continuous: PackedFloat64Array = sim.continuous.duplicate()
	var final_energy: float = _total_energy(sim, final_body, final_continuous)
	var final_momentum: float = _axial_momentum(final_body, final_continuous)
	var expected_work: float = final_continuous[1] - final_continuous[2] + final_continuous[3]
	var expected_angular_impulse: float = final_continuous[4]
	var result := {
		"ok": fault.is_empty(),
		"error": fault,
		"format": "openrc-glow-coupling-bench v1",
		"engine": _engine,
		"family": "glow_2t" if _engine == "2t" else "glow_4t",
		"profile_identity": _input_identity,
		"profile_operation": _profile_model.get("operation", {}),
		"max_supported_rpm": _max_rpm,
		"simulation": {
			"ticks_requested": ticks,
			"ticks_completed": sim.tick,
			"hz": hz,
			"duration_s": float(sim.tick) / float(hz),
			"wall_time_s": float(elapsed_usec) / 1000000.0,
			"wall_usec_per_completed_tick": float(elapsed_usec) / float(maxi(1, sim.tick)),
			"stage_rpm_is_coupled": true,
			"integrator": "Simulation.continuous_evaluate with coupled RK4 stages",
		},
		"inputs": {
			"initial_rpm": initial_continuous[0],
			"dry_air_density_kg_m3": _dry_density_kg_m3,
			"mixture": _mixture,
			"low_admission_after_1_4_s": _low_admission,
			"admission_schedule": [
				{"from_s": 0.0, "to_s": 0.4, "admission": 0.6},
				{"from_s": 0.4, "to_s": 1.4, "admission": 1.0},
				{"from_s": 1.4, "admission": _low_admission},
			],
			"propeller": {
				"diameter_m": _propeller.diameter,
				"thrust_coefficient_ct": _propeller.ct,
				"power_coefficient_cp": _propeller.cp,
				"evidence": "explicit benchmark diameter with estimated coefficients; not a measured propeller or manufacturer calibration",
				"coverage": "energy-admissible through J=1.2; beyond coverage, negative-Ct drag and zero-Cp floor are unqualified",
			},
			"rotor_inertia_kg_m2": ROTOR_INERTIA_KG_M2,
			"locked_body_inertia_kg_m2": _locked_body_inertia(),
			"carrier_mass_kg": _carrier_mass_kg,
			"carrier_inertia_scope": "explicit locked-carrier test tensor; not an inferred or physical airframe inertia",
			"carrier_mass_scope": "isolated bench carrier; not a physical airframe estimate",
			"body_gravity_m_s2": 0.0,
			"fuel_location": "offboard model; no onboard fuel mass or variable-mass claim",
		},
		"metrics": {
			"initial_rpm": initial_continuous[0],
			"final_rpm": final_continuous[0],
			"minimum_rpm": min_rpm_seen,
			"maximum_rpm": max_rpm_seen,
			"maximum_thrust_n": max_thrust_n,
			"maximum_prop_torque_nm": max_prop_torque_nm,
			"maximum_forward_inflow_mps": max_inflow_mps,
			"delivered_fuel_kg": final_continuous[5],
			"burned_fuel_kg": final_continuous[6],
			"unburned_delivered_fuel_kg": final_continuous[5] - final_continuous[6],
			"engine_work_j": final_continuous[1],
			"propeller_absorbed_work_j": final_continuous[2],
			"thrust_work_j": final_continuous[3],
			"energy_change_j": final_energy - initial_energy,
			"work_closure_error_j": absf(final_energy - initial_energy - expected_work),
			"axial_angular_momentum_change_nms": final_momentum - initial_momentum,
			"external_angular_impulse_nms": expected_angular_impulse,
			"axial_angular_momentum_closure_error_nms": absf(final_momentum - initial_momentum - expected_angular_impulse),
		},
		"samples": samples,
	}
	sim.free()
	return result


func _new_sim() -> Node:
	var sim: Node = Sim.new()
	sim.mass = _carrier_mass_kg
	sim.gravity = 0.0
	sim.inertia = _locked_body_inertia()
	sim.continuous = PackedFloat64Array([DEFAULT_RPM, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	sim.aux = PackedFloat64Array([DEFAULT_RPM])
	sim.modes = PackedInt64Array([1])
	sim.model.block_aux = func(values: PackedFloat64Array, _sampled_aux: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array([values[0]])
	_last_stage_failure = ""
	sim.model.stage = func(body: PackedFloat64Array, values: PackedFloat64Array, time_s: float) -> Dictionary:
		var point: Dictionary = _evaluate_point(body, values, time_s)
		if not point.get("ok", false):
			_last_stage_failure = str(point.get("error", "coupled engine stage was rejected"))
			return {}
		return {"loads": point["loads"], "derivative": point["derivative"], "rotor_momentum": point["rotor_momentum"]}
	sim.reset(_initial_state())
	return sim


func _evaluate_point(body: PackedFloat64Array, values: PackedFloat64Array, time_s: float) -> Dictionary:
	if body.size() != RB.SIZE or values.size() != 7:
		return {"ok": false, "error": "malformed rigid-body or continuous state"}
	if values[0] < 0.0:
		return {"ok": false, "error": "negative trial RPM requires a future starter/stall event model"}
	var rpm: float = values[0]
	var admission: float = _admission(time_s)
	var engine_result: Dictionary
	if not _profile_model.is_empty():
		engine_result = GlowSource.evaluate(
			_profile_model, rpm, admission, _mixture, _dry_density_kg_m3, true, 1.0
		)
	elif _engine == "2t":
		engine_result = TwoStroke.evaluate(
			rpm, admission, _mixture, _dry_density_kg_m3, _parameters, true, 1.0
		)
	else:
		engine_result = FourStroke.evaluate(rpm, admission, _mixture, _dry_density_kg_m3, _parameters, true, 1.0)
	if not engine_result.get("ok", false):
		return {"ok": false, "error": str(engine_result.get("message", "engine kernel rejected stage"))}
	var velocity: PackedFloat64Array = body.slice(RB.VEL, RB.VEL + 3)
	var prop_output: PackedFloat64Array = Propulsion.thrust_torque(
		velocity, rpm, _propeller, _dry_density_kg_m3
	)
	var prop_torque_nm: float = Propulsion.prop_torque(
		rpm, velocity[0], _propeller, _dry_density_kg_m3
	)
	var body_loads: PackedFloat64Array = Propulsion.loads(
		velocity, rpm, _propeller, _dry_density_kg_m3
	)
	var external_prop_moment_x: float = body_loads[3]
	var relative_speed_rad_s: float = rpm * TAU / 60.0
	var body_rate: PackedFloat64Array = body.slice(RB.RATE, RB.RATE + 3)
	var body_inertia: PackedFloat64Array = _locked_body_inertia()
	var net_shaft_torque_nm: float = float(engine_result["shaft_torque_nm"]) - prop_torque_nm
	var response: Dictionary = Rotor.response(
		body_rate,
		body_loads.slice(3, 6),
		body_inertia,
		RB.inertia_inverse(body_inertia),
		_axis(),
		ROTOR_INERTIA_KG_M2,
		relative_speed_rad_s,
		net_shaft_torque_nm
	)
	if not response.get("ok", false):
		return {"ok": false, "error": "RotorCoupling.response rejected the RK stage"}
	for axis_index: int in 3:
		body_loads[3 + axis_index] += response.reaction[axis_index]
	var absolute_speed_rad_s: float = relative_speed_rad_s + M.dot(body_rate, _axis())
	var derivative := PackedFloat64Array([
		float(response["spin_acceleration"]) * 60.0 / TAU,
		float(engine_result["shaft_torque_nm"]) * relative_speed_rad_s,
		prop_torque_nm * absolute_speed_rad_s,
		prop_output[0] * M.dot(velocity, _axis()),
		external_prop_moment_x,
		float(engine_result["delivered_fuel_kg_s"]),
		float(engine_result["burned_fuel_kg_s"]),
	])
	for lane: float in derivative:
		if not is_finite(lane):
			return {"ok": false, "error": "nonfinite coupled RK-stage derivative"}
	return {
		"ok": true,
		"loads": body_loads,
		"derivative": derivative,
		"rotor_momentum": response["momentum"],
		"engine_torque_nm": float(engine_result["shaft_torque_nm"]),
		"prop_torque_nm": prop_torque_nm,
		"thrust_n": prop_output[0],
		"advance_ratio": prop_output[2],
		"inflow_mps": velocity[0],
		"rpm_rate": float(response["spin_acceleration"]) * 60.0 / TAU,
		"reaction_x_nm": response["reaction"][0],
		"admission": admission,
		"cycle_frequency_hz": float(engine_result["cycle_frequency_hz"]),
		"opportunity_frequency_hz": float(engine_result["opportunity_frequency_hz"]),
		"firing_frequency_hz": float(engine_result["firing_frequency_hz"]),
	}


func _sample_point(sim: Node, time_s: float) -> Dictionary:
	return _evaluate_point(sim.state, sim.continuous, time_s)


func _sample_record(sim: Node, point: Dictionary) -> Dictionary:
	return {
		"tick": sim.tick,
		"time_s": sim.time(),
		"rpm": sim.continuous[0],
		"admission": point["admission"],
		"shaft_torque_nm": point["engine_torque_nm"],
		"prop_torque_nm": point["prop_torque_nm"],
		"thrust_n": point["thrust_n"],
		"advance_ratio": point["advance_ratio"],
		"forward_inflow_mps": point["inflow_mps"],
		"rpm_rate": point["rpm_rate"],
		"rotor_reaction_x_nm": point["reaction_x_nm"],
		"cycle_frequency_hz": point["cycle_frequency_hz"],
		"opportunity_frequency_hz": point["opportunity_frequency_hz"],
		"firing_frequency_hz": point["firing_frequency_hz"],
	}


func _fixture_parameters(engine: String) -> Dictionary:
	if engine == "2t":
		return {
			"displacement_m3": 1.1e-5,
			"oil_fraction": 0.18,
			"stoich_air_fuel_ratio": 6.5,
			"fuel_lhv_j_kg": 42.0e6,
			"delivery_ratio": _flat_curve(0.85),
			"trapping_efficiency": _flat_curve(0.85),
			"scavenge_pressure_pa": _flat_curve(600.0),
			"mechanical_torque_nm": _flat_curve(0.035),
			"combustion_efficiency": _flat_curve(0.8, 2.0),
			"indicated_efficiency": _flat_curve(0.08),
		}
	return {
		"displacement_m3": 1.1e-5,
		"oil_fraction": 0.18,
		"stoich_air_fuel_ratio": 6.5,
		"fuel_lhv_j_kg": 42.0e6,
		"mechanical_torque_nm": _flat_curve(0.025),
		"combustion_efficiency": _flat_curve(0.8, 2.0),
		"indicated_efficiency": _flat_curve(0.14),
		"volumetric_efficiency": _flat_curve(0.85),
		"pumping_pressure_pa": _flat_curve(600.0),
		"intake_pressure_drop_pa": 250.0,
		"valve_torque_nm": _flat_curve(0.006),
	}


func _flat_curve(value: float, x_end: float = 16000.0) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, value, x_end, value])


func _estimated_propeller(diameter_m: float) -> Dictionary:
	return {
		"diameter": diameter_m,
		"ct": PackedFloat64Array([0.0, 0.10, 0.2, 0.075, 0.5, 0.04, 1.0, 0.01, 1.2, 0.0]),
		"cp": PackedFloat64Array([0.0, 0.045, 0.2, 0.043, 0.5, 0.03, 1.0, 0.02, 1.2, 0.0]),
		"cp_min": 0.0,
		"offset": PackedFloat64Array([0.0, 0.0, 0.0]),
	}


func _locked_body_inertia() -> PackedFloat64Array:
	return PackedFloat64Array([0.02, 0.03, 0.03, 0.0, 0.0, 0.0])


func _axis() -> PackedFloat64Array:
	return PackedFloat64Array([1.0, 0.0, 0.0])


func _initial_state() -> PackedFloat64Array:
	return RB.make_state(
		PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0]),
		PackedFloat64Array([1.0, 0.0, 0.0, 0.0]),
		PackedFloat64Array([0.0, 0.0, 0.0])
	)


func _admission(time_s: float) -> float:
	if time_s < 0.4:
		return 0.6
	if time_s < 1.4:
		return 1.0
	return _low_admission


func _total_energy(sim: Node, body: PackedFloat64Array, values: PackedFloat64Array) -> float:
	var rate: PackedFloat64Array = body.slice(RB.RATE, RB.RATE + 3)
	var locked_angular_momentum: PackedFloat64Array = RB.inertia_mul(sim.inertia, rate)
	var omega: float = values[0] * TAU / 60.0
	var rotational: float = (
		0.5 * M.dot(rate, locked_angular_momentum)
		+ ROTOR_INERTIA_KG_M2 * omega * M.dot(rate, _axis())
		+ 0.5 * ROTOR_INERTIA_KG_M2 * omega * omega
	)
	var velocity: PackedFloat64Array = body.slice(RB.VEL, RB.VEL + 3)
	return rotational + 0.5 * sim.mass * M.dot(velocity, velocity)


func _axial_momentum(body: PackedFloat64Array, values: PackedFloat64Array) -> float:
	var rate: PackedFloat64Array = body.slice(RB.RATE, RB.RATE + 3)
	var locked: PackedFloat64Array = RB.inertia_mul(_locked_body_inertia(), rate)
	return M.dot(locked, _axis()) + ROTOR_INERTIA_KG_M2 * values[0] * TAU / 60.0


func _fail(message: String) -> void:
	push_error("glow coupling bench: " + message)
	quit(2)
