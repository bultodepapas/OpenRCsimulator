extends Node3D
# The game shell: world, airplane rendering, camera, panel, keys, captures and headless traces.
# The flight itself (aircraft data, trim, commands, simulation) lives in sim/flight_session.gd.

const Spec := preload("res://spec.gd")
const Scripted := preload("res://sim/scripted.gd")
const Frames := preload("res://render/frames.gd")
const AirplaneBuilder := preload("res://render/airplane.gd")
const GroundGear := preload("res://render/ground_gear.gd")
const PropellerBlur := preload("res://render/propeller_blur.gd")
const EngineSmoke := preload("res://render/smoke/exhaust.gd")
const Propulsion := preload("res://physics/propulsion.gd")
const Slipstream := preload("res://physics/slipstream.gd")
const SmokeAssignment := preload("res://ui/smoke_aux_assignment.gd")
const PilotCamera := preload("res://render/pilot_camera.gd")
const CameraRig := preload("res://render/camera/camera_rig.gd")
const GroundTerrain := preload("res://physics/ground_terrain.gd")
const Commands := preload("res://input/commands.gd")
const InputPanel := preload("res://render/panel.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const CrashDirector = preload("res://render/crash/director.gd")
const SceneryDamageDirector = preload("res://render/crash/scenery_damage.gd")
const ImpactSnapshot = preload("res://physics/impact_snapshot.gd")
const Recorder := preload("res://sim/recorder.gd")
const RB := preload("res://physics/rigid_body.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const EngineSound := preload("res://render/engine_sound.gd")
const FlightAudio = preload("res://audio/flight_audio.gd")
const VisualTimeline = preload("res://environment/visual_timeline.gd")
const VisualCheckpoint = preload("res://app_state/visual_checkpoint.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const TimeOfDayLighting = preload("res://render/time_of_day_lighting.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Shadow := preload("res://render/shadow.gd")
const Ground := preload("res://render/ground.gd") # legacy atmosphere fixture only
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const SceneryCollisionSetup = preload("res://scenery/collision_setup.gd")
const World := preload("res://render/world/world.gd")
const FieldError = preload("res://ui/field_error.gd")
const Hud := preload("res://render/hud.gd")
const FrameSamples := preload("res://render/frame_samples.gd")
const Air := preload("res://physics/air_data.gd")
const M := preload("res://physics/math3d.gd")
const VisualEvidence = preload("res://render/visual_evidence.gd")
const BuildInfo := preload("res://app_state/build_info.gd")
const LatencyPatch = preload("res://input/latency_patch.gd")
const OverlayManager := preload("res://render/overlays/overlay_manager.gd")

## [Esc] outside the calibration wizard: the pilot asks for the pause menu (app_root owns menus; without one, nothing).
signal pause_requested
## The player changed the flight overlays (X, [F2], [F3]); Home saves them (docs/plans/flight-overlays.md).
signal overlay_settings_changed(settings: Dictionary)

## Data path is injectable before entering the tree; normal routes use the packaged default.
var field_path: String = FieldLoader.DEFAULT_PATH
var field: Dictionary = {}

var session: Node
var recorder: RefCounted
## The catalog aircraft to fly. Set before adding the node (Home does); otherwise --aircraft=<id>, else the Ugly Stik.
var aircraft_id := ""
var _experimental_aircraft_path := ""
var _electric_demo: String = ""
## Interactive Home choice only; CLI and scripted routes retain the airborne default.
var start_choice: String = "airborne"
var weather_config: Dictionary = {}
## TOD: immutable selection for this flight; no preference reads on the direct route.
var lighting_config: Dictionary = {}
var _lighting: Dictionary = {}
var _visual_timeline: Dictionary = {}
var _visual_context_status: String = "present"
var _field_world_lighting: bool = false
var _world_environment: WorldEnvironment
var _sun: DirectionalLight3D
var _field_node: Node3D


## Direct/technical launches never read interactive preferences. All values remain SI/full precision.
func _weather_options(options: Dictionary) -> Dictionary:
	var raw: Variant = weather_config.duplicate(true) if not weather_config.is_empty() else FlightSession.WeatherConfig.defaults()
	if options.has("weather") and options.has("weather-file"):
		return {ok = false, config = {}, errors = PackedStringArray(["choose --weather or --weather-file, not both"])}
	if options.has("weather"):
		if typeof(options.weather) != TYPE_STRING:
			return {ok = false, config = {}, errors = PackedStringArray(["--weather needs a preset ID"])}
		raw = FlightSession.WeatherConfig.preset(options.weather)
		if raw.is_empty():
			return {ok = false, config = {}, errors = PackedStringArray(["unknown weather preset '%s'" % options.weather])}
	if options.has("weather-file"):
		if typeof(options["weather-file"]) != TYPE_STRING or not FileAccess.file_exists(options["weather-file"]):
			return {ok = false, config = {}, errors = PackedStringArray(["--weather-file needs an existing JSON file"])}
		var parser: JSON = JSON.new()
		if parser.parse(FileAccess.get_file_as_string(options["weather-file"])) != OK:
			return {ok = false, config = {}, errors = PackedStringArray(["weather JSON is invalid: " + parser.get_error_message()])}
		raw = parser.data
	var mappings: Dictionary = {"wind-speed": "speed_mps", "wind-from": "from_deg", "gust-speed": "gust_mps", "gust-up": "gust_up_mps", "gust-duration": "gust_duration_s", "gust-period": "gust_period_s", "gust-delay": "gust_delay_s"}
	for key: String in mappings:
		if not options.has(key):
			continue
		if not raw is Dictionary or typeof(options[key]) != TYPE_STRING or not str(options[key]).is_valid_float():
			return {ok = false, config = {}, errors = PackedStringArray(["--%s needs a finite number" % key])}
		raw[mappings[key]] = str(options[key]).to_float()
	return FlightSession.WeatherConfig.validate(raw)


func _render_wind(time_s: float) -> Vector3:
	if _scripted or session == null:
		return Vector3.ZERO
	return Frames.ned_to_render(Array(session.wind_at(time_s)))
var interactive_start: bool = false
## UI-06d: Home injects the saved diagnostic choice; technical launches retain their explicit marker flag.
var latency_marker_enabled: bool = false
## Flight overlays instead of the legacy text labels: Home sets it with the saved settings; the direct route uses
## --hud=overlays (default --hud=legacy, so captures and automation keep their picture).
var overlays_enabled: bool = false
var overlay_settings: Variant = {}
var startup_error: String = ""
var _airplane: Dictionary
var _camera: Camera3D
## CAM-02: views, zoom and camera input (render/camera/camera_rig.gd); built with the world.
var _rig: CameraRig
## The view a flight starts in: --view=<pilot|chase|orbit|closeup>, or closeup with --inspect.
var _initial_view := "pilot"
var _camera_dt := 0.0
var _panel: Label
## The historical close-up switch, kept for fixtures that set it: true selects the close-up view, false the pilot view.
var _inspect: bool:
	get:
		return _rig.view == "closeup" if _rig != null else _initial_view == "closeup"
	set(on):
		if _rig != null:
			_rig.set_view("closeup" if on else "pilot")
		else:
			_initial_view = "closeup" if on else "pilot"
var _capturing := false
var _t := 0.0
var _prop_angle := 0.0
## --scripted: the Stage 0/1 scripted circle instead of the physics simulation.
var _scripted := false
var _engine_audio: AudioStreamPlayer3D
var _soundscape_audio: FlightAudio
## Technical fixtures can retain the original diagnostic freeze route.
var crash_effects_enabled := true
var _crash_director: CrashDirector
var _scenery_damage_director: SceneryDamageDirector
var _cg_model := Vector3.ZERO
var _env: Environment
## Landscape review view (L0): (azimuth, elevation) in degrees from the pilot's eye, or (NAN, NAN) to follow the airplane.
var _look := Vector2(NAN, NAN)
var _look_height := 1.7 # m above the pilot station (L0b top-down view: 30)
var _shadow: MeshInstance3D
## Ground shadow mode: "sun" (projected along the light, L3, default), "vertical" (the D7 pilot aid) or "off".
## [V] cycles; Gate L decides the default.
const SHADOW_MODES := ["sun", "vertical", "off"]
var _shadow_mode := "sun"
var _extent := Vector2(1.5, 1.3) # airplane span and length (m), measured from the built model
var _hud: Label
var _overlays: CanvasLayer = null # OverlayManager when overlays_enabled
var _auto_zoom := true
var _show_perf := true
var _frame_times := PackedFloat64Array()
## VQ-01b frame-time logger; raw wall deltas and the engine's delta are both retained.
var _frametimes_path: String = ""
var _frametimes_warmup_s: float = 1.0
var _frametimes_duration: float = 20.0
var _frametime_samples: RefCounted = null
var _frametimes_elapsed: float = 0.0
var _frametimes_active: bool = false
var _frametimes_clock_primed: bool = false
var _frametimes_scripted_fixed: bool = false
var _frametimes_last_usec: int = 0
var _frametimes_sim_start_s: float = 0.0
var _frametimes_sim_start_tick: int = 0
## Last one-off message (reload result), shown in the panel.
var _note := ""
var _visual_pose: Dictionary = {}
var _smoke: EngineSmoke
var _smoke_key_on := false
var _smoke_assignment: SmokeAssignment
var _smoke_assignment_was_paused := false
var _last_render_pose: Dictionary = {}
var _treeline_hidden: bool = false # L6c background-only capture (--hide_treeline)


func _ready() -> void:
	var args := _user_args()
	# The field-world route owns --date when paired with its time selection.
	var lighting_args: Dictionary = args.duplicate()
	if (args.has("time_of_day") or args.has("time")) and not (args.has("time-of-day") or args.has("lighting") or args.has("lighting-config")):
		lighting_args.erase("date")
	var selected_light: Dictionary = LightingConfig.validate(LightingConfig.defaults() if lighting_config.is_empty() else lighting_config) if interactive_start else LightingConfig.from_args(lighting_args)
	if not selected_light.ok:
		startup_error = "; ".join(selected_light.errors)
		set_process(false)
		set_process_unhandled_input(false)
		if not interactive_start:
			printerr("lighting: " + startup_error)
			get_tree().quit(ERR_INVALID_PARAMETER)
		return
	lighting_config = selected_light.config.duplicate(true)
	_lighting = TimeOfDayLighting.snapshot(lighting_config)
	_visual_timeline = VisualTimeline.create(lighting_config).timeline
	var latency_args: Dictionary = args.duplicate()
	if interactive_start and latency_marker_enabled:
		latency_args["latency-patch"] = true
	var latency_options: Dictionary = LatencyPatch.options(latency_args)
	if not latency_options.ok:
		printerr(latency_options.error)
		set_process(false)
		set_process_unhandled_input(false)
		get_tree().quit(ERR_INVALID_PARAMETER)
		return
	var trace_ticks: int = -1
	if args.has("trace"):
		var duration_text: String = str(args.get("t", Spec.CAPTURE.time))
		var duration: float = duration_text.to_float() if duration_text.is_valid_float() else NAN
		var rounded_ticks: float = roundf(duration * Engine.physics_ticks_per_second)
		if typeof(args.trace) != TYPE_STRING or str(args.trace).is_empty() \
			or not is_finite(duration) or duration <= 0.0 or not is_finite(rounded_ticks) \
			or rounded_ticks < 1.0 or rounded_ticks >= float(9223372036854775807):
			push_error("--trace requires a path and finite positive --t that rounds to at least one tick and fits the tick counter")
			set_process(false)
			set_process_unhandled_input(false)
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
		trace_ticks = int(rounded_ticks)
	var loaded_field: Dictionary = FieldLoader.load_from(field_path)
	if not loaded_field.ok:
		if interactive_start:
			startup_error = "; ".join(loaded_field.errors)
			set_process(false)
			set_process_unhandled_input(false)
			return
		FieldError.report(self, loaded_field.errors)
		return
	field = loaded_field.field
	var frametime_options: Dictionary = FrameSamples.options(args)
	if not frametime_options.ok:
		push_error(str(frametime_options.error))
		set_process(false)
		set_process_unhandled_input(false)
		get_tree().quit(ERR_INVALID_PARAMETER)
		return
	var pose_error: String = VisualEvidence.validate_pose(args)
	if pose_error != "":
		push_error(pose_error)
		set_process(false)
		get_tree().quit(ERR_INVALID_PARAMETER)
		return
	if args.has("visual_pose"):
		_visual_pose = VisualEvidence.synthetic_pose(str(args.visual_pose), float(args.visual_distance), float(field.pilot.eye_height) - float(field.pilot.down),
			float(args.get("visual_elevation", VisualEvidence.DEFAULT_ELEVATION_DEG)), float(args.get("visual_azimuth", VisualEvidence.DEFAULT_AZIMUTH_DEG)))
		_visual_pose.pos += Frames.ned_to_render([field.pilot.north, field.pilot.east, 0.0])
	# Deliver input events at once: with accumulation, joypad events reach the game a frame late on Linux/macOS.
	Input.use_accumulated_input = false
	_inspect = args.has("inspect")
	if args.has("view"):
		_initial_view = str(args.view)
		if not CameraRig.is_view(_initial_view) or (args.has("visual_pose") and _initial_view != "pilot"):
			push_error("--view must be one of %s (visual poses need the pilot view)" % ", ".join(CameraRig.VIEWS))
			set_process(false)
			set_process_unhandled_input(false)
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
	_scripted = args.has("scripted")
	if aircraft_id == "":
		aircraft_id = str(args.get("aircraft", Catalog.DEFAULT_ID))
	if not Catalog.has(aircraft_id) or (not Catalog.can_fly(aircraft_id) and not _scripted):
		# Never another airplane in its place, and never a preview "flying" without flight data (it would be a
		# ballistic throw). A preview may still fly the scripted circle (--scripted): visual only.
		push_error("aircraft '%s' refused: %s" % [aircraft_id, "not in the catalog (%s)" % ", ".join(Catalog.ids()) if not Catalog.has(aircraft_id) else "preview only, no flight data (use --scripted)"])
		set_process(false)
		set_process_unhandled_input(false)
		get_tree().quit(1)
		return
	_electric_demo = str(args.get("electric-demo", ""))
	if args.has("electric-demo") and (_electric_demo not in ["4s", "6s", "4s-battery", "6s-battery"] or aircraft_id != Catalog.DEFAULT_ID or _scripted):
		printerr("electric demo requires 4s, 6s, 4s-battery or 6s-battery, the default visual airframe, and a physics flight")
		set_process(false)
		set_process_unhandled_input(false)
		get_tree().quit(ERR_INVALID_PARAMETER)
		return
	var experimental_input_sha256 := ""
	if args.has("experimental-aircraft-data"):
		var experimental: Dictionary = _validate_experimental_aircraft_data(
			args.get("experimental-aircraft-data"), aircraft_id, _scripted, args.has("electric-demo"))
		if not experimental.ok:
			printerr("experimental aircraft data refused: ", experimental.error)
			set_process(false)
			set_process_unhandled_input(false)
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
		_experimental_aircraft_path = experimental.path
		experimental_input_sha256 = experimental.input_sha256
		_note = "EXPERIMENTAL: wing polar; aircraft-specific flight validation pending."
		print("EXPERIMENTAL AIRCRAFT DATA: wing polar, aircraft-specific flight validation pending: ", _experimental_aircraft_path)
	_auto_zoom = str(args.get("autozoom", "1")) != "0"
	var hud_mode := str(args.get("hud", "overlays" if overlays_enabled else "legacy"))
	if hud_mode != "legacy" and hud_mode != "overlays":
		printerr("--hud must be legacy or overlays")
		set_process(false)
		set_process_unhandled_input(false)
		get_tree().quit(ERR_INVALID_PARAMETER)
		return
	overlays_enabled = hud_mode == "overlays"
	if args.has("look_az"):
		_look = Vector2(float(args.look_az), float(args.get("look_el", 0.0)))
		_look_height = float(args.get("look_alt", field.pilot.eye_height))
	Atmosphere.engine_shadows = Atmosphere.engine_shadows_enabled(args, interactive_start)
	_build_world()
	_rig.set_view(_initial_view)
	_rig.auto_zoom = _auto_zoom
	_rig.look = _look
	_rig.look_height = _look_height
	_shadow_mode = str(args.get("shadow", "sun"))
	if args.has("hide_airplane"):
		# L0c readability: the same view without the airplane (and its pilot-aid shadow) is the background reference.
		_airplane.root.visible = false
		_shadow.visible = false
	if args.has("hide_treeline"):
		# L6c: the same view without the vegetation gives the exact tree mask behind the airplane. A field with
		# nothing to hide (the atmosphere fixture) must fail, never pass off a view with trees as the tree-free one.
		if not _hide_field_objects():
			push_error("--hide_treeline refused: this field has no objects to hide")
			set_process(false)
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
	session = FlightSession.new()
	session.physics_enabled = not _scripted
	if args.has("shaft-integrator") and (not session.setup_shaft_integrator(args["shaft-integrator"]) or _scripted):
		printerr("shaft integrator refused: ", session.shaft_error if not _scripted else "requires a physics flight")
		session.free() # refused before add_child(): this owner would otherwise remain orphaned
		session = null
		get_tree().quit(ERR_INVALID_PARAMETER)
		set_process(false)
		set_process_unhandled_input(false)
		return
	var physics_path: String = _experimental_aircraft_path if not _experimental_aircraft_path.is_empty() else (str(Catalog.entry(aircraft_id).data) if _electric_demo.is_empty() else "res://data/aircraft/synthetic_stik_electric_%s.json" % _electric_demo.replace("-", "_"))
	session.setup(physics_path, aircraft_id if _electric_demo.is_empty() and _experimental_aircraft_path.is_empty() else "")
	# D6e: keyboard and gamepad flights use the aircraft's normal rates and expo (controls.rates.normal) unless
	# --rates=full asks for the maximum throws; radios keep their own rates either way.
	var rates := str(args.get("rates", "normal"))
	if rates != "normal" and rates != "full":
		printerr("--rates must be normal or full")
		session.free()
		session = null
		set_process(false)
		set_process_unhandled_input(false)
		get_tree().quit(ERR_INVALID_PARAMETER)
		return
	session.rate_profile = rates
	if not _experimental_aircraft_path.is_empty():
		var candidate_model: Dictionary = session.aircraft.get("model", {}) if session.aircraft.get("ok", false) else {}
		var candidate_envelope: Dictionary = candidate_model.get("envelope", {})
		if not session.aircraft.get("ok", false) or candidate_model.get("id", "") != Catalog.DEFAULT_ID or not candidate_envelope.has("wing_polar") or session.aircraft.get("input_identity", {}).get("sha256", "") != experimental_input_sha256:
			var load_reason := "; ".join(session.aircraft.get("errors", PackedStringArray())) if not session.aircraft.get("ok", false) else "loaded model identity/polar is missing, or candidate changed during validation"
			printerr("experimental aircraft data refused after load: ", load_reason)
			session.free()
			session = null
			set_process(false)
			set_process_unhandled_input(false)
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
	if args.has("shaft-integrator") and not session.is_flyable():
		printerr("shaft integrator refused: ", session.pause_reason)
		session.free()
		session = null
		get_tree().quit(ERR_INVALID_PARAMETER)
		set_process(false)
		set_process_unhandled_input(false)
		return
	session.set_field(field) # E3a: the wheels roll on this field's runway, mown and rough surfaces
	if not _scripted and _capture_scene_id() == "field":
		var obstacles := SceneryCollisionSetup.build(field)
		if not obstacles.ok or not session.set_collision_world(obstacles.world):
			startup_error = "Scenery collision inventory refused: " + "; ".join(obstacles.errors)
			printerr(startup_error)
			session.free()
			session = null
			set_process(false)
			set_process_unhandled_input(false)
			get_tree().quit(ERR_INVALID_DATA)
			return
	session.start_choice = start_choice
	var conditions: Dictionary = _weather_options(args)
	if not conditions.ok or not session.setup_weather(conditions.config):
		startup_error = "; ".join(conditions.errors) if not conditions.ok else session.weather_error
		if not interactive_start:
			printerr("weather refused: ", startup_error)
			get_tree().quit(ERR_INVALID_PARAMETER)
		set_process(false)
		set_process_unhandled_input(false)
		return
	_update_cg_model()
	if args.has("alt"):
		session.set_start_altitude(float(args.alt))
	add_child(session)
	Input.joy_connection_changed.connect(_on_smoke_connection_changed)
	if latency_options.enabled:
		var latency_patch: LatencyPatch = LatencyPatch.new()
		latency_patch.session = session
		latency_patch.axis = latency_options.axis
		latency_patch.threshold = latency_options.threshold
		latency_patch.left_side = _overlays != null # HUD: the overlays hold the right-hand side
		add_child(latency_patch)
	recorder = Recorder.new(session.sim, session.electrical_state)
	session.resetting.connect(_on_resetting)
	if str(args.get("soundscape", "on")) == "legacy" and session.aircraft.ok and not _scripted and session.aircraft.model.propulsion.get("kind", "glow_prop") != "electric_prop":
		_engine_audio = EngineSound.create(_airplane.root, session.sim, session.aircraft.model.propulsion.max_rpm)
	session.reset()
	GroundGear.attach(_airplane, session)
	# VQ-05: speed-driven propeller blur beside the model (never inside it); it only reads sim.aux[0] each frame.
	PropellerBlur.attach(_airplane, session, self)
	# SM: authored combustion outlet + accepted propulsion kind; previews/conversions stay clear.
	if str(args.get("smoke", "on")) != "off" and not _scripted and not args.has("capture") and not args.has("trace") and session.aircraft.get("ok", false):
		var mouths: Array = _airplane.get("exhausts", [])
		if mouths.size() == 1 and EngineSmoke.valid_anchor(mouths[0]) \
				and Propulsion.source_kind(session.aircraft.model.propulsion) == mouths[0].kind:
			_smoke = EngineSmoke.new()
			add_child(_smoke)
			_smoke.configure(mouths[0])
			_smoke_key_on = str(args.get("smoke-pump", "off")) == "on" # explicit technical capture/profile request
	if not _experimental_aircraft_path.is_empty() and (not session.is_flyable() or not session.surface_error.is_empty()):
		var candidate_flight_error: String = session.start_error if not session.start_error.is_empty() else session.pause_reason
		if candidate_flight_error.is_empty():
			candidate_flight_error = session.surface_error if not session.surface_error.is_empty() else "candidate did not produce a flyable start"
		printerr("experimental aircraft data refused before flight: ", candidate_flight_error)
		session.sim.set_paused(true)
		session.sim.process_mode = Node.PROCESS_MODE_DISABLED
		set_process(false)
		set_process_unhandled_input(false)
		get_tree().quit(ERR_INVALID_PARAMETER)
		return
	if interactive_start and not session.is_flyable():
		startup_error = session.start_error if not session.start_error.is_empty() else session.pause_reason
		if startup_error.is_empty():
			startup_error = "Aircraft data or starting condition invalid."
		set_process(false)
		set_process_unhandled_input(false)
		return
	if args.has("trace"):
		if not session.aircraft.ok or not session.surface_error.is_empty():
			# Never record a "flight" on invalid data (it would be a ballistic throw): fail the run instead.
			push_error("--trace refused: %s" % ("aircraft data invalid" if not session.aircraft.ok else session.surface_error))
			get_tree().quit(1)
			return
		# Headless trace: record from the start to t, save, quit. No window needed.
		_write_trace_and_quit(trace_ticks, str(args.trace))
		return
	if not _scripted and not args.has("capture") and str(args.get("soundscape", "on")) == "on":
		_soundscape_audio = FlightAudio.new()
		_soundscape_audio.name = "FlightAudio"
		add_child(_soundscape_audio)
		_soundscape_audio.configure(self)
		if session.aircraft.model.propulsion.get("kind", "glow_prop") != "electric_prop":
			_engine_audio = _soundscape_audio.soundscape.voices[0] # retain legacy combustion/turbine inspection interface
	elif str(args.get("soundscape", "on")) == "off":
		FlightAudio.silence_legacy_ambience(self)
	if not _scripted and _field_node != null and _capture_scene_id() == "field":
		_scenery_damage_director = SceneryDamageDirector.new()
		_scenery_damage_director.name = "SceneryDamageDirector"
		add_child(_scenery_damage_director)
		_scenery_damage_director.configure(self)
	if crash_effects_enabled and not _scripted and not args.has("capture") and str(args.get("crash-effects", "on")) != "off":
		_crash_director = CrashDirector.new()
		_crash_director.name = "CrashDirector"
		add_child(_crash_director)
		_crash_director.configure(self, physics_path, str(args.get("soundscape", "on")) != "off")
		session.crash_auto_restart = false
	# E3d1: interactive flights get soft hull contacts (a wingtip brush or belly slide continues); scripted, capture
	# and trace routes keep "any hull contact is a crash". -- --soft-contacts=off restores it interactively.
	session.soft_hull_contacts = not _scripted and not args.has("capture") and str(args.get("soft-contacts", "on")) != "off"
	if bool(frametime_options.enabled):
		_frametimes_path = str(frametime_options.path)
		_frametimes_warmup_s = float(frametime_options.warmup_s)
		_frametimes_duration = float(frametime_options.sample_s)
		_frametime_samples = FrameSamples.new()
		if not _frametime_samples.configure(_frametimes_warmup_s, _frametimes_duration):
			push_error("Invalid frame-time options: " + _frametime_samples.failure)
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
		_frametimes_active = true
		_frametimes_scripted_fixed = _scripted
		if _frametimes_scripted_fixed:
			session.input_enabled = false
			_show_perf = false
			set_process_unhandled_input(false)
	if args.has("capture"):
		_capturing = true
		_show_perf = false # wall-clock numbers would make captures differ run to run
		session.input_enabled = false
		# Settled commands from arguments (the limiter is skipped), so captures are deterministic.
		var c := {
			roll = float(args.get("roll", 0)), pitch = float(args.get("pitch", 0)),
			yaw = float(args.get("yaw", 0)), throttle = float(args.get("throttle", 0.5)),
		}
		var t := float(args.get("t", Spec.CAPTURE.time))
		await _capture(t, c, args.get("out", "user://capture.png"))


func _process(delta: float) -> void:
	if _capturing:
		return
	var dt := minf(delta, 0.1) # a stalled window must not jump the propeller or the scripted circle
	if _frametimes_active:
		if not _frametimes_clock_primed:
			_frametimes_last_usec = Time.get_ticks_usec()
			_frametimes_clock_primed = true
			_frametimes_sim_start_s = session.sim.time()
			_frametimes_sim_start_tick = session.sim.tick
		else:
			_log_frame_time(delta)
	var visual_clock_s: float = session.sim.time()
	if _frametimes_scripted_fixed:
		visual_clock_s = _frametimes_elapsed
	World.update(_env, visual_clock_s, _render_wind(visual_clock_s), _last_render_pose.get("pos"), _camera) # deterministic wind and field-world adaptation
	_frame_times.append(delta)
	if _frame_times.size() > Hud.FRAMES:
		_frame_times = _frame_times.slice(_frame_times.size() - Hud.FRAMES)
	var sim: Node = session.sim
	if _smoke_assignment != null and (not session.radio.connected or session.radio.device_id != _smoke_assignment.device_id):
		_end_smoke_assignment(true)
	_t += dt
	if _frametimes_scripted_fixed:
		_t = _frametimes_elapsed
	# Any pause (menu, focus, failsafe, calibration, crash) freezes the picture and the sound with the simulation:
	# the propeller stops where it is and the engine's generator stops being drained (stream_paused), so no stale
	# buzz at flying rpm plays on (UI-02, research 19).
	var frozen: bool = sim.paused and not _scripted
	if _frametimes_scripted_fixed:
		_prop_angle = fposmod(TAU * (sim.aux[0] / 60.0) * _frametimes_elapsed, TAU)
	elif not frozen:
		_prop_angle += TAU * (sim.aux[0] / 60.0) * dt
	if _engine_audio != null and _soundscape_audio == null:
		_engine_audio.stream_paused = frozen
		if not frozen:
			EngineSound.update(_engine_audio, 0.0, sim.aux[0], session.aircraft.model.propulsion.max_rpm)
	var surfaces: Dictionary = session.surfaces()
	InputPanel.update(_panel, session.raw, session.commands, _view_name(), _status(), surfaces, session.throws_deg())
	_camera_dt = dt
	_render_pose(_current_pose(), surfaces, _prop_angle)
	_update_smoke()
	if _crash_director != null:
		_crash_director.update(dt)
		if _crash_director.active and is_nan(_look.x):
			_crash_director.aim(_camera, _rig.view != "pilot") # chase and orbit keep the director's wreck view
		if _crash_director.active:
			_panel.text = _crash_director.description()
	_update_hud()
	if _overlays != null:
		if _overlays.tick(dt):
			_overlays.refresh_numbers(_overlay_snapshot())
		_overlays.refresh_sticks(OverlayManager.sticks(session) if not _scripted and _visual_pose.is_empty() else {})


func _update_cg_model() -> void:
	if session.aircraft.ok:
		var datum := AirplaneBuilder.datum(aircraft_id) # the data file's le frame in this aircraft's model
		_cg_model = Frames.cg_in_model_frame(session.aircraft.model.cg_le, datum.x, datum.y)


func _update_smoke() -> void:
	if _smoke == null or session == null:
		return
	var sim: Node = session.sim
	if sim.paused:
		return # all pause owners freeze smoke on the last presented interval
	var clock_s: float = sim.time()
	if not sim.paused and sim.tick > 0:
		clock_s = maxf(0.0, clock_s - sim.dt() + Engine.get_physics_interpolation_fraction() * sim.dt())
	var prop: Dictionary = session.aircraft.model.propulsion
	var request: float = session.radio.smoke_amount() if session.radio.connected else (1.0 if _smoke_key_on else 0.0)
	var wash := Vector3.ZERO
	if prop.has("slipstream"):
		var air: Dictionary = session.air_data(sim.state, clock_s)
		var rho: float = session.air_density()
		var output: PackedFloat64Array = Propulsion.thrust_torque(air.v_air, sim.aux[0], prop, rho)
		var flow: Dictionary = Slipstream.wake(air.v_air, output[0], output[1], prop, rho)
		var axis: PackedFloat64Array = Propulsion.axis(prop)
		wash = _airplane.root.global_basis * Vector3(-axis[1], axis[2], axis[0]) * maxf(flow.w, 0.0)
	_smoke.advance(clock_s, _airplane.root.global_transform, Propulsion.source_kind(prop), sim.aux[0],
		float(prop.get("idle_rpm", 0.0)), float(prop.get("max_rpm", 0.0)), sim.inputs[3], _render_wind(clock_s),
		request, session.crash.is_empty() and sim.fault_reason.is_empty(), _camera.global_position.distance_to(_airplane.root.global_position), wash)


func _begin_smoke_assignment() -> void:
	if _smoke == null or not session.radio.connected or session.calibration != null or _smoke_assignment != null:
		_note = tr("Connect a radio before assigning smoke AUX.")
		return
	_smoke_key_on = false
	_smoke_assignment_was_paused = session.sim.paused
	session.hold("smoke AUX assignment")
	var layer := CanvasLayer.new()
	layer.name = "SmokeAuxLayer"
	layer.layer = 20
	add_child(layer)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	_smoke_assignment = SmokeAssignment.new()
	center.add_child(_smoke_assignment)
	_smoke_assignment.profile_ready.connect(func(profile: Dictionary) -> void:
		var gamepad: bool = profile.get("kind", "") == "gamepad"
		session.radio.use_profile(profile, "gamepad" if gamepad else "calibrated")
		var saved: Error = session.RcCalibration.save_smoke_binding(session.profiles_path, session.radio.device_key, profile.aux.smoke) if gamepad \
			else session.RcCalibration.save_profile(session.profiles_path, session.radio.device_key, profile)
		_note = tr("Smoke AUX assigned. Move throttle and smoke control to OFF before resuming.") if saved == OK else tr("Smoke AUX assigned for this flight; profile could not be saved.")
		_end_smoke_assignment(false))
	_smoke_assignment.cancelled.connect(func() -> void: _end_smoke_assignment(true))
	_smoke_assignment.begin(session.radio.device_id, session.radio.profile, session.radio.device_key, session.profiles_path, session.radio.axes)


func _on_smoke_connection_changed(_device: int, _connected: bool) -> void:
	_smoke_key_on = false
	if _smoke != null:
		_smoke.levels.pump = 0.0
		_smoke.pump.emitting = false


func _end_smoke_assignment(cancelled: bool) -> void:
	var layer := get_node_or_null("SmokeAuxLayer")
	_smoke_assignment = null
	if layer != null:
		layer.queue_free()
	session.release("smoke AUX assignment")
	if cancelled and not _smoke_assignment_was_paused:
		session.resume()


func _update_hud() -> void:
	if _crash_director != null and _crash_director.active:
		_hud.text = ""
		return
	var lines := PackedStringArray()
	if _scripted or not session.aircraft.ok:
		lines.append("synthetic inspection" if not _visual_pose.is_empty() else ("scripted circle" if _scripted else "no flight data"))
	else:
		var s: PackedFloat64Array = session.sim.state
		var air: Dictionary = session.air_data(s)
		lines.append(Hud.flight_line(air.V, -s[RB.POS + 2], rad_to_deg(air.alpha), session.sim.inputs[3]))
		if not session.weather_is_calm():
			var wind: PackedFloat64Array = session.wind_at(session.sim.time())
			lines.append(_weather_hud_line(s, wind))
	if not _scripted and session.aircraft.ok and not session.atmosphere_is_reference():
		var field_air: Dictionary = session.atmosphere_configuration()
		var true_speed: float = session.air_data(session.sim.state).V
		lines.append(tr("EAS %.1f m/s  air %.3f kg/m³  density altitude %.0f m") % [true_speed * M.sqrt_(field_air.sigma), field_air.rho_kgm3, field_air.density_altitude_m])
	if _overlays != null:
		_overlays.performance_label.text = Hud.perf_line(_frame_times, session.sim.step_usec).trim_suffix("  [F3]")
	elif _show_perf:
		lines.append(Hud.perf_line(_frame_times, session.sim.step_usec))
	if not _experimental_aircraft_path.is_empty():
		lines.append("EXPERIMENTAL: wing polar; aircraft-specific flight validation pending.")
	_hud.text = "\n".join(lines)


## Ground speed is horizontal NED speed. A vertical-only air current has no compass bearing.
func _weather_hud_line(s: PackedFloat64Array, wind: PackedFloat64Array) -> String:
	var horizontal: float = M.sqrt_(wind[0] * wind[0] + wind[1] * wind[1])
	var bearing: String = "--"
	if horizontal > 0.0:
		bearing = "%03.0f°" % fposmod(rad_to_deg(M.atan2_(-wind[1], -wind[0])), 360.0)
	var q: PackedFloat64Array = M.quat(s[RB.ATT], s[RB.ATT + 1], s[RB.ATT + 2], s[RB.ATT + 3])
	var velocity: PackedFloat64Array = M.q_rotate(q, M.v3(s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]))
	var ground_speed: float = M.sqrt_(velocity[0] * velocity[0] + velocity[1] * velocity[1])
	return tr("ground speed %.1f m/s  wind %.1f m/s from %s  up %+.1f m/s") % [ground_speed, horizontal, bearing, -wind[2]]


func _status() -> String:
	if not _visual_pose.is_empty():
		return "mode: synthetic inspection (not flight)"
	if _scripted:
		return "mode: scripted circle"
	if not session.aircraft.ok:
		return "AIRCRAFT DATA INVALID: %s" % session.aircraft.errors[0]
	var sim: Node = session.sim
	var s: PackedFloat64Array = sim.state
	var trims: Dictionary = session.trims
	var speed := sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)
	var line := "sim %5.2f s  alt %5.1f m  speed %5.1f m/s  engine %5.0f rpm" % [sim.time(), -s[RB.POS + 2], speed, sim.aux[0]]
	if session.rates_active():
		line += "  rates: normal"
	if not _electric_demo.is_empty():
		line = "Synthetic electric test airframe (%s)\n" % _electric_demo.to_upper() + line
		if session.battery_is_dynamic():
			var battery: Dictionary = session.electrical_state()
			if battery.get("ok", false):
				line = "Battery %.1f%% | %.2f V | %.1f A%s\n" % [100.0 * battery.soc, battery.bus_voltage_v, battery.pack_current_a, " | depleted" if battery.exhausted else ""] + line
	line += "\ntrims: ail %+.3f  elev %+.3f  rud %+.3f" % [trims.roll, trims.pitch, trims.yaw]
	line += "\n" + session.radio.describe()
	if _smoke != null:
		line += "\n" + tr("[H] smoke pump %s  [J] assign radio AUX") % ("on" if _smoke.levels.pump > 0.0 else "off")
	if session.calibration != null:
		line += "\nCALIBRATION %s  [Esc] cancel" % session.calibration.prompt()
		if session.calibration.error != "":
			line += "\n  " + session.calibration.error
		line += "\n  axes " + " ".join(Array(session.radio.axes).map(func(v): return "%+.2f" % v))
	if _crash_director != null and _crash_director.active:
		line += "\n" + _crash_director.description()
	elif sim.paused:
		line += "\nPAUSED%s  [P] resume" % ("" if session.pause_reason == "" else " (%s)" % session.pause_reason)
	if recorder.recording:
		line += "\nREC %.1f s  [T] stop and save" % recorder.seconds()
	elif recorder.note != "":
		line += "\n" + recorder.note
	else:
		line += "\n[T] record trace"
	line += "\n[Z] auto-zoom %s  [V] shadow: %s  [F5] reload aircraft data" % ["on" if _rig.auto_zoom else "off", _shadow_mode]
	if _note != "":
		line += "\n" + _note
	return line


## Pose to draw: { pos: Vector3, basis: Basis } in render axes.
func _current_pose() -> Dictionary:
	if not _visual_pose.is_empty():
		return _visual_pose
	if _scripted:
		var p := Scripted.pose_at(_t)
		return { pos = Frames.ned_to_render(p.ned), basis = Frames.attitude_to_render(p.yaw, p.pitch, p.roll) }
	# CR-01c: presentation reads the estimate; the observed tick state stays authoritative.
	if not session.crash.is_empty():
		var impact: ImpactSnapshot.Snapshot = session.crash.get("impact") as ImpactSnapshot.Snapshot
		if impact != null:
			if impact.crossing != null and impact.crossing.available:
				var position: PackedFloat64Array = impact.crossing.position_ned
				return { pos = Frames.ned_to_render([position[0], position[1], position[2]]),
					basis = Frames.quat_to_render(impact.crossing.attitude) }
			return _pose_of(impact.detected_state)
		return _pose_of(session.sim.state)
	return _pose_of(session.sim.interpolated(Engine.get_physics_interpolation_fraction()))


func _pose_of(s: PackedFloat64Array) -> Dictionary:
	return { pos = Frames.ned_to_render([s[RB.POS], s[RB.POS + 1], s[RB.POS + 2]]), basis = Frames.quat_to_render(s.slice(RB.ATT, RB.ATT + 4)) }


func _unhandled_input(event: InputEvent) -> void:
	if _smoke_assignment != null:
		return
	if event.is_action_pressed("smoke_pump") and not event.is_echo() and _smoke != null and not session.sim.paused and not session.radio.connected:
		_smoke_key_on = not _smoke_key_on
		get_viewport().set_input_as_handled()
		return
	if _camera_input(event):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_PAGEUP, KEY_PAGEDOWN:
				if session.adjust_elevator_trim(-0.1 if event.physical_keycode == KEY_PAGEUP else 0.1):
					_note = tr("Elevator trim: %+.1f° (PgUp down / PgDn up)") % (session.trims.pitch * session.throws_deg().elevator)
					get_viewport().set_input_as_handled()
			KEY_J:
				_begin_smoke_assignment()
			KEY_R:
				session.reset()
			KEY_P:
				session.resume()
			KEY_T:
				if recorder.recording:
					recorder.stop()
				elif not _scripted:
					recorder.start(_trace_meta())
			KEY_C:
				_rig.cycle(-1 if event.shift_pressed else 1)
			KEY_1:
				_rig.set_view("pilot")
			KEY_2:
				_rig.set_view("chase")
			KEY_5:
				_rig.set_view("orbit")
			KEY_EQUAL:
				_rig.zoom(1.0)
			KEY_MINUS:
				_rig.zoom(-1.0)
			KEY_BACKSPACE:
				_rig.reset_view()
			KEY_K:
				session.start_calibration()
			KEY_ENTER, KEY_KP_ENTER:
				session.advance_calibration()
			KEY_ESCAPE:
				if session.calibration != null:
					session.cancel_calibration() # Esc leaves the wizard first; the pause menu comes on the next press
				else:
					pause_requested.emit()
			KEY_Z:
				_rig.toggle_auto_zoom()
			KEY_V:
				_shadow_mode = SHADOW_MODES[(SHADOW_MODES.find(_shadow_mode) + 1) % SHADOW_MODES.size()]
			KEY_F3:
				if _overlays != null:
					_overlays.toggle_developer()
				else:
					_show_perf = not _show_perf
			KEY_F2:
				if _overlays != null:
					_overlays.cycle_preset()
			KEY_F5:
				_note = session.reload() if _experimental_aircraft_path.is_empty() else "Experimental polar is fixed for this flight; restart the application to load another file."
				_update_cg_model()
				print(_note)


## CAM-04: mouse wheel zooms the current view; a right-button drag turns the orbit view. True when used.
func _camera_input(event: InputEvent) -> bool:
	if _rig == null:
		return false
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var notches: float = event.factor if event.factor > 0.0 else 1.0
		_rig.zoom(notches if event.button_index == MOUSE_BUTTON_WHEEL_UP else -notches)
		get_viewport().set_input_as_handled()
		return true
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
		_rig.drag(event.relative)
		get_viewport().set_input_as_handled()
		return true
	return false


## Terrain height (render y) under a render-space point, from the session's own ground table; NAN when unknown.
func _ground_height(x: float, z: float) -> float:
	if session == null:
		return 0.0
	return GroundTerrain.sample(-z, x, session.ground_surfaces)[0]


## What the flight overlays show this frame; {} when there is no physics flight to describe.
func _overlay_snapshot() -> Dictionary:
	if _scripted or not _visual_pose.is_empty() or session == null:
		return {}
	var forward: Vector3 = -_camera.global_transform.basis.z
	var view_heading: float = OverlayManager.Telemetry.heading_of_render_forward(forward.x, forward.z)
	return OverlayManager.snapshot(session, field.pilot, _extent.x, not _experimental_aircraft_path.is_empty(), view_heading)


## Shows or hides the flight's text overlays (input panel and HUD). A menu hides them: the paused picture then
## shows the airplane alone, and the panel's "[P] resume" never contradicts the menu.
func set_overlays_visible(on: bool) -> void:
	for label in [_panel, _hud]:
		var n: Node = label
		while n != null and not n is CanvasLayer:
			n = n.get_parent()
		if n != null:
			n.visible = on
	var latency_marker := get_node_or_null("LatencyPatch") as CanvasLayer
	if latency_marker != null:
		latency_marker.visible = on


## TOD-08a: paired technical replay checkpoint; native Variant encoding preserves physics bits.
## This is not a live-input save game or a rendered trace player.
func checkpoint() -> Dictionary:
	if session == null or _scripted or _capturing or _field_world_lighting or _capture_scene_id() != "field":
		return {}
	var selection: Dictionary = VisualTimeline.evaluate(_visual_timeline, session.sim.tick)
	if not selection.ok or selection.config != lighting_config:
		return {} # refuse an unrecorded visual edit
	var saved: Dictionary = VisualCheckpoint.make(session.checkpoint(), _visual_timeline, _field_identity())
	return saved.checkpoint if saved.ok else {}


## Validate both halves and prepare detached shadow geometry before the physics owner commits.
## No await: an invalid record cannot change the live world, recording or simulation.
func restore_checkpoint(candidate: Variant) -> Dictionary:
	if session == null or _scripted or _capturing or _field_world_lighting or _capture_scene_id() != "field" or not startup_error.is_empty():
		return {ok = false, errors = ["visual checkpoint requires a ready production flight"]}
	var decoded: Dictionary = VisualCheckpoint.read(candidate, _field_identity())
	if not decoded.ok:
		return decoded
	# TOD-09c1 defines progressing records before the live controller consumes them.
	# Refuse even a stopped v2 history: its restart selection and fractional phase
	# cannot be represented by this controller's fixed-time reset path yet.
	if decoded.timeline.format != VisualTimeline.FORMAT:
		return {ok = false, errors = ["progressing visual checkpoints require the solar progression controller"]}
	var staged: Dictionary = _prepare_checkpoint_lighting(decoded.config)
	if not staged.ok:
		return {ok = false, errors = ["could not prepare checkpoint lighting"]}
	if not session.restore_checkpoint(decoded.physics):
		return {ok = false, errors = ["physics checkpoint is invalid or incompatible"]}
	if not _commit_lighting(staged, decoded.config):
		return {ok = false, physics_restored = true, errors = ["physics restored, but visual scene changed during restoration"]}
	_visual_timeline = decoded.timeline.duplicate(true)
	_smoke_key_on = false
	if _smoke != null:
		_smoke.reset() # a physical checkpoint carries no particle history
	if _scenery_damage_director != null:
		_scenery_damage_director.sync(true)
	_visual_context_status = decoded.context_status
	_prop_angle = 0.0 # propeller phase was never part of the physical checkpoint contract
	if _engine_audio != null:
		_engine_audio.stream_paused = true
	_render_pose(_current_pose(), session.surfaces(), _prop_angle)
	_note = "Checkpoint restored; visual context: " + _visual_context_status
	return {ok = true, context_status = _visual_context_status, errors = []}


## Apply a visual-only edit while paused. Never restore physical state or change live input ownership.
func apply_lighting_config(raw: Variant) -> Dictionary:
	if session == null or _scripted or _capturing or _field_world_lighting or _capture_scene_id() != "field" or not startup_error.is_empty():
		return {ok = false, changed = false, errors = ["lighting edit requires a ready production flight"]}
	if not session.sim.paused:
		return {ok = false, changed = false, errors = ["pause the flight before editing lighting"]}
	var checked: Dictionary = LightingConfig.validate(raw)
	if not checked.ok:
		return {ok = false, changed = false, errors = checked.errors}
	if checked.config == lighting_config:
		return {ok = true, changed = false, errors = []}
	var edited: Dictionary = VisualTimeline.append_config_edit(_visual_timeline, session.sim.tick, checked.config)
	if not edited.ok:
		return {ok = false, changed = false, errors = edited.errors}
	var staged: Dictionary = _prepare_checkpoint_lighting(checked.config)
	if not staged.ok:
		return {ok = false, changed = false, errors = ["could not prepare lighting"]}
	# Prepare the prior context without publishing it until the scene update succeeds.
	var initial_context: String = JSON.stringify(TimeOfDayLighting.context(lighting_config, _lighting), "", true, true)
	if not _commit_lighting(staged, checked.config):
		return {ok = false, changed = false, errors = ["visual scene changed during lighting edit"]}
	if recorder.recording and not recorder.trace.meta.has("visual_context"):
		recorder.trace.meta.visual_context = initial_context
	_visual_timeline = edited.timeline
	if recorder.recording:
		recorder.trace.meta.visual_timeline = JSON.stringify(_visual_timeline, "", true, true)
	_render_pose(_current_pose(), session.surfaces(), _prop_angle)
	return {ok = true, changed = true, errors = []}


## TOD-09b: publish in place; no await or physical-session mutation here.
func _commit_lighting(staged: Dictionary, config: Dictionary) -> bool:
	var updated: bool = FieldBuilder.commit_lighting(_field_node, staged.field)
	if staged.field.changed and not updated:
		return false
	Atmosphere.update_environment(_env, staged.lighting)
	Atmosphere.update_sun(_sun, staged.lighting)
	lighting_config = config.duplicate(true)
	_lighting = staged.lighting
	var current_time: float = session.sim.time()
	ShaderClock.update(current_time, _render_wind(current_time))
	Atmosphere.update_clouds(_env, current_time)
	return true


func _field_identity() -> String:
	var hashing: HashingContext = HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(field))
	return hashing.finish().hex_encode()


