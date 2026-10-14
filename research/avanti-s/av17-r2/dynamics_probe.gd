extends SceneTree

## Reproducible AV-17-R2 paired static trim / roll-damping probe.
## Run from the app project so res://physics resolves to app/physics:
##   godot --headless --path app --script <absolute-path>/dynamics_probe.gd -- \
##     --aircraft=<baseline.json> --aircraft=<candidate.json> --out=<comparison.json>
## The model files are inputs only; this probe does not edit aircraft or runtime code.

const AD := preload("res://physics/aircraft_data.gd")
const Trim := preload("res://physics/trim.gd")
const Air := preload("res://physics/air_data.gd")
const Aero := preload("res://physics/aero.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const M := preload("res://physics/math3d.gd")

const RHO := 1.225
const G := 9.80665
const MIN_SWEEP_MPS := 16.0
const MAX_SWEEP_MPS := 24.0
const STEP_MPS := 0.05
const RATE_STEP_RAD_S := 0.01


func _initialize() -> void:
	var aircraft_paths: Array[String] = []
	var output_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--aircraft="):
			aircraft_paths.append(arg.trim_prefix("--aircraft="))
		elif arg.begins_with("--out="):
			output_path = arg.trim_prefix("--out=")
	if aircraft_paths.is_empty():
		aircraft_paths.append("res://data/aircraft/sebart_avanti_s_a200.json")

	var result := {
		"probe": "AV-17-R2 runtime trim and roll-rate derivative",
		"method": {
			"density_kg_m3": RHO,
			"gravity_m_s2": G,
			"trim": "Trim.solve(level, V, model, g, throw_rad, rho), clean model, calm air",
			"minimum_trim_resolution_m_s": STEP_MPS,
			"clp_rate_difference_rad_s": RATE_STEP_RAD_S,
			"clp_definition": "(dMx/dp) * 2V / (qbar*S*b^2); positive means roll anti-damping",
			"lift_cl_definition": "Aero.loads force (excluding propulsion) projected normal to the body longitudinal velocity, divided by qbar*S; prop_normal_cl is computed separately from Dynamics.evaluate",
			"limits": "software-model result only; not an A200 flight validation or measured polar"
		},
		"cases": []
	}
	for path in aircraft_paths:
		result.cases.append(_run_case(path))
	var text := JSON.stringify(result, "\t", false)
	if output_path.is_empty():
		print(text)
	else:
		var file := FileAccess.open(output_path, FileAccess.WRITE)
		if file == null:
			printerr("cannot write ", output_path, " (error ", FileAccess.get_open_error(), ")")
			quit(2)
			return
		file.store_string(text + "\n")
		file.close()
		print("wrote ", output_path)
	quit(0)


func _run_case(path: String) -> Dictionary:
	var loaded: Dictionary = AD.load_file(path)
	if not loaded.ok:
		return {"aircraft_path": path, "ok": false, "errors": loaded.errors}
	var model: Dictionary = loaded.model
	var first_success := NAN
	var previous_failure := NAN
	var successful_points := 0
	var sweep_max_cl := -INF
	var sweep_max: Dictionary = {}
	var index := 0
	while MIN_SWEEP_MPS + STEP_MPS * float(index) <= MAX_SWEEP_MPS + 1e-9:
		var speed := MIN_SWEEP_MPS + STEP_MPS * float(index)
		var sample := _trim_sample(speed, model)
		if sample.ok:
			successful_points += 1
			if is_nan(first_success):
				first_success = speed
			if float(sample.total_aero_cl) > sweep_max_cl:
				sweep_max_cl = float(sample.total_aero_cl)
				sweep_max = sample
		else:
			if is_nan(first_success):
				previous_failure = speed
		index += 1

	if is_nan(first_success):
		return {"aircraft_path": path, "ok": false, "errors": ["no successful level trim in sweep"]}

	var trim_at_floor := _trim_sample(first_success, model)
	var comparable_speeds: Array[float] = [18.5, 18.6, 19.0, 19.2, 29.0]
	# Add the first successful speed and a point one tenth above it, retaining fixed comparison points.
	comparable_speeds.append(first_success)
	comparable_speeds.append(first_success + 0.1)
	var unique_speeds: Array[float] = []
	for speed in comparable_speeds:
		if not unique_speeds.has(speed):
			unique_speeds.append(speed)
	var rate_rows: Array[Dictionary] = []
	for speed in unique_speeds:
		var row := _trim_sample(speed, model)
		if row.ok:
			rate_rows.append(_roll_rate_sample(speed, model, row))
		else:
			rate_rows.append({"speed_m_s": speed, "trim_ok": false, "trim_message": row.get("message", "")})

	var vs_declared := sqrt(2.0 * model.mass_kg * G / (RHO * model.reference.S * model.envelope.CL_max))
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))	
	var twist_values: Array = []
	if raw.get("aero", {}).get("surfaces", {}).has("wing_station_incidence"):
		twist_values = raw.aero.surfaces.wing_station_incidence.value
	return {
		"aircraft_file": path.get_file(),
		"case_id": path.get_file().get_basename(),
		"ok": true,
		"input_identity": loaded.get("input_identity", {}),
		"model_identity": raw.get("name", raw.get("id", "")),
		"declared_global_cl_max": model.envelope.CL_max,
		"vs_from_declared_clmax_m_s": vs_declared,
		"min_successful_trim_grid_m_s": first_success,
		"preceding_failed_grid_m_s": previous_failure,
		"trim_speed_grid_step_m_s": STEP_MPS,
		"successful_trim_points_16_to_24_m_s": successful_points,
		"trim_at_grid_floor": _compact_trim(trim_at_floor),
		"maximum_total_cl_in_trim_sweep": {"total_cl": sweep_max_cl, "sample": _compact_trim(sweep_max)},
		"rate_derivatives_at_comparison_speeds": rate_rows,
		"wing_station_incidence_rad_root_mid_tip": twist_values
	}


