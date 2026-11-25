# GP-03: visual wheel articulation via the model team's existing gear pivots.
# This observer never writes simulation state. Phase is presentation-only and
# restarts on reset/checkpoint seek; compression and steering read current physics.
extends Node

const Retraction := preload("res://aircraft/retractable_model.gd")
const NightKit := preload("res://render/world/aircraft_lights.gd")
const Cadence := preload("res://render/presentation_cadence.gd")
const GroundAudioModel := preload("res://audio/ground_audio_model.gd")

var _session: Node
var _airplane: Dictionary
var _rest: Dictionary = {}
var _angles: Dictionary = {}
var _previous_speeds := PackedFloat64Array()
var _last_tick := -1
## VQ-01c-R1: wheel spin is visible motion, so it advances every rendered frame at most (never less often).
var _cadence := Cadence.new(mini(Cadence.configured_every_frames(), 1))
## F1: `Retraction.apply` poses every rig node from the extension alone (about 90 us per frame). Only this observer
## poses the live rig. When the rig and extension are unchanged, the nodes it posed keep their pose, except those this
## observer rewrites afterwards (spin, steering and compression nodes). Those get the same `position` and `quaternion`
## values through the same setters as `apply` (a restored `transform` would decompose differently when `rotation.x`
## is written next, as on the Corsair's quarter-turned retracted wheels).
var _applied_rig: Dictionary = {}
var _applied_extension := NAN
var _posed_rewritten: Array = [] # [Node3D, position, quaternion] that the last apply set


static func attach(airplane: Dictionary, session: Node) -> Node:
	var observer := new()
	observer.name = "GroundGearMotion"
	observer._session = session
	observer._airplane = airplane
	for key in ["left", "right", "nose", "tail"]:
		if airplane.get("gear", {}).has(key):
			observer._rest[key] = airplane.gear[key].position
			observer._angles[key] = 0.0
	airplane.root.add_child(observer)
	session.sim.stepped.connect(observer._stepped)
	return observer


static func _key(name: String) -> String:
	return name.trim_prefix("main_")


func _stepped(tick: int, _time: float, _state: PackedFloat64Array, _loads: PackedFloat64Array,
		_inputs: PackedFloat64Array, _aux: PackedFloat64Array) -> void:
	if _cadence.on_tick(tick):
		_advance_wheels(tick)


## Spin phase from the accepted wheel speeds since the last observation: trapezoidal over the
## elapsed ticks (exact per tick; across a frame it uses the two endpoint speeds).
func _advance_wheels(tick: int) -> void:
	if not is_instance_valid(_session) or _session.sim == null or not _session.aircraft.get("ok", false) or _session.wheel_count() == 0:
		return
	var start: int = _session.wheel_index()
	var speeds: PackedFloat64Array = _session.sim.continuous.slice(start, start + _session.wheel_count())
	if tick <= _last_tick or _previous_speeds.size() != speeds.size():
		for key in _angles:
			_angles[key] = 0.0
		_previous_speeds = speeds.duplicate()
		_last_tick = tick
		return
	var contacts: Array = _session.aircraft.model.landing_gear.contacts
	var elapsed_s: float = float(tick - _last_tick) * _session.sim.dt()
	for i in speeds.size():
		var key := _key(contacts[i].name)
		if _angles.has(key):
			# All three builders use +X axles and nose -Z; forward rolling is -X.
			_angles[key] = fmod(float(_angles[key]) - 0.5 * (_previous_speeds[i] + speeds[i]) * elapsed_s / float(contacts[i].wheel_radius), TAU)
	_previous_speeds = speeds.duplicate()
	_last_tick = tick


