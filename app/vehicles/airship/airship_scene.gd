## BL-10/BL-12: playable RC blimp activity on the shared airfield. Physics belongs exclusively to the airship
## session (sim/airship/session.gd); this node samples the pilot input once per 240 Hz tick, draws the interpolated
## accepted state, and owns camera, HUD, sound and the pause menu. Graphics settings never change physics.
extends Node3D

const Session = preload("res://sim/airship/session.gd")
const PilotInput = preload("res://input/airship_input.gd")
const RcInput = preload("res://input/rc_input.gd")
const ControllerActions = preload("res://input/controller_actions.gd")
const Visual = preload("res://vehicles/airship/airship_visual.gd")
const Hud = preload("res://vehicles/airship/airship_hud.gd")
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const World = preload("res://render/world/world.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const TimeOfDayLighting = preload("res://render/time_of_day_lighting.gd")
const SkyAppearance = preload("res://environment/sky_appearance_config.gd")
const Atmosphere = preload("res://render/atmosphere.gd")
const Frames = preload("res://render/frames.gd")
const CameraRig = preload("res://render/camera/camera_rig.gd")
const CameraSettings = preload("res://render/camera/camera_settings.gd")
const CameraCollision = preload("res://render/camera/camera_collision.gd")
const PilotCamera = preload("res://render/pilot_camera.gd")
const CollisionSetup = preload("res://scenery/collision_setup.gd")
const LakeWorld = preload("res://render/lake/lake_world.gd")
const Scenery = preload("res://scenery/scenery.gd")
const AirshipLog = preload("res://sim/airship/flight_log.gd")
const Catalog = preload("res://vehicles/airship/airship_catalog.gd")
const MechanicalAudio = preload("res://audio/mechanical_audio.gd")
const MechanicalProfile = preload("res://audio/mechanical_profile.gd")
const LensStack = preload("res://render/lens/lens_stack.gd")
const LensSettings = preload("res://render/lens/lens_settings.gd")
const CreatorVisual = preload("res://workshop/creator/visual_builder.gd")
const CREATOR_LABEL := "RC blimp physics · %s appearance only — experimental"
const CREATOR_UNAVAILABLE := "This model could not be shown on the blimp."
## Servo sound channels: [id, continuous indices averaged] (vector and fin angles in radians, CTRL sign).
const SERVO_CHANNELS := [["vector_side", [4, 5]], ["vector_stern", [6]], ["fin_dorsal", [7]], ["fin_port", [8]], ["fin_starboard", [9]]]
const SERVO_ANCHORS := [["vector_port", "vector_starboard"], ["vector_stern"], ["fin_dorsal"], ["fin_port"], ["fin_starboard"]]

const DATA_PATH := "res://data/airships/rc-blimp-5m.json"
const MOTOR_AUDIO := "res://assets/audio/powertrains/electric_quad.wav"
const MOTOR_AUDIO_REFERENCE_HZ := 232.1
const FULL_SPEED_RPM := 7800.0
const BLADES := 3.0
const VIEW_KEYS := {KEY_1: "pilot", KEY_2: "chase", KEY_3: "fpv", KEY_4: "flyby", KEY_5: "orbit"}

signal home_requested
signal skin_changed(id: String)

var startup_error := ""
var skin_id := "tiburon-blanco"
var departure_managed := false
var controller_registry: RefCounted
var controller_profile_for := Callable()
var controller_confirmation := Callable()
var field_path: String = FieldLoader.DEFAULT_PATH
var lighting_config: Dictionary = LightingConfig.defaults()
var night_options := {}
var sky_config: Dictionary = SkyAppearance.defaults()
## LENS-01 (docs/plans/lens-screen-effects.md): rain on the lens, impact grime, and blood when the blimp strikes a
## person. Null when disabled.
var _lens: LensStack
var _obstacle_world: Dictionary = {}
var enable_audio := true
var enable_world := true
var startup_checkpoint := Callable()
## Deterministic test seam: tick -> [roll, pitch, yaw, throttle]; sampled only on physics ticks.
var scripted_sticks := Callable()
## BL-19d: a frozen Workshop build (workshop/trial.gd). Empty = the shipped blimp.
var workshop_trial := {}
## AC-CV: {source: admitted ClearView InspectedSource, name}. The stock blimp physics fly; the imported model
## replaces only the drawn envelope, fitted to the stock envelope's length and centre. Empty keeps the route.
var creator_visual := {}
var _trial_raw := {}
## Virtual size of the flown build (Workshop scale); camera, audio and weigh-off presets follow it.
var _size := 1.0

var session: Node
## BL-08 opt-in black box (F10 start/stop, F11 marker).
var flight_log: RefCounted
var visual: RefCounted
var hud: CanvasLayer
var camera: Camera3D
var camera_preferences := {}
var _rig: CameraRig
var input = PilotInput.new()
var field := {}
## CR-AUD-01: the field's enabled lake, resolved once like the field builder resolves it and passed to every session
## preparation so the physics terrain matches the rendered basin ({} = no lake or a refused one).
var _lake := {}
var presentation := {}
var ballast_index := 2
var wind_index := 0
var start_index := 0
var _lighting := {}
var _environment: Environment
var _last_input := {}
var _audio_side: AudioStreamPlayer3D
var _audio_stern: AudioStreamPlayer3D
## BL-19f: the shared servo/retract synthesizer, driven by accepted vector and fin angles (Workshop audio profile).
var _mechanical: Node3D
var _servo_anchors: Array = []
var _servo_anchor_visual := 0
var _controller_generation := 0
var _pause_bindings := {}
var _pause_held := {}
var _pause_off_seen := {}


func _ready() -> void:
	if not startup_checkpoint.is_valid():
		prepare_activity()


## Home owns the staged coroutine and the lifetime of a cancelled partial activity.
func prepare_activity() -> void:
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
	_obstacle_world = obstacles.world
	if not session.prepare(field, _session_options()):
		startup_error = "Blimp could not be prepared: " + str(session.load_error)
		_disable()
		return
	if startup_checkpoint.is_valid() and not await startup_checkpoint.call("Preparing aircraft"):
		return
	visual = Visual.new()
	var skins := Visual.skins(presentation)
	if skins.is_empty() or not visual.build(presentation, skin_id):
		startup_error = str(visual.error) if not str(visual.error).is_empty() else "No blimp skins are available"
		_disable()
		return
	add_child(visual.root)
	# SA-08: a Projected shadow selection also gives the blimp its planar shadow.
	preload("res://render/vehicle_shadow_cue.gd").attach(self, visual.root, _lighting, _ground_height_render)
	# The model child carries the Workshop size; the root keeps the accepted pose only.
	visual.model.scale = Vector3.ONE * _size
	if not creator_visual.is_empty() and not _apply_creator_visual():
		_disable()
		return
	if not workshop_trial.is_empty() and visual.has_method("apply_presentation"):
		var painted: Dictionary = visual.call("apply_presentation", workshop_trial.get("presentation_profile", {}))
		if not painted.get("ok", false):
			startup_error = "Blimp presentation refused: " + "; ".join(painted.get("errors", PackedStringArray()))
			_disable()
			return
	_configure_lights()
	if enable_world:
		Atmosphere.configure_appearance(sky_config)
		if startup_checkpoint.is_valid():
			var world := await World.build_staged(self, field, _build_field_staged, {}, _lighting, night_options, startup_checkpoint)
			if world.get("cancelled", false):
				return
			_environment = world.environment
		else:
			_environment = World.build(self, field, _build_field, {}, _lighting, night_options).environment
	camera = PilotCamera.create(self, field.pilot)
	_rig = CameraRig.new(camera, float(session.data.envelope.length))
	_rig.light_direction = Atmosphere.shadow_direction(_lighting)
	_bind_fpv_mount()
	if camera_preferences.is_empty():
		_rig.set_view("chase")
	else:
		CameraSettings.apply_at_start(_rig, camera_preferences)
	hud = Hud.new()
	add_child(hud)
	var names: Array = []
	var selected := 0
	for i in skins.size():
		names.append(str(skins[i].name))
		if skins[i].id == skin_id:
			selected = i
	hud.set_camera_views(_rig.available_views())
	hud.set_skins(names, selected)
	hud.select_choice("ballast", ballast_index)
	hud.select_choice("wind", wind_index)
	hud.select_choice("start", start_index)
	if workshop_trial.is_empty() and creator_visual.is_empty() and field.id != "default":
		(hud.choices.start as OptionButton).set_item_disabled(1, true)
	hud.select_choice("camera", _rig.available_views().find(_rig.view))
	if not workshop_trial.is_empty():
		var length := float(session.data.envelope.length)
		hud.set_workshop_trial("Workshop trial · RC blimp %.1f m — experimental" % length, length)
	elif not creator_visual.is_empty():
		hud.set_workshop_trial(tr(CREATOR_LABEL) % str(creator_visual.get("name", "")), float(session.data.envelope.length))
	hud.action_requested.connect(handle_action)
	hud.option_selected.connect(_option_selected)
	session.crashed.connect(_on_crash)
	session.crashed.connect(_lens_crash)
	session.resetting.connect(func() -> void:
		if _lens != null:
			_lens.reset())
	_start_lens()
	session.faulted.connect(func(reason: String) -> void: _open_menu("Simulation paused: " + reason))
	_connect_selected_controller()
	Input.joy_connection_changed.connect(_joy_connection_changed)
	if _has_registry() and controller_registry.has_signal("selection_changed"):
		controller_registry.selection_changed.connect(_on_controller_selection_changed)
	_refresh_pause_bindings()
	if enable_audio:
		_build_audio()
	_open_menu(session.pause_reason)
	_note_weigh_off()
	_process(0.0)


## All three catalog skins carry the same fixed shell name and forward (-Z) datum.
## Resolve its actual foremost fitting once per accepted skin/scale, outside the draw loop.
func _bind_fpv_mount() -> void:
	if creator_visual.is_empty() and session.crash.is_empty():
		var shell := visual.model.find_child("airship_mesh", true, false) as MeshInstance3D
		if shell != null and shell.mesh != null:
			var bounds: AABB = CreatorVisual.relative(visual.root, shell) * shell.get_aabb()
			if bounds.has_volume():
				var lens := Vector3(0.0, 0.0, bounds.position.z - 0.025 * _size)
				if _rig.set_fpv_mount(Transform3D(Basis.IDENTITY, lens), 90.0, 0.025 * _size):
					return
	_rig.clear_fpv_mount()


func _refresh_fpv_mount() -> void:
	_bind_fpv_mount()
	hud.set_camera_views(_rig.available_views())
	hud.select_choice("camera", _rig.available_views().find(_rig.view))


func _on_crash(reason: String) -> void:
	if _rig.view == "fpv":
		_rig.set_view("orbit")
	_refresh_fpv_mount()
	_open_menu(reason + ". Restart to fly again.")


## AC-CV: hides the stock envelope and shows the imported ClearView model in its place, scaled so its length
## (render Z) equals the stock model's and centred on it. Presentation only; physics stay the stock blimp's.
func _apply_creator_visual() -> bool:
	var source: Variant = creator_visual.get("source")
	var built: Dictionary = {}
	if source is CreatorVisual.InspectedSource:
		built = CreatorVisual.build_flight(source, {nose_axis = "-x", up_axis = "+y", unit_scale = 1.0, datum = [0.0, 0.0, 0.0]})
	if built.is_empty():
		startup_error = CREATOR_UNAVAILABLE
		return false
	var imported: Node3D = built.root
	var stock_box := _mesh_bounds(visual.root, visual.model)
	var imported_box := _mesh_bounds(imported, imported)
	if not stock_box.has_volume() or not imported_box.has_volume() or imported_box.size.z <= 0.0:
		imported.free()
		startup_error = CREATOR_UNAVAILABLE
		return false
	var fit := stock_box.size.z / imported_box.size.z
	visual.model.visible = false
	imported.name = "CreatorModel"
	imported.transform = Transform3D(Basis.from_scale(Vector3.ONE * fit), stock_box.get_center() - imported_box.get_center() * fit)
	visual.root.add_child(imported)
	return true


## Bounds of every mesh under `node`, in `ancestor` space.
static func _mesh_bounds(ancestor: Node, node: Node) -> AABB:
	var box := AABB()
	var found := false
	for child: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		var placed: AABB = CreatorVisual.relative(ancestor, mesh) * mesh.get_aabb()
		box = placed if not found else box.merge(placed)
		found = true
	return box


## LENS-01: the blimp session reports a crash as a reason; the lens asks the installed obstacle inventory (read-only)
## what lies within the envelope's reach of the accepted crash state.
func _start_lens() -> void:
	if _lens != null:
		remove_child(_lens)
		_lens.queue_free()
		_lens = null
	if camera == null or not enable_world:
		return
	var resolved: Dictionary = LensSettings.resolve({}, true)
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
		"view_provider": func() -> String: return _rig.view,
		"sky_provider": func() -> String: return str(sky_config.get("preset", "classic")),
		"field": field,
		"hull": PackedFloat64Array([0.0, 0.0, 0.0]),
		"station": PackedFloat64Array([float(pilot.north), float(pilot.east), float(pilot.down)]),
		"eye_height": float(pilot.get("eye_height", 1.7)),
		"mass_kg": float(session.model.get("mass", 5.0)),
		"seed": hash(skin_id),
	})
	if not ok:
		_lens.queue_free()
		_lens = null
		return
	_lens.person_struck.connect(func(player: bool) -> void:
		_lens.show_message(tr("The aircraft struck the pilot. Keep it in front of you and away from the flight line.") if player
			else tr("The aircraft struck a person. Never fly over or toward people.")))