## Prepare the only replaceable geometry before publishing; the field, Sun and Environment retain ownership.
func _prepare_checkpoint_lighting(config: Dictionary) -> Dictionary:
	var snapshot: Dictionary = TimeOfDayLighting.snapshot(config)
	var prepared_field: Dictionary = FieldBuilder.prepare_lighting(_field_node, snapshot)
	return {ok = prepared_field.ok, field = prepared_field, lighting = snapshot}


## The session's trace header plus which build flew it (UI-04a): the exported smoke test compares app_build with
## the ZIP name. "development" when running from the source tree.
func _trace_meta() -> Dictionary:
	var meta: Dictionary = session.trace_meta()
	var build := BuildInfo.current()
	meta.app_build = build.describe if build.source == "export" else "development"
	meta.app_version = build.parsed.semver if build.source == "export" else build.version + " (development)"
	if _visual_context_status != "present":
		meta.visual_context_status = _visual_context_status
	if _visual_context_status != "present" or not _visual_timeline.events.is_empty():
		meta.visual_timeline = JSON.stringify(_visual_timeline, "", true, true)
	if lighting_config.get("mode", "legacy") != "legacy" or _visual_context_status != "present" or not _visual_timeline.events.is_empty():
		# Self-contained optional header, copied/frozen by Recorder; CSV columns and physics identity stay unchanged.
		meta.visual_context = JSON.stringify(TimeOfDayLighting.context(lighting_config, _lighting), "", true, true)
	return meta


