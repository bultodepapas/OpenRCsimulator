extends SceneTree

const GroundStart := preload("res://physics/ground_start.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Surfaces := preload("res://physics/ground_surfaces.gd")
const Scenarios := preload("res://sim/scenarios.gd")
const WindFlow := preload("res://physics/wind_aircraft_flow.gd")
const RB := preload("res://physics/rigid_body.gd")

const G := 9.80665

var _failures := 0
var _checks := 0


class LinearWindEnvironment:
	extends RefCounted
	var samples: Array[Dictionary] = []
	var mean_east: float = -6.0

	func _init(east_component := -6.0) -> void:
		mean_east = east_component

	func wind_world(position_ned: PackedFloat64Array, time_s: float) -> PackedFloat64Array:
		if time_s != 0.0 or position_ned.size() != 3:
			return PackedFloat64Array()
		var n: float = position_ned[0]
		var e: float = position_ned[1]
		var height: float = -position_ned[2]
		var wind := wind_world_formula(position_ned)
		samples.append({"position": position_ned.duplicate(), "wind": wind.duplicate()})
		return wind

	func expected_wind(position_ned: PackedFloat64Array) -> PackedFloat64Array:
		return wind_world_formula(position_ned)

	func wind_world_formula(position_ned: PackedFloat64Array) -> PackedFloat64Array:
		var n: float = position_ned[0]
		var e: float = position_ned[1]
		var height: float = -position_ned[2]
		return PackedFloat64Array([
			0.15 + 0.00015 * n - 0.00007 * e + 0.0004 * height,
			mean_east + 0.00009 * n + 0.00011 * e,
			0.0002 * n - 0.0003 * e + 0.002 * height,
		])


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	print(("ok   " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  " + detail))
	if not ok:
		_failures += 1


func _hash_value(value: Variant) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes(value))
	return context.finish().hex_encode()


func _empty_result(result: Dictionary) -> bool:
	return result.state.is_empty() and result.anchors.is_empty() and result.rest_state.is_empty()


func _base_fixture() -> Dictionary:
	var model: Dictionary = AircraftData.load_file(Scenarios.AIRCRAFT).model
	var field: Dictionary = FieldLoader.load_from().field
	var surfaces: PackedFloat64Array = Surfaces.build(Surfaces.load_table().table, field).rects
	return {"model": model, "surfaces": surfaces, "d": {
		"elevator": 0.0, "aileron_left": 0.0, "aileron_right": 0.0, "rudder": 0.0}}


func _solve_with_linear_weather(fixture: Dictionary, heading: float) -> Dictionary:
	var environment := LinearWindEnvironment.new(-6.0 if heading > 0.0 else 6.0)
	var candidate_states: Array[PackedFloat64Array] = []
	var candidate_positions: Array[PackedFloat64Array] = []
	var candidate_winds: Array[PackedFloat64Array] = []
	var candidate_air_at_state: Callable = func(state: PackedFloat64Array, rho_kgm3: float) -> Dictionary:
		var first_query: int = environment.samples.size()
		candidate_states.append(state.duplicate())
		var receipt: Dictionary = WindFlow.stage_air(state, fixture.model, environment, 0.0, rho_kgm3)
		if environment.samples.size() > first_query:
			candidate_positions.append(environment.samples[first_query].position.duplicate())
			candidate_winds.append(environment.samples[first_query].wind.duplicate())
		return receipt
	var result: Dictionary = GroundStart.solve(fixture.model, fixture.surfaces, 15.0, -47.0, heading,
		fixture.d, 0.0, 2500.0, 1.225, G, PackedFloat64Array([0.0, 0.0, 0.0]), false, Callable(),
		candidate_air_at_state)
	return {"result": result, "environment": environment, "states": candidate_states,
		"positions": candidate_positions, "winds": candidate_winds}


func _has_distinct_candidate_positions(states: Array[PackedFloat64Array]) -> bool:
	if states.size() < 2:
		return false
	var first: PackedFloat64Array = states[0].slice(RB.POS, RB.POS + 3)
	for state: PackedFloat64Array in states:
		var position: PackedFloat64Array = state.slice(RB.POS, RB.POS + 3)
		if position != first:
			return true
	return false


func _initialize() -> void:
	var fixture := _base_fixture()
	var zero: Dictionary = GroundStart.solve(fixture.model, fixture.surfaces, 15.0, -47.0, PI / 2.0,
		fixture.d, 0.0, 2500.0, 1.225, G)
	_check("legacy zero-wind no-callback result retains pre-seam bytes",
		_hash_value(zero) == "f8762c8a62052540c78f396e96a18aae0cf246fa8da80e1c1ac12d6007fb35f9")
	var uniform: Dictionary = GroundStart.solve(fixture.model, fixture.surfaces, 15.0, -47.0, PI / 2.0,
		fixture.d, 0.0, 2500.0, 1.225, G, PackedFloat64Array([0.7, -1.25, 0.2]), false)
	_check("legacy uniform-wind no-callback result retains pre-seam bytes",
		_hash_value(uniform) == "79833b3dc04c2451f01c633dbcf6f745d5f7f50a853520f1a2c80aacff146ac9")

	for heading in [PI / 2.0, -PI / 2.0]:
		var run := _solve_with_linear_weather(fixture, heading)
		var result: Dictionary = run.result
		var suffix := "eastbound" if heading > 0.0 else "westbound"
		_check("linear field candidate Air solves " + suffix + " runway", result.ok, str(result.get("message", "")))
		if result.ok:
			_check("candidate Air is sampled at changing " + suffix + " poses",
				_has_distinct_candidate_positions(run.states))
			_check("candidate solver records stage-air sampling " + suffix,
				int(result.diagnostics.candidate_air.queries) == run.states.size() and run.states.size() > 2)
			var samples_match: bool = run.positions.size() == run.winds.size() and run.positions.size() > 2
			for index in run.positions.size():
				samples_match = samples_match and run.winds[index] == run.environment.expected_wind(run.positions[index])
			_check("linear world wind matches each sampled candidate position " + suffix, samples_match)
			_check("stage Air samples its aerodynamic and propulsion stations " + suffix,
				run.environment.samples.size() > run.states.size())

	var reject_query: Callable = func(_state: PackedFloat64Array, _rho_kgm3: float) -> Dictionary:
		return {"ok": false, "errors": PackedStringArray(["synthetic candidate refusal"])}
	var refused: Dictionary = GroundStart.solve(fixture.model, fixture.surfaces, 15.0, -47.0, PI / 2.0,
		fixture.d, 0.0, 2500.0, 1.225, G, PackedFloat64Array([12.0, 0.0, 0.0]), false, Callable(), reject_query)
	_check("bad candidate query refuses instead of using uniform wind",
		not refused.ok and _empty_result(refused) and refused.message.contains("candidate_air_at_state rejected")
			and refused.message.contains("synthetic candidate refusal"))

	var invalid_environment := LinearWindEnvironment.new()
	var missing_v_air: Callable = func(state: PackedFloat64Array, rho_kgm3: float) -> Dictionary:
		var receipt: Dictionary = WindFlow.stage_air(state, fixture.model, invalid_environment, 0.0, rho_kgm3)
		if receipt.ok:
			var air: Dictionary = receipt.air
			air.erase("v_air")
			receipt["air"] = air
		return receipt
	var malformed_air: Dictionary = GroundStart.solve(fixture.model, fixture.surfaces, 15.0, -47.0, PI / 2.0,
		fixture.d, 0.0, 2500.0, 1.225, G, PackedFloat64Array([0.0, 0.0, 0.0]), false, Callable(), missing_v_air)
	_check("missing Air.v_air refuses without publishing a state",
		not malformed_air.ok and _empty_result(malformed_air) and malformed_air.message.contains("air.v_air"),
		str(malformed_air.get("message", "")))

	invalid_environment = LinearWindEnvironment.new()
	var nonfinite_qbar: Callable = func(state: PackedFloat64Array, rho_kgm3: float) -> Dictionary:
		var receipt: Dictionary = WindFlow.stage_air(state, fixture.model, invalid_environment, 0.0, rho_kgm3)
		if receipt.ok:
			var air: Dictionary = receipt.air
			air["qbar"] = NAN
			receipt["air"] = air
		return receipt
	var malformed_qbar: Dictionary = GroundStart.solve(fixture.model, fixture.surfaces, 15.0, -47.0, PI / 2.0,
		fixture.d, 0.0, 2500.0, 1.225, G, PackedFloat64Array([0.0, 0.0, 0.0]), false, Callable(), nonfinite_qbar)
	_check("nonfinite Air.qbar refuses without publishing a state",
		not malformed_qbar.ok and _empty_result(malformed_qbar) and malformed_qbar.message.contains("air.qbar"),
		str(malformed_qbar.get("message", "")))

	print("M5-W05c-R2 spatial runway start: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