## Settings changed during the flight: rebuild the lens from the new preference (presentation only).
func apply_lens_preferences() -> void:
	if session != null and session.prepared:
		_start_lens()


func _lens_crash(reason: String) -> void:
	if _lens == null:
		return
	var state: Variant = session.crash.get("state", PackedFloat64Array())
	if not state is PackedFloat64Array or (state as PackedFloat64Array).size() < 6:
		return
	var s: PackedFloat64Array = state
	var speed := Vector3(s[3], s[4], s[5]).length()
	var reach := float(session.model.get("bound_radius", 1.4)) + 0.6
	_lens.strike_from_crash(s.slice(0, 3), speed, _obstacle_world if reason.begins_with("Obstacle strike") else {},
		"blimp:%d" % int(session.crash.get("tick", 0)), reach)


func _disable() -> void:
	set_physics_process(false)
	set_process(false)
	set_process_unhandled_input(false)


## Losing focus pauses the flight behind the menu; resuming is explicit and re-arms the controls.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and session != null and session.prepared and hud != null:
		_pause_held.clear()
		_pause_off_seen.clear()
		input.reset_throttle()
		_open_menu(Session.FOCUS_PAUSE)


func _exit_tree() -> void:
	if _rig != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		CameraRig.hold_cursor(false)
	_stop_recording("left the blimp activity")
	if visual != null and visual.has_method("dispose_lighting"):
		visual.dispose_lighting()
	if Input.joy_connection_changed.is_connected(_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_joy_connection_changed)
	if _has_registry() and controller_registry.has_signal("selection_changed") \
			and controller_registry.selection_changed.is_connected(_on_controller_selection_changed):
		controller_registry.selection_changed.disconnect(_on_controller_selection_changed)


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
	var lake_resolution: Dictionary = LakeWorld.resolve(field, Scenery.options())
	_lake = lake_resolution.lake if lake_resolution.ok else {}
	if not lake_resolution.ok:
		push_warning("Blimp field lake refused: " + "; ".join(lake_resolution.errors))
	return true


