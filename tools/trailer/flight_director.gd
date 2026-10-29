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
# TRA-10: presentation-only livery cycle on one flight (--livery-cycle=a,b,... --livery-from=s --livery-every=s).
# Each livery is another GLB of the same airframe; only MeshInstance3D resources are swapped, never physics.
const ORBIT_BANK_RAD := -0.17 # Light left bank (about 10 degrees) held through the orbit pass.
const ORBIT_ALTITUDE_M := 6.0
var _liveries: Array[Dictionary] = []
var _livery_from_s := 1.0
var _livery_every_s := 0.6
var _livery_active := ""
var _livery_matched := 0
var _orbit_previous_altitude_m := NAN
var _orbit_altitude_integral := 0.0


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
	_load_livery_cycle()


## TRA-10: preload every requested livery scene's meshes, keyed by node name in scene order.
func _load_livery_cycle() -> void:
	var ids := PackedStringArray()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--livery-cycle="):
			ids = arg.trim_prefix("--livery-cycle=").split(",", false)
		elif arg.begins_with("--livery-from="):
			_livery_from_s = arg.trim_prefix("--livery-from=").to_float()
		elif arg.begins_with("--livery-every="):
			_livery_every_s = maxf(arg.trim_prefix("--livery-every=").to_float(), 1.0 / 60.0)
	if ids.is_empty():
		return
	var records: Array = main._airplane.get("model_manifest", {}).get("liveries", [])
	for id: String in ids:
		var found: Array = records.filter(func(r: Dictionary) -> bool: return str(r.id) == id)
		var scene: PackedScene = load(str(found[0].path)) as PackedScene if not found.is_empty() else null
		if scene == null:
			push_error("TRA-10 livery cycle: unknown livery " + id)
			_liveries.clear()
			return
		var instance: Node = scene.instantiate()
		_liveries.append({id = id, meshes = _mesh_table(instance)})
		instance.free()
	print("FLIGHT_CAPTURE_LIVERY_CYCLE ", ",".join(ids), " from=", _livery_from_s, " every=", _livery_every_s)


func _mesh_table(root: Node) -> Dictionary:
	var table := {}
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var overrides: Array = []
		for i: int in mesh.get_surface_override_material_count():
			overrides.append(mesh.get_surface_override_material(i))
		var key := str(mesh.name)
		if not table.has(key):
			table[key] = []
		table[key].append({mesh = mesh.mesh, overrides = overrides, material_override = mesh.material_override})
	return table


func _apply_livery_cycle(t: float) -> void:
	if _liveries.is_empty():
		return
	var index := 0 if t < _livery_from_s else 1 + int(floor((t - _livery_from_s) / _livery_every_s))
	var entry: Dictionary = _liveries[index % _liveries.size()]
	if entry.id == _livery_active:
		return
	var seen := {}
	_livery_matched = 0
	for node: Node in main._airplane.root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var key := str(mesh.name)
		var ordinal: int = seen.get(key, 0)
		seen[key] = ordinal + 1
		var sources: Array = entry.meshes.get(key, [])
		if ordinal >= sources.size():
			continue
		var source: Dictionary = sources[ordinal]
		mesh.mesh = source.mesh
		for i: int in source.overrides.size():
			mesh.set_surface_override_material(i, source.overrides[i])
		mesh.material_override = source.material_override
		_livery_matched += 1
	_livery_active = entry.id


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
	_apply_livery_cycle(float(main.session.sim.time()))
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
	if not _liveries.is_empty():
		frame_records[-1]["presented_livery"] = {id = _livery_active, meshes_swapped = _livery_matched}
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
		"corsair-orbit": # TRA-10: low pass holding a light left bank and altitude while the camera orbits.
			c.throttle = 0.85
			c = _corsair_run_up(c, NAN, ORBIT_BANK_RAD, ORBIT_ALTITUDE_M)
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
## TRA-10: bank_rad holds a bank instead of wings level; a finite altitude_m eases the hold toward that height.
func _corsair_run_up(c: Dictionary, pitch_override_rad := NAN, bank_rad := 0.0, altitude_m := NAN) -> Dictionary:
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
	var trim := 0.0
	if is_finite(altitude_m):
		# Low pass: altitude error, climb-rate damping and an integral trim hold the height at full speed.
		var dt: float = main.session.sim.dt()
		var climb: float = 0.0 if is_nan(_orbit_previous_altitude_m) else (altitude - _orbit_previous_altitude_m) / dt
		_orbit_previous_altitude_m = altitude
		_orbit_altitude_integral = clampf(_orbit_altitude_integral + (altitude_m - altitude) * dt, -20.0, 20.0)
		pitch_target = clampf(0.05 * (altitude_m - altitude) - 0.08 * climb, -0.2, 0.15)
		trim = 0.02 * _orbit_altitude_integral
	if is_finite(pitch_override_rad):
		pitch_target = pitch_override_rad
	c.roll = clampf(-1.5 * (bank - bank_rad), -0.5, 0.5)
	c.pitch = clampf(2.5 * (pitch_target - pitch) + trim, -0.4, 0.4)
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
	if shot == "corsair-orbit":
		_orbit_camera(t)
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


## TRA-10: one full 360-degree orbit in the aircraft's heading frame over the shot, eased at both ends,
## starting off the front-left quarter and passing the nose, the right side, the tail and back.
func _orbit_camera(t: float) -> void:
	var aircraft: Node3D = main._airplane.root
	var center: Vector3 = aircraft.global_position
	var forward: Vector3 = -aircraft.global_basis.z
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	if forward.length_squared() < 0.9:
		forward = Vector3.FORWARD
	var right: Vector3 = forward.cross(Vector3.UP)
	var p: float = smoothstep(0.0, 1.0, clampf(t / maxf(duration_s, 0.001), 0.0, 1.0))
	var angle: float = deg_to_rad(-40.0) + TAU * p # 0 = straight ahead, positive toward the right wing.
	var radius := 7.0
	var offset: Vector3 = (forward * cos(angle) + right * sin(angle)) * radius
	main._camera.global_position = center + offset + Vector3.UP * (0.9 + 0.5 * sin(PI * p))
	main._camera.look_at(center + Vector3.UP * 0.2, Vector3.UP)
	main._camera.fov = 34.0


## TRA-09: hero chase of the first live AI companion; the rest of the traffic stays in the scene behind it.
func _frame_companions() -> bool:
	var manager: Node = main.get("companions")
	if manager == null:
		return false
	for agent: Node in manager.agents:
		if is_instance_valid(agent) and str(agent.failure).is_empty() and not agent.view.is_empty():
			var lead: Node3D = agent.view.root
			var forward: Vector3 = -lead.global_basis.z
			forward = Vector3(forward.x, 0.0, forward.z).normalized()
			if forward.length_squared() < 0.9:
				forward = Vector3.FORWARD
			var right: Vector3 = forward.cross(Vector3.UP)
			main._camera.global_position = lead.global_position - forward * 7.0 + right * 2.2 + Vector3.UP * 2.0
			main._camera.look_at(lead.global_position + forward * 1.5, Vector3.UP)
			main._camera.fov = 24.0
			return true
	return false


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
