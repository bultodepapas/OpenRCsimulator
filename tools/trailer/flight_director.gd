## Narrowly scoped external controller/camera/evidence node for capture_flight.gd.
## It only supplies existing pilot commands before a tick and reads accepted simulation/render state.
extends Node

const RB := preload("res://physics/rigid_body.gd")
const Exposure := preload("res://render/world/exposure.gd")

var main: Node
var shot := "stik-bank"
var duration_s := 4.0
var fps := 60
var tick_records: Array[Dictionary] = []
var frame_records: Array[Dictionary] = []
var record_tick_evidence := true # Real-time frame measurements avoid allocating a second full tick log.
var _gear_keys: Array[String] = ["left", "right", "nose", "tail"]
var _post_report_restart := false
var _last_state := PackedFloat64Array() # TRA-09: latest accepted state for the Corsair run-up hold.
var _run_up_altitude_m := -1.0
const CORSAIR_TOP_RUDDER := 1.0 # Sign verified against measured nose drop in knife-edge.


func configure(flight_main: Node, shot_name: String, shot_duration_s: float, output_fps: int) -> void:
	main = flight_main
	shot = shot_name
	duration_s = shot_duration_s
	fps = output_fps
	process_physics_priority = -2 # FlightSession is -1: stage this tick's inputs before the real solver node.
	process_priority = 10 # Main renders first; this node then places the cinematic camera before draw.
	main.session.input_enabled = false
	main.session.sim.stepped.connect(_on_sim_stepped)
	if shot != "lighting-pilot":
		main._rig.set_view("chase")
		main._rig.auto_zoom = false


func resume_after_report_restart() -> void:
	_post_report_restart = true


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
	if shot == "lighting-pilot":
		return # Production pilot rig and magnifier own both cameras for this acceptance view.
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
	var lighting: Node = main.get("_rgb_lighting")
	if is_instance_valid(lighting):
		frame_records[-1]["aircraft_lighting"] = lighting.budget_info()
		frame_records[-1]["world_exposure"] = Exposure.last
	var magnifier: Node = main.get("_magnifier")
	if is_instance_valid(magnifier) and magnifier.shown:
		frame_records[-1]["magnifier"] = {
			"shown": true, "mode": magnifier.mode,
			"viewport_size": [magnifier.camera.get_viewport().size.x, magnifier.camera.get_viewport().size.y],
			"msaa_3d": magnifier.camera.get_viewport().msaa_3d,
			"hdr_2d": magnifier.camera.get_viewport().use_hdr_2d,
			"camera_position_m": _v3(magnifier.camera.global_position),
			"camera_fov_deg": magnifier.camera.fov,
		}


func _commands_at(t: float) -> Dictionary:
	var session: Node = main.session
	var throttle := clampf(float(session.start.get("throttle", 0.65)) + 0.08, 0.0, 1.0)
	var c := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = throttle}
	if shot == "crash" and _post_report_restart:
		# Resume the native reset into its trimmed airborne start for the final two source seconds.
		return c
	match shot:
		"lighting-pass", "lighting-pilot":
			pass # Same trimmed start and neutral controls for matched lighting-only captures.
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
		"corsair-roll": # TRA-09: full-throttle run-up, then one axial roll; identical for every livery take.
			c.throttle = 1.0
			# Run-up to top speed, nose raised before entry, then aileron held with top rudder
			# in knife-edge and forward stick inverted (axial-roll technique).
			if t < 9.0:
				c = _corsair_run_up(c, 0.21 if t >= 8.3 else NAN)
			else:
				var bank: float = _attitude().x
				c.roll = 1.0
				c.yaw = CORSAIR_TOP_RUDDER * 0.6 * sin(bank)
				c.pitch = 0.06 * cos(bank)
		"mini-pass":
			pass # TRA-09: neutral trimmed flight keeps the 10 % model off the grass.
		"mustang-pass", "corsair-pass": # TRA-09 reuses the warbird pass for the F4U.
			c.throttle = 0.9
			c.roll = 0.16 if t >= 0.9 and t < 2.0 else 0.0
		"timber-pass", "x8-pass": # TRA-09 reuses the electric pass for the X8 wing.
			c.throttle = 0.88
			c.roll = -0.12 if t >= 0.65 and t < 1.6 else 0.07 if t >= 2.0 and t < 2.6 else 0.0
		"controls":
			c.roll = 0.5 if t >= 0.38 and t < 1.35 else -0.24 if t >= 1.65 and t < 2.2 else 0.0
			c.pitch = -0.12 if t >= 2.45 and t < 2.85 else 0.0
		"crash":
			c.throttle = 1.0
			c.roll = 0.0
			c.pitch = -0.2 # Shallow, straight low approach: keep the propeller disc ahead of the spinner/hull contact.
		_:
			c.roll = 0.24 if t >= 0.5 and t < 1.6 else 0.0
	return c


