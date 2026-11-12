## DR-16b/20/36a/37: the playable experimental FPV quad free-flight activity on the shared field. Physics belongs
## exclusively to the multirotor session (sim/multirotor/session.gd); this node samples the pilot once per 240 Hz
## tick, computes ONE interpolated pose per frame for the visual and the camera, and owns the OSD, the hold/menu
## policy, the motor sound and the opt-in flight log. Graphics settings never change physics.
extends Node3D

const Session = preload("res://sim/multirotor/session.gd")
const MultirotorLog = preload("res://sim/multirotor/flight_log.gd")
const FlightLogFormat = preload("res://sim/flight_log.gd")
const FC = preload("res://physics/multirotor/flight_controller.gd")
const PilotInput = preload("res://input/multirotor_input.gd")
const RcInput = preload("res://input/rc_input.gd")
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
const Track = preload("res://sim/race/track.gd")
const RaceDirector = preload("res://sim/race/race_director.gd")
const CourseVisual = preload("res://vehicles/multirotor/race_course_visual.gd")
const RaceRecords = preload("res://vehicles/multirotor/race_records.gd")
const LensStack = preload("res://render/lens/lens_stack.gd")
const LensSettings = preload("res://render/lens/lens_settings.gd")
const RcTrackOption = preload("res://scenery/rc_track_option.gd")
const GrassMask = preload("res://render/landscape_upgrade/scenery_grass_mask.gd")
const RB = preload("res://physics/rigid_body.gd")

const DT := 1.0 / 240.0
## CC0 quadcopter recording already shipped for the blimp's electric motors (assets/audio/powertrains/LICENSE.txt).
const MOTOR_AUDIO := "res://assets/audio/powertrains/electric_quad.wav"
## Simulation seconds the crash or depletion aftermath keeps running before the menu opens.
const AFTERMATH_S := 2.0
const RACE_TRACK := "res://data/race/tracks/openrc-practice-oval-1.json"
## DR-28/32 courses the pilot cycles with T on this field (each is offered only on the field it was authored for).
const RACE_TRACKS := [RACE_TRACK, "res://data/race/tracks/openrc-tower-sprint-1.json"]
const OSD_PREFS := "user://multirotor_osd.cfg"
const READY_TEXT := "Ready. Cycle the arm switch OFF then ON at low throttle."
const CHANGED_TEXT := "The controller changed: restart on the pad to fly with it."

signal home_requested

