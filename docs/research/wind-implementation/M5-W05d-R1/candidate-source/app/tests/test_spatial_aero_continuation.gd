extends SceneTree

const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const AD := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")

const RHO := Air.RHO_SEA_LEVEL
const STIK := "jensen-das-ugly-stik-60"
const POLAR_AIRCRAFT := "gp-extra-300s-60"
var ZERO := PackedFloat64Array([0.0, 0.0, 0.0])

var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s%s" % [label, " — " + detail if not detail.is_empty() else ""])


func _initialize() -> void:
	var model := _station_model(STIK)
	_check("normalized Stik model is available", not model.is_empty())
	if model.is_empty():
		print("Spatial aero continuation: %d checks, %d failed" % [_checks, _failures])
		quit(1)
		return
	_check_uniform_parity(model)
	_check_stall_oracle_and_continuity(model)
	_check_reversal_and_zero_speed(model)
	_check_polar_full_angle()
	_check_malformed_bounds(model)
	print("Spatial aero continuation: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _load_model(aircraft_id: String) -> Dictionary:
	var path: String = Catalog.data_for(aircraft_id, "ideal")
	if path.is_empty():
		return {}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not raw is Dictionary:
		return {}
	var loaded: Dictionary = AD.validate_and_derive(raw)
	return loaded.model if loaded.get("ok", false) else {}


func _station_model(aircraft_id: String) -> Dictionary:
	var source := _load_model(aircraft_id)
	if source.is_empty():
		return {}
	var model: Dictionary = source.duplicate(true)
	var ys: PackedFloat64Array = model.envelope.station_ys.duplicate()
	var n: int = ys.size()
	for i in range(int(n / 2)):
		var mirror: int = n - 1 - i
		var magnitude := 0.5 * (absf(ys[i]) + absf(ys[mirror]))
		ys[i] = -magnitude
		ys[mirror] = magnitude
	if n % 2 == 1:
		ys[int(n / 2)] = 0.0
	model.envelope.station_ys = ys
	model.cg_le = model.reference.arp_le.duplicate()
	model.aero.CL0 = 0.0
	model.aero.CLa = 4.0
	model.aero.CD0 = 0.02
	model.aero.k_induced = 0.0
	model.aero.CL_minD = 0.0
	for key: String in ["induced_map", "strip_slope", "strip_cl0", "wing_polar"]:
		model.envelope.erase(key)
	for key: String in ["station_incidence", "wing_cm_ac", "body_cn_beta", "body_cy_beta",
			"body_crossflow_area", "wing_body_cl_beta"]:
		model.surfaces.erase(key)
	model.erase("flaps")
	return model


func _check_uniform_parity(model: Dictionary) -> void:
	var stalled_alpha: float = minf(float(model.envelope.a2) + deg_to_rad(1.0), deg_to_rad(80.0))
	var cases: Array[PackedFloat64Array] = [
		M.v3(20.0, 0.0, 0.0),
		M.v3(20.0 * cos(stalled_alpha), 0.0, 20.0 * sin(stalled_alpha)),
		M.v3(-18.0, 0.0, 0.0),
		M.v3(0.0, 0.0, 0.0),
	]
	for case_index in cases.size():
		var state := _state(cases[case_index])
		var air: Dictionary = Air.compute(state, ZERO, RHO)
		var zero_delta := _zero_delta(model)
		var result: Dictionary = Aero.ambient_spatial_continuation_loads(state, air, _neutral(), model,
			RHO, zero_delta, NAN, NAN)
		_check("uniform regime %d is accepted" % case_index, result.get("ok", false), str(result.get("errors", [])))
		if not result.get("ok", false):
			continue
		var legacy: PackedFloat64Array = Aero.loads(state, air, _neutral(), model, RHO, NAN, NAN)
		_check("uniform regime %d keeps exact legacy bytes" % case_index,
			result.loads.to_byte_array() == legacy.to_byte_array())
		_check("uniform regime %d has exact zero delta" % case_index,
			result.delta.to_byte_array() == PackedFloat64Array([0., 0., 0., 0., 0., 0.]).to_byte_array())
		_check("uniform regime %d reports continuation identity" % case_index,
			result.law == Aero.SPATIAL_CONTINUATION_LAW)
	var small_state := _state(M.v3(20.0, 0.0, 0.0))
	var small_air: Dictionary = Air.compute(small_state, ZERO, RHO)
	var small_delta := _zero_delta(model)
	small_delta[2] = 1e-8
	var small_result: Dictionary = Aero.ambient_spatial_continuation_loads(small_state, small_air,
		_neutral(), model, RHO, small_delta, 0.0, NAN)
	_check("a vanishing nonzero field approaches the exact legacy limit", small_result.get("ok", false),
		str(small_result.get("errors", [])))
	if small_result.get("ok", false):
		var legacy: PackedFloat64Array = Aero.loads(small_state, small_air, _neutral(), model, RHO, 0.0, NAN)
		_check("near-uniform continuation does not jump at the exact-zero fast path",
			_vectors_near(small_result.loads, legacy, 1e-7) and absf(small_result.delta[2]) < 1e-7,
			"%s != %s" % [small_result.loads, legacy])


func _check_stall_oracle_and_continuity(model: Dictionary) -> void:
	var a1: float = model.envelope.a1
	var a2: float = model.envelope.a2
	var alpha_reference := a1 - deg_to_rad(3.0)
	var state := _state(_velocity_at(alpha_reference, 0.0))
	var air: Dictionary = Air.compute(state, ZERO, RHO)
	var ys: PackedFloat64Array = model.envelope.station_ys
	var station := _outer_right_station(ys)
	var targets: Array[float] = [a1 - 1e-4, a1, a1 + 1e-4, 0.5 * (a1 + a2), a2 - 1e-4, a2, a2 + 1e-4]
	for target: float in targets:
		var delta := _zero_delta(model)
		delta[3 * station + 2] = air.v_air[0] * tan(target) - air.v_air[2]
		var result: Dictionary = Aero.ambient_spatial_continuation_loads(state, air, _neutral(), model,
			RHO, delta, 0.0, NAN)
		_check("one-station target " + str(target) + " rad is accepted", result.get("ok", false), str(result.get("errors", [])))
		if not result.get("ok", false):
			continue
		var expected := _independent_one_station_delta(air, target, model, station, RHO)
		_check("one-station target " + str(target) + " matches independent section oracle",
			_vectors_near(result.delta, expected, 2e-8), "%s != %s" % [result.delta, expected])
	var blend_alpha: float = float(model.surfaces.attached_limit) \
		+ 0.2 * (float(model.envelope.a1) - float(model.surfaces.attached_limit))
	var blend_state := _state(_velocity_at(blend_alpha, 0.0))
	var blend_air: Dictionary = Air.compute(blend_state, ZERO, RHO)
	var blend_weight: float = Aero.local_flow_weight(blend_state, blend_air, _neutral(), model, 0.0)
	var blend_delta := _zero_delta(model)
	blend_delta[3 * station + 2] = 0.05
	var blend_result: Dictionary = Aero.ambient_spatial_continuation_loads(blend_state, blend_air,
		_neutral(), model, RHO, blend_delta, 0.0, NAN)
	var blend_target := atan2(blend_air.v_air[2] + 0.05, blend_air.v_air[0])
	var blend_expected := _independent_one_station_delta(blend_air, blend_target, model, station, RHO)
	_check("partial global/local selector fixture is active", blend_weight > 0.0 and blend_weight < 1.0,
		str(blend_weight))
	_check("spatial section differential remains unweighted in the partial blend",
		blend_result.get("ok", false) and _vectors_near(blend_result.delta, blend_expected, 2e-8),
		str(blend_result.get("errors", [])))
	var midpoint := 0.5 * (a1 + a2)
	var midpoint_delta := _delta_for_target(air, model, station, midpoint)
	var midpoint_result: Dictionary = Aero.ambient_spatial_continuation_loads(state, air, _neutral(), model,
		RHO, midpoint_delta, 0.0, NAN)
	_check("one wing can be separated while reference stays attached",
		midpoint_result.get("ok", false) and midpoint_result.delta[3] != 0.0, str(midpoint_result.get("errors", [])))
	var fully_separated_target := a2 + deg_to_rad(1.0)
	var one_wing_delta := _zero_delta(model)
	for i in ys.size():
		if ys[i] > 0.0:
			one_wing_delta[3 * i + 2] = air.v_air[0] * tan(fully_separated_target) - air.v_air[2]
	var one_wing_result: Dictionary = Aero.ambient_spatial_continuation_loads(state, air, _neutral(), model,
		RHO, one_wing_delta, 0.0, NAN)
	var one_wing_expected := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	for i in ys.size():
		if ys[i] > 0.0:
			var strip_expected := _independent_one_station_delta(air, fully_separated_target, model, i, RHO)
			for axis in 6:
				one_wing_expected[axis] += strip_expected[axis]
	_check("right wing can separate with left wing still attached",
		one_wing_result.get("ok", false) and _vectors_near(one_wing_result.delta, one_wing_expected, 2e-8),
		"%s != %s" % [one_wing_result.get("delta", PackedFloat64Array()), one_wing_expected])
	var v1_result: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), model, RHO,
		midpoint_delta, 0.0, NAN)
	_check("legacy v1 keeps refusing this separated spatial case",
		not v1_result.get("ok", false) and not v1_result.has("loads"), str(v1_result.get("errors", [])))
	for threshold: float in [a1, a2]:
		var h := 1e-5
		var below := _continuation_at_angle(state, air, model, station, threshold - h)
		var at := _continuation_at_angle(state, air, model, station, threshold)
		var above := _continuation_at_angle(state, air, model, station, threshold + h)
		_check("stall threshold " + str(threshold) + " samples are accepted",
			below.get("ok", false) and at.get("ok", false) and above.get("ok", false))
		if not below.get("ok", false) or not at.get("ok", false) or not above.get("ok", false):
			continue
		for axis in 6:
			var curvature := absf(below.delta[axis] - 2.0 * at.delta[axis] + above.delta[axis])
			_check("stall threshold " + str(threshold) + " has no finite-step jump on axis " + str(axis),
				curvature < 1e-4, "curvature " + str(curvature))


