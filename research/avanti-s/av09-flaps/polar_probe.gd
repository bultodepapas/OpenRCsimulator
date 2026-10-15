## Static AV-09 model sensitivity probe: 1-g aerodynamic trim and positive lift polar.
## Run with Godot --headless --path app --script <this file> --
##   --baseline=<gain-0 model.json> --candidate=<gain-1 model.json> --out=<new report.json>.
## These are deterministic model calculations, not measured aircraft performance.
extends SceneTree

const AircraftData := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const RB := preload("res://physics/rigid_body.gd")
const Commands := preload("res://input/commands.gd")
const M := preload("res://physics/math3d.gd")

const RHO_KGM3: float = 1.225
const G_MPS2: float = 9.80665
const TRIM_SPEEDS_MPS: Array[float] = [20.0, 22.0, 24.0, 27.0, 30.0]
const POLAR_SPEED_MPS: float = 30.0

var _baseline_path: String = ""
var _candidate_path: String = ""
var _out_path: String = ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline="):
			_baseline_path = argument.trim_prefix("--baseline=")
		elif argument.begins_with("--candidate="):
			_candidate_path = argument.trim_prefix("--candidate=")
		elif argument.begins_with("--out="):
			_out_path = argument.trim_prefix("--out=")
	if _baseline_path.is_empty() or _candidate_path.is_empty() or _out_path.is_empty():
		printerr("polar_probe.gd requires --baseline, --candidate, and --out paths")
		quit(2)
		return
	call_deferred("_run")


