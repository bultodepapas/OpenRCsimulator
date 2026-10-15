class_name GroundVehicleDamage
extends RefCounted
## Bounded deterministic gameplay damage estimate for the MT8 ground vehicle.
## This sidecar observes accepted float64 state/telemetry; it never feeds forces
## into VehicleDynamics or changes the contact solver.

const STATE_SIZE := 19
const SNAPSHOT_SIZE := STATE_SIZE
const SNAPSHOT_VERSION := 2
const MAX_EPISODE_ENERGY_J := 2000.0
const MAX_LAST_IMPACT_ENERGY_J := 2000.0
const BODY_DAMAGE_ENERGY_J := 180.0
const DRIVE_DAMAGE_ENERGY_J := 300.0
const SUSPENSION_DAMAGE_ENERGY_J := 20.0
const DAMAGE_EPSILON_J := 1.0e-9
const MIN_EPISODE_DAMAGE_ENERGY_J := 2.0
const MIN_CONTACT_SPEED_M_PER_S := 0.4
const MIN_IMPACT_VELOCITY_CHANGE_M_PER_S := 0.05
const SEVERE_BOTTOMING_RATE_M_PER_S := 1.8
const BOTTOMING_TRIGGER_RATIO := 0.96
const BOTTOMING_RELEASE_RATIO := 0.72
const MIN_OVERTRAVEL_DAMAGE_M := 0.004
const CONTACT_POWER_CAP_W := 10000.0
const M := preload("res://physics/math3d.gd")

const STATE_LAYOUT := [
	"body_front_damage_fraction",
	"body_rear_damage_fraction",
	"body_left_damage_fraction",
	"body_right_damage_fraction",
	"body_bottom_damage_fraction",
	"suspension_damage_fl_fraction",
	"suspension_damage_fr_fraction",
	"suspension_damage_rl_fraction",
	"suspension_damage_rr_fraction",
	"drive_damage_fraction",
	"hull_contact_active_flag",
	"wall_contact_active_flag",
	"hull_episode_energy_j",
	"wall_episode_energy_j",
	"bottoming_latched_fl_flag",
	"bottoming_latched_fr_flag",
	"bottoming_latched_rl_flag",
	"bottoming_latched_rr_flag",
	"last_impact_energy_j",
]

const BODY_FRONT := 0
const BODY_REAR := 1
const BODY_LEFT := 2
const BODY_RIGHT := 3
const BODY_BOTTOM := 4
const SUSPENSION_BASE := 5
const DRIVE := 9
const HULL_ACTIVE := 10
const WALL_ACTIVE := 11
const HULL_EPISODE_ENERGY := 12
const WALL_EPISODE_ENERGY := 13
const BOTTOMING_LATCH_BASE := 14
const LAST_IMPACT_ENERGY := 18

const CORNER_COUNT := 4
const STATE_WIDTH := 31
const STATE_VEL := 3
const STATE_RATE := 10
const STATE_TRAVEL := 13
const STATE_TRAVEL_RATE := 17

var _values := PackedFloat64Array()


func _init() -> void:
	reset()


func reset() -> void:
	_values = PackedFloat64Array()
	_values.resize(STATE_SIZE)
	for index in STATE_SIZE:
		_values[index] = 0.0


