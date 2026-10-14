extends RefCounted
## Six-DOF sprung body, four moving hubs, four axial wheel rotors, and a
## second-order steering servo. This custom float64 kernel does not use the
## Godot rigid-body solver. It is a compact game-simulation model, not a
## calibrated tire or suspension model for a specific physical truck.
##
## State begins with the shared NED/FRD rigid-body contract, then appends
## compression-positive arm travel, travel rates, positive-forward wheel
## spin rates, wheel angles, and the positive-right steering servo state.
## Unsprung hubs follow the finite-length arm curve; their translational
## kinetic energy is included in a coupled generalized mass matrix, including
## Coriolis/centrifugal terms. Wheel axial inertia is coupled to body rate and
## relative spin exactly at the axle. Suspension and travel-stop forces are
## internal generalized loads; ground tire/hull forces are external loads.
##
## Tires are point-probed compliant spheres. Tangential tire and hull forces
## use a combined Coulomb circle with a projected Gauss-Seidel acceleration
## constraint and finite slip-relaxation target. This provides low-speed
## sticking and wheelspin without the engine contact solver. The model uses
## parallel front steering, equal four-wheel drive torque, no differential
## gearing dynamics, and axial-only wheel inertia. Terrain callbacks must be
## deterministic and return a unit outward/up normal in NED.

const M := preload("res://physics/math3d.gd")
const Integrator := preload("res://physics/integrator.gd")

const POS := 0
const VEL := 3
const ATT := 6
const RATE := 10
const TRAVEL := 13
const TRAVEL_RATE := 17
const WHEEL_SPIN := 21
const WHEEL_ANGLE := 25
const STEER := 29
const STEER_RATE := 30
const STATE_SIZE := 31
const CORNER_COUNT := 4
const GENERALIZED_SIZE := 14
const SUBSTEPS_PER_TICK := 2
const FRICTION_SWEEPS := 6
const MIN_SLIP_SPEED_M_PER_S := 0.05
const MATRIX_PIVOT_RELATIVE_TOLERANCE := 1.0e-12

const STATE_LAYOUT := [
	"north_m", "east_m", "down_m", "u_m_per_s", "v_m_per_s", "w_m_per_s",
	"qw", "qx", "qy", "qz", "p_rad_per_s", "q_rad_per_s", "r_rad_per_s",
	"travel_fl_m", "travel_fr_m", "travel_rl_m", "travel_rr_m",
	"travel_rate_fl_m_per_s", "travel_rate_fr_m_per_s", "travel_rate_rl_m_per_s", "travel_rate_rr_m_per_s",
	"wheel_spin_fl_rad_per_s", "wheel_spin_fr_rad_per_s", "wheel_spin_rl_rad_per_s", "wheel_spin_rr_rad_per_s",
	"wheel_angle_fl_rad", "wheel_angle_fr_rad", "wheel_angle_rl_rad", "wheel_angle_rr_rad",
	"steering_right_rad", "steering_rate_right_rad_per_s",
]

const DEFAULT_CONTROLS := {"throttle": 0.0, "steering": 0.0, "brake": 0.0, "reverse": false}


## Construct a level, zero-speed supported state for a spawn point. Spawns must
## lie on a locally level, flat start patch; the function refuses unequal
## corner heights/normals instead of hiding an unsupported initial impulse.
static func initialize(
	model: Dictionary,
	road: Callable,
	north_m: float = 0.0,
	east_m: float = 0.0,
) -> Dictionary:
	if not _valid_model(model) or not road.is_valid() or not is_finite(north_m) or not is_finite(east_m):
		return _failure("Invalid model, road callback, or spawn position")
	var static_travel := _static_travel(model)
	var tire_radius := float(model["tire_radius_m"])
	var tire_stiffness := float(model["tire_stiffness_n_per_m"])
	var unsprung_mass := float(model["unsprung_mass_kg"])
	var gravity := float(model["gravity_m_per_s2"])
	var sprung_mass := float(model["sprung_mass_kg"])
	var wheel_load := (sprung_mass / 4.0 + unsprung_mass) * gravity
	var tire_compression := wheel_load / tire_stiffness if gravity > 0.0 else 0.0
	var patch := _check_static_spawn_patch(model, road, north_m, east_m, 0.0, static_travel)
	if not bool(patch["ok"]):
		return _failure(str(patch["error"]))
	var mean_height := float(patch["mean_height_m"])
	var cg_height := (
		mean_height + tire_radius - tire_compression
		+ float(model["cg_height_above_chassis_datum_m"])
		+ float(model["wheel_center_rest_below_chassis_datum_m"])
		- static_travel
	)
	var pose := {
		"id": "default",
		"north_m": north_m,
		"east_m": east_m,
		"heading_rad": 0.0,
		"vehicle_up_m": cg_height,
	}
	var state := make_state(model, pose, road)
	if state.is_empty():
		return _failure("Spawn equilibrium could not be constructed")
	return {"ok": true, "state": state, "error": ""}


## Construct a supported state at an explicit course pose. `vehicle_up_m` is
## the sprung-CG altitude, heading is clockwise/right-positive from north, and
## the initial patch must be level and flat for the tire/spring preload used.
static func make_state(model: Dictionary, pose: Dictionary, road: Callable) -> PackedFloat64Array:
	if not _valid_model(model) or not road.is_valid() or not _valid_pose(pose):
		return PackedFloat64Array()
	var north_m := float(pose["north_m"])
	var east_m := float(pose["east_m"])
	var vehicle_up_m := float(pose["vehicle_up_m"])
	var heading_rad := float(pose["heading_rad"])
	var travel := _static_travel(model)
	var patch := _check_static_spawn_patch(
		model, road, north_m, east_m, heading_rad, travel,
	)
	if not bool(patch["ok"]):
		return PackedFloat64Array()
	var state := PackedFloat64Array()
	state.resize(STATE_SIZE)
	state[POS] = north_m
	state[POS + 1] = east_m
	state[POS + 2] = -vehicle_up_m
	var attitude := M.q_from_euler(heading_rad, 0.0, 0.0)
	for i in 4:
		state[ATT + i] = attitude[i]
	for corner in CORNER_COUNT:
		state[TRAVEL + corner] = travel
	return state


## One deterministic fixed public tick. The caller owns tick/time policy;
## controls stay constant through all RK stages. Input arrays are never edited.
## Returns an empty array on malformed inputs, road samples, or a singular
## generalized mass matrix so a Session can reject the tick transactionally.
static func step(
	state: PackedFloat64Array,
	model: Dictionary,
	controls: Dictionary,
	dt: float,
	road: Callable,
) -> PackedFloat64Array:
	if state.size() != STATE_SIZE or not _valid_model(model) or not _valid_controls(controls):
		return PackedFloat64Array()
	if not road.is_valid() or not is_finite(dt) or dt <= 0.0 or dt > 1.0 / 30.0:
		return PackedFloat64Array()
	if not _finite_array(state) or not _valid_attitude(state):
		return PackedFloat64Array()
	var next := state.duplicate()
	var substep_dt := dt / float(SUBSTEPS_PER_TICK)
	for substep in SUBSTEPS_PER_TICK:
		next = _rk4_step(next, model, controls, road, substep_dt)
		if next.is_empty():
			return PackedFloat64Array()
	return next


