## SC-HUM-03: render-only head aim for the field population. Each person keeps a small head state
## (yaw, pitch and their rates) advanced in fixed steps of simulation time, like WindsockMotion.
## Pilots stay coupled to the aircraft; spectators and pits members hold their head until the
## aircraft leaves a dead zone, then follow it. Nothing here touches simulation state, and the
## population keeps its MultiMesh batches: apply() only rewrites per-instance yaw/pitch.
## The per-step state lives in packed float64 arrays (struct of arrays); `_people` keeps the
## per-person metadata and seeded parameters for apply(), tests and diagnostics.
extends RefCounted

const Palette = preload("res://scenery/palette.gd")

const STEP_S: float = 1.0 / 120.0
const MAX_STEPS_PER_UPDATE: int = 120
## Human head rotation peaks well above this; the limit only stops a snap after a target jump.
const RATE_LIMIT_RAD_S: float = 4.5
const PITCH_DOWN_LIMIT_RAD: float = -0.26
## Beyond the yaw limit plus this margin the target is behind the person: return to rest.
const REAR_GATE_MARGIN_RAD: float = 0.35
## Velocity estimate smoothing for the anticipation lead (s).
const VELOCITY_TIME_CONSTANT_S: float = 0.2
## Shader encoding: INSTANCE_CUSTOM.w = yaw / PI, instance COLOR.a = 0.5 + pitch / PI.
const ENCODE_EPSILON: float = 1.0e-4
## SC-HUM-05 crash glance: after a seeded startle delay, spectators and pits members look at the
## player's crash for this long regardless of their usual range and with a small dead zone.
const ALERT_DURATION_S: float = 8.0
const ALERT_DEAD_ZONE_SCALE: float = 0.25

var simulated_time_s: float = 0.0
var _people: Array[Dictionary] = []
var _nodes: Dictionary = {}
var _epoch_time_s: float = 0.0
var _step_index: int = 0
var _last_observed_time_s: float = 0.0
## Target 0 is the player's aircraft; target k + 1 is companion slot k (SC-HUM-04). Each holds
## {valid, position, previous, velocity}; a companion that disappears falls back to the player.
var _targets: Array[Dictionary] = []
var _alert_input: bool = false
var _alert_start_s: float = -INF
var _initialized: bool = false
var _dirty: bool = true

# Seeded parameters, one entry per person.
var _coupled := PackedByteArray()
var _slot := PackedInt32Array()
var _omega := PackedFloat64Array()
var _dead_zone := PackedFloat64Array()
var _lead_s := PackedFloat64Array()
var _range_m := PackedFloat64Array()
var _yaw_limit := PackedFloat64Array()
var _pitch_up_limit := PackedFloat64Array()
var _mover := PackedFloat64Array()
var _rest_yaw := PackedFloat64Array()
var _rest_pitch := PackedFloat64Array()
var _reaction_s := PackedFloat64Array()
var _pivot := PackedVector3Array()
var _to_local: Array[Basis] = []
# Head state.
var _yaw := PackedFloat64Array()
var _pitch := PackedFloat64Array()
var _yaw_rate := PackedFloat64Array()
var _pitch_rate := PackedFloat64Array()
var _goal_yaw := PackedFloat64Array()
var _goal_pitch := PackedFloat64Array()
var _tracking := PackedByteArray()


## Builds the model from Population.build() metadata, or returns null when the population has no people.
static func from_population(population: Node3D) -> RefCounted:
	if population == null or not population.has_meta("people"):
		return null
	var people: Array = population.get_meta("people")
	if people.is_empty():
		return null
	var model: RefCounted = (load("res://scenery/people_gaze.gd") as GDScript).new()
	model.configure(people, population.get_meta("people_nodes", {}))
	return model


func configure(people: Array, nodes: Dictionary) -> void:
	_nodes = nodes
	_people.clear()
	_to_local.clear()
	var next_slot := 0
	for entry: Dictionary in people:
		var person: Dictionary = entry.duplicate()
		person.merge(_params(str(entry.get("role", "spectator")), int(entry.get("seed", 0))), true)
		# Flight-line pilots fly the companions in roster order; everyone else watches the player.
		person.companion_slot = next_slot if bool(person.coupled) else -1
		if bool(person.coupled):
			next_slot += 1
		_people.append(person)
		_to_local.append((person.basis as Basis).inverse())
	var count := _people.size()
	for array: Variant in [_coupled, _slot, _omega, _dead_zone, _lead_s, _range_m, _yaw_limit, _pitch_up_limit,
			_mover, _rest_yaw, _rest_pitch, _reaction_s, _pivot, _yaw, _pitch, _yaw_rate, _pitch_rate,
			_goal_yaw, _goal_pitch, _tracking]:
		array.resize(count)
	for i in count:
		var person: Dictionary = _people[i]
		_coupled[i] = 1 if bool(person.coupled) else 0
		_slot[i] = int(person.companion_slot)
		_omega[i] = person.omega
		_dead_zone[i] = person.dead_zone
		_lead_s[i] = person.lead_s
		_range_m[i] = person.range_m
		_yaw_limit[i] = person.yaw_limit
		_pitch_up_limit[i] = person.pitch_up_limit
		_mover[i] = person.mover
		_rest_yaw[i] = person.rest_yaw
		_rest_pitch[i] = person.rest_pitch
		_reaction_s[i] = person.reaction_s
		_pivot[i] = person.pivot
	_rest_heads()
	_dirty = true