## One file never mixes two flights.
func _on_resetting() -> void:
	_smoke_key_on = false
	if _smoke != null:
		_smoke.reset()
	_visual_timeline = VisualTimeline.create(lighting_config).timeline
	_visual_context_status = "present"
	_t = 0.0
	if _rig != null:
		_rig.reset()
	if recorder.recording:
		recorder.stop()
	if _engine_audio != null and _soundscape_audio == null and _engine_audio.playing:
		# A new flight: discard the prior flight's audio queue and oscillator state.
		EngineSound.restart(_engine_audio)


## Arguments after `--`: --capture, --inspect, --scripted, --t=3.0, --roll=1, --out=/path.png, --trace=/path.csv,
## --alt=4 (start altitude, m), --autozoom=0, --view=pilot|chase|orbit|closeup (CAM-04), --look_az=90 --look_el=10 --look_alt=30 (fixed landscape review view),
## --hide_airplane (readability reference), --hide_treeline (L6c tree-mask reference; refused without field objects),
## --visual_pose=level --visual_distance=100 [--visual_elevation=1.6 --visual_azimuth=0] (synthetic inspection,
## with --scripted and an explicit --autozoom), --frametimes=<file.json>, --shadow=sun|vertical|off, --engine_shadows,
## --aircraft=<catalog id> (default the Ugly Stik; a preview aircraft only with --scripted),
## --rates=normal|full (D6e: the aircraft's normal-flight rates and expo on the keyboard/gamepad sticks, or the maximum throws),
## --experimental-aircraft-data=<absolute JSON path> (research-only Ugly Stik wing-polar candidate)
func _user_args() -> Dictionary:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	return args


