## SC-HUM-03: render-only head aim for the field population. Each person keeps a small head state
## (yaw, pitch and their rates) advanced in fixed steps of simulation time, like WindsockMotion.
## Pilots stay coupled to the aircraft; spectators and pits members hold their head until the
## aircraft leaves a dead zone, then follow it. Nothing here touches simulation state, and the
## population keeps its MultiMesh batches: apply() only rewrites per-instance yaw/pitch.
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

var simulated_time_s: float = 0.0
var _people: Array[Dictionary] = []
var _nodes: Dictionary = {}
var _epoch_time_s: float = 0.0
var _step_index: int = 0
var _last_observed_time_s: float = 0.0
var _target := Vector3.ZERO
var _previous_target := Vector3.ZERO
var _velocity := Vector3.ZERO
var _initialized: bool = false
var _dirty: bool = true


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
	for entry: Dictionary in people:
		var person: Dictionary = entry.duplicate()
		person.merge(_params(str(entry.get("role", "spectator")), int(entry.get("seed", 0))), true)
		person.yaw = person.rest_yaw
		person.pitch = person.rest_pitch
		person.yaw_rate = 0.0
		person.pitch_rate = 0.0
		person.goal_yaw = person.rest_yaw
		person.goal_pitch = person.rest_pitch
		person.tracking = false
		_people.append(person)
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
	var person: Dictionary = _people[index]
	return Vector2(float(person.yaw) * float(person.mover), float(person.pitch) * float(person.mover))


func person_role(index: int) -> String:
	return str(_people[index].role)


## Restart at time_s with the target at the given render-space position. Heads return to rest.
func reset(time_s: float, target: Vector3) -> void:
	_epoch_time_s = time_s
	_last_observed_time_s = time_s
	_step_index = 0
	simulated_time_s = time_s
	_target = target
	_previous_target = target
	_velocity = Vector3.ZERO
	_initialized = true
	for person: Dictionary in _people:
		person.yaw = person.rest_yaw
		person.pitch = person.rest_pitch
		person.yaw_rate = 0.0
		person.pitch_rate = 0.0
		person.goal_yaw = person.rest_yaw
		person.goal_pitch = person.rest_pitch
		person.tracking = false
	_dirty = true


## Advance to time_s with the aircraft at `target` (render space). Repeated timestamps are ignored;
## a backward jump (restart, checkpoint restore) resets, as the windsock does.
func update_to(time_s: float, target: Vector3) -> void:
	if not _initialized or not is_finite(time_s) or time_s < _last_observed_time_s - 1.0e-12:
		reset(time_s, target)
		return
	var elapsed: float = time_s - _last_observed_time_s
	_last_observed_time_s = time_s
	if elapsed > 0.0:
		var measured: Vector3 = (target - _previous_target) / elapsed
		var blend: float = 1.0 - exp(-elapsed / VELOCITY_TIME_CONSTANT_S)
		_velocity = _velocity.lerp(measured, blend)
		_previous_target = target
	_target = target
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


func _step(dt: float) -> void:
	for person: Dictionary in _people:
		var want := _desired(person)
		if bool(person.coupled):
			person.goal_yaw = want.x
			person.goal_pitch = want.y
		else:
			var error: float = Vector2(want.x - float(person.yaw), want.y - float(person.pitch)).length()
			if bool(person.tracking):
				person.goal_yaw = want.x
				person.goal_pitch = want.y
				if error < float(person.dead_zone) * 0.25:
					person.tracking = false
			elif Vector2(want.x - float(person.goal_yaw), want.y - float(person.goal_pitch)).length() > float(person.dead_zone):
				person.tracking = true
				person.goal_yaw = want.x
				person.goal_pitch = want.y
		_follow(person, "yaw", "yaw_rate", float(person.goal_yaw), dt)
		_follow(person, "pitch", "pitch_rate", float(person.goal_pitch), dt)


## Critically damped follower with a rate limit (semi-implicit Euler; omega·dt ≤ 0.08 at 120 Hz).
static func _follow(person: Dictionary, angle_key: String, rate_key: String, goal: float, dt: float) -> void:
	var omega: float = person.omega
	var angle: float = person[angle_key]
	var rate: float = person[rate_key]
	rate += (omega * omega * (goal - angle) - 2.0 * omega * rate) * dt
	rate = clampf(rate, -RATE_LIMIT_RAD_S, RATE_LIMIT_RAD_S)
	person[rate_key] = rate
	person[angle_key] = angle + rate * dt


## Head direction toward the (lead-corrected) aircraft in the person's frame, or rest when the
## aircraft is out of range or behind. Local forward is −Z, as the source meshes face.
func _desired(person: Dictionary) -> Vector2:
	var rest := Vector2(person.rest_yaw, person.rest_pitch)
	var aim: Vector3 = _target + _velocity * float(person.lead_s)
	var offset: Vector3 = aim - (person.pivot as Vector3)
	if offset.length() > float(person.range_m):
		return rest
	var local: Vector3 = (person.basis as Basis).inverse() * offset
	var horizontal: float = Vector2(local.x, local.z).length()
	if horizontal < 1.0e-6 and absf(local.y) < 1.0e-6:
		return rest
	var yaw: float = atan2(-local.x, -local.z)
	var limit: float = person.yaw_limit
	if absf(yaw) > limit + REAR_GATE_MARGIN_RAD:
		return rest
	var pitch: float = atan2(local.y, horizontal)
	return Vector2(clampf(yaw, -limit, limit), clampf(pitch, PITCH_DOWN_LIMIT_RAD, float(person.pitch_up_limit)))


## Write the current head angles to the MultiMesh instances. Cheap when nothing changed.
func apply() -> void:
	if not _dirty:
		return
	_dirty = false
	for person: Dictionary in _people:
		var angles := Vector2(float(person.yaw) * float(person.mover), float(person.pitch) * float(person.mover))
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