var startup_error := ""
var departure_managed := false
## AppRoot's controller registry: the device selected for the "flight" role flies the quad (none = keyboard). Without
## a registry (direct test routes) the first connected joypad is used.
var controller_registry: RefCounted
## AppRoot hook (or found on the parent AppRoot's ControllerService, see _adopt_app_controllers): device id -> the
## saved/active profile the controller service resolved for it ({} = not configured).
var controller_profile_for := Callable()
## AppRoot hook: ControllerService._confirmed_gamepad_connection(id, expected_id, expected_generation) — a selected,
## known, focused gamepad needs no fresh stick motion to become ready (as in the fixed-wing flight).
var controller_confirmation := Callable()
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
## DR-23/32/36b: the local practice course flown from this activity when it belongs to the loaded field ("" = none).
var race_track: String = RACE_TRACK
## Where finished and aborted race records are written (tests point this at an isolated folder).
var results_directory: String = Session.RESULTS_DIRECTORY

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
## LENS-01 (docs/plans/lens-screen-effects.md): rain on the FPV lens, impact blood and grime. Null when disabled.
var _lens: LensStack
## The installed obstacle inventory, read-only: names what an "Obstacle strike" hit, for the lens only.
var _obstacle_world: Dictionary = {}
var _audio: AudioStreamPlayer3D
var _audio_level := 0.0
var _hover_speed := 1.0
var _accumulation_owned := false
var _accumulation_before := true
var _race_option := ""
## DR-37: the pilot's race record book (race_records.gd), read once from results_directory.
var _records := {}
var _records_loaded := false
## RC-TRACK: the club field's RC car circuit when the pilot shows it (Settings > Graphics), else {}; one decision per
## activity feeds the drawn circuit, the quad's terrain and its obstacle inventory together.
var _rc_track := {}
var _race_action := 0
var _gate_views: Array = []
var _gate_next := -1
## DR-32 race course presentation (gates, numbers, start pad); null in free flight without a course.
var course_visual: RefCounted
## Telemetry of the last accepted tick (one plant evaluation per tick, not per rendered frame); emptied by the
## session's `resetting` signal so a pad restart, prepare or restore at the same tick is never served stale values.
var _telemetry := {}
var _telemetry_tick := -1
## After a resume the drawn pose stays on the accepted frame until the next tick (no blend back to a pre-pause tick).
var _hold_pose_until_tick := -1
## Identity (RcInput.key_for) of the active device lost to an unplug, re-selected if it returns.
var _lost_device_key := ""
## Whether the keyboard flies because the pilot selected it while a controller was connected (vs. no controller).
var _keyboard_by_choice := false


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
	# A menu-launched activity follows the saved preference; tests and command-line runs (--multirotor=, which the app
	# also starts departure-managed) stay without it unless OPENRC_RC_TRACK asks.
	_rc_track = RcTrackOption.resolve(field, departure_managed and not _command_line_launch())
	var obstacles: Dictionary = CollisionSetup.build(field, _rc_track)
	if not obstacles.ok or not session.set_collision_world(obstacles.world):
		startup_error = "FPV quad obstacle inventory refused: " + "; ".join(obstacles.get("errors", []))
		_disable()
		return
	_obstacle_world = obstacles.world
	# The flight is prepared for the source that will fly it (its throttle policy and limit are session options).
	_adopt_app_controllers()
	_connect_selected_controller()
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
	# DR-31b: the OSD layout and units persist only on the interactive route with the player's own settings file.
	var app := get_parent()
	if app != null and app.get("has_home") == true and str(app.get("preferences_path")) == "user://settings.cfg":
		hud.set_prefs_path(OSD_PREFS)
	var identity: Dictionary = session.data.identity
	hud.set_variant(str(identity.get("variant", "")))
	var battery: Variant = session.data.get("battery")
	hud.cells = int((battery as Dictionary).get("cells", 0)) if typeof(battery) == TYPE_DICTIONARY else 0
	hud.capacity_mah = 1000.0 * float((battery as Dictionary).get("capacity_ah", 0.0)) if typeof(battery) == TYPE_DICTIONARY else 0.0
	hud.set_fixture(visual.fixture)
	hud.action_requested.connect(handle_action)
	session.crashed.connect(_on_crashed)
	session.depleted.connect(_on_depleted)
	session.race_event.connect(_on_race_event)
	session.race_result.connect(_on_race_result)
	session.resetting.connect(_invalidate_telemetry)
	_build_gates()
	# Pay the solver fingerprint (about 70 ms of source hashing, once per process) while loading, not on F10.
	FlightLogFormat.replay_identity()
	session.faulted.connect(func(reason: String) -> void: _open_menu(tr("Simulation paused: %s") % reason))
	var none_selected: bool = _has_registry() and int(controller_registry.selected_device_id("flight")) < 0
	_keyboard_by_choice = none_selected and not Input.get_connected_joypads().is_empty()
	_flight_generation = input.source_generation
	Input.joy_connection_changed.connect(_joy_connection_changed)
	if _has_registry() and controller_registry.has_signal("selection_changed"):
		controller_registry.selection_changed.connect(_on_controller_selection_changed)
	if enable_audio:
		_build_audio()
	_start_lens()
	_open_menu(tr(READY_TEXT))
	_process(0.0)


func _disable() -> void:
	set_physics_process(false)
	set_process(false)
	set_process_unhandled_input(false)


## Losing focus holds the flight behind the menu; resuming is explicit.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and session != null and session.prepared and hud != null:
		_hold(tr("Paused: the window lost focus."))


func _exit_tree() -> void:
	_stop_recording("left the FPV quad activity")
	if Input.joy_connection_changed.is_connected(_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_joy_connection_changed)
	if _has_registry() and controller_registry.has_signal("selection_changed") \
			and controller_registry.selection_changed.is_connected(_on_controller_selection_changed):
		controller_registry.selection_changed.disconnect(_on_controller_selection_changed)
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
	_race_option = _course_option(race_track)
	return true


## The course path to prepare: `path` when it loads and belongs to the loaded field, else "" (plain free flight).
func _course_option(path: String) -> String:
	if path.is_empty():
		return ""
	var track: Dictionary = Track.load_file(path)
	return path if track.ok and str(track.track.field_id) == str(field.get("id", "")) else ""


## T: the next course for this field; the quad returns to the pad to fly it (a race attempt is aborted as by R).
func cycle_course() -> void:
	if session == null or not session.prepared:
		return
	var available: Array = []
	for path: String in RACE_TRACKS:
		if not _course_option(path).is_empty():
			available.append(path)
	if available.size() < 2:
		return
	var at: int = available.find(_race_option)
	race_track = available[(at + 1) % available.size()]
	_race_option = race_track
	if restart_on_pad():
		hud.flash(tr("Course: %s") % tr(str(session.course.get("track_name", ""))), 3.0)


