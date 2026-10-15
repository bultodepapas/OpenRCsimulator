## Playable ground-vehicle activity. Physics belongs exclusively to Session.
extends Node3D

const Session = preload("res://sim/ground_vehicle/session.gd")
const Driver = preload("res://input/ground_vehicle_input.gd")
const Registry = preload("res://input/controller_registry.gd")
const UiInput = preload("res://ui/ui_input.gd")
const Model = preload("res://vehicles/ground/mt8_model.gd")
const Dashboard = preload("res://vehicles/ground/ground_dashboard.gd")
const CameraRig = preload("res://vehicles/ground/ground_camera.gd")
const CourseView = preload("res://vehicles/ground/course_view.gd")
const TrackView = preload("res://vehicles/ground/airfield_track_view.gd")
const Course = preload("res://physics/ground_vehicle/course.gd")
const AirfieldCourse = preload("res://physics/ground_vehicle/airfield_course.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const GrassMask = preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const World = preload("res://render/world/world.gd")
const LakeWorld = preload("res://render/lake/lake_world.gd")
const Scenery = preload("res://scenery/scenery.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const TimeOfDayLighting = preload("res://render/time_of_day_lighting.gd")
const SkyConfig = preload("res://environment/sky_appearance_config.gd")
const Spec = preload("res://spec.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
const EngineAudio = preload("res://render/engine_audio.gd")
const GroundEffects = preload("res://vehicles/ground/ground_effects.gd")
const DamageView = preload("res://vehicles/ground/ground_damage_view.gd")
const ContactDebug = preload("res://vehicles/ground/contact_debug.gd")

signal home_requested
var startup_error := ""
var session: Node
var visual := {}
var dashboard: CanvasLayer
var camera: Camera3D
var camera_rig = CameraRig.new()
var driver = Driver.new()
var user_args := PackedStringArray()
var scripted_controls := Callable() # deterministic test seam, sampled only on physics ticks
var controller_registry: RefCounted
var joy_axis_reader: Callable = func(id: int, axis: JoyAxis) -> float: return Input.get_joy_axis(id, axis)
var joy_button_reader: Callable = func(id: int, button: JoyButton) -> bool: return Input.is_joy_button_pressed(id, button)
var enable_audio := true
var enable_vehicle_effects := true
var _effects: Node3D
var _damage_view: RefCounted
var _effects_time_s := 0.0
var enable_course_visual := true
## Production shares the aircraft field. Synthetic ramps remain an explicit research/test fixture.
var use_practice_fixture := false
var field_path: String = FieldLoader.DEFAULT_PATH
var field := {}
var lighting_config: Dictionary = LightingConfig.defaults()
var night_options := {}
var sky_config: Dictionary = SkyConfig.defaults()
var _lighting := {}
var _environment: Environment
var _presentation_context := {}
var mode := 0
var _course := {}
var _model := {}
var _focused := true
var _sound: AudioStreamPlayer3D
var checkpoint_path := "user://rcv/checkpoint.json"
var _checkpoint := {}
var _checkpoint_backup_path := ""
var _jump_time := -1.0
var _jump_origin := Vector2.ZERO
var _airtime := 0.0
var _best_jump := 0.0
var _landing_pending := false
var _landing_tick := 0
var _show_diagnostics := false
var _snapshot := PackedFloat64Array()
var _previous := PackedFloat64Array()
var _record_export_pending := false
var _last_export := {}
var _previous_auto_quit := true
var _contact_debug: MeshInstance3D
var _render_road: Callable
var _audio_was_paused := true
var _controller_device_id := -1
var _controller_generation := 0
var _controller_requires_selection := false
var _keyboard_neutral_gate := false
var _source_controller_registry: RefCounted
var _last_controls := {}
var _shortcut_buttons := {}

func _ready() -> void:
	name = "GroundVehicleActivity"
	_presentation_context = World.presentation_context()
	_initialize_driving_devices()
	_connect_controller_registry()
	_previous_auto_quit = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	session = Session.new()
	session.name = "GroundVehicleSession"
	add_child(session)
	var prepared: bool = session.prepare_default() if use_practice_fixture else _prepare_airfield()
	if not prepared:
		if startup_error.is_empty(): startup_error = session.load_error
		set_physics_process(false)
		set_process(false)
		return
	_model = session.model_snapshot()
	_course = session.course_snapshot()
	_render_road = func(north: float, east: float) -> Dictionary:
		return Course.sample(_course, north, east) if use_practice_fixture else AirfieldCourse.sample(_course, north, east)
	visual = Model.build()
	if not visual.ok:
		startup_error = visual.error
		set_physics_process(false)
		set_process(false)
		return
	add_child(visual.root)
	_damage_view = DamageView.new()
	if not _damage_view.prepare(visual):
		startup_error = "Bisonte damage bindings are unavailable"
		set_physics_process(false)
		set_process(false)
		return
	if enable_vehicle_effects:
		_effects = GroundEffects.new()
		if not _effects.prepare(visual, self):
			startup_error = "Bisonte effects bindings are unavailable"
			set_physics_process(false)
			set_process(false)
			return
	_contact_debug = ContactDebug.new()
	_contact_debug.visible = false
	add_child(_contact_debug)
	if not use_practice_fixture and enable_course_visual:
		Atmosphere.configure_appearance(sky_config)
		_environment = World.build(self, field, _build_airfield, {}, _lighting, night_options).environment
	else:
		ShaderClock.register()
		Atmosphere.state = {}
		var environment := WorldEnvironment.new()
		_environment = Atmosphere.environment(_lighting)
		environment.environment = _environment
		add_child(environment)
		var sun := Atmosphere.create_sun(self, _lighting)
		sun.directional_shadow_max_distance = 35.0
		if enable_course_visual: CourseView.build(self, _course)
	camera = Camera3D.new()
	camera.near = 0.01
	camera.far = Spec.CAMERA.far
	add_child(camera)
	camera.make_current()
	dashboard = Dashboard.new()
	dashboard.airfield = not use_practice_fixture
	dashboard.track_available = _course.has("track")
	add_child(dashboard)
	dashboard.action_requested.connect(handle_action)
	dashboard.controller_selected.connect(select_driving_device)
	dashboard.mode_selected.connect(_select_mode)
	dashboard.experiment_requested.connect(_experiment)
	dashboard.spawn_selected.connect(func(id: String):
		if _finish_recording() and session.reset(id): _after_reset())
	session.event_added.connect(_event)
	session.faulted.connect(func(reason: String):
		open_garage()
		dashboard.message("Simulation paused: " + reason, "Simulación en pausa: " + reason))
	session.tick_advanced.connect(_accepted_tick)
	session.recording_limit_reached.connect(_on_recording_limit)
	session.recording_interrupted.connect(_on_recording_interrupted)
	_snapshot = session.state_snapshot()
	_previous = _snapshot.duplicate()
	if enable_audio:
		_build_audio()
	open_garage()
	_capture_initial_controller_selection()
	_refresh_controller_ui()
	_process(0.0)


## Driving owns a local selection. Aircraft profiles and menu preferences survive
## a visit to the garage; a raw radio is never interpreted as an Xbox axis layout.
func _initialize_driving_devices() -> void:
	_source_controller_registry = controller_registry
	controller_registry = Registry.new()
	_refresh_driving_devices()
	if _source_controller_registry != null:
		_source_controller_registry.devices_changed.connect(_refresh_driving_devices)
	else:
		Input.joy_connection_changed.connect(_native_connection_changed)
	var preferred := -1
	if _source_controller_registry != null:
		preferred = _source_controller_registry.selected_device_id("flight")
	if not _is_flight_gamepad(_registry_device_for_id(preferred)):
		preferred = -1
		for record: Dictionary in controller_registry.get_devices():
			if _is_flight_gamepad(record):
				preferred = int(record.id)
				break
	controller_registry.select_device("flight", preferred)


func _native_connection_changed(id: int, connected: bool) -> void:
	if not connected:
		controller_registry.disconnect_device(id)
	_refresh_driving_devices.call_deferred()


func _refresh_driving_devices() -> void:
	var observations: Array = []
	if _source_controller_registry != null:
		for record: Dictionary in _source_controller_registry.get_devices():
			if record.get("connected", false): observations.append(record)
	else:
		for id: int in Input.get_connected_joypads():
			var record := Input.get_joy_info(id)
			record.merge({"id": id, "name": Input.get_joy_name(id), "guid": Input.get_joy_guid(id),
				"known": Input.is_joy_known(id), "kind": "gamepad" if Input.is_joy_known(id) else "joystick"}, true)
			observations.append(record)
	controller_registry.update_devices(observations)
	_refresh_controller_ui()


func select_driving_device(device: int) -> void:
	if device >= 0 and not _is_flight_gamepad(_registry_device_for_id(device)):
		return
	if controller_registry.select_device("flight", device):
		# Selecting the same item is also an explicit reconnect acknowledgement.
		apply_controller_selection(device)
	_refresh_controller_ui()


func _refresh_controller_ui() -> void:
	if dashboard == null or controller_registry == null:
		return
	var selected := _registry_selected_device_id("flight")
	dashboard.set_controllers(controller_registry.get_devices(), selected, _controller_requires_selection)
	UiInput.set_gamepad(selected if _has_flight_gamepad() else -1)

func _build_airfield() -> void:
	var exclusions: Array = []
	if _course.has("track"):
		var track: Dictionary = _course.track
		var access: Dictionary = track.access
		var half := float(access.width_m) * 0.5 + float(track.shoulder_m)
		var points := PackedVector2Array([
			Vector2(float(access.north_min_m) - float(track.shoulder_m), float(access.east_m) - half),
			Vector2(access.north_max_m, float(access.east_m) - half),
			Vector2(access.north_max_m, float(access.east_m) + half),
			Vector2(float(access.north_min_m) - float(track.shoulder_m), float(access.east_m) + half)])
		exclusions.append(GrassMask._record("rc-access", "dirt_track", points))
		camera_rig.track_center = Vector3(track.center_east_m, 0.0, -float(track.center_north_m))
	add_child(FieldBuilder.build(field, _lighting, exclusions))
	if _course.has("track"):
		add_child(TrackView.build(_course, _render_road))

func _prepare_airfield() -> bool:
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
	var lake := LakeWorld.resolve(field, Scenery.options())
	if not lake.ok:
		startup_error = "; ".join(lake.errors)
		return false
	camera_rig.pilot_position = Frames.ned_to_render([field.pilot.north, field.pilot.east, field.pilot.down - field.pilot.eye_height])
	return session.prepare_airfield(loaded, {}, lake.lake)

func _build_audio() -> void:
	_sound = EngineAudio.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = 0.15
	_sound.stream = stream
	_sound.volume_db = -19.0
	_sound.unit_size = 2.0
	_sound.max_distance = 35.0
	add_child(_sound)
	_sound.begin_voice()
	_sound.stream_paused = true

func _physics_process(_delta: float) -> void:
	if not startup_error.is_empty() or session == null or not session.prepared:
		return
	var controls := _read_controls()
	if scripted_controls.is_valid():
		controls = scripted_controls.call(session.tick)
	_last_controls = controls
	if not controls.get("armed", false) and not session.paused:
		open_garage()
		dashboard.message("Controls unavailable. Release them and check the selected device.", "Controles no disponibles. Suéltalos y revisa el dispositivo seleccionado.")
	if session.tick_once(controls):
		_update_landing_award()

func _update_landing_award() -> void:
	if not _landing_pending or session.tick < _landing_tick + 120:
		return
	_landing_pending = false
	var state: PackedFloat64Array = session.state_snapshot()
	var upright := Frames.quat_to_render(state.slice(6, 10)).y.dot(Vector3.UP) > 0.65
	var telemetry: Dictionary = session.telemetry_snapshot()
	var supported := false
	for contact in telemetry.get("wheel_in_contact", PackedByteArray()):
		supported = supported or contact != 0
	supported = supported and not telemetry.get("airborne", true)
	if upright and supported and session.run_valid:
		_best_jump = maxf(_best_jump, _airtime)
		dashboard.message("Landed! %.2f s in the air. Best %.2f s." % [_airtime, _best_jump], "¡Aterrizaje! %.2f s en el aire. Mejor %.2f s." % [_airtime, _best_jump])
	elif not upright:
		dashboard.message("Rollover. Try less approach speed; R recovers the truck.", "Volcamiento. Prueba con menos velocidad; R recupera el carro.")
	else:
		dashboard.message("Landing not scored: settle on the wheels in an unassisted run.", "Aterrizaje sin puntuar: apoya las ruedas en un recorrido sin asistencia.")

func _read_controls() -> Dictionary:
	var joy: Dictionary = _registry_joy_controls() if controller_registry != null else {"connected": false}
	var keys := {"accelerate": _key(KEY_W) or _key(KEY_UP), "reverse": _key(KEY_S) or _key(KEY_DOWN),
		"left": _key(KEY_A) or _key(KEY_LEFT), "right": _key(KEY_D) or _key(KEY_RIGHT),
		"brake": _key(KEY_SPACE), "blocked": not _focused, "focused": _focused}
	if controller_registry != null:
		keys.blocked = keys.blocked or _controller_requires_selection or _keyboard_neutral_gate
	var controls: Dictionary = driver.sample(keys, joy)
	if controller_registry != null and _keyboard_neutral_gate:
		_keyboard_neutral_gate = false
	return controls

func _registry_joy_controls() -> Dictionary:
	var device: int = _registry_selected_device_id("flight")
	if device < 0:
		if _controller_device_id >= 0 and not _controller_requires_selection:
			_begin_controller_loss("Controller selection cleared.", "Selección de control cancelada.")
		return {"connected": false}
	var record: Dictionary = _registry_device_for_id(device)
	if not _is_flight_gamepad(record):
		if not _controller_requires_selection or _controller_device_id != device:
			_controller_device_id = device
			_controller_generation = int(record.get("generation", 0))
			_begin_controller_loss("Select a connected, recognized gamepad for driving.", "Selecciona un mando reconocido y conectado para conducir.")
		return {"connected": false}
	var generation: int = int(record.get("generation", 0))
	if device != _controller_device_id:
		if not apply_controller_selection(device):
			return {"connected": false}
	elif generation != _controller_generation:
		if not _controller_requires_selection:
			_controller_generation = generation
			_begin_controller_loss("Controller connection changed. Select it again to continue.", "La conexión del mando cambió. Selecciónalo otra vez para continuar.")
		return {"connected": false}
	if _controller_requires_selection:
		return {"connected": false}
	return _joy_controls(device)

func _joy_controls(device: int) -> Dictionary:
	return {"connected": true, "device_id": device,
		"left_x": joy_axis_reader.call(device, JOY_AXIS_LEFT_X),
		"right_trigger": joy_axis_reader.call(device, JOY_AXIS_TRIGGER_RIGHT),
		"left_trigger": joy_axis_reader.call(device, JOY_AXIS_TRIGGER_LEFT),
		"reverse": joy_button_reader.call(device, JOY_BUTTON_B)}

func _connect_controller_registry() -> void:
	if controller_registry == null or not controller_registry.has_signal("selection_changed"):
		return
	var callback := Callable(self, "_on_controller_selection_changed")
	if not controller_registry.is_connected("selection_changed", callback):
		controller_registry.connect("selection_changed", callback)

func _capture_initial_controller_selection() -> void:
	if controller_registry == null:
		return
	var device: int = _registry_selected_device_id("flight")
	if device < 0:
		return
	var record: Dictionary = _registry_device_for_id(device)
	_controller_device_id = device
	_controller_generation = int(record.get("generation", 0))
	if not _is_flight_gamepad(record):
		_begin_controller_loss("Select a connected, recognized gamepad for driving.", "Selecciona un mando reconocido y conectado para conducir.")

func _registry_selected_device_id(role: String) -> int:
	if controller_registry == null or not controller_registry.has_method("selected_device_id"):
		return -1
	var result: Variant = controller_registry.call("selected_device_id", role)
	return int(result) if typeof(result) == TYPE_INT else -1

func _registry_device_for_id(device: int) -> Dictionary:
	if controller_registry == null or device < 0 or not controller_registry.has_method("device_for_id"):
		return {}
	var result: Variant = controller_registry.call("device_for_id", device)
	return result if typeof(result) == TYPE_DICTIONARY else {}

func _is_flight_gamepad(record: Dictionary) -> bool:
	return typeof(record.get("connected")) == TYPE_BOOL and record.connected \
		and typeof(record.get("known")) == TYPE_BOOL and record.known \
		and typeof(record.get("kind")) == TYPE_STRING and record.kind == "gamepad" and record.kind != "radio"

func _on_controller_selection_changed(role: String, device: int) -> void:
	if role != "flight":
		return
	if device >= 0:
		apply_controller_selection(device)
		return
	var prior: Dictionary = _registry_device_for_id(_controller_device_id)
	var lost_or_changed: bool = prior.is_empty() or prior.get("connected", false) != true \
		or int(prior.get("generation", 0)) != _controller_generation
	if lost_or_changed:
		_begin_controller_loss("Controller disconnected. Select a controller or keyboard to continue.", "Control desconectado. Selecciona un mando o el teclado para continuar.")
	else:
		apply_controller_selection(-1)

func apply_controller_selection(device: int) -> bool:
	if controller_registry == null or _registry_selected_device_id("flight") != device:
		return false
	_shortcut_buttons.clear()
	if device == -1:
		_controller_device_id = -1
		_controller_generation = 0
		_controller_requires_selection = false
		_keyboard_neutral_gate = true
		driver.reset()
		open_garage()
		_refresh_controller_ui()
		return true
	if device < 0:
		return false
	var record: Dictionary = _registry_device_for_id(device)
	_controller_device_id = device
	_controller_generation = int(record.get("generation", 0))
	if not _is_flight_gamepad(record):
		_begin_controller_loss("Select a connected, recognized gamepad for driving.", "Selecciona un mando reconocido y conectado para conducir.")
		return false
	_controller_requires_selection = false
	_keyboard_neutral_gate = false
	driver.reset()
	open_garage()
	_refresh_controller_ui()
	return true

func _begin_controller_loss(message_en: String, message_es: String) -> void:
	if not _controller_requires_selection:
		_shortcut_buttons.clear()
		_controller_requires_selection = true
		_keyboard_neutral_gate = false
		driver.reset()
		open_garage()
		if dashboard != null:
			dashboard.message(message_en, message_es)
		_refresh_controller_ui()

func _has_flight_gamepad() -> bool:
	if controller_registry == null or _controller_requires_selection:
		return false
	var device: int = _registry_selected_device_id("flight")
	if device < 0:
		return false
	var record: Dictionary = _registry_device_for_id(device)
	return _is_flight_gamepad(record) and device == _controller_device_id \
		and int(record.get("generation", 0)) == _controller_generation

func _accept_controller_button(device: int) -> bool:
	if controller_registry == null:
		return false
	for role: String in ["ui", "flight"]:
		if _registry_selected_device_id(role) != device:
			continue
		var record: Dictionary = _registry_device_for_id(device)
		if record.get("connected", false) != true:
			continue
		if role == "flight" and (not _is_flight_gamepad(record) or _controller_requires_selection or not _has_flight_gamepad()):
			continue
		return true
	return false

func _key(code: Key) -> bool:
	return Input.is_physical_key_pressed(code)

func _accepted_tick(_tick: int, _time: float, state: PackedFloat64Array, _telemetry: Dictionary) -> void:
	_previous = _snapshot
	_snapshot = state

func _process(delta: float) -> void:
	if dashboard == null or _snapshot.size() != 31:
		return
	# Interpolation changes only the drawn pose. No callback can feed float32 render state back.
	var drawn := _snapshot.duplicate()
	var alpha := Engine.get_physics_interpolation_fraction() if not session.paused else 1.0
	for i in [0, 1, 2, 13, 14, 15, 16, 25, 26, 27, 28, 29]:
		drawn[i] = lerpf(_previous[i], _snapshot[i], alpha)
	var qa := Quaternion(Frames.quat_to_render(_previous.slice(6, 10)))
	var qb := Quaternion(Frames.quat_to_render(_snapshot.slice(6, 10)))
	Model.draw(visual, drawn, _model.cg_height_above_chassis_datum_m)
	var basis := Basis(qa.slerp(qb, alpha))
	var target := Frames.ned_to_render([drawn[0], drawn[1], drawn[2]])
	visual.root.transform = Frames.root_transform(basis, target, Vector3(0, _model.cg_height_above_chassis_datum_m, 0))
	camera_rig.update(camera, target, basis, delta, dashboard.menu_visible, func(x: float, z: float) -> float: return _render_road.call(-z, x).height_m)
	World.update(_environment, 37.0 + session.time_s(), Vector3.ZERO, target, camera)
	var telemetry: Dictionary = session.telemetry_snapshot()
	telemetry.surface_id = _render_road.call(drawn[0], drawn[1]).surface_id
	_damage_view.update(session.damage_visual_state())
	if _effects != null:
		var simulated_delta := maxf(0.0, session.time_s() - _effects_time_s)
		_effects_time_s = session.time_s()
		var night_weight := 1.0 - smoothstep(0.05, 0.75, float(_lighting.get("sun_energy", 1.0)))
		_effects.update_render(simulated_delta, telemetry, _last_controls, _render_road, session.paused, night_weight)
		dashboard.update_lights(_effects.headlights_enabled)
	_contact_debug.update_snapshot(drawn, _model, telemetry, _render_road)
	dashboard.update_snapshot(telemetry, session.paused, session.time_s(), session.recording, _show_diagnostics or mode == 2)
	dashboard.update_input_status(_controls_ready(_last_controls), _controller_requires_selection, _focused)
	if visual.travel_outside_art:
		dashboard.message("Suspension beyond visual travel; see recorded physical state.", "Suspensión fuera del recorrido visual; consulta el estado físico grabado.")
	if _sound != null:
		_sound.global_position = target
		_sound.stream_paused = session.paused or not enable_audio
		if _sound.stream_paused:
			_audio_was_paused = true
		else:
			# Audible gearbox harmonic, an estimated presentation mapping, not a measured motor RPM.
			var rpm := 0.0
			for i in 4:
				rpm += absf(_snapshot[21 + i]) * 60.0 / TAU * 8.0 / 4.0
			if _audio_was_paused:
				_sound.restart_voice()
				_sound.voice.reset(rpm, 18000.0)
				_audio_was_paused = false
			_sound.refill(rpm, 18000.0)

func open_garage() -> void:
	if dashboard == null:
		return
	session.add_pause_hold("garage")
	driver.sample({"blocked": true}, {})
	_last_controls = {}
	dashboard.set_menu(true)
	camera_rig.reset()


func _controls_ready(controls: Dictionary) -> bool:
	return controls.get("armed", false) == true and controls.get("throttle", -1.0) == 0.0 \
		and controls.get("brake", -1.0) == 0.0 and controls.get("steering", -1.0) == 0.0 \
		and controls.get("reverse", true) == false

func handle_action(action: String) -> void:
	match action:
		"menu": open_garage()
		"resume":
			if not session.paused or not _focused:
				return
			if controller_registry != null and _controller_requires_selection:
				open_garage()
				dashboard.message("Select a connected gamepad or explicitly choose keyboard controls.", "Selecciona un mando conectado o elige explícitamente los controles de teclado.")
				return
			# Recheck at the click/Start boundary: the most recent physics sample
			# may precede a new trigger or key press. tick_once only observes the
			# readiness latch while paused; no physics step can be integrated here.
			var current: Dictionary = _read_controls()
			if not _controls_ready(current):
				dashboard.message("Release all controls before continuing.", "Suelta todos los controles antes de continuar.")
				return
			if not session.tick_once(current):
				return
			session.release_pause_hold("garage")
			if session.resume():
				dashboard.set_menu(false)
				camera_rig.reset()
				if mode == 1:
					dashboard.message("Follow the central lane. Start gently; release throttle before landing.", "Sigue el carril central. Empieza suave; suelta el acelerador antes de aterrizar.")
				else:
					dashboard.message("Ready to drive.", "Listo para conducir.")
			else:
				session.add_pause_hold("garage")
				dashboard.message("Release all controls before continuing.", "Suelta todos los controles antes de continuar.")
		"reset":
			if not _finish_recording(): return
			if session.reset(): _after_reset()
		"recover":
			if session.manual_recovery():
				_after_reset()
				dashboard.message("Recovered and repaired. This run is marked as assisted.", "Recuperado y reparado. Esta prueba queda marcada como asistida.")
		"camera":
			camera_rig.mode = (camera_rig.mode + 1) % (4 if _course.has("track") else 3)
			camera_rig.reset()
		"track_view":
			if _course.has("track"):
				camera_rig.mode = 0 if camera_rig.mode == 3 else 3
				camera_rig.reset()
		"body": visual.nodes.Body.visible = not visual.nodes.Body.visible
		"contacts":
			_show_diagnostics = not _show_diagnostics
			_contact_debug.visible = _show_diagnostics
		"sound": enable_audio = not enable_audio
		"lights":
			if _effects != null:
				_effects.headlights_enabled = not _effects.headlights_enabled
				dashboard.update_lights(_effects.headlights_enabled)
		"record":
			if session.recording:
				_finish_recording()
			elif not _record_export_pending:
				if session.start_recording():
					dashboard.record_button.text = dashboard.words("Stop and save recording", "Detener y guardar grabación")
				else:
					dashboard.message("Recording could not start. Reset the run and try again.", "No se pudo iniciar la grabación. Reinicia el recorrido e inténtalo de nuevo.")
			else:
				_finish_recording()
		"save":
			if _save_checkpoint():
				dashboard.message("State saved in " + checkpoint_path, "Estado guardado en " + checkpoint_path)
			elif not _checkpoint_backup_path.is_empty():
				dashboard.message("Save failed. Previous file kept at: " + _checkpoint_backup_path, "Falló el guardado. Archivo anterior conservado en: " + _checkpoint_backup_path)
			else:
				dashboard.message("Could not save state. Previous save kept.", "No se pudo guardar el estado. Se conservó el guardado anterior.")
		"restore":
			if not _finish_recording(): return
			var restored: bool = session.restore_checkpoint(_checkpoint) if not _checkpoint.is_empty() else _restore_checkpoint_file()
			if restored:
				_after_reset()
				dashboard.message("Saved state restored. Press Enter to continue.", "Estado restaurado. Pulsa Enter para continuar.")
			else:
				dashboard.message("State does not match this vehicle and course.", "El estado no corresponde a este vehículo y pista.")
		"home":
			if _finish_recording(): home_requested.emit()

func _restore_checkpoint_file() -> bool:
	var destination := ProjectSettings.globalize_path(checkpoint_path)
	var candidates: Array[String] = [destination]
	var backups: Array[String] = []
	if not DirAccess.dir_exists_absolute(destination.get_base_dir()): return false
	var prefix := destination.get_file() + ".tmp-"
	for name in DirAccess.get_files_at(destination.get_base_dir()):
		if name.begins_with(prefix) and name.ends_with(".previous"):
			backups.append(destination.get_base_dir().path_join(name))
	backups.sort_custom(func(a: String, b: String) -> bool:
		var a_time := FileAccess.get_modified_time(a)
		var b_time := FileAccess.get_modified_time(b)
		return a > b if a_time == b_time else a_time > b_time)
	candidates.append_array(backups)
	for path in candidates:
		if not FileAccess.file_exists(path): continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not parsed is Dictionary or not session.restore_checkpoint(parsed): continue
		_checkpoint = parsed
		if path != destination:
			_checkpoint_backup_path = path
			if not FileAccess.file_exists(destination) and _move_checkpoint_file(path, destination) == OK:
				_checkpoint_backup_path = ""
		return true
	return false

## Commit both disk and cache only after a complete, verified sibling-temp write.
## This handles reported I/O failure; it does not promise power-loss durability.
func _save_checkpoint() -> bool:
	var candidate: Dictionary = session.checkpoint()
	if candidate.is_empty():
		return false
	var destination := ProjectSettings.globalize_path(checkpoint_path)
	if DirAccess.make_dir_recursive_absolute(destination.get_base_dir()) != OK:
		return false
	var temporary := destination + ".tmp-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var contents := JSON.stringify(candidate, "\t", true, true)
	var error := _write_checkpoint_temp(temporary, contents)
	if error == OK:
		var verify := FileAccess.open(temporary, FileAccess.READ)
		if verify == null:
			error = ERR_FILE_CANT_READ
		else:
			var bytes := contents.to_utf8_buffer()
			if verify.get_length() != bytes.size() or verify.get_buffer(bytes.size()) != bytes or verify.get_error() != OK:
				error = ERR_FILE_CORRUPT
			verify.close()
	var backup := temporary + ".previous"
	# Godot 4.7.2 on Windows deletes an existing rename destination before moving.
	# Move the old save aside first, so even a failed commit cannot destroy it.
	if error == OK and FileAccess.file_exists(destination):
		error = _move_checkpoint_file(destination, backup)
	if error == OK:
		error = _move_checkpoint_file(temporary, destination)
	if error != OK:
		if FileAccess.file_exists(backup):
			if _move_checkpoint_file(backup, destination) != OK:
				_checkpoint_backup_path = backup
		if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
		return false
	if FileAccess.file_exists(backup): DirAccess.remove_absolute(backup)
	if not _checkpoint_backup_path.is_empty() and FileAccess.file_exists(_checkpoint_backup_path):
		DirAccess.remove_absolute(_checkpoint_backup_path)
	_checkpoint_backup_path = ""
	_checkpoint = candidate
	return true

func _move_checkpoint_file(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(from, to)

func _write_checkpoint_temp(path: String, contents: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(contents)
	file.flush()
	var error := file.get_error()
	file.close()
	return error

func _finish_recording() -> bool:
	if session.recording:
		session.stop_recording()
		_record_export_pending = true
	if not _record_export_pending:
		return true
	var name := "mt8-%d-%d" % [int(Time.get_unix_time_from_system()), Time.get_ticks_msec()]
	_last_export = session.export_recording(name)
	if not _last_export.ok:
		open_garage()
		dashboard.message("Recording kept in memory: " + _last_export.error, "Grabación conservada en memoria: " + _last_export.error)
		return false
	_record_export_pending = false
	dashboard.record_button.text = dashboard.words("Record telemetry", "Grabar telemetría")
	dashboard.message("Saved: " + _last_export.csv_path, "Guardado: " + _last_export.csv_path)
	return true

func _on_recording_limit(_sample_count: int, _elapsed_seconds: float) -> void:
	_record_export_pending = true
	open_garage()
	dashboard.record_button.text = dashboard.words("Save recording", "Guardar grabación")
	dashboard.message("Recording limit reached. Your data is kept; save it to start another run.", "Límite de grabación alcanzado. Los datos se conservan; guárdalos para iniciar otra prueba.")

func _on_recording_interrupted(reason: String, _sample_count: int) -> void:
	_record_export_pending = true
	open_garage()
	dashboard.record_button.text = dashboard.words("Save interrupted recording", "Guardar grabación interrumpida")
	dashboard.message("Recording interrupted; data kept: " + reason, "Grabación interrumpida; datos conservados: " + reason)

func _after_reset() -> void:
	_snapshot = session.state_snapshot()
	_previous = _snapshot.duplicate()
	_model = session.model_snapshot()
	_effects_time_s = session.time_s()
	if _effects != null: _effects.reset()
	if _damage_view != null:
		_damage_view.reset()
		_damage_view.update(session.damage_visual_state())
	_jump_time = -1.0
	_landing_pending = false
	dashboard.plot.clear_history()
	dashboard.select_spawn(session.spawn_id)
	if camera_rig.mode == 3: camera_rig.mode = 0
	camera_rig.reset()
	open_garage()

func _select_mode(index: int) -> void:
	mode = index
	dashboard.lab.visible = mode == 2
	if mode == 1:
		dashboard.message("Follow the central lane. Start gently; release throttle before landing.", "Sigue el carril central. Empieza suave; suelta el acelerador antes de aterrizar.")
	elif mode == 2:
		dashboard.message("Record the same route before and after changing one parameter.", "Graba la misma ruta antes y después de cambiar un parámetro.")

func _experiment(knobs: Dictionary) -> void:
	if not _finish_recording(): return
	if session.set_experiment(knobs):
		_after_reset()
		dashboard.message("Experiment applied. Mass, inertia and source identity updated.", "Experimento aplicado. Masa, inercia e identidad actualizadas.")
	else:
		dashboard.message(session.load_error, session.load_error)

func _event(event: Dictionary) -> void:
	if event.type == "damage":
		if event.stage == "disabled":
			dashboard.message("Drive damaged. Recover with R to repair.", "Propulsión averiada. Pulsa R para recuperar y reparar.")
		elif event.stage == "damaged":
			dashboard.message("Impact damage. Check the truck or recover with R.", "Daños por impacto. Revisa el carro o recupéralo con R.")
	elif event.type == "jump":
		# A bounce starts a new flight; the previous landing is no longer settled.
		_landing_pending = false
		_jump_time = event.time_s
		var state: PackedFloat64Array = session.state_snapshot()
		_jump_origin = Vector2(state[0], state[1])
	elif event.type == "landing" and _jump_time >= 0.0:
		_airtime = float(event.time_s) - _jump_time
		_jump_time = -1.0
		if _airtime > 0.08:
			_landing_pending = true
			_landing_tick = session.tick
	elif event.type == "braking_distance":
		dashboard.message("Braking distance %.2f m" % event.distance_m, "Distancia de frenado %.2f m" % event.distance_m)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if dashboard == null or _finish_recording(): get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_shortcut_buttons.clear()
		if dashboard != null: open_garage()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true

func _exit_tree() -> void:
	if not _presentation_context.is_empty():
		World.restore_presentation_context(_presentation_context)
	if controller_registry != null and controller_registry.has_signal("selection_changed"):
		var callback := Callable(self, "_on_controller_selection_changed")
		if controller_registry.is_connected("selection_changed", callback):
			controller_registry.disconnect("selection_changed", callback)
	if _source_controller_registry != null and _source_controller_registry.devices_changed.is_connected(_refresh_driving_devices):
		_source_controller_registry.devices_changed.disconnect(_refresh_driving_devices)
	if Input.joy_connection_changed.is_connected(_native_connection_changed):
		Input.joy_connection_changed.disconnect(_native_connection_changed)
	UiInput.isolate_joypads()
	get_tree().auto_accept_quit = _previous_auto_quit

func _unhandled_input(event: InputEvent) -> void:
	if dashboard == null: return
	if event is InputEventJoypadButton and not event.pressed:
		_shortcut_buttons.erase("%d:%d" % [event.device, event.button_index])
		return
	if not _focused: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE: handle_action("menu")
			KEY_ENTER: handle_action("resume")
			KEY_C: handle_action("camera")
			KEY_L: handle_action("lights")
			KEY_R: handle_action("recover")
			KEY_F9: handle_action("record")
			_: return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and _accept_controller_button(event.device):
		var action := ""
		if event.button_index == JOY_BUTTON_START:
			action = "resume" if dashboard.menu_visible else "menu"
		elif not dashboard.menu_visible:
			if event.button_index == JOY_BUTTON_X: action = "camera"
			elif event.button_index == JOY_BUTTON_Y: action = "recover"
		if action.is_empty(): return
		var edge := "%d:%d" % [event.device, event.button_index]
		if not _shortcut_buttons.has(edge):
			_shortcut_buttons[edge] = true
			handle_action(action)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera_rig.drag(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: camera_rig.zoom(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera_rig.zoom(1.1)
