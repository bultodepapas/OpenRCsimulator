# DR-04a (foundation slice): rung one of the drone plan's fidelity ladder (docs/plans/drone-racing.md §4.1):
# per-rotor quadratic thrust and torque calibrated at the static bench point, T = c_T·ω², Q = c_Q·ω², with the
# control literature's linear rotor drag F_h = −k_h·ω·V_p as the small-advance-ratio in-plane force. No inflow,
# vortex-ring, ground-effect or blade-element terms: those are DR-04 proper on the shared HELI-04 law.
# Frames: body FRD about the CG; every rotor's positive-thrust axis is a = [0, 0, −1] (up); `spin` is +1 for a
# rotor turning counter-clockwise viewed from above and its reaction torque on the body has the sign of −spin
# about a. 64-bit floats only.
extends RefCounted

const M := preload("res://physics/math3d.gd")


## Body loads of one rotor about the CG: {force: float64[3], moment: float64[3], thrust, torque}.
## `hub` is the hub position from the CG in FRD; `v_air` the CG air velocity in FRD; `rates` the body rates.
## `omega_dot` adds the inertial reaction of the rotor's own acceleration about the thrust axis (drone plan §4.6).
static func loads(omega: float, spin: float, hub: PackedFloat64Array, v_air: PackedFloat64Array,
		rates: PackedFloat64Array, omega_dot: float, rotor: Dictionary) -> Dictionary:
	var c_t: float = float(rotor.thrust_coefficient_n_s2)
	var c_q: float = float(rotor.torque_coefficient_n_m_s2)
	var k_h: float = float(rotor.rotor_drag_n_s2_per_m)
	var inertia: float = float(rotor.inertia_kg_m2)
	var thrust: float = c_t * omega * omega
	var torque: float = c_q * omega * omega
	# Air velocity at the hub: the CG air velocity plus the rotation sweep.
	var v_hub: PackedFloat64Array = M.add(v_air, M.cross(rates, hub))
	var force: PackedFloat64Array = M.v3(-k_h * omega * v_hub[0], -k_h * omega * v_hub[1], -thrust)
	var moment: PackedFloat64Array = M.cross(hub, force)
	# Reaction of the aerodynamic torque and of the rotor's inertial acceleration, both about a = [0, 0, −1].
	moment[2] += spin * torque + spin * inertia * omega_dot
	return {force = force, moment = moment, thrust = thrust, torque = torque}


## Hover rotor speed of n identical rotors carrying weight m·g: ω_h = sqrt(m·g / (n·c_T)).
static func hover_speed(mass_kg: float, gravity: float, rotor_count: int, rotor: Dictionary) -> float:
	return sqrt(mass_kg * gravity / (float(rotor_count) * float(rotor.thrust_coefficient_n_s2)))