## State derivative under one set of controls and a spatially sampled road.
## Exposed for independent numerical oracles; invalid input returns empty.
static func derivative(
	state: PackedFloat64Array,
	model: Dictionary,
	controls: Dictionary,
	road: Callable,
) -> PackedFloat64Array:
	if state.size() != STATE_SIZE or not _valid_model(model) or not _valid_controls(controls):
		return PackedFloat64Array()
	if not road.is_valid() or not _finite_array(state) or not _valid_attitude(state):
		return PackedFloat64Array()
	var evaluated := _evaluate(state, model, controls, road)
	if not bool(evaluated["ok"]):
		return PackedFloat64Array()
	var acceleration: PackedFloat64Array = evaluated["generalized_acceleration"]
	var result := PackedFloat64Array()
	result.resize(STATE_SIZE)
	var velocity_body := _slice3(state, VEL)
	var rate_body := _slice3(state, RATE)
	var accel_body: PackedFloat64Array = PackedFloat64Array([acceleration[0], acceleration[1], acceleration[2]])
	var body_velocity_rate := M.sub(accel_body, M.cross(rate_body, velocity_body))
	var position_rate := M.q_rotate(_state_quaternion(state), velocity_body)
	for i in 3:
		result[POS + i] = position_rate[i]
		result[VEL + i] = body_velocity_rate[i]
		result[RATE + i] = acceleration[3 + i]
	for i in 4:
		result[ATT + i] = _quaternion_rate_component(state, rate_body, i)
		result[TRAVEL + i] = state[TRAVEL_RATE + i]
		result[TRAVEL_RATE + i] = acceleration[6 + i]
		result[WHEEL_SPIN + i] = acceleration[10 + i]
		result[WHEEL_ANGLE + i] = state[WHEEL_SPIN + i]
	result[STEER] = state[STEER_RATE]
	result[STEER_RATE] = float(evaluated["steering_acceleration_rad_per_s2"])
	return result if _finite_array(result) else PackedFloat64Array()


## Diagnostic scalar total energy in joules: sprung/hub/axial-rotor kinetic,
## gravitational, suspension/stop, tire and hull elastic terms. Friction and
## damping dissipate energy; this is diagnostic, not a conserved invariant.
static func energy(state: PackedFloat64Array, model: Dictionary, road: Callable) -> float:
	if state.size() != STATE_SIZE or not _valid_model(model) or not road.is_valid() or not _finite_array(state):
		return NAN
	var evaluated := _evaluate(state, model, DEFAULT_CONTROLS, road)
	if not bool(evaluated["ok"]):
		return NAN
	return float(evaluated["energy_j"])


## Per-corner loads, slip and support diagnostics. Returned vectors use
## FL,FR,RL,RR order; `airborne` means no tire or hull sphere is supporting.
static func telemetry(state: PackedFloat64Array, model: Dictionary, road: Callable) -> Dictionary:
	if state.size() != STATE_SIZE or not _valid_model(model) or not road.is_valid() or not _finite_array(state):
		return {"ok": false, "error": "Invalid telemetry input"}
	var evaluated := _evaluate(state, model, DEFAULT_CONTROLS, road)
	if not bool(evaluated["ok"]):
		return {"ok": false, "error": str(evaluated["error"])}
	var velocity: PackedFloat64Array = _slice3(state, VEL)
	var position_world_velocity: PackedFloat64Array = M.q_rotate(_state_quaternion(state), velocity)
	return {
		"ok": true,
		"error": "",
		"speed_m_per_s": M.norm(position_world_velocity),
		"forward_speed_m_per_s": velocity[0],
		"wheel_load_n": evaluated["wheel_load_n"],
		"wheel_longitudinal_force_n": evaluated["wheel_longitudinal_force_n"],
		"wheel_lateral_force_n": evaluated["wheel_lateral_force_n"],
		"wheel_slip_ratio": evaluated["wheel_slip_ratio"],
		"wheel_slip_angle_rad": evaluated["wheel_slip_angle_rad"],
		"wheel_slip_speed_m_per_s": evaluated["wheel_slip_speed_m_per_s"],
		"wheel_in_contact": evaluated["wheel_in_contact"],
		"hull_in_contact": evaluated["hull_in_contact"],
		"airborne": bool(evaluated["airborne"]),
		"suspension_travel_m": PackedFloat64Array([state[TRAVEL], state[TRAVEL + 1], state[TRAVEL + 2], state[TRAVEL + 3]]),
		"suspension_force_n": evaluated["suspension_force_n"],
		"total_energy_j": evaluated["energy_j"],
	}


static func _rk4_step(
	state: PackedFloat64Array,
	model: Dictionary,
	controls: Dictionary,
	road: Callable,
	dt: float,
) -> PackedFloat64Array:
	var k1 := derivative(state, model, controls, road)
	if k1.is_empty():
		return PackedFloat64Array()
	var stage_2 := Integrator.axpy(state, 0.5 * dt, k1)
	var k2 := derivative(stage_2, model, controls, road)
	if k2.is_empty():
		return PackedFloat64Array()
	var stage_3 := Integrator.axpy(state, 0.5 * dt, k2)
	var k3 := derivative(stage_3, model, controls, road)
	if k3.is_empty():
		return PackedFloat64Array()
	var stage_4 := Integrator.axpy(state, dt, k3)
	var k4 := derivative(stage_4, model, controls, road)
	if k4.is_empty():
		return PackedFloat64Array()
	var weighted := Integrator.axpy(k1, 2.0, k2)
	weighted = Integrator.axpy(weighted, 2.0, k3)
	weighted = Integrator.axpy(weighted, 1.0, k4)
	var next := Integrator.axpy(state, dt / 6.0, weighted)
	if not _finite_array(next):
		return PackedFloat64Array()
	var attitude := M.q_normalized(_state_quaternion(next))
	for i in 4:
		next[ATT + i] = attitude[i]
	return next