## Seeded per-person behaviour. Values are estimates within the survey's human-factors ranges (H1–H3, H10).
static func _params(role: String, seed: int) -> Dictionary:
	var h := func(salt: int) -> float: return Palette.hash01(seed, salt)
	var coupled := role == "pilot"
	var params := {
		role = role,
		coupled = coupled,
		yaw_limit = deg_to_rad(62.0 + 13.0 * h.call(301)),
		pitch_up_limit = deg_to_rad(45.0 + 10.0 * h.call(302)),
		mover = 0.85 + 0.15 * h.call(303),
		rest_yaw = deg_to_rad(-6.0 + 12.0 * h.call(304)),
		rest_pitch = deg_to_rad(-3.0 + 6.0 * h.call(305)),
		reaction_s = 0.2 + 0.6 * h.call(310),
	}
	if coupled:
		params.merge({dead_zone = 0.0, omega = 7.0 + 2.0 * h.call(306), lead_s = 0.15 + 0.10 * h.call(307), range_m = INF}, true)
	elif role == "pits":
		params.merge({dead_zone = deg_to_rad(18.0 + 10.0 * h.call(306)), omega = 4.5 + 2.0 * h.call(307),
			lead_s = 0.05 + 0.10 * h.call(308), range_m = 70.0 + 60.0 * h.call(309)}, true)
	else:
		params.merge({dead_zone = deg_to_rad(12.0 + 8.0 * h.call(306)), omega = 4.5 + 2.0 * h.call(307),
			lead_s = 0.05 + 0.10 * h.call(308), range_m = 180.0 + 140.0 * h.call(309)}, true)
	return params


func person_count() -> int:
	return _people.size()


## Displayed head angles (yaw, pitch) in radians, as written to the shader.
func head_angles(index: int) -> Vector2:
	return Vector2(_yaw[index] * _mover[index], _pitch[index] * _mover[index])


func person_role(index: int) -> String:
	return str(_people[index].role)


func companion_slot(index: int) -> int:
	return _slot[index]


func _rest_heads() -> void:
	for i in _people.size():
		_yaw[i] = _rest_yaw[i]
		_pitch[i] = _rest_pitch[i]
		_yaw_rate[i] = 0.0
		_pitch_rate[i] = 0.0
		_goal_yaw[i] = _rest_yaw[i]
		_goal_pitch[i] = _rest_pitch[i]
		_tracking[i] = 0


## Restart at time_s with the player's aircraft at `target` (render space) and the companions at
## `companions` (render-space Vector3, or null for an absent slot). `alert` is true while the
## player's aircraft is crashed. Heads return to rest.
func reset(time_s: float, target: Vector3, companions: Array = [], alert: bool = false) -> void:
	_epoch_time_s = time_s
	_last_observed_time_s = time_s
	_step_index = 0
	simulated_time_s = time_s
	_targets.clear()
	_set_targets(target, companions, 0.0)
	_alert_input = alert
	_alert_start_s = time_s if alert else -INF
	_initialized = true
	_rest_heads()
	_dirty = true


## Advance to time_s with the aircraft positions (render space, see reset). Repeated timestamps are
## ignored; a backward jump (restart, checkpoint restore) resets, as the windsock does.
func update_to(time_s: float, target: Vector3, companions: Array = [], alert: bool = false) -> void:
	if not _initialized or not is_finite(time_s) or time_s < _last_observed_time_s - 1.0e-12:
		reset(time_s, target, companions, alert)
		return
	var elapsed: float = time_s - _last_observed_time_s
	_last_observed_time_s = time_s
	_set_targets(target, companions, elapsed)
	if alert and not _alert_input:
		_alert_start_s = time_s
	_alert_input = alert
	var target_index: int = int(floor((time_s - _epoch_time_s) / STEP_S + 1.0e-9))
	var steps: int = target_index - _step_index
	if steps > MAX_STEPS_PER_UPDATE:
		_step_index = target_index - MAX_STEPS_PER_UPDATE
		steps = MAX_STEPS_PER_UPDATE
	for _i: int in steps:
		_step(STEP_S)
		_step_index += 1
	simulated_time_s = _epoch_time_s + float(_step_index) * STEP_S
	if steps > 0:
		_dirty = true


## Update every target's position and smoothed velocity. A target that (re)appears starts at rest
## so a roster change never produces a lead spike.
func _set_targets(player: Vector3, companions: Array, elapsed: float) -> void:
	var positions: Array = [player]
	positions.append_array(companions)
	_targets.resize(maxi(_targets.size(), positions.size()))
	for index in _targets.size():
		var value: Variant = positions[index] if index < positions.size() else null
		var entry: Dictionary = _targets[index] if _targets[index] is Dictionary and not _targets[index].is_empty() else {valid = false}
		if not value is Vector3 or not (value as Vector3).is_finite():
			entry.valid = false
		elif not bool(entry.valid):
			entry = {valid = true, position = value, previous = value, velocity = Vector3.ZERO}
		else:
			if elapsed > 0.0:
				var measured: Vector3 = ((value as Vector3) - (entry.previous as Vector3)) / elapsed
				var blend: float = 1.0 - exp(-elapsed / VELOCITY_TIME_CONSTANT_S)
				entry.velocity = (entry.velocity as Vector3).lerp(measured, blend)
				entry.previous = value
			entry.position = value
		_targets[index] = entry


