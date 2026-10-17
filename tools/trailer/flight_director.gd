## Narrowly scoped external controller/camera/evidence node for capture_flight.gd.
## It only supplies existing pilot commands before a tick and reads accepted simulation/render state.
extends Node

const RB := preload("res://physics/rigid_body.gd")

var main: Node
var shot := "stik-bank"
var duration_s := 4.0
var fps := 60
var tick_records: Array[Dictionary] = []
var frame_records: Array[Dictionary] = []
var _gear_keys: Array[String] = ["left", "right", "nose", "tail"]


func configure(flight_main: Node, shot_name: String, shot_duration_s: float, output_fps: int) -> void:
	main = flight_main
	shot = shot_name
	duration_s = shot_duration_s
	fps = output_fps
	process_physics_priority = -2 # FlightSession is -1: stage this tick's inputs before the real solver node.
	process_priority = 10 # Main renders first; this node then places the cinematic camera before draw.
	main.session.input_enabled = false
	main.session.sim.stepped.connect(_on_sim_stepped)
	main._rig.set_view("chase")
	main._rig.auto_zoom = false


func _physics_process(_delta: float) -> void:
	if main == null or main.session == null or not main.session.crash.is_empty() or main.session.sim.paused:
		return
	var session: Node = main.session
	var t: float = float(session.sim.tick) * session.sim.dt()
	var controls: Dictionary = _commands_at(t)
	session.commands = controls.duplicate(true)
	session.raw = controls.duplicate(true)
	session.sim.inputs = session._inputs()


func _process(_delta: float) -> void:
	if main == null or main._camera == null or main._airplane.is_empty():
		return
	if main.session != null and not main.session.crash.is_empty():
		return # The live CrashDirector owns the camera once the physical incident occurs.
	_place_camera(float(main.session.sim.time()))


func record_presented_frame(frame_index: int, preroll_frames: int) -> void:
	if main == null or main.session == null or main._airplane.is_empty():
		return
	var session: Node = main.session
	var sim: Node = session.sim
	var root: Node3D = main._airplane.root
	var transform: Transform3D = root.global_transform
	var rotation: Quaternion = transform.basis.get_rotation_quaternion().normalized()
	var state: PackedFloat64Array = sim.interpolated(Engine.get_physics_interpolation_fraction())
	var gear: Dictionary = session.gear_state()
	var gear_transforms := {}
	for key: String in _gear_keys:
		var part: Variant = main._airplane.get("gear", {}).get(key)
		if part is Node3D:
			var gear_transform: Transform3D = part.global_transform
			gear_transforms[key] = {
				position = _v3(gear_transform.origin),
				quaternion_xyzw = _quat(gear_transform.basis.get_rotation_quaternion()),
			}
	var prop: Node3D = main._airplane.get("propeller")
	var smoke_data := _smoke_evidence()
	var camera: Camera3D = main._camera
	frame_records.append({
		frame = frame_index,
		capture_time_s = float(frame_index) / float(fps),
		preroll_frames = preroll_frames,
		sim_tick = int(sim.tick),
		sim_time_s = float(sim.time()),
		sim_tick_dt_s = float(sim.dt()),
		state_ned_position_m = _slice(state, RB.POS, 3),
		state_ned_attitude_wxyz = _slice(state, RB.ATT, 4),
		aircraft_root_world_position_m = _v3(transform.origin),
		aircraft_root_world_quaternion_xyzw = _quat(rotation),
		aircraft_root_world_basis_rows = _basis_rows(transform.basis),
		actual_surface_angles_deg = session.surface_angles_deg(),
		actual_surface_commands = session.surfaces(),
		flap_state = session.flap_state(),
		landing_gear_state = gear,
		landing_gear_world_transforms = gear_transforms,
		propeller = {
			angle_rad = float(prop.rotation.z) if prop != null else 0.0,
			shaft_rpm = float(sim.aux[0]) if sim.aux.size() > 0 else 0.0,
			spin_sign = float(main._airplane.get("propeller_spin_sign", 1.0)),
		},
		smoke = smoke_data,
		camera = {
			position_m = _v3(camera.global_position),
			quaternion_xyzw = _quat(camera.global_basis.get_rotation_quaternion()),
			fov_deg = float(camera.fov),
		},
	})


