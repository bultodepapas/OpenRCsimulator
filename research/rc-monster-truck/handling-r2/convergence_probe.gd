extends SceneTree

## One-state isolated braking-contact experiment. It clones the frozen GDScript
## reference evaluator and compares baseline radial clipping with a mobility-metric
## Coulomb projection. Runtime and native sources are read-only.

const Vehicle := preload("res://physics/ground_vehicle/vehicle_dynamics.gd")
const Data := preload("res://physics/ground_vehicle/vehicle_data.gd")
const M := preload("res://physics/math3d.gd")
const SPEED_MPS := 9.8872212131554
const BRAKE_NM := 1.2
const BRAKE := {"throttle": 0.0, "steering": 0.0, "brake": 1.0, "reverse": false}
const BASELINE_ARG := "--handling-baseline="
const SOURCE_ARG := "--handling-source="

const EUCLIDEAN_BLOCK := """
			var trial_norm := M.sqrt_(trial_long * trial_long + trial_lateral * trial_lateral)
			var force_limit := maxf(0.0, float(contact["mu_load"]))
			if trial_norm > force_limit and trial_norm > 0.0:
				var ratio := force_limit / trial_norm
				trial_long *= ratio
				trial_lateral *= ratio
"""
const METRIC_BLOCK := """
			var force_limit := maxf(0.0, float(contact["mu_load"]))
			var projected := _handling_metric_projection(w00, w01, w10, w11,
				trial_long, trial_lateral, force_limit)
			trial_long = projected[0]
			trial_lateral = projected[1]
"""
func _initialize() -> void:
	_run.call_deferred()

func _road(_north: float, _east: float) -> Dictionary:
	return {"height_m": 0.0, "normal_ned": PackedFloat64Array([0.0, 0.0, -1.0]),
		"mu": 0.85, "rolling": 1.0, "surface_id": "handling_r2_flat"}

func _run() -> void:
	var loaded: Dictionary = Data.load_default()
	var source_path := ""
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with(BASELINE_ARG):
			loaded = Data.load_file(str(argument).substr(BASELINE_ARG.length()))
		elif str(argument).begins_with(SOURCE_ARG):
			source_path = str(argument).substr(SOURCE_ARG.length())
	if source_path.is_empty():
		_fail("frozen source path argument is required")
		return
	if not bool(loaded.get("ok", false)):
		_fail("vehicle data failed to load: " + JSON.stringify(loaded))
		return
	var base: Dictionary = loaded.model.duplicate(true)
	base.brake_torque_per_wheel_nm = BRAKE_NM
	var initialized: Dictionary = Vehicle.initialize(base, _road, 0.0, 0.0)
	if not bool(initialized.get("ok", false)):
		_fail("initialization failed: " + JSON.stringify(initialized))
		return
	var straight: PackedFloat64Array = initialized.state.duplicate()
	straight[Vehicle.VEL] = SPEED_MPS
	for corner in 4:
		straight[Vehicle.WHEEL_SPIN + corner] = SPEED_MPS / float(base.tire_radius_m)
	var source := FileAccess.get_file_as_string(source_path)
	if source.is_empty():
		_fail("could not read frozen evaluator source: " + source_path)
		return
	var outputs: Array[Dictionary] = []
	for case_name in ["reference6", "reference24", "reference64", "reference128",
			"metric6", "metric24", "metric64", "metric128"]:
		var kernel := _make_kernel(source, case_name)
		if kernel == null:
			_fail("could not compile evaluator clone: " + case_name)
			return
		var entry := {"name": case_name,
			"initial_exact_symmetric_diagnostic": _diagnostic(kernel, base, straight)}
		outputs.append(entry)
		print("CASE ", JSON.stringify(entry))
	var result := {
		"vehicle_descriptor_identity": loaded.get("identity", {}),
		"vehicle_drive_parameters": {"drive_torque_per_wheel_nm": base.drive_torque_per_wheel_nm,
			"drive_torque_fade_rad_s": base.drive_torque_fade_rad_s,
			"brake_torque_per_wheel_nm": base.brake_torque_per_wheel_nm},
		"evaluator": "Frozen GDScript reference source cloned in memory; direct _evaluate calls only",
		"native_evaluator_used": false,
		"frequency_hz": 240,
		"fixture": "flat mu=0.85, rolling=1.0; 9.887221 m/s straight braking; four matched wheel speeds",
		"brake_torque_per_wheel_nm": BRAKE_NM,
		"sources": ["referenceN: baseline Euclidean projection with the requested sweep cap",
			"metricN: constrained local minimizer in the mobility metric with the requested sweep cap"],
		"cases": outputs,
	}
	print("RESULT_JSON ", JSON.stringify(result))
	quit(0)

