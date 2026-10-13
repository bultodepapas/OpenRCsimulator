# HELI-04-R1: dimensional signed induced-velocity state (m/s).
# This is a chosen first-order lag, not a validated transient VRS model.
# It preserves the literal Johnson equilibrium law, including its C/M seams.
extends RefCounted

const M = preload("res://physics/math3d.gd")
const Equilibrium = preload("res://physics/rotorcraft/inflow.gd")
const LAW: String = "openrc-dimensional-inflow-lag-v1"
const DISC_MASS: float = 0.849


# radius in metres, effective flow and its explicit floor in m/s.
# Using dimensional velocity removes division by shaft speed at stop/spool-up.
static func derivative(velocity: float, target_velocity: float, radius: float,
		effective_flow: float, flow_floor: float) -> Dictionary:
	if not _finite([velocity, target_velocity, radius, effective_flow, flow_floor]) \
		or radius <= 0.0 or effective_flow < 0.0 or flow_floor <= 0.0:
		return {"ok": false}
	var tau: float = (DISC_MASS / 4.0) * radius / maxf(effective_flow, flow_floor)
	if not is_finite(tau) or tau <= 0.0:
		return {"ok": false}
	var rate: float = (target_velocity - velocity) / tau
	if not is_finite(rate):
		return {"ok": false}
	return {"ok": true, "rate": rate, "tau": tau}


# vi is positive downstream for positive reference thrust; climb is positive
# along the reference thrust axis. Under reflection both vi and climb reverse.
# A nonnegative height declares that the actual downstream wake meets terrain.
static func evaluate(velocity: float, thrust: float, density: float, radius: float,
		climb: float, crossflow: float, flow_floor: float, height_over_radius: float = -1.0,
		loss: float = 1.0, instability: float = 1.0) -> Dictionary:
	if not is_finite(velocity) or not is_finite(flow_floor) or flow_floor <= 0.0:
		return {"ok": false}
	var equilibrium: Dictionary = Equilibrium.target(thrust, density, radius, climb,
		crossflow, height_over_radius, loss, instability)
	if not equilibrium.ok:
		return equilibrium
	var axial_flow: float = velocity + climb
	var effective_flow: float = M.sqrt_(crossflow * crossflow + axial_flow * axial_flow)
	var response: Dictionary = derivative(velocity, equilibrium.velocity, radius, effective_flow, flow_floor)
	if not response.ok:
		return response
	return {"ok": true, "rate": response.rate, "tau": response.tau,
		"target": equilibrium.velocity, "effective_flow": effective_flow,
		"hover": equilibrium.hover, "ground_factor": equilibrium.ground_factor}


static func _finite(values: Array) -> bool:
	for value: float in values:
		if not is_finite(value):
			return false
	return true