func _load_presentation() -> bool:
	var parsed: Variant
	if not workshop_trial.is_empty():
		var bytes: PackedByteArray = workshop_trial.get("raw_bytes", PackedByteArray())
		parsed = JSON.parse_string(bytes.get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY:
			_trial_raw = parsed
		_size = float(workshop_trial.get("scale", 1.0))
		skin_id = Catalog.DEFAULT_SKIN
	else:
		var file := FileAccess.open(DATA_PATH, FileAccess.READ)
		parsed = JSON.parse_string(file.get_as_text()) if file != null else null
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("presentation")) != TYPE_DICTIONARY:
		startup_error = "Blimp presentation data is unavailable"
		return false
	presentation = parsed.presentation
	return true


func _build_field() -> void:
	var field_node: Node3D = FieldBuilder.build(field, _lighting, [])
	_attach_field(field_node)


func _build_field_staged() -> Dictionary:
	var field_node := await FieldBuilder.build_staged(field, _lighting, [], startup_checkpoint)
	if field_node == null:
		return {cancelled = true}
	var attach_started := Time.get_ticks_usec()
	_attach_field(field_node)
	return {cancelled = false, field_build_ms = float(field_node.get_meta("field_build_ms", 0.0))
		+ (Time.get_ticks_usec() - attach_started) / 1000.0}