func _check_reversal_and_zero_speed(model: Dictionary) -> void:
	var ys: PackedFloat64Array = model.envelope.station_ys
	var station := _outer_right_station(ys)
	var zero_state := _state(M.v3(0.0, 0.0, 0.0))
	var zero_air: Dictionary = Air.compute(zero_state, ZERO, RHO)
	var reversal_samples: Array[PackedFloat64Array] = []
	for flow: PackedFloat64Array in [M.v3(8.0, 0.0, 3.0), M.v3(-1e-6, 0.0, 3.0),
			M.v3(0.0, 0.0, 3.0), M.v3(1e-6, 0.0, 3.0), M.v3(-8.0, 0.0, 3.0)]:
		var delta := _zero_delta(model)
		delta[3 * station] = flow[0]
		delta[3 * station + 1] = flow[1]
		delta[3 * station + 2] = flow[2]
		var result: Dictionary = Aero.ambient_spatial_continuation_loads(zero_state, zero_air, _neutral(),
			model, RHO, delta, 0.0, NAN)
		_check("forward/edge/reversed flow %s is accepted" % str(flow), result.get("ok", false),
			str(result.get("errors", [])))
		if not result.get("ok", false):
			continue
		var expected := _independent_one_station_delta(zero_air, atan2(flow[2], flow[0]), model, station, RHO,
			flow[0], flow[2])
		_check("flow %s matches independent full-angle section oracle" % str(flow),
			_vectors_near(result.delta, expected, 2e-8), "%s != %s" % [result.delta, expected])
		var work: float = result.delta[0] * flow[0] + result.delta[2] * flow[2]
		_check("flow %s section force opposes its relative flow" % str(flow), work < 0.0,
			"flow work " + str(work))
		reversal_samples.append(result.delta)
	if reversal_samples.size() == 5:
		for axis in 6:
			var curvature := absf(reversal_samples[1][axis] - 2.0 * reversal_samples[2][axis]
				+ reversal_samples[3][axis])
			_check("local force crosses forward-flow reversal continuously on axis " + str(axis),
				curvature < 1e-8, "curvature " + str(curvature))
	var vertical_tail_index: int = ys.size() + 1
	var crosswind := _zero_delta(model)
	crosswind[3 * vertical_tail_index + 1] = 8.0
	var crosswind_result: Dictionary = Aero.ambient_spatial_continuation_loads(zero_state, zero_air,
		_neutral(), model, RHO, crosswind, 0.0, NAN)
	_check("standing pure crosswind has finite local fin response", crosswind_result.get("ok", false),
		str(crosswind_result.get("errors", [])))
	if crosswind_result.get("ok", false):
		_check("standing crosswind fin drag opposes flow", crosswind_result.delta[1] < 0.0,
			str(crosswind_result.delta))
		var tail: Dictionary = model.surfaces.vertical
		var expected_side_force: float = -0.5 * RHO * 8.0 * 8.0 * float(tail.area) \
			* (float(model.surfaces.tail_CD0) + float(model.surfaces.tail_CD90))
		_check("standing crosswind fin force matches independent edge-on drag oracle",
			absf(crosswind_result.delta[1] - expected_side_force) < 2e-8,
			"%s != %s" % [crosswind_result.delta[1], expected_side_force])
		_check("zero wing-plane speeds are reported, not divided by", 
			int(crosswind_result.flow.spatial_zero_plane_wing_stations) == ys.size())