func _build_field() -> void:
	var field_node: Node3D = FieldBuilder.build(field, _lighting, _pad_grass_exclusions(), _rc_track)
	var lake_error := str(field_node.get_meta("lake_error", ""))
	if not lake_error.is_empty():
		push_warning("FPV quad field lake refused: " + lake_error)
	add_child(field_node)


## True when the app was started straight into this activity from the command line (--multirotor=<id>).
static func _command_line_launch() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--multirotor"):
			return true
	return false


## Grass stays off the race pad (painted on the open field, away from the mown rotorcraft pad): every shipped course of
## this field shares one pad, so one record covers a course change.
func _pad_grass_exclusions() -> Array:
	var records: Array = []
	for path: String in RACE_TRACKS:
		var loaded: Dictionary = Track.load_file(path)
		if not loaded.ok or str(loaded.track.field_id) != str(field.get("id", "")):
			continue
		var pad: Dictionary = loaded.track.pad
		var n := float(pad.north_m)
		var e := float(pad.east_m)
		var half := 0.5 * CourseVisual.PAD_SIZE_M + 0.15
		var key := "race-pad-%.2f-%.2f" % [float(pad.north_m), float(pad.east_m)]
		if records.any(func(record: Dictionary) -> bool: return record.id == key):
			continue
		records.append(GrassMask._record(key, "race_pad", PackedVector2Array([Vector2(n - half, e - half),
			Vector2(n + half, e - half), Vector2(n + half, e + half), Vector2(n - half, e + half)])))
	return records


## The throttle policy follows the input source and is fixed for the flight it prepares; so is the pilot's throttle
## limit (a session option: changing it takes a fresh prepare on the pad, never a change mid-flight).
func _session_options() -> Dictionary:
	return {data_path = Catalog.DATA_PATH, throttle_policy = _input_policy(), start = "pad",
		source_generation = input.source_generation, throttle_limit = input.throttle_limit(), race_track = _race_option,
		rc_track = _rc_track}


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
	if _has_registry():
		# The controller service owns adoption and the "flight" selection; only a lost active device is dropped here.
		if not connected:
			if input.radio.connected and int(input.radio.device_id) == id:
				_lost_device_key = str(input.radio.device_key)
			input.on_connection_changed(id, false)
		else:
			_adopt_returning_device.call_deferred(id)
		_sync_selected_controller.call_deferred()
	else:
		input.on_connection_changed(id, connected)
		if not connected and not input.radio.connected:
			# Another joypad still plugged in takes over (none: the keyboard).
			input.connect_first_device()
		_bind_gamepad_confirmation()
	_announce_source_change(before)


## AppRoot suspends automatic controller selection during this activity, so the quad itself re-selects the device it
## lost when it comes back, or a first device when the keyboard was only the fallback (none connected at start); a
## keyboard the pilot chose stays chosen.
func _adopt_returning_device(id: int) -> void:
	if not is_inside_tree() or not _has_registry() or int(controller_registry.selected_device_id("flight")) >= 0:
		return
	var info: Dictionary = controller_registry.device_for_id(id)
	if not bool(info.get("connected", false)):
		return
	var returning := not _lost_device_key.is_empty() and RcInput.key_for(id, info) == _lost_device_key
	if returning or not _keyboard_by_choice:
		controller_registry.select_device("flight", id)


## A connected known gamepad is confirmed by its live connection (ControllerService through AppRoot, or the direct
## check below without a registry) instead of waiting for motion on all four axes and a centred dwell; a radio keeps
## its calibrated-profile and fresh-evidence rules.
func _bind_gamepad_confirmation() -> void:
	if not input.radio.connected:
		return
	var id := int(input.radio.device_id)
	if _has_registry():
		if controller_confirmation.is_valid() and controller_registry.has_method("connection_generation"):
			input.radio.confirmed_gamepad_connection = controller_confirmation.bind(id,
				int(controller_registry.connection_generation(id)))
	else:
		input.radio.confirmed_gamepad_connection = _confirmed_direct_gamepad