func _attach_field(field_node: Node3D) -> void:
	var lake_error := str(field_node.get_meta("lake_error", ""))
	if not lake_error.is_empty():
		push_warning("Blimp field lake refused: " + lake_error)
	add_child(field_node)


func _session_options() -> Dictionary:
	# Weigh-off presets are stated for the 5 m blimp and scale with displaced volume (s^3).
	var options := {data_path = DATA_PATH, heaviness_kg = Hud.BALLAST_KG[ballast_index] * pow(_size, 3.0),
		wind_speed_mps = Hud.WIND_MPS[wind_index], wind_from_deg = 270.0, start = "air" if start_index == 0 else "ground"}
	if not _trial_raw.is_empty():
		options.data = _trial_raw
	if not _lake.is_empty():
		options.lake = _lake
	return options


func _has_registry() -> bool:
	return controller_registry != null and controller_registry.has_method("selected_device_id")


func _connect_selected_controller() -> void:
	if not _has_registry():
		input.connect_first_device()
		_bind_gamepad_confirmation()
		return
	var id := int(controller_registry.selected_device_id("flight"))
	var info: Dictionary = controller_registry.device_for_id(id)
	if id < 0 or not bool(info.get("connected", false)):
		input.use_keyboard()
		_controller_generation = 0
		return
	var profile: Dictionary = controller_profile_for.call(id) if controller_profile_for.is_valid() else {}
	if profile.is_empty():
		# The managed resolver returns the standard pad default when authorized.
		# An empty result can instead mean a storage or identity refusal; do not
		# let RcInput infer a gamepad mapping from that failure.
		info = info.duplicate(true)
		info.known = false
	input.connect_device(id, info, profile)
	_controller_generation = int(controller_registry.connection_generation(id))
	_bind_gamepad_confirmation()


func _bind_gamepad_confirmation() -> void:
	input.radio.confirmed_gamepad_connection = Callable()
	if not input.radio.connected:
		return
	var id := int(input.radio.device_id)
	if _has_registry():
		if controller_confirmation.is_valid():
			input.radio.confirmed_gamepad_connection = controller_confirmation.bind(id, _controller_generation)
	else:
		input.radio.confirmed_gamepad_connection = _confirmed_direct_gamepad