## Observe one accepted simulation tick. Inputs are validated before any local
## state is committed, so false means the previous snapshot remains byte-equal.
func advance(
	previous_state_value: Variant,
	next_state_value: Variant,
	previous_telemetry: Dictionary,
	next_telemetry: Dictionary,
	model: Dictionary,
	dt: float,
) -> bool:
	if not _inputs_are_valid(previous_state_value, next_state_value,
			previous_telemetry, next_telemetry, model, dt):
		return false
	var previous_state: PackedFloat64Array = previous_state_value
	var next_state: PackedFloat64Array = next_state_value
	var next_values := _values.duplicate()
	var previous_hull := _hull_contact(previous_telemetry)
	var next_hull := _hull_contact(next_telemetry)
	var previous_wall := _wall_contact(previous_telemetry)
	var next_wall := _wall_contact(next_telemetry)
	var previous_speed := _linear_speed(previous_state)
	var next_speed := _linear_speed(next_state)
	var impact_speed_drop := maxf(0.0, previous_speed - next_speed)
	# Wall contacts also appear in hull_in_contact. Keep the wall episode as the
	# single source for that tick instead of double-counting the same body hit.
	previous_hull = previous_hull and not previous_wall
	next_hull = next_hull and not next_wall
	var measured_energy_loss := _contact_energy_loss(previous_telemetry, next_telemetry, dt)
	if not is_finite(measured_energy_loss):
		return false
	var energy_loss_j := minf(measured_energy_loss, CONTACT_POWER_CAP_W * dt)
	var contact_speed := maxf(previous_speed, next_speed)
	var region := _impact_region(previous_state, next_state)
	var wall_episode_present := previous_wall or next_wall
	var hull_episode_present := (previous_hull or next_hull) and not wall_episode_present
	if wall_episode_present:
		var previous_hull_wall := _hull_wall_contact(previous_telemetry)
		var next_hull_wall := _hull_wall_contact(next_telemetry)
		if not previous_wall:
			next_values[WALL_EPISODE_ENERGY] = 0.0
		var energy_before := next_values[WALL_EPISODE_ENERGY]
		var added_wall_energy := _episode_energy_increment(
			energy_loss_j, contact_speed, impact_speed_drop, energy_before,
		)
		next_values[WALL_EPISODE_ENERGY] += added_wall_energy
		var damaging_wall_energy := _above_episode_threshold(
			energy_before, next_values[WALL_EPISODE_ENERGY],
		)
		if damaging_wall_energy > DAMAGE_EPSILON_J:
			if previous_hull_wall or next_hull_wall:
				_apply_hull_impact(next_values, region, damaging_wall_energy)
			else:
				_apply_wheel_wall_impact(next_values, damaging_wall_energy,
					previous_telemetry, next_telemetry)
		if added_wall_energy > 0.0:
			next_values[LAST_IMPACT_ENERGY] = next_values[WALL_EPISODE_ENERGY]
		if not next_wall:
			next_values[WALL_EPISODE_ENERGY] = 0.0
	else:
		next_values[WALL_EPISODE_ENERGY] = 0.0

	if hull_episode_present:
		if not previous_hull:
			next_values[HULL_EPISODE_ENERGY] = 0.0
		var energy_before := next_values[HULL_EPISODE_ENERGY]
		var added_hull_energy := _episode_energy_increment(
			energy_loss_j, contact_speed, impact_speed_drop, energy_before,
		)
		next_values[HULL_EPISODE_ENERGY] += added_hull_energy
		var damaging_hull_energy := _above_episode_threshold(
			energy_before, next_values[HULL_EPISODE_ENERGY],
		)
		if damaging_hull_energy > DAMAGE_EPSILON_J:
			_apply_hull_impact(next_values, region, damaging_hull_energy)
		if added_hull_energy > 0.0:
			next_values[LAST_IMPACT_ENERGY] = next_values[HULL_EPISODE_ENERGY]
		if not next_hull:
			next_values[HULL_EPISODE_ENERGY] = 0.0
	else:
		next_values[HULL_EPISODE_ENERGY] = 0.0

	for corner in CORNER_COUNT:
		var latch_index := BOTTOMING_LATCH_BASE + corner
		var bump_limit := float(model["travel_bump_m"])
		var travel_before := previous_state[STATE_TRAVEL + corner]
		var travel_after := next_state[STATE_TRAVEL + corner]
		var travel_rate_before := previous_state[STATE_TRAVEL_RATE + corner]
		var travel_rate_after := next_state[STATE_TRAVEL_RATE + corner]
		if travel_after < bump_limit * BOTTOMING_RELEASE_RATIO and travel_rate_after <= 0.0:
			next_values[latch_index] = 0.0
		if next_values[latch_index] < 0.5 and _severe_bottoming(
				travel_before, travel_after, travel_rate_before, travel_rate_after,
				bump_limit, float(model["bump_stop_stiffness_n_per_m"])):
			var quarter_mass := float(model["sprung_mass_kg"]) * 0.25 + float(model["unsprung_mass_kg"])
			var compression_speed := maxf(travel_rate_before, travel_rate_after)
			var excess_travel := maxf(0.0, travel_after - bump_limit)
			var event_energy := 0.5 * quarter_mass * compression_speed * compression_speed \
				+ 0.5 * float(model["bump_stop_stiffness_n_per_m"]) * excess_travel * excess_travel
			if not is_finite(event_energy):
				return false
			event_energy = clampf(event_energy, 0.0, MAX_LAST_IMPACT_ENERGY_J)
			if event_energy > DAMAGE_EPSILON_J:
				next_values[SUSPENSION_BASE + corner] = clampf(
					next_values[SUSPENSION_BASE + corner] + event_energy / SUSPENSION_DAMAGE_ENERGY_J,
					0.0, 1.0,
				)
				next_values[LAST_IMPACT_ENERGY] = event_energy
			next_values[latch_index] = 1.0

	next_values[HULL_ACTIVE] = 1.0 if next_hull else 0.0
	next_values[WALL_ACTIVE] = 1.0 if next_wall else 0.0
	if not valid_snapshot(next_values):
		return false
	_values = next_values
	return true


