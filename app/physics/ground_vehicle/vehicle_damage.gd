class_name GroundVehicleDamage
extends RefCounted
## Bounded deterministic gameplay damage estimate for the MT8 ground vehicle.
## This sidecar observes accepted float64 state/telemetry; it never feeds forces
## into VehicleDynamics or changes the contact solver.

const STATE_SIZE := 19
const SNAPSHOT_SIZE := STATE_SIZE
const SNAPSHOT_VERSION := 1
const MAX_EPISODE_ENERGY_J := 2000.0
const MAX_LAST_IMPACT_ENERGY_J := 2000.0
const BODY_DAMAGE_ENERGY_J := 180.0
const DRIVE_DAMAGE_ENERGY_J := 300.0
const SUSPENSION_DAMAGE_ENERGY_J := 20.0
const DAMAGE_EPSILON_J := 1.0e-9
const MIN_EPISODE_DAMAGE_ENERGY_J := 2.0
const MIN_CONTACT_SPEED_M_PER_S := 0.4
const SEVERE_BOTTOMING_RATE_M_PER_S := 1.8
const BOTTOMING_TRIGGER_RATIO := 0.96
const BOTTOMING_RELEASE_RATIO := 0.72
const MIN_OVERTRAVEL_DAMAGE_M := 0.004
const CONTACT_POWER_CAP_W := 10000.0

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
	# Wall contacts also appear in hull_in_contact. Keep the wall episode as the
	# single source for that tick instead of double-counting the same body hit.
	previous_hull = previous_hull and not previous_wall
	next_hull = next_hull and not next_wall
	var energy_loss_j := minf(_contact_energy_loss(previous_telemetry, next_telemetry, dt),
		CONTACT_POWER_CAP_W * dt)
	var contact_speed := maxf(_linear_speed(previous_state), _linear_speed(next_state))
	var region := _impact_region(previous_state, next_state)
	var wall_episode_present := previous_wall or next_wall
	var hull_episode_present := (previous_hull or next_hull) and not wall_episode_present
	if wall_episode_present:
		if not previous_wall:
			next_values[WALL_EPISODE_ENERGY] = 0.0
		var energy_before := next_values[WALL_EPISODE_ENERGY]
		var added_wall_energy := _episode_energy_increment(
			energy_loss_j, contact_speed, energy_before,
		)
		next_values[WALL_EPISODE_ENERGY] += added_wall_energy
		var damaging_wall_energy := _above_episode_threshold(
			energy_before, next_values[WALL_EPISODE_ENERGY],
		)
		if damaging_wall_energy > DAMAGE_EPSILON_J:
			_apply_hull_impact(next_values, region, damaging_wall_energy)
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
			energy_loss_j, contact_speed, energy_before,
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
	return inertia is PackedFloat64Array and inertia.size() == 6 \
		and _finite_packed(inertia) and radii is PackedFloat64Array \
		and radii.size() > 0 and _finite_packed(radii)


func _telemetry_is_valid(value: Dictionary, hull_count: int) -> bool:
	if typeof(value.get("ok")) != TYPE_BOOL or not bool(value.ok):
		return false
	for key in ["total_energy_j", "wall_normal_load_n", "wall_friction_power_w"]:
		var scalar: Variant = value.get(key, NAN)
		if typeof(scalar) not in [TYPE_INT, TYPE_FLOAT] or typeof(scalar) == TYPE_BOOL \
				or not is_finite(float(scalar)):
			return false
	var wall_count: Variant = value.get("wall_contact_count", -1)
	if typeof(wall_count) != TYPE_INT or int(wall_count) < 0:
		return false
	var hull_contacts: Variant = value.get("hull_in_contact")
	var wheel_wall_contacts: Variant = value.get("wheel_wall_in_contact")
	var wheel_wall_load: Variant = value.get("wheel_wall_load_n")
	var hull_wall_load: Variant = value.get("hull_wall_load_n")
	var travel: Variant = value.get("suspension_travel_m")
	var suspension_force: Variant = value.get("suspension_force_n")
	return hull_contacts is PackedByteArray and hull_contacts.size() == hull_count \
		and wheel_wall_contacts is PackedByteArray and wheel_wall_contacts.size() == CORNER_COUNT \
		and wheel_wall_load is PackedFloat64Array and wheel_wall_load.size() == CORNER_COUNT \
		and _finite_packed(wheel_wall_load) \
		and hull_wall_load is PackedFloat64Array and hull_wall_load.size() == hull_count \
		and _finite_packed(hull_wall_load) \
		and travel is PackedFloat64Array and travel.size() == CORNER_COUNT \
		and _finite_packed(travel) \
		and suspension_force is PackedFloat64Array and suspension_force.size() == CORNER_COUNT \
		and _finite_packed(suspension_force)


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