func _validate_experimental_aircraft_data(path: Variant, selected_aircraft_id: String, scripted: bool, electric_demo: bool) -> Dictionary:
	if typeof(path) != TYPE_STRING or str(path).is_empty():
		return {ok = false, error = "--experimental-aircraft-data needs an absolute JSON file path"}
	var candidate_path: String = str(path)
	if not candidate_path.is_absolute_path() or candidate_path.get_extension().to_lower() != "json":
		return {ok = false, error = "--experimental-aircraft-data needs an absolute JSON file path"}
	if not FileAccess.file_exists(candidate_path):
		return {ok = false, error = "candidate file does not exist: %s" % candidate_path}
	if selected_aircraft_id != Catalog.DEFAULT_ID or scripted or electric_demo:
		return {ok = false, error = "candidate route requires a physics flight of the catalog default Ugly Stik only"}
	var candidate_parser := JSON.new()
	var candidate_bytes := FileAccess.get_file_as_bytes(candidate_path)
	if candidate_parser.parse(candidate_bytes.get_string_from_utf8()) != OK or typeof(candidate_parser.data) != TYPE_DICTIONARY:
		return {ok = false, error = "candidate must be a JSON object: %s" % candidate_path}
	var candidate: Dictionary = candidate_parser.data
	if typeof(candidate.get("id")) != TYPE_STRING or candidate.get("id") != Catalog.DEFAULT_ID:
		return {ok = false, error = "candidate id must match the catalog default Ugly Stik"}
	if typeof(candidate.get("aero")) != TYPE_DICTIONARY or typeof(candidate.aero.get("wing_polar")) != TYPE_DICTIONARY:
		return {ok = false, error = "candidate must contain aero.wing_polar as an object"}
	var reference_path: String = str(Catalog.entry(Catalog.DEFAULT_ID).get("data", ""))
	var reference_parser := JSON.new()
	if reference_path.is_empty() or reference_parser.parse(FileAccess.get_file_as_string(reference_path)) != OK or typeof(reference_parser.data) != TYPE_DICTIONARY:
		return {ok = false, error = "catalog default aircraft reference data is unavailable"}
	var candidate_reference: Dictionary = candidate.duplicate(true)
	var catalog_reference: Dictionary = reference_parser.data.duplicate(true)
	candidate_reference["aero"].erase("wing_polar")
	catalog_reference["aero"].erase("wing_polar")
	if candidate_reference != catalog_reference:
		return {ok = false, error = "candidate may change only aero.wing_polar from catalog default data; reference geometry and other data must match"}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(candidate_bytes)
	return {ok = true, path = candidate_path, input_sha256 = digest.finish().hex_encode()}