## The direct-route check (FlightSession._confirmed_direct_gamepad): the focused window, the same connected known pad.
func _confirmed_direct_gamepad(id: int) -> bool:
	if not is_inside_tree() or not get_window().has_focus() or not input.radio.connected:
		return false
	if id != int(input.radio.device_id) or not Input.get_connected_joypads().has(id) or not Input.is_joy_known(id):
		return false
	var info: Dictionary = Input.get_joy_info(id)
	info.merge({name = Input.get_joy_name(id), guid = Input.get_joy_guid(id), known = Input.is_joy_known(id)})
	return RcInput.key_for(id, info) == str(input.radio.device_key)


## The parent AppRoot's ControllerService supplies the profile resolver and the live gamepad confirmation when the
## launcher did not set them (AppRoot itself sets only the registry; app_root.gd stays out of this activity's
## wiring because the companion behavior manifest pins its bytes).
func _adopt_app_controllers() -> void:
	var parent := get_parent()
	var service: Variant = parent.get("controllers") if parent != null else null
	if not service is Object or not is_instance_valid(service):
		return
	if controller_registry == null and service.get("registry") is RefCounted:
		controller_registry = service.registry
	if not controller_profile_for.is_valid() and service.has_method("profile_for_device"):
		controller_profile_for = Callable(service, "profile_for_device")
	if not controller_confirmation.is_valid() and service.has_method("_confirmed_gamepad_connection"):
		controller_confirmation = Callable(service, "_confirmed_gamepad_connection")


func _has_registry() -> bool:
	return controller_registry != null and controller_registry.has_method("selected_device_id")


## The app's "flight" device with the profile the controller service resolved, or the keyboard; the first joypad
## without a registry.
func _connect_selected_controller() -> void:
	if not _has_registry():
		input.connect_first_device()
		_bind_gamepad_confirmation()
		return
	var id := int(controller_registry.selected_device_id("flight"))
	if id < 0:
		input.use_keyboard()
		return
	_lost_device_key = ""
	var info: Dictionary = controller_registry.device_for_id(id)
	if not bool(info.get("connected", false)):
		input.use_keyboard()
		return
	var profile: Dictionary = controller_profile_for.call(id) if controller_profile_for.is_valid() else {}
	input.connect_device(id, info, profile)
	_bind_gamepad_confirmation()


## Follow a changed "flight" selection (or a hot-plug the service resolved): a different device is a new source.
func _sync_selected_controller() -> void:
	if not is_inside_tree() or not _has_registry():
		return
	var id := int(controller_registry.selected_device_id("flight"))
	var current: int = int(input.radio.device_id) if input.radio.connected else -1
	if id == current:
		return
	var before: int = input.source_generation
	_connect_selected_controller()
	_announce_source_change(before)


func _on_controller_selection_changed(role: String, _id: int) -> void:
	if role == "flight":
		_sync_selected_controller.call_deferred()


func _announce_source_change(before: int) -> void:
	if input.source_generation == before or session == null or not session.prepared:
		return
	var stale_policy: bool = _input_policy() != str(session.options.throttle_policy)
	var stale_limit: bool = absf(input.throttle_limit() - _session_limit()) > 1.0e-9
	if _at_start() and (stale_policy or stale_limit):
		# Untouched on the pad: prepare the flight for the new source at once (as Restart on pad would).
		restart_on_pad()
	if input.radio.connected:
		_hold(tr("Controller connected: the motors are disarmed. Cycle the arm switch after resuming."))
	else:
		_hold(tr("Controller disconnected: the motors are disarmed. Cycle the arm switch after resuming."))


## Hold the flight behind the menu for an external reason, keeping a crash or depletion message the pilot still
## needs (the menu already offers only the restart there).
func _hold(reason: String) -> void:
	if hud != null and hud.menu_visible and _terminal_state() != "":
		if session.prepared and not session.paused:
			session.pause(reason)
		return
	_open_menu(reason)


func _input(event: InputEvent) -> void:
	input.on_event(event)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_P, KEY_ESCAPE:
				if hud.menu_visible: handle_action("resume")
				else: _open_menu(tr("Flight paused"))
			KEY_R:
				# DR-37: straight back to flying on the pad (the menu's Restart on pad keeps the menu open).
				quick_restart()
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
			KEY_T:
				cycle_course()
			KEY_G:
				request_race()
			KEY_F10:
				toggle_recording()
			KEY_F11:
				if flight_log != null and flight_log.recording:
					flight_log.mark()
					hud.flash(tr("Flight log marker"))
			_:
				return
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START \
			and input.radio.connected and input.radio.is_gamepad() and event.device == input.radio.device_id:
		# Only the active gamepad's Start: a radio in USB mode reports raw button numbers (a switch on button 6
		# must not pause the flight), and a second, unused controller has no say.
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
	# A race start or cancel the pilot asked for belongs to that moment, never to a later resume.
	_race_action = RaceDirector.ACTION_NONE
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