static func _evaluate(state: PackedFloat64Array, model: Dictionary, controls: Dictionary, road: Callable) -> Dictionary:
	var q := M.q_normalized(_state_quaternion(state))
	var q_conjugate := M.q_conj(q)
	var body_rate := _slice3(state, RATE)
	var servo_angle := state[STEER]
	var servo_rate := state[STEER_RATE]
	var servo_target := float(controls["steering"]) * float(model["max_steer_angle_rad"])
	var servo_frequency := float(model["steer_servo_natural_frequency_rad_s"])
	var servo_damping := float(model["steer_servo_damping_ratio"])
	var servo_acceleration := (
		servo_frequency * servo_frequency * (servo_target - servo_angle)
		- 2.0 * servo_damping * servo_frequency * servo_rate
	)
	if not is_finite(servo_acceleration):
		return _failure("Steering servo acceleration is non-finite")

	var geometry := _corner_geometry(state, model, servo_angle, servo_rate, servo_acceleration)
	if not bool(geometry["ok"]):
		return geometry
	var matrix := _generalized_mass_matrix(model, geometry)
	if matrix.is_empty():
		return _failure("Could not assemble the coupled generalized mass matrix")
	var rhs := PackedFloat64Array()
	rhs.resize(GENERALIZED_SIZE)
	var gravity_body := M.q_rotate(q_conjugate, PackedFloat64Array([0.0, 0.0, float(model["gravity_m_per_s2"])]))
	var sprung_mass := float(model["sprung_mass_kg"])
	for axis in 3:
		rhs[axis] += sprung_mass * gravity_body[axis]
	var inertia: PackedFloat64Array = model["sprung_inertia_kg_m2"]
	var angular_momentum := _symmetric_inertia_mul(inertia, body_rate)
	var body_gyro := M.cross(body_rate, angular_momentum)
	for axis in 3:
		rhs[3 + axis] -= body_gyro[axis]

	var suspension_force := PackedFloat64Array()
	suspension_force.resize(CORNER_COUNT)
	var tire_load := PackedFloat64Array()
	tire_load.resize(CORNER_COUNT)
	var tire_slip_ratio := PackedFloat64Array()
	tire_slip_ratio.resize(CORNER_COUNT)
	var tire_slip_angle := PackedFloat64Array()
	tire_slip_angle.resize(CORNER_COUNT)
	var tire_slip_speed := PackedFloat64Array()
	tire_slip_speed.resize(CORNER_COUNT)
	var tire_longitudinal_force := PackedFloat64Array()
	tire_longitudinal_force.resize(CORNER_COUNT)
	var tire_lateral_force := PackedFloat64Array()
	tire_lateral_force.resize(CORNER_COUNT)
	var tire_contact := PackedByteArray()
	tire_contact.resize(CORNER_COUNT)
	var hull_contact := PackedByteArray()
	var hull_centers: PackedFloat64Array = model["hull_probe_centers_frd_m"]
	var hull_radii: PackedFloat64Array = model["hull_probe_radii_m"]
	hull_contact.resize(hull_radii.size())
	var spring_energy := 0.0
	var tire_energy := 0.0
	var hull_energy := 0.0
	var friction_contacts: Array[Dictionary] = []
	var position_world := _slice3(state, POS)
	var body_velocity := _slice3(state, VEL)
	var unsprung_mass := float(model["unsprung_mass_kg"])
	var suspension_k := float(model["suspension_stiffness_n_per_m"])
	var suspension_c := float(model["suspension_damping_n_s_per_m"])
	var tire_k := float(model["tire_stiffness_n_per_m"])
	var tire_c := float(model["tire_damping_n_s_per_m"])
	var radius := float(model["tire_radius_m"])
	var bump_k := float(model["bump_stop_stiffness_n_per_m"])
	var bump_c := float(model["bump_stop_damping_n_s_per_m"])
	var droop_k := float(model["droop_stop_stiffness_n_per_m"])
	var droop_c := float(model["droop_stop_damping_n_s_per_m"])
	var wheel_inertia := float(model["wheel_spin_inertia_kg_m2"])
	var spin_axis_body: Array[PackedFloat64Array] = geometry["spin_axis_body"]
	var hub_position_body: Array[PackedFloat64Array] = geometry["hub_position_body"]
	var hub_position_world: Array[PackedFloat64Array] = []
	var hub_velocity_world: Array[PackedFloat64Array] = []
	var hub_force_world: Array[PackedFloat64Array] = []
	var tire_contact_offset_body: Array[PackedFloat64Array] = []
	var tire_normal_world: Array[PackedFloat64Array] = []
	var tire_surface_id: Array = []
	var tire_road_sample: Array[Dictionary] = []
	var controls_throttle := float(controls["throttle"])
	var reverse_factor := -float(model["reverse_torque_fraction"]) if bool(controls["reverse"]) else 1.0
	var drive_base := controls_throttle * float(model["drive_torque_per_wheel_nm"]) * reverse_factor
	var brake_base := float(controls["brake"]) * float(model["brake_torque_per_wheel_nm"])
	var drive_fade := float(model["drive_torque_fade_rad_s"])
	var rolling_scale := float(model["rolling_resistance_coefficient"])
	var tire_mu_scale := float(model["tire_friction_scale"])
	var gravity := float(model["gravity_m_per_s2"])
	var wheel_angles := PackedFloat64Array()
	wheel_angles.resize(CORNER_COUNT)
	var normal_forces_body: Array[PackedFloat64Array] = []
	var hub_bias_body: Array[PackedFloat64Array] = geometry["hub_bias_body"]
	var hub_speed_body: Array[PackedFloat64Array] = geometry["hub_speed_body"]
	var wheel_axis_rate_body: Array[PackedFloat64Array] = geometry["spin_axis_rate_body"]
	var wheel_abs_omega_body: Array[PackedFloat64Array] = []
	var tire_forward_world: Array[PackedFloat64Array] = []
	var tire_lateral_world: Array[PackedFloat64Array] = []
	var tire_slip_long := PackedFloat64Array()
	var tire_slip_lat := PackedFloat64Array()
	tire_slip_long.resize(CORNER_COUNT)
	tire_slip_lat.resize(CORNER_COUNT)
	var tire_mu_normal := PackedFloat64Array()
	tire_mu_normal.resize(CORNER_COUNT)
	var total_rotor_kinetic := 0.0
	var hub_kinetic := 0.0
	var gravity_potential := sprung_mass * gravity * position_world[2]

	for corner in CORNER_COUNT:
		var travel := state[TRAVEL + corner]
		var travel_rate := state[TRAVEL_RATE + corner]
		var stop_force := _travel_stop_force(travel, travel_rate, model)
		var fs := suspension_k * travel + suspension_c * travel_rate
		suspension_force[corner] = fs
		rhs[6 + corner] -= fs
		rhs[6 + corner] += stop_force
		spring_energy += 0.5 * suspension_k * travel * travel
		if travel > float(model["travel_bump_m"]):
			var compression := travel - float(model["travel_bump_m"])
			spring_energy += 0.5 * bump_k * compression * compression
		elif travel < -float(model["travel_droop_m"]):
			var extension := -float(model["travel_droop_m"]) - travel
			spring_energy += 0.5 * droop_k * extension * extension

		var r: PackedFloat64Array = hub_position_body[corner]
		var r_prime: PackedFloat64Array = geometry["hub_position_derivative_body"][corner]
		var hub_world := M.add(position_world, M.q_rotate(q, r))
		var hub_velocity := M.add(body_velocity, M.add(M.cross(body_rate, r), M.scale(r_prime, travel_rate)))
		var hub_velocity_ned := M.q_rotate(q, hub_velocity)
		hub_position_world.append(hub_world)
		hub_velocity_world.append(hub_velocity_ned)
		var sample_result := _sample_surface(road, hub_world[0], hub_world[1])
		if not bool(sample_result["ok"]):
			return sample_result
		var sample: Dictionary = sample_result["surface"]
		tire_road_sample.append(sample)
		tire_surface_id.append(sample.get("surface_id", ""))
		var normal: PackedFloat64Array = sample["normal_ned"]
		tire_normal_world.append(normal)
		var surface_point := PackedFloat64Array([hub_world[0], hub_world[1], -float(sample["height_m"])])
		var signed_distance := M.dot(normal, M.sub(hub_world, surface_point))
		var penetration := maxf(radius - signed_distance, 0.0)
		var hub_normal_speed := M.dot(hub_velocity_ned, normal)
		var normal_load := 0.0
		if penetration > 0.0:
			normal_load = maxf(0.0, tire_k * penetration - tire_c * hub_normal_speed)
		tire_load[corner] = normal_load
		tire_contact[corner] = 1 if normal_load > 0.0 else 0
		tire_mu_normal[corner] = maxf(0.0, float(sample["mu"]) * tire_mu_scale * normal_load)
		tire_energy += 0.5 * tire_k * penetration * penetration
		var force_world := M.scale(normal, normal_load)
		var force_body := M.q_rotate(q_conjugate, force_world)
		var rho_world := M.scale(normal, -radius)
		var rho_body := M.q_rotate(q_conjugate, rho_world)
		tire_contact_offset_body.append(rho_body)
		hub_force_world.append(force_world)
		normal_forces_body.append(force_body)
		_add_contact_force(rhs, r, force_body, r_prime, corner, spin_axis_body[corner], rho_body)

		var left_steer_angle := -servo_angle if corner < 2 else 0.0
		var left_steer_rate := -servo_rate if corner < 2 else 0.0
		var wheel_axis := spin_axis_body[corner]
		var wheel_spin := state[WHEEL_SPIN + corner]
		var wheel_omega := M.add(body_rate, M.add(
			PackedFloat64Array([0.0, 0.0, left_steer_rate]), M.scale(wheel_axis, wheel_spin)))
		wheel_abs_omega_body.append(wheel_omega)
		var contact_velocity_ned := M.add(
			hub_velocity_ned,
			M.q_rotate(q, M.cross(wheel_omega, rho_body)),
		)
		var forward_body := PackedFloat64Array([M.cos_(left_steer_angle), -M.sin_(left_steer_angle), 0.0])
		var forward_world := M.q_rotate(q, forward_body)
		forward_world = M.sub(forward_world, M.scale(normal, M.dot(forward_world, normal)))
		var forward_norm := M.norm(forward_world)
		if forward_norm <= 1.0e-10:
			return _failure("Tire forward axis is degenerate on the sampled surface")
		forward_world = M.scale(forward_world, 1.0 / forward_norm)
		var lateral_world := M.cross(forward_world, normal)
		var lateral_norm := M.norm(lateral_world)
		if lateral_norm <= 1.0e-10:
			return _failure("Tire lateral axis is degenerate on the sampled surface")
		lateral_world = M.scale(lateral_world, 1.0 / lateral_norm)
		tire_forward_world.append(forward_world)
		tire_lateral_world.append(lateral_world)
		var slip_long := M.dot(contact_velocity_ned, forward_world)
		var slip_lateral := M.dot(contact_velocity_ned, lateral_world)
		tire_slip_long[corner] = slip_long
		tire_slip_lat[corner] = slip_lateral
		tire_slip_speed[corner] = M.sqrt_(slip_long * slip_long + slip_lateral * slip_lateral)
		var wheel_circumference_speed := wheel_spin * radius
		var hub_forward_speed := M.dot(hub_velocity_ned, forward_world)
		var ratio_denominator := maxf(MIN_SLIP_SPEED_M_PER_S, maxf(absf(hub_forward_speed), absf(wheel_circumference_speed)))
		tire_slip_ratio[corner] = (wheel_circumference_speed - hub_forward_speed) / ratio_denominator
		tire_slip_angle[corner] = M.atan2_(slip_lateral, maxf(absf(slip_long), MIN_SLIP_SPEED_M_PER_S))
		if normal_load > 0.0:
			var tangent_rows := _tire_contact_rows(q_conjugate, forward_world, lateral_world, r, rho_body, r_prime, wheel_axis, corner)
			var bias_result := _tire_contact_bias(
				q, body_rate, hub_bias_body[corner], hub_velocity, wheel_omega,
				wheel_axis_rate_body[corner], left_steer_rate,
				geometry["steering_acceleration_body"][corner],
				wheel_spin, rho_body,
			)
			if not bool(bias_result["ok"]):
				return bias_result
			friction_contacts.append({
				"rows": tangent_rows,
				"directions": [forward_world, lateral_world],
				"slip": PackedFloat64Array([slip_long, slip_lateral]),
				"bias": bias_result["bias"],
				"mu_load": tire_mu_normal[corner],
				"tau": float(model["tire_slip_relaxation_s"]),
				"kind": "wheel",
				"index": corner,
			})

		var torque := drive_base
		if drive_fade > 0.0:
			torque *= maxf(0.0, 1.0 - absf(wheel_spin) / drive_fade)
		var brake_direction := signf(wheel_spin)
		if absf(wheel_spin) <= 1.0e-5:
			brake_direction = signf(torque)
		rhs[10 + corner] += torque - brake_base * brake_direction
		if normal_load > 0.0:
			var rolling_torque := (
				rolling_scale * float(sample["rolling"]) * normal_load * radius
				* wheel_spin / M.sqrt_(wheel_spin * wheel_spin + 1.0e-6)
			)
			rhs[10 + corner] -= rolling_torque
		var rotor_rate := M.dot(body_rate, wheel_axis) + wheel_spin
		total_rotor_kinetic += 0.5 * wheel_inertia * rotor_rate * rotor_rate
		wheel_angles[corner] = state[WHEEL_ANGLE + corner]

		var hub_bias: PackedFloat64Array = hub_bias_body[corner]
		var hub_bias_generalized := _hub_bias_generalized(r, r_prime, corner, unsprung_mass, hub_bias)
		_add_scaled_vector(rhs, hub_bias_generalized, -1.0)
		var gravity_generalized := _hub_gravity_generalized(r, r_prime, corner, unsprung_mass, gravity_body)
		_add_scaled_vector(rhs, gravity_generalized, 1.0)
		var hub_velocity_vec: PackedFloat64Array = hub_speed_body[corner]
		hub_kinetic += 0.5 * unsprung_mass * M.dot(hub_velocity_vec, hub_velocity_vec)
		gravity_potential += unsprung_mass * gravity * hub_world[2]

	# Add wheel-rotor convective angular momentum bias. Axial inertia is included
	# in the mass matrix; this term accounts for body transport and steering-axis
	# motion without counting motor/contact torque twice.
	for corner in CORNER_COUNT:
		var axis: PackedFloat64Array = spin_axis_body[corner]
		var axis_rate: PackedFloat64Array = wheel_axis_rate_body[corner]
		var spin := state[WHEEL_SPIN + corner]
		var axial_rate := M.dot(body_rate, axis) + spin
		var rotor_bias := M.add(
			M.scale(axis, M.dot(body_rate, axis_rate)),
			M.scale(M.add(axis_rate, M.cross(body_rate, axis)), axial_rate),
		)
		var wheel_inertia_value := float(model["wheel_spin_inertia_kg_m2"])
		for axis_index in 3:
			rhs[3 + axis_index] -= wheel_inertia_value * rotor_bias[axis_index]
		rhs[10 + corner] -= wheel_inertia_value * M.dot(body_rate, axis_rate)

	# Hull spheres provide physical bumper, roof and side impacts for rollovers.
	for probe in hull_radii.size():
		var center := PackedFloat64Array([
			hull_centers[probe * 3], hull_centers[probe * 3 + 1], hull_centers[probe * 3 + 2],
		])
		var center_world := M.add(position_world, M.q_rotate(q, center))
		var surface_result := _sample_surface(road, center_world[0], center_world[1])
		if not bool(surface_result["ok"]):
			return surface_result
		var surface_probe: Dictionary = surface_result["surface"]
		var normal_probe: PackedFloat64Array = surface_probe["normal_ned"]
		var ground_point := PackedFloat64Array([
			center_world[0], center_world[1], -float(surface_probe["height_m"]),
		])
		var signed_probe_distance := M.dot(normal_probe, M.sub(center_world, ground_point))
		var probe_penetration := maxf(hull_radii[probe] - signed_probe_distance, 0.0)
		var center_velocity_body := M.add(body_velocity, M.cross(body_rate, center))
		var center_velocity_world := M.q_rotate(q, center_velocity_body)
		var probe_normal_speed := M.dot(center_velocity_world, normal_probe)
		var hull_load := 0.0
		if probe_penetration > 0.0:
			hull_load = maxf(
				0.0,
				float(model["hull_contact_stiffness_n_per_m"]) * probe_penetration
				- float(model["hull_contact_damping_n_s_per_m"]) * probe_normal_speed,
			)
		hull_contact[probe] = 1 if hull_load > 0.0 else 0
		hull_energy += 0.5 * float(model["hull_contact_stiffness_n_per_m"]) * probe_penetration * probe_penetration
		if hull_load <= 0.0:
			continue
		var hull_force_world := M.scale(normal_probe, hull_load)
		var hull_force_body := M.q_rotate(q_conjugate, hull_force_world)
		_add_body_force(rhs, center, hull_force_body)
		var rho_world_hull := M.scale(normal_probe, -hull_radii[probe])
		var rho_body_hull := M.q_rotate(q_conjugate, rho_world_hull)
		var hull_contact_point_velocity := M.add(
			center_velocity_world,
			M.q_rotate(q, M.cross(body_rate, rho_body_hull)),
		)
		var hull_tangent := M.sub(hull_contact_point_velocity, M.scale(normal_probe, M.dot(hull_contact_point_velocity, normal_probe)))
		var hull_tangent_speed := M.norm(hull_tangent)
		var hull_friction_limit := maxf(0.0, float(surface_probe["mu"]) * float(model["hull_contact_friction_scale"]) * hull_load)
		if hull_tangent_speed > 1.0e-10 and hull_friction_limit > 0.0:
			var tangent_direction := M.scale(hull_tangent, -1.0 / hull_tangent_speed)
			var tangent_force := M.scale(tangent_direction, hull_friction_limit * M.tanh_(hull_tangent_speed / 0.02))
			_add_body_force(rhs, M.add(center, rho_body_hull), M.q_rotate(q_conjugate, tangent_force))

	var inverse_result := _invert_matrix(matrix, GENERALIZED_SIZE)
	if not bool(inverse_result["ok"]):
		return _failure("Coupled generalized mass matrix is singular: " + str(inverse_result["error"]))
	var inverse: PackedFloat64Array = inverse_result["inverse"]
	var acceleration := _matrix_vector(inverse, rhs, GENERALIZED_SIZE)
	if not _finite_array(acceleration):
		return _failure("Unconstrained generalized acceleration is non-finite")
	var friction_result := _solve_tangent_friction(
		inverse, acceleration, friction_contacts, tire_longitudinal_force, tire_lateral_force,
	)
	if not bool(friction_result["ok"]):
		return friction_result
	acceleration = friction_result["acceleration"]
	var tire_in_contact_count := 0
	var hull_in_contact_count := 0
	for byte in tire_contact:
		tire_in_contact_count += int(byte)
	for byte in hull_contact:
		hull_in_contact_count += int(byte)
	var energy_value := _energy_from_terms(state, model, body_rate, hub_kinetic, total_rotor_kinetic,
		gravity_potential, spring_energy, tire_energy, hull_energy)
	return {
		"ok": true,
		"error": "",
		"generalized_acceleration": acceleration,
		"steering_acceleration_rad_per_s2": servo_acceleration,
		"suspension_force_n": suspension_force,
		"wheel_load_n": tire_load,
		"wheel_longitudinal_force_n": tire_longitudinal_force,
		"wheel_lateral_force_n": tire_lateral_force,
		"wheel_slip_ratio": tire_slip_ratio,
		"wheel_slip_angle_rad": tire_slip_angle,
		"wheel_slip_speed_m_per_s": tire_slip_speed,
		"wheel_in_contact": tire_contact,
		"hull_in_contact": hull_contact,
		"airborne": tire_in_contact_count == 0 and hull_in_contact_count == 0,
		"energy_j": energy_value,
	}


