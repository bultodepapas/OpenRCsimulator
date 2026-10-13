extends RefCounted
## Reduced quarter-car oracle. State order: sprung height, unsprung height,
## sprung vertical speed, unsprung vertical speed; all heights are upward metres.
## Parameters are prevalidated by the caller. This model has no travel limits,
## tire damping, road deformation, or unsprung rotational/linkage dynamics.

const Integrator := preload("res://physics/integrator.gd")

const Z_SPRUNG := 0
const Z_UNSPRUNG := 1
const V_SPRUNG := 2
const V_UNSPRUNG := 3
const STATE_SIZE := 4
const SUBSTEPS_PER_TICK := 2


static func equilibrium(p: Dictionary, road_height: float = 0.0) -> PackedFloat64Array:
	var sprung_mass := float(p["sprung_mass_kg"])
	var unsprung_mass := float(p["unsprung_mass_kg"])
	var suspension_stiffness := float(p["suspension_stiffness_n_per_m"])
	var tire_stiffness := float(p["tire_stiffness_n_per_m"])
	var gravity := float(p["gravity_m_per_s2"])
	var rest_length := float(p["suspension_rest_length_m"])
	var tire_radius := float(p["tire_radius_m"])

	var unsprung_height := tire_radius + road_height - (sprung_mass + unsprung_mass) * gravity / tire_stiffness
	var sprung_height := unsprung_height + rest_length - sprung_mass * gravity / suspension_stiffness
	return PackedFloat64Array([sprung_height, unsprung_height, 0.0, 0.0])


static func derivative(state: PackedFloat64Array, p: Dictionary, road_height: float = 0.0) -> PackedFloat64Array:
	var sprung_mass := float(p["sprung_mass_kg"])
	var unsprung_mass := float(p["unsprung_mass_kg"])
	var suspension_stiffness := float(p["suspension_stiffness_n_per_m"])
	var suspension_damping := float(p["suspension_damping_n_s_per_m"])
	var tire_stiffness := float(p["tire_stiffness_n_per_m"])
	var gravity := float(p["gravity_m_per_s2"])
	var rest_length := float(p["suspension_rest_length_m"])
	var tire_radius := float(p["tire_radius_m"])

	var suspension_compression := rest_length - state[Z_SPRUNG] + state[Z_UNSPRUNG]
	var suspension_force := (
		suspension_stiffness * suspension_compression
		+ suspension_damping * (state[V_UNSPRUNG] - state[V_SPRUNG])
	)
	var tire_compression := maxf(tire_radius + road_height - state[Z_UNSPRUNG], 0.0)
	var tire_force := tire_stiffness * tire_compression

	var sprung_acceleration := suspension_force / sprung_mass - gravity
	var unsprung_acceleration := (tire_force - suspension_force) / unsprung_mass - gravity
	return PackedFloat64Array([
		state[V_SPRUNG],
		state[V_UNSPRUNG],
		sprung_acceleration,
		unsprung_acceleration,
	])


static func loads(state: PackedFloat64Array, p: Dictionary, road_height: float = 0.0) -> Dictionary:
	var suspension_stiffness := float(p["suspension_stiffness_n_per_m"])
	var suspension_damping := float(p["suspension_damping_n_s_per_m"])
	var tire_stiffness := float(p["tire_stiffness_n_per_m"])
	var rest_length := float(p["suspension_rest_length_m"])
	var tire_radius := float(p["tire_radius_m"])

	var suspension_compression := rest_length - state[Z_SPRUNG] + state[Z_UNSPRUNG]
	var tire_compression := maxf(tire_radius + road_height - state[Z_UNSPRUNG], 0.0)
	var suspension_force := (
		suspension_stiffness * suspension_compression
		+ suspension_damping * (state[V_UNSPRUNG] - state[V_SPRUNG])
	)
	var tire_force := tire_stiffness * tire_compression
	var relative_damper_speed := state[V_SPRUNG] - state[V_UNSPRUNG]

	return {
		"suspension_force_n": suspension_force,
		"tire_force_n": tire_force,
		"suspension_compression_m": suspension_compression,
		"tire_compression_m": tire_compression,
		"dissipation_w": suspension_damping * relative_damper_speed * relative_damper_speed,
		"in_contact": tire_compression > 0.0,
	}


static func energy(state: PackedFloat64Array, p: Dictionary, road_height: float = 0.0) -> float:
	var sprung_mass := float(p["sprung_mass_kg"])
	var unsprung_mass := float(p["unsprung_mass_kg"])
	var suspension_stiffness := float(p["suspension_stiffness_n_per_m"])
	var tire_stiffness := float(p["tire_stiffness_n_per_m"])
	var gravity := float(p["gravity_m_per_s2"])
	var rest_length := float(p["suspension_rest_length_m"])
	var tire_radius := float(p["tire_radius_m"])

	var suspension_compression := rest_length - state[Z_SPRUNG] + state[Z_UNSPRUNG]
	var tire_compression := maxf(tire_radius + road_height - state[Z_UNSPRUNG], 0.0)
	var kinetic_energy := (
		0.5 * sprung_mass * state[V_SPRUNG] * state[V_SPRUNG]
		+ 0.5 * unsprung_mass * state[V_UNSPRUNG] * state[V_UNSPRUNG]
	)
	var gravitational_energy := (
		sprung_mass * gravity * state[Z_SPRUNG]
		+ unsprung_mass * gravity * state[Z_UNSPRUNG]
	)
	var suspension_energy := 0.5 * suspension_stiffness * suspension_compression * suspension_compression
	var tire_energy := 0.5 * tire_stiffness * tire_compression * tire_compression
	return kinetic_energy + gravitational_energy + suspension_energy + tire_energy


static func step(
	state: PackedFloat64Array,
	p: Dictionary,
	t: float,
	dt: float,
	road: Callable,
) -> PackedFloat64Array:
	# The undamped 240 Hz single-step oracle exceeded its frozen error gate, so
	# this bench uses two equal RK4 substeps at every public tick rate.
	var substep_dt := dt / float(SUBSTEPS_PER_TICK)
	var first_half := _rk4_step(state, p, t, substep_dt, road)
	return _rk4_step(first_half, p, t + substep_dt, substep_dt, road)


static func _rk4_step(
	state: PackedFloat64Array,
	p: Dictionary,
	t: float,
	dt: float,
	road: Callable,
) -> PackedFloat64Array:
	# The road callback must be deterministic for a given time. RK4 samples the
	# midpoint twice, once for each of its two midpoint derivative evaluations.
	# Use the shared element-wise helper only; the rigid-body finalizer normalizes
	# a quaternion and is not valid for this four-state system.
	var k1 := derivative(state, p, float(road.call(t)))
	var stage_2 := Integrator.axpy(state, 0.5 * dt, k1)
	var k2 := derivative(stage_2, p, float(road.call(t + 0.5 * dt)))
	var stage_3 := Integrator.axpy(state, 0.5 * dt, k2)
	var k3 := derivative(stage_3, p, float(road.call(t + 0.5 * dt)))
	var stage_4 := Integrator.axpy(state, dt, k3)
	var k4 := derivative(stage_4, p, float(road.call(t + dt)))

	var weighted := Integrator.axpy(k1, 2.0, k2)
	weighted = Integrator.axpy(weighted, 2.0, k3)
	weighted = Integrator.axpy(weighted, 1.0, k4)
	return Integrator.axpy(state, dt / 6.0, weighted)
