## BL-10/BL-12: playable RC blimp activity on the shared airfield. Physics belongs exclusively to the airship
## session (sim/airship/session.gd); this node samples the pilot input once per 240 Hz tick, draws the interpolated
## accepted state, and owns camera, HUD, sound and the pause menu. Graphics settings never change physics.
extends Node3D

const Session = preload("res://sim/airship/session.gd")
const PilotInput = preload("res://input/airship_input.gd")
const Visual = preload("res://vehicles/airship/airship_visual.gd")
const Hud = preload("res://vehicles/airship/airship_hud.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const World = preload("res://render/world/world.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const TimeOfDayLighting = preload("res://render/time_of_day_lighting.gd")
const SkyConfig = preload("res://environment/sky_appearance_config.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Frames = preload("res://render/frames.gd")
const Spec = preload("res://spec.gd")
const CollisionSetup = preload("res://scenery/collision_setup.gd")

const DATA_PATH := "res://data/airships/rc-blimp-5m.json"
const MOTOR_AUDIO := "res://assets/audio/powertrains/electric_quad.wav"
const MOTOR_AUDIO_REFERENCE_HZ := 232.1
const FULL_SPEED_RPM := 7800.0
const BLADES := 3.0
const CAMERA_NAMES := ["chase", "pilot", "orbit"]

signal home_requested

var startup_error := ""
var skin_id := "tiburon-blanco"
var departure_managed := false
var controller_registry: RefCounted
var field_path: String = FieldLoader.DEFAULT_PATH
var lighting_config: Dictionary = LightingConfig.defaults()
var night_options := {}
var sky_config: Dictionary = SkyConfig.defaults()
var enable_audio := true
var enable_world := true
## Deterministic test seam: tick -> [roll, pitch, yaw, throttle]; sampled only on physics ticks.
var scripted_sticks := Callable()

var session: Node
var visual: RefCounted
var hud: CanvasLayer
var camera: Camera3D
var input = PilotInput.new()
var field := {}
var presentation := {}
var camera_mode := 0
var ballast_index := 2
var wind_index := 0
var start_index := 0
var _lighting := {}
var _environment: Environment
var _last_input := {}
var _orbit_yaw := 0.6
var _orbit_pitch := 0.25
var _orbit_distance := 10.0
var _chase_heading := 0.0
var _audio_side: AudioStreamPlayer3D
var _audio_stern: AudioStreamPlayer3D
var _pilot_position := Vector3.ZERO


func _ready() -> void:
	name = "AirshipActivity"
	if not _load_field() or not _load_presentation():
		_disable()
		return
	session = Session.new()
	session.name = "AirshipSession"
	add_child(session)
	var obstacles: Dictionary = CollisionSetup.build(field)
	if not obstacles.ok or not session.set_collision_world(obstacles.world):
		startup_error = "Blimp obstacle inventory refused: " + "; ".join(obstacles.get("errors", []))
		_disable()
		return
	if not session.prepare(field, _session_options()):
		startup_error = "Blimp could not be prepared: " + str(session.load_error)
		_disable()
		return
	visual = Visual.new()
	var skins := Visual.skins(presentation)
	if skins.is_empty() or not visual.build(presentation, skin_id):
		startup_error = str(visual.error) if not str(visual.error).is_empty() else "No blimp skins are available"
		_disable()
		return
	add_child(visual.root)
	if enable_world:
		Atmosphere.configure_appearance(sky_config)
		_environment = World.build(self, field, _build_field, {}, _lighting, night_options).environment
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = Spec.CAMERA.far
	camera.fov = 60.0
	add_child(camera)
	camera.make_current()
	hud = Hud.new()
	add_child(hud)
	var names: Array = []
	var selected := 0
	for i in skins.size():
		names.append(str(skins[i].name))
		if skins[i].id == skin_id:
			selected = i
	hud.set_skins(names, selected)
	hud.select_choice("ballast", ballast_index)
	hud.select_choice("wind", wind_index)
	hud.select_choice("start", start_index)
	hud.select_choice("camera", camera_mode)
	hud.action_requested.connect(handle_action)
	hud.option_selected.connect(_option_selected)
	session.crashed.connect(func(reason: String) -> void: _open_menu(reason + ". Restart to fly again."))
	session.faulted.connect(func(reason: String) -> void: _open_menu("Simulation paused: " + reason))
	input.connect_first_device()
	Input.joy_connection_changed.connect(_joy_connection_changed)
	if enable_audio:
		_build_audio()
	_chase_heading = deg_to_rad(float(session.options.heading_deg))
	_open_menu(session.pause_reason)
	_process(0.0)


func _disable() -> void:
	set_physics_process(false)
	set_process(false)
	set_process_unhandled_input(false)


func _exit_tree() -> void:
	if Input.joy_connection_changed.is_connected(_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_joy_connection_changed)


func _load_field() -> bool:
	var loaded := FieldLoader.load_from(field_path)
	if not loaded.ok:
		startup_error = "; ".join(loaded.errors)
		return false
	var checked_light := LightingConfig.validate(lighting_config)
	var checked_sky := SkyConfig.validate(sky_config)
	if not checked_light.ok or not checked_sky.ok:
		startup_error = "; ".join(checked_light.errors) + "; ".join(checked_sky.errors)
		return false
	lighting_config = checked_light.config
	sky_config = checked_sky.config
	_lighting = TimeOfDayLighting.snapshot(lighting_config) if lighting_config.mode != "legacy" else {}
	field = loaded.field
	var pilot: Dictionary = field.pilot
	_pilot_position = Frames.ned_to_render([pilot.north, pilot.east, pilot.down - pilot.eye_height])
	return true


func _load_presentation() -> bool:
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("presentation")) != TYPE_DICTIONARY:
		startup_error = "Blimp presentation data is unavailable"
		return false
	presentation = parsed.presentation
	return true


func _build_field() -> void:
	var field_node: Node3D = FieldBuilder.build(field, _lighting, [])
	var lake_error := str(field_node.get_meta("lake_error", ""))
	if not lake_error.is_empty():
		push_warning("Blimp field lake refused: " + lake_error)
	add_child(field_node)


func _session_options() -> Dictionary:
	return {data_path = DATA_PATH, heaviness_kg = Hud.BALLAST_KG[ballast_index], wind_speed_mps = Hud.WIND_MPS[wind_index],
		wind_from_deg = 270.0, start = "air" if start_index == 0 else "ground"}


func _joy_connection_changed(id: int, connected: bool) -> void:
	input.on_connection_changed(id, connected)
	if not session.paused:
		_open_menu(input.message)
	else:
		hud.flash(input.message)


func _input(event: InputEvent) -> void:
	input.on_event(event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_P, KEY_ESCAPE:
				if hud.menu_visible: handle_action("resume")
				else: _open_menu("Paused")
				get_viewport().set_input_as_handled()
			KEY_R:
				handle_action("restart")
				get_viewport().set_input_as_handled()
			KEY_C:
				camera_mode = (camera_mode + 1) % CAMERA_NAMES.size()
				hud.select_choice("camera", camera_mode)
				get_viewport().set_input_as_handled()
			KEY_H:
				hud.help.visible = not hud.help.visible
				get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		if hud.menu_visible: handle_action("resume")
		else: _open_menu("Paused")
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_orbit_yaw -= event.relative.x * 0.005
		_orbit_pitch = clampf(_orbit_pitch + event.relative.y * 0.004, -0.2, 1.3)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: _orbit_distance = maxf(5.5, _orbit_distance * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: _orbit_distance = minf(60.0, _orbit_distance * 1.1)


func _open_menu(reason: String) -> void:
	if session.prepared and not session.paused:
		session.pause(reason)
	var can_resume: bool = session.crash.is_empty() and str(session.fault_reason).is_empty()
	hud.show_menu(reason, can_resume)


func handle_action(action: String) -> void:
	match action:
		"resume":
			if not session.crash.is_empty():
				hud.flash("Restart to fly again.")
				return
			var sample: Dictionary = input.sample(1.0 / 240.0, false)
			if not sample.armed:
				hud.flash("Controls not armed: lower the throttle and check the controller.")
				return
			if not session.resume(sample.sticks):
				hud.flash(str(session.pause_reason))
				return
			hud.hide_menu()
		"restart":
			_restart()
		"help":
			hud.help.visible = not hud.help.visible
		"home":
			session.pause("Leaving")
			home_requested.emit()
			if not departure_managed:
				get_tree().quit()


func _option_selected(option: String, index: int) -> void:
	match option:
		"skin":
			var skins := Visual.skins(presentation)
			if index >= 0 and index < skins.size() and str(skins[index].id) != skin_id:
				_swap_skin(str(skins[index].id))
		"ballast":
			ballast_index = index
			_restart()
		"wind":
			wind_index = index
			_restart()
		"start":
			start_index = index
			_restart()
		"camera":
			camera_mode = index


## A configuration change is a new admitted model: prepare and reset, keeping the old session on refusal.
func _restart() -> void:
	if not session.prepare(field, _session_options()):
		hud.flash("Configuration refused: " + str(session.load_error))
		return
	input.reset_throttle()
	_chase_heading = deg_to_rad(float(session.options.heading_deg))
	_open_menu(session.pause_reason)


func _swap_skin(next_skin: String) -> void:
	var candidate := Visual.new()
	if not candidate.build(presentation, next_skin):
		hud.flash(str(candidate.error))
		return
	visual.root.queue_free()
	visual = candidate
	skin_id = next_skin
	add_child(visual.root)
	_process(0.0)


func _physics_process(_delta: float) -> void:
	if session == null or not session.prepared:
		return
	var integrate: bool = not session.paused
	var sample: Dictionary = input.sample(1.0 / 240.0, integrate)
	if scripted_sticks.is_valid():
		sample = {sticks = scripted_sticks.call(session.sim.tick), armed = true, source = "script", error = "", throttle_low = true}
	_last_input = sample
	if session.paused:
		return
	if not sample.armed or not str(sample.error).is_empty():
		_open_menu("Controls unavailable: " + (str(sample.error) if not str(sample.error).is_empty() else "arm with the throttle low."))
		return
	session.tick_once(sample.sticks)


func _process(delta: float) -> void:
	if session == null or not session.prepared or visual == null:
		return
	var fraction := Engine.get_physics_interpolation_fraction() if not session.paused else 1.0
	var drawn: PackedFloat64Array = session.interpolated(fraction)
	visual.pose(drawn, session.sim.continuous, delta if not session.paused else 0.0)
	var target := Frames.ned_to_render([drawn[0], drawn[1], drawn[2]])
	var basis := Frames.quat_to_render(drawn.slice(6, 10))
	_update_camera(target, basis, delta)
	if _environment != null:
		World.update(_environment, 37.0 + session.sim.time(), Vector3.ZERO, target, camera)
	var t: Dictionary = session.telemetry()
	hud.update(t, _last_input, CAMERA_NAMES[camera_mode])
	_update_audio(target, basis)


func _ground_height_render(x: float, z: float) -> float:
	var h: PackedFloat64Array = session.environment.ground(-z, x)
	return h[0] if h.size() == 3 and is_finite(h[0]) else 0.0


func _update_camera(target: Vector3, basis: Basis, delta: float) -> void:
	var nose := -basis.z
	var heading := atan2(nose.x, -nose.z)
	_chase_heading = lerp_angle(_chase_heading, heading, clampf(delta * 1.2, 0.0, 1.0))
	var eye: Vector3
	match CAMERA_NAMES[camera_mode]:
		"chase":
			var back := Vector3(-sin(_chase_heading), 0.0, cos(_chase_heading))
			eye = target + back * 11.0 + Vector3.UP * 3.2
			camera.fov = 60.0
		"pilot":
			eye = _pilot_position
			var distance := maxf(eye.distance_to(target), 1.0)
			# Keep the 5 m hull near a third of the vertical view, within lens limits.
			camera.fov = clampf(rad_to_deg(2.0 * atan(6.5 / distance)), 12.0, 70.0)
		_:
			var offset := Vector3(sin(_orbit_yaw) * cos(_orbit_pitch), sin(_orbit_pitch), cos(_orbit_yaw) * cos(_orbit_pitch))
			eye = target + offset * _orbit_distance
			camera.fov = 60.0
	eye.y = maxf(eye.y, _ground_height_render(eye.x, eye.z) + 0.4)
	camera.global_position = eye
	if eye.distance_to(target) > 0.01:
		camera.look_at(target, Vector3.UP)


func _build_audio() -> void:
	var stream := load(MOTOR_AUDIO) as AudioStreamWAV
	if stream == null:
		return
	var looped := stream.duplicate() as AudioStreamWAV
	looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looped.loop_begin = 0
	looped.loop_end = int(stream.get_length() * float(stream.mix_rate))
	_audio_side = _motor_player(looped, "SideMotors")
	_audio_stern = _motor_player(looped, "SternMotors")


func _motor_player(stream: AudioStreamWAV, node_name: String) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = node_name
	player.stream = stream
	player.unit_size = 3.0
	player.max_distance = 120.0
	player.volume_db = -80.0
	add_child(player)
	player.play()
	return player


func _update_audio(target: Vector3, basis: Basis) -> void:
	if _audio_side == null:
		return
	var c: PackedFloat64Array = session.sim.continuous
	var side := maxf(absf(c[0]), absf(c[1]))
	var stern := maxf(absf(c[2]), absf(c[3]))
	_motor_sound(_audio_side, side, target + basis * Vector3(0.0, -0.17, -0.8))
	_motor_sound(_audio_stern, stern, target + basis * Vector3(0.0, 0.0, 2.45))


func _motor_sound(player: AudioStreamPlayer3D, n: float, position: Vector3) -> void:
	player.global_position = position
	var silent: bool = session.paused or n < 0.02
	player.stream_paused = silent
	if silent:
		return
	var blade_hz := FULL_SPEED_RPM * n * BLADES / 60.0
	player.pitch_scale = clampf(blade_hz / MOTOR_AUDIO_REFERENCE_HZ, 0.35, 2.5)
	player.volume_db = linear_to_db(clampf(0.15 + 0.85 * n * n, 0.001, 1.0)) - 6.0


## AppRoot controller hooks shared with the ground activity slot.
func apply_controller_selection(_device_id: int) -> bool:
	return true


func _refresh_controller_ui() -> void:
	pass
