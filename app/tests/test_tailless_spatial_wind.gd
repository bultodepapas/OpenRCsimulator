extends SceneTree
## M5-W05d-R3: swept tailless station flow and ambient spatial loads.

const AD := preload("res://physics/aircraft_data.gd")
const Aero := preload("res://physics/aero.gd")
const Air := preload("res://physics/air_data.gd")
const Flow := preload("res://physics/wind_aircraft_flow.gd")
const M := preload("res://physics/math3d.gd")
const RB := preload("res://physics/rigid_body.gd")
const SimEnvironment := preload("res://sim/environment.gd")

const X8_PATHS := [
	"res://data/aircraft/skywalker_x8.json",
	"res://data/aircraft/battery/skywalker_x8_6s_pack.json",
]
const RHO: float = Air.RHO_SEA_LEVEL
const WING_STATIONS := 6
const HORIZONTAL_SLOT := 6
const FIN_SLOT := 7
const HUB_SLOT := 8


class CountingWeather extends "res://physics/wind_field.gd":
	var mode := "linear"
	var uniform_wind := PackedFloat64Array([2.5, -1.25, 0.75])
	var calls := 0
	var positions: Array[PackedFloat64Array] = []
	var times: Array[float] = []

	func sample_world(position_ned: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		calls += 1
		positions.append(position_ned.duplicate())
		times.append(time_s)
		if mode == "uniform":
			return uniform_wind.duplicate()
		return PackedFloat64Array([
			0.2 + 0.008 * position_ned[0] - 0.003 * position_ned[1] + 0.001 * time_s,
			-0.1 + 0.002 * position_ned[0] + 0.004 * position_ned[1] - 0.001 * time_s,
			0.05 - 0.006 * position_ned[2] + 0.002 * position_ned[0] + 0.001 * time_s,
		])


var _checks := 0
var _failures := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s%s" % [label, " — " + detail if not detail.is_empty() else ""])


func _near(actual: float, expected: float, tolerance := 1.0e-10) -> bool:
	return is_finite(actual) and absf(actual - expected) <= tolerance


func _same(actual: PackedFloat64Array, expected: PackedFloat64Array) -> bool:
	return actual.to_byte_array() == expected.to_byte_array()


func _near_array(actual: PackedFloat64Array, expected: PackedFloat64Array,
		tolerance := 1.0e-10) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		if not _near(actual[i], expected[i], tolerance):
			return false
	return true


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for path_value: Variant in X8_PATHS:
		var path: String = path_value
		var loaded: Dictionary = AD.load_file(path)
		_check("normalized X8 variant loads: %s" % path, loaded.get("ok", false),
			str(loaded.get("errors", PackedStringArray())))
		if not loaded.get("ok", false):
			continue
		var model: Dictionary = loaded.model
		var snapshot: String = JSON.stringify(model)
		_geometry_contract(model, path)
		_uniform_load_parity(model, path)
		if path == X8_PATHS[0]:
			_stage_flow_and_narrow_domain(model)
			_spatial_load_signs_and_fin(model)
			_fail_closed_layouts(model)
		_check("geometry and aero calls do not mutate the normalized model: %s" % path,
			JSON.stringify(model) == snapshot)
	print("tailless spatial wind: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _geometry_contract(model: Dictionary, label: String) -> void:
	var capabilities: Dictionary = model.get("capabilities", {})
	var controls: Dictionary = model.get("controls", {})
	var surfaces: Dictionary = model.get("surfaces", {})
	var tailless: Dictionary = surfaces.get("tailless", {})
	var station_x: Variant = tailless.get("station_x", null)
	_check("%s declares the tailless elevon model" % label,
		capabilities.get("airframe_layout", "") == "tailless"
			and capabilities.get("controls", "") == "elevon"
			and controls.get("layout", "") == "elevon")
	_check("%s has six finite derived swept station x coordinates" % label,
		station_x is PackedFloat64Array and station_x.size() == WING_STATIONS
			and _all_finite(station_x))
	if not station_x is PackedFloat64Array or station_x.size() != WING_STATIONS \
			or not _all_finite(station_x):
		return

	var built: Dictionary = Flow.geometry(model)
	_check("%s swept geometry succeeds" % label, built.get("ok", false), str(built.get("errors", [])))
	if not built.get("ok", false):
		return
	_check("%s keeps six wings, inactive H slot, fin 7, and hub 8" % label,
		built.wing_count == WING_STATIONS and built.horizontal_index == -1
			and built.vertical_index == FIN_SLOT and built.propulsion_index == HUB_SLOT)
	var offsets: PackedFloat64Array = built.offsets_body
	_check("%s preserves the 27-float station and hub coverage" % label, offsets.size() == 27)
	if offsets.size() != 27:
		return
	_check("%s reserves the inactive horizontal slot at the datum" % label,
		_same(offsets.slice(HORIZONTAL_SLOT * 3, HORIZONTAL_SLOT * 3 + 3), _zero3()))
	_check("%s uses swept FRD wing arms and unchanged fin and hub arms" % label,
		_near_array(offsets, _expected_offsets(model)), str(offsets))


func _expected_offsets(model: Dictionary) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	var cg: PackedFloat64Array = model.cg_le
	var arp: PackedFloat64Array = model.reference.arp_le
	var ys: PackedFloat64Array = model.envelope.station_ys
	var station_x: PackedFloat64Array = model.surfaces.tailless.station_x
	for i in WING_STATIONS:
		result.append(-(station_x[i] - cg[0]) + 0.0)
		result.append(arp[1] - cg[1] + ys[i])
		result.append(-(arp[2] - cg[2]) + 0.0)
	result.append_array(_zero3())
	var fin: PackedFloat64Array = model.surfaces.vertical.position
	result.append(-(fin[0] - cg[0]))
	result.append(fin[1] - cg[1])
	result.append(-(fin[2] - cg[2]))
	var propulsion: Dictionary = model.propulsion
	var point: PackedFloat64Array = propulsion.intake_offset if propulsion.get("kind", "") == "turbine" \
		else propulsion.offset
	result.append(-point[0])
	result.append(point[1])
	result.append(-point[2])
	return result


func _stage_flow_and_narrow_domain(model: Dictionary) -> void:
	var weather := CountingWeather.new()
	var environment: Variant = _environment(weather)
	var yaw := 0.41
	var pitch := -0.23
	var roll := 0.31
	var time_s := 2.25
	var position := PackedFloat64Array([121.0, -17.5, -4.25])
	var velocity := PackedFloat64Array([18.0, -1.5, 0.75])
	var omega := PackedFloat64Array([0.10, -0.20, 0.15])
	var state := RB.make_state(position, velocity, M.q_from_euler(yaw, pitch, roll), omega)
	var state_bytes: PackedByteArray = state.to_byte_array()
	var stage: Dictionary = Flow.stage_air(state, model, environment, time_s, RHO,
		Aero.SPATIAL_CONTINUATION_LAW)
	_check("swept X8 stage air succeeds", stage.get("ok", false), str(stage.get("errors", [])))
	if not stage.get("ok", false):
		return
	var flow: Dictionary = stage.flow
	var geometry: Dictionary = Flow.geometry(model)
	_check("datum plus eight active point queries sample the field exactly nine times",
		weather.calls == 9 and weather.positions.size() == 9 and weather.times.size() == 9,
		"calls=%d" % weather.calls)
	_check("the datum is queried first and all queries use the same stage time",
		_same(weather.positions[0], position) and weather.times.all(
			func(value: float) -> bool: return value == time_s))
	_check("stage flow retains 27-float coverage and marks the H slot inactive",
		flow.delta_body.size() == 27 and flow.horizontal_index == -1
			and _same(flow.delta_body.slice(HORIZONTAL_SLOT * 3, HORIZONTAL_SLOT * 3 + 3), _zero3()))
	_check("stage aero receipt retains 24 floats and exact zero H delta",
		stage.air.aero_station_delta_body.size() == 24
			and _same(stage.air.aero_station_delta_body, flow.delta_body.slice(0, 24))
			and _same(stage.air.aero_station_delta_body.slice(HORIZONTAL_SLOT * 3,
				HORIZONTAL_SLOT * 3 + 3), _zero3()))
	_check("stage sampling leaves the rigid-body state unchanged", state.to_byte_array() == state_bytes)
	if flow.delta_body.size() != 27 or flow.relative_body.size() != 27 or geometry.is_empty():
		return

	var reference_wind := _linear_wind(position, time_s)
	var wind_body := _inverse_rotation(yaw, pitch, roll, reference_wind)
	var reference_air := PackedFloat64Array([
		velocity[0] - wind_body[0], velocity[1] - wind_body[1], velocity[2] - wind_body[2],
	])
	_check("datum air subtraction uses the independent rotation matrix",
		_near_array(flow.reference_air_body, reference_air))
	var active_indices: Array[int] = [0, 1, 2, 3, 4, 5, FIN_SLOT, HUB_SLOT]
	var rate_arm_seen := false
	for query_index in active_indices.size():
		var station_index: int = active_indices[query_index]
		var arm: PackedFloat64Array = geometry.offsets_body.slice(station_index * 3,
			station_index * 3 + 3)
		var offset_ned := _rotate_euler(yaw, pitch, roll, arm)
		var point := PackedFloat64Array([
			position[0] + offset_ned[0], position[1] + offset_ned[1], position[2] + offset_ned[2],
		])
		var station_wind := _linear_wind(point, time_s)
		var delta_body := _inverse_rotation(yaw, pitch, roll, _subtract3(reference_wind, station_wind))
		var rate_delta := _cross(omega, arm)
		var local_air := reference_air.duplicate()
		for axis in 3:
			local_air[axis] += rate_delta[axis] + delta_body[axis]
		if absf(rate_delta[0]) + absf(rate_delta[1]) + absf(rate_delta[2]) > 1.0e-10:
			rate_arm_seen = true
		var provider_index: int = query_index + 1
		_check("active station %d is transformed to its swept world point" % station_index,
			_near_array(weather.positions[provider_index], point), str(weather.positions[provider_index]))
		_check("active station %d has the independent local wind delta" % station_index,
			_near_array(flow.delta_body.slice(station_index * 3, station_index * 3 + 3), delta_body))
		_check("active station %d adds omega cross swept arm exactly once" % station_index,
			_near_array(flow.relative_body.slice(station_index * 3, station_index * 3 + 3), local_air))
	_check("the fixture exercises nonzero omega cross swept arms", rate_arm_seen)
	_check("inactive H slot has no rate arm or ambient delta",
		_near_array(flow.relative_body.slice(HORIZONTAL_SLOT * 3, HORIZONTAL_SLOT * 3 + 3), reference_air)
			and _same(flow.delta_body.slice(HORIZONTAL_SLOT * 3, HORIZONTAL_SLOT * 3 + 3), _zero3()))

	var aero_result: Dictionary = Aero.ambient_spatial_loads(state, stage.air, _neutral(), model,
		RHO, stage.air.aero_station_delta_body, NAN, NAN)
	_check("attached ambient bridge accepts the modest swept gradient with nonzero body rates",
		aero_result.get("ok", false), str(aero_result.get("errors", [])))
	if aero_result.get("ok", false):
		_check("the accepted narrow-domain pass produces a finite spatial correction",
			_aero_finite(aero_result.get("delta", PackedFloat64Array()))
				and _has_nonzero(aero_result.delta), str(aero_result.get("delta", PackedFloat64Array())))


func _uniform_load_parity(model: Dictionary, label: String) -> void:
	var stalled_alpha: float = minf(float(model.envelope.a2) + deg_to_rad(1.0), deg_to_rad(80.0))
	var cases: Array[PackedFloat64Array] = [
		M.v3(20.0, 0.0, 0.0),
		M.v3(20.0 * cos(stalled_alpha), 0.0, 20.0 * sin(stalled_alpha)),
		M.v3(-18.0, 0.0, 0.0),
		M.v3(0.0, 0.0, 0.0),
	]
	var names: Array[String] = ["attached", "post-stall", "reverse", "zero-speed"]
	for case_index in cases.size():
		var state := _state(cases[case_index])
		var air: Dictionary = Air.compute(state, _zero3(), RHO)
		var zero_delta := _zero_station_delta()
		var legacy: PackedFloat64Array = Aero.loads(state, air, _neutral(), model, RHO, NAN, NAN)
		var narrow: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), model, RHO,
			zero_delta, NAN, NAN)
		var continuation: Dictionary = Aero.ambient_spatial_continuation_loads(state, air,
			_neutral(), model, RHO, zero_delta, NAN, NAN)
		var case_name: String = "%s %s" % [label, names[case_index]]
		_check("%s uniform narrow-domain aero is accepted" % case_name, narrow.get("ok", false),
			str(narrow.get("errors", [])))
		_check("%s uniform narrow-domain result preserves legacy load bytes" % case_name,
			narrow.get("ok", false) and _same(narrow.get("loads", PackedFloat64Array()), legacy))
		_check("%s uniform full-angle aero is accepted" % case_name,
			continuation.get("ok", false), str(continuation.get("errors", [])))
		_check("%s uniform full-angle result preserves legacy load bytes" % case_name,
			continuation.get("ok", false)
				and _same(continuation.get("loads", PackedFloat64Array()), legacy))
		if narrow.get("ok", false) and continuation.get("ok", false):
			_check("%s uniform APIs return exact zero wrench deltas" % case_name,
				_same(narrow.get("delta", PackedFloat64Array()), _zero6())
					and _same(continuation.get("delta", PackedFloat64Array()), _zero6()))


