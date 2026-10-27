# HELI-26a: reduced structural LOAD BENCH, not a flight/contact solver.
# Three independent modes: left/right skid compression and lateral canopy bending.
# m*q'' + c*q' + k*q = applied force. SI units; scalar float64 state only.
# These are declared estimates, not material identification or aircraft qualification.
# Geometry/provenance and coefficient rationale: HELI-26a/elasticity.md.
extends RefCounted

const M := preload("res://physics/math3d.gd")

const MASS_KG := [2.6, 2.6, 0.06]
const STIFFNESS_N_M := [6000.0, 6000.0, 800.0]
const DAMPING_NS_M := [80.0, 80.0, 2.5]
const FORCE_LIMIT_N := [51.0, 51.0, 2.0]
const TRAVEL_LIMIT_M := [0.020, 0.020, 0.008]
var displacement := PackedFloat64Array([0, 0, 0])
var velocity := PackedFloat64Array([0, 0, 0])
var force := PackedFloat64Array([0, 0, 0])
var dissipated_j := 0.0
var work_j := 0.0


func set_loads(loads: PackedFloat64Array) -> bool:
	if loads.size() != 3:
		return false
	for i in 3:
		if not is_finite(loads[i]) or absf(loads[i]) > FORCE_LIMIT_N[i] or (i < 2 and loads[i] < 0):
			return false
	force = loads.duplicate()
	return true


func energy_j() -> float:
	return _energy(displacement, velocity)


func _energy(q: PackedFloat64Array, v: PackedFloat64Array) -> float:
	var result := 0.0
	for i in 3:
		result += 0.5 * (MASS_KG[i] * v[i] * v[i] + STIFFNESS_N_M[i] * q[i] * q[i])
	return result


# Exact constant-force solution, including stalls; no frame-dependent integration.
# An out-of-domain candidate retains the complete accepted state. No travel clipping
# or velocity reset is allowed to masquerade as energy dissipation.
func advance(dt: float) -> bool:
	if not is_finite(dt) or dt < 0 or dt > 60:
		return false
	var q := displacement.duplicate()
	var v := velocity.duplicate()
	var work := 0.0
	for i in 3:
		var a: float = DAMPING_NS_M[i] / (2.0 * MASS_KG[i])
		var omega2: float = STIFFNESS_N_M[i] / MASS_KG[i]
		var w := sqrt(omega2 - a * a)
		var equilibrium: float = force[i] / STIFFNESS_N_M[i]
		var u := displacement[i] - equilibrium
		# Check both alternating extrema, not only the end of a long frame.
		# Subsequent peaks decay about equilibrium and cannot exceed these two.
		var first_peak := fposmod(M.atan2_(velocity[i], (a * velocity[i] + omega2 * u) / w), PI) / w
		for peak in 2:
			var t := first_peak + peak * PI / w
			if t <= dt:
				var peak_q := equilibrium + M.exp_(-a * t) * (u * M.cos_(w * t) + (velocity[i] + a * u) * M.sin_(w * t) / w)
				if absf(peak_q) > TRAVEL_LIMIT_M[i]:
					return false
		var decay := M.exp_(-a * dt)
		var cosine := M.cos_(w * dt)
		var sine := M.sin_(w * dt)
		q[i] = equilibrium + decay * (u * cosine + (velocity[i] + a * u) * sine / w)
		v[i] = decay * (velocity[i] * cosine - (a * velocity[i] + omega2 * u) * sine / w)
		if not is_finite(q[i]) or not is_finite(v[i]) or absf(q[i]) > TRAVEL_LIMIT_M[i]:
			return false
		work += force[i] * (q[i] - displacement[i])
	var loss := work + energy_j() - _energy(q, v)
	if loss < -1e-10:
		return false
	displacement = q
	velocity = v
	work_j += work
	dissipated_j += maxf(0.0, loss)
	return true


func needs_advance() -> bool:
	for i in 3:
		if absf(displacement[i] - force[i] / STIFFNESS_N_M[i]) > 1e-10 or absf(velocity[i]) > 1e-9:
			return true
	return false


func capture_state() -> Dictionary:
	return {"q": displacement.duplicate(), "v": velocity.duplicate(), "force": force.duplicate(),
		"work_j": work_j, "dissipated_j": dissipated_j}


func restore_state(state: Dictionary) -> void:
	# Internal rollback from our own detached snapshot only.
	displacement = state.q.duplicate()
	velocity = state.v.duplicate()
	force = state.force.duplicate()
	work_j = state.work_j
	dissipated_j = state.dissipated_j