## A centred-stick throttle frozen above zero across a RECOVERY (the input source changed during the hold while the
## motors kept authority): resuming zeroes it first (FPV/02 §6). A plain hold (P, Esc, focus loss) of the same source
## resumes at the frozen throttle: the centred stick or released key holds it, so there is no jump, and zeroing it
## would drop a hovering quad. A changed source disarms in the controller, which zeroes the accumulator itself.
func _rate_reset_needed() -> bool:
	return str(session.options.throttle_policy) == "rate" and float(session.sim.aux[FC.AUX_VIRTUAL_THROTTLE]) > 0.0 \
		and input.source_generation != _flight_generation


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
					hud.flash(tr(Hud.NOT_READY_TEXT) if input.source() != "keyboard" \
						else tr("No controller: connect or check the controller."))
					return
			if _rate_reset_needed():
				input.request_throttle_reset()
			_flight_generation = input.source_generation
			if not session.resume():
				hud.flash(str(session.pause_reason))
				return
			_hold_pose_until_tick = int(session.sim.tick)
			hud.hide_menu()
		"restart":
			restart_on_pad()
		"throttle_limit":
			cycle_throttle_limit()
		"course":
			cycle_course()
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
	# The session's `resetting` signal closes a recording on success; a refused restart keeps flight and log.
	_race_action = RaceDirector.ACTION_NONE
	var ok: bool
	var reconfigure: bool = _input_policy() != str(session.options.throttle_policy) \
		or absf(input.throttle_limit() - _session_limit()) > 1.0e-9 or _race_option != str(session.options.get("race_track", ""))
	if reconfigure:
		# A fresh prepare publishes no race record: abort an attempt in progress through the pad reset first.
		ok = true
		if session.race != null and str(_race_phase()) in ["COUNTDOWN", "RACING"]:
			ok = session.reset_to_pad()
		if ok and not session.prepare(field, _session_options()):
			# The pad reset already happened: keep the scene in step with it, then say the new settings did not apply.
			var reason := str(session.load_error)
			_after_pad_reset()
			hud.flash(tr("Restart refused: %s") % reason)
			return false
	else:
		ok = session.reset_to_pad()
	if not ok:
		hud.flash(tr("Restart refused: %s") % str(session.load_error))
		return false
	_after_pad_reset()
	return true


## Scene state after the session returned to the pad: no recording, crash cause, OSD timer, aftermath, held pose or
## stale camera history; arm switch OFF and the menu ready to fly.
func _after_pad_reset() -> void:
	_stop_recording("restarted on the pad")
	_sync_course_visual()
	_hold_pose_until_tick = -1
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


func _on_crashed(reason: String) -> void:
	_crash_cause = reason
	_terminal_text = tr("Crashed: %s. Press R to reset.") % reason
	_aftermath_until = float(session.sim.time()) + AFTERMATH_S
	# The OSD hint already names the cause (no duplicate flash).
	_lens_crash(reason)


## LENS-01: the quad session reports a strike only as a reason. Presentation names what was hit by asking the installed
## obstacle inventory (read-only) what lies at the accepted crash position: a person draws blood, the ground grime.
func _start_lens() -> void:
	if _lens != null:
		remove_child(_lens)
		_lens.queue_free()
		_lens = null
	if camera == null or not enable_world:
		return
	var resolved: Dictionary = LensSettings.resolve({}, not scripted_pilot.is_valid())
	if not resolved.enabled:
		return
	_lens = LensStack.new()
	_lens.name = "LensStack"
	add_child(_lens)
	var pilot: Dictionary = field.pilot
	var ok := _lens.configure({
		"settings": resolved,
		"camera": camera,
		"session": session,
		"view_provider": func() -> String: return view.view_name(),
		"sky_provider": func() -> String: return str(sky_config.get("preset", "classic")),
		"field": field,
		# The quad is small: its centre is its hull for the pilot-strike sweep.
		"hull": PackedFloat64Array([0.0, 0.0, 0.0]),
		"station": PackedFloat64Array([float(pilot.north), float(pilot.east), float(pilot.down)]),
		"eye_height": float(pilot.eye_height),
		"mass_kg": float(session.data.get("mass_kg", 0.6)),
		"seed": int(sky_config.get("seed", 1)),
	})
	if not ok:
		_lens.queue_free()
		_lens = null
	else:
		_lens.person_struck.connect(func(player: bool) -> void:
			hud.flash(tr("The aircraft struck the pilot. Keep it in front of you and away from the flight line.") if player
				else tr("The aircraft struck a person. Never fly over or toward people."), 5.0))
		if not session.resetting.is_connected(_on_lens_resetting):
			session.resetting.connect(_on_lens_resetting)