func _confirmed_direct_gamepad(id: int) -> bool:
	if not is_inside_tree() or not get_window().has_focus() or not input.radio.connected \
			or id != int(input.radio.device_id) or not Input.get_connected_joypads().has(id) or not Input.is_joy_known(id):
		return false
	var info: Dictionary = Input.get_joy_info(id)
	info.merge({name = Input.get_joy_name(id), guid = Input.get_joy_guid(id), known = true})
	return RcInput.key_for(id, info) == str(input.radio.device_key)


func _sync_selected_controller() -> void:
	if not is_inside_tree() or not _has_registry():
		return
	var id := int(controller_registry.selected_device_id("flight"))
	var current: int = int(input.radio.device_id) if input.radio.connected else -1
	var generation := int(controller_registry.connection_generation(id)) if id >= 0 else 0
	if id == current and generation == _controller_generation:
		return
	var before: int = input.source_generation
	if current >= 0 and id < 0:
		var previous: Dictionary = controller_registry.device_for_id(current)
		if not bool(previous.get("connected", false)) \
				or int(previous.get("generation", 0)) != _controller_generation:
			input.on_connection_changed(current, false)
			_controller_generation = 0
			_source_changed(before)
			return
	_connect_selected_controller()
	_source_changed(before)


func _on_controller_selection_changed(role: String, _id: int) -> void:
	if role == "flight":
		_sync_selected_controller()
	_refresh_pause_bindings()


func _source_changed(before: int) -> void:
	if before == input.source_generation:
		return
	input.reset_virtual_for_pause()
	_refresh_pause_bindings()
	if session != null and session.prepared and hud != null:
		_open_menu(input.message)


func _joy_connection_changed(id: int, connected: bool) -> void:
	var before: int = input.source_generation
	if _has_registry():
		if not connected and input.radio.connected and int(input.radio.device_id) == id:
			input.on_connection_changed(id, false)
		# Registry selection is explicit; a new connection, even with the same
		# name or handle, cannot take over the flight role automatically.
		_sync_selected_controller.call_deferred()
	else:
		input.on_connection_changed(id, connected)
		_bind_gamepad_confirmation()
	_source_changed(before)


## Cache the Pause binding for each selected role. A raw device has no inherited
## SDL button layout: it may use a joystick binding only when explicitly saved.
func _refresh_pause_bindings() -> void:
	_pause_bindings.clear()
	for role: String in ["flight", "ui"]:
		var id := int(controller_registry.selected_device_id(role)) if _has_registry() \
			else (int(input.radio.device_id) if input.radio.connected else -1)
		if id < 0:
			continue
		var generation: int = int(controller_registry.connection_generation(id)) if _has_registry() else int(input.source_generation)
		var profile: Dictionary = {}
		if input.radio.connected and int(input.radio.device_id) == id:
			profile = input.radio.profile
		elif controller_profile_for.is_valid():
			profile = controller_profile_for.call(id)
		if profile.is_empty() or not bool(profile.get("configured", false)):
			continue
		var actions: Dictionary = profile.get("actions", {})
		if profile.get("kind", "") != "gamepad" and not actions.has("pause"):
			continue
		var binding: Dictionary = ControllerActions.effective_bindings(profile, {}).get("pause", {})
		_pause_bindings[role] = {id = id, generation = generation, kind = str(profile.get("kind", "")), binding = binding}


## Observe the actual selected role and its saved Pause binding, including release
## and axis hysteresis. Raw button and axis mappings must first be observed OFF.
func _route_controller_pause(event: InputEvent) -> bool:
	if not event is InputEventJoypadButton and not event is InputEventJoypadMotion and not event is InputEventKey:
		return false
	var role := "ui" if hud != null and hud.menu_visible else "flight"
	var entry: Dictionary = _pause_bindings.get(role, {})
	if entry.is_empty():
		return false
	if (event is InputEventJoypadButton or event is InputEventJoypadMotion) and event.device != int(entry.id):
		return false
	var binding: Dictionary = entry.binding
	var kind := str(binding.get("type", ""))
	if kind == "button":
		if not event is InputEventJoypadButton or event.button_index != int(binding.get("button", -1)):
			return false
	elif kind == "axis":
		if not event is InputEventJoypadMotion or event.axis != int(binding.get("axis", -1)) or not is_finite(event.axis_value):
			return false
	elif kind == "key":
		if not event is InputEventKey or event.echo:
			return false
		var physical := int(binding.get("physical_keycode", 0))
		if (event.physical_keycode != physical if physical != 0 else event.keycode != int(binding.get("keycode", 0))):
			return false
	else:
		return false
	var key := "%d:%d:%s" % [int(entry.id), int(entry.generation), var_to_str(binding)]
	var was_held := bool(_pause_held.get(key, false))
	var active := ControllerActions.matches_binding(binding, event, int(entry.id), was_held)
	if kind == "button":
		active = (event as InputEventJoypadButton).pressed
	elif kind == "key":
		active = (event as InputEventKey).pressed and active
	if not active:
		_pause_held.erase(key)
		if kind in ["axis", "button"]:
			_pause_off_seen[key] = true
		return false
	var needs_off: bool = kind == "axis" or (kind == "button" and str(entry.get("kind", "")) in ["radio", "joystick"])
	if needs_off and not bool(_pause_off_seen.get(key, false)):
		return false
	if not was_held:
		_pause_held[key] = true
		if hud.menu_visible: handle_action("resume")
		else: _open_menu("Paused")
	return true