func _target_for(index: int) -> Dictionary:
	var slot: int = _slot[index]
	if slot >= 0 and slot + 1 < _targets.size() and bool(_targets[slot + 1].valid):
		return _targets[slot + 1]
	return _targets[0]


func _step(dt: float) -> void:
	var since_alert: float = _epoch_time_s + float(_step_index + 1) * STEP_S - _alert_start_s
	for i in _people.size():
		var coupled: bool = _coupled[i] != 0
		var alerted: bool = not coupled and since_alert >= _reaction_s[i] and since_alert < _reaction_s[i] + ALERT_DURATION_S
		var want := _desired(i, alerted)
		if coupled:
			_goal_yaw[i] = want.x
			_goal_pitch[i] = want.y
		else:
			var dead_zone: float = _dead_zone[i] * (ALERT_DEAD_ZONE_SCALE if alerted else 1.0)
			var error: float = Vector2(want.x - _yaw[i], want.y - _pitch[i]).length()
			if _tracking[i] != 0:
				_goal_yaw[i] = want.x
				_goal_pitch[i] = want.y
				if error < dead_zone * 0.25:
					_tracking[i] = 0
			elif Vector2(want.x - _goal_yaw[i], want.y - _goal_pitch[i]).length() > dead_zone:
				_tracking[i] = 1
				_goal_yaw[i] = want.x
				_goal_pitch[i] = want.y
		# Critically damped follower with a rate limit (semi-implicit Euler; omega·dt ≤ 0.08 at 120 Hz).
		var omega: float = _omega[i]
		var rate: float = _yaw_rate[i] + (omega * omega * (_goal_yaw[i] - _yaw[i]) - 2.0 * omega * _yaw_rate[i]) * dt
		rate = clampf(rate, -RATE_LIMIT_RAD_S, RATE_LIMIT_RAD_S)
		_yaw_rate[i] = rate
		_yaw[i] = _yaw[i] + rate * dt
		rate = _pitch_rate[i] + (omega * omega * (_goal_pitch[i] - _pitch[i]) - 2.0 * omega * _pitch_rate[i]) * dt
		rate = clampf(rate, -RATE_LIMIT_RAD_S, RATE_LIMIT_RAD_S)
		_pitch_rate[i] = rate
		_pitch[i] = _pitch[i] + rate * dt


## Head direction toward the (lead-corrected) aircraft in the person's frame, or rest when the
## aircraft is out of range or behind. Local forward is −Z, as the source meshes face. A crash
## alert lifts the range limit.
func _desired(i: int, alerted: bool = false) -> Vector2:
	var rest := Vector2(_rest_yaw[i], _rest_pitch[i])
	var target: Dictionary = _target_for(i)
	if not bool(target.valid):
		return rest
	var aim: Vector3 = (target.position as Vector3) + (target.velocity as Vector3) * _lead_s[i]
	var offset: Vector3 = aim - _pivot[i]
	if not alerted and offset.length() > _range_m[i]:
		return rest
	var local: Vector3 = _to_local[i] * offset
	var horizontal: float = Vector2(local.x, local.z).length()
	if horizontal < 1.0e-6 and absf(local.y) < 1.0e-6:
		return rest
	var yaw: float = atan2(-local.x, -local.z)
	var limit: float = _yaw_limit[i]
	if absf(yaw) > limit + REAR_GATE_MARGIN_RAD:
		return rest
	var pitch: float = atan2(local.y, horizontal)
	return Vector2(clampf(yaw, -limit, limit), clampf(pitch, PITCH_DOWN_LIMIT_RAD, _pitch_up_limit[i]))


## Write the current head angles to the MultiMesh instances. Cheap when nothing changed.
func apply() -> void:
	if not _dirty:
		return
	_dirty = false
	for i in _people.size():
		var person: Dictionary = _people[i]
		var angles := head_angles(i)
		var encoded := Vector2(angles.x / PI, 0.5 + angles.y / PI)
		var written: Variant = person.get("written", null)
		if written is Vector2 and (written as Vector2).distance_to(encoded) < ENCODE_EPSILON:
			continue
		person.written = encoded
		var custom: Color = person.custom
		var tint: Color = person.tint
		var index: int = person.index
		for node: MultiMeshInstance3D in _nodes.get(person.asset, []):
			if not is_instance_valid(node) or node.multimesh == null:
				continue
			node.multimesh.set_instance_custom_data(index, Color(custom.r, custom.g, custom.b, encoded.x))
			node.multimesh.set_instance_color(index, Color(tint.r, tint.g, tint.b, encoded.y))