func _on_lens_resetting() -> void:
	if _lens != null:
		_lens.reset()


## Settings changed during the flight: rebuild the lens from the new preference (presentation only).
func apply_lens_preferences() -> void:
	if session != null and session.prepared:
		_start_lens()


func _lens_crash(reason: String) -> void:
	if _lens == null:
		return
	var state: PackedFloat64Array = session.sim.state
	if state.size() < RB.SIZE:
		return
	var speed := Vector3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]).length()
	# Only an obstacle strike can have hit a person; a ground crash next to one is still a ground crash.
	_lens.strike_from_crash(state.slice(RB.POS, RB.POS + 3), speed,
		_obstacle_world if reason == "Obstacle strike" else {}, "quad:%d" % int(session.sim.tick))


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
	var action: int = _race_action
	_race_action = RaceDirector.ACTION_NONE
	if not session.tick_once(sample.pilot, action):
		if action == RaceDirector.ACTION_START:
			hud.flash(tr("Race start refused: return to the pad and stop"))
		elif not session.paused:
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
	var tick := int(session.sim.tick)
	var held: bool = session.paused or tick <= _hold_pose_until_tick
	var fraction := Engine.get_physics_interpolation_fraction() if not held else 1.0
	var drawn: PackedFloat64Array = session.interpolated(fraction)
	var t: Dictionary = _current_telemetry()
	var frame_dt := delta if not session.paused else 0.0
	visual.pose(drawn, t.get("rotor_speed_rad_s", PackedFloat64Array()), frame_dt)
	view.update(drawn, session.data.camera.mount_frd, delta, _ground_height_render)
	if _lens != null:
		_lens.advance(delta, float(session.sim.time()), session.paused)
	if _environment != null:
		World.update(_environment, 37.0 + float(session.sim.time()), Vector3.ZERO, visual.root.position, camera)
	var flight_s := float(_armed_ticks) * DT
	var raw: Variant = _last_input.get("raw", {})
	var arm_requested := bool((raw as Dictionary).get("arm", false)) if typeof(raw) == TYPE_DICTIONARY else false
	# Before the first accepted tick the controller still reports its start mode: show the pilot's selection.
	var pilot_mode: int = input.flight_mode() if not scripted_pilot.is_valid() and int(session.sim.tick) == 0 else -1
	hud.update(t, {camera = view.view_name(), tilt_deg = view.tilt_deg, hfov_deg = view.hfov_deg,
		vfov_deg = camera.fov if camera != null else 90.0, aspect = view.aspect(), attitude = drawn.slice(6, 10),
		body = drawn, sticks = raw, stick_policy = str(_last_input.get("throttle_policy", "")),
		accepted = session.sim.state, tick_dt = DT, gate = _osd_gate(_osd_gate_index(t)), gate_number = _osd_gate_index(t) + 1,
		flight_s = flight_s, arm_requested = arm_requested, crash_reason = _crash_cause, pilot_mode = pilot_mode,
		bindings = _osd_bindings(), throttle_limit = _session_limit(), race_on_pad = _on_race_pad()})
	_update_gates(t.get("race", {}), delta)
	_update_audio(t, delta)


## DR-31c: the next required gate of this frame's race telemetry (not the course visual, which follows a frame
## later), or -1 outside a counting-down or running race.
func _osd_gate_index(t: Dictionary) -> int:
	var race: Variant = t.get("race", {})
	if typeof(race) != TYPE_DICTIONARY or not str((race as Dictionary).get("phase", "")) in ["COUNTDOWN", "RACING"]:
		return -1
	return int((race as Dictionary).get("next_gate", -1))


## The render-space centre of gate `index` for the OSD gate guide, or null.
func _osd_gate(index: int) -> Variant:
	if course_visual == null or index < 0 or index >= course_visual.gate_frames.size():
		return null
	return (course_visual.gate_frames[index] as Dictionary).get("centre")


## The source's OSD bindings plus whether its latest sample is ready (a connected controller may not be yet).
func _osd_bindings() -> Dictionary:
	var bindings: Dictionary = input.bindings()
	bindings.ready = bool(_last_input.get("ready", true))
	return bindings