func _spatial_load_signs_and_fin(model: Dictionary) -> void:
	var state := _state(M.v3(20.0, 0.0, 0.0))
	var air: Dictionary = Air.compute(state, _zero3(), RHO)
	var right_gust := _zero_station_delta()
	var left_gust := _zero_station_delta()
	for station in 3:
		right_gust[3 * (station + 3) + 2] = 1.0
		left_gust[3 * station + 2] = 1.0
	var right_result: Dictionary = Aero.ambient_spatial_continuation_loads(state, air, _neutral(),
		model, RHO, right_gust, NAN, NAN)
	var left_result: Dictionary = Aero.ambient_spatial_continuation_loads(state, air, _neutral(),
		model, RHO, left_gust, NAN, NAN)
	_check("right-wing vertical gust evaluates through the full-angle aero law",
		right_result.get("ok", false), str(right_result.get("errors", [])))
	_check("left-wing vertical gust evaluates through the full-angle aero law",
		left_result.get("ok", false), str(left_result.get("errors", [])))
	if right_result.get("ok", false) and left_result.get("ok", false):
		_check("mirrored left and right vertical gusts produce opposite roll corrections",
			right_result.delta[3] < 0.0 and left_result.delta[3] > 0.0,
			"right=%s left=%s" % [right_result.delta[3], left_result.delta[3]])

	var fin_delta := _zero_station_delta()
	fin_delta[3 * FIN_SLOT + 1] = 0.5
	var fin_result: Dictionary = Aero.ambient_spatial_continuation_loads(state, air, _neutral(),
		model, RHO, fin_delta, NAN, NAN)
	_check("vertical-fin spatial delta evaluates through the tailless model",
		fin_result.get("ok", false), str(fin_result.get("errors", [])))
	if fin_result.get("ok", false):
		_check("vertical-fin sideflow changes the actual wrench",
			absf(fin_result.delta[1]) + absf(fin_result.delta[3]) + absf(fin_result.delta[5]) > 1.0e-10,
			str(fin_result.delta))

	var poisoned := _zero_station_delta()
	poisoned[3 * HORIZONTAL_SLOT] = 0.25
	var narrow_poison: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), model,
		RHO, poisoned, NAN, NAN)
	var continuation_poison: Dictionary = Aero.ambient_spatial_continuation_loads(state, air,
		_neutral(), model, RHO, poisoned, NAN, NAN)
	_check("narrow-domain aero refuses a nonzero inactive H delta without partial loads",
		not narrow_poison.get("ok", false) and not narrow_poison.has("loads"),
		str(narrow_poison.get("errors", [])))
	_check("full-angle aero refuses a nonzero inactive H delta without partial loads",
		not continuation_poison.get("ok", false) and not continuation_poison.has("loads"),
		str(continuation_poison.get("errors", [])))


