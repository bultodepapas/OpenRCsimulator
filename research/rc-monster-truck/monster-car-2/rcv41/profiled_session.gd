## Source-only attribution wrapper. Production equations and callbacks are unchanged.
extends "res://sim/ground_vehicle/session.gd"

var profiling := false
var costs := {"identity_guard": [], "integration": [], "telemetry": [], "state_validation": [],
	"telemetry_validation": [], "road_sampling": []}


func wrap_road() -> void:
	var original := _road
	_road = func(north: float, east: float) -> Dictionary:
		var start := Time.get_ticks_usec()
		var result: Dictionary = original.call(north, east)
		if profiling: costs.road_sampling.append(Time.get_ticks_usec() - start)
		return result


func _active_backend_matches_prepared() -> bool:
	var start := Time.get_ticks_usec()
	var result := super._active_backend_matches_prepared()
	if profiling: costs.identity_guard.append(Time.get_ticks_usec() - start)
	return result


func _step_model(state_value: PackedFloat64Array, model: Dictionary, controls: Dictionary,
		dt: float, road: Callable) -> PackedFloat64Array:
	var start := Time.get_ticks_usec()
	var result := super._step_model(state_value, model, controls, dt, road)
	if profiling: costs.integration.append(Time.get_ticks_usec() - start)
	return result


func _telemetry_for_model(state_value: PackedFloat64Array, model: Dictionary, road: Callable,
		controls: Dictionary) -> Dictionary:
	var start := Time.get_ticks_usec()
	var result := super._telemetry_for_model(state_value, model, road, controls)
	if profiling: costs.telemetry.append(Time.get_ticks_usec() - start)
	return result


func _state_is_valid(value: Variant) -> bool:
	var start := Time.get_ticks_usec()
	var result := super._state_is_valid(value)
	if profiling: costs.state_validation.append(Time.get_ticks_usec() - start)
	return result


func _telemetry_is_valid(value: Variant) -> bool:
	var start := Time.get_ticks_usec()
	var result := super._telemetry_is_valid(value)
	if profiling: costs.telemetry_validation.append(Time.get_ticks_usec() - start)
	return result


func profile_summary() -> Dictionary:
	var result := {}
	for key in costs:
		var values: Array = costs[key]
		var total := 0
		for value in values: total += int(value)
		result[key] = {"calls": values.size(), "total_us": total,
			"mean_us_per_tick": float(total) / costs.integration.size()}
	return result
