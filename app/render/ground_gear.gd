# GP-03: visual wheel articulation via the model team's existing gear pivots.
# This observer never writes simulation state. Phase is presentation-only and
# restarts on reset/checkpoint seek; compression and steering read current physics.
extends Node

var _session: Node
var _airplane: Dictionary
var _rest: Dictionary = {}
var _angles: Dictionary = {}
var _previous_speeds := PackedFloat64Array()
var _last_tick := -1


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
	if not is_instance_valid(_session) or _session.sim == null or not _session.aircraft.get("ok", false) or _session.wheel_count() == 0:
		return
	var speeds: PackedFloat64Array = _session.sim.continuous.slice(_session.wheel_index())
	if tick <= _last_tick or _previous_speeds.size() != speeds.size():
		for key in _angles:
			_angles[key] = 0.0
		_previous_speeds = speeds.duplicate()
		_last_tick = tick
		return
	var contacts: Array = _session.aircraft.model.landing_gear.contacts
	for i in speeds.size():
		var key := _key(contacts[i].name)
		if _angles.has(key):
			# All three builders use +X axles and nose -Z; forward rolling is -X.
			_angles[key] = fmod(float(_angles[key]) - 0.5 * (_previous_speeds[i] + speeds[i]) * _session.sim.dt() / float(contacts[i].wheel_radius), TAU)
	_previous_speeds = speeds.duplicate()
	_last_tick = tick


func _process(_dt: float) -> void:
	if not is_instance_valid(_session) or _session.sim == null or not _session.aircraft.get("ok", false) or _session.wheel_count() == 0:
		return
	var contacts: Array = _session.aircraft.model.landing_gear.contacts
	var compression: PackedFloat64Array = _session.gear_compressions(_session.sim.interpolated(Engine.get_physics_interpolation_fraction()))
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
			# Equivalent compliant contact: move the axle up in world space. The leg
			# mesh is not a multibody strut; do not scale or rewrite model geometry.
			var up_local: Vector3 = wheel.get_parent().global_basis.inverse() * Vector3.UP
			wheel.position = _rest[key] + up_local * maxf(0.0, compression[i])