func _commands_at(t: float) -> Dictionary:
	var session: Node = main.session
	var throttle := clampf(float(session.start.get("throttle", 0.65)) + 0.08, 0.0, 1.0)
	var c := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = throttle}
	match shot:
		"stik-bank", "wind", "storm":
			c.roll = 0.36 if t >= 0.42 and t < 1.55 else (-0.16 if t >= 1.95 and t < 2.45 else 0.0)
			c.pitch = 0.025
		"jet-pass":
			c.throttle = 0.94
			c.roll = 0.12 if t >= 1.0 and t < 2.15 else 0.0
		"extra-roll":
			c.throttle = 0.94
			c.roll = 0.9 if t < 3.55 else (-0.45 if t < 3.8 else 0.0)
			c.pitch = 0.025
		"mustang-pass":
			c.throttle = 0.9
			c.roll = 0.16 if t >= 0.9 and t < 2.0 else 0.0
		"timber-pass":
			c.throttle = 0.88
			c.roll = -0.12 if t >= 0.65 and t < 1.6 else 0.07 if t >= 2.0 and t < 2.6 else 0.0
		"controls":
			c.roll = 0.5 if t >= 0.38 and t < 1.35 else -0.24 if t >= 1.65 and t < 2.2 else 0.0
			c.pitch = -0.12 if t >= 2.45 and t < 2.85 else 0.0
		"crash":
			c.throttle = 0.82
			c.roll = 0.12 if t < 0.55 else 0.0
			c.pitch = -1.0 if t >= 0.4 else 0.0 # Real pilot input: a sustained push-over, not a fabricated impact.
		_:
			c.roll = 0.24 if t >= 0.5 and t < 1.6 else 0.0
	return c