func _make_kernel(source: String, case_name: String) -> GDScript:
	var code := source
	var cap := 6
	if case_name.ends_with("24"):
		cap = 24
	elif case_name.ends_with("128"):
		cap = 128
	elif case_name.ends_with("64"):
		cap = 64
	if cap != 6:
		code = code.replace("const FRICTION_SWEEPS := 6", "const FRICTION_SWEEPS := %d" % cap)
	if case_name.begins_with("metric"):
		code = code.replace(EUCLIDEAN_BLOCK, METRIC_BLOCK)
		code += """

static func _handling_metric_projection(
	w00: float, w01: float, w10: float, w11: float,
	trial_long: float, trial_lateral: float, force_limit: float
) -> PackedFloat64Array:
	var result := PackedFloat64Array([trial_long, trial_lateral])
	if force_limit <= 0.0:
		return PackedFloat64Array([0.0, 0.0])
	if M.sqrt_(trial_long * trial_long + trial_lateral * trial_lateral) <= force_limit:
		return result
	var b0 := w00 * trial_long + w01 * trial_lateral
	var b1 := w10 * trial_long + w11 * trial_lateral
	var lo := 0.0
	var hi := maxf(1.0, M.sqrt_(b0 * b0 + b1 * b1) / force_limit)
	for _iteration in 32:
		var lmbda := 0.5 * (lo + hi)
		var a00 := w00 + lmbda
		var a11 := w11 + lmbda
		var determinant := a00 * a11 - w01 * w10
		var f0 := (a11 * b0 - w01 * b1) / determinant
		var f1 := (a00 * b1 - w10 * b0) / determinant
		if f0 * f0 + f1 * f1 > force_limit * force_limit:
			lo = lmbda
		else:
			hi = lmbda
	var lmbda := 0.5 * (lo + hi)
	var a00 := w00 + lmbda
	var a11 := w11 + lmbda
	var determinant := a00 * a11 - w01 * w10
	return PackedFloat64Array([
		(a11 * b0 - w01 * b1) / determinant,
		(a00 * b1 - w10 * b0) / determinant,
	])
"""
	code = code.replace("\"wheel_slip_speed_m_per_s\": tire_slip_speed,",
		"\"wheel_slip_speed_m_per_s\": tire_slip_speed,\n\t\t\"probe_slip_long\": tire_slip_long,\n\t\t\"probe_slip_lateral\": tire_slip_lat,")
	var script := GDScript.new()
	script.source_code = code
	if script.reload() != OK:
		print("COMPILE_ERROR ", case_name, " ", script.get_error())
		return null
	return script

func _diagnostic(kernel: GDScript, model: Dictionary, start: PackedFloat64Array) -> Dictionary:
	var evaluation: Dictionary = kernel.call("_evaluate", start, model, BRAKE, _road, false, false)
	if not bool(evaluation.get("ok", false)):
		return {"error": str(evaluation.get("error", "evaluation failed"))}
	var slip_long: PackedFloat64Array = evaluation.get("probe_slip_long", PackedFloat64Array())
	var slip_lat: PackedFloat64Array = evaluation.get("probe_slip_lateral", PackedFloat64Array())
	var slip_power := PackedFloat64Array()
	slip_power.resize(4)
	var total_power := 0.0
	for corner in 4:
		slip_power[corner] = (evaluation.wheel_longitudinal_force_n[corner] * slip_long[corner]
			+ evaluation.wheel_lateral_force_n[corner] * slip_lat[corner])
		total_power += slip_power[corner]
	return {
		"sweeps_used": evaluation.friction_sweeps_used,
		"yaw_accel_rad_s2": evaluation.generalized_acceleration[5],
		"lateral_accel_m_s2": evaluation.generalized_acceleration[1],
		"wheel_load_n_fl_fr_rl_rr": evaluation.wheel_load_n,
		"long_force_n_fl_fr_rl_rr": evaluation.wheel_longitudinal_force_n,
		"lat_force_n_fl_fr_rl_rr": evaluation.wheel_lateral_force_n,
		"brake_torque_nm_fl_fr_rl_rr": evaluation.wheel_brake_torque_n_m,
		"patch_slip_long_mps_fl_fr_rl_rr": slip_long,
		"patch_slip_lateral_mps_fl_fr_rl_rr": slip_lat,
		"slip_force_power_w_per_corner": slip_power,
		"sum_slip_force_power_w": total_power,
	}

func _fail(message: String) -> void:
	print("FAIL ", message)
	quit(1)