func snapshot() -> PackedFloat64Array:
	return _values.duplicate()


static func valid_snapshot(value: Variant) -> bool:
	if typeof(value) != TYPE_PACKED_FLOAT64_ARRAY or value.size() != STATE_SIZE:
		return false
	var values: PackedFloat64Array = value
	for index in values.size():
		var item := values[index]
		if not is_finite(item):
			return false
		if index <= DRIVE:
			if item < 0.0 or item > 1.0:
				return false
	if values[HULL_ACTIVE] not in [0.0, 1.0] or values[WALL_ACTIVE] not in [0.0, 1.0]:
		return false
	if values[HULL_EPISODE_ENERGY] < 0.0 or values[HULL_EPISODE_ENERGY] > MAX_EPISODE_ENERGY_J \
			or values[WALL_EPISODE_ENERGY] < 0.0 or values[WALL_EPISODE_ENERGY] > MAX_EPISODE_ENERGY_J \
			or values[LAST_IMPACT_ENERGY] < 0.0 or values[LAST_IMPACT_ENERGY] > MAX_LAST_IMPACT_ENERGY_J:
		return false
	if values[HULL_ACTIVE] == 0.0 and values[HULL_EPISODE_ENERGY] != 0.0 \
			or values[WALL_ACTIVE] == 0.0 and values[WALL_EPISODE_ENERGY] != 0.0:
		return false
	for corner in CORNER_COUNT:
		if values[BOTTOMING_LATCH_BASE + corner] not in [0.0, 1.0]:
			return false
	return true


func restore_snapshot(value: Variant) -> bool:
	if not valid_snapshot(value):
		return false
	var candidate: PackedFloat64Array = value
	_values = candidate.duplicate()
	return true


## Return a presentation projection; these keys contain no authority over
## physics. The Session applies only drive_scale to propulsion commands.
func visual_state() -> Dictionary:
	var body_damage := 0.0
	var suspension_damage := 0.0
	for index in 5:
		body_damage = maxf(body_damage, _values[index])
	for corner in CORNER_COUNT:
		suspension_damage = maxf(suspension_damage, _values[SUSPENSION_BASE + corner])
	var drive_scale := clampf(1.0 - _values[DRIVE], 0.0, 1.0)
	var stage := "intact"
	if drive_scale <= 0.02:
		stage = "disabled"
	elif maxf(body_damage, suspension_damage) >= 0.28:
		stage = "damaged"
	elif maxf(body_damage, suspension_damage) >= 0.04:
		stage = "scuffed"
	return {
		"body_damage": body_damage,
		"body_front_damage": _values[BODY_FRONT],
		"body_rear_damage": _values[BODY_REAR],
		"body_left_damage": _values[BODY_LEFT],
		"body_right_damage": _values[BODY_RIGHT],
		"body_bottom_damage": _values[BODY_BOTTOM],
		"suspension_damage": suspension_damage,
		"suspension_damage_by_corner": PackedFloat64Array([
			_values[SUSPENSION_BASE], _values[SUSPENSION_BASE + 1],
			_values[SUSPENSION_BASE + 2], _values[SUSPENSION_BASE + 3],
		]),
		"drive_scale": drive_scale,
		"stage": stage,
		"last_impact_energy_j": _values[LAST_IMPACT_ENERGY],
	}


## Propulsion derating is the only operational damage effect. Steering, braking,
## wheel state, and contact forces are passed through unchanged.
func effective_controls(controls: Dictionary) -> Dictionary:
	if not _controls_are_valid(controls):
		return {}
	var result := controls.duplicate(true)
	result["throttle"] = float(result["throttle"]) * float(visual_state()["drive_scale"])
	return result