func _run() -> void:
	var baseline: Dictionary = AircraftData.load_file(_baseline_path)
	var candidate: Dictionary = AircraftData.load_file(_candidate_path)
	if not baseline.get("ok", false) or not candidate.get("ok", false):
		printerr("cannot load AV-09 model(s): baseline=", baseline.get("errors", []),
			" candidate=", candidate.get("errors", []))
		quit(1)
		return
	if not baseline.model.has("flaps") or not candidate.model.has("flaps"):
		printerr("both probe models must carry the flap actuator/config")
		quit(1)
		return
	var models: Array[Dictionary] = [
		{"name": "same-tape baseline, flap aerodynamic gain 0", "model": baseline.model},
		{"name": "candidate, flap aerodynamic gain 1", "model": candidate.model},
	]
	var configurations: Array[Dictionary] = []
	for entry: Dictionary in models:
		var model: Dictionary = entry.model
		var configs: Array[Dictionary] = []
		for flap_fraction: float in [0.0, 0.4, 1.0]:
			var trim_by_speed: Array[Dictionary] = []
			for speed: float in TRIM_SPEEDS_MPS:
				var trim: Dictionary = _solve_trim(model, flap_fraction, speed)
				trim_by_speed.append({"speed_mps": speed, "one_g_trim": trim})
			var polar: Dictionary = _positive_polar(model, flap_fraction, POLAR_SPEED_MPS)
			var mix_fraction: float = flap_fraction * float(model.flaps.elevator_mix_per_flap_fraction)
			var elevator_throw_deg: float = float(model.controls.throw_deg.elevator)
			configs.append({
				"flap_fraction": flap_fraction,
				"flap_angle_deg": flap_fraction * float(model.flaps.max_angle_deg),
				"manual_mixer_at_zero_pilot_pitch": {
					"normalized_pitch_bias": -mix_fraction,
					"net_elevator_te_up_deg": -mix_fraction * elevator_throw_deg,
					"max_elevator_te_up_deg_at_full_up_command": (1.0 - mix_fraction) * elevator_throw_deg,
					"max_elevator_te_down_deg_at_full_down_command": -elevator_throw_deg,
					"upward_throw_remaining_fraction": 1.0 - mix_fraction,
					"downward_throw_remaining_fraction": 1.0,
					"note": "Shows the authored mixer bias and command clamp endpoints; it is not a servo-force or pilot-authority measurement.",
				},
				"one_g_trim_by_speed": trim_by_speed,
				"positive_lift_polar": polar,
			})
		var source_hash: String = str(baseline.get("input_identity", {}).get("sha256", "unavailable")) \
			if entry.name == models[0].name else str(candidate.get("input_identity", {}).get("sha256", "unavailable"))
		configurations.append({"model": entry.name, "aircraft_input_sha256": source_hash,
			"flap_aerodynamic_gain": model.flaps.get("aerodynamic_gain", NAN), "flap_configurations": configs})
	var fixed_state_increments: Array[Dictionary] = []
	for flap_fraction: float in [0.4, 1.0]:
		var mixed_pitch: float = flap_fraction * float(candidate.model.flaps.elevator_mix_per_flap_fraction)
		var baseline_value: Dictionary = _evaluate(baseline.model, TRIM_SPEEDS_MPS[3], deg_to_rad(7.0), mixed_pitch, flap_fraction, true)
		var candidate_value: Dictionary = _evaluate(candidate.model, TRIM_SPEEDS_MPS[3], deg_to_rad(7.0), mixed_pitch, flap_fraction, true)
		var qS: float = 0.5 * RHO_KGM3 * TRIM_SPEEDS_MPS[3] * TRIM_SPEEDS_MPS[3] * float(candidate.model.reference.S)
		fixed_state_increments.append({
			"flap_fraction": flap_fraction,
			"angle_deg": flap_fraction * float(candidate.model.flaps.max_angle_deg),
			"reference_speed_mps": TRIM_SPEEDS_MPS[3],
			"reference_alpha_deg": 7.0,
			"net_elevator_te_up_deg": 0.0,
			"aero_delta_candidate_minus_gain0": {
				"lift_n": float(candidate_value.lift_n) - float(baseline_value.lift_n),
				"drag_n": float(candidate_value.drag_n) - float(baseline_value.drag_n),
				"My_nm": float(candidate_value.loads[4]) - float(baseline_value.loads[4]),
				"delta_CL": float(candidate_value.CL) - float(baseline_value.CL),
				"delta_CD": float(candidate_value.CD) - float(baseline_value.CD),
				"delta_Cm_about_cg": (float(candidate_value.loads[4]) - float(baseline_value.loads[4])) / qS / float(candidate.model.reference.c),
				"local_wing_total_delta_My_nm": float(candidate_value.local_wing_My_nm) - float(baseline_value.local_wing_My_nm),
				"local_wing_section_couple_and_panel_drag_arm_delta_My_nm": float(candidate_value.local_wing_section_pitch_couple_nm) - float(baseline_value.local_wing_section_pitch_couple_nm),
			},
			"moment_sign_interpretation": "The isolated thin-airfoil quarter-chord flap lift couple is expected negative My (nose-down in FRD); total-airplane delta My also includes induced tail-wake changes and can have the opposite sign.",
		})
	var report: Dictionary = {
		"method": "AV-09 deterministic static aerodynamic model sensitivity",
		"scope": "1-g lift and pitch-moment equilibrium across approach speeds plus positive-angle lift polar at fixed speed",
		"not_physical_validation": true,
		"assumptions": {
			"density_kgm3": RHO_KGM3,
			"gravity_mps2": G_MPS2,
			"trim_speeds_mps": TRIM_SPEEDS_MPS,
			"polar_speed_mps": POLAR_SPEED_MPS,
			"wind_mps": [0.0, 0.0, 0.0],
			"body_rates_radps": [0.0, 0.0, 0.0],
			"control": "symmetric ailerons/rudder at zero; the authored flap-to-elevator mix is included in the steady elevator command",
			"trim": "Newton solution of vertical lift = weight and aerodynamic pitch moment = 0, with level flight-path kinematics; drag is reported as required thrust, not solved propulsion trim",
			"polar": "static fixed-speed alpha sweep from 0 to 70 degrees with zero pilot pitch command; the reported maximum is the broad-angle modeled peak, not a measured or usable stall-onset point",
			"implied_stall_speed": "ideal sqrt(2W/(rho*S*CLmax)) from that broad-angle CL maximum, including post-stall samples; a model sensitivity indicator only, never a landing-speed prescription",
			"positive_down_flap_moment": "the Glauert quarter-chord flap lift couple is expected negative ΔCm (nose-down) in FRD; full-airplane ΔMy includes tail wake and its sign is reported separately",
			"flap_gain_0": "software sensitivity control; not the clean aircraft's calibration",
		},
		"models": configurations,
		"fixed_state_flap_increments": fixed_state_increments,
	}
	var file: FileAccess = FileAccess.open(_out_path, FileAccess.WRITE)
	if file == null:
		printerr("cannot write AV-09 polar report: ", _out_path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t", true, true) + "\n")
	file.close()
	print("AV-09 static probe saved: ", _out_path)
	quit(0)


func _solve_trim(model: Dictionary, flap_fraction: float, speed: float) -> Dictionary:
	var weight: float = float(model.mass_kg) * G_MPS2
	var chord: float = float(model.reference.c)
	var alpha: float = deg_to_rad(7.0)
	var pitch_command: float = 0.0
	for iteration: int in 40:
		var value: Dictionary = _evaluate(model, speed, alpha, pitch_command, flap_fraction)
		var residual: PackedFloat64Array = _trim_residual(value, alpha, weight, chord)
		if maxf(absf(residual[0]), absf(residual[1])) < 2.0e-7:
			return {
				"status": "converged",
				"iterations": iteration,
				"alpha_deg": rad_to_deg(alpha),
				"pilot_pitch_command": pitch_command,
				"net_elevator_te_up_deg": float(value.net_elevator_te_up_deg),
				"lift_n": float(value.lift_n),
				"required_thrust_n": float(value.drag_n),
				"CL": float(value.CL),
				"CD": float(value.CD),
				"pitch_moment_nm": float(value.loads[4]),
			}
		var da: float = 1.0e-4
		var dp: float = 1.0e-4
		var r_alpha: PackedFloat64Array = _trim_residual(_evaluate(model, speed, alpha + da, pitch_command, flap_fraction), alpha + da, weight, chord)
		var r_pitch: PackedFloat64Array = _trim_residual(_evaluate(model, speed, alpha, pitch_command + dp, flap_fraction), alpha, weight, chord)
		var j00: float = (r_alpha[0] - residual[0]) / da
		var j10: float = (r_alpha[1] - residual[1]) / da
		var j01: float = (r_pitch[0] - residual[0]) / dp
		var j11: float = (r_pitch[1] - residual[1]) / dp
		var determinant: float = j00 * j11 - j01 * j10
		if not is_finite(determinant) or absf(determinant) < 1.0e-12:
			return {"status": "singular", "iterations": iteration, "residual": Array(residual)}
		var delta_alpha: float = (-residual[0] * j11 + residual[1] * j01) / determinant
		var delta_pitch: float = (-j00 * residual[1] + j10 * residual[0]) / determinant
		alpha = clampf(alpha + clampf(delta_alpha, -deg_to_rad(8.0), deg_to_rad(8.0)), deg_to_rad(-8.0), deg_to_rad(35.0))
		pitch_command = clampf(pitch_command + clampf(delta_pitch, -0.2, 0.2), -1.0, 1.0)
	var final_value: Dictionary = _evaluate(model, speed, alpha, pitch_command, flap_fraction)
	return {
		"status": "not_converged",
		"iterations": 40,
		"alpha_deg": rad_to_deg(alpha),
		"pilot_pitch_command": pitch_command,
		"net_elevator_te_up_deg": float(final_value.net_elevator_te_up_deg),
		"residual": Array(_trim_residual(final_value, alpha, weight, chord)),
	}


func _trim_residual(value: Dictionary, alpha: float, weight: float, chord: float) -> PackedFloat64Array:
	return PackedFloat64Array([
		(float(value.lift_n) - weight) / weight,
		float(value.loads[4]) / (weight * chord),
	])


func _positive_polar(model: Dictionary, flap_fraction: float, speed: float) -> Dictionary:
	var best_cl: float = -INF
	var best_alpha: float = 0.0
	var best_cd: float = NAN
	var positive_samples: int = 0
	for sample_index: int in 281:
		var alpha: float = deg_to_rad(float(sample_index) * 0.25)
		var value: Dictionary = _evaluate(model, speed, alpha, 0.0, flap_fraction)
		var cl: float = float(value.CL)
		var cd: float = float(value.CD)
		if not is_finite(cl) or not is_finite(cd):
			continue
		positive_samples += 1
		if cl > best_cl:
			best_cl = cl
			best_alpha = alpha
			best_cd = cd
	var speed_at_clmax: float = sqrt(2.0 * float(model.mass_kg) * G_MPS2 / (RHO_KGM3 * float(model.reference.S) * best_cl)) if best_cl > 0.0 else NAN
	return {
		"status": "complete" if positive_samples == 281 and is_finite(best_cl) else "incomplete",
		"samples": positive_samples,
		"alpha_step_deg": 0.25,
		"alpha_range_deg": [0.0, 70.0],
		"CLmax": best_cl,
		"alpha_at_CLmax_deg": rad_to_deg(best_alpha),
		"CD_at_CLmax": best_cd,
		"implied_one_g_stall_speed_mps": speed_at_clmax,
		"implied_one_g_stall_speed_interpretation": "Ideal sqrt(2W/(rho*S*CLmax)) using the global 0-70 degree sweep maximum, including post-stall samples; not measured stall onset or a landing-speed recommendation.",
	}


func _evaluate(model: Dictionary, speed: float, alpha: float, pitch_command: float, flap_fraction: float,
		include_wing_diagnostics: bool = false) -> Dictionary:
	var state: PackedFloat64Array = PackedFloat64Array([
		0.0, 0.0, 0.0,
		speed * M.cos_(alpha), 0.0, speed * M.sin_(alpha),
		1.0, 0.0, 0.0, 0.0,
		0.0, 0.0, 0.0,
	])
	var wind: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
	var air: Dictionary = Air.compute(state, wind, RHO_KGM3)
	var mixed_pitch: float = clampf(pitch_command - flap_fraction * float(model.flaps.elevator_mix_per_flap_fraction), -1.0, 1.0)
	var pilot: Dictionary = {roll = 0.0, pitch = mixed_pitch, yaw = 0.0}
	var surfaces: Dictionary = Commands.surface_deflections_deg(pilot, model.controls.throw_deg)
	var deflections: Dictionary = Aero.deflections_from_surfaces(surfaces)
	deflections.flap = deg_to_rad(flap_fraction * float(model.flaps.max_angle_deg))
	var loads: PackedFloat64Array = Aero.loads(state, air, deflections, model, RHO_KGM3)
	var wing_my: float = NAN
	var wing_couple_my: float = NAN
	if include_wing_diagnostics:
		wing_my = 0.0
		wing_couple_my = 0.0
		for strip: Dictionary in Aero.wing_strip_loads(state, air, deflections, model, RHO_KGM3):
			wing_my += float(strip.moment_body_nm[1])
			wing_couple_my += float(strip.section_pitch_couple_nm)
	var sa: float = M.sin_(alpha)
	var ca: float = M.cos_(alpha)
	var qS: float = air.qbar * float(model.reference.S)
	var lift: float = loads[0] * sa - loads[2] * ca
	var drag: float = -loads[0] * ca - loads[2] * sa
	return {
		"loads": loads,
		"lift_n": lift,
		"drag_n": drag,
		"CL": lift / qS if qS > 0.0 else NAN,
		"CD": drag / qS if qS > 0.0 else NAN,
		"net_elevator_te_up_deg": float(surfaces.elevator),
		"local_wing_My_nm": wing_my,
		"local_wing_section_pitch_couple_nm": wing_couple_my,
	}
