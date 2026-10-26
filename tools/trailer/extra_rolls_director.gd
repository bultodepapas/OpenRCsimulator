## Independent six-second Extra roll sequence for the real trailer capture harness.
## Supplies only ordinary pilot commands and a chase camera; flight state is always the live simulation.
extends Node

const RB := preload("res://physics/rigid_body.gd")

var main: Node
var duration_s := 6.0
var fps := 60
var tick_records: Array[Dictionary] = []
var frame_records: Array[Dictionary] = []
var _previous_roll_rad := NAN
var _unwrapped_roll_deg := 0.0
var _control_previous_roll_rad := NAN
var _control_unwrapped_roll_deg := 0.0
var _control_bank_rad := 0.0
var _latest_body_roll_rate_radps := 0.0
var _roll_brake_started := false
var _minimum_altitude_m := INF
var _maximum_altitude_m := -INF
var _inside_frame_count := 0
var _inspection_camera := false


func configure(flight_main: Node, shot_name: String, shot_duration_s: float, output_fps: int) -> void:
	main = flight_main
	duration_s = shot_duration_s
	fps = output_fps
	_inspection_camera = shot_name == "extra-roll-inspection"
	if shot_name not in ["extra-roll", "extra-roll-inspection"]:
		push_error("extra_rolls_director requires extra-roll or extra-roll-inspection")
	process_physics_priority = -2 # Stage commands before FlightSession's physics tick.
	process_priority = 10 # Place the camera after Main updates the real rendered aircraft.
	main.session.input_enabled = false
	main.session.sim.stepped.connect(_on_sim_stepped)
	main._rig.set_view("chase")
	main._rig.auto_zoom = false


func _physics_process(_delta: float) -> void:
	if main == null or main.session == null or not main.session.crash.is_empty() or main.session.sim.paused:
		return
	var session: Node = main.session
	var t: float = float(session.sim.tick) * session.sim.dt()
	var controls := _commands_at(t)
	session.commands = controls.duplicate(true)
	session.raw = controls.duplicate(true)
	session.sim.inputs = session._inputs()


func _process(_delta: float) -> void:
	if main == null or main._camera == null or main._airplane.is_empty():
		return
	_place_camera()


func record_presented_frame(frame_index: int, preroll_frames: int) -> void:
	if main == null or main.session == null or main._airplane.is_empty():
		return
	var session: Node = main.session
	var sim: Node = session.sim
	var aircraft: Node3D = main._airplane.root
	var transform := aircraft.global_transform
	var state: PackedFloat64Array = sim.interpolated(Engine.get_physics_interpolation_fraction())
	var altitude_m := -float(state[RB.POS + 2])
	var wrapped_roll_rad := _projected_roll_angle(transform.basis.orthonormalized())
	if is_finite(_previous_roll_rad):
		var delta_rad := wrapf(wrapped_roll_rad - _previous_roll_rad, -PI, PI)
		_unwrapped_roll_deg += rad_to_deg(delta_rad)
	else:
		_unwrapped_roll_deg = 0.0
	_previous_roll_rad = wrapped_roll_rad
	_minimum_altitude_m = minf(_minimum_altitude_m, altitude_m)
	_maximum_altitude_m = maxf(_maximum_altitude_m, altitude_m)
	var camera: Camera3D = main._camera
	var viewport_size := get_viewport().get_visible_rect().size
	var center_px := camera.unproject_position(transform.origin)
	var bounds := _visible_mesh_bounds(camera, viewport_size)
	if bool(bounds.get("intersects_viewport", false)):
		_inside_frame_count += 1
	var prop: Node3D = main._airplane.get("propeller")
	frame_records.append({
		frame = frame_index,
		capture_time_s = float(frame_index) / float(fps),
		preroll_frames = preroll_frames,
		sim_tick = int(sim.tick),
		sim_time_s = float(sim.time()),
		altitude_m = altitude_m,
		unwrapped_roll_deg = _unwrapped_roll_deg,
		wrapped_roll_deg = rad_to_deg(wrapped_roll_rad),
		body_roll_rate_radps = float(state[RB.RATE]),
		state_ned_position_m = _slice(state, RB.POS, 3),
		state_ned_attitude_wxyz = _slice(state, RB.ATT, 4),
		aircraft_root_world_position_m = _v3(transform.origin),
		aircraft_root_world_quaternion_xyzw = _quat(transform.basis.get_rotation_quaternion().normalized()),
		aircraft_root_world_basis_rows = _basis_rows(transform.basis),
		actual_surface_angles_deg = session.surface_angles_deg(),
		actual_surface_commands = session.surfaces(),
		landing_gear_state = session.gear_state(),
		propeller = {
			angle_rad = float(prop.rotation.z) if prop != null else 0.0,
			shaft_rpm = float(sim.aux[0]) if sim.aux.size() > 0 else 0.0,
		},
		camera = {
			inspection_framing = _inspection_camera,
			position_m = _v3(camera.global_position),
			quaternion_xyzw = _quat(camera.global_basis.get_rotation_quaternion()),
			fov_deg = float(camera.fov),
			aircraft_center_px = [float(center_px.x), float(center_px.y)],
			aircraft_mesh_bounds_px = bounds,
		},
	})


