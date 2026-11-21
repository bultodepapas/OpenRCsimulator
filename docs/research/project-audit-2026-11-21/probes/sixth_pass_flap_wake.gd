# Research witness for the static/settled flap wake contract. Stock data, no production edits.
extends SceneTree
const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Dynamics := preload("res://physics/dynamics.gd")
const GE := preload("res://physics/ground_effect.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const RHO := 1.225
var checks := 0
var failures := 0

func _check(label: String, okay: bool) -> void:
	checks += 1
	if not okay:
		failures += 1
		printerr("FAIL ", label)

func _difference(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for i in a.size():
		out.append(a[i] - b[i])
	return out

func _max_abs(a: PackedFloat64Array) -> float:
	var result := 0.0
	for value in a:
		result = maxf(result, absf(value))
	return result

func _case(filename: String, model: Dictionary, speed: float, alpha_deg: float,
		flap_deg: float, ground: bool) -> Dictionary:
	var alpha := deg_to_rad(alpha_deg)
	var zero := M.v3(0.0, 0.0, 0.0)
	var state := RB.make_state(M.v3(0.0, 0.0, -0.25),
		M.v3(speed*cos(alpha), 0.0, speed*sin(alpha)), M.q_identity(), zero)
	var air := Air.compute(state, zero, RHO)
	var ground_up: float = 0.0 if ground else NAN
	var ge := GE.factors(state, model, ground_up)
	var clean := {elevator=0.0, rudder=0.0, aileron_left=0.0, aileron_right=0.0}
	var deflections: Dictionary = clean.duplicate(true)
	deflections.flap = deg_to_rad(flap_deg)
	var wake_clean := Aero.wing_wake_velocity(state, air, clean, model, ground_up)
	var wake_flap := Aero.wing_wake_velocity(state, air, deflections, model, ground_up)
	var static_loads := Aero.loads(state, air, deflections, model, RHO, NAN, ground_up)
	var held_loads := Aero.loads(state, air, deflections, model, RHO, wake_flap, ground_up)
	var delta := _difference(held_loads, static_loads)
	var static_total := Dynamics.loads(state, model, deflections, 0.0, RHO, zero, NAN,
		PackedFloat64Array(), ground_up)
	var held_total := Dynamics.loads(state, model, deflections, 0.0, RHO, zero, wake_flap,
		PackedFloat64Array(), ground_up)
	var total_delta := _difference(held_total, static_total)
	var clean_blend_nan := Aero.local_flow_weight(state, air, clean, model, NAN, ge)
	var clean_blend_held := Aero.local_flow_weight(state, air, clean, model, wake_flap, ge)
	_check(filename + " finite load components", static_loads.size() == 6 and held_loads.size() == 6)
	for value in delta:
		_check(filename + " finite difference", is_finite(value))
	_check(filename + " shared Dynamics propagates component difference",
		_max_abs(_difference(total_delta, delta)) < 1e-10)
	if flap_deg == 0.0:
		_check(filename + " clean settled source equals static", _max_abs(delta) < 1e-11)
	if alpha_deg == 30.0:
		_check(filename + " fully local selection", clean_blend_nan == 1.0 and clean_blend_held == 1.0)
		_check(filename + " fully local settled source equals static", _max_abs(delta) < 1e-11)
	if alpha_deg == 0.0 and not ground and flap_deg == 10.0:
		_check(filename + " attached composite selection", clean_blend_nan == 0.0 and clean_blend_held == 0.0)
		_check(filename + " nonzero settled discrepancy", absf(delta[0]) > 0.001)
	var tail: Dictionary = model.surfaces.horizontal
	return {
		"aircraft": filename, "speed_mps": speed, "alpha_deg": alpha_deg,
		"flap_deg": flap_deg, "ground_effect_requested": ground,
		"clean_wake_mps": wake_clean, "flapped_wake_mps": wake_flap,
		"clean_blend_nan": clean_blend_nan, "clean_blend_held": clean_blend_held,
		"static_loads": Array(static_loads), "held_loads": Array(held_loads),
		"held_minus_static": Array(delta), "dynamics_held_minus_static": Array(total_delta),
		"oracle_inputs": {"rho": RHO, "tail_area": tail.area,
			"tail_free_slope": tail.free_slope, "tail_free_incidence": tail.free_incidence,
			"tail_downwash_gain": tail.downwash_per_cl,
			"tail_cd0": model.surfaces.tail_CD0, "tail_k": model.surfaces.tail_k,
			"tail_cd90": model.surfaces.tail_CD90,
			"tail_linear_limit_rad": model.surfaces.tail_local_limit,
			"tail_position_le": Array(tail.position), "cg_le": Array(model.cg_le)}
	}

func _initialize() -> void:
	var records: Array = []
	var admissions: Array = []
	for filename: String in ["f4u_corsair_250", "p51d_mustang_120", "sebart_avanti_s_a200"]:
		var info := AD.load_file("res://data/aircraft/" + filename + ".json")
		_check(filename + " complete stock data admission", info.ok)
		admissions.append({"aircraft":filename, "ok":info.ok, "errors":Array(info.errors),
			"input_identity":info.get("input_identity", {})})
		if not info.ok:
			continue
		var model: Dictionary = info.model
		_check(filename + " flap witness within authored travel", float(model.flaps.max_angle_deg) >= 10.0)
		for speed: float in [10.0,20.0,30.0]:
			records.append(_case(filename, model, speed, 0.0, 10.0, false))
		records.append(_case(filename, model, 20.0, 0.0, 0.0, false))
		records.append(_case(filename, model, 20.0, 0.0, 0.0001, false))
		records.append(_case(filename, model, 20.0, 30.0, 10.0, false))
		records.append(_case(filename, model, 20.0, 0.0, 10.0, true))
		records.append(_case(filename, model, 20.0, 6.0, 10.0, false))
	print("R6_FLAP_JSON ", JSON.stringify({"admissions":admissions, "cases":records,
		"checks":checks, "failures":failures, "scope":"stock-data component and shared Dynamics loads; no session flight or physical calibration"}))
	print("R6 flap wake witness: %d failures" % failures)
	quit(1 if failures else 0)