## Session telemetry of the accepted frame. It runs one plant evaluation (loads, contact, bus), so it is computed
## once per accepted tick and reused by every frame drawn before the next one (high refresh rates, holds, menus).
func _current_telemetry() -> Dictionary:
	var tick := int(session.sim.tick)
	if tick != _telemetry_tick or _telemetry.is_empty():
		_telemetry = session.telemetry()
		_telemetry_tick = tick
	return _telemetry


func _invalidate_telemetry() -> void:
	_telemetry = {}
	_hold_pose_until_tick = -1


func _race_phase() -> String:
	var race: Variant = _current_telemetry().get("race", {})
	return str((race as Dictionary).get("phase", "")) if typeof(race) == TYPE_DICTIONARY else ""


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
## AppRoot calls this after a controller profile is saved (and with the current "flight" device): the quad adopts
## the selected device, or the saved profile of the device it already flies, as a new source (motors disarmed, the
## flight held behind the menu). Nothing changes when the profile is the one in use.
func apply_controller_selection(device_id: int) -> bool:
	if session == null or not session.prepared or not _has_registry():
		return false
	var current: int = int(input.radio.device_id) if input.radio.connected else -1
	if device_id != current:
		_sync_selected_controller()
		return true
	if device_id < 0 or not controller_profile_for.is_valid():
		return true
	var profile: Dictionary = controller_profile_for.call(device_id)
	if profile.is_empty() or profile == input.radio.profile:
		return true
	var before: int = input.source_generation
	if not input.use_profile(profile, "calibrated"):
		return false # the quad keeps flying the profile in use; the Controls screen reports the refusal
	_announce_source_change(before)
	return true


func _refresh_controller_ui() -> void:
	pass


## DR-36b: G starts a race from the pad, or cancels a countdown or a race in progress. The action is sampled with the
## next accepted tick (one pulse); the session refuses a start while its result outbox is full.
func request_race() -> void:
	if session == null or not session.prepared or session.race == null:
		return
	var racing: bool = _race_phase() in ["COUNTDOWN", "RACING"]
	if not racing and (not _on_race_pad() or not session.crash.is_empty()):
		# DR-37 one-key retry: anywhere off the pad (after a finish, a crash or free flight) G first puts the quad back
		# on the pad, resumes and stages the start (the countdown then asks to arm).
		if quick_restart():
			_race_action = RaceDirector.ACTION_START
		return
	if session.paused:
		return
	_race_action = RaceDirector.ACTION_CANCEL if racing else RaceDirector.ACTION_START


## DR-37: R and G's retry: back on the pad and flying again at once (no menu). When the flight cannot resume (a
## controller not ready, a changed throttle policy) the menu stays open with the reason, as after Restart on pad.
func quick_restart() -> bool:
	if not restart_on_pad():
		return false
	handle_action("resume")
	return not session.paused


func _on_race_event(event: Dictionary) -> void:
	match str(event.get("type", "")):
		"race_go":
			pass # the OSD's large start count shows GO for the first second of the race
		"race_refused":
			hud.flash(race_refusal_text(str(event.get("reason", ""))), 5.0)
		"race_gate":
			if course_visual != null:
				course_visual.gate_passed(int(event.get("gate", -1)))
		"race_lap":
			hud.flash("%s %d  %s" % [tr("Lap"), int(event.get("lap", 0)), Hud.format_lap(float(event.get("duration_s", 0.0)))], 3.0)


## DR-37: what a refused start or GO needs from the pilot, by the race director's reason (translated).
func race_refusal_text(reason: String) -> String:
	match reason:
		"start_refused_not_on_pad":
			return tr("Start from the pad: press G to return to it.")
		"start_refused_moving":
			return tr("Hold still on the pad, then press G.")
		"start_refused_terminal":
			return tr("Crashed: press G or R to return to the pad.")
		"go_refused_not_armed":
			return tr("False start: arm before GO (%s).") % str(input.bindings().get("arm", "E"))
		"go_refused_throttle":
			return tr("Jump start: keep the throttle low until GO.")
		"go_refused_source":
			return tr("Controller not ready at GO: check the controller, then press G.")
	return tr("Race start refused: return to the pad and stop")


