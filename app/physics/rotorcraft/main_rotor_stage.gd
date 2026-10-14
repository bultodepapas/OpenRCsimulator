# HELI-05a: pure joint main-rotor loads and dimensional inflow/flap derivatives.
# Shaft speed is provided by the future drive owner. No tail/airframe/gyro model.
extends RefCounted

const Rotor = preload("res://physics/rotorcraft/main_rotor.gd")
const Inflow = preload("res://physics/rotorcraft/dynamic_inflow.gd")
const M = preload("res://physics/math3d.gd")
const STATE_LAYOUT: Array = ["a1_rad", "b1_rad", "induced_velocity_mps"]


static func evaluate(model: Dictionary, state: PackedFloat64Array, omega: float,
		hub_air_velocity: PackedFloat64Array, body_rates: PackedFloat64Array,
		collective_75: float, cyclic_forward: float, cyclic_right: float, flow_floor: float,
		height_over_radius: float = -1.0, loss: float = 1.0, instability: float = 1.0,
		diagnostics: bool = false, thrust_axis_downworld_scalar: float = NAN) -> Dictionary:
	return _evaluate(model, state, omega, hub_air_velocity, body_rates, collective_75,
		cyclic_forward, cyclic_right, flow_floor, height_over_radius, loss, instability,
		diagnostics, false, thrust_axis_downworld_scalar)


# Internal joint-stage entry. Its caller already validated the frozen component
# models once when it created the aerodynamic performance context.
static func _evaluate_prepared(model: Dictionary, state: PackedFloat64Array, omega: float,
		hub_air_velocity: PackedFloat64Array, body_rates: PackedFloat64Array,
		collective_75: float, cyclic_forward: float, cyclic_right: float, flow_floor: float,
		height_over_radius: float = -1.0, loss: float = 1.0, instability: float = 1.0,
		diagnostics: bool = false, thrust_axis_downworld_scalar: float = NAN) -> Dictionary:
	return _evaluate(model, state, omega, hub_air_velocity, body_rates, collective_75,
		cyclic_forward, cyclic_right, flow_floor, height_over_radius, loss, instability,
		diagnostics, true, thrust_axis_downworld_scalar)


static func _evaluate(model: Dictionary, state: PackedFloat64Array, omega: float,
		hub_air_velocity: PackedFloat64Array, body_rates: PackedFloat64Array,
		collective_75: float, cyclic_forward: float, cyclic_right: float, flow_floor: float,
		height_over_radius: float, loss: float, instability: float, diagnostics: bool,
		prepared: bool, thrust_axis_downworld_scalar: float) -> Dictionary:
	var parts: Array = _evaluate_parts(model, state, omega, hub_air_velocity, body_rates,
		collective_75, cyclic_forward, cyclic_right, flow_floor, height_over_radius,
		loss, instability, diagnostics, prepared, thrust_axis_downworld_scalar)
	if parts.size() != 3:
		return {"ok": false}
	var rotor: Dictionary = parts[0]
	var flow: Dictionary = parts[1]
	var derivative: PackedFloat64Array = parts[2]
	return {"ok": true, "loads": rotor.loads, "derivative": derivative,
		"rotor": rotor, "inflow": flow}


# The aerodynamic owner consumes these parts directly and avoids constructing
# a short-lived stage Dictionary. The older public evaluate() shape is built by
# _evaluate() above from this same calculation path.
static func _evaluate_prepared_parts(model: Dictionary, state: PackedFloat64Array, omega: float,
		hub_air_velocity: PackedFloat64Array, body_rates: PackedFloat64Array,
		collective_75: float, cyclic_forward: float, cyclic_right: float, flow_floor: float,
		height_over_radius: float = -1.0, loss: float = 1.0, instability: float = 1.0,
		diagnostics: bool = false, thrust_axis_downworld_scalar: float = NAN) -> Array:
	return _evaluate_parts(model, state, omega, hub_air_velocity, body_rates, collective_75,
		cyclic_forward, cyclic_right, flow_floor, height_over_radius, loss, instability,
		diagnostics, true, thrust_axis_downworld_scalar)


static func _evaluate_parts(model: Dictionary, state: PackedFloat64Array, omega: float,
		hub_air_velocity: PackedFloat64Array, body_rates: PackedFloat64Array,
		collective_75: float, cyclic_forward: float, cyclic_right: float, flow_floor: float,
		height_over_radius: float, loss: float, instability: float, diagnostics: bool,
		prepared: bool, thrust_axis_downworld_scalar: float) -> Array:
	if state.size() != 3:
		return []
	var rotor: Dictionary = Rotor._evaluate_prepared(model, omega, state[2], hub_air_velocity, body_rates,
		collective_75, cyclic_forward, cyclic_right, state[0], state[1], diagnostics) if prepared else Rotor.evaluate(
		model, omega, state[2], hub_air_velocity, body_rates, collective_75, cyclic_forward, cyclic_right,
		state[0], state[1], diagnostics)
	if not rotor.ok:
		return []
	var inflow_height_over_radius: float = height_over_radius
	if not is_nan(thrust_axis_downworld_scalar):
		if not is_finite(thrust_axis_downworld_scalar) or absf(thrust_axis_downworld_scalar) > 1.0 + 1.0e-10:
			return []
		# The positive-thrust normal is the disc normal. Its opposite points
		# downstream. Apply terrain influence only if that downstream direction
		# has a positive NED-down component toward the ground plane.
		if rotor.thrust_n * thrust_axis_downworld_scalar >= 0.0:
			inflow_height_over_radius = -1.0
	# Match the paper's shaft/body-frame inflow approximation. Projecting this
	# flow into the exact tilted TPP would be a separately qualified extension.
	var crossflow: float = M.sqrt_(hub_air_velocity[0] * hub_air_velocity[0] + hub_air_velocity[1] * hub_air_velocity[1])
	var flow: Dictionary = Inflow.evaluate(state[2], rotor.thrust_n, model.rho_kg_m3, model.rotor_radius_m,
		-hub_air_velocity[2], crossflow, flow_floor, inflow_height_over_radius, loss, instability)
	if not flow.ok:
		return []
	return [rotor, flow, PackedFloat64Array([rotor.flap_rate_a1_rad_s, rotor.flap_rate_b1_rad_s, flow.rate])]