func _input(event: InputEvent) -> void:
	input.on_event(event)
	if hud != null and _route_controller_pause(event):
		get_viewport().set_input_as_handled()


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
				_rig.cycle(-1 if event.shift_pressed else 1)
				hud.select_choice("camera", _rig.available_views().find(_rig.view))
				get_viewport().set_input_as_handled()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				_rig.select_view(VIEW_KEYS[event.physical_keycode])
				hud.select_choice("camera", _rig.available_views().find(_rig.view))
				get_viewport().set_input_as_handled()
			KEY_EQUAL, KEY_MINUS:
				_rig.zoom(1.0 if event.physical_keycode == KEY_EQUAL else -1.0)
				get_viewport().set_input_as_handled()
			KEY_BACKSPACE:
				_rig.reset_view()
				get_viewport().set_input_as_handled()
			KEY_Z:
				_rig.toggle_auto_zoom()
				get_viewport().set_input_as_handled()
			KEY_H:
				hud.toggle_help()
				get_viewport().set_input_as_handled()
			KEY_F10:
				toggle_recording()
				get_viewport().set_input_as_handled()
			KEY_F11:
				if flight_log != null and flight_log.recording:
					flight_log.mark()
					hud.flash("Flight log marker")
				get_viewport().set_input_as_handled()
	elif not hud.menu_visible:
		if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			_rig.drag(event.relative)
		elif event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT and _rig.view == "orbit":
				CameraRig.hold_cursor(event.pressed)
			elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				var notches: float = event.factor if event.factor > 0.0 else 1.0
				_rig.zoom(notches if event.button_index == MOUSE_BUTTON_WHEEL_UP else -notches)


func _open_menu(reason: String) -> void:
	if session.prepared and not session.paused:
		input.reset_virtual_for_pause()
		session.pause(reason)
	var can_resume: bool = session.crash.is_empty() and str(session.fault_reason).is_empty()
	hud.show_menu(reason + "\nVirtual throttle and keyboard sticks reset. Lower throttle and centre yaw to resume.", can_resume)


func handle_action(action: String) -> void:
	match action:
		"resume":
			if not session.crash.is_empty():
				hud.flash("Restart to fly again.")
				return
			var sample: Dictionary = input.sample(1.0 / 240.0, false)
			if not sample.armed:
				var reason := str(sample.get("error", ""))
				hud.flash(reason if not reason.is_empty() else "Controls not armed: lower the throttle and check the controller.")
				return
			if not session.resume(sample.sticks):
				hud.flash(str(session.pause_reason))
				return
			hud.hide_menu()
		"restart":
			_restart()
		"help":
			hud.toggle_help()
		"home":
			_stop_recording("left the blimp activity")
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
			var previous := ballast_index
			ballast_index = index
			if not _restart():
				ballast_index = previous
				hud.select_choice("ballast", previous)
		"wind":
			var previous := wind_index
			wind_index = index
			if not _restart():
				wind_index = previous
				hud.select_choice("wind", previous)
		"start":
			var previous := start_index
			start_index = index
			if not _restart():
				start_index = previous
				hud.select_choice("start", previous)
		"camera":
			var views := _rig.available_views()
			if index >= 0 and index < views.size():
				_rig.set_view(views[index])


## A configuration change is a new admitted model: prepare and reset, keeping the old session on refusal.
func _restart() -> bool:
	if not session.prepare(field, _session_options()):
		hud.flash("Configuration refused: " + str(session.load_error))
		return false
	input.reset_throttle()
	_rig.reset()
	_refresh_fpv_mount()
	if visual.has_method("reset_lighting"):
		visual.reset_lighting()
	_open_menu(session.pause_reason)
	_note_weigh_off()
	return true