## Rig nodes this observer writes after `Retraction.apply`, with the exact values the pose gave them (the same
## interpolation and helpers as `Retraction.apply`, for these few nodes only).
func _rewritten_after_posing(rig: Dictionary, extension: float) -> Array:
	var result: Array = []
	if rig.is_empty() or not is_finite(extension) or extension < 0.0 or extension > 1.0:
		return result
	var names := {}
	for node_name: Variant in rig.get("nodes", {}).keys():
		names[rig.nodes[node_name]] = node_name
	var candidates: Array = _airplane.get("gear", {}).values()
	candidates.append_array(rig.get("compression", {}).values())
	var samples: Array = rig.data.retraction.samples
	var at := extension * (samples.size() - 1)
	var left := mini(int(floor(at)), samples.size() - 2)
	var fraction := at - left
	for node: Variant in candidates:
		if not node is Node3D or not names.has(node) or result.any(func(posed: Array) -> bool: return posed[0] == node):
			continue
		var node_name: Variant = names[node]
		if not samples[left].nodes.has(node_name):
			continue
		var a: Dictionary = samples[left].nodes[node_name]
		var b: Dictionary = samples[left + 1].nodes[node_name]
		result.append([node, Retraction._v3(a.translation).lerp(Retraction._v3(b.translation), fraction),
			Retraction._rotation(a.rotation_wxyz).slerp(Retraction._rotation(b.rotation_wxyz), fraction).normalized()])
	return result


func _process(_dt: float) -> void:
	if not is_instance_valid(_session) or _session.sim == null:
		return
	if _cadence.take(_session.sim.tick):
		_advance_wheels(_session.sim.tick)
	if not _session.aircraft.get("ok", false) or _session.wheel_count() == 0:
		return
	var contacts: Array = _session.current_landing_gear().contacts
	var rig: Dictionary = _airplane.get("gear_retraction", {})
	var retractable: bool = _session.gear_is_retractable()
	# One accepted gear state per frame; every reader below sees the same extension.
	var extension: float = _session.gear_state().extension if not rig.is_empty() or retractable else 1.0
	if not rig.is_empty():
		if not is_same(rig, _applied_rig) or extension != _applied_extension:
			Retraction.apply(rig, extension)
			_applied_rig = rig
			_applied_extension = extension
			_posed_rewritten = _rewritten_after_posing(rig, extension)
		else:
			for posed: Array in _posed_rewritten:
				if is_instance_valid(posed[0]):
					(posed[0] as Node3D).position = posed[1]
					(posed[0] as Node3D).quaternion = posed[2]
	elif retractable:
		# P51-11b: procedural builders pose their own gear legs and doors from the accepted extension.
		var builder: Script = _airplane.get("_model_builder")
		if builder != null and builder.has_method("set_gear"):
			builder.call("set_gear", _airplane, extension)
	# P51-V13: night-kit lights anchored on moving parts follow them; gear-gated lamps work only down and locked.
	var model: Node3D = _airplane.get("root")
	if model != null and model.has_node("NightKit"):
		NightKit.update_dynamic(model.get_node("NightKit"), model, extension if retractable else 1.0)
	# Far above the ground no wheel can be compressed: skip the per-wheel terrain/lake/track queries and leave the
	# axles at rest. The bound (reach + highest surface + margin + 0.5 s of travel) also covers the interpolated
	# pose between two accepted ticks. Same conservative test as ground audio (VQ-01c-R1).
	var clear: bool = GroundAudioModel.wheels_clear_of_ground(_session)
	var compression := PackedFloat64Array()
	if not clear:
		var fraction := 1.0 if _session.sim.paused else Engine.get_physics_interpolation_fraction()
		compression = _session.gear_compressions(_session.sim.interpolated(fraction))
	var steer: float = _session.sim.aux[_session.AUX_SERVO + 2]
	var gear: Dictionary = _airplane.get("gear", {})
	for i in contacts.size():
		var key := _key(contacts[i].name)
		# Update the parent steering transform before converting world-up compression.
		if float(contacts[i].max_steering) != 0.0 and gear.has("steering"):
			gear.steering.rotation.y = -steer * float(contacts[i].max_steering)
		if gear.has(key):
			var wheel: Node3D = gear[key]
			wheel.rotation.x = float(_angles.get(key, 0.0))
			if not rig.is_empty():
				var lower_leg: Node3D = rig.compression[key]
				if clear:
					lower_leg.position = rig.rest[key].origin
					continue
				lower_leg.position = rig.rest[key].origin + lower_leg.get_parent().global_basis.inverse() * Vector3.UP * maxf(0.0, compression[i])
				continue
			if clear:
				wheel.position = _rest[key]
				continue
			# Equivalent compliant contact: move the axle up in world space. The leg
			# mesh is not a multibody strut; do not scale or rewrite model geometry.
			var up_local: Vector3 = wheel.get_parent().global_basis.inverse() * Vector3.UP
			wheel.position = _rest[key] + up_local * maxf(0.0, compression[i])