func capture_summary() -> Dictionary:
	return {
		frames_with_aircraft_mesh_in_view = _inside_frame_count,
		minimum_altitude_m = _minimum_altitude_m,
		maximum_altitude_m = _maximum_altitude_m,
		final_unwrapped_roll_deg = _unwrapped_roll_deg,
		completed_axial_rolls = int(floor(absf(_unwrapped_roll_deg) / 360.0)),
	}


func _commands_at(t: float) -> Dictionary:
	# Use aileron to cross two rolls, then counter only while measured body roll is
	# still fast. Modest elevator/rudder inputs follow the live bank through the
	# maneuver so recovery begins before the second roll is complete.
	if _control_unwrapped_roll_deg >= 740.0:
		_roll_brake_started = true
	var roll := 1.0
	if _roll_brake_started:
		if _latest_body_roll_rate_radps > 0.65:
			roll = -0.45
		elif _latest_body_roll_rate_radps < -0.65:
			roll = 0.45
		else:
			roll = 0.0
	var pitch := clampf(0.15 + 0.40 * cos(_control_bank_rad), -0.25, 0.55)
	var yaw := 0.08 * sin(_control_bank_rad)
	return {roll = roll, pitch = pitch, yaw = yaw, throttle = 1.0}


func _on_sim_stepped(tick: int, time_s: float, state: PackedFloat64Array, _loads: PackedFloat64Array,
		inputs: PackedFloat64Array, aux: PackedFloat64Array) -> void:
	var session: Node = main.session
	var attitude := _slice(state, RB.ATT, 4)
	if attitude.size() == 4:
		var attitude_basis := Basis(Quaternion(attitude[1], attitude[2], attitude[3], attitude[0]))
		_control_bank_rad = _projected_ned_roll_angle(attitude_basis)
		if is_finite(_control_previous_roll_rad):
			_control_unwrapped_roll_deg += rad_to_deg(wrapf(_control_bank_rad - _control_previous_roll_rad, -PI, PI))
		_control_previous_roll_rad = _control_bank_rad
	_latest_body_roll_rate_radps = float(state[RB.RATE])
	tick_records.append({
		tick = tick,
		time_s = time_s,
		pilot_commands = _commands_at(time_s),
		pilot_bank_phase_deg = rad_to_deg(_control_bank_rad),
		pilot_unwrapped_roll_deg = _control_unwrapped_roll_deg,
		commands = session.commands.duplicate(true),
		input_vector = Array(inputs),
		state_ned_position_m = _slice(state, RB.POS, 3),
		state_ned_attitude_wxyz = _slice(state, RB.ATT, 4),
		state_body_velocity_mps = _slice(state, RB.VEL, 3),
		state_body_rates_radps = _slice(state, RB.RATE, 3),
		actual_surface_angles_deg = session.surface_angles_deg(),
		shaft_rpm = float(aux[0]) if aux.size() > 0 else 0.0,
	})


