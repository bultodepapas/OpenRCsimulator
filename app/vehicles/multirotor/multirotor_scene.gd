## DR-16b/20/36a/37: the playable experimental FPV quad free-flight activity on the shared field. Physics belongs
## exclusively to the multirotor session (sim/multirotor/session.gd); this node samples the pilot once per 240 Hz
## tick, computes ONE interpolated pose per frame for the visual and the camera, and owns the OSD, the hold/menu
## policy, the motor sound and the opt-in flight log. Graphics settings never change physics.
extends Node3D

const Session = preload("res://sim/multirotor/session.gd")
const MultirotorLog = preload("res://sim/multirotor/flight_log.gd")
const FC = preload("res://physics/multirotor/flight_controller.gd")
const PilotInput = preload("res://input/multirotor_input.gd")
const Visual = preload("res://vehicles/multirotor/multirotor_visual.gd")
const ViewController = preload("res://vehicles/multirotor/multirotor_camera.gd")
const Hud = preload("res://vehicles/multirotor/multirotor_hud.gd")
const Catalog = preload("res://vehicles/multirotor/multirotor_catalog.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const World = preload("res://render/world/world.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const TimeOfDayLighting = preload("res://render/time_of_day_lighting.gd")
const SkyAppearance = preload("res://environment/sky_appearance_config.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Frames = preload("res://render/frames.gd")
const Spec = preload("res://spec.gd")
const CollisionSetup = preload("res://scenery/collision_setup.gd")

const DT := 1.0 / 240.0
## CC0 quadcopter recording already shipped for the blimp's electric motors (assets/audio/powertrains/LICENSE.txt).
const MOTOR_AUDIO := "res://assets/audio/powertrains/electric_quad.wav"
## Simulation seconds the crash or depletion aftermath keeps running before the menu opens.
const AFTERMATH_S := 2.0
const READY_TEXT := "Ready. Cycle the arm switch OFF then ON at low throttle."
const CHANGED_TEXT := "The controller changed: restart on the pad to fly with it."

signal home_requested

var startup_error := ""
var departure_managed := false
var controller_registry: RefCounted
var vehicle_id: String = Catalog.ID
var field_path: String = FieldLoader.DEFAULT_PATH
var lighting_config: Dictionary = LightingConfig.defaults()
var night_options := {}
var sky_config: Dictionary = SkyAppearance.defaults()
var enable_audio := true
var enable_world := true
## Test seam: the frame model the visual loads (a missing path exercises the lab fixture).
var frame_model: String = Visual.MODEL_PATH
## Deterministic test seam: tick -> 9-value pilot frame (FC layout), replacing the input adapter on physics ticks.
var scripted_pilot := Callable()

var session: Node
## Opt-in black box (F10 start/stop, F11 marker).
var flight_log: RefCounted
var visual: RefCounted
var view: RefCounted = ViewController.new()
var hud: CanvasLayer
var camera: Camera3D
var input = PilotInput.new()
var field := {}
var _lighting := {}
var _environment: Environment
var _last_input := {}
var _flight_generation := 0
## Simulation time of the first accepted armed tick since the last reset; -1 before arming.
var _arm_time := -1.0
## Accepted armed ticks since the last reset: the OSD timer is armed flight time, like an FPV OSD's armed timer
## (it stops while disarmed after a landing).
var _armed_ticks := 0
var _aftermath_until := -1.0
var _terminal_text := ""
var _crash_cause := ""
var _audio: AudioStreamPlayer3D
var _audio_level := 0.0
var _hover_speed := 1.0
var _accumulation_owned := false
var _accumulation_before := true


func _enter_tree() -> void:
	# INPUT-10: a direct launch must not depend on the fixed-wing route having disabled accumulation.
	if not _accumulation_owned:
		_accumulation_before = Input.use_accumulated_input
		_accumulation_owned = true
	Input.use_accumulated_input = false


func _ready() -> void:
	name = "MultirotorActivity"
	if not Catalog.contains(vehicle_id):
		startup_error = "Unknown multirotor: " + vehicle_id
		_disable()
		return
	if not _load_field():
		_disable()
		return
	session = Session.new()
	session.name = "MultirotorSession"
	add_child(session)
	var obstacles: Dictionary = CollisionSetup.build(field)
	if not obstacles.ok or not session.set_collision_world(obstacles.world):
		startup_error = "FPV quad obstacle inventory refused: " + "; ".join(obstacles.get("errors", []))
		_disable()
		return
	_flight_generation = input.source_generation
	if not session.prepare(field, _session_options()):
		startup_error = "FPV quad could not be prepared: " + str(session.load_error)
		_disable()
		return
	visual = Visual.new()
	if not visual.build(session.data, frame_model):
		startup_error = str(visual.error) if not str(visual.error).is_empty() else "FPV quad visual could not be built"
		_disable()
		return
	add_child(visual.root)
	var derived: Variant = session.data.get("derived", {})
	_hover_speed = float(derived.get("hover_speed_rad_s", 0.0)) if typeof(derived) == TYPE_DICTIONARY else 0.0
	if not is_finite(_hover_speed) or _hover_speed <= 0.0:
		_hover_speed = sqrt(float(session.data.mass_kg) * 9.80665 / (4.0 * float(session.data.rotor_law.thrust_coefficient_n_s2)))
	if enable_world:
		Atmosphere.configure_appearance(sky_config)
		_environment = World.build(self, field, _build_field, {}, _lighting, night_options).environment
	var camera_data: Dictionary = session.data.camera
	view.tilt_deg = float(camera_data.tilt_deg)
	view.hfov_deg = float(camera_data.hfov_deg)
	var pilot: Dictionary = field.pilot
	view.pilot_eye = Frames.ned_to_render([pilot.north, pilot.east, pilot.down - pilot.eye_height])
	camera = view.build(self, Spec.CAMERA.far)
	get_viewport().size_changed.connect(_on_viewport_resized)
	hud = Hud.new()
	add_child(hud)
	var identity: Dictionary = session.data.identity
	hud.set_variant(str(identity.get("variant", "")))
	var battery: Variant = session.data.get("battery")
	hud.cells = int((battery as Dictionary).get("cells", 0)) if typeof(battery) == TYPE_DICTIONARY else 0
	hud.set_fixture(visual.fixture)
	hud.action_requested.connect(handle_action)
	session.crashed.connect(_on_crashed)
	session.depleted.connect(_on_depleted)
	session.faulted.connect(func(reason: String) -> void: _open_menu(tr("Simulation paused: %s") % reason))
	input.connect_first_device()
	_flight_generation = input.source_generation
	Input.joy_connection_changed.connect(_joy_connection_changed)
	if enable_audio:
		_build_audio()
	_open_menu(tr(READY_TEXT))
	_process(0.0)


func _disable() -> void:
	set_physics_process(false)
	set_process(false)
	set_process_unhandled_input(false)


## Losing focus holds the flight behind the menu; resuming is explicit.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and session != null and session.prepared and hud != null:
		_open_menu(tr("Paused: the window lost focus."))


func _exit_tree() -> void:
	_stop_recording("left the FPV quad activity")
	if Input.joy_connection_changed.is_connected(_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_joy_connection_changed)
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.disconnect(_on_viewport_resized)
	if _accumulation_owned:
		Input.use_accumulated_input = _accumulation_before
		_accumulation_owned = false


func _load_field() -> bool:
	var loaded := FieldLoader.load_from(field_path)
	if not loaded.ok:
		startup_error = "; ".join(loaded.errors)
		return false
	var checked_light := LightingConfig.validate(lighting_config)
	var checked_sky := SkyAppearance.validate(sky_config)
	if not checked_light.ok or not checked_sky.ok:
		startup_error = "; ".join(checked_light.errors) + "; ".join(checked_sky.errors)
		return false
	lighting_config = checked_light.config
	sky_config = checked_sky.config
	_lighting = TimeOfDayLighting.snapshot(lighting_config) if lighting_config.mode != "legacy" else {}
	field = loaded.field
	return true


func _build_field() -> void:
	var field_node: Node3D = FieldBuilder.build(field, _lighting, [])
	var lake_error := str(field_node.get_meta("lake_error", ""))
	if not lake_error.is_empty():
		push_warning("FPV quad field lake refused: " + lake_error)
	add_child(field_node)


## The throttle policy follows the input source and is fixed for the flight it prepares; so is the pilot's throttle
## limit (a session option: changing it takes a fresh prepare on the pad, never a change mid-flight).
func _session_options() -> Dictionary:
	return {data_path = Catalog.DATA_PATH, throttle_policy = _input_policy(), start = "pad",
		source_generation = input.source_generation, throttle_limit = input.throttle_limit()}


## The prepared flight's throttle limit.
func _session_limit() -> float:
	return float(session.options.get("throttle_limit", 1.0))


## Whether the flight still sits untouched at its start (nothing accepted since the last prepare or pad reset).
func _at_start() -> bool:
	return int(session.sim.tick) == 0 and session.crash.is_empty()


func _input_policy() -> String:
	return str(session.options.throttle_policy) if scripted_pilot.is_valid() and session != null and session.prepared \
		else input.throttle_policy()


func _joy_connection_changed(id: int, connected: bool) -> void:
	var before: int = input.source_generation
	input.on_connection_changed(id, connected)
	if input.source_generation == before:
		return
	if connected:
		_open_menu(tr("Controller connected: the motors are disarmed. Cycle the arm switch after resuming."))
	else:
		_open_menu(tr("Controller disconnected: the motors are disarmed. Cycle the arm switch after resuming."))


func _input(event: InputEvent) -> void:
	input.on_event(event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_P, KEY_ESCAPE:
				if hud.menu_visible: handle_action("resume")
				else: _open_menu(tr("Flight paused"))
			KEY_R:
				handle_action("restart")
			KEY_C:
				view.cycle_view()
				_flash_view()
			KEY_H:
				hud.toggle_help()
			KEY_BRACKETLEFT:
				if view.adjust_tilt(-1): _flash_view()
			KEY_BRACKETRIGHT:
				if view.adjust_tilt(1): _flash_view()
			KEY_MINUS:
				if view.adjust_fov(-1): _flash_view()
			KEY_EQUAL:
				if view.adjust_fov(1): _flash_view()
			KEY_F10:
				toggle_recording()
			KEY_F11:
				if flight_log != null and flight_log.recording:
					flight_log.mark()
					hud.flash(tr("Flight log marker"))
			_:
				return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START:
		if hud.menu_visible: handle_action("resume")
		else: _open_menu(tr("Flight paused"))


func _flash_view() -> void:
	if view.view_name() != "fpv":
		# Tilt and FOV belong to the FPV mount; the inspection views have their own lenses.
		hud.flash(tr("Camera %s") % tr(str(Hud.CAMERA_NAMES[view.view_name()])), 2.0)
		return
	hud.flash(tr("Camera %s  tilt %d°  FOV %d°") % [tr(str(Hud.CAMERA_NAMES[view.view_name()])), int(round(view.tilt_deg)),
		int(round(view.hfov_deg))], 2.0)


func _open_menu(reason: String) -> void:
	if session.prepared and not session.paused:
		session.pause(reason)
	hud.set_throttle_limit(_session_limit(), input.throttle_limit())
	hud.show_menu(reason, _can_resume(), _rate_reset_needed(), _terminal_state())


## "" for a flyable quad; "crash", or after pack depletion "depleted_air" (it can only fall: resuming is a
## secondary choice to watch it) or "depleted_ground".
func _terminal_state() -> String:
	if not session.crash.is_empty():
		return "crash"
	var f: Dictionary = session.frame()
	if f.modes[FC.MODE_MOTOR] != FC.MOTOR_DEPLETED:
		return ""
	var body: PackedFloat64Array = f.body
	var under: PackedFloat64Array = session.environment.ground(body[0], body[1])
	var agl := -body[2] - (under[0] if under.size() == 3 and is_finite(under[0]) else 0.0)
	return "depleted_air" if agl > 0.3 else "depleted_ground"


func _can_resume() -> bool:
	return session.crash.is_empty() and str(session.fault_reason).is_empty() \
		and _input_policy() == str(session.options.throttle_policy)


## A centred-stick throttle frozen above zero: resuming zeroes it first (FPV/02 §6 recovery).
func _rate_reset_needed() -> bool:
	return str(session.options.throttle_policy) == "rate" and float(session.sim.aux[FC.AUX_VIRTUAL_THROTTLE]) > 0.0


func handle_action(action: String) -> void:
	match action:
		"resume":
			if not session.crash.is_empty():
				hud.flash(tr("Restart on the pad to fly again."))
				return
			if _input_policy() != str(session.options.throttle_policy):
				hud.flash(tr(CHANGED_TEXT))
				return
			if not scripted_pilot.is_valid():
				var sample: Dictionary = input.sample(DT, false)
				if not sample.ready:
					hud.flash(tr("No controller: connect or check the controller."))
					return
			if _rate_reset_needed():
				input.request_throttle_reset()
			_flight_generation = input.source_generation
			if not session.resume():
				hud.flash(str(session.pause_reason))
				return
			hud.hide_menu()
		"restart":
			restart_on_pad()
		"throttle_limit":
			cycle_throttle_limit()
		"help":
			hud.toggle_help()
		"home":
			_stop_recording("left the FPV quad activity")
			session.pause("Leaving")
			home_requested.emit()
			if not departure_managed:
				get_tree().quit()


## Next throttle limit for the current source. Untouched on the pad it applies at once through a fresh prepare (the
## same as Restart on pad); after any flight it waits for Restart on pad, so a flight never changes mid-way.
func cycle_throttle_limit() -> void:
	var next: float = input.cycle_throttle_limit()
	if _at_start() and session.paused:
		restart_on_pad()
		return
	hud.set_throttle_limit(_session_limit(), next)


## A disarmed quad back on the pad: same configuration (a new one if the source changed the throttle policy or the
## pilot chose another throttle limit), no stale camera history, OSD timer or crash cause. Refusal keeps the flight.
func restart_on_pad() -> bool:
	_stop_recording("restarted on the pad")
	var ok: bool
	if _input_policy() != str(session.options.throttle_policy) or absf(input.throttle_limit() - _session_limit()) > 1.0e-9:
		ok = session.prepare(field, _session_options())
	else:
		ok = session.reset_to_pad()
	if not ok:
		hud.flash(tr("Restart refused: %s") % str(session.load_error))
		return false
	input.reset_for_restart()
	_flight_generation = input.source_generation
	_arm_time = -1.0
	_armed_ticks = 0
	_aftermath_until = -1.0
	_terminal_text = ""
	_crash_cause = ""
	view.snap()
	_open_menu(tr(READY_TEXT))
	_process(0.0)
	return true


func _on_crashed(reason: String) -> void:
	_crash_cause = reason
	_terminal_text = tr("Crashed: %s. Press R to reset.") % reason
	_aftermath_until = float(session.sim.time()) + AFTERMATH_S
	# The OSD hint already names the cause (no duplicate flash).


func _on_depleted() -> void:
	_terminal_text = tr("The battery is depleted. Restart on the pad to fly again.")
	if _aftermath_until < 0.0:
		_aftermath_until = float(session.sim.time()) + AFTERMATH_S


func _physics_process(_delta: float) -> void:
	if session == null or not session.prepared:
		return
	var integrate: bool = not session.paused
	var sample: Dictionary
	if scripted_pilot.is_valid():
		var frame: PackedFloat64Array = scripted_pilot.call(int(session.sim.tick))
		sample = {pilot = frame, source = "script", ready = frame[FC.IN_SOURCE_READY] == 1.0, error = "",
			throttle_policy = str(session.options.throttle_policy), raw = {arm = frame[FC.IN_ARM] == 1.0},
			source_generation = _flight_generation}
	else:
		sample = input.sample(DT, integrate)
	_last_input = sample
	if session.paused:
		return
	if str(sample.throttle_policy) != str(session.options.throttle_policy):
		_open_menu(tr(CHANGED_TEXT))
		return
	if int(sample.source_generation) != _flight_generation:
		_open_menu(tr("Controller disconnected: the motors are disarmed. Cycle the arm switch after resuming."))
		return
	if not session.tick_once(sample.pilot):
		if not session.paused:
			_open_menu(tr("The input frame was refused."))
		return
	if session.sim.modes[FC.MODE_MOTOR] == FC.MOTOR_ARMED:
		if _arm_time < 0.0:
			_arm_time = float(session.sim.time())
		_armed_ticks += 1
	if _aftermath_until >= 0.0 and float(session.sim.time()) >= _aftermath_until:
		_aftermath_until = -1.0
		_open_menu(_terminal_text)


func _process(delta: float) -> void:
	if session == null or not session.prepared or visual == null:
		return
	var fraction := Engine.get_physics_interpolation_fraction() if not session.paused else 1.0
	var drawn: PackedFloat64Array = session.interpolated(fraction)
	var t: Dictionary = session.telemetry()
	var frame_dt := delta if not session.paused else 0.0
	visual.pose(drawn, t.get("rotor_speed_rad_s", PackedFloat64Array()), frame_dt)
	view.update(drawn, session.data.camera.mount_frd, delta, _ground_height_render)
	if _environment != null:
		World.update(_environment, 37.0 + float(session.sim.time()), Vector3.ZERO, visual.root.position, camera)
	var flight_s := float(_armed_ticks) * DT
	var raw: Variant = _last_input.get("raw", {})
	var arm_requested := bool((raw as Dictionary).get("arm", false)) if typeof(raw) == TYPE_DICTIONARY else false
	# Before the first accepted tick the controller still reports its start mode: show the pilot's selection.
	var pilot_mode: int = input.flight_mode() if not scripted_pilot.is_valid() and int(session.sim.tick) == 0 else -1
	hud.update(t, {camera = view.view_name(), tilt_deg = view.tilt_deg, hfov_deg = view.hfov_deg,
		vfov_deg = camera.fov if camera != null else 90.0, aspect = view.aspect(), attitude = drawn.slice(6, 10),
		flight_s = flight_s, arm_requested = arm_requested, crash_reason = _crash_cause, pilot_mode = pilot_mode,
		bindings = input.bindings(), throttle_limit = _session_limit()})
	_update_audio(t, delta)


func _ground_height_render(x: float, z: float) -> float:
	var h: PackedFloat64Array = session.environment.ground(-z, x)
	return h[0] if h.size() == 3 and is_finite(h[0]) else 0.0


func _on_viewport_resized() -> void:
	if session != null and session.prepared:
		_process(0.0)


func _build_audio() -> void:
	var stream := load(MOTOR_AUDIO) as AudioStreamWAV
	if stream == null:
		return
	var looped := stream.duplicate() as AudioStreamWAV
	looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looped.loop_begin = 0
	looped.loop_end = int(stream.get_length() * float(stream.mix_rate))
	_audio = AudioStreamPlayer3D.new()
	_audio.name = "Motors"
	_audio.stream = looped
	_audio.unit_size = 2.0
	_audio.max_distance = 150.0
	_audio.volume_db = -80.0
	add_child(_audio)
	_audio.play()
	_audio.stream_paused = true


## One loop for the four motors: pitch follows the mean ACHIEVED shaft speed relative to hover; the level fades to
## silence as the rotors stop. Held flights are silent.
func _update_audio(t: Dictionary, delta: float) -> void:
	if _audio == null:
		return
	var speeds: PackedFloat64Array = t.get("rotor_speed_rad_s", PackedFloat64Array())
	var mean := 0.0
	for speed: float in speeds:
		mean += absf(speed) / maxf(float(speeds.size()), 1.0)
	var n := mean / _hover_speed
	var target := 0.0 if session.paused else clampf(n, 0.0, 1.0)
	_audio_level = move_toward(_audio_level, target, maxf(delta, 0.0) * 4.0) if delta > 0.0 else target
	_audio.global_position = visual.root.position
	var silent: bool = session.paused or _audio_level < 0.02
	_audio.stream_paused = silent
	if silent:
		return
	_audio.pitch_scale = clampf(n, 0.35, 2.5)
	_audio.volume_db = linear_to_db(clampf(_audio_level, 0.001, 1.0)) - 4.0


## Start or stop the opt-in flight log of the current flight; a reset or reconfiguration closes it.
func toggle_recording() -> void:
	if session == null or not session.prepared:
		return
	if flight_log != null and flight_log.recording:
		flight_log.stop("pilot stopped recording")
		hud.flash(str(flight_log.note))
		return
	flight_log = MultirotorLog.new(session)
	flight_log.start({field_path = field_path})
	hud.flash(str(flight_log.note))


func _stop_recording(reason: String) -> void:
	if flight_log != null and flight_log.recording:
		flight_log.stop(reason)


## AppRoot controller hooks shared with the ground activity slot.
func apply_controller_selection(_device_id: int) -> bool:
	return true


func _refresh_controller_ui() -> void:
	pass