func _view_name() -> String:
	if not _visual_pose.is_empty():
		return "fixed inspection"
	return _rig.view_name()


func _build_world() -> void:
	var snapshot: Dictionary = _lighting if lighting_config.get("mode", "legacy") != "legacy" else {}
	var built: Dictionary = World.build(self, field, _build_field, {}, snapshot)
	_field_world_lighting = bool(built.conditions.time_of_day)
	_env = built.environment
	_world_environment = built.world_environment
	_sun = built.sun

	_airplane = AirplaneBuilder.build(aircraft_id)
	add_child(_airplane.root)
	_extent = Shadow.model_extent(_airplane.root)
	_shadow = Shadow.create(self)
	Shadow.bind_model(_shadow, _airplane.root)
	World.dress_aircraft(_airplane.root) # FW-35: night kit from dusk, after the extent is measured
	_camera = PilotCamera.create(self, field.pilot)
	_rig = CameraRig.new(_camera, _extent.x)
	if overlays_enabled:
		_overlays = OverlayManager.new(overlay_settings, TranslationServer.get_locale().substr(0, 2))
		_overlays.settings_changed.connect(func(settings: Dictionary) -> void: overlay_settings_changed.emit(settings))
		add_child(_overlays)
		_panel = _overlays.diagnostics_panel
		_hud = _overlays.diagnostics_hud
	else:
		_panel = InputPanel.create(self)
		_hud = Hud.create(self)