func _projected_ned_roll_angle(body: Basis) -> float:
	var forward := body.x.normalized()
	var body_up := -body.z
	var world_up := Vector3(0.0, 0.0, -1.0)
	body_up -= forward * body_up.dot(forward)
	world_up -= forward * world_up.dot(forward)
	if body_up.length_squared() < 1.0e-8 or world_up.length_squared() < 1.0e-8:
		return 0.0
	return world_up.normalized().signed_angle_to(body_up.normalized(), forward)


func _place_camera() -> void:
	var aircraft: Node3D = main._airplane.root
	var body := aircraft.global_basis.orthonormalized()
	var center := aircraft.global_position
	var forward := Vector3(-body.z.x, 0.0, -body.z.z).normalized()
	if forward.length_squared() < 0.9:
		forward = Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var elapsed := clampf(float(main.session.sim.time()) / maxf(duration_s, 0.001), 0.0, 1.0)
	var distance := lerpf(4.25, 3.75, elapsed)
	var height := lerpf(1.55, 1.25, elapsed)
	var lateral := 0.85 * sin(elapsed * PI)
	if _inspection_camera:
		# Keep the original trailer rail intact. The inspection rail leaves room
		# for the complete airframe during both rolls at native 1920x1080.
		distance *= 1.7
		height *= 1.7
		lateral *= 1.7
	main._camera.global_position = center - forward * distance + right * lateral + Vector3.UP * height
	main._camera.look_at(center + forward * 0.45 + Vector3.UP * 0.2, Vector3.UP)
	main._camera.fov = 37.0


func _projected_roll_angle(body: Basis) -> float:
	var forward := (-body.z).normalized()
	var body_up := body.y - forward * body.y.dot(forward)
	var world_up := Vector3.UP - forward * Vector3.UP.dot(forward)
	if body_up.length_squared() < 1.0e-8 or world_up.length_squared() < 1.0e-8:
		return 0.0
	body_up = body_up.normalized()
	world_up = world_up.normalized()
	return world_up.signed_angle_to(body_up, forward)


func _visible_mesh_bounds(camera: Camera3D, viewport_size: Vector2) -> Dictionary:
	var points: Array[Vector2] = []
	var stack: Array[Node] = [main._airplane.root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child: Node in node.get_children():
			stack.append(child)
		if not node is MeshInstance3D or not node.visible:
			continue
		var mesh_instance := node as MeshInstance3D
		var bounds := mesh_instance.get_aabb()
		for x: float in [bounds.position.x, bounds.position.x + bounds.size.x]:
			for y: float in [bounds.position.y, bounds.position.y + bounds.size.y]:
				for z: float in [bounds.position.z, bounds.position.z + bounds.size.z]:
					var world_point := mesh_instance.global_transform * Vector3(x, y, z)
					if not camera.is_position_behind(world_point):
						points.append(camera.unproject_position(world_point))
	if points.is_empty():
		return {visible_corner_count = 0, intersects_viewport = false}
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for point: Vector2 in points:
		min_x = minf(min_x, point.x)
		min_y = minf(min_y, point.y)
		max_x = maxf(max_x, point.x)
		max_y = maxf(max_y, point.y)
	return {
		visible_corner_count = points.size(),
		min_x_px = min_x,
		min_y_px = min_y,
		max_x_px = max_x,
		max_y_px = max_y,
		intersects_viewport = max_x >= 0.0 and min_x <= viewport_size.x and max_y >= 0.0 and min_y <= viewport_size.y,
	}


func _slice(values: PackedFloat64Array, start: int, count: int) -> Array[float]:
	var result: Array[float] = []
	for index: int in range(start, mini(start + count, values.size())):
		result.append(float(values[index]))
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