func _check_polar_full_angle() -> void:
	var model := _load_model(POLAR_AIRCRAFT)
	_check("tabulated-polar model is available", not model.is_empty())
	if model.is_empty() or not model.envelope.has("wing_polar"):
		return
	model.envelope.wing_polar.strip_factor = PackedFloat64Array()
	var state := _state(M.v3(0.0, 0.0, 0.0))
	var air: Dictionary = Air.compute(state, ZERO, RHO)
	var ys: PackedFloat64Array = model.envelope.station_ys
	var station := _outer_right_station(ys)
	var delta := _zero_delta(model)
	delta[3 * station + 2] = 8.0
	var result: Dictionary = Aero.ambient_spatial_continuation_loads(state, air, _neutral(), model,
		RHO, delta, 0.0, NAN)
	_check("tabulated polar continues through 90-degree local flow", result.get("ok", false),
		str(result.get("errors", [])))
	if result.get("ok", false):
		_check("tabulated polar continuation stays finite and bounded",
			_spatial_loads_bounded(result.delta) and _spatial_loads_bounded(result.loads), str(result.delta))
		var expected_area: float = float(model.reference.S) / float(ys.size())
		var polar: Dictionary = model.envelope.wing_polar
		var expected_drag: float = -0.5 * RHO * 8.0 * 8.0 * expected_area \
			* (float(polar.cd0) + float(polar.cd90))
		_check("90-degree tabulated polar matches independent flat-plate drag endpoint",
			absf(result.delta[2] - expected_drag) < 2e-8, "%s != %s" % [result.delta[2], expected_drag])