func _fail_closed_layouts(model: Dictionary) -> void:
	var state := _state(M.v3(20.0, 0.0, 0.0))
	var air: Dictionary = Air.compute(state, _zero3(), RHO)
	var valid_zero := _zero_station_delta()
	var cases: Array[Dictionary] = []
	var bad_airframe: Dictionary = model.duplicate(true)
	bad_airframe.capabilities.airframe_layout = "conventional"
	cases.append({"name": "airframe capability mismatch", "model": bad_airframe})
	var bad_controls_capability: Dictionary = model.duplicate(true)
	bad_controls_capability.capabilities.controls = "conventional"
	cases.append({"name": "control capability mismatch", "model": bad_controls_capability})
	var bad_control_layout: Dictionary = model.duplicate(true)
	bad_control_layout.controls.layout = "conventional"
	cases.append({"name": "normalized control layout mismatch", "model": bad_control_layout})
	var short_station_x: Dictionary = model.duplicate(true)
	short_station_x.surfaces.tailless.station_x = PackedFloat64Array([0.0, 0.1])
	cases.append({"name": "wrong swept station count", "model": short_station_x})
	var nan_station_x: Dictionary = model.duplicate(true)
	nan_station_x.surfaces.tailless.station_x[2] = NAN
	cases.append({"name": "nonfinite swept station", "model": nan_station_x})
	var missing_fin: Dictionary = model.duplicate(true)
	missing_fin.surfaces.erase("vertical")
	cases.append({"name": "missing vertical surface", "model": missing_fin})
	var fake_tail: Dictionary = model.duplicate(true)
	fake_tail.surfaces.horizontal = fake_tail.surfaces.vertical.duplicate(true)
	cases.append({"name": "horizontal tail on tailless model", "model": fake_tail})
	for item: Dictionary in cases:
		var label: String = item.name
		var candidate: Dictionary = item.model
		var geometry: Dictionary = Flow.geometry(candidate)
		var narrow: Dictionary = Aero.ambient_spatial_loads(state, air, _neutral(), candidate,
			RHO, valid_zero, NAN, NAN)
		var continuation: Dictionary = Aero.ambient_spatial_continuation_loads(state, air,
			_neutral(), candidate, RHO, valid_zero, NAN, NAN)
		_check("%s fails closed in wind geometry" % label,
			not geometry.get("ok", false) and geometry.get("offsets_body", PackedFloat64Array()).is_empty(),
			str(geometry.get("errors", [])))
		_check("%s fails closed in narrow aero without partial loads" % label,
			not narrow.get("ok", false) and not narrow.has("loads"), str(narrow.get("errors", [])))
		_check("%s fails closed in full-angle aero without partial loads" % label,
			not continuation.get("ok", false) and not continuation.has("loads"),
			str(continuation.get("errors", [])))


