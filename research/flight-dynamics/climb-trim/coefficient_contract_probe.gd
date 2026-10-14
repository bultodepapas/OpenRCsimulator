extends SceneTree
## Independent attached-flow scalar oracle for the global coefficient contract and
## the local horizontal-tail control derivative. It reads validated fleet data but
## does not call production Aero for the reported oracle values.

const AircraftCatalog = preload("res://app_state/aircraft_catalog.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
const Aero = preload("res://physics/aero.gd") # comparison only; never the oracle source
const RigidBody = preload("res://physics/rigid_body.gd")

const OUTPUT_RELATIVE := "docs/research/flight-dynamics/climb-trim/coefficient-contract-experiments.json"
const RHO := 1.225
const SPEED := 15.0
const ALPHA_PROBE := 0.05235987755982989 # 3 deg, inside the attached-flow region
const SAMPLE_DE := 0.08726646259971647 # 5 deg, aero convention: trailing edge down is positive
const FD_STEP := 0.00001 # rad, central differences; pitch-rate coordinate is q*c/(2V)
const QHAT_CASES := [-0.01, 0.0, 0.01]
const LOAD_FORCE_TOLERANCE_N := 1e-9
const LOAD_MOMENT_TOLERANCE_NM := 1e-9


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var app_path := ProjectSettings.globalize_path("res://").trim_suffix("/")
	var repo_path := app_path.path_join("..").simplify_path()
	var probe_path := repo_path.path_join("research/flight-dynamics/climb-trim/coefficient_contract_probe.gd")
	var aero_path := app_path.path_join("physics/aero.gd")
	var source_hashes_start := {"aero_gd": _sha256(aero_path), "probe_gd": _sha256(probe_path)}
	var rows: Array = []
	for entry in AircraftCatalog.flyable_entries():
		var loaded: Dictionary = AircraftData.load_file(str(entry.data))
		if not loaded.get("ok", false):
			push_error("Unable to load %s: %s" % [entry.id, loaded.get("errors", [])])
			quit(1)
			return
		var model: Dictionary = loaded.model
		var raw: Dictionary = _read_raw(str(entry.data))
		rows.append(_analyze(str(entry.id), str(entry.data), raw, model))
	var source_hashes_end := {"aero_gd": _sha256(aero_path), "probe_gd": _sha256(probe_path)}
	var source_hash_guard_passed: bool = source_hashes_start == source_hashes_end
	var max_runtime_fx_error := 0.0
	var max_runtime_fz_error := 0.0
	var max_runtime_my_error := 0.0
	var runtime_case_count := 0
	var runtime_checks_passed := true
	var coefficient_checks_passed := true
	for row in rows:
		var check: Dictionary = row.runtime_global_load_cross_check
		max_runtime_fx_error = maxf(max_runtime_fx_error, float(check.max_abs_fx_error_n))
		max_runtime_fz_error = maxf(max_runtime_fz_error, float(check.max_abs_fz_error_n))
		max_runtime_my_error = maxf(max_runtime_my_error, float(check.max_abs_my_error_nm))
		runtime_case_count += int(check.case_count)
		runtime_checks_passed = runtime_checks_passed and bool(check.passed)
		coefficient_checks_passed = coefficient_checks_passed and float(row.production_cross_check_max_abs_CL_CD_Cm) <= 1e-12
	var validation := {
		"production_coefficients_cross_check_passed": coefficient_checks_passed,
		"runtime_global_load_cross_check_passed": runtime_checks_passed,
		"runtime_global_load_case_count": runtime_case_count,
		"runtime_max_abs_fx_error_n": max_runtime_fx_error,
		"runtime_max_abs_fz_error_n": max_runtime_fz_error,
		"runtime_max_abs_my_error_nm": max_runtime_my_error,
		"runtime_force_tolerance_n": LOAD_FORCE_TOLERANCE_N,
		"runtime_moment_tolerance_nm": LOAD_MOMENT_TOLERANCE_NM,
		"source_hash_guard_passed": source_hash_guard_passed,
		"source_hashes_start": source_hashes_start,
		"source_hashes_end": source_hashes_end,
		"passed": rows.size() == 7 and coefficient_checks_passed and runtime_checks_passed and source_hash_guard_passed
	}

	var report := {
		"format": "openrc-coefficient-contract-experiments-v2",
		"purpose": "Independent scalar audit of the attached global coefficient reference, force transfer ARP to CG, and local horizontal-tail elevator force/moment derivative.",
		"scope": "Seven catalog aircraft at fixed 15 m/s and sea-level density. Coefficients are authored or estimated inputs; agreement between two model paths is an internal contract check, not physical validation.",
		"method": {
			"input_loader": "AircraftData.load_file validates and derives each catalog model; raw source bytes are SHA-256 fingerprinted.",
			"global_oracle": "CL = CL0 + CLa*alpha + CLde*de + CLq*qhat; CD = CD0 + k*(CL_static-CL_minD)^2 + abs(CDde*de); Cm_ARP = Cm0 + Cma*alpha + Cmde*de + Cmq*qhat. qhat=q*c/(2V). The body force is resolved in FRD and M_CG=M_ARP+(r_ARP-CG cross F).",
			"local_oracle": "Scalar horizontal-tail law at alpha=0, qhat=0; section lift and drag are evaluated at de=+/-1e-5 rad and force is resolved with the authored tail arm about CG. This isolates the local tail's elevator derivative; the local wing has no direct elevator term.",
			"finite_difference": "Central differences use 1e-5 rad for alpha, aero elevator and qhat. The absolute-value global CDde term is nondifferentiable at de=0, so both one-sided slopes are also retained.",
			"sign_and_frame": {
				"data_control": "aero elevator positive = trailing edge down",
				"pilot_control": "pilot elevator positive = trailing edge up",
				"mapping": "pilot +5 deg maps to aero de=-5 deg; negative aero elevator therefore decreases attached CL and, for negative Cmde, adds nose-up Cm",
				"body_axes": "FRD: x forward, y right, z down",
				"position_datum": "LE data [aft,right,up] to body arm [-(x-cg_x), y-cg_y, -(z-cg_z)]",
				"arp_transfer": "r_ARP-CG=[-(arp_x-cg_x), arp_y-cg_y, -(arp_z-cg_z)]; M_CG=M_ARP+r cross F"
			},
			"production_comparison": "Aero.coefficients is cross-checked at alpha=+/-3 deg and elevator=+/-5 deg. Aero._global_loads is separately cross-checked for Fx, Fz and My_CG over alpha=+/-3 deg, elevator=-5/0/+5 deg and qhat=-0.01/0/+0.01. Neither function supplies oracle results.",
			"state_layout": "RigidBody.make_state constructs the 13-value state with body rates at indices 10..12; the pitch rate passed to runtime is q=2*V*qhat/c."
		},
		"condition": {"rho_kg_m3": RHO, "speed_m_s": SPEED, "qbar_pa": 0.5 * RHO * SPEED * SPEED, "alpha_probe_rad": ALPHA_PROBE, "alpha_probe_deg": rad_to_deg(ALPHA_PROBE), "elevator_sample_rad": SAMPLE_DE, "elevator_sample_deg": rad_to_deg(SAMPLE_DE), "finite_difference_step_rad": FD_STEP, "attached_only": true},
		"validation": validation,
		"aircraft": rows
	}
	var out_path := repo_path.path_join(OUTPUT_RELATIVE)
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	if out == null:
		push_error("Cannot write research result %s (error %d)" % [out_path, FileAccess.get_open_error()])
		quit(1)
		return
	out.store_string(JSON.stringify(report, "\t") + "\n")
	out.close()
	if not validation.passed:
		push_error("coefficient contract runtime check failed: %s" % validation)
		quit(1)
		return
	print("wrote " + out_path + " (" + str(rows.size()) + " aircraft, " + str(runtime_case_count)
		+ " runtime cases; max Fx/Fz/My errors N/N/Nm=" + str(max_runtime_fx_error) + "/"
		+ str(max_runtime_fz_error) + "/" + str(max_runtime_my_error) + ")")
	quit(0)


func _read_raw(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed := JSON.new()
	if parsed.parse(text) != OK or typeof(parsed.data) != TYPE_DICTIONARY:
		return {}
	return parsed.data


func _sha256(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	hasher.update(bytes)
	return hasher.finish().hex_encode()


func _analyze(id: String, path: String, raw: Dictionary, model: Dictionary) -> Dictionary:
	var ref: Dictionary = model.reference
	var aero: Dictionary = model.aero
	var surfaces: Dictionary = model.surfaces
	var cg: PackedFloat64Array = model.cg_le
	var arp: PackedFloat64Array = ref.arp_le
	var tail: Dictionary = surfaces.horizontal
	var chord: float = ref.c
	var area: float = ref.S
	var arp_arm := PackedFloat64Array([-(arp[0] - cg[0]), arp[1] - cg[1], -(arp[2] - cg[2])])
	var tail_arm := PackedFloat64Array([-(tail.position[0] - cg[0]), tail.position[1] - cg[1], -(tail.position[2] - cg[2])])
	var tail_aft_arp: float = float(tail.position[0]) - float(arp[0])
	var source_clde: Dictionary = raw.get("aero", {}).get("coefficients", {}).get("CLde", {})
	var source_cmde: Dictionary = raw.get("aero", {}).get("coefficients", {}).get("Cmde", {})
	var d0 := {"elevator": 0.0, "aileron_right": 0.0, "aileron_left": 0.0, "rudder": 0.0}
	var base_plus_alpha := _global_point(ALPHA_PROBE + FD_STEP, 0.0, 0.0, aero, ref, arp_arm)
	var base_minus_alpha := _global_point(ALPHA_PROBE - FD_STEP, 0.0, 0.0, aero, ref, arp_arm)
	var de_plus := _global_point(ALPHA_PROBE, FD_STEP, 0.0, aero, ref, arp_arm)
	var de_minus := _global_point(ALPHA_PROBE, -FD_STEP, 0.0, aero, ref, arp_arm)
	var q_plus := _global_point(ALPHA_PROBE, 0.0, FD_STEP, aero, ref, arp_arm)
	var q_minus := _global_point(ALPHA_PROBE, 0.0, -FD_STEP, aero, ref, arp_arm)
	var negative_sample := _global_point(ALPHA_PROBE, -SAMPLE_DE, 0.0, aero, ref, arp_arm)
	var neutral_sample := _global_point(ALPHA_PROBE, 0.0, 0.0, aero, ref, arp_arm)
	var positive_sample := _global_point(ALPHA_PROBE, SAMPLE_DE, 0.0, aero, ref, arp_arm)
	var production_error := _production_error(aero)
	var runtime_cross_check := _runtime_load_cross_check(model, aero, ref, arp_arm)
	var local_plus := _local_tail_point(0.0, FD_STEP, 0.0, model)
	var local_minus := _local_tail_point(0.0, -FD_STEP, 0.0, model)
	var local_neutral := _local_tail_point(0.0, 0.0, 0.0, model)
	var global_clde: float = float(aero.CLde)
	var global_cmde: float = float(aero.Cmde)
	var local_clde: float = _central(local_plus.CL, local_minus.CL, FD_STEP)
	var local_cmde_cg: float = _central(local_plus.Cm_CG, local_minus.Cm_CG, FD_STEP)
	var local_cmde_arp: float = _central(local_plus.Cm_ARP, local_minus.Cm_ARP, FD_STEP)
	var local_cdde: float = _central(local_plus.CD, local_minus.CD, FD_STEP)
	var ratio_arm := NAN
	if absf(global_clde) > 1e-12:
		ratio_arm = -global_cmde * chord / global_clde
	var tail_arm_candidate := NAN
	if tail_aft_arp > 1e-12:
		tail_arm_candidate = -global_cmde * chord / tail_aft_arp
	var alpha_derivatives := _derivatives(base_plus_alpha, base_minus_alpha, FD_STEP)
	var control_derivatives := _derivatives(de_plus, de_minus, FD_STEP)
	var qhat_derivatives := _derivatives(q_plus, q_minus, FD_STEP)
	var points: Array = []
	for sample in [-SAMPLE_DE, 0.0, SAMPLE_DE]:
		var values: Dictionary = _global_point(ALPHA_PROBE, float(sample), 0.0, aero, ref, arp_arm)
		points.append({"alpha_rad": ALPHA_PROBE, "elevator_aero_rad_te_down_positive": sample, "CL": values.CL, "CD": values.CD, "Cm_ARP": values.Cm_ARP, "Cm_CG": values.Cm_CG, "force_body_frd_n": values.force_body})
	var result := {
		"id": id,
		"source_path": path,
		"source_sha256": _sha256(path),
		"derived_model_sha256": str(model.get("data_sha256", "")),
		"coefficient_provenance": {"CLde": source_clde, "Cmde": source_cmde},
		"reference": {"S_m2": area, "b_m": ref.b, "c_m": chord, "cg_le_aft_right_up_m": cg, "arp_le_aft_right_up_m": arp, "arp_minus_cg_body_frd_m": arp_arm, "tail_arm_from_cg_body_frd_m": tail_arm, "tail_aft_of_arp_m": tail_aft_arp},
		"global_coefficients_at_attached_probe": {"CL0": aero.CL0, "CLa_per_rad": aero.CLa, "CLq_per_rad": aero.CLq, "CLde_per_rad": global_clde, "CD0": aero.CD0, "k_induced": aero.k_induced, "CL_minD": aero.CL_minD, "CDde_per_rad_magnitude": aero.CDde, "Cm0": aero.Cm0, "Cma_per_rad": aero.Cma, "Cmq_per_rad": aero.Cmq, "Cmde_per_rad": global_cmde, "input_kind_CLde": source_clde.get("kind", ""), "input_kind_Cmde": source_cmde.get("kind", "")},
		"production_cross_check_max_abs_CL_CD_Cm": production_error,
		"runtime_global_load_cross_check": runtime_cross_check,
		"attached_global_finite_differences": {"about_alpha_rad": ALPHA_PROBE, "dCL_dalpha_per_rad": alpha_derivatives.CL, "dCD_dalpha_per_rad": alpha_derivatives.CD, "dCmARP_dalpha_per_rad": alpha_derivatives.Cm_ARP, "dCmCG_dalpha_per_rad": alpha_derivatives.Cm_CG, "dCL_dde_per_rad": control_derivatives.CL, "dCD_dde_central_at_zero": control_derivatives.CD, "dCD_dde_right_at_zero": _one_sided(de_plus.CD, neutral_sample.CD, FD_STEP), "dCD_dde_left_at_zero": _one_sided(neutral_sample.CD, de_minus.CD, FD_STEP), "dCmARP_dde_per_rad": control_derivatives.Cm_ARP, "dCmCG_dde_per_rad": control_derivatives.Cm_CG, "qhat_definition": "q*c/(2V)", "dCL_dqhat": qhat_derivatives.CL, "dCD_dqhat": qhat_derivatives.CD, "dCmARP_dqhat": qhat_derivatives.Cm_ARP, "dCmCG_dqhat": qhat_derivatives.Cm_CG},
		"local_horizontal_tail_control_derivative_at_alpha0": {"baseline_CL": local_neutral.CL, "baseline_CD": local_neutral.CD, "baseline_Cm_CG": local_neutral.Cm_CG, "dCL_dde_per_rad": local_clde, "dCD_dde_per_rad": local_cdde, "dCmCG_dde_per_rad": local_cmde_cg, "dCmARP_dde_per_rad": local_cmde_arp, "tail_model_CLde_from_lift_slope_times_tau_area_ratio": float(tail.free_slope if tail.has("free_slope") else tail.lift_slope) * float(tail.elevator_tau if tail.has("elevator_tau") else tail.control_effectiveness) * float(tail.area) / area},
		"counterfactual_candidates": {"global_CLde_to_preserve_authored_Cmde_at_tail_aft_of_ARP_per_rad": tail_arm_candidate, "local_tail_finite_difference_CLde_per_rad": local_clde, "local_tail_finite_difference_Cmde_at_ARP_per_rad": local_cmde_arp, "global_ratio_equivalent_aft_arm_m_pure_lift_only": ratio_arm, "interpretation": "Sensitivity candidates only. The ratio assumes a single lift force at the tail and omits force-axis rotation, drag, wing/control interaction, dynamic flow and coefficient provenance uncertainty."},
		"coefficient_samples": points,
		"negative_elevator_sign_check": {"pilot_elevator_te_up_deg": 5.0, "aero_de_rad": -deg_to_rad(5.0), "delta_CL": negative_sample.CL - neutral_sample.CL, "delta_Cm_ARP": negative_sample.Cm_ARP - neutral_sample.Cm_ARP, "delta_Cm_CG": negative_sample.Cm_CG - neutral_sample.Cm_CG, "positive_aero_de_expected": "more attached lift, negative pitch moment for a stabilizing tail", "negative_aero_de_expected": "less attached lift, positive pitch moment (nose-up)"}
	}
	return result


func _global_coefficients(alpha: float, de: float, qhat: float, aero: Dictionary) -> Dictionary:
	var cl_static: float = float(aero.CL0) + float(aero.CLa) * alpha + float(aero.CLde) * de
	var cl_total: float = cl_static + float(aero.CLq) * qhat
	var cd: float = float(aero.CD0) + float(aero.k_induced) * pow(cl_static - float(aero.CL_minD), 2.0) + absf(float(aero.CDde) * de)
	var cm: float = float(aero.Cm0) + float(aero.Cma) * alpha + float(aero.Cmde) * de + float(aero.Cmq) * qhat
	return {"CL": cl_total, "CL_static": cl_static, "CD": cd, "Cm_ARP": cm}


func _global_point(alpha: float, de: float, qhat: float, aero: Dictionary, ref: Dictionary, arp_arm: PackedFloat64Array) -> Dictionary:
	var coeff := _global_coefficients(alpha, de, qhat, aero)
	var qbar: float = 0.5 * RHO * SPEED * SPEED
	var lift: float = qbar * float(ref.S) * float(coeff.CL)
	var drag: float = qbar * float(ref.S) * float(coeff.CD)
	var sa := sin(alpha)
	var ca := cos(alpha)
	var fx: float = -drag * ca + lift * sa
	var fy := 0.0
	var fz: float = -drag * sa - lift * ca
	var my_arp: float = qbar * float(ref.S) * float(ref.c) * float(coeff.Cm_ARP)
	var my_cg: float = my_arp + arp_arm[2] * fx - arp_arm[0] * fz
	return {"CL": coeff.CL, "CD": coeff.CD, "Cm_ARP": coeff.Cm_ARP, "Cm_CG": my_cg / (qbar * float(ref.S) * float(ref.c)), "force_body": PackedFloat64Array([fx, fy, fz]), "moment_arp_nm": my_arp, "moment_cg_nm": my_cg}


func _local_tail_point(alpha: float, de: float, qhat: float, model: Dictionary) -> Dictionary:
	var ref: Dictionary = model.reference
	var surfaces: Dictionary = model.surfaces
	var tail: Dictionary = surfaces.horizontal
	var cg: PackedFloat64Array = model.cg_le
	var arp: PackedFloat64Array = ref.arp_le
	var position: PackedFloat64Array = tail.position
	var arm := PackedFloat64Array([-(position[0] - cg[0]), position[1] - cg[1], -(position[2] - cg[2])])
	var q_rate: float = 2.0 * SPEED * qhat / float(ref.c)
	var flow_x: float = SPEED * cos(alpha) + q_rate * arm[2]
	var flow_z: float = SPEED * sin(alpha) - q_rate * arm[0]
	var speed := sqrt(flow_x * flow_x + flow_z * flow_z)
	var flow_angle := atan2(flow_z, flow_x)
	var wing_cl := _wing_cl_attached(alpha, qhat, model)
	var effective: float
	var slope: float
	if tail.has("free_slope"):
		effective = wrapf(flow_angle - float(tail.downwash_per_cl) * wing_cl + float(tail.elevator_tau) * de + float(tail.free_incidence), -PI, PI)
		slope = float(tail.free_slope)
	else:
		effective = wrapf(flow_angle + float(tail.control_effectiveness) * de + float(tail.incidence), -PI, PI)
		slope = float(tail.lift_slope)
	var local_limit: float = float(surfaces.tail_local_limit)
	var stall_end: float = float(surfaces.tail_stall_end)
	var blend := _smoothstep((absf(effective) - local_limit) / (stall_end - local_limit))
	var cl: float = (1.0 - blend) * slope * effective + blend * 0.5 * float(surfaces.tail_CD90) * sin(2.0 * effective)
	var cd: float = float(surfaces.tail_CD0) + float(surfaces.tail_k) * cl * cl + float(surfaces.tail_CD90) * pow(sin(effective), 2.0)
	var force_scale: float = -0.5 * RHO * speed * float(tail.area) * cd
	var fx: float = flow_x * force_scale
	var fz: float = flow_z * force_scale
	if speed > 1e-10:
		var lift: float = 0.5 * RHO * speed * speed * float(tail.area) * cl
		fx += lift * flow_z / speed
		fz -= lift * flow_x / speed
	var my_cg: float = arm[2] * fx - arm[0] * fz
	var arp_arm := PackedFloat64Array([-(arp[0] - cg[0]), arp[1] - cg[1], -(arp[2] - cg[2])])
	var my_arp: float = my_cg - (arp_arm[2] * fx - arp_arm[0] * fz)
	var qbar_s: float = 0.5 * RHO * SPEED * SPEED * float(ref.S)
	var ca := cos(alpha)
	var sa := sin(alpha)
	var cl_wind: float = (fx * sa - fz * ca) / qbar_s
	var cd_wind: float = -(fx * ca + fz * sa) / qbar_s
	var c_scale: float = qbar_s * float(ref.c)
	return {"CL": cl_wind, "CD": cd_wind, "Cm_CG": my_cg / c_scale, "Cm_ARP": my_arp / c_scale, "force_body": PackedFloat64Array([fx, 0.0, fz]), "wing_cl": wing_cl, "tail_alpha": effective}


func _wing_cl_attached(alpha: float, qhat: float, model: Dictionary) -> float:
	var env: Dictionary = model.get("envelope", {})
	var ref: Dictionary = model.reference
	var aero: Dictionary = model.aero
	var ys: PackedFloat64Array = env.get("station_ys", PackedFloat64Array())
	var e_map: PackedFloat64Array = env.get("induced_map", PackedFloat64Array())
	var strip_cl0: PackedFloat64Array = env.get("strip_cl0", PackedFloat64Array())
	if ys.is_empty() or e_map.size() != ys.size() * ys.size() or strip_cl0.size() != ys.size():
		return float(aero.CL0) + float(aero.CLa) * alpha + float(aero.CLq) * qhat
	var twist: PackedFloat64Array = model.surfaces.get("station_incidence", PackedFloat64Array())
	var cg: PackedFloat64Array = model.cg_le
	var arp: PackedFloat64Array = ref.arp_le
	var ax: float = -(arp[0] - cg[0])
	var ay: float = arp[1] - cg[1]
	var az: float = -(arp[2] - cg[2])
	var q_rate: float = 2.0 * SPEED * qhat / float(ref.c)
	var angles := PackedFloat64Array()
	angles.resize(ys.size())
	for i in ys.size():
		var arm_y: float = ay + ys[i]
		var flow_x: float = SPEED * cos(alpha) + q_rate * az
		var flow_z: float = SPEED * sin(alpha) - q_rate * ax
		var geometric := atan2(flow_z, flow_x)
		if not twist.is_empty():
			geometric += twist[i]
		angles[i] = geometric
	var strip_slope: float = float(env.get("strip_slope", aero.CLa))
	var mean_cl := 0.0
	for i in ys.size():
		var mapped := 0.0
		for k in ys.size():
			mapped += e_map[i * ys.size() + k] * angles[k]
		mean_cl += (strip_cl0[i] + strip_slope * mapped) / ys.size()
	return mean_cl


func _production_error(aero: Dictionary) -> float:
	var max_error := 0.0
	var rates := PackedFloat64Array([0.0, 0.0, 0.0])
	for a in [-ALPHA_PROBE, ALPHA_PROBE]:
		for de in [-SAMPLE_DE, 0.0, SAMPLE_DE]:
			var air := {"alpha": float(a), "beta": 0.0, "V": SPEED, "qbar": 0.5 * RHO * SPEED * SPEED}
			var controls := {"elevator": float(de), "aileron_right": 0.0, "aileron_left": 0.0, "rudder": 0.0}
			var independent := _global_coefficients(float(a), float(de), 0.0, aero)
			var observed: Dictionary = Aero.coefficients(air, rates, controls, aero, {})
			for key in ["CL", "CD", "Cm"]:
				var oracle_key: String = "Cm_ARP" if key == "Cm" else key
				max_error = maxf(max_error, absf(float(independent[oracle_key]) - float(observed[key])))
	return max_error


func _runtime_load_cross_check(model: Dictionary, aero: Dictionary, ref: Dictionary, arp_arm: PackedFloat64Array) -> Dictionary:
	var max_fx_error := 0.0
	var max_fz_error := 0.0
	var max_my_error := 0.0
	var worst_case := {}
	var case_count := 0
	for alpha in [-ALPHA_PROBE, ALPHA_PROBE]:
		for de in [-SAMPLE_DE, 0.0, SAMPLE_DE]:
			for qhat in QHAT_CASES:
				var alpha_value: float = float(alpha)
				var de_value: float = float(de)
				var qhat_value: float = float(qhat)
				var q_rate: float = 2.0 * SPEED * qhat_value / float(ref.c)
				var velocity := PackedFloat64Array([SPEED * cos(alpha_value), 0.0, SPEED * sin(alpha_value)])
				var rates := PackedFloat64Array([0.0, q_rate, 0.0])
				var state: PackedFloat64Array = RigidBody.make_state(PackedFloat64Array([0.0, 0.0, 0.0]), velocity,
					PackedFloat64Array([1.0, 0.0, 0.0, 0.0]), rates)
				var air := {"alpha": alpha_value, "beta": 0.0, "V": SPEED, "qbar": 0.5 * RHO * SPEED * SPEED, "v_air": velocity}
				var controls := {"elevator": de_value, "aileron_right": 0.0, "aileron_left": 0.0, "rudder": 0.0}
				var expected: Dictionary = _global_point(alpha_value, de_value, qhat_value, aero, ref, arp_arm)
				var observed: PackedFloat64Array = Aero._global_loads(state, air, controls, model, RHO)
				var error_fx: float = absf(observed[0] - expected.force_body[0])
				var error_fz: float = absf(observed[2] - expected.force_body[2])
				var error_my: float = absf(observed[4] - expected.moment_cg_nm)
				case_count += 1
				if error_fx > max_fx_error or error_fz > max_fz_error or error_my > max_my_error:
					worst_case = {"alpha_rad": alpha_value, "elevator_rad": de_value, "qhat": qhat_value}
				max_fx_error = maxf(max_fx_error, error_fx)
				max_fz_error = maxf(max_fz_error, error_fz)
				max_my_error = maxf(max_my_error, error_my)
	return {"case_count": case_count, "max_abs_fx_error_n": max_fx_error, "max_abs_fz_error_n": max_fz_error, "max_abs_my_error_nm": max_my_error, "worst_case_coordinates": worst_case, "force_tolerance_n": LOAD_FORCE_TOLERANCE_N, "moment_tolerance_nm": LOAD_MOMENT_TOLERANCE_NM, "passed": max_fx_error <= LOAD_FORCE_TOLERANCE_N and max_fz_error <= LOAD_FORCE_TOLERANCE_N and max_my_error <= LOAD_MOMENT_TOLERANCE_NM}


func _derivatives(plus: Dictionary, minus: Dictionary, h: float) -> Dictionary:
	return {"CL": _central(plus.CL, minus.CL, h), "CD": _central(plus.CD, minus.CD, h), "Cm_ARP": _central(plus.Cm_ARP, minus.Cm_ARP, h), "Cm_CG": _central(plus.Cm_CG, minus.Cm_CG, h)}


func _central(plus: float, minus: float, h: float) -> float:
	return (plus - minus) / (2.0 * h)


func _one_sided(plus: float, base: float, h: float) -> float:
	return (plus - base) / h


func _smoothstep(x: float) -> float:
	var t: float = clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