func _swap_skin(next_skin: String) -> void:
	if not workshop_trial.is_empty() or not creator_visual.is_empty():
		return
	var candidate := Visual.new()
	if not candidate.build(presentation, next_skin):
		hud.select_choice("skin", Catalog.SKIN_IDS.find(skin_id))
		hud.flash(str(candidate.error))
		return
	if visual.has_method("dispose_lighting"):
		visual.dispose_lighting()
	remove_child(visual.root)
	visual.root.queue_free()
	visual = candidate
	skin_id = next_skin
	add_child(visual.root)
	visual.model.scale = Vector3.ONE * _size
	var shadow_cue := get_node_or_null("VehicleShadowCue")
	if shadow_cue != null:
		shadow_cue.set_vehicle(visual.root) # rebinds the new skin's silhouette on its next frame
	_configure_lights()
	_refresh_fpv_mount()
	_process(0.0)
	skin_changed.emit(skin_id)


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
	if session.tick_once(sample.sticks) and is_instance_valid(_mechanical):
		_mechanical.observe_accepted(_servo_snapshot(false))


func _process(delta: float) -> void:
	if session == null or not session.prepared or visual == null:
		return
	var fraction := Engine.get_physics_interpolation_fraction() if not session.paused else 1.0
	var drawn: PackedFloat64Array = session.interpolated(fraction)
	visual.pose(drawn, session.sim.continuous, delta if not session.paused else 0.0)
	_update_lights(drawn, delta)
	var pose: Transform3D = visual.root.transform
	var target := pose.origin
	var body_basis := pose.basis
	var velocity := body_basis * Frames.ned_to_render([drawn[3], drawn[4], drawn[5]])
	# Size the shared rigid inspection offset to the envelope, including a scaled Workshop build.
	var inspection := Transform3D(body_basis.scaled(Vector3.ONE * float(session.data.envelope.length) * 0.5), target)
	if hud.menu_visible and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		CameraRig.hold_cursor(false)
	else:
		CameraRig.release_cursor_if_up()
	# The inspection boom has its own scale. FPV already binds the scaled shell in the visual root's frame.
	_rig.update(target, pose if _rig.view == "fpv" else inspection, body_basis, delta, session.paused,
		_ground_height_render, velocity, _camera_clearance)
	if _environment != null:
		World.update(_environment, 37.0 + session.sim.time(), Vector3.ZERO, target, camera)
	if _lens != null:
		# A crash pauses the session; the lens keeps presenting its aftermath, and holds only for a real pause.
		_lens.advance(delta, session.sim.time(), session.paused and session.crash.is_empty())
	hud.update(session.telemetry, _last_input, _rig.view_name(), session.pause_reason if session.paused else "")
	_update_audio(target, body_basis)


func _ground_height_render(x: float, z: float) -> float:
	var h: PackedFloat64Array = session.environment.ground(-z, x)
	return h[0] if h.size() == 3 and is_finite(h[0]) else 0.0


func _camera_clearance(from: Vector3, to: Vector3) -> float:
	return CameraCollision.free_fraction(_obstacle_world, from, to)


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
	_mechanical = MechanicalAudio.new()
	_mechanical.name = "ServoAudio"
	_mechanical.configure(self, &"Master", MechanicalProfile.resolve(workshop_trial.get("presentation_profile", {})))
	_mechanical.set_accepted_tick_observation(true)


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


func _update_audio(target: Vector3, body_basis: Basis) -> void:
	if _audio_side == null:
		return
	if is_instance_valid(_mechanical):
		var servo := _servo_snapshot(session.paused)
		var root_position: Vector3 = visual.root.global_position
		var anchors := _servo_anchor_nodes()
		for i in anchors.size():
			var sum := Vector3.ZERO
			var count := 0
			for node: Node3D in anchors[i]:
				if is_instance_valid(node):
					sum += node.global_position
					count += 1
			servo.channels[i].position = sum / float(count) if count > 0 else root_position
		servo.gear.position = root_position
		servo.listener = camera.global_position
		_mechanical.update_sound(servo, get_process_delta_time())
	var c: PackedFloat64Array = session.sim.continuous
	var side := maxf(absf(c[0]), absf(c[1]))
	var stern := maxf(absf(c[2]), absf(c[3]))
	_motor_sound(_audio_side, side, target + body_basis * (Vector3(0.0, -0.17, -0.8) * _size))
	_motor_sound(_audio_stern, stern, target + body_basis * (Vector3(0.0, 0.0, 2.45) * _size))


## The hinge nodes each servo channel sounds from, resolved once per built visual (a skin swap builds a new one).
func _servo_anchor_nodes() -> Array:
	var id := visual.get_instance_id()
	if id != _servo_anchor_visual:
		_servo_anchor_visual = id
		_servo_anchors.clear()
		var bindings: Dictionary = visual.get("_bindings")
		for keys: Array in SERVO_ANCHORS:
			var nodes: Array[Node3D] = []
			for key: String in keys:
				var node := (bindings.get(key, {}) as Dictionary).get("node") as Node3D
				if node != null:
					nodes.append(node)
			_servo_anchors.append(nodes)
	return _servo_anchors


