extends SceneTree

const Flight := preload("res://sim/flight_session.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")


class ThrottleCeilingFailure extends RefCounted:
	var effective_input_calls: int = 0
	var effective_throttle_calls: int = 0

	func prepare(_inputs: PackedFloat64Array, _servo: PackedFloat64Array, _airborne: bool) -> Dictionary:
		return {"ok": true}

	func effective_inputs(raw: PackedFloat64Array) -> PackedFloat64Array:
		effective_input_calls += 1
		var result: PackedFloat64Array = raw.duplicate()
		result[3] = minf(result[3], 0.5)
		return result

	func effective_throttle(raw: float) -> float:
		effective_throttle_calls += 1
		return minf(raw, 0.5)

	func propulsion_cut_active() -> bool:
		return false

	func servo_rate_factor(_axis: int) -> float:
		return 1.0

	func commit(_tick: int) -> bool:
		return false

	func rollback() -> void:
		pass


class StuckHighThrottleFailure extends RefCounted:
	func prepare(_inputs: PackedFloat64Array, _servo: PackedFloat64Array, _airborne: bool) -> Dictionary:
		return {"ok": true}

	func effective_inputs(raw: PackedFloat64Array) -> PackedFloat64Array:
		var result: PackedFloat64Array = raw.duplicate()
		result[3] = maxf(result[3], 0.8)
		return result

	func effective_throttle(raw: float) -> float:
		return maxf(raw, 0.8)

	func propulsion_cut_active() -> bool:
		return false

	func servo_rate_factor(_axis: int) -> float:
		return 1.0

	func commit(_tick: int) -> bool:
		return false

	func rollback() -> void:
		pass


var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_test_all_aircraft_power_routes()
	print("Failure power adapter: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: Variant = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s: %s" % [label, str(detail)])


func _new_flight(id: String) -> Node:
	var entry: Dictionary = Catalog.entry(id)
	var flight: Node = Flight.new()
	flight.setup(str(entry.get("data", "")), id)
	flight.input_enabled = false
	return flight


func _test_all_aircraft_power_routes() -> void:
	var ids: PackedStringArray = Catalog.airplane_flyable_ids()
	_check("the original fleet and additional aircraft are covered", ids.size() >= 7, ids)
	for id: String in ids:
		var healthy: Node = _new_flight(id)
		var limited: Node = _new_flight(id)
		_check(id + " healthy flight is valid", healthy.is_flyable())
		_check(id + " limited flight is valid", limited.is_flyable())
		if not healthy.is_flyable() or not limited.is_flyable():
			healthy.free()
			limited.free()
			continue
		var initial_fields: Array[String] = ["state", "aux", "continuous", "last_loads"]
		_check(id + " fixtures start with identical physical state", _fields_bytes(healthy.sim, initial_fields) == _fields_bytes(limited.sim, initial_fields))
		var healthy_inputs: PackedFloat64Array = healthy.sim.inputs.duplicate()
		healthy_inputs[3] = 0.5
		healthy.sim.inputs = healthy_inputs
		var limited_inputs: PackedFloat64Array = limited.sim.inputs.duplicate()
		limited_inputs[3] = 1.0
		limited.sim.inputs = limited_inputs
		var ceiling: ThrottleCeilingFailure = ThrottleCeilingFailure.new()
		limited._failures = ceiling
		_check(id + " retains full pilot input while reporting capped demand", limited.sim.inputs[3] == 1.0 and limited.propulsion_throttle() == 0.5)
		ceiling.effective_input_calls = 0
		ceiling.effective_throttle_calls = 0
		healthy.sim.step()
		limited.sim.step()
		_check(id + " healthy comparison step succeeds", healthy.sim.tick == 1 and healthy.sim.fault_reason.is_empty())
		_check(id + " limited comparison step succeeds", limited.sim.tick == 1 and limited.sim.fault_reason.is_empty())
		_check(id + " routes samples through the failure input adapter", ceiling.effective_input_calls > 0)
		_check(id + " preserves raw throttle after the accepted step", limited.sim.inputs[3] == 1.0)
		_check(id + " throttle-limited propulsion matches pilot demand 0.5", _fields_bytes(healthy.sim, initial_fields) == _fields_bytes(limited.sim, initial_fields))
		if limited.glow_is_active():
			_test_glow_cut_precedes_stuck_throttle(limited)
		healthy.free()
		limited.free()


func _test_glow_cut_precedes_stuck_throttle(flight: Node) -> void:
	var stuck := StuckHighThrottleFailure.new()
	flight._failures = stuck
	var inputs: PackedFloat64Array = flight.sim.inputs.duplicate()
	inputs[3] = 0.1
	flight.sim.inputs = inputs
	_check("glow fixture presents elevated stuck-throttle demand", flight.propulsion_throttle() == 0.8)
	var before: Dictionary = flight.glow_state()
	_check("glow cut accepts a live finite-fuel engine", before.get("ok", false) and flight.glow_cut())
	var cut_fuel: float = float(flight.glow_state().fuel_kg)
	flight.sim.step()
	var after: Dictionary = flight.glow_state()
	_check("glow cut step is accepted under elevated throttle", flight.sim.fault_reason.is_empty() and flight.sim.tick == 2)
	_check("finite engine cut stays latched ahead of stuck throttle", not after.running and str(after.stop_reason) == "cut" and not flight.engine_running)
	_check("stuck throttle cannot restart firing or burn fuel after cut", float(after.fuel_kg) == cut_fuel and float(after.chemical_power_w) == 0.0)


func _fields_bytes(sim: Object, fields: Array[String]) -> PackedByteArray:
	var values: Array = []
	for field: String in fields:
		values.append(sim.get(field))
	return var_to_bytes(values)
