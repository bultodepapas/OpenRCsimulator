## Playable ground-vehicle activity. Physics belongs exclusively to Session.
extends Node3D

const Session = preload("res://sim/ground_vehicle/session.gd")
const Driver = preload("res://input/ground_vehicle_input.gd")
const Model = preload("res://vehicles/ground/mt8_model.gd")
const Dashboard = preload("res://vehicles/ground/ground_dashboard.gd")
const CameraRig = preload("res://vehicles/ground/ground_camera.gd")
const CourseView = preload("res://vehicles/ground/course_view.gd")
const Course = preload("res://physics/ground_vehicle/course.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const ShaderClock = preload("res://render/shader_clock.gd")
const Frames = preload("res://render/frames.gd")
const EngineAudio = preload("res://render/engine_audio.gd")
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
var enable_course_visual := true
var mode := 0
var _course := {}
var _model := {}
var _focused := true
var _sound: AudioStreamPlayer3D
var _checkpoint := {}
var _jump_time := -1.0
var _jump_origin := Vector2.ZERO
var _airtime := 0.0
var _best_jump := 0.0
var _landing_pending := false
var _landing_tick := 0
var _show_diagnostics := false
var _last_device := -1
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

func _ready() -> void:
	name = "GroundVehicleActivity"
	_connect_controller_registry()
	_previous_auto_quit = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	session = Session.new()
	session.name = "GroundVehicleSession"
	add_child(session)
	if not session.prepare_default():
		startup_error = session.load_error
		set_physics_process(false)
		set_process(false)
		return
	_model = session.model_snapshot()
	_course = session.course_snapshot()
	_render_road = func(north: float, east: float) -> Dictionary: return Course.sample(_course, north, east)
	visual = Model.build()
	if not visual.ok:
		startup_error = visual.error
		set_physics_process(false)
		set_process(false)
		return
	add_child(visual.root)
	_contact_debug = ContactDebug.new()
	_contact_debug.visible = false
	add_child(_contact_debug)
	# Reuse the shared sky/light calibration; this analytic course has no airfield scenery.
	ShaderClock.register()
	Atmosphere.state = {}
	var environment := WorldEnvironment.new()
	environment.environment = Atmosphere.environment()
	add_child(environment)
	var sun := Atmosphere.create_sun(self)
	sun.directional_shadow_max_distance = 35.0
	if enable_course_visual:
		CourseView.build(self, _course)
	camera = Camera3D.new()
	camera.near = 0.01
	camera.far = 1500.0
	add_child(camera)
	camera.make_current()
	dashboard = Dashboard.new()
	add_child(dashboard)
	dashboard.action_requested.connect(handle_action)
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
	_process(0.0)

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
	session.tick_once(controls)
	if _landing_pending and session.tick >= _landing_tick + 120:
		_landing_pending = false
		var state: PackedFloat64Array = session.state_snapshot()
		var upright := Frames.quat_to_render(state.slice(6, 10)).y.dot(Vector3.UP) > 0.65
		if upright and session.run_valid:
			_best_jump = maxf(_best_jump, _airtime)
			dashboard.message("Landed! %.2f s in the air. Best %.2f s." % [_airtime, _best_jump], "¡Aterrizaje! %.2f s en el aire. Mejor %.2f s." % [_airtime, _best_jump])
		else:
			dashboard.message("Rollover. Try less approach speed; R recovers the truck.", "Volcamiento. Prueba con menos velocidad; R recupera el carro.")

func _read_controls() -> Dictionary:
	var joy: Dictionary = _registry_joy_controls() if controller_registry != null else _legacy_joy_controls()
	var keys := {"accelerate": _key(KEY_W) or _key(KEY_UP), "reverse": _key(KEY_S) or _key(KEY_DOWN),
		"left": _key(KEY_A) or _key(KEY_LEFT), "right": _key(KEY_D) or _key(KEY_RIGHT),
		"brake": _key(KEY_SPACE), "blocked": not _focused, "focused": _focused}
	if controller_registry != null:
		keys.blocked = keys.blocked or _controller_requires_selection or _keyboard_neutral_gate
	var controls: Dictionary = driver.sample(keys, joy)
	if controller_registry != null and _keyboard_neutral_gate:
		_keyboard_neutral_gate = false
	return controls

func _legacy_joy_controls() -> Dictionary:
	var devices := Input.get_connected_joypads()
	var device := -1 if devices.is_empty() else int(devices[0])
	if _last_device >= 0 and device != _last_device:
		open_garage()
		if dashboard != null:
			dashboard.message("Controller disconnected. Release controls to continue.", "Control desconectado. Suelta los controles para continuar.")
	_last_device = device
	return _joy_controls(device) if device >= 0 else {"connected": false}

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
		"right_trigger": maxf(0.0, joy_axis_reader.call(device, JOY_AXIS_TRIGGER_RIGHT)),
		"left_trigger": maxf(0.0, joy_axis_reader.call(device, JOY_AXIS_TRIGGER_LEFT)),
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
	if device == -1:
		_controller_device_id = -1
		_controller_generation = 0
		_controller_requires_selection = false
		_keyboard_neutral_gate = true
		driver.reset()
		open_garage()
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
	return true

func _begin_controller_loss(message_en: String, message_es: String) -> void:
	if not _controller_requires_selection:
		_controller_requires_selection = true
		_keyboard_neutral_gate = false
		driver.reset()
		open_garage()
		if dashboard != null:
			dashboard.message(message_en, message_es)

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
		return true
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
	camera_rig.update(camera, target, basis, delta, dashboard.menu_visible, func(x: float, z: float) -> float: return Course.sample(_course, -z, x).height_m)
	var telemetry: Dictionary = session.telemetry_snapshot()
	telemetry.surface_id = Course.sample(_course, drawn[0], drawn[1]).surface_id
	_contact_debug.update_snapshot(drawn, _model, telemetry, _render_road)
	dashboard.update_snapshot(telemetry, session.paused, session.time_s(), session.recording, _show_diagnostics or mode == 2)
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
	dashboard.set_menu(true)
	camera_rig.reset()

func handle_action(action: String) -> void:
	match action:
		"menu": open_garage()
		"resume":
			if controller_registry != null and _controller_requires_selection:
				open_garage()
				dashboard.message("Select a connected gamepad or explicitly choose keyboard controls.", "Selecciona un mando conectado o elige explícitamente los controles de teclado.")
				return
			session.release_pause_hold("garage")
			if session.resume():
				dashboard.set_menu(false)
				camera_rig.reset()
				if mode == 1:
					dashboard.message("Follow the central lane. Start gently; release throttle before landing.", "Sigue el carril central. Empieza suave; suelta el acelerador antes de aterrizar.")
				elif controller_registry != null and not _has_flight_gamepad():
					dashboard.message("W forward · S reverse · A/D steer · Space brake", "W avanzar · S reversa · A/D girar · Espacio frenar")
				elif controller_registry == null and Input.get_connected_joypads().is_empty():
					dashboard.message("W forward · S reverse · A/D steer · Space brake", "W avanzar · S reversa · A/D girar · Espacio frenar")
				else:
					dashboard.message("RT drive · LT brake · Left stick steer · Hold B + RT reverse", "RT acelerar · LT frenar · Stick izquierdo girar · B + RT reversa")
			else:
				session.add_pause_hold("garage")
				dashboard.message("Release all controls before continuing.", "Suelta todos los controles antes de continuar.")
		"reset":
			if not _finish_recording(): return
			if session.reset(): _after_reset()
		"recover":
			if session.manual_recovery():
				_after_reset()
				dashboard.message("Recovered. This run is marked as assisted.", "Recuperado. Esta prueba queda marcada como asistida.")
		"camera":
			camera_rig.mode = (camera_rig.mode + 1) % 3
			camera_rig.reset()
		"body": visual.nodes.Body.visible = not visual.nodes.Body.visible
		"contacts":
			_show_diagnostics = not _show_diagnostics
			_contact_debug.visible = _show_diagnostics
		"sound": enable_audio = not enable_audio
		"record":
			if session.recording:
				_finish_recording()
			elif not _record_export_pending:
				session.start_recording()
				dashboard.record_button.text = dashboard.words("Stop and save recording", "Detener y guardar grabación")
			else:
				_finish_recording()
		"save":
			_checkpoint = session.checkpoint()
			var directory := ProjectSettings.globalize_path("user://rcv")
			DirAccess.make_dir_recursive_absolute(directory)
			var file := FileAccess.open(directory.path_join("checkpoint.json"), FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify(_checkpoint, "\t", true, true))
				file.close()
				dashboard.message("State saved in user://rcv/checkpoint.json", "Estado guardado en user://rcv/checkpoint.json")
			else:
				dashboard.message("Could not save state to disk.", "No se pudo guardar el estado en disco.")
		"restore":
			if not _finish_recording(): return
			if _checkpoint.is_empty() and FileAccess.file_exists("user://rcv/checkpoint.json"):
				var parsed = JSON.parse_string(FileAccess.get_file_as_string("user://rcv/checkpoint.json"))
				if parsed is Dictionary: _checkpoint = parsed
			if session.restore_checkpoint(_checkpoint):
				_after_reset()
				dashboard.message("Saved state restored. Press Enter to continue.", "Estado restaurado. Pulsa Enter para continuar.")
			else:
				dashboard.message("State does not match this vehicle and course.", "El estado no corresponde a este vehículo y pista.")
		"home":
			if _finish_recording(): home_requested.emit()

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
	_jump_time = -1.0
	_landing_pending = false
	dashboard.plot.clear_history()
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
	if event.type == "jump":
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
		if dashboard != null: open_garage()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true

func _exit_tree() -> void:
	if controller_registry != null and controller_registry.has_signal("selection_changed"):
		var callback := Callable(self, "_on_controller_selection_changed")
		if controller_registry.is_connected("selection_changed", callback):
			controller_registry.disconnect("selection_changed", callback)
	get_tree().auto_accept_quit = _previous_auto_quit

func _unhandled_input(event: InputEvent) -> void:
	if dashboard == null: return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE: handle_action("menu")
			KEY_ENTER: handle_action("resume")
			KEY_C: handle_action("camera")
			KEY_R: handle_action("recover")
			KEY_F9: handle_action("record")
			_: return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START \
			and _accept_controller_button(event.device):
		handle_action("resume" if dashboard.menu_visible else "menu")
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		camera_rig.drag(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: camera_rig.zoom(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: camera_rig.zoom(1.1)
