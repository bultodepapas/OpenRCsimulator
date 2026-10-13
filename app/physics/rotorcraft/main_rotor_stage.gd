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
		diagnostics: bool = false) -> Dictionary:
	if state.size() != 3:
		return {"ok": false}
	var rotor: Dictionary = Rotor.evaluate(model, omega, state[2], hub_air_velocity, body_rates,
		collective_75, cyclic_forward, cyclic_right, state[0], state[1], diagnostics)
	if not rotor.ok:
		return rotor
	# Match the paper's shaft/body-frame inflow approximation. Projecting this
	# flow into the exact tilted TPP would be a separately qualified extension.
	var crossflow: float = M.sqrt_(hub_air_velocity[0] * hub_air_velocity[0] + hub_air_velocity[1] * hub_air_velocity[1])
	var flow: Dictionary = Inflow.evaluate(state[2], rotor.thrust_n, model.rho_kg_m3, model.rotor_radius_m,
		-hub_air_velocity[2], crossflow, flow_floor, height_over_radius, loss, instability)
	if not flow.ok:
		return flow
	return {"ok": true, "loads": rotor.loads,
		"derivative": PackedFloat64Array([rotor.flap_rate_a1_rad_s, rotor.flap_rate_b1_rad_s, flow.rate]),
		"rotor": rotor, "inflow": flow}