func _check_malformed_bounds(model: Dictionary) -> void:
	var state := _state(M.v3(0.0, 0.0, 0.0))
	var air: Dictionary = Air.compute(state, ZERO, RHO)
	var zero_delta := _zero_delta(model)
	var wrong_shape := PackedFloat64Array([0.0, 0.0])
	_check_refused("wrong station shape", state, air, model, wrong_shape, RHO)
	var nan_delta := zero_delta.duplicate()
	nan_delta[0] = NAN
	_check_refused("NaN station delta", state, air, model, nan_delta, RHO)
	var huge_delta := zero_delta.duplicate()
	huge_delta[0] = 1001.0
	_check_refused("finite station delta beyond safety bound", state, air, model, huge_delta, RHO)
	_check_refused("density beyond safety bound", state, air, model, zero_delta, 1001.0)
	var huge_reference := model.duplicate(true)
	huge_reference.reference.S = 1e16
	var spatial := zero_delta.duplicate()
	spatial[0] = 10.0
	_check_refused("finite but unbounded resultant loads", state, air, huge_reference, spatial, RHO)


func _check_refused(label: String, state: PackedFloat64Array, air: Dictionary, model: Dictionary,
		station_delta: PackedFloat64Array, density: float) -> void:
	var result: Dictionary = Aero.ambient_spatial_continuation_loads(state, air, _neutral(), model,
		density, station_delta, 0.0, NAN)
	_check(label + " returns a refusal", not result.get("ok", false), str(result.get("errors", [])))
	_check(label + " returns no partial loads", not result.has("loads"))