func _trim_sample(speed: float, model: Dictionary) -> Dictionary:
	var row: Dictionary = Trim.solve("level", speed, model, G, model.controls.throw_rad, RHO)
	if not row.ok:
		return {"ok": false, "message": row.get("message", "")}
	var state: PackedFloat64Array = row.state
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var controls := {
		"elevator": row.elevator,
		"aileron_right": row.aileron,
		"aileron_left": -row.aileron,
		"rudder": row.rudder
	}
	var loads: PackedFloat64Array = Aero.loads(state, air, controls, model, RHO)
	var total_cl := _lift_coefficient(loads, air, model.reference.S)
	var dynamics: Dictionary = Dynamics.evaluate(state, model, controls, row.rpm, RHO, M.v3(0.0, 0.0, 0.0), G)
	var prop_normal_cl := _lift_coefficient(dynamics.propulsion_loads, air, model.reference.S)
	var force_normal_cl := total_cl + prop_normal_cl
	var required_weight_cl: float = model.mass_kg * G / (air.qbar * model.reference.S)
	var wing_cl: float = Aero.wing_lift_coefficient(state, air, controls, model)
	var vs_from_trim_cl := sqrt(2.0 * model.mass_kg * G / (RHO * model.reference.S * total_cl))
	var tip_fraction := 0.0
	for strip in Aero.wing_strip_loads(state, air, controls, model, RHO):
		if absf(float(strip.y_m)) > 0.7:
			tip_fraction = maxf(tip_fraction, float(strip.stall_weight))
	return {
		"ok": true,
		"speed_m_s": speed,
		"alpha_deg": rad_to_deg(row.alpha),
		"beta_deg": rad_to_deg(row.beta),
		"elevator_deg": rad_to_deg(row.elevator),
		"elevator": row.elevator,
		"aileron": row.aileron,
		"rudder": row.rudder,
		"state": state,
		"throttle": row.throttle,
		"rpm": row.rpm,
		"wing_cl": wing_cl,
		"total_aero_cl": total_cl,
		"prop_normal_cl": prop_normal_cl,
		"aero_plus_prop_normal_cl": force_normal_cl,
		"weight_required_cl_at_speed": required_weight_cl,
		"normal_force_cl_residual": force_normal_cl - required_weight_cl,
		"vs_from_aero_cl_no_thrust_m_s": vs_from_trim_cl,
		"max_tip_separation_weight": tip_fraction
	}


func _roll_rate_sample(speed: float, model: Dictionary, trim: Dictionary) -> Dictionary:
	var state: PackedFloat64Array = trim.state
	var air: Dictionary = Air.compute(state, M.v3(0.0, 0.0, 0.0), RHO)
	var controls := {
		"elevator": trim.elevator,
		"aileron_right": trim.aileron,
		"aileron_left": -trim.aileron,
		"rudder": trim.rudder
	}
	var plus: PackedFloat64Array = state.duplicate()
	var minus: PackedFloat64Array = state.duplicate()
	plus[10] = RATE_STEP_RAD_S
	minus[10] = -RATE_STEP_RAD_S
	var lp: PackedFloat64Array = Aero.loads(plus, Air.compute(plus, M.v3(0.0, 0.0, 0.0), RHO), controls, model, RHO)
	var lm: PackedFloat64Array = Aero.loads(minus, Air.compute(minus, M.v3(0.0, 0.0, 0.0), RHO), controls, model, RHO)
	var dmx_dp: float = (lp[3] - lm[3]) / (2.0 * RATE_STEP_RAD_S)
	var clp: float = dmx_dp * 2.0 * speed / (air.qbar * model.reference.S * model.reference.b * model.reference.b)
	var local := Aero._local_loads(state, air, controls, model, RHO)
	var global := Aero._global_loads(state, air, controls, model, RHO)
	return {
		"speed_m_s": speed,
		"trim_ok": true,
		"alpha_deg": trim.alpha_deg,
		"tip_separation_weight": trim.max_tip_separation_weight,
		"dMx_dp_N_m_per_rad_s": dmx_dp,
		"Clp_p_hat": clp,
		"local_flow_weight": Aero.local_flow_weight(state, air, controls, model),
		"total_cl": trim.total_aero_cl,
		"local_cl": _lift_coefficient(local, air, model.reference.S),
		"global_cl_at_trim_state": _lift_coefficient(global, air, model.reference.S)
	}


func _lift_coefficient(loads: PackedFloat64Array, air: Dictionary, area: float) -> float:
	var plane_speed := sqrt(air.v_air[0] * air.v_air[0] + air.v_air[2] * air.v_air[2])
	var lift_x: float = air.v_air[2] / plane_speed
	var lift_z: float = -air.v_air[0] / plane_speed
	return (loads[0] * lift_x + loads[2] * lift_z) / (air.qbar * area)


func _compact_trim(row: Dictionary) -> Dictionary:
	var result := {}
	for key in ["ok", "message", "speed_m_s", "alpha_deg", "beta_deg", "elevator_deg", "throttle", "rpm",
		"wing_cl", "total_aero_cl", "prop_normal_cl", "aero_plus_prop_normal_cl", "weight_required_cl_at_speed",
		"normal_force_cl_residual", "vs_from_aero_cl_no_thrust_m_s", "max_tip_separation_weight"]:
		if row.has(key):
			result[key] = row[key]
	return result