## Production field seam. The atmosphere fixture overrides only these ground meshes.
func _build_field() -> void:
	_field_node = FieldBuilder.build(field, _lighting if lighting_config.get("mode", "legacy") != "legacy" else {})
	add_child(_field_node)


## Hides every field object (today: the treeline) for a background-only capture. False when there is none.
func _hide_field_objects() -> bool:
	var hidden := false
	for object_data: Dictionary in field.get("objects", []):
		var node: Node3D = get_node_or_null(NodePath("Field/%s" % str(object_data.id))) as Node3D
		if node != null:
			node.visible = false
			hidden = true
	_treeline_hidden = hidden
	return hidden


func _capture_scene_id() -> String:
	return "field"


func _render_pose(pose: Dictionary, c: Dictionary, prop_angle: float) -> void:
	_last_render_pose = pose
	_airplane.root.transform = Frames.root_transform(pose.basis, pose.pos, _cg_model)
	_airplane.propeller.rotation.z = prop_angle
	AirplaneBuilder.apply_surfaces(_airplane, Commands.hinge_rotations(c, session.throws_deg()))
	var snapshot_lighting: bool = lighting_config.get("mode", "legacy") != "legacy"
	var strength: float = Atmosphere.shadow_strength(_lighting) if snapshot_lighting and _shadow_mode == "sun" else 1.0
	_shadow.visible = _shadow_mode != "off" and _airplane.root.visible and strength > 0.0
	var direction: Vector3 = Atmosphere.sun_direction(_lighting) if snapshot_lighting else Atmosphere.shadow_direction()
	Shadow.update(_shadow, pose.basis, pose.pos, _extent.x, _extent.y, direction if _shadow_mode == "sun" else Vector3.UP, strength)
	var paused: bool = session != null and session.sim.paused and not _scripted
	_rig.update(pose.pos, _airplane.root.transform, pose.basis, _camera_dt, paused, _ground_height)