## TRA-09: pilot-like wings-level, altitude-hold stick during the full-throttle run-up.
## pitch_override_rad (when finite) replaces altitude hold with a fixed nose-up attitude.
func _corsair_run_up(c: Dictionary, pitch_override_rad := NAN) -> Dictionary:
	c.roll = 0.0
	c.pitch = 0.0
	if _last_state.size() < RB.ATT + 4:
		return c
	var attitude: Vector2 = _attitude()
	var bank: float = attitude.x
	var pitch: float = attitude.y
	var altitude: float = -_last_state[RB.POS + 2]
	if _run_up_altitude_m < 0.0:
		_run_up_altitude_m = altitude
	var pitch_target: float = clampf(0.03 * (_run_up_altitude_m - altitude), -0.08, 0.08)
	if is_finite(pitch_override_rad):
		pitch_target = pitch_override_rad
	c.roll = clampf(-1.5 * bank, -0.5, 0.5)
	c.pitch = clampf(2.5 * (pitch_target - pitch), -0.4, 0.4)
	return c


## Bank (x) and pitch (y) in radians from the latest accepted NED attitude.
func _attitude() -> Vector2:
	if _last_state.size() < RB.ATT + 4:
		return Vector2.ZERO
	var w: float = _last_state[RB.ATT]
	var x: float = _last_state[RB.ATT + 1]
	var y: float = _last_state[RB.ATT + 2]
	var z: float = _last_state[RB.ATT + 3]
	return Vector2(atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y)),
		asin(clampf(2.0 * (w * y - z * x), -1.0, 1.0)))


func _on_sim_stepped(tick: int, time_s: float, state: PackedFloat64Array, _loads: PackedFloat64Array,
		inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	_last_state = state
	if not record_tick_evidence:
		return
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
	if shot == "companions" and _frame_companions():
		return
	var aircraft: Node3D = main._airplane.root
	var body: Basis = aircraft.global_basis.orthonormalized()
	var center: Vector3 = aircraft.global_position
	var forward: Vector3 = -body.z.normalized()
	var right: Vector3 = Vector3(body.x.x, 0.0, body.x.z).normalized()
	if right.length_squared() < 0.9:
		right = Vector3.RIGHT
	if shot == "extra-roll" or shot == "corsair-roll":
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
		"extra-roll", "corsair-roll":
			distance = lerpf(7.0, 4.8, elapsed)
			height = lerpf(1.9, 1.35, elapsed)
			lateral = 1.8 * sin(elapsed * PI)
			fov = 37.0
		"mustang-pass", "corsair-pass":
			distance = lerpf(8.0, 5.1, elapsed)
			height = lerpf(2.15, 1.4, elapsed)
			lateral = lerpf(-1.8, 1.5, elapsed)
			fov = 36.0
		"timber-pass", "x8-pass":
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
	# TRA-09 Workshop size shots keep the default orbit, framed in proportion to the virtual size.
	var size_frame := 0.24 if shot == "mini-pass" else (2.6 if shot == "giant-pass" else 1.0)
	distance *= size_frame
	height *= size_frame
	lateral *= size_frame
	var look_ahead := (0.5 if shot != "crash" else 0.0) * size_frame
	var look_target: Vector3 = center + forward * look_ahead + Vector3.UP * 0.22 * size_frame
	main._camera.global_position = center - forward * distance + right * lateral + Vector3.UP * height
	main._camera.look_at(look_target, Vector3.UP)
	main._camera.fov = fov


## TRA-09: chase the first live AI companion and widen until its nearest neighbor shares the frame.
func _frame_companions() -> bool:
	var manager: Node = main.get("companions")
	if manager == null:
		return false
	var roots: Array[Node3D] = []
	for agent: Node in manager.agents:
		if is_instance_valid(agent) and str(agent.failure).is_empty() and not agent.view.is_empty():
			roots.append(agent.view.root)
	roots.append(main._airplane.root)
	if roots.size() < 2:
		return false
	var lead: Node3D = roots[0]
	var other: Node3D = roots[1]
	for candidate: Node3D in roots.slice(2):
		if candidate.global_position.distance_to(lead.global_position) < other.global_position.distance_to(lead.global_position):
			other = candidate
	var forward: Vector3 = -lead.global_basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	if forward.length_squared() < 0.9:
		forward = Vector3.FORWARD
	var mid: Vector3 = (lead.global_position + other.global_position) * 0.5
	var spread: float = minf(lead.global_position.distance_to(other.global_position), 120.0)
	var distance: float = 9.0 + spread * 0.9
	main._camera.global_position = lead.global_position - forward * distance + forward.cross(Vector3.UP) * 3.0 + Vector3.UP * (2.5 + spread * 0.15)
	main._camera.look_at(mid if spread < 120.0 else lead.global_position, Vector3.UP)
	main._camera.fov = 40.0
	return true


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
