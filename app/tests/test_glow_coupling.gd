extends SceneTree

const TwoStroke := preload("res://physics/glow/two_stroke.gd")
const FourStroke := preload("res://physics/glow/four_stroke.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Rotor := preload("res://physics/rotor_coupling.gd")
const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Sim := preload("res://sim/simulation.gd")

const AIR_DENSITY_KG_M3 := 1.18
const ROTOR_INERTIA_KG_M2 := 8.0e-5
const TEST_DURATION_S := 2.5

var _checks: int = 0
var _failures: int = 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if condition else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not condition:
		_failures += 1


func _initialize() -> void:
	Engine.physics_ticks_per_second = 240
	_test_prop_map_energy_admissibility()
	for engine: String in ["2t", "4t"]:
		_test_engine_prop_and_rotor_signs(engine)
		var at_240: Dictionary = _run_case(engine, 240, int(TEST_DURATION_S * 240.0))
		var at_480: Dictionary = _run_case(engine, 480, int(TEST_DURATION_S * 480.0))
		var at_960: Dictionary = _run_case(engine, 960, int(TEST_DURATION_S * 960.0))
		_test_loaded_run(engine, at_240)
		_test_refinement(engine, at_240, at_480, at_960)
		_test_checkpoint_pause_and_fault(engine)
	Engine.physics_ticks_per_second = 240
	print("glow shaft/prop coupling: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_engine_prop_and_rotor_signs(engine: String) -> void:
	var parameters: Dictionary = _parameters(engine)
	var prop: Dictionary = _propeller()
	var zero_air: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
	var forward_air: PackedFloat64Array = PackedFloat64Array([15.0, 0.0, 0.0])
	var stopped: PackedFloat64Array = Propulsion.thrust_torque(zero_air, 5000.0, prop, AIR_DENSITY_KG_M3)
	var forward: PackedFloat64Array = Propulsion.thrust_torque(forward_air, 5000.0, prop, AIR_DENSITY_KG_M3)
	var stopped_load: float = Propulsion.prop_torque(5000.0, 0.0, prop, AIR_DENSITY_KG_M3)
	var forward_load: float = Propulsion.prop_torque(5000.0, 15.0, prop, AIR_DENSITY_KG_M3)
	_check("%s estimated prop produces positive static thrust" % engine, stopped[0] > 0.0)
	_check("%s estimated prop absorbs positive shaft torque" % engine, stopped_load > 0.0)
	_check("%s Propulsion.prop_torque matches thrust_torque load" % engine,
		absf(stopped_load - stopped[1]) <= 1.0e-12, "prop=%s output=%s" % [stopped_load, stopped[1]])
	_check("%s forward inflow advances the propeller" % engine, forward[2] > 0.0)
	_check("%s forward inflow unloads the estimated Cp curve" % engine, forward_load < stopped_load)
	_check("%s thrust remains forward under forward inflow" % engine, forward[0] > 0.0)

	var rpm: float = 5000.0
	var initial_kernel: Dictionary = _engine_result(engine, rpm, 0.6, parameters)
	var initial_prop_torque: float = Propulsion.prop_torque(rpm, 0.0, prop, AIR_DENSITY_KG_M3)
	_check("%s initial admission torque exceeds estimated static prop load" % engine,
		float(initial_kernel.get("shaft_torque_nm", 0.0)) > initial_prop_torque, str(initial_kernel))

	var initial_state: PackedFloat64Array = _initial_state()
	var initial_z: PackedFloat64Array = PackedFloat64Array([rpm, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var spin_up: Dictionary = _evaluate_point(engine, initial_state, initial_z, 0.0, parameters, prop)
	var cut_z: PackedFloat64Array = initial_z.duplicate()
	cut_z[0] = 9000.0
	var spin_down: Dictionary = _evaluate_point(engine, initial_state, cut_z, 1.5, parameters, prop)
	_check("%s has positive initial shaft acceleration" % engine,
		spin_up.get("ok", false) and float(spin_up.get("rpm_rate", 0.0)) > 0.0,
		str(spin_up.get("rpm_rate", NAN)))
	_check("%s low admission overcomes prop torque with negative shaft acceleration" % engine,
		spin_down.get("ok", false) and float(spin_down.get("rpm_rate", 0.0)) < 0.0,
		str(spin_down.get("rpm_rate", NAN)))
	_check("%s spin-up reaction opposes positive rotor acceleration" % engine,
		float(spin_up.get("reaction_x_nm", 0.0)) < 0.0)
	_check("%s spin-down reaction opposes negative rotor acceleration" % engine,
		float(spin_down.get("reaction_x_nm", 0.0)) > 0.0)

	var two_stroke_probe: Dictionary = _engine_result("2t", rpm, 0.6, _parameters("2t"))
	var four_stroke_probe: Dictionary = _engine_result("4t", rpm, 0.6, _parameters("4t"))
	_check("%s uses its family-specific cadence" % engine,
		absf(float(initial_kernel["cycle_frequency_hz"]) - (rpm / (60.0 if engine == "2t" else 120.0))) < 1.0e-12)
	_check("720-degree opportunity cadence is half the 2T cadence",
		absf(float(four_stroke_probe["opportunity_frequency_hz"]) * 2.0
			- float(two_stroke_probe["opportunity_frequency_hz"])) < 1.0e-12)


func _test_loaded_run(engine: String, run: Dictionary) -> void:
	_check("%s simulation accepted every requested RK4 tick" % engine,
		run.get("ticks", -1) == int(TEST_DURATION_S * 240.0) and str(run.get("fault", "")).is_empty(),
		"ticks=%s fault=%s" % [run.get("ticks", -1), run.get("fault", "")])
	_check("%s loaded run spins above and below its initial RPM" % engine,
		float(run.get("max_rpm", 0.0)) > 5000.0 and float(run.get("final_rpm", INF)) < float(run.get("max_rpm", 0.0)))
	_check("%s fixed prop produces positive thrust and body inflow" % engine,
		float(run.get("max_thrust_n", 0.0)) > 0.0 and float(run.get("max_inflow_mps", 0.0)) > 0.0)
	_check("%s delivered fuel contains the burned mass" % engine,
		float(run.get("delivered_fuel_kg", 0.0)) >= float(run.get("burned_fuel_kg", INF))
			and float(run.get("burned_fuel_kg", 0.0)) > 0.0)
	var prop_work_margin_j: float = float(run.get("propeller_absorbed_work_j", -INF)) - float(run.get("thrust_work_j", INF))
	_check("%s integrated prop drag work covers thrust work in still air" % engine,
		prop_work_margin_j >= -maxf(1.0e-8, absf(float(run.get("thrust_work_j", 0.0))) * 1.0e-10),
		"margin=%s J prop=%s J thrust=%s J" % [
			String.num_scientific(prop_work_margin_j),
			run.get("propeller_absorbed_work_j", NAN), run.get("thrust_work_j", NAN)
		])
	_check("%s body-free angular momentum closes against prop drag impulse" % engine,
		float(run.get("angular_momentum_error", INF)) < 2.0e-9,
		"%s N·m·s" % String.num_scientific(float(run.get("angular_momentum_error", INF))))
	_check("%s rotor and translation work close independently" % engine,
		float(run.get("work_error_j", INF)) < 1.0e-3,
		"%s J" % String.num_scientific(float(run.get("work_error_j", INF))))


func _test_refinement(engine: String, coarse: Dictionary, medium: Dictionary, fine: Dictionary) -> void:
	var coarse_error: float = _state_distance(coarse["body"], coarse["continuous"], medium["body"], medium["continuous"])
	var fine_error: float = _state_distance(medium["body"], medium["continuous"], fine["body"], fine["continuous"])
	_check("%s 240/480/960 Hz traces stay finite" % engine,
		is_finite(coarse_error) and is_finite(fine_error))
	_check("%s 480/960 Hz endpoint refinement improves over 240/480 Hz" % engine,
		fine_error < coarse_error, "coarse=%s fine=%s" % [coarse_error, fine_error])
	_check("%s conservation error tightens at the finest step" % engine,
		float(fine["work_error_j"]) < float(coarse["work_error_j"])
			and float(fine["angular_momentum_error"]) <= float(coarse["angular_momentum_error"]) + 1.0e-12,
		"work=%s→%s angular=%s→%s" % [
			coarse["work_error_j"], fine["work_error_j"],
			coarse["angular_momentum_error"], fine["angular_momentum_error"]
		])


func _test_checkpoint_pause_and_fault(engine: String) -> void:
	var sim: Node = _new_sim(engine, 240)
	for _tick: int in 120:
		sim.step()
	var checkpoint: Dictionary = sim.checkpoint()
	_check("%s full continuous checkpoint is valid" % engine, not checkpoint.is_empty())
	var encoded_checkpoint: PackedByteArray = var_to_bytes(checkpoint)

	for _tick: int in 80:
		sim.step()
	var expected: PackedByteArray = var_to_bytes(sim.checkpoint())
	_check("%s branch continuation runs without a simulation fault" % engine, sim.fault_reason.is_empty())

	_check("%s accepts its exact checkpoint for replay" % engine, sim.restore_checkpoint(bytes_to_var(encoded_checkpoint)))
	_check("%s restored checkpoint pauses before explicit resume" % engine, sim.paused)
	var paused_tick: int = sim.tick
	sim._physics_process(sim.dt())
	_check("%s pause prevents a physics tick" % engine, sim.tick == paused_tick)
	sim.set_paused(false)
	for _tick: int in 80:
		sim.step()
	_check("%s checkpoint replay is byte-exact" % engine, var_to_bytes(sim.checkpoint()) == expected)
	sim.free()

	var fault_sim: Node = _new_sim(engine, 240)
	for _tick: int in 8:
		fault_sim.step()
	var before_fault: Dictionary = fault_sim.checkpoint()
	var original_evaluate: Callable = fault_sim.model.stage
	var evaluate_calls: Array[int] = [0]
	fault_sim.model.stage = func(body: PackedFloat64Array, values: PackedFloat64Array, time_s: float) -> Dictionary:
		evaluate_calls[0] += 1
		if evaluate_calls[0] == 3:
			return {}
		return original_evaluate.call(body, values, time_s)
	fault_sim.step()
	_check("%s malformed joint RK stage faults and pauses" % engine,
		fault_sim.paused and fault_sim.fault_reason.contains("joint stage"))
	_check("%s malformed joint RK stage rolls back every state lane" % engine,
		_simulation_matches(fault_sim, before_fault))
	fault_sim.free()


func _run_case(engine: String, hz: int, ticks: int) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var parameters: Dictionary = _parameters(engine)
	var prop: Dictionary = _propeller()
	var sim: Node = _new_sim(engine, hz)
	if not sim.fault_reason.is_empty():
		var failed := {
			"ticks": -1, "fault": sim.fault_reason,
			"body": PackedFloat64Array(), "continuous": PackedFloat64Array(),
			"max_rpm": 0.0, "final_rpm": 0.0, "max_thrust_n": 0.0,
			"max_inflow_mps": 0.0, "max_prop_torque_nm": 0.0,
			"delivered_fuel_kg": 0.0, "burned_fuel_kg": 0.0,
			"work_error_j": INF, "angular_momentum_error": INF,
		}
		sim.free()
		return failed
	var initial_body: PackedFloat64Array = sim.state.duplicate()
	var initial_continuous: PackedFloat64Array = sim.continuous.duplicate()
	var initial_energy: float = _total_energy(sim, initial_body, initial_continuous)
	var initial_momentum: float = _axial_momentum(initial_body, initial_continuous)
	var max_rpm: float = float(sim.continuous[0])
	var max_thrust_n: float = 0.0
	var max_inflow_mps: float = 0.0
	var max_prop_torque_nm: float = 0.0
	var fault: String = ""
	for _tick: int in ticks:
		sim.step()
		if not sim.fault_reason.is_empty():
			fault = sim.fault_reason
			break
		max_rpm = maxf(max_rpm, float(sim.continuous[0]))
		var point: Dictionary = _evaluate_point(
			engine, sim.state, sim.continuous, sim.time(), parameters, prop
		)
		if not point.get("ok", false):
			fault = str(point.get("error", "test sample evaluation failed"))
			break
		max_thrust_n = maxf(max_thrust_n, float(point["thrust_n"]))
		max_inflow_mps = maxf(max_inflow_mps, float(point["inflow_mps"]))
		max_prop_torque_nm = maxf(max_prop_torque_nm, float(point["prop_torque_nm"]))

	var final_body: PackedFloat64Array = sim.state.duplicate()
	var final_continuous: PackedFloat64Array = sim.continuous.duplicate()
	var final_energy: float = _total_energy(sim, final_body, final_continuous)
	var final_momentum: float = _axial_momentum(final_body, final_continuous)
	var expected_work: float = final_continuous[1] - final_continuous[2] + final_continuous[3]
	var work_error_j: float = absf(final_energy - initial_energy - expected_work)
	var angular_momentum_error: float = absf(
		final_momentum - initial_momentum - final_continuous[4]
	)
	var result := {
		"ticks": sim.tick,
		"fault": fault,
		"body": final_body,
		"continuous": final_continuous,
		"max_rpm": max_rpm,
		"final_rpm": final_continuous[0],
		"max_thrust_n": max_thrust_n,
		"max_inflow_mps": max_inflow_mps,
		"max_prop_torque_nm": max_prop_torque_nm,
		"delivered_fuel_kg": final_continuous[5],
		"burned_fuel_kg": final_continuous[6],
		"propeller_absorbed_work_j": final_continuous[2],
		"thrust_work_j": final_continuous[3],
		"work_error_j": work_error_j,
		"angular_momentum_error": angular_momentum_error,
	}
	sim.free()
	return result

func _new_sim(engine: String, hz: int) -> Node:
	Engine.physics_ticks_per_second = hz
	var parameters: Dictionary = _parameters(engine)
	var prop: Dictionary = _propeller()
	var sim: Node = Sim.new()
	sim.mass = 0.25
	sim.gravity = 0.0
	sim.inertia = _locked_body_inertia()
	sim.continuous = PackedFloat64Array([5000.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	sim.aux = PackedFloat64Array([5000.0])
	sim.modes = PackedInt64Array([1])
	sim.model.block_aux = func(values: PackedFloat64Array, _sampled_aux: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array([values[0]])
	sim.model.stage = func(body: PackedFloat64Array, values: PackedFloat64Array, time_s: float) -> Dictionary:
		var point: Dictionary = _evaluate_point(engine, body, values, time_s, parameters, prop)
		if not point.get("ok", false):
			return {}
		return {
			"loads": point["loads"],
			"derivative": point["derivative"],
			"rotor_momentum": point["rotor_momentum"],
		}
	sim.reset(_initial_state())
	return sim

func _evaluate_point(
		engine: String,
		body: PackedFloat64Array,
		values: PackedFloat64Array,
		time_s: float,
		parameters: Dictionary,
		prop: Dictionary
	) -> Dictionary:
	if body.size() != RB.SIZE or values.size() != 7:
		return {"ok": false, "error": "malformed body or continuous state"}
	if values[0] < 0.0:
		return {"ok": false, "error": "negative trial RPM is outside the mean-cycle coupling model"}
	var rpm: float = values[0]
	var admission: float = _admission(time_s)
	var engine_point: Dictionary = _engine_result(engine, rpm, admission, parameters)
	if not engine_point.get("ok", false):
		return {"ok": false, "error": str(engine_point.get("error", engine_point.get("message", "engine kernel failed")))}
	var velocity: PackedFloat64Array = body.slice(RB.VEL, RB.VEL + 3)
	var prop_point: PackedFloat64Array = Propulsion.thrust_torque(
		velocity, rpm, prop, AIR_DENSITY_KG_M3
	)
	var prop_torque_nm: float = Propulsion.prop_torque(
		rpm, velocity[0], prop, AIR_DENSITY_KG_M3
	)
	var body_loads: PackedFloat64Array = Propulsion.loads(
		velocity, rpm, prop, AIR_DENSITY_KG_M3
	)
	var prop_external_moment_x: float = body_loads[3]
	var relative_speed_rad_s: float = rpm * TAU / 60.0
	var net_shaft_torque_nm: float = float(engine_point["shaft_torque_nm"]) - prop_torque_nm
	var body_rate: PackedFloat64Array = body.slice(RB.RATE, RB.RATE + 3)
	var response: Dictionary = Rotor.response(
		body_rate,
		body_loads.slice(3, 6),
		_locked_body_inertia(),
		RB.inertia_inverse(_locked_body_inertia()),
		_axis(),
		ROTOR_INERTIA_KG_M2,
		relative_speed_rad_s,
		net_shaft_torque_nm
	)
	if not response.get("ok", false):
		return {"ok": false, "error": "RotorCoupling.response rejected the stage"}
	for axis_index: int in 3:
		body_loads[3 + axis_index] += response.reaction[axis_index]

	var absolute_speed_rad_s: float = relative_speed_rad_s + M.dot(body_rate, _axis())
	var engine_work_rate_w: float = float(engine_point["shaft_torque_nm"]) * relative_speed_rad_s
	var prop_work_rate_w: float = prop_torque_nm * absolute_speed_rad_s
	var thrust_work_rate_w: float = prop_point[0] * M.dot(velocity, _axis())
	var rpm_rate: float = response.spin_acceleration * 60.0 / TAU
	var derivative := PackedFloat64Array([
		rpm_rate,
		engine_work_rate_w,
		prop_work_rate_w,
		thrust_work_rate_w,
		prop_external_moment_x,
		float(engine_point["delivered_fuel_kg_s"]),
		float(engine_point["burned_fuel_kg_s"]),
	])
	for lane: float in derivative:
		if not is_finite(lane):
			return {"ok": false, "error": "nonfinite stage derivative"}
	return {
		"ok": true,
		"loads": body_loads,
		"derivative": derivative,
		"rotor_momentum": response.momentum,
		"engine_torque_nm": float(engine_point["shaft_torque_nm"]),
		"prop_torque_nm": prop_torque_nm,
		"thrust_n": prop_point[0],
		"advance_ratio": prop_point[2],
		"inflow_mps": velocity[0],
		"rpm_rate": rpm_rate,
		"reaction_x_nm": response.reaction[0],
		"admission": admission,
	}


func _engine_result(engine: String, rpm: float, admission: float, parameters: Dictionary) -> Dictionary:
	if engine == "2t":
		return TwoStroke.evaluate(rpm, admission, 1.0, AIR_DENSITY_KG_M3, parameters, true, 1.0)
	return FourStroke.evaluate(rpm, admission, 1.0, AIR_DENSITY_KG_M3, parameters, true, 1.0)


func _parameters(engine: String) -> Dictionary:
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
		"mechanical_torque_nm": PackedFloat64Array([0.0, 0.025, 16000.0, 0.025]),
		"combustion_efficiency": PackedFloat64Array([0.0, 0.8, 2.0, 0.8]),
		"indicated_efficiency": PackedFloat64Array([0.0, 0.14, 16000.0, 0.14]),
		"volumetric_efficiency": PackedFloat64Array([0.0, 0.85, 16000.0, 0.85]),
		"pumping_pressure_pa": PackedFloat64Array([0.0, 600.0, 16000.0, 600.0]),
		"intake_pressure_drop_pa": 250.0,
		"valve_torque_nm": PackedFloat64Array([0.0, 0.006, 16000.0, 0.006]),
	}


func _flat_curve(value: float, x_end: float = 16000.0) -> PackedFloat64Array:
	return PackedFloat64Array([0.0, value, x_end, value])


func _propeller() -> Dictionary:
	# Estimated, deliberately simple test propeller; not a measured or manufacturer map.
	return {
		"diameter": 0.30,
		"ct": PackedFloat64Array([0.0, 0.10, 0.2, 0.075, 0.5, 0.04, 1.0, 0.01, 1.2, 0.0]),
		"cp": PackedFloat64Array([0.0, 0.045, 0.2, 0.043, 0.5, 0.03, 1.0, 0.02, 1.2, 0.0]),
		"cp_min": 0.0,
		"offset": PackedFloat64Array([0.0, 0.0, 0.0]),
	}


func _test_prop_map_energy_admissibility() -> void:
	var prop: Dictionary = _propeller()
	var ct: PackedFloat64Array = prop["ct"]
	var cp: PackedFloat64Array = prop["cp"]
	var rpm: float = 6000.0
	var n: float = rpm / 60.0
	var diameter_m: float = float(prop["diameter"])
	var rho: float = AIR_DENSITY_KG_M3
	var power_scale_w: float = rho * n * n * n * pow(diameter_m, 5.0)
	var tolerance_w: float = 1.0e-12 * maxf(1.0, power_scale_w)
	var sample_margin_w: float = INF
	for sample_index: int in range(0, 1201):
		var advance_ratio: float = float(sample_index) / 1000.0
		var inflow_mps: float = advance_ratio * n * diameter_m
		var output: PackedFloat64Array = Propulsion.thrust_torque(
			PackedFloat64Array([inflow_mps, 0.0, 0.0]), rpm, prop, rho
		)
		var prop_torque_nm: float = Propulsion.prop_torque(rpm, inflow_mps, prop, rho)
		var margin_w: float = prop_torque_nm * rpm * TAU / 60.0 - output[0] * inflow_mps
		sample_margin_w = minf(sample_margin_w, margin_w)
	_check("estimated prop map satisfies J·Ct ≤ Cp over 0≤J≤1.2 samples",
		sample_margin_w >= -tolerance_w,
		"minimum prop-drag minus thrust power=%s W" % String.num_scientific(sample_margin_w))

	var interval_min_margin_w := INF
	for row: int in range(0, ct.size() - 2, 2):
		var x0: float = ct[row]
		var x1: float = ct[row + 2]
		var ct_slope: float = (ct[row + 3] - ct[row + 1]) / (x1 - x0)
		var ct_intercept: float = ct[row + 1] - ct_slope * x0
		var cp_slope: float = (cp[row + 3] - cp[row + 1]) / (x1 - x0)
		var cp_intercept: float = cp[row + 1] - cp_slope * x0
		var candidates: Array[float] = [x0, x1]
		if absf(ct_slope) > 1.0e-15:
			var vertex: float = -(ct_intercept - cp_slope) / (2.0 * ct_slope)
			if vertex > x0 and vertex < x1:
				candidates.append(vertex)
		for advance_ratio: float in candidates:
			var sampled_ct: float = Propulsion.coefficient(ct, advance_ratio, -0.1)
			var sampled_cp: float = Propulsion.coefficient(cp, advance_ratio, 0.0)
			var margin: float = sampled_cp - advance_ratio * sampled_ct
			interval_min_margin_w = minf(interval_min_margin_w, margin * power_scale_w)
	_check("estimated prop map satisfies J·Ct ≤ Cp at every interval endpoint and extremum",
		interval_min_margin_w >= -tolerance_w,
		"minimum admissibility margin=%s W" % String.num_scientific(interval_min_margin_w))
	var windmilling_ct: float = Propulsion.coefficient(ct, 1.5, -0.1)
	var windmilling_cp: float = Propulsion.coefficient(cp, 1.5, 0.0)
	_check("beyond map coverage uses negative drag Ct and a zero Cp floor",
		windmilling_ct < 0.0 and windmilling_cp == 0.0,
		"Ct=%s Cp=%s; windmilling is not qualified" % [windmilling_ct, windmilling_cp])


func _locked_body_inertia() -> PackedFloat64Array:
	# Explicit locked carrier-plus-rotor tensor; not inferred from an aircraft catalog.
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
	return 0.3


func _total_energy(sim: Node, body: PackedFloat64Array, values: PackedFloat64Array) -> float:
	var rate: PackedFloat64Array = body.slice(RB.RATE, RB.RATE + 3)
	var locked_angular_momentum: PackedFloat64Array = RB.inertia_mul(sim.inertia, rate)
	var omega: float = values[0] * TAU / 60.0
	var rotational: float = 0.5 * M.dot(rate, locked_angular_momentum) 		+ ROTOR_INERTIA_KG_M2 * omega * M.dot(rate, _axis()) 		+ 0.5 * ROTOR_INERTIA_KG_M2 * omega * omega
	var velocity: PackedFloat64Array = body.slice(RB.VEL, RB.VEL + 3)
	var translational: float = 0.5 * sim.mass * M.dot(velocity, velocity)
	return rotational + translational


func _axial_momentum(body: PackedFloat64Array, values: PackedFloat64Array) -> float:
	var rate: PackedFloat64Array = body.slice(RB.RATE, RB.RATE + 3)
	var locked: PackedFloat64Array = RB.inertia_mul(_locked_body_inertia(), rate)
	return M.dot(locked, _axis()) + ROTOR_INERTIA_KG_M2 * values[0] * TAU / 60.0


func _state_distance(
		body_left: PackedFloat64Array,
		continuous_left: PackedFloat64Array,
		body_right: PackedFloat64Array,
		continuous_right: PackedFloat64Array
	) -> float:
	if body_left.size() != body_right.size() or continuous_left.size() != continuous_right.size():
		return INF
	var distance: float = 0.0
	for i: int in body_left.size():
		distance = maxf(distance, absf(body_left[i] - body_right[i]) / maxf(1.0, absf(body_right[i])))
	for i: int in continuous_left.size():
		distance = maxf(distance, absf(continuous_left[i] - continuous_right[i]) / maxf(1.0, absf(continuous_right[i])))
	return distance


func _simulation_matches(sim: Node, snapshot: Dictionary) -> bool:
	if sim.tick != snapshot.get("tick", -1) or sim.stop_at_tick != snapshot.get("stop_at_tick", -2):
		return false
	for key: String in ["state", "previous", "continuous", "aux", "inputs", "modes", "last_loads"]:
		if var_to_bytes(sim.get(key)) != var_to_bytes(snapshot.get(key)):
			return false
	return true