func _on_sim_stepped(tick: int, time_s: float, state: PackedFloat64Array, _loads: PackedFloat64Array,
		inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	var commands: Dictionary = main.session.commands
	tick_records.append({
		tick = tick,
		time_s = time_s,
		input_vector = Array(inputs),
		commands = commands.duplicate(true),
		state_ned_position_m = _slice(state, RB.POS, 3),
		state_ned_attitude_wxyz = _slice(state, RB.ATT, 4),
		actual_surface_state = _slice(aux, main.session.AUX_SERVO, 3),
		shaft_rpm = float(aux[0]) if aux.size() > 0 else 0.0,
	})


func _place_camera(t: float) -> void:
	var aircraft: Node3D = main._airplane.root
	var body: Basis = aircraft.global_basis.orthonormalized()
	var center: Vector3 = aircraft.global_position
	var forward: Vector3 = -body.z.normalized()
	var right: Vector3 = Vector3(body.x.x, 0.0, body.x.z).normalized()
	if right.length_squared() < 0.9:
		right = Vector3.RIGHT
	if shot == "extra-roll":
		# Keep the hero camera on a world-horizontal chase rail so the aircraft's axial roll
		# rotates in frame without dragging the camera around its body axis.
		forward = Vector3(-body.z.x, 0.0, -body.z.z).normalized()
		if forward.length_squared() < 0.9:
			forward = Vector3.FORWARD
		right = forward.cross(Vector3.UP).normalized()
	var elapsed: float = clampf(t / maxf(duration_s, 0.001), 0.0, 1.0)
	var distance := 5.5
	var height := 1.6
	var lateral := 1.2
	var fov := 36.0
	match shot:
		"jet-pass":
			distance = lerpf(10.0, 4.5, elapsed)
			height = lerpf(2.0, 1.2, elapsed)
			lateral = lerpf(-2.5, 1.7, elapsed)
			fov = 35.0
		"extra-roll":
			distance = lerpf(7.0, 4.8, elapsed)
			height = lerpf(1.9, 1.35, elapsed)
			lateral = 1.8 * sin(elapsed * PI)
			fov = 37.0
		"mustang-pass":
			distance = lerpf(8.0, 5.1, elapsed)
			height = lerpf(2.15, 1.4, elapsed)
			lateral = lerpf(-1.8, 1.5, elapsed)
			fov = 36.0
		"timber-pass":
			distance = lerpf(7.0, 4.7, elapsed)
			height = lerpf(1.9, 1.25, elapsed)
			lateral = 1.8 * sin(elapsed * PI * 0.9)
			fov = 36.0
		"crash":
			distance = 7.5
			height = 1.9
			lateral = 1.2
			fov = 39.0
		_:
			# A three-part close orbit, staying inside the requested 4–7 m hero framing band.
			if elapsed < 0.28:
				var beat := smoothstep(0.0, 1.0, elapsed / 0.28)
				distance = lerpf(7.0, 4.7, beat)
				height = lerpf(1.9, 1.35, beat)
				lateral = lerpf(-1.6, 1.1, beat)
			elif elapsed < 0.72:
				var beat := smoothstep(0.0, 1.0, (elapsed - 0.28) / 0.44)
				distance = lerpf(4.7, 5.5, beat)
				height = lerpf(1.35, 1.7, beat)
				lateral = lerpf(1.1, -1.4, beat)
			else:
				var beat := smoothstep(0.0, 1.0, (elapsed - 0.72) / 0.28)
				distance = lerpf(5.5, 7.0, beat)
				height = lerpf(1.7, 2.0, beat)
				lateral = lerpf(-1.4, -2.0, beat)
	var look_ahead := 0.5 if shot != "crash" else 0.0
	var look_target: Vector3 = center + forward * look_ahead + Vector3.UP * 0.22
	main._camera.global_position = center - forward * distance + right * lateral + Vector3.UP * height
	main._camera.look_at(look_target, Vector3.UP)
	main._camera.fov = fov


func _smoke_evidence() -> Dictionary:
	var smoke: Node = main._smoke
	if smoke == null:
		return {available = false}
	var anchor: Dictionary = smoke.get("_anchor")
	var emitter_position := Vector3.ZERO
	var emitter_direction := Vector3.BACK
	if not anchor.is_empty():
		emitter_position = main._airplane.root.global_transform * anchor.position
		emitter_direction = (main._airplane.root.global_basis * anchor.direction).normalized()
	return {
		available = true,
		pump_supported = smoke.supports_pump(),
		levels = smoke.levels.duplicate(true),
		presented_time_s = float(smoke.presented_s),
		last_interval_s = float(smoke.last_interval_s),
		exhaust_emitting = smoke.exhaust.emitting if smoke.exhaust != null else false,
		pump_emitting = smoke.pump.emitting if smoke.pump != null else false,
		emitter_world_position_m = _v3(emitter_position),
		emitter_world_direction = _v3(emitter_direction),
	}


func _slice(values: PackedFloat64Array, start: int, count: int) -> Array:
	var result: Array = []
	for i: int in range(start, mini(start + count, values.size())):
		result.append(float(values[i]))
	return result


func _v3(value: Vector3) -> Array[float]:
	return [float(value.x), float(value.y), float(value.z)]


func _quat(value: Quaternion) -> Array[float]:
	return [float(value.x), float(value.y), float(value.z), float(value.w)]


func _basis_rows(value: Basis) -> Array:
	return [
		[float(value.x.x), float(value.y.x), float(value.z.x)],
		[float(value.x.y), float(value.y.y), float(value.z.y)],
		[float(value.x.z), float(value.y.z), float(value.z.z)],
	]