func _inputs_are_valid(
	previous_state_value: Variant,
	next_state_value: Variant,
	previous_telemetry: Dictionary,
	next_telemetry: Dictionary,
	model: Dictionary,
	dt: float,
) -> bool:
	if not valid_snapshot(_values) or not is_finite(dt) or dt <= 0.0 or dt > 1.0 / 30.0:
		return false
	if typeof(previous_state_value) != TYPE_PACKED_FLOAT64_ARRAY \
			or typeof(next_state_value) != TYPE_PACKED_FLOAT64_ARRAY:
		return false
	var previous_state: PackedFloat64Array = previous_state_value
	var next_state: PackedFloat64Array = next_state_value
	if previous_state.size() != STATE_WIDTH or next_state.size() != STATE_WIDTH:
		return false
	for item in previous_state:
		if not is_finite(item):
			return false
	for item in next_state:
		if not is_finite(item):
			return false
	if not _state_quaternion_is_valid(previous_state) or not _state_quaternion_is_valid(next_state):
		return false
	if not is_finite(_linear_speed(previous_state)) or not is_finite(_linear_speed(next_state)):
		return false
	if not _model_is_valid(model):
		return false
	var hull_radii: PackedFloat64Array = model["hull_probe_radii_m"]
	var hull_count := hull_radii.size()
	return _telemetry_is_valid(previous_telemetry, hull_count) \
		and _telemetry_is_valid(next_telemetry, hull_count)


func _model_is_valid(model: Dictionary) -> bool:
	for key in ["sprung_mass_kg", "unsprung_mass_kg", "travel_bump_m", "bump_stop_stiffness_n_per_m"]:
		var value: Variant = model.get(key, NAN)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or typeof(value) == TYPE_BOOL \
				or not is_finite(float(value)):
			return false
	if float(model["sprung_mass_kg"]) <= 0.0 or float(model["unsprung_mass_kg"]) < 0.0 \
			or float(model["travel_bump_m"]) <= 0.0 or float(model["bump_stop_stiffness_n_per_m"]) < 0.0:
		return false
	var inertia: Variant = model.get("sprung_inertia_kg_m2")
	var radii: Variant = model.get("hull_probe_radii_m")
	if not inertia is PackedFloat64Array or inertia.size() != 6 or not _finite_packed(inertia) \
			or not radii is PackedFloat64Array or radii.is_empty() or not _finite_packed(radii):
		return false
	for index in 3:
		if inertia[index] <= 0.0:
			return false
	for radius in radii:
		if radius <= 0.0:
			return false
	return true


func _telemetry_is_valid(value: Dictionary, hull_count: int) -> bool:
	if value.has("environment"):
		var environment: Variant = value.environment
		if typeof(environment) != TYPE_DICTIONARY or typeof(environment.get("power_w")) not in [TYPE_INT, TYPE_FLOAT] \
				or not is_finite(float(environment.power_w)): return false
	if typeof(value.get("ok")) != TYPE_BOOL or not bool(value.ok):
		return false
	for key in ["total_energy_j", "wall_normal_load_n", "wall_friction_power_w"]:
		var scalar: Variant = value.get(key, NAN)
		if typeof(scalar) not in [TYPE_INT, TYPE_FLOAT] or typeof(scalar) == TYPE_BOOL \
				or not is_finite(float(scalar)):
			return false
	if float(value.wall_friction_power_w) > 0.0:
		return false
	var wall_count: Variant = value.get("wall_contact_count", -1)
	if typeof(wall_count) != TYPE_INT or int(wall_count) < 0:
		return false
	if float(value.wall_normal_load_n) < 0.0:
		return false
	var hull_contacts: Variant = value.get("hull_in_contact")
	var wheel_wall_contacts: Variant = value.get("wheel_wall_in_contact")
	var wheel_wall_load: Variant = value.get("wheel_wall_load_n")
	var hull_wall_load: Variant = value.get("hull_wall_load_n")
	var travel: Variant = value.get("suspension_travel_m")
	var suspension_force: Variant = value.get("suspension_force_n")
	if not (hull_contacts is PackedByteArray and hull_contacts.size() == hull_count \
		and wheel_wall_contacts is PackedByteArray and wheel_wall_contacts.size() == CORNER_COUNT \
		and wheel_wall_load is PackedFloat64Array and wheel_wall_load.size() == CORNER_COUNT \
		and _finite_packed(wheel_wall_load) \
		and hull_wall_load is PackedFloat64Array and hull_wall_load.size() == hull_count \
		and _finite_packed(hull_wall_load) \
		and travel is PackedFloat64Array and travel.size() == CORNER_COUNT \
		and _finite_packed(travel) \
		and suspension_force is PackedFloat64Array and suspension_force.size() == CORNER_COUNT \
		and _finite_packed(suspension_force)):
		return false
	var has_wall_contact := false
	for active in hull_contacts:
		if active not in [0, 1]:
			return false
	for active in wheel_wall_contacts:
		if active not in [0, 1]:
			return false
	for load in wheel_wall_load:
		if load < 0.0:
			return false
		has_wall_contact = has_wall_contact or load > 0.0
	for index in hull_count:
		if hull_wall_load[index] < 0.0:
			return false
		if hull_wall_load[index] > 0.0 and hull_contacts[index] == 0:
			return false
		has_wall_contact = has_wall_contact or hull_wall_load[index] > 0.0
	for active in wheel_wall_contacts:
		has_wall_contact = has_wall_contact or active != 0
	return (int(wall_count) > 0) == has_wall_contact \
		and (int(wall_count) > 0) == (float(value.wall_normal_load_n) > 0.0)


