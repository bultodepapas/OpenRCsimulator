extends RefCounted
## RCV-04b small-angle seven-DOF vertical support bench, not a six-DOF truck.
## Coordinates use x forward, y left, z up. Positive roll about +x raises the
## left side; positive pitch about +y lowers the front. State positions are
## [z, roll, pitch, zu_FL, zu_FR, zu_RL, zu_RR], followed by their rates.
## The four hubs move vertically only. Roll/pitch inertias are fixed effective
## rig values; this omits full multibody, lateral/longitudinal, and hub-rotation
## coupling. Road heights and all corner arrays use FL, FR, RL, RR order.
## Parameters are prevalidated by the caller; no travel stops or tire damping.
## State inputs have 14 values and road samples have four finite values. `step`
## assumes finite time, positive dt, and a deterministic road callback.

const Integrator := preload("res://physics/integrator.gd")

const HEAVE := 0
const ROLL := 1
const PITCH := 2
const HUB_FL := 3
const DOF_COUNT := 7
const RATE_OFFSET := 7
const STATE_SIZE := 14
const CORNER_COUNT := 4
const SUBSTEPS_PER_TICK := 2


static func derivative(
	state: PackedFloat64Array,
	p: Dictionary,
	road_height: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
) -> PackedFloat64Array:
	var evaluated := _evaluate(state, p, road_height)
	var generalized_load: PackedFloat64Array = evaluated["generalized_suspension_load"]
	var suspension_force: PackedFloat64Array = evaluated["suspension_force_n"]
	var tire_force: PackedFloat64Array = evaluated["tire_force_n"]
	var sprung_mass := float(p["sprung_mass_kg"])
	var unsprung_mass := float(p["unsprung_mass_kg"])
	var gravity := float(p["gravity_m_per_s2"])
	var roll_inertia := float(p["roll_inertia_kg_m2"])
	var pitch_inertia := float(p["pitch_inertia_kg_m2"])

	var result := PackedFloat64Array()
	result.resize(STATE_SIZE)
	for degree in DOF_COUNT:
		result[degree] = state[RATE_OFFSET + degree]
	result[RATE_OFFSET + HEAVE] = generalized_load[HEAVE] / sprung_mass - gravity
	result[RATE_OFFSET + ROLL] = generalized_load[ROLL] / roll_inertia
	result[RATE_OFFSET + PITCH] = generalized_load[PITCH] / pitch_inertia
	for corner in CORNER_COUNT:
		result[RATE_OFFSET + HUB_FL + corner] = (
			(tire_force[corner] - suspension_force[corner]) / unsprung_mass - gravity
		)
	return result


static func loads(
	state: PackedFloat64Array,
	p: Dictionary,
	road_height: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
) -> Dictionary:
	return _evaluate(state, p, road_height)


static func energy(
	state: PackedFloat64Array,
	p: Dictionary,
	road_height: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
) -> float:
	var evaluated := _evaluate(state, p, road_height)
	var suspension_compression: PackedFloat64Array = evaluated["suspension_compression_m"]
	var tire_compression: PackedFloat64Array = evaluated["tire_compression_m"]
	var sprung_mass := float(p["sprung_mass_kg"])
	var unsprung_mass := float(p["unsprung_mass_kg"])
	var suspension_stiffness := float(p["suspension_stiffness_n_per_m"])
	var tire_stiffness := float(p["tire_stiffness_n_per_m"])
	var gravity := float(p["gravity_m_per_s2"])
	var roll_inertia := float(p["roll_inertia_kg_m2"])
	var pitch_inertia := float(p["pitch_inertia_kg_m2"])

	var total_energy := (
		0.5 * sprung_mass * state[RATE_OFFSET + HEAVE] * state[RATE_OFFSET + HEAVE]
		+ 0.5 * roll_inertia * state[RATE_OFFSET + ROLL] * state[RATE_OFFSET + ROLL]
		+ 0.5 * pitch_inertia * state[RATE_OFFSET + PITCH] * state[RATE_OFFSET + PITCH]
		+ sprung_mass * gravity * state[HEAVE]
	)
	for corner in CORNER_COUNT:
		var hub_state_index := HUB_FL + corner
		var hub_rate_index := RATE_OFFSET + hub_state_index
		total_energy += (
			0.5 * unsprung_mass * state[hub_rate_index] * state[hub_rate_index]
			+ unsprung_mass * gravity * state[hub_state_index]
			+ 0.5 * suspension_stiffness * suspension_compression[corner] * suspension_compression[corner]
			+ 0.5 * tire_stiffness * tire_compression[corner] * tire_compression[corner]
		)
	return total_energy