static func _corner_geometry(state: PackedFloat64Array, model: Dictionary, steer_right: float, steer_rate_right: float, steer_accel_right: float) -> Dictionary:
	var corner_x: PackedFloat64Array = model["corner_x_m"]
	var corner_y: PackedFloat64Array = model["corner_y_m"]
	var arm_length := float(model["arm_length_m"])
	var cg_height := float(model["cg_height_above_chassis_datum_m"])
	var rest_below := float(model["wheel_center_rest_below_chassis_datum_m"])
	var body_rate := _slice3(state, RATE)
	var hubs: Array[PackedFloat64Array] = []
	var derivatives: Array[PackedFloat64Array] = []
	var second_derivatives: Array[PackedFloat64Array] = []
	var hub_speed: Array[PackedFloat64Array] = []
	var hub_bias: Array[PackedFloat64Array] = []
	var axes: Array[PackedFloat64Array] = []
	var axis_rates: Array[PackedFloat64Array] = []
	var servo_accels: Array[float] = []
	for corner in CORNER_COUNT:
		var travel := state[TRAVEL + corner]
		if absf(travel) >= arm_length:
			return _failure("Suspension travel reaches the A-arm geometric singularity")
		var lateral_offset := M.sqrt_(arm_length * arm_length - travel * travel)
		var side := signf(corner_y[corner])
		# Preserve the authored wheel station about the shifted CG; travel moves
		# the hub laterally along its arm from that zero-travel location.
		var y := corner_y[corner] + side * (lateral_offset - arm_length)
		var y_prime := -side * travel / lateral_offset
		var y_second := -side * arm_length * arm_length / (lateral_offset * lateral_offset * lateral_offset)
		var r := PackedFloat64Array([corner_x[corner], y, cg_height + rest_below - travel])
		var r_prime := PackedFloat64Array([0.0, y_prime, -1.0])
		var r_second := PackedFloat64Array([0.0, y_second, 0.0])
		var rate := state[TRAVEL_RATE + corner]
		var hub_v := M.add(_slice3(state, VEL), M.add(M.cross(body_rate, r), M.scale(r_prime, rate)))
		var hub_b := M.add(
			M.cross(body_rate, M.cross(body_rate, r)),
			M.add(M.scale(M.cross(body_rate, r_prime), 2.0 * rate), M.scale(r_second, rate * rate)),
		)
		var left_angle := -steer_right if corner < 2 else 0.0
		var left_rate := -steer_rate_right if corner < 2 else 0.0
		var left_accel := -steer_accel_right if corner < 2 else 0.0
		var forward := PackedFloat64Array([M.cos_(left_angle), -M.sin_(left_angle), 0.0])
		var axis := M.cross(forward, PackedFloat64Array([0.0, 0.0, -1.0]))
		var axis_rate := M.scale(M.cross(PackedFloat64Array([0.0, 0.0, 1.0]), axis), left_rate)
		hubs.append(r)
		derivatives.append(r_prime)
		second_derivatives.append(r_second)
		hub_speed.append(hub_v)
		hub_bias.append(hub_b)
		axes.append(axis)
		axis_rates.append(axis_rate)
		servo_accels.append(left_accel)
	return {
		"ok": true,
		"hub_position_body": hubs,
		"hub_position_derivative_body": derivatives,
		"hub_position_second_derivative_body": second_derivatives,
		"hub_speed_body": hub_speed,
		"hub_bias_body": hub_bias,
		"spin_axis_body": axes,
		"spin_axis_rate_body": axis_rates,
		"steering_acceleration_body": servo_accels,
	}