func _controls_are_valid(controls: Dictionary) -> bool:
	for key in ["throttle", "steering", "brake"]:
		var value: Variant = controls.get(key, NAN)
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or typeof(value) == TYPE_BOOL \
				or not is_finite(float(value)):
			return false
		if float(value) < -1.0 or float(value) > 1.0:
			return false
	return typeof(controls.get("reverse")) == TYPE_BOOL \
		and float(controls.throttle) >= 0.0 and float(controls.brake) >= 0.0


func _hull_contact(telemetry: Dictionary) -> bool:
	for active in telemetry.hull_in_contact:
		if active != 0:
			return true
	for load in telemetry.hull_wall_load_n:
		if load > 0.0:
			return true
	return false


func _wall_contact(telemetry: Dictionary) -> bool:
	if int(telemetry.get("wall_contact_count", 0)) > 0 or float(telemetry.wall_normal_load_n) > 0.0:
		return true
	for active in telemetry.wheel_wall_in_contact:
		if active != 0:
			return true
	for load in telemetry.wheel_wall_load_n:
		if load > 0.0:
			return true
	return false


func _hull_wall_contact(telemetry: Dictionary) -> bool:
	for load in telemetry.hull_wall_load_n:
		if load > 0.0:
			return true
	return false


func _contact_energy_loss(
	previous_telemetry: Dictionary,
	next_telemetry: Dictionary,
	dt: float,
) -> float:
	var previous_energy := float(previous_telemetry.total_energy_j)
	var next_energy := float(next_telemetry.total_energy_j)
	var wall_friction_work_j := -0.5 * float(previous_telemetry.wall_friction_power_w) * dt \
		- 0.5 * float(next_telemetry.wall_friction_power_w) * dt
	# Fluid work changes mechanical energy without implying a solid-body impact.
	var environment_work_j := 0.5 * (float(previous_telemetry.get("environment", {}).get("power_w", 0.0)) \
		+ float(next_telemetry.get("environment", {}).get("power_w", 0.0))) * dt
	var energy_loss_j := previous_energy - next_energy - wall_friction_work_j + environment_work_j
	if not is_finite(wall_friction_work_j) or not is_finite(energy_loss_j):
		return NAN
	return clampf(energy_loss_j, 0.0, MAX_EPISODE_ENERGY_J)


func _episode_energy_increment(
	energy_loss_j: float,
	contact_speed: float,
	impact_speed_drop: float,
	energy_before: float,
) -> float:
	if contact_speed < MIN_CONTACT_SPEED_M_PER_S \
			or impact_speed_drop < MIN_IMPACT_VELOCITY_CHANGE_M_PER_S:
		return 0.0
	return minf(energy_loss_j, maxf(0.0, MAX_EPISODE_ENERGY_J - energy_before))


func _above_episode_threshold(energy_before: float, energy_after: float) -> float:
	return maxf(0.0, energy_after - MIN_EPISODE_DAMAGE_ENERGY_J) \
		- maxf(0.0, energy_before - MIN_EPISODE_DAMAGE_ENERGY_J)