## Positive gravity requires positive tire support at all four corners. At zero
## gravity, a planar road gets a neutral, zero-preload pose; a nonplanar road
## cannot satisfy this rig's four-corner static-support assumptions.
static func equilibrium(
	p: Dictionary,
	road_height: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0]),
) -> Dictionary:
	if not _valid_road(road_height):
		return _equilibrium_failure("Road height must contain four finite FL, FR, RL, RR values")

	var sprung_mass := float(p["sprung_mass_kg"])
	var unsprung_mass := float(p["unsprung_mass_kg"])
	var suspension_stiffness := float(p["suspension_stiffness_n_per_m"])
	var tire_stiffness := float(p["tire_stiffness_n_per_m"])
	var gravity := float(p["gravity_m_per_s2"])
	var rest_length := float(p["suspension_rest_length_m"])
	var tire_radius := float(p["tire_radius_m"])
	var corner_x: PackedFloat64Array = p["corner_x_m"]
	var corner_y: PackedFloat64Array = p["corner_y_m"]
	if gravity == 0.0:
		return _zero_gravity_equilibrium(p, road_height)
	var effective_stiffness := (
		suspension_stiffness * tire_stiffness / (suspension_stiffness + tire_stiffness)
	)

	var matrix := PackedFloat64Array()
	matrix.resize(9)
	var right_hand_side := PackedFloat64Array([-sprung_mass * gravity, 0.0, 0.0])
	for corner in CORNER_COUNT:
		var basis := PackedFloat64Array([1.0, corner_y[corner], -corner_x[corner]])
		var offset := (
			rest_length + tire_radius + road_height[corner]
			- unsprung_mass * gravity / tire_stiffness
		)
		for row in 3:
			right_hand_side[row] += basis[row] * effective_stiffness * offset
			for column in 3:
				matrix[row * 3 + column] += (
					effective_stiffness * basis[row] * basis[column]
				)

	var solution := _solve_3x3(matrix, right_hand_side)
	if not bool(solution["ok"]):
		return _equilibrium_failure(str(solution["error"]))
	var body_position: PackedFloat64Array = solution["position"]
	var state := PackedFloat64Array()
	state.resize(STATE_SIZE)
	state[HEAVE] = body_position[0]
	state[ROLL] = body_position[1]
	state[PITCH] = body_position[2]

	for corner in CORNER_COUNT:
		var mount_height := (
			body_position[0] + corner_y[corner] * body_position[1]
			- corner_x[corner] * body_position[2]
		)
		var offset := (
			rest_length + tire_radius + road_height[corner]
			- unsprung_mass * gravity / tire_stiffness
		)
		var spring_force := effective_stiffness * (offset - mount_height)
		var tire_load := spring_force + unsprung_mass * gravity
		if not is_finite(spring_force) or not is_finite(tire_load):
			return _equilibrium_failure("Equilibrium produced a non-finite corner load")
		if tire_load <= 0.0:
			return _equilibrium_failure("Equilibrium requires positive tire load at all four corners")
		state[HUB_FL + corner] = (
			tire_radius + road_height[corner] - tire_load / tire_stiffness
		)
		if not is_finite(state[HUB_FL + corner]):
			return _equilibrium_failure("Equilibrium produced a non-finite hub height")

	return {
		"ok": true,
		"errors": PackedStringArray(),
		"state": state,
	}


static func step(
	state: PackedFloat64Array,
	p: Dictionary,
	t: float,
	dt: float,
	road: Callable,
) -> PackedFloat64Array:
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
	# The road callback must be deterministic by time. The shared rigid-body
	# RK4 finalizer normalizes a quaternion, so this state uses axpy only.
	var k1 := derivative(state, p, road.call(t))
	var stage_2 := Integrator.axpy(state, 0.5 * dt, k1)
	var k2 := derivative(stage_2, p, road.call(t + 0.5 * dt))
	var stage_3 := Integrator.axpy(state, 0.5 * dt, k2)
	var k3 := derivative(stage_3, p, road.call(t + 0.5 * dt))
	var stage_4 := Integrator.axpy(state, dt, k3)
	var k4 := derivative(stage_4, p, road.call(t + dt))

	var weighted := Integrator.axpy(k1, 2.0, k2)
	weighted = Integrator.axpy(weighted, 2.0, k3)
	weighted = Integrator.axpy(weighted, 1.0, k4)
	return Integrator.axpy(state, dt / 6.0, weighted)