static func _generalized_mass_matrix(model: Dictionary, geometry: Dictionary) -> PackedFloat64Array:
	var n := GENERALIZED_SIZE
	var matrix := PackedFloat64Array()
	matrix.resize(n * n)
	var sprung_mass := float(model["sprung_mass_kg"])
	for axis in 3:
		matrix[axis * n + axis] += sprung_mass
	var inertia: PackedFloat64Array = model["sprung_inertia_kg_m2"]
	matrix[3 * n + 3] += inertia[0]
	matrix[4 * n + 4] += inertia[1]
	matrix[5 * n + 5] += inertia[2]
	matrix[3 * n + 4] += inertia[3]
	matrix[4 * n + 3] += inertia[3]
	matrix[3 * n + 5] += inertia[4]
	matrix[5 * n + 3] += inertia[4]
	matrix[4 * n + 5] += inertia[5]
	matrix[5 * n + 4] += inertia[5]
	var mass := float(model["unsprung_mass_kg"])
	var hubs: Array[PackedFloat64Array] = geometry["hub_position_body"]
	var derivatives: Array[PackedFloat64Array] = geometry["hub_position_derivative_body"]
	for corner in CORNER_COUNT:
		var jacobian := _hub_jacobian(hubs[corner], derivatives[corner], corner)
		_add_gram(matrix, jacobian, mass, n)
	var wheel_inertia := float(model["wheel_spin_inertia_kg_m2"])
	var axes: Array[PackedFloat64Array] = geometry["spin_axis_body"]
	for corner in CORNER_COUNT:
		var rotor_row := PackedFloat64Array()
		rotor_row.resize(n)
		for axis in 3:
			rotor_row[3 + axis] = axes[corner][axis]
		rotor_row[10 + corner] = 1.0
		_add_outer(matrix, rotor_row, wheel_inertia, n)
	return matrix


static func _hub_jacobian(r: PackedFloat64Array, r_prime: PackedFloat64Array, corner: int) -> PackedFloat64Array:
	var n := GENERALIZED_SIZE
	var jacobian := PackedFloat64Array()
	jacobian.resize(3 * n)
	for axis in 3:
		jacobian[axis * n + axis] = 1.0
	# A hub's body angular velocity contribution is omega × r = -[r]x omega.
	jacobian[0 * n + 4] = r[2]
	jacobian[0 * n + 5] = -r[1]
	jacobian[1 * n + 3] = -r[2]
	jacobian[1 * n + 5] = r[0]
	jacobian[2 * n + 3] = r[1]
	jacobian[2 * n + 4] = -r[0]
	for axis in 3:
		jacobian[axis * n + 6 + corner] = r_prime[axis]
	return jacobian