## A finished or aborted attempt: write the pending records at once (bounded, on request of this activity); a failed
## write keeps them in the session outbox and says so. DR-37: the attempt also enters the record book (best total,
## best lap, medal), and the results card shows it against the pilot's best. A pad reset during a race is no attempt
## for the book (the pilot chose to leave it).
func _on_race_result(result: Dictionary) -> void:
	var report: Dictionary = session.save_results(results_directory)
	if int(report.failed) > 0:
		hud.flash(tr("Race result not saved"))
	if str(result.get("reason", "")) == "pad_reset" or session.race == null:
		return
	_load_records()
	var summary: Dictionary = RaceRecords.apply(_records, session.course, result)
	_records = summary.records
	if RaceRecords.save_file(_records, records_path()) != OK:
		hud.flash(tr("Race record not saved"))
	var card: Dictionary = result.duplicate(true)
	card.merge(summary, true)
	card.erase("records")
	card.next_medal = RaceRecords.next_medal(str((summary.entry as Dictionary).get("medal", "")), RaceRecords.targets(session.course))
	hud.show_race_result(card)
	_push_race_info()


## A prepared course that differs from the drawn one (a course change through a fresh prepare) is drawn anew.
func _sync_course_visual() -> void:
	var drawn: String = str(course_visual.course_identity) if course_visual != null else ""
	var prepared: String = str(session.course.get("identity", "")) if session.race != null else ""
	if drawn == prepared:
		return
	if course_visual != null:
		course_visual.free_nodes()
		course_visual = null
	_gate_views = []
	_gate_next = -1
	_build_gates()


## The pause menu's Course button: the prepared course and whether the field offers another.
func _refresh_course_choice() -> void:
	if hud == null or session == null:
		return
	var offered := 0
	for path: String in RACE_TRACKS:
		if not _course_option(path).is_empty():
			offered += 1
	hud.set_course(str(session.course.get("track_name", "")) if session.race != null else "", offered > 1)
	_push_race_info()


## DR-37: the record book lives beside the per-attempt result files.
func records_path() -> String:
	return results_directory.path_join(RaceRecords.FILE_NAME)


## Read the record book once; an unreadable book is set aside (kept, never overwritten) and a new one starts.
func _load_records() -> void:
	if _records_loaded:
		return
	_records_loaded = true
	var loaded: Dictionary = RaceRecords.load_file(records_path())
	_records = loaded.records
	if not loaded.ok:
		RaceRecords.set_aside(records_path())
		hud.flash(tr("Race records unreadable: a new record book starts (the old file is kept)."), 6.0)


## The prepared course's best total, best lap, best medal and medal targets for the OSD and the pause menu.
func _push_race_info() -> void:
	if hud == null or session == null:
		return
	if session.race == null:
		hud.set_race_info({})
		return
	_load_records()
	var entry: Dictionary = _records.get(str(session.course.get("identity", "")), {})
	hud.set_race_info({best_total_s = float(entry.get("best_total_s", 0.0)), best_lap_s = float(entry.get("best_lap_s", 0.0)),
		medal = str(entry.get("medal", "")), targets = RaceRecords.targets(session.course)})


## Whether the quad sits on the course's start pad (the race rules' radius) - what G needs to start.
func _on_race_pad() -> bool:
	if session == null or session.race == null:
		return false
	var pad: Dictionary = session.course.get("pad", {})
	var rules: Dictionary = Track.ruleset()
	var dn: float = session.sim.state[RB.POS] - float(pad.get("north", 0.0))
	var de: float = session.sim.state[RB.POS + 1] - float(pad.get("east", 0.0))
	return sqrt(dn * dn + de * de) <= float(rules.pad_radius_m) and session.crash.is_empty()


## The course as drawn (race_course_visual.gd): panels at the same boxes the session collides with, LED states,
## numbers, feet and the start pad.
func _build_gates() -> void:
	if session.race == null:
		return
	_refresh_course_choice()
	course_visual = CourseVisual.new()
	# Light-only course elements (neon halos, guidance) brighten as the sun's energy falls.
	var night: float = 1.0 - clampf(float(_lighting.get("sun_energy", 1.0)), 0.0, 1.0)
	course_visual.build(self, session.course, night)
	_gate_views = course_visual.gate_views


## Highlight the next required gate (and the one after it) while a race is counting down or under way.
func _update_gates(race: Variant, delta := 0.0) -> void:
	if course_visual == null or typeof(race) != TYPE_DICTIONARY:
		return
	course_visual.set_exposure(_environment.tonemap_exposure if _environment != null else 1.0)
	course_visual.update(delta, race)
	var next: int = int(race.get("next_gate", 0)) if str(race.get("phase", "")) in ["COUNTDOWN", "RACING"] else -1
	if next == _gate_next:
		return
	_gate_next = next
	course_visual.set_next(next)