func _motor_sound(player: AudioStreamPlayer3D, n: float, at: Vector3) -> void:
	player.global_position = at
	var silent: bool = session.paused or n < 0.02
	player.stream_paused = silent
	if silent:
		return
	var blade_hz := FULL_SPEED_RPM * n * BLADES / 60.0
	player.pitch_scale = clampf(blade_hz / MOTOR_AUDIO_REFERENCE_HZ, 0.35, 2.5)
	player.volume_db = linear_to_db(clampf(0.15 + 0.85 * n * n, 0.001, 1.0)) - 6.0


## Start or stop the opt-in flight log of the current flight; a reset or reconfiguration closes it.
func toggle_recording() -> void:
	if session == null or not session.prepared:
		return
	if flight_log != null and flight_log.recording:
		flight_log.stop("pilot stopped recording")
		hud.flash(str(flight_log.note))
		return
	flight_log = AirshipLog.new(session)
	flight_log.start({field_path = field_path})
	hud.flash(str(flight_log.note))


func _stop_recording(reason: String) -> void:
	if flight_log != null and flight_log.recording:
		flight_log.stop(reason)


## The keel ballast is limited: a heavy (or very light) Workshop build may not reach the selected weigh-off preset.
func _note_weigh_off() -> void:
	var requested := float(Hud.BALLAST_KG[ballast_index]) * pow(_size, 3.0)
	var actual := float(session.model.get("heaviness_kg", requested))
	if absf(actual - requested) > 1.0e-4:
		hud.flash("This build cannot trim to the selected weigh-off: it flies %+.0f g %s." % [1000.0 * absf(actual),
			"heavy" if actual >= 0.0 else "light"], 6.0)


## BL-19c: navigation, strobe, beacon and landing lights from the Workshop lighting profile ("inherit" = the night
## kit only at night). Graphics only: nothing here reads back into the session.
func _configure_lights() -> void:
	if visual == null or not visual.has_method("configure_lighting"):
		return
	var result: Dictionary = visual.configure_lighting(workshop_trial.get("presentation_profile", {}).get("lighting", {}),
		{lighting_config = lighting_config, lighting_snapshot = _lighting, rig_parent = self})
	if not result.get("ok", true):
		push_warning("Blimp lighting: " + "; ".join(result.get("errors", PackedStringArray())))


func _update_lights(drawn: PackedFloat64Array, delta: float) -> void:
	if not visual.has_method("update_lighting"):
		return
	var throttle := 0.0
	var sticks: Variant = _last_input.get("sticks", PackedFloat64Array())
	if sticks is PackedFloat64Array and sticks.size() == 4:
		throttle = sticks[3]
	var speed := sqrt(drawn[3] * drawn[3] + drawn[4] * drawn[4] + drawn[5] * drawn[5])
	var distance := camera.global_position.distance_to(visual.root.global_position) if camera != null else 0.0
	visual.update_lighting(delta if not session.paused else 0.0, session.sim.time(), {throttle = throttle, speed_mps = speed,
		airspeed = speed, roll_rate = drawn[10], pitch_rate = drawn[11], distance_m = distance})


## Accepted actuator angles only (degrees), as the fixed-wing mechanical snapshot. The blimp has fixed gear.
func _servo_snapshot(paused: bool) -> Dictionary:
	var c: PackedFloat64Array = session.sim.continuous
	var channels: Array[Dictionary] = []
	for spec: Array in SERVO_CHANNELS:
		var total := 0.0
		for index: int in spec[1]:
			total += c[index]
		channels.append({id = str(spec[0]), angle_deg = rad_to_deg(total / float(spec[1].size())), position = Vector3.ZERO})
	return {tick = int(session.sim.tick), tick_rate = float(Session.FIXED_HZ), paused = paused, channels = channels,
		gear = {available = false, extension = 0.0, target_down = false, status = "unavailable", target = 0.0, position = Vector3.ZERO}}


## AppRoot calls this after saving a profile for the selected flight device.
func apply_controller_selection(device_id: int) -> bool:
	if session == null or not session.prepared or not _has_registry():
		return false
	if device_id != int(controller_registry.selected_device_id("flight")):
		return false
	var current: int = int(input.radio.device_id) if input.radio.connected else -1
	if device_id != current:
		_sync_selected_controller()
		return true
	if device_id < 0 or not controller_profile_for.is_valid():
		_refresh_pause_bindings()
		return true
	var profile: Dictionary = controller_profile_for.call(device_id)
	if profile.is_empty() or profile == input.radio.profile:
		_refresh_pause_bindings()
		return true
	var before: int = input.source_generation
	if not input.use_profile(profile):
		return false
	_bind_gamepad_confirmation()
	_source_changed(before)
	return true


func _refresh_controller_ui() -> void:
	_refresh_pause_bindings()