static func _add_gram(matrix: PackedFloat64Array, jacobian: PackedFloat64Array, mass: float, n: int) -> void:
	for row in n:
		var row_values := PackedFloat64Array([jacobian[row], jacobian[n + row], jacobian[2 * n + row]])
		for column in n:
			matrix[row * n + column] += mass * (
				row_values[0] * jacobian[column]
				+ row_values[1] * jacobian[n + column]
				+ row_values[2] * jacobian[2 * n + column]
			)


static func _add_outer(matrix: PackedFloat64Array, row: PackedFloat64Array, scale: float, n: int) -> void:
	for i in n:
		for j in n:
			matrix[i * n + j] += scale * row[i] * row[j]


static func _hub_bias_generalized(r: PackedFloat64Array, r_prime: PackedFloat64Array, corner: int, mass: float, bias: PackedFloat64Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(GENERALIZED_SIZE)
	for axis in 3:
		result[axis] = mass * bias[axis]
	var moment := M.cross(r, bias)
	for axis in 3:
		result[3 + axis] = mass * moment[axis]
	result[6 + corner] = mass * M.dot(r_prime, bias)
	return result


static func _hub_gravity_generalized(r: PackedFloat64Array, r_prime: PackedFloat64Array, corner: int, mass: float, gravity_body: PackedFloat64Array) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(GENERALIZED_SIZE)
	for axis in 3:
		result[axis] = mass * gravity_body[axis]
	var moment := M.cross(r, gravity_body)
	for axis in 3:
		result[3 + axis] = mass * moment[axis]
	result[6 + corner] = mass * M.dot(r_prime, gravity_body)
	return result


static func _add_contact_force(
	rhs: PackedFloat64Array,
	r: PackedFloat64Array,
	force_body: PackedFloat64Array,
	r_prime: PackedFloat64Array,
	corner: int,
	spin_axis: PackedFloat64Array,
	rho_body: PackedFloat64Array,
) -> void:
	for axis in 3:
		rhs[axis] += force_body[axis]
	var moment := M.cross(M.add(r, rho_body), force_body)
	for axis in 3:
		rhs[3 + axis] += moment[axis]
	rhs[6 + corner] += M.dot(r_prime, force_body)
	rhs[10 + corner] += M.dot(spin_axis, M.cross(rho_body, force_body))


static func _add_body_force(rhs: PackedFloat64Array, point_body: PackedFloat64Array, force_body: PackedFloat64Array) -> void:
	for axis in 3:
		rhs[axis] += force_body[axis]
	var moment := M.cross(point_body, force_body)
	for axis in 3:
		rhs[3 + axis] += moment[axis]


static func _tire_contact_rows(
	q_conjugate: PackedFloat64Array,
	forward_world: PackedFloat64Array,
	lateral_world: PackedFloat64Array,
	r: PackedFloat64Array,
	rho: PackedFloat64Array,
	r_prime: PackedFloat64Array,
	spin_axis: PackedFloat64Array,
	corner: int,
) -> Array[PackedFloat64Array]:
	var rows: Array[PackedFloat64Array] = []
	rows.append(_contact_row(q_conjugate, forward_world, M.add(r, rho), r_prime, spin_axis, rho, corner))
	rows.append(_contact_row(q_conjugate, lateral_world, M.add(r, rho), r_prime, spin_axis, rho, corner))
	return rows


static func _contact_row(
	q_conjugate: PackedFloat64Array,
	direction_world: PackedFloat64Array,
	lever_body: PackedFloat64Array,
	r_prime: PackedFloat64Array,
	spin_axis: PackedFloat64Array,
	rho: PackedFloat64Array,
	corner: int,
) -> PackedFloat64Array:
	var direction_body := M.q_rotate(q_conjugate, direction_world)
	var row := PackedFloat64Array()
	row.resize(GENERALIZED_SIZE)
	for axis in 3:
		row[axis] = direction_body[axis]
	var moment := M.cross(lever_body, direction_body)
	for axis in 3:
		row[3 + axis] = moment[axis]
	row[6 + corner] = M.dot(r_prime, direction_body)
	row[10 + corner] = M.dot(spin_axis, M.cross(rho, direction_body))
	return row


static func _tire_contact_bias(
	q: PackedFloat64Array,
	body_rate: PackedFloat64Array,
	hub_bias: PackedFloat64Array,
	hub_velocity: PackedFloat64Array,
	wheel_omega: PackedFloat64Array,
	spin_axis_rate: PackedFloat64Array,
	steer_rate_left: float,
	steer_accel_left: float,
	wheel_spin: float,
	rho_body: PackedFloat64Array,
) -> Dictionary:
	var angular_convective := M.add(
		M.cross(body_rate, wheel_omega),
	M.add(
		M.scale(PackedFloat64Array([0.0, 0.0, 1.0]), steer_accel_left),
		M.scale(spin_axis_rate, wheel_spin),
	)
	)
	var point_bias_body := M.add(
		hub_bias,
		M.cross(angular_convective, rho_body),
	)
	var point_bias_world := M.q_rotate(q, point_bias_body)
	# The surface normal's spatial derivative is unavailable in the road API;
	# this local constraint therefore treats the sampled plane as tangent-fixed.
	if not _finite_array(point_bias_world) or not is_finite(steer_rate_left) or not _finite_array(hub_velocity):
		return _failure("Tire contact bias became non-finite")
	return {"ok": true, "bias": point_bias_world}


static func _solve_tangent_friction(
	inverse: PackedFloat64Array,
	acceleration: PackedFloat64Array,
	contacts: Array[Dictionary],
	longitudinal_force: PackedFloat64Array,
	lateral_force: PackedFloat64Array,
) -> Dictionary:
	if contacts.is_empty():
		return {"ok": true, "acceleration": acceleration}
	var rows: Array[PackedFloat64Array] = []
	var columns: Array[PackedFloat64Array] = []
	var contact_row_indexes: Array[PackedInt32Array] = []
	for contact in contacts:
		var contact_rows: Array = contact["rows"]
		var indexes := PackedInt32Array()
		for row_value in contact_rows:
			var row: PackedFloat64Array = row_value
			indexes.append(rows.size())
			rows.append(row)
			columns.append(_matrix_vector(inverse, row, GENERALIZED_SIZE))
		contact_row_indexes.append(indexes)
	var forces := PackedFloat64Array()
	forces.resize(rows.size())
	var slip_bias: Array[PackedFloat64Array] = []
	for contact in contacts:
		var bias_world: PackedFloat64Array = contact["bias"]
		var directions: Array = contact["directions"]
		var forward_direction: PackedFloat64Array = directions[0]
		var lateral_direction: PackedFloat64Array = directions[1]
		var bias := PackedFloat64Array([
			M.dot(forward_direction, bias_world), M.dot(lateral_direction, bias_world),
		])
		slip_bias.append(bias)
	for sweep in FRICTION_SWEEPS:
		for contact_index in contacts.size():
			var contact: Dictionary = contacts[contact_index]
			var indexes: PackedInt32Array = contact_row_indexes[contact_index]
			var i0 := indexes[0]
			var i1 := indexes[1]
			var row0: PackedFloat64Array = rows[i0]
			var row1: PackedFloat64Array = rows[i1]
			var col0: PackedFloat64Array = columns[i0]
			var col1: PackedFloat64Array = columns[i1]
			var w00 := M.dot(row0, col0)
			var w01 := M.dot(row0, col1)
			var w10 := M.dot(row1, col0)
			var w11 := M.dot(row1, col1)
			var determinant := w00 * w11 - w01 * w10
			if not is_finite(determinant) or determinant <= 1.0e-18:
				return _failure("Tangent contact mobility is singular")
			var current_long := M.dot(row0, acceleration) + slip_bias[contact_index][0]
			var current_lateral := M.dot(row1, acceleration) + slip_bias[contact_index][1]
			var slip: PackedFloat64Array = contact["slip"]
			var tau := maxf(float(contact["tau"]), 1.0e-5)
			var target_long := -slip[0] / tau
			var target_lateral := -slip[1] / tau
			var error_long := target_long - current_long
			var error_lateral := target_lateral - current_lateral
			var delta_long := (w11 * error_long - w01 * error_lateral) / determinant
			var delta_lateral := (-w10 * error_long + w00 * error_lateral) / determinant
			var trial_long := forces[i0] + delta_long
			var trial_lateral := forces[i1] + delta_lateral
			var trial_norm := M.sqrt_(trial_long * trial_long + trial_lateral * trial_lateral)
			var force_limit := maxf(0.0, float(contact["mu_load"]))
			if trial_norm > force_limit and trial_norm > 0.0:
				var ratio := force_limit / trial_norm
				trial_long *= ratio
				trial_lateral *= ratio
			delta_long = trial_long - forces[i0]
			delta_lateral = trial_lateral - forces[i1]
			forces[i0] = trial_long
			forces[i1] = trial_lateral
			for degree in GENERALIZED_SIZE:
				acceleration[degree] += columns[i0][degree] * delta_long + columns[i1][degree] * delta_lateral
			if str(contact["kind"]) == "wheel":
				var corner := int(contact["index"])
				longitudinal_force[corner] = trial_long
				lateral_force[corner] = trial_lateral
	return {"ok": true, "acceleration": acceleration}


static func _matrix_vector(matrix: PackedFloat64Array, vector: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	result.resize(n)
	for row in n:
		var value := 0.0
		for column in n:
			value += matrix[row * n + column] * vector[column]
		result[row] = value
	return result


static func _invert_matrix(matrix: PackedFloat64Array, n: int) -> Dictionary:
	if matrix.size() != n * n:
		return {"ok": false, "error": "invalid matrix dimensions"}
	var width := 2 * n
	var augmented := PackedFloat64Array()
	augmented.resize(n * width)
	var scale := 0.0
	for row in n:
		for column in n:
			var value := matrix[row * n + column]
			if not is_finite(value):
				return {"ok": false, "error": "non-finite matrix entry"}
			augmented[row * width + column] = value
			scale = maxf(scale, absf(value))
		augmented[row * width + n + row] = 1.0
	if scale <= 0.0:
		return {"ok": false, "error": "zero matrix"}
	for pivot_column in n:
		var pivot_row := pivot_column
		for row in range(pivot_column + 1, n):
			if absf(augmented[row * width + pivot_column]) > absf(augmented[pivot_row * width + pivot_column]):
				pivot_row = row
		var pivot := augmented[pivot_row * width + pivot_column]
		if not is_finite(pivot) or absf(pivot) <= scale * MATRIX_PIVOT_RELATIVE_TOLERANCE:
			return {"ok": false, "error": "pivot is below relative precision threshold"}
		if pivot_row != pivot_column:
			for column in width:
				var swap := augmented[pivot_column * width + column]
				augmented[pivot_column * width + column] = augmented[pivot_row * width + column]
				augmented[pivot_row * width + column] = swap
		pivot = augmented[pivot_column * width + pivot_column]
		for column in width:
			augmented[pivot_column * width + column] /= pivot
		for row in n:
			if row == pivot_column:
				continue
			var factor := augmented[row * width + pivot_column]
			for column in width:
				augmented[row * width + column] -= factor * augmented[pivot_column * width + column]
	var inverse := PackedFloat64Array()
	inverse.resize(n * n)
	for row in n:
		for column in n:
			var value := augmented[row * width + n + column]
			if not is_finite(value):
				return {"ok": false, "error": "inverse became non-finite"}
			inverse[row * n + column] = value
	return {"ok": true, "inverse": inverse}


static func _travel_stop_force(travel: float, travel_rate: float, model: Dictionary) -> float:
	var bump := float(model["travel_bump_m"])
	var droop := float(model["travel_droop_m"])
	if travel > bump:
		return (
			float(model["bump_stop_stiffness_n_per_m"]) * (travel - bump)
			+ float(model["bump_stop_damping_n_s_per_m"]) * maxf(travel_rate, 0.0)
		)
	if travel < -droop:
		return -(
			float(model["droop_stop_stiffness_n_per_m"]) * (-droop - travel)
			+ float(model["droop_stop_damping_n_s_per_m"]) * maxf(-travel_rate, 0.0)
		)
	return 0.0


static func _sample_surface(road: Callable, north: float, east: float) -> Dictionary:
	if not road.is_valid() or not is_finite(north) or not is_finite(east):
		return _failure("Invalid road sample request")
	var raw: Variant = road.call(north, east)
	if typeof(raw) != TYPE_DICTIONARY:
		return _failure("Road callback must return a Dictionary")
	var surface: Dictionary = raw
	if not surface.has("height_m") or not surface.has("normal_ned") or not surface.has("mu") or not surface.has("rolling"):
		return _failure("Road callback omitted height, normal, friction, or rolling resistance")
	var normal_variant: Variant = surface["normal_ned"]
	if typeof(normal_variant) != TYPE_PACKED_FLOAT64_ARRAY:
		return _failure("Road normal must be a PackedFloat64Array")
	var normal: PackedFloat64Array = normal_variant
	if normal.size() != 3 or not _finite_array(normal):
		return _failure("Road normal must contain three finite NED values")
	var normal_length := M.norm(normal)
	if absf(normal_length - 1.0) > 1.0e-5:
		return _failure("Road normal must be unit length")
	var height := float(surface["height_m"])
	var mu := float(surface["mu"])
	var rolling := float(surface["rolling"])
	if not is_finite(height) or not is_finite(mu) or not is_finite(rolling) or mu < 0.0 or rolling < 0.0:
		return _failure("Road height/friction/rolling values must be finite and nonnegative where applicable")
	return {"ok": true, "surface": surface}


static func _valid_model(model: Dictionary) -> bool:
	var scalars := [
		"sprung_mass_kg", "unsprung_mass_kg", "wheel_spin_inertia_kg_m2", "gravity_m_per_s2",
		"arm_inner_offset_m", "arm_length_m", "cg_height_above_chassis_datum_m",
		"wheel_center_rest_below_chassis_datum_m", "tire_radius_m",
		"suspension_stiffness_n_per_m", "suspension_damping_n_s_per_m",
		"tire_stiffness_n_per_m", "tire_damping_n_s_per_m", "tire_slip_relaxation_s",
		"travel_droop_m", "travel_bump_m", "bump_stop_stiffness_n_per_m",
		"bump_stop_damping_n_s_per_m", "droop_stop_stiffness_n_per_m",
		"droop_stop_damping_n_s_per_m", "drive_torque_per_wheel_nm",
		"brake_torque_per_wheel_nm", "reverse_torque_fraction", "drive_torque_fade_rad_s",
		"rolling_resistance_coefficient", "tire_friction_scale", "max_steer_angle_rad",
		"steer_servo_natural_frequency_rad_s", "steer_servo_damping_ratio",
		"hull_contact_stiffness_n_per_m", "hull_contact_damping_n_s_per_m",
		"hull_contact_friction_scale",
	]
	for key in scalars:
		if not model.has(key) or not is_finite(float(model[key])):
			return false
	var positive := [
		"sprung_mass_kg", "unsprung_mass_kg", "wheel_spin_inertia_kg_m2", "arm_length_m",
		"tire_radius_m", "suspension_stiffness_n_per_m", "tire_stiffness_n_per_m",
		"tire_slip_relaxation_s", "travel_droop_m", "travel_bump_m",
		"bump_stop_stiffness_n_per_m", "droop_stop_stiffness_n_per_m",
		"max_steer_angle_rad", "steer_servo_natural_frequency_rad_s",
		"hull_contact_stiffness_n_per_m",
	]
	for key in positive:
		if float(model[key]) <= 0.0:
			return false
	var nonnegative := [
		"gravity_m_per_s2", "arm_inner_offset_m", "cg_height_above_chassis_datum_m",
		"wheel_center_rest_below_chassis_datum_m", "suspension_damping_n_s_per_m",
		"tire_damping_n_s_per_m", "bump_stop_damping_n_s_per_m", "droop_stop_damping_n_s_per_m",
		"drive_torque_per_wheel_nm", "brake_torque_per_wheel_nm", "reverse_torque_fraction",
		"drive_torque_fade_rad_s", "rolling_resistance_coefficient", "tire_friction_scale",
		"steer_servo_damping_ratio", "hull_contact_damping_n_s_per_m", "hull_contact_friction_scale",
	]
	for key in nonnegative:
		if float(model[key]) < 0.0:
			return false
	if not model.has("sprung_inertia_kg_m2") or not model.has("corner_x_m") or not model.has("corner_y_m"):
		return false
	var inertia: PackedFloat64Array = model["sprung_inertia_kg_m2"]
	var corner_x: PackedFloat64Array = model["corner_x_m"]
	var corner_y: PackedFloat64Array = model["corner_y_m"]
	if inertia.size() != 6 or corner_x.size() != CORNER_COUNT or corner_y.size() != CORNER_COUNT:
		return false
	if not _finite_array(inertia) or not _finite_array(corner_x) or not _finite_array(corner_y):
		return false
	if inertia[0] <= 0.0 or inertia[1] <= 0.0 or inertia[2] <= 0.0:
		return false
	if not model.has("hull_probe_centers_frd_m") or not model.has("hull_probe_radii_m"):
		return false
	var centers: PackedFloat64Array = model["hull_probe_centers_frd_m"]
	var radii: PackedFloat64Array = model["hull_probe_radii_m"]
	if centers.is_empty() or centers.size() % 3 != 0 or radii.size() * 3 != centers.size():
		return false
	if not _finite_array(centers) or not _finite_array(radii):
		return false
	for radius in radii:
		if radius <= 0.0:
			return false
	for corner in CORNER_COUNT:
		if corner_y[corner] == 0.0 or absf(corner_x[corner]) >= 10.0 or absf(corner_y[corner]) >= 10.0:
			return false
	return true


static func _valid_controls(controls: Dictionary) -> bool:
	if not controls.has("throttle") or not controls.has("steering") or not controls.has("brake") or not controls.has("reverse"):
		return false
	var throttle := float(controls["throttle"])
	var steering := float(controls["steering"])
	var brake := float(controls["brake"])
	return is_finite(throttle) and throttle >= 0.0 and throttle <= 1.0 \
		and is_finite(steering) and steering >= -1.0 and steering <= 1.0 \
		and is_finite(brake) and brake >= 0.0 and brake <= 1.0 \
		and typeof(controls["reverse"]) == TYPE_BOOL


static func _valid_pose(pose: Dictionary) -> bool:
	for key in ["north_m", "east_m", "heading_rad", "vehicle_up_m"]:
		if not pose.has(key) or not is_finite(float(pose[key])):
			return false
	return true


static func _valid_attitude(state: PackedFloat64Array) -> bool:
	var q := _state_quaternion(state)
	var length := M.norm(q)
	return is_finite(length) and length > 1.0e-10 and absf(length - 1.0) < 1.0e-3


static func _state_quaternion(state: PackedFloat64Array) -> PackedFloat64Array:
	return M.quat(state[ATT], state[ATT + 1], state[ATT + 2], state[ATT + 3])


static func _quaternion_rate_component(state: PackedFloat64Array, rate: PackedFloat64Array, component: int) -> float:
	var qdot := M.q_mul(_state_quaternion(state), M.quat(0.0, rate[0], rate[1], rate[2]))
	return 0.5 * qdot[component]


static func _slice3(state: PackedFloat64Array, index: int) -> PackedFloat64Array:
	return PackedFloat64Array([state[index], state[index + 1], state[index + 2]])


static func _symmetric_inertia_mul(inertia: PackedFloat64Array, value: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([
		inertia[0] * value[0] + inertia[3] * value[1] + inertia[4] * value[2],
		inertia[3] * value[0] + inertia[1] * value[1] + inertia[5] * value[2],
		inertia[4] * value[0] + inertia[5] * value[1] + inertia[2] * value[2],
	])


static func _add_scaled_vector(target: PackedFloat64Array, value: PackedFloat64Array, scale: float) -> void:
	for i in target.size():
		target[i] += scale * value[i]


static func _static_travel(model: Dictionary) -> float:
	if float(model["gravity_m_per_s2"]) <= 0.0:
		return 0.0
	return float(model["sprung_mass_kg"]) * float(model["gravity_m_per_s2"]) \
		/ (4.0 * float(model["suspension_stiffness_n_per_m"]))


static func _check_static_spawn_patch(
	model: Dictionary,
	road: Callable,
	north_m: float,
	east_m: float,
	heading_rad: float,
	travel: float,
) -> Dictionary:
	var arm_length := float(model["arm_length_m"])
	if absf(travel) >= arm_length:
		return _failure("Static suspension travel reaches the A-arm singularity")
	var q := M.q_from_euler(heading_rad, 0.0, 0.0)
	var x: PackedFloat64Array = model["corner_x_m"]
	var y: PackedFloat64Array = model["corner_y_m"]
	var heights := PackedFloat64Array()
	heights.resize(CORNER_COUNT)
	var mean_height := 0.0
	for corner in CORNER_COUNT:
		var side := signf(y[corner])
		var lateral_offset := M.sqrt_(arm_length * arm_length - travel * travel)
		var r := PackedFloat64Array([
			x[corner],
			y[corner] + side * (lateral_offset - arm_length),
			float(model["cg_height_above_chassis_datum_m"])
				+ float(model["wheel_center_rest_below_chassis_datum_m"]) - travel,
		])
		var world_offset := M.q_rotate(q, r)
		var sample_result := _sample_surface(road, north_m + world_offset[0], east_m + world_offset[1])
		if not bool(sample_result["ok"]):
			return _failure("Could not sample a spawn tire patch: " + str(sample_result["error"]))
		var surface: Dictionary = sample_result["surface"]
		var normal: PackedFloat64Array = surface["normal_ned"]
		if M.norm(M.sub(normal, PackedFloat64Array([0.0, 0.0, -1.0]))) > 1.0e-5:
			return _failure("Static spawn requires an upward level surface")
		heights[corner] = float(surface["height_m"])
		mean_height += heights[corner] / float(CORNER_COUNT)
	for corner in CORNER_COUNT:
		if absf(heights[corner] - mean_height) > 1.0e-4:
			return _failure("Static spawn requires a flat patch across all four tires")
	return {"ok": true, "mean_height_m": mean_height, "corner_heights_m": heights}


static func _energy_from_terms(
	state: PackedFloat64Array,
	model: Dictionary,
	body_rate: PackedFloat64Array,
	hub_kinetic: float,
	rotor_kinetic: float,
	gravity_potential: float,
	spring_energy: float,
	tire_energy: float,
	hull_energy: float,
) -> float:
	var body_velocity := _slice3(state, VEL)
	var energy_value := (
		0.5 * float(model["sprung_mass_kg"]) * M.dot(body_velocity, body_velocity)
		+ 0.5 * M.dot(body_rate, _symmetric_inertia_mul(model["sprung_inertia_kg_m2"], body_rate))
		+ hub_kinetic + rotor_kinetic + gravity_potential + spring_energy + tire_energy + hull_energy
	)
	return energy_value


static func _finite_array(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