static func _evaluate(
	state: PackedFloat64Array,
	p: Dictionary,
	road_height: PackedFloat64Array,
) -> Dictionary:
	var suspension_stiffness := float(p["suspension_stiffness_n_per_m"])
	var suspension_damping := float(p["suspension_damping_n_s_per_m"])
	var tire_stiffness := float(p["tire_stiffness_n_per_m"])
	var rest_length := float(p["suspension_rest_length_m"])
	var tire_radius := float(p["tire_radius_m"])
	var corner_x: PackedFloat64Array = p["corner_x_m"]
	var corner_y: PackedFloat64Array = p["corner_y_m"]

	var mount_height := PackedFloat64Array()
	var mount_speed := PackedFloat64Array()
	var suspension_compression := PackedFloat64Array()
	var tire_compression := PackedFloat64Array()
	var suspension_force := PackedFloat64Array()
	var tire_force := PackedFloat64Array()
	var damper_loss := PackedFloat64Array()
	mount_height.resize(CORNER_COUNT)
	mount_speed.resize(CORNER_COUNT)
	suspension_compression.resize(CORNER_COUNT)
	tire_compression.resize(CORNER_COUNT)
	suspension_force.resize(CORNER_COUNT)
	tire_force.resize(CORNER_COUNT)
	damper_loss.resize(CORNER_COUNT)
	var generalized_load := PackedFloat64Array([0.0, 0.0, 0.0])

	for corner in CORNER_COUNT:
		var hub_state_index := HUB_FL + corner
		var hub_rate_index := RATE_OFFSET + hub_state_index
		mount_height[corner] = (
			state[HEAVE] + corner_y[corner] * state[ROLL]
			- corner_x[corner] * state[PITCH]
		)
		mount_speed[corner] = (
			state[RATE_OFFSET + HEAVE] + corner_y[corner] * state[RATE_OFFSET + ROLL]
			- corner_x[corner] * state[RATE_OFFSET + PITCH]
		)
		suspension_compression[corner] = (
			rest_length - mount_height[corner] + state[hub_state_index]
		)
		var damper_speed := state[hub_rate_index] - mount_speed[corner]
		suspension_force[corner] = (
			suspension_stiffness * suspension_compression[corner]
			+ suspension_damping * damper_speed
		)
		tire_compression[corner] = maxf(
			tire_radius + road_height[corner] - state[hub_state_index],
			0.0,
		)
		tire_force[corner] = tire_stiffness * tire_compression[corner]
		damper_loss[corner] = suspension_damping * damper_speed * damper_speed
		generalized_load[HEAVE] += suspension_force[corner]
		generalized_load[ROLL] += corner_y[corner] * suspension_force[corner]
		generalized_load[PITCH] += -corner_x[corner] * suspension_force[corner]

	var in_contact := PackedByteArray()
	in_contact.resize(CORNER_COUNT)
	for corner in CORNER_COUNT:
		in_contact[corner] = 1 if tire_compression[corner] > 0.0 else 0

	return {
		"suspension_force_n": suspension_force,
		"tire_force_n": tire_force,
		"suspension_compression_m": suspension_compression,
		"tire_compression_m": tire_compression,
		"mount_height_m": mount_height,
		"mount_speed_m_per_s": mount_speed,
		"damper_loss_w": damper_loss,
		"generalized_suspension_load": generalized_load,
		"in_contact": in_contact,
	}