func _environment(weather: CountingWeather) -> Variant:
	var environment := SimEnvironment.new()
	environment.weather = weather
	return environment


func _state(velocity: PackedFloat64Array) -> PackedFloat64Array:
	return RB.make_state(M.v3(0.0, 0.0, -10.0), velocity, M.q_identity(), M.v3(0.0, 0.0, 0.0))


func _neutral() -> Dictionary:
	return {"elevator": 0.0, "aileron_left": 0.0, "aileron_right": 0.0,
		"rudder": 0.0, "flap": 0.0}


func _zero3() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0])


func _zero6() -> PackedFloat64Array:
	return PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


func _zero_station_delta() -> PackedFloat64Array:
	var result := PackedFloat64Array()
	for i in (WING_STATIONS + 2) * 3:
		result.append(0.0)
	return result


func _all_finite(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true


func _aero_finite(values: PackedFloat64Array) -> bool:
	if values.size() != 6:
		return false
	return _all_finite(values)


func _has_nonzero(values: PackedFloat64Array) -> bool:
	for value: float in values:
		if value != 0.0:
			return true
	return false


func _linear_wind(position_ned: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
	return PackedFloat64Array([
		0.2 + 0.008 * position_ned[0] - 0.003 * position_ned[1] + 0.001 * time_s,
		-0.1 + 0.002 * position_ned[0] + 0.004 * position_ned[1] - 0.001 * time_s,
		0.05 - 0.006 * position_ned[2] + 0.002 * position_ned[0] + 0.001 * time_s,
	])


func _rotate_euler(yaw: float, pitch: float, roll: float, value: PackedFloat64Array) -> PackedFloat64Array:
	var cy := cos(yaw)
	var sy := sin(yaw)
	var cp := cos(pitch)
	var sp := sin(pitch)
	var cr := cos(roll)
	var sr := sin(roll)
	return PackedFloat64Array([
		(cy * cp) * value[0] + (cy * sp * sr - sy * cr) * value[1] + (cy * sp * cr + sy * sr) * value[2],
		(sy * cp) * value[0] + (sy * sp * sr + cy * cr) * value[1] + (sy * sp * cr - cy * sr) * value[2],
		-sp * value[0] + cp * sr * value[1] + cp * cr * value[2],
	])


func _inverse_rotation(yaw: float, pitch: float, roll: float,
		value: PackedFloat64Array) -> PackedFloat64Array:
	var cy := cos(yaw)
	var sy := sin(yaw)
	var cp := cos(pitch)
	var sp := sin(pitch)
	var cr := cos(roll)
	var sr := sin(roll)
	return PackedFloat64Array([
		(cy * cp) * value[0] + (sy * cp) * value[1] - sp * value[2],
		(cy * sp * sr - sy * cr) * value[0] + (sy * sp * sr + cy * cr) * value[1] + cp * sr * value[2],
		(cy * sp * cr + sy * sr) * value[0] + (sy * sp * cr - cy * sr) * value[1] + cp * cr * value[2],
	])


func _subtract3(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2]])


func _cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([
		a[1] * b[2] - a[2] * b[1],
		a[2] * b[0] - a[0] * b[2],
		a[0] * b[1] - a[1] * b[0],
	])