func _write_trace_and_quit(ticks: int, path: String) -> void:
	session.input_enabled = false
	session.sim.process_mode = Node.PROCESS_MODE_DISABLED
	if not session.is_flyable() or session.sim.tick != 0:
		push_error("--trace refused: flight did not start in a valid state at tick zero")
		get_tree().quit(1)
		return
	recorder.start(_trace_meta())
	for i in ticks:
		session.sim.step()
		if not session.sim.fault_reason.is_empty() or session.sim.tick != i + 1:
			recorder.recording = false
			push_error("--trace aborted at tick %d: %s" % [session.sim.tick, session.sim.fault_reason])
			get_tree().quit(1)
			return
	if recorder.trace.row_count() != ticks + 1:
		recorder.recording = false
		push_error("--trace aborted: recorder did not receive every tick")
		get_tree().quit(1)
		return
	get_tree().quit(recorder.stop(path))


func _capture(t: float, c: Dictionary, out: String) -> void:
	var sim: Node = session.sim
	if _scripted:
		_t = t
	else:
		# Step the simulation synchronously to time t, then freeze it for the capture.
		for i in roundi(t / sim.dt()):
			sim.step()
		sim.set_paused(true)
		c = session.commands # physics captures show the real commands, not capture arguments
	# Surfaces as flown: physics captures draw the servos' actual positions (trims included), like live rendering.
	var surfaces: Dictionary = c if _scripted else session.surfaces()
	InputPanel.update(_panel, Commands.neutral_raw(), c, _view_name(), _status(), surfaces, session.throws_deg())
	var pose := _current_pose() if _scripted else _pose_of(sim.state)
	_render_pose(pose, surfaces, TAU * Commands.prop_rev_per_sec(c) * t)
	var clock_s: float = t if _scripted else sim.time()
	World.update(_env, clock_s, _render_wind(clock_s), pose.pos, _camera)
	_update_hud()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out).get_base_dir())
	var err := get_viewport().get_texture().get_image().save_png(out)
	# Render counters of the captured frame (L0): deterministic for a fixed view, so landscape budgets are testable.
	var manifest_err := _write_manifest(out, err)
	var sun_px := _camera.unproject_position(_camera.global_position + Atmosphere.disc_direction(_lighting) * 1000.0)
	var sun_visible: bool = Atmosphere.light_energy(_lighting) > 0.0 and not _camera.is_position_behind(_camera.global_position + Atmosphere.disc_direction(_lighting) * 1000.0)
	# L3: where the sun shadow of the airplane's CG falls on the ground (along the light, onto y = 0), on screen.
	var cg: Vector3 = pose.pos
	var sd := Atmosphere.sun_direction(_lighting)
	var shadow_available: bool = sd.y > 0.00001 and Atmosphere.shadow_strength(_lighting) > 0.0
	# Match the visible footprint's low-angle bound instead of logging an unbounded physical projection.
	var projection_direction: Vector3 = sd
	projection_direction.y = maxf(projection_direction.y, 0.05)
	var shadow_point: Vector3 = cg - projection_direction * (cg.y / projection_direction.y) if shadow_available else Vector3(cg.x, 0.0, cg.z)
	var shadow_px := _camera.unproject_position(shadow_point)
	var shadow_seen: bool = shadow_available and not _camera.is_position_behind(shadow_point)
	var below_px := _camera.unproject_position(Vector3(cg.x, 0.0, cg.z)) # straight below: where a vertical shadow would be
	print("saved %s (error %d) draw_calls=%d primitives=%d sun_px=%s sim_clock=%s shadow_px=%s below_px=%s" % [out, err,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		("%.1f,%.1f" % [sun_px.x, sun_px.y]) if sun_visible else "behind", str(ShaderClock.last_clock),
		("%.1f,%.1f" % [shadow_px.x, shadow_px.y]) if shadow_seen else "behind", "%.1f,%.1f" % [below_px.x, below_px.y]])
	get_tree().quit(err if err != OK else manifest_err)


## L0b determinism manifest next to each capture (<name>.json): image hash, per-pass render counters, renderer,
## Mesa and Godot versions, llvmpipe thread count. Two fixed runs must give identical manifests; sky-only views can have zero visible mesh counters.
func _write_manifest(png_path: String, err: Error) -> Error:
	var vp := get_viewport().get_viewport_rid()
	var info := func(type: int, what: int) -> int: return RenderingServer.viewport_get_render_info(vp, type, what)
	var visible := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	var shadow := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW
	var m := {
		format = "openrc-capture v1",
		visual_evidence = capture_evidence(),
		capture_scene = _capture_scene_id(),
		renderer = RenderingServer.get_current_rendering_method(),
		image = png_path.get_file(),
		sha256 = FileAccess.get_sha256(png_path) if err == OK else "",
		draw_calls = { visible = info.call(visible, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME), shadow = info.call(shadow, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME) },
		primitives = { visible = info.call(visible, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME), shadow = info.call(shadow, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME) },
		objects = { visible = info.call(visible, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME), shadow = info.call(shadow, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME) },
		video_memory_bytes = int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		adapter = RenderingServer.get_video_adapter_name(),
		api = RenderingServer.get_video_adapter_api_version(),
		godot = Engine.get_version_info().string,
		lp_num_threads = OS.get_environment("LP_NUM_THREADS"),
		args = " ".join(OS.get_cmdline_user_args()).replace(png_path, png_path.get_file()),
	}
	var f := FileAccess.open(png_path.get_basename() + ".json", FileAccess.WRITE)
	if f == null:
		var open_error := FileAccess.get_open_error()
		push_error("Cannot write capture manifest: %s" % error_string(open_error))
		return open_error
	f.store_string(JSON.stringify(m, "  ", true) + "\n")
	f.flush()
	var write_error := f.get_error()
	f.close()
	if write_error != OK:
		push_error("Cannot save capture manifest: %s" % error_string(write_error))
	return write_error