static func _solve_3x3(matrix: PackedFloat64Array, right_hand_side: PackedFloat64Array) -> Dictionary:
	if matrix.size() != 9 or right_hand_side.size() != 3:
		return {"ok": false, "error": "Equilibrium matrix has invalid dimensions"}
	var augmented := PackedFloat64Array()
	augmented.resize(12)
	var matrix_scale := 0.0
	for row in 3:
		for column in 3:
			var value := matrix[row * 3 + column]
			if not is_finite(value):
				return {"ok": false, "error": "Equilibrium matrix is non-finite"}
			augmented[row * 4 + column] = value
			matrix_scale = maxf(matrix_scale, absf(value))
		if not is_finite(right_hand_side[row]):
			return {"ok": false, "error": "Equilibrium target is non-finite"}
		augmented[row * 4 + 3] = right_hand_side[row]
	if matrix_scale == 0.0:
		return {"ok": false, "error": "Equilibrium matrix is singular"}

	for pivot_column in 3:
		var pivot_row := pivot_column
		for row in range(pivot_column + 1, 3):
			if absf(augmented[row * 4 + pivot_column]) > absf(augmented[pivot_row * 4 + pivot_column]):
				pivot_row = row
		var pivot_value := augmented[pivot_row * 4 + pivot_column]
		if not is_finite(pivot_value) or absf(pivot_value) <= matrix_scale * 1.0e-12:
			return {"ok": false, "error": "Equilibrium matrix is singular at float64 precision"}
		if pivot_row != pivot_column:
			for column in 4:
				var swap_value := augmented[pivot_column * 4 + column]
				augmented[pivot_column * 4 + column] = augmented[pivot_row * 4 + column]
				augmented[pivot_row * 4 + column] = swap_value

		pivot_value = augmented[pivot_column * 4 + pivot_column]
		for column in range(pivot_column, 4):
			augmented[pivot_column * 4 + column] /= pivot_value
		for row in 3:
			if row == pivot_column:
				continue
			var factor := augmented[row * 4 + pivot_column]
			for column in range(pivot_column, 4):
				augmented[row * 4 + column] -= factor * augmented[pivot_column * 4 + column]

	var position := PackedFloat64Array([
		augmented[3],
		augmented[7],
		augmented[11],
	])
	for value in position:
		if not is_finite(value):
			return {"ok": false, "error": "Equilibrium solution is non-finite"}
	return {"ok": true, "position": position}


static func _zero_gravity_equilibrium(
	p: Dictionary,
	road_height: PackedFloat64Array,
) -> Dictionary:
	# Fit the body plane to the zero-force mount height at each corner. The hub
	# center then sits at the tire radius above the road and both spring and tire
	# forces are zero. A nonplanar road leaves a nonzero residual; accepting it
	# would imply hidden preload or a tensile/compressive contact force at g=0.
	var rest_length := float(p["suspension_rest_length_m"])
	var tire_radius := float(p["tire_radius_m"])
	var suspension_stiffness := float(p["suspension_stiffness_n_per_m"])
	var corner_x: PackedFloat64Array = p["corner_x_m"]
	var corner_y: PackedFloat64Array = p["corner_y_m"]
	var matrix := PackedFloat64Array()
	matrix.resize(9)
	var right_hand_side := PackedFloat64Array([0.0, 0.0, 0.0])
	for corner in CORNER_COUNT:
		var basis := PackedFloat64Array([1.0, corner_y[corner], -corner_x[corner]])
		var target_height := rest_length + tire_radius + road_height[corner]
		for row in 3:
			right_hand_side[row] += basis[row] * target_height
			for column in 3:
				matrix[row * 3 + column] += basis[row] * basis[column]
	var solution := _solve_3x3(matrix, right_hand_side)
	if not bool(solution["ok"]):
		return _equilibrium_failure(str(solution["error"]))
	var body_position: PackedFloat64Array = solution["position"]
	var state := PackedFloat64Array()
	state.resize(STATE_SIZE)
	state[HEAVE] = body_position[0]
	state[ROLL] = body_position[1]
	state[PITCH] = body_position[2]
	for corner in CORNER_COUNT:
		state[HUB_FL + corner] = tire_radius + road_height[corner]
		if not is_finite(state[HUB_FL + corner]):
			return _equilibrium_failure("Zero-gravity pose produced a non-finite hub height")

	var evaluated := _evaluate(state, p, road_height)
	var spring_force: PackedFloat64Array = evaluated["suspension_force_n"]
	var scale := maxf(1.0, absf(rest_length) + absf(tire_radius))
	for corner in CORNER_COUNT:
		scale = maxf(scale, absf(road_height[corner]))
		var mount_height: PackedFloat64Array = evaluated["mount_height_m"]
		scale = maxf(scale, absf(mount_height[corner]))
		scale = maxf(scale, absf(state[HUB_FL + corner]))
	var force_tolerance := 128.0 * 2.220446049250313e-16 * maxf(
		1.0,
		suspension_stiffness * scale,
	)
	for force in spring_force:
		if not is_finite(force) or absf(force) > force_tolerance:
			return _equilibrium_failure(
				"Zero-gravity equilibrium requires a planar road and zero spring preload"
			)
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"state": state,
	}


static func _valid_road(road_height: PackedFloat64Array) -> bool:
	if road_height.size() != CORNER_COUNT:
		return false
	for height in road_height:
		if not is_finite(height):
			return false
	return true


static func _equilibrium_failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"errors": PackedStringArray([message]),
		"state": PackedFloat64Array(),
	}