func _continuation_at_angle(state: PackedFloat64Array, air: Dictionary, model: Dictionary,
		station: int, target: float) -> Dictionary:
	return Aero.ambient_spatial_continuation_loads(state, air, _neutral(), model, RHO,
		_delta_for_target(air, model, station, target), 0.0, NAN)


func _delta_for_target(air: Dictionary, model: Dictionary, station: int, target: float) -> PackedFloat64Array:
	var delta := _zero_delta(model)
	delta[3 * station + 2] = air.v_air[0] * tan(target) - air.v_air[2]
	return delta


func _independent_one_station_delta(air: Dictionary, target: float, model: Dictionary,
		station: int, rho: float, u_override := NAN, w_override := NAN) -> PackedFloat64Array:
	var u0: float = air.v_air[0]
	var w0: float = air.v_air[2]
	var u1: float = u0 if is_nan(u_override) else u_override
	var w1: float = u1 * tan(target) if is_nan(w_override) else w_override
	var area: float = float(model.reference.S) / float(model.envelope.station_ys.size())
	var reference_force := _independent_strip_force(u0, w0, model, area, rho)
	var spatial_force := _independent_strip_force(u1, w1, model, area, rho)
	var dx: float = spatial_force[0] - reference_force[0]
	var dz: float = spatial_force[1] - reference_force[1]
	var y: float = model.envelope.station_ys[station]
	return PackedFloat64Array([dx, 0.0, dz, y * dz, 0.0, -y * dx])


func _independent_strip_force(u: float, w: float, model: Dictionary, area: float, rho: float) -> PackedFloat64Array:
	var plane_speed := sqrt(u * u + w * w)
	if plane_speed == 0.0:
		return PackedFloat64Array([0.0, 0.0])
	var alpha := atan2(w, u)
	var weight := _independent_stall_weight(alpha, model.envelope)
	var base: float = float(model.aero.CL0) + float(model.aero.CLa) * alpha
	var flat_plate := 0.5 * float(model.envelope.CD90) * sin(2.0 * alpha)
	var cl: float = base if weight == 0.0 else (1.0 - weight) * base + weight * flat_plate
	var cd: float = float(model.aero.CD0) + (1.0 - weight) * float(model.aero.k_induced) \
		* pow(cl - float(model.aero.CL_minD), 2.0) + weight * float(model.envelope.CD90) * pow(sin(alpha), 2.0)
	var force_scale := -0.5 * rho * plane_speed * area * cd
	var fx := u * force_scale
	var fz := w * force_scale
	var lift := 0.5 * rho * plane_speed * plane_speed * area * cl
	fx += lift * w / plane_speed
	fz -= lift * u / plane_speed
	return PackedFloat64Array([fx, fz])


func _independent_stall_weight(alpha: float, envelope: Dictionary) -> float:
	var start: float = float(envelope.a1) if alpha >= 0.0 else float(envelope.n1)
	var finish: float = float(envelope.a2) if alpha >= 0.0 else float(envelope.n2)
	var t := clampf((absf(alpha) - start) / (finish - start), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _outer_right_station(ys: PackedFloat64Array) -> int:
	var result := -1
	var largest := 0.0
	for i in ys.size():
		if ys[i] > largest:
			largest = ys[i]
			result = i
	return result


func _zero_delta(model: Dictionary) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(3 * (model.envelope.station_ys.size() + 2))
	return result


func _neutral() -> Dictionary:
	return {"elevator": 0.0, "aileron_left": 0.0, "aileron_right": 0.0,
		"rudder": 0.0, "flap": 0.0}


func _state(velocity: PackedFloat64Array) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -10.0), velocity, M.q_identity(), M.v3(0.0, 0.0, 0.0))


func _velocity_at(alpha: float, beta: float, speed := 20.0) -> PackedFloat64Array:
	return M.v3(speed * cos(beta) * cos(alpha), speed * sin(beta), speed * cos(beta) * sin(alpha))


func _vectors_near(actual: PackedFloat64Array, expected: PackedFloat64Array, tolerance: float) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		if not is_finite(actual[i]) or not is_finite(expected[i]) \
				or absf(actual[i] - expected[i]) > tolerance:
			return false
	return true


func _spatial_loads_bounded(values: PackedFloat64Array) -> bool:
	if values.size() != 6:
		return false
	for value: float in values:
		if not is_finite(value) or absf(value) > 1e12:
			return false
	return true
