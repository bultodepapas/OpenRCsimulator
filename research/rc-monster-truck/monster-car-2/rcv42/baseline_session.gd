extends "res://sim/ground_vehicle/session.gd"
const BeforeBody = preload("res://../research/rc-monster-truck/monster-car-2/rcv42/baseline_vehicle_dynamics.gd")
const BeforeNitro = preload("res://../research/rc-monster-truck/monster-car-2/rcv42/baseline_nitro_dynamics.gd")
func _step_model(state_value: PackedFloat64Array, model: Dictionary, controls: Dictionary,
		dt: float, road: Callable) -> PackedFloat64Array:
	return BeforeNitro.step(state_value, model, controls, dt, road) if _uses_nitro(model) else BeforeBody.step(state_value, model, controls, dt, road)
func _telemetry_for_model(state_value: PackedFloat64Array, model: Dictionary, road: Callable,
		controls: Dictionary) -> Dictionary:
	return BeforeNitro.telemetry(state_value, model, road, controls, DT) if _uses_nitro(model) else BeforeBody.telemetry(state_value, model, road, controls)