func _linear_speed(state: PackedFloat64Array) -> float:
	return _stable_norm3(state[STATE_VEL], state[STATE_VEL + 1], state[STATE_VEL + 2])


func _state_quaternion_is_valid(state: PackedFloat64Array) -> bool:
	var scale := 0.0
	for index in 4:
		scale = maxf(scale, absf(state[6 + index]))
	if scale == 0.0 or not is_finite(scale):
		return false
	var norm_scaled := 0.0
	for index in 4:
		var component := state[6 + index] / scale
		norm_scaled += component * component
	var norm := scale * M.sqrt_(norm_scaled)
	return is_finite(norm) and norm > 1.0e-10


func _stable_norm3(x: float, y: float, z: float) -> float:
	var scale := maxf(absf(x), maxf(absf(y), absf(z)))
	if scale == 0.0:
		return 0.0
	var scaled_x := x / scale
	var scaled_y := y / scale
	var scaled_z := z / scale
	return scale * M.sqrt_(scaled_x * scaled_x + scaled_y * scaled_y + scaled_z * scaled_z)


func _impact_region(previous_state: PackedFloat64Array, next_state: PackedFloat64Array) -> int:
	var forward := 0.5 * previous_state[STATE_VEL] + 0.5 * next_state[STATE_VEL]
	var right := 0.5 * previous_state[STATE_VEL + 1] + 0.5 * next_state[STATE_VEL + 1]
	var down := 0.5 * previous_state[STATE_VEL + 2] + 0.5 * next_state[STATE_VEL + 2]
	if absf(down) > maxf(absf(forward), absf(right)):
		return BODY_BOTTOM
	if absf(forward) >= absf(right):
		return BODY_FRONT if forward >= 0.0 else BODY_REAR
	return BODY_RIGHT if right >= 0.0 else BODY_LEFT


func _apply_hull_impact(values: PackedFloat64Array, region: int, energy_j: float) -> void:
	values[region] = clampf(values[region] + energy_j / BODY_DAMAGE_ENERGY_J, 0.0, 1.0)
	values[DRIVE] = clampf(values[DRIVE] + energy_j / DRIVE_DAMAGE_ENERGY_J, 0.0, 1.0)


func _apply_wheel_wall_impact(
	values: PackedFloat64Array,
	energy_j: float,
	previous_telemetry: Dictionary,
	next_telemetry: Dictionary,
) -> void:
	var contact_weights := PackedFloat64Array()
	contact_weights.resize(CORNER_COUNT)
	var total_weight := 0.0
	var previous_load: PackedFloat64Array = previous_telemetry.wheel_wall_load_n
	var next_load: PackedFloat64Array = next_telemetry.wheel_wall_load_n
	var previous_contact: PackedByteArray = previous_telemetry.wheel_wall_in_contact
	var next_contact: PackedByteArray = next_telemetry.wheel_wall_in_contact
	for corner in CORNER_COUNT:
		contact_weights[corner] = maxf(previous_load[corner], next_load[corner])
		if contact_weights[corner] <= 0.0 and (previous_contact[corner] != 0 or next_contact[corner] != 0):
			contact_weights[corner] = 1.0
		total_weight += contact_weights[corner]
	if total_weight <= 0.0:
		return
	for corner in CORNER_COUNT:
		if contact_weights[corner] <= 0.0:
			continue
		var corner_energy := energy_j * contact_weights[corner] / total_weight
		values[SUSPENSION_BASE + corner] = clampf(
			values[SUSPENSION_BASE + corner] + corner_energy / SUSPENSION_DAMAGE_ENERGY_J,
			0.0, 1.0,
		)


func _severe_bottoming(
	travel_before: float,
	travel_after: float,
	rate_before: float,
	rate_after: float,
	bump_limit: float,
	stop_stiffness: float,
) -> bool:
	var compression_rate := maxf(rate_before, rate_after)
	var crossed_trigger := travel_before < bump_limit * BOTTOMING_TRIGGER_RATIO \
		and travel_after >= bump_limit * BOTTOMING_TRIGGER_RATIO
	var overtravel := travel_after - bump_limit
	var compressing := compression_rate > 0.0 and travel_after >= travel_before
	return compressing and ((crossed_trigger and compression_rate >= SEVERE_BOTTOMING_RATE_M_PER_S) \
		or (overtravel >= MIN_OVERTRAVEL_DAMAGE_M and stop_stiffness > 0.0))


func _finite_packed(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true