## VQ-01b: records raw monotonic frame intervals after warm-up. Legacy summary fields use wall-clock deltas;
## engine `delta` stays available in engine_* fields. Use --warmup=<seconds> (default 1) and --t=<seconds> (20).
func _log_frame_time(delta: float) -> void:
	var now_usec: int = Time.get_ticks_usec()
	var wall_delta_usec: int = now_usec - _frametimes_last_usec
	_frametimes_last_usec = now_usec
	var sim: Node = session.sim
	var raw_metrics: Dictionary = {
		sim_time_s = sim.time(),
		sim_tick = sim.tick,
		physics_step_usec = sim.step_usec,
		fps_monitor = Performance.get_monitor(Performance.TIME_FPS),
		process_time_s = Performance.get_monitor(Performance.TIME_PROCESS),
		physics_process_time_s = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
		object_count = Performance.get_monitor(Performance.OBJECT_COUNT),
		node_count = Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		draw_calls = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		primitives = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		physics_3d_active_objects = Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		physics_3d_collision_pairs = Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
	}
	if not _frametime_samples.record_frame(delta, wall_delta_usec, now_usec, raw_metrics):
		_frametimes_active = false
		push_error("Frame-time measurement failed: " + _frametime_samples.failure)
		get_tree().quit(1)
		return
	_frametimes_elapsed = float(_frametime_samples.elapsed_wall_usec) / 1000000.0
	if not _frametime_samples.finished:
		return
	var report: Dictionary = _frametime_samples.report()
	var sim_end_s: float = sim.time()
	var sim_end_tick: int = sim.tick
	var sample_metrics: Dictionary = report.raw_metrics
	var sample_times: PackedFloat64Array = sample_metrics.get("sim_time_s", PackedFloat64Array())
	var sample_ticks: PackedFloat64Array = sample_metrics.get("sim_tick", PackedFloat64Array())
	var sample_simulation: Dictionary = {
		scope = "first sampled frame end through last sampled frame end; excludes the first sampled interval",
		start_time_s = sample_times[0] if not sample_times.is_empty() else sim_end_s,
		end_time_s = sample_times[sample_times.size() - 1] if not sample_times.is_empty() else sim_end_s,
		start_tick = int(sample_ticks[0]) if not sample_ticks.is_empty() else sim_end_tick,
		end_tick = int(sample_ticks[sample_ticks.size() - 1]) if not sample_ticks.is_empty() else sim_end_tick,
		ticks = int(sample_ticks[sample_ticks.size() - 1] - sample_ticks[0]) if sample_ticks.size() > 1 else 0,
	}
	var run_args: Dictionary = _user_args()
	var route_name: String = "scripted-fixed" if _frametimes_scripted_fixed else "live-input"
	report.merge({
		case_id = str(run_args.get("case", route_name)),
		route = route_name,
		preset = "current-default",
		backend = RenderingServer.get_current_rendering_method(),
		render_settings = {msaa_3d = get_viewport().msaa_3d, screen_space_aa = get_viewport().screen_space_aa, scaling_3d_scale = get_viewport().scaling_3d_scale},
		camera = {
			fov_deg = _camera.fov,
			autozoom = _rig.auto_zoom,
			near_m = _camera.near,
			far_m = _camera.far,
			mode = _view_name(),
			projection = _camera.projection,
			keep_aspect = _camera.keep_aspect,
			viewport = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
			transform = VisualEvidence.transform(_camera.global_transform),
		},
		physics_us_per_tick = sim.step_usec,
		adapter = RenderingServer.get_video_adapter_name(),
		api = RenderingServer.get_video_adapter_api_version(),
		godot = Engine.get_version_info().string,
		os = OS.get_name(),
		pid = OS.get_process_id(),
		window = "%dx%d" % [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y],
		vsync = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED,
		aircraft_id = aircraft_id,
		input_enabled = session.input_enabled,
		simulation = {
			scope = "first _process clock prime through sample completion; includes warm-up",
			start_time_s = _frametimes_sim_start_s,
			end_time_s = sim_end_s,
			elapsed_time_s = sim_end_s - _frametimes_sim_start_s,
			start_tick = _frametimes_sim_start_tick,
			end_tick = sim_end_tick,
			ticks = sim_end_tick - _frametimes_sim_start_tick,
			physics_ticks_per_second = Engine.physics_ticks_per_second,
			physics_enabled = session.physics_enabled,
			paused = sim.paused,
			fault = sim.fault_reason,
			step_usec_smoothed = sim.step_usec,
		},
		measured_simulation = sample_simulation,
		code_provenance = VisualEvidence.provenance(),
		note = "Frame intervals use monotonic Time.get_ticks_usec wall time; legacy seconds/fps_mean/frame_ms use that clock. Godot delta is recorded separately under engine_*. The first _process call primes the clock, excluding ready/startup. The scripted-fixed route disables input and advances its visual clock from elapsed wall time. preset=current-default reports current rendering settings; the app has no named performance presets. Software renderers such as llvmpipe are not target-hardware performance numbers.",
	}, true)
	var write_result: Dictionary = FrameSamples.write_json(_frametimes_path, report)
	_frametimes_active = false
	var frame_stats: Dictionary = report.frame_ms
	print("frame times: p50 %.2f ms, p95 %.2f ms, p99 %.2f ms over %d frames → %s" % [frame_stats.p50, frame_stats.p95, frame_stats.p99, report.frames, _frametimes_path])
	if not write_result.ok:
		push_error("Cannot write frame-time report '%s': %s" % [_frametimes_path, error_string(int(write_result.error))])
		get_tree().quit(1)
		return
	get_tree().quit(OK)


## Actual rendered state, not just the requested CLI flags. Shared with the UI transition fixture.
func capture_evidence() -> Dictionary:
	var args: Dictionary = _user_args()
	var pilot: Vector3 = Frames.ned_to_render([field.pilot.north, field.pilot.east, float(field.pilot.down) - float(field.pilot.eye_height)])
	var position: Vector3 = _last_render_pose.get("pos", Vector3.ZERO)
	var basis: Basis = _last_render_pose.get("basis", Basis.IDENTITY)
	return {
		format = "openrc-visual-evidence v1", lighting = TimeOfDayLighting.context(lighting_config, _lighting), provenance = VisualEvidence.provenance(),
		case_id = str(args.get("case", "unspecified")), aircraft = aircraft_id,
		field_data = {id = field.id, path = field_path, sha256 = FileAccess.get_sha256(field_path)},
		visual_pose = str(args.get("visual_pose", "")), visual_distance_m = float(args.get("visual_distance", 0.0)),
		visual_elevation_deg = float(args.get("visual_elevation", VisualEvidence.DEFAULT_ELEVATION_DEG)),
		visual_azimuth_deg = float(args.get("visual_azimuth", VisualEvidence.DEFAULT_AZIMUTH_DEG)),
		light = {direction = VisualEvidence.vector(Atmosphere.sun_direction(_lighting)), energy = Atmosphere.light_energy(_lighting), color = str(_lighting.sun_color)},
		route = "synthetic-inspection" if not _visual_pose.is_empty() else ("scripted-circle" if _scripted else "physics-fixed"),
		preset = "current-default", backend = RenderingServer.get_current_rendering_method(),
		pose = VisualEvidence.transform(Transform3D(basis, position)), coordinate_frame = "render: east/up/south; metres",
		distance_to_pilot_m = position.distance_to(pilot), distance_to_camera_m = position.distance_to(_camera.global_position),
		camera = {transform = VisualEvidence.transform(_camera.global_transform), fov_deg = _camera.fov,
			autozoom = _rig.auto_zoom, near_m = _camera.near, far_m = _camera.far, mode = _view_name(),
			projection = _camera.projection, keep_aspect = _camera.keep_aspect,
			viewport = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]},
		exposure = _env.tonemap_exposure, tonemapper = _env.tonemap_mode,
		render_settings = {msaa_3d = get_viewport().msaa_3d, screen_space_aa = get_viewport().screen_space_aa, scaling_3d_scale = get_viewport().scaling_3d_scale},
		clock_s = ShaderClock.last_clock, simulation_time_s = session.sim.time(), simulation_tick = session.sim.tick,
		state = {paused = session.sim.paused, aircraft_visible = _airplane.root.visible, treeline_visible = not _treeline_hidden, shadow = _shadow_mode,
			engine_shadows = Atmosphere.engine_shadows, physics_state = Array(session.sim.state),
			controls = session.commands, surfaces = session.surfaces(), propeller_angle_rad = _airplane.propeller.rotation.z},
		seed = {kind = "not-used", note = "procedural shaders use fixed analytic noise; no RNG"},
	}