func _contact_energy_loss(
	previous_telemetry: Dictionary,
	next_telemetry: Dictionary,
	dt: float,
) -> float:
	var previous_energy := float(previous_telemetry.total_energy_j)
	var next_energy := float(next_telemetry.total_energy_j)
	var wall_friction_power := 0.5 * (
		float(previous_telemetry.wall_friction_power_w)
		+ float(next_telemetry.wall_friction_power_w)
	)
	var wall_friction_work_j := maxf(0.0, -wall_friction_power * dt)
	return clampf(previous_energy - next_energy - wall_friction_work_j,
		0.0, MAX_EPISODE_ENERGY_J)


func _episode_energy_increment(energy_loss_j: float, contact_speed: float, energy_before: float) -> float:
	if contact_speed < MIN_CONTACT_SPEED_M_PER_S:
		return 0.0
	return minf(energy_loss_j, maxf(0.0, MAX_EPISODE_ENERGY_J - energy_before))


func _above_episode_threshold(energy_before: float, energy_after: float) -> float:
	return maxf(0.0, energy_after - MIN_EPISODE_DAMAGE_ENERGY_J) \
		- maxf(0.0, energy_before - MIN_EPISODE_DAMAGE_ENERGY_J)


func _linear_speed(state: PackedFloat64Array) -> float:
	return sqrt(state[STATE_VEL] * state[STATE_VEL]
		+ state[STATE_VEL + 1] * state[STATE_VEL + 1]
		+ state[STATE_VEL + 2] * state[STATE_VEL + 2])


func _impact_region(previous_state: PackedFloat64Array, next_state: PackedFloat64Array) -> int:
	var forward := 0.5 * (previous_state[STATE_VEL] + next_state[STATE_VEL])
	var right := 0.5 * (previous_state[STATE_VEL + 1] + next_state[STATE_VEL + 1])
	var down := 0.5 * (previous_state[STATE_VEL + 2] + next_state[STATE_VEL + 2])
	if absf(down) > maxf(absf(forward), absf(right)):
		return BODY_BOTTOM
	if absf(forward) >= absf(right):
		return BODY_FRONT if forward >= 0.0 else BODY_REAR
	return BODY_RIGHT if right >= 0.0 else BODY_LEFT


func _apply_hull_impact(values: PackedFloat64Array, region: int, energy_j: float) -> void:
	values[region] = clampf(values[region] + energy_j / BODY_DAMAGE_ENERGY_J, 0.0, 1.0)
	values[DRIVE] = clampf(values[DRIVE] + energy_j / DRIVE_DAMAGE_ENERGY_J, 0.0, 1.0)


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
	return (crossed_trigger and compression_rate >= SEVERE_BOTTOMING_RATE_M_PER_S) \
		or (overtravel >= MIN_OVERTRAVEL_DAMAGE_M and stop_stiffness > 0.0)


func _finite_packed(values: PackedFloat64Array) -> bool:
	for value in values:
		if not is_finite(value):
			return false
	return true
