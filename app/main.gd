extends Node3D

## Set by the interactive shell before the session enters the tree.
var external_controller_selection := false
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
const ControlSurfaces := preload("res://physics/control_surfaces.gd")
const InputPanel := preload("res://render/panel.gd")
const FlightSession := preload("res://sim/flight_session.gd")
const FailureConfig := preload("res://failures/config.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const CrashDirector = preload("res://render/crash/director.gd")
const AccidentIncident = preload("res://economy/incident.gd")
const AccidentSettlement = preload("res://economy/settlement.gd")
const AccidentReport = preload("res://ui/accident_report.gd")
const SceneryDamageDirector = preload("res://render/crash/scenery_damage.gd")
const ImpactSnapshot = preload("res://physics/impact_snapshot.gd")
const Recorder := preload("res://sim/recorder.gd")
const FlightLog := preload("res://sim/flight_log.gd")
const RB := preload("res://physics/rigid_body.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Preferences := preload("res://app_state/preferences.gd")
const ScenarioConfig := preload("res://scenarios/scenario_config.gd")
const EngineSound := preload("res://render/engine_sound.gd")
const FlightAudio = preload("res://audio/flight_audio.gd")
const VisualTimeline = preload("res://environment/visual_timeline.gd")
const VisualCheckpoint = preload("res://app_state/visual_checkpoint.gd")
const LightingConfig = preload("res://environment/time_of_day_config.gd")
const TimeOfDayLighting = preload("res://render/time_of_day_lighting.gd")
const Atmosphere := preload("res://render/atmosphere.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const SkyCheckpoint := preload("res://app_state/sky_checkpoint.gd")
const Lightning := preload("res://render/weather/lightning.gd")
const ShaderClock := preload("res://render/shader_clock.gd")
const Shadow := preload("res://render/shadow.gd")
const Ground := preload("res://render/ground.gd") # legacy atmosphere fixture only
const FieldLoader = preload("res://data/field_loader.gd")
const FieldBuilder = preload("res://render/field.gd")
const LakeWorld = preload("res://render/lake/lake_world.gd")
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
const WATER_CHECKPOINT_FORMAT := "openrc-visual-water-checkpoint v1"
const WATER_CHECKPOINT_FIELDS: Array[String] = ["format", "visual", "water_render", "payload_sha256"]

## [Esc] outside the calibration wizard: the pilot asks for the pause menu (app_root owns menus; without one, nothing).
signal pause_requested
## The player changed the flight overlays (X, [F2], [F3]); Home saves them (docs/plans/flight-overlays.md).
signal overlay_settings_changed(settings: Dictionary)
signal scenario_changed(scenario: Dictionary)

## Data path is injectable before entering the tree; normal routes use the packaged default.
var field_path: String = FieldLoader.DEFAULT_PATH
var field: Dictionary = {}

var session: Node
var recorder: RefCounted
var flight_log: RefCounted
var _flight_log_label: Label
## The catalog aircraft to fly. Set before adding the node (Home does); otherwise --aircraft=<id>, else the Ugly Stik.
var aircraft_id := ""
## Detached Workshop compilation; aircraft_id remains the catalog visual identity.
var workshop_trial: Dictionary = {}
## NR: accepted resolved selection, outside the sealed physics/weather/checkpoint contracts.
var flight_scenario: Dictionary = {}
## Session origin survives checkpoint restore, which deliberately clears scenario provenance.
var remember_lighting_selection: bool = true
var _experimental_aircraft_path := ""
var _electric_demo: String = ""
## Interactive Home choice only; CLI and scripted routes retain the airborne default.
var start_choice: String = "airborne"
var weather_config: Dictionary = {}
## Resolved only when this flight is created. Session reset retains its draw and onset.
var failure_config: Dictionary = FailureConfig.defaults()
var failure_seed: int = -1
var failure_notifications: bool = true
var _failure_notice: CanvasLayer
var _failure_label: Label
var _failure_overlays_visible: bool = true
## TOD: immutable selection for this flight; no preference reads on the direct route.
var lighting_config: Dictionary = {}
var sky_config: Dictionary = SkyConfig.defaults()
var _sky_edits: Array = []
var _storm_fx: Node3D
## FW-71: visual-only field lighting and campfire choices; direct launches resolve these from CLI defaults/flags.
var night_options: Dictionary = Preferences.NIGHT_DEFAULTS.duplicate(true)
## AppRoot passes the same argument list it used to choose the direct route; standalone launches use the OS list.
var user_args: PackedStringArray = OS.get_cmdline_user_args()
var _lighting: Dictionary = {}
var _visual_timeline: Dictionary = {}
var _visual_context_status: String = "present"
var _field_world_lighting: bool = false
var _world_environment: WorldEnvironment
var _sun: DirectionalLight3D
var _field_node: Node3D


func _failure_options(options: Dictionary) -> Dictionary:
	var config: Dictionary = failure_config.duplicate(true)
	var seed_value: int = failure_seed
	if options.has("failures"):
		if typeof(options.failures) != TYPE_STRING or not str(options.failures).is_valid_int():
			return {ok = false, errors = ["--failures needs an integer from 0 to 100"]}
		config.probability_percent = str(options.failures).to_int()
	for key: String in ["catastrophic", "failure-notices"]:
		if options.has(key):
			if options[key] not in ["on", "off"]:
				return {ok = false, errors = ["--%s must be on or off" % key]}
			config["include_catastrophic" if key == "catastrophic" else "notify"] = options[key] == "on"
	if options.has("failure-seed"):
		if typeof(options["failure-seed"]) != TYPE_STRING or not str(options["failure-seed"]).is_valid_int():
			return {ok = false, errors = ["--failure-seed needs an integer from 0 to 4294967295"]}
		seed_value = str(options["failure-seed"]).to_int()
		if seed_value < 0:
			return {ok = false, errors = ["--failure-seed must be non-negative"]}
	var checked: Dictionary = FailureConfig.validate(config)
	if not checked.ok:
		return checked
	if seed_value < -1 or seed_value > 4294967295:
		return {ok = false, errors = ["Failure seed must fit an unsigned 32-bit integer"]}
	if seed_value == -1:
		# A local RNG never perturbs weather/scenery or the failure generator's resolved sequence.
		var random_source := RandomNumberGenerator.new()
		random_source.randomize()
		seed_value = random_source.randi() if checked.config.probability_percent > 0 else 0
	return {ok = true, config = checked.config, seed = seed_value, errors = []}


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
var _lake_ambience: AudioStreamPlayer3D
## Technical fixtures can retain the original diagnostic freeze route.
var crash_effects_enabled := true
## CR-30/32: independent from visual effects; technical fixtures can opt out.
var accident_reports_enabled := true
var accident_archive_path := "user://last_accident.json"
var _accident_incident: RefCounted
var _accident_report: CanvasLayer
var _accident_restored := false
var _accident_bindings: Dictionary = {}
var _accident_source_hash := ""
var _accident_archive_error := OK
var _accident_settlement: RefCounted
var _accident_settled_pending := false
var _accident_ground_stable := false
var _accident_reload_pending := false
var _accident_checkpoint_restoring := false
var _accident_paired_history := false
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
var _night_kit: Node3D # FW-35b: the aircraft's night lights (fitted at dusk, or by [L] at any hour)
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
var _wheel_brake_key_held := false
var _visual_pose: Dictionary = {}
var _smoke: EngineSmoke
var _smoke_key_on := false
var _smoke_assignment: SmokeAssignment
var _smoke_assignment_was_paused := false
var _last_render_pose: Dictionary = {}
var _treeline_hidden: bool = false # L6c background-only capture (--hide_treeline)


func _ready() -> void:
	var args := _user_args()
	var night_result: Dictionary = Preferences.validate_night_options(night_options) if interactive_start \
		else Preferences.night_options_from_args(args)
	if not night_result.get("ok", false):
		startup_error = "; ".join(night_result.errors)
		printerr("night lighting: " + startup_error)
		set_process(false)
		set_process_unhandled_input(false)
		get_tree().quit(ERR_INVALID_PARAMETER)
		return
	night_options = night_result.options.duplicate(true)
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
	var selected_sky: Dictionary = SkyConfig.validate(sky_config) if interactive_start else SkyConfig.from_args(args)
	if not selected_sky.ok:
		startup_error = "; ".join(selected_sky.errors)
		set_process(false)
		set_process_unhandled_input(false)
		if not interactive_start:
			printerr("sky: " + startup_error)
			get_tree().quit(ERR_INVALID_PARAMETER)
		return
	sky_config = selected_sky.config
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
	if not _build_world():
		set_process(false)
		set_process_unhandled_input(false)
		if not interactive_start:
			printerr(startup_error)
			get_tree().quit(ERR_INVALID_DATA)
		return
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
	session.external_controller_selection = external_controller_selection
	session.physics_enabled = not _scripted
	# This explicit airborne operating point must be selected before setup solves trim.
	# Runway selection still waits for field/contact configuration below.
	if start_choice == FlightSession.START_HALF_POWER:
		session.start_choice = start_choice
	if args.has("shaft-integrator") and (not session.setup_shaft_integrator(args["shaft-integrator"]) or _scripted):
		printerr("shaft integrator refused: ", session.shaft_error if not _scripted else "requires a physics flight")
		session.free() # refused before add_child(): this owner would otherwise remain orphaned
		session = null
		get_tree().quit(ERR_INVALID_PARAMETER)
		set_process(false)
		set_process_unhandled_input(false)
		return
	var physics_path: String = _experimental_aircraft_path if not _experimental_aircraft_path.is_empty() else (str(Catalog.entry(aircraft_id).data) if _electric_demo.is_empty() else "res://data/aircraft/synthetic_stik_electric_%s.json" % _electric_demo.replace("-", "_"))
	if workshop_trial.is_empty():
		session.setup(physics_path, aircraft_id if _electric_demo.is_empty() and _experimental_aircraft_path.is_empty() else "")
	else:
		session.workshop_identity = workshop_trial.identity.duplicate(true)
		session.setup("workshop://" + str(workshop_trial.identity.trial_id), str(workshop_trial.data.model.id), workshop_trial.data)
	# Glow visuals use the exact propeller selected by the validated runtime model. Applying from the base geometry
	# each time also handles installation-profile reloads that retain the same aircraft ID.
	if session.aircraft.get("ok", false):
		var loaded_model: Dictionary = session.aircraft.model
		var propulsion: Dictionary = loaded_model.get("propulsion", {})
		var glow: Dictionary = propulsion.get("glow", {})
		if not glow.is_empty():
			var glow_propeller: Dictionary = glow.get("propeller", {})
			var diameter_m: float = float(glow_propeller.get("diameter_m", NAN))
			if not AirplaneBuilder.apply_propeller_diameter(_airplane, diameter_m):
				push_error("render/airplane.gd: validated glow model has no applicable propeller diameter")
				session.free()
				session = null
				set_process(false)
				set_process_unhandled_input(false)
				get_tree().quit(ERR_INVALID_DATA)
				return
			_extent = Shadow.model_extent(_airplane.root)
			Shadow.bind_model(_shadow, _airplane.root)
			_rig.set_span(_extent.x)
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
	# The accepted scene definition also owns the float64 contact surface. Never fly a refused lake.
	var lake_context: Dictionary = _field_node.get_meta("lake_context", {}) if _field_node != null else {}
	var lake_error: String = str(_field_node.get_meta("lake_error", "")) if _field_node != null else ""
	if not lake_error.is_empty() or not session.set_lake_context(lake_context):
		startup_error = "Lake configuration refused: " + lake_error
		printerr(startup_error)
		session.free()
		session = null
		set_process(false)
		set_process_unhandled_input(false)
		get_tree().quit(ERR_INVALID_DATA)
		return
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
	var failure_options: Dictionary = _failure_options(args)
	if not failure_options.ok or (_scripted and failure_options.config.probability_percent > 0):
		startup_error = "; ".join(failure_options.errors) if not failure_options.ok else "Failures require a physics flight."
		if not interactive_start:
			printerr(startup_error)
			get_tree().quit(ERR_INVALID_PARAMETER)
		set_process(false)
		set_process_unhandled_input(false)
		return
	failure_config = failure_options.config.duplicate(true)
	failure_seed = failure_options.seed
	failure_notifications = failure_config.notify
	if not _scripted and not session.setup_failures(failure_config, failure_seed):
		startup_error = session.failure_error
		if not interactive_start:
			printerr(startup_error)
			get_tree().quit(ERR_INVALID_PARAMETER)
		set_process(false)
		set_process_unhandled_input(false)
		return
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
	Atmosphere.configure_appearance(sky_config, SkyConfig.mean_wind_ned(session.weather_configuration()))
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
	_lake_ambience = LakeWorld.ambience_player(_field_node)
	if _lake_ambience != null:
		if _soundscape_audio != null:
			_soundscape_audio.soundscape.buses_releasing.connect(_lake_ambience.stop)
			var soundscape_buses: Variant = _soundscape_audio.soundscape.get("_bus_names")
			if soundscape_buses is Array and soundscape_buses.size() >= 3:
				LakeWorld.set_ambience_bus(_field_node, StringName(soundscape_buses[2]))
		_lake_ambience.stream_paused = not session.holds.is_empty()
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
	if accident_reports_enabled and not _scripted and not args.has("capture") and not args.has("trace") \
		and str(args.get("accident-report", "on")) != "off":
		_accident_incident = AccidentIncident.new()
		_accident_settlement = AccidentSettlement.new()
		_accident_incident.archive_path = accident_archive_path
		_begin_accident_ledger()
		_accident_report = AccidentReport.new()
		_accident_report.name = "AccidentReport"
		add_child(_accident_report)
		_accident_incident.assessment_changed.connect(_on_accident_assessment)
		_accident_report.restart_requested.connect(session.reset)
		session.contact_events_changed.connect(_on_accident_contacts)
		var archived: Dictionary = _accident_incident.load_archive()
		if not archived.is_empty():
			_accident_report.show_archived(archived)
		session.crash_auto_restart = false
	flight_log = FlightLog.new(session)
	if args.has("flight-log"):
		if typeof(args["flight-log"]) != TYPE_STRING or str(args["flight-log"]).is_empty() or _scripted or args.has("capture"):
			push_error("--flight-log requires a new file path and a physics flight.")
			get_tree().quit(ERR_INVALID_PARAMETER)
			return
		if flight_log.start(str(args["flight-log"])) != OK:
			get_tree().quit(ERR_CANT_CREATE)
			return
		_update_flight_log_label()
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
	if _accident_report != null:
		_accident_report.suspend(not session.holds.is_empty())
		_update_accident_report()
	if flight_log != null and _flight_log_label != null:
		_update_flight_log_label()
	if _capturing:
		_clear_wheel_brake()
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
	if _wheel_brake_key_held and (sim.paused or not session.crash.is_empty() or not session.gear_is_retractable()
		or not Input.is_physical_key_pressed(KEY_B)):
		_clear_wheel_brake()
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
	if is_instance_valid(_lake_ambience):
		_lake_ambience.stream_paused = not session.holds.is_empty()
	var surfaces: Dictionary = session.surfaces()
	InputPanel.update(_panel, session.raw, session.commands, _view_name(), _status(), surfaces, session.throws_deg())
	_camera_dt = dt
	_render_pose(_current_pose(), surfaces, _prop_angle)
	_update_storm(visual_clock_s, frozen)
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
		var scale_factor: float = float(workshop_trial.get("scale", 1.0))
		_cg_model = Frames.cg_in_model_frame(session.aircraft.model.cg_le, datum.x * scale_factor, datum.y * scale_factor)


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
		var saved := false
		if session.persist_full_controller_profile.is_valid():
			var result: Dictionary = session.persist_full_controller_profile.call(profile)
			saved = bool(result.get("ok", false))
			if not saved:
				_note = tr("Could not save the updated controller profile; the existing profile is unchanged.")
		else:
			var gamepad: bool = profile.get("kind", "") == "gamepad"
			var applied: bool = session.radio.use_profile(profile, "gamepad" if gamepad else "calibrated")
			var write_error: Error = ERR_INVALID_DATA
			if applied:
				write_error = session.RcCalibration.save_smoke_binding(session.profiles_path, session.radio.device_key, profile.aux.smoke) if gamepad \
					else session.RcCalibration.save_profile(session.profiles_path, session.radio.device_key, profile)
			saved = applied and write_error == OK
			if not applied:
				_note = tr("The current controller profile could not be updated.")
			elif not saved:
				_note = tr("Smoke AUX assigned for this flight; profile could not be saved.")
		if saved:
			_note = tr("Smoke AUX assigned. Move throttle and smoke control to OFF before resuming.")
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
	_update_failure_notice()
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
		var gear: Dictionary = session.gear_state()
		if bool(gear.get("available", false)):
			var gear_line := tr("Landing gear: %s") % _gear_status_label(gear)
			if bool(gear.get("inhibited", false)):
				gear_line += " — " + tr("retraction blocked while on wheels")
			lines.append(gear_line)
		var flaps: Dictionary = session.flap_state()
		if bool(flaps.get("available", false)):
			var actual_deg := float(flaps.get("angle_deg", 0.0))
			var target_deg := float(flaps.get("target_deg", 0.0))
			var flap_line := tr("Flaps: %.1f° actual → %.1f° target") % [actual_deg, target_deg]
			var flap_limit := float(flaps.get("limit_mps", NAN))
			lines.append(flap_line)
			if bool(flaps.get("overspeed", false)) and is_finite(flap_limit) and flap_limit > 0.0:
				lines.append(tr("Flaps above estimated speed limit: %.0f m/s EAS") % flap_limit)
		else:
			lines.append(tr("Flaps are unavailable on this aircraft."))
		if not session.weather_is_calm():
			var wind: PackedFloat64Array = session.wind_at(session.sim.time())
			lines.append(_weather_hud_line(s, wind))
		if not session.atmosphere_is_reference():
			var field_air: Dictionary = session.atmosphere_configuration()
			lines.append(tr("EAS %.1f m/s  air %.3f kg/m³  density altitude %.0f m") % [air.V * M.sqrt_(field_air.sigma), field_air.rho_kgm3, field_air.density_altitude_m])
	if _overlays != null:
		_overlays.performance_label.text = Hud.perf_line(_frame_times, session.sim.step_usec).trim_suffix("  [F3]")
	elif _show_perf:
		lines.append(Hud.perf_line(_frame_times, session.sim.step_usec))
	if not _experimental_aircraft_path.is_empty():
		lines.append("EXPERIMENTAL: wing polar; aircraft-specific flight validation pending.")
	if not _scripted and session != null and session.has_method("glow_is_active") and session.glow_is_active():
		var glow: Dictionary = session.glow_state()
		if glow.get("ok", false):
			var family: String = str(glow.get("family", ""))
			var family_label := "2-stroke" if family == "glow_2t" else "4-stroke" if family == "glow_4t" else family
			var temperature_c: float = float(glow.get("temperature_k", 273.15)) - 273.15
			# The generated Stik data estimates premix at about 0.8 g/mL; display the corresponding approximate volume.
			var fuel_ml: float = float(glow.get("fuel_kg", 0.0)) / 0.0008
			var engine_mode: String = "running" if glow.get("running", false) else str(glow.get("stop_reason", "stopped")).replace("_", " ")
			lines.append("Glow %s  %.0f rpm  head %.0f °C  fuel ~%.0f mL  %s  φ %.2f" % [
				family_label, float(glow.get("rpm", 0.0)), temperature_c, fuel_ml, engine_mode,
				float(glow.get("mixture_command", 0.0))])
			if glow.get("above_recommended_rpm", false):
				lines.append("ABOVE RECOMMENDED RPM")
			lines.append("[F6] cut  [F7] starter  [F8] lean  [F9] rich")
	_hud.text = "\n".join(lines)


## An optional incident card, independent of the ordinary telemetry HUD and its preset.
func _update_failure_notice() -> void:
	var status: Dictionary = session.failure_status() if session != null else {}
	var show_notice: bool = failure_notifications and _failure_overlays_visible and bool(status.get("active", false))
	if not show_notice:
		if _failure_notice != null:
			_failure_notice.visible = false
		return
	if _failure_notice == null:
		_failure_notice = CanvasLayer.new()
		_failure_notice.name = "FailureNotice"
		_failure_notice.layer = 70
		add_child(_failure_notice)
		var card := PanelContainer.new()
		card.theme = UiTheme.build()
		card.set_anchors_preset(Control.PRESET_CENTER_TOP)
		card.offset_left = -250.0
		card.offset_right = 250.0
		card.offset_top = 84.0
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_failure_notice.add_child(card)
		_failure_label = Label.new()
		_failure_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_failure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_failure_label.custom_minimum_size.x = 470.0
		_failure_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(_failure_label)
	_failure_label.text = tr("Failure: %s") % tr(str(status.get("label", ""))) + "\n" + tr(str(status.get("hint", "")))
	_failure_notice.visible = true


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


## Semantic gamepad actions share operations with keyboard shortcuts.
## This presentation/routing contract advertises only implemented aircraft equipment.
func controller_capabilities() -> Dictionary:
	return {
		"gear": session != null and session.gear_is_retractable(),
		"smoke": _smoke != null and _smoke.supports_pump(),
		"flaps": session != null and session.flaps_available(),
	}


func accident_menu_active() -> bool:
	return _accident_report != null and _accident_report.wants_controller_menu() and session.holds.is_empty()


func controller_action(action: String) -> bool:
	if session == null: return false
	if _accident_report != null and _accident_report.controller_action(action):
		return true
	match action:
		"camera_cycle": _rig.cycle(1)
		"camera_previous": _rig.cycle(-1)
		"camera_pilot": _rig.set_view("pilot")
		"camera_chase": _rig.set_view("chase")
		"camera_orbit": _rig.set_view("orbit")
		"camera_zoom_in": _rig.zoom(1.0)
		"camera_zoom_out": _rig.zoom(-1.0)
		"camera_auto_zoom": _rig.toggle_auto_zoom()
		"view_reset": _rig.reset_view()
		"lights_cycle": _cycle_night_lights()
		"smoke_toggle":
			if session.sim.paused: return true
			if _smoke == null or not _smoke.supports_pump():
				_note = tr("Smoke is not available on this aircraft.")
			elif session.radio.auxiliary_action(action):
				_note = tr("Smoke pump: on") if session.radio.smoke_amount() > 0.0 else tr("Smoke pump: off")
		"flaps_up", "flaps_down", "flaps_cycle":
			if not session.sim.paused:
				_request_flaps_action(action)
		"gear_toggle":
			if session.sim.paused: return true
			if _has_gear_aux_binding():
				_note = tr("Landing gear is controlled by its AUX input.")
			elif not session.gear_is_retractable():
				_note = tr("Landing gear is fixed on this aircraft.")
			else:
				var accepted: bool = session.toggle_gear()
				var gear: Dictionary = session.gear_state()
				_note = _gear_command_note() if accepted or bool(gear.get("inhibited", false)) else tr("Landing gear command was refused.")
		"trim_left": session.adjust_aileron_trim(-0.005)
		"trim_right": session.adjust_aileron_trim(0.005)
		"trim_up": session.adjust_elevator_trim(-0.1)
		"trim_down": session.adjust_elevator_trim(0.1)
		"overlay_preset":
			if _overlays != null: _overlays.cycle_preset()
		"throttle_cut": session.controller_throttle_cut()
		"calibrate": session.start_calibration()
		"accept":
			if session.calibration != null: session.advance_calibration()
			elif session.sim.paused: session.resume()
		"back", "pause":
			if session.calibration != null: session.cancel_calibration()
			else: pause_requested.emit()
		_: return false
	return true

## Keyboard detents follow the active model's full-down angle and recommended takeoff fraction.
func _flap_detents() -> Array[float]:
	var takeoff_fraction: float = float(session.aircraft.model.flaps.get("takeoff_fraction", 0.4))
	var detents: Array[float] = [0.0]
	if takeoff_fraction > 0.0 and takeoff_fraction < 1.0:
		detents.append(takeoff_fraction)
	detents.append(1.0)
	return detents


func _flap_detent_after(requested: float, direction: int) -> float:
	var detents := _flap_detents()
	var nearest := 0
	var distance := INF
	for i in detents.size():
		var candidate_distance := absf(requested - detents[i])
		if candidate_distance < distance:
			nearest = i
			distance = candidate_distance
	return detents[posmod(nearest + direction, detents.size())]


func _request_flaps_amount(amount: float) -> bool:
	if session == null:
		return false
	var state: Dictionary = session.flap_state()
	if not bool(state.get("available", false)):
		_note = tr("Flaps are unavailable on this aircraft.")
		return false
	if session.sim.paused:
		return false
	var normalized := clampf(amount, 0.0, 1.0)
	if session.radio.connected and not session.radio.set_flaps_action_amount(normalized):
		_note = tr("Flaps are controlled by the radio AUX input.")
		return false
	if not session.set_flaps(normalized):
		_note = tr("Flaps request was refused.")
		return false
	_note = tr("Flaps request accepted.")
	return true


func _request_flaps_action(action: String) -> bool:
	if session == null:
		return false
	var state: Dictionary = session.flap_state()
	if not bool(state.get("available", false)):
		_note = tr("Flaps are unavailable on this aircraft.")
		return false
	var requested := float(state.get("requested", 0.0))
	match action:
		"flaps_up": return _request_flaps_amount(0.0)
		"flaps_down": return _request_flaps_amount(1.0)
		"flaps_cycle": return _request_flaps_amount(_flap_detent_after(requested, 1))
	return false


func _step_flaps(direction: int) -> void:
	if session == null or session.sim.paused:
		return
	var state: Dictionary = session.flap_state()
	if not bool(state.get("available", false)):
		_note = tr("Flaps are unavailable on this aircraft.")
		return
	_request_flaps_amount(_flap_detent_after(float(state.get("requested", 0.0)), direction))


func _gear_status_label(gear: Dictionary) -> String:
	match str(gear.get("status", "")):
		"up": return tr("Up")
		"down": return tr("Down")
		"extending": return tr("Extending")
		"retracting": return tr("Retracting")
	return tr("Unknown")


func _gear_command_note() -> String:
	var gear: Dictionary = session.gear_state()
	if not bool(gear.get("available", false)):
		return tr("Landing gear is fixed on this aircraft.")
	if bool(gear.get("inhibited", false)):
		return tr("Gear retraction is blocked while the aircraft is on its wheels.")
	return tr("Landing gear: %s") % _gear_status_label(gear)


func _has_gear_aux_binding() -> bool:
	if session == null:
		return false
	var aux_value: Variant = session.radio.profile.get("aux", {})
	if typeof(aux_value) != TYPE_DICTIONARY:
		return false
	var aux: Dictionary = aux_value
	var binding_value: Variant = aux.get("gear", {})
	if typeof(binding_value) != TYPE_DICTIONARY:
		return false
	var binding: Dictionary = binding_value
	return str(binding.get("type", "")) in ["axis", "button"]


func _clear_wheel_brake() -> void:
	if session != null:
		session.set_wheel_brake(0.0) # Brake release remains valid during pause and focus loss.
	_wheel_brake_key_held = false


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_B and not event.pressed:
		_clear_wheel_brake()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear_wheel_brake()


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
		if not _scripted and session != null and session.has_method("glow_is_active") and session.glow_is_active():
			var glow_action_ok := false
			var action_label := ""
			match event.physical_keycode:
				KEY_F6:
					glow_action_ok = session.glow_cut()
					action_label = "cut"
				KEY_F7:
					glow_action_ok = session.glow_start()
					action_label = "starter"
				KEY_F8, KEY_F9:
					var glow_model: Dictionary = session.aircraft.model.propulsion.glow
					var nominal_phi: float = float(glow_model.profile.operation.nominal_mixture)
					var target_phi: float = nominal_phi * (0.85 if event.physical_keycode == KEY_F8 else 1.15)
					glow_action_ok = session.glow_set_mixture(target_phi)
					action_label = "lean mixture φ %.2f" % target_phi if event.physical_keycode == KEY_F8 else "rich mixture φ %.2f" % target_phi
			if action_label != "":
				_note = "Glow %s %s." % [action_label, "accepted" if glow_action_ok else "refused"]
				get_viewport().set_input_as_handled()
				return
		match event.physical_keycode:
			KEY_F10:
				if flight_log != null and not _scripted:
					if flight_log.recording: flight_log.stop()
					else: flight_log.start()
					_update_flight_log_label()
					get_viewport().set_input_as_handled()
			KEY_F11:
				if flight_log != null and flight_log.recording:
					flight_log.mark()
					_note = "Flight log marker at tick %d" % session.sim.tick
					get_viewport().set_input_as_handled()
			KEY_G:
				controller_action("gear_toggle")
				get_viewport().set_input_as_handled()
			KEY_F:
				_step_flaps(-1 if event.shift_pressed else 1)
				get_viewport().set_input_as_handled()
			KEY_B:
				if not session.sim.paused and session.gear_is_retractable() and session.set_wheel_brake(1.0):
					_wheel_brake_key_held = true
					get_viewport().set_input_as_handled()
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				if session.adjust_aileron_trim(-0.005 if event.physical_keycode == KEY_BRACKETLEFT else 0.005):
					_note = tr("Aileron trim: %+.1f%%") % (session.trims.roll * 100.0)
					get_viewport().set_input_as_handled()
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
			KEY_L:
				_cycle_night_lights()
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


## FW-35b: [L] cycles the night lights ALL → NAV (navigation and strobes) → OFF. In daylight the first press fits the
## kit; its physical brightness then shows as faint dots, as real LEDs do in the sun.
func _cycle_night_lights() -> void:
	var modes: Array = World.AircraftLights.MODES
	if _night_kit == null or not is_instance_valid(_night_kit):
		_night_kit = World.AircraftLights.attach(_airplane.root)
	else:
		var mode := String(_night_kit.get_meta("mode", "all"))
		World.AircraftLights.set_mode(_night_kit, modes[(modes.find(mode) + 1) % modes.size()])
	_note = tr("Night lights: " + String(_night_kit.get_meta("mode", "all")))


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
	var snap := OverlayManager.snapshot(session, field.pilot, _extent.x, not _experimental_aircraft_path.is_empty(), view_heading)
	if snap.has("control_guide"):
		snap.control_guide.capabilities = controller_capabilities()
		snap.control_guide.equipment_state = {
			gear = session.gear_state().get("status", "unavailable"),
			smoke = "on" if _smoke != null and float(_smoke.levels.pump) > 0.0 else "off",
			flaps = session.flap_state(),
		}
	return snap


## Shows or hides the flight's text overlays (input panel and HUD). A menu hides them: the paused picture then
## shows the airplane alone, and the panel's "[P] resume" never contradicts the menu.
func set_overlays_visible(on: bool) -> void:
	_failure_overlays_visible = on
	if _failure_notice != null:
		_failure_notice.visible = on and failure_notifications and bool(session.failure_status().get("active", false))
	for label in [_panel, _hud]:
		var n: Node = label
		while n != null and not n is CanvasLayer:
			n = n.get_parent()
		if n != null:
			n.visible = on
	var latency_marker := get_node_or_null("LatencyPatch") as CanvasLayer
	if latency_marker != null:
		latency_marker.visible = on


## Called by the Home launch transaction, after the real model/session have accepted their inputs.
func bind_scenario(raw: Variant) -> Dictionary:
	var checked: Dictionary = ScenarioConfig.validate(raw)
	if not checked.ok:
		return checked
	var selected: Dictionary = checked.scenario
	var sources: Dictionary = ScenarioConfig.validate_sources(selected, field_path)
	if not sources.ok:
		return sources
	if not interactive_start or session == null or not session.is_flyable() or not workshop_trial.is_empty() \
			or not _experimental_aircraft_path.is_empty() or not _electric_demo.is_empty() \
			or aircraft_id != selected.aircraft_id or start_choice != selected.start_choice \
			or session.weather_configuration() != selected.weather_config or lighting_config != selected.lighting_config \
			or session.aircraft.get("input_identity", {}).get("sha256", "") != selected.aircraft_identity \
			or _airplane.get("model_manifest_sha256", "") != selected.model_identity or field.get("id", "") != selected.field_id:
		return {ok = false, errors = ["Prepared flight does not match the random scenario."]}
	flight_scenario = selected.duplicate(true)
	_note = tr("Natural Random") if selected.provenance == "generated" else tr("Custom from Natural Random")
	return {ok = true, errors = []}


func _forget_scenario() -> void:
	if not flight_scenario.is_empty():
		flight_scenario = {}
		if _note in [tr("Natural Random"), tr("Custom from Natural Random")]:
			_note = ""
		scenario_changed.emit({})


## TOD-08a: paired technical replay checkpoint; native Variant encoding preserves physics bits.
## This is not a live-input save game or a rendered trace player.
func checkpoint() -> Dictionary:
	if session == null or _scripted or _capturing or _field_world_lighting or _capture_scene_id() != "field":
		return {}
	var selection: Dictionary = VisualTimeline.evaluate(_visual_timeline, session.sim.tick)
	if not selection.ok or selection.config != lighting_config:
		return {} # refuse an unrecorded visual edit
	var saved: Dictionary = VisualCheckpoint.make(session.checkpoint(), _visual_timeline, _field_identity())
	if not saved.ok:
		return {}
	var paired: Dictionary = saved.checkpoint
	if sky_config != SkyConfig.defaults() or not _sky_edits.is_empty():
		paired = SkyCheckpoint.make(paired, sky_config, Atmosphere.cloud_transport_checkpoint(), _sky_edits)
		if paired.is_empty():
			return {}
	if _crash_director != null:
		var water_render: Dictionary = _crash_director.water_checkpoint()
		if not water_render.is_empty():
			var wrapped: Dictionary = {
				"format": WATER_CHECKPOINT_FORMAT,
				"visual": paired,
				"water_render": water_render,
			}
			wrapped["payload_sha256"] = _water_checkpoint_digest(paired, water_render)
			paired = wrapped
	if _accident_incident != null and _accident_incident.has_damage():
		if _accident_reload_pending:
			return {}
		var ledger: Dictionary = _accident_incident.checkpoint(session.sim.tick, _accident_bindings)
		if ledger.is_empty():
			return {}
		paired = AccidentIncident.Checkpoint.wrap(paired, {ledger = ledger,
			settlement = _accident_settlement.checkpoint(),
			presentation = {ground_stable = _accident_ground_stable, settled_pending = _accident_settled_pending}})
	return paired


## Validate both halves and prepare detached shadow geometry before the physics owner commits.
## No await: an invalid record cannot change the live world, recording or simulation.
func restore_checkpoint(candidate: Variant) -> Dictionary:
	if session == null or _scripted or _capturing or _field_world_lighting or _capture_scene_id() != "field" or not startup_error.is_empty():
		return {ok = false, errors = ["visual checkpoint requires a ready production flight"]}
	var economic_restore: Dictionary = {}
	if candidate is Dictionary and candidate.get("format") == AccidentIncident.Checkpoint.ENVELOPE:
		if _accident_incident == null:
			return {ok = false, errors = ["Economics checkpoint requires accident reporting."]}
		var unwrapped: Dictionary = AccidentIncident.Checkpoint.unwrap(candidate)
		if not unwrapped.ok:
			return unwrapped
		economic_restore = unwrapped.economy
		if economic_restore.is_empty():
			return {ok = false, errors = ["Paired economics checkpoint has no ledger."]}
		candidate = unwrapped.visual
	var visual_candidate: Variant = candidate
	var water_restore: Dictionary = {}
	var has_water_render: bool = false
	if typeof(candidate) == TYPE_DICTIONARY and candidate.get("format") == WATER_CHECKPOINT_FORMAT:
		if not _has_exact_keys(candidate, WATER_CHECKPOINT_FIELDS) \
				or typeof(candidate.get("visual")) != TYPE_DICTIONARY \
				or typeof(candidate.get("water_render")) != TYPE_DICTIONARY \
				or typeof(candidate.get("payload_sha256")) != TYPE_STRING \
				or candidate.payload_sha256 != _water_checkpoint_digest(candidate.visual, candidate.water_render):
			return {ok = false, errors = ["water visual checkpoint envelope is invalid"]}
		if _crash_director == null:
			return {ok = false, errors = ["water visual checkpoint requires the crash director"]}
		water_restore = _crash_director.prepare_water_restore(candidate.water_render)
		if water_restore.is_empty():
			return {ok = false, errors = ["water aftermath checkpoint is invalid or incompatible"]}
		visual_candidate = candidate.visual
		has_water_render = true
	var sky_restore: Dictionary = SkyCheckpoint.read(visual_candidate)
	if not sky_restore.ok:
		return sky_restore
	var decoded: Dictionary = VisualCheckpoint.read(sky_restore.visual, _field_identity())
	if not decoded.ok:
		return decoded
	var prepared_economics: Dictionary = {}
	if not economic_restore.is_empty():
		if not AccidentIncident.Checkpoint.keys(economic_restore, ["ledger", "settlement", "presentation"]) \
			or not AccidentSettlement.valid_checkpoint(economic_restore.settlement, decoded.physics.simulation.tick) \
			or not economic_restore.presentation is Dictionary \
			or not AccidentIncident.Checkpoint.keys(economic_restore.presentation, ["ground_stable", "settled_pending"]) \
			or not economic_restore.presentation.ground_stable is bool or not economic_restore.presentation.settled_pending is bool:
			return {ok = false, errors = ["Invalid economics settlement or presentation checkpoint."]}
		if economic_restore.presentation.settled_pending and (not economic_restore.settlement.settled or not economic_restore.presentation.ground_stable):
			return {ok = false, errors = ["Settled report requires completed dwell and stable ground contact."]}
		prepared_economics = _accident_incident.prepare_restore(economic_restore.ledger, decoded.physics.simulation.tick, _accident_bindings)
		if not prepared_economics.ok:
			return prepared_economics
	var restored_time: float = float(decoded.physics.simulation.tick) * float(decoded.physics.simulation.dt)
	var restored_mean: Array = SkyConfig.mean_wind_ned(decoded.physics.get("weather_config", {}))
	if not sky_restore.legacy and (float(sky_restore.transport.anchor_time_s) > restored_time + 1.0e-9 \
			or not Atmosphere.validate_cloud_transport_for(sky_restore.config, sky_restore.transport, restored_mean)):
		return {ok = false, errors = ["cloud transport disagrees with checkpoint time or weather"]}
	for edit: Dictionary in sky_restore.edits:
		if edit.tick > decoded.physics.simulation.tick or not Atmosphere.validate_cloud_transport_for(edit.config, edit.transport, restored_mean):
			return {ok = false, errors = ["sky edit disagrees with checkpoint tick or weather"]}
	# TOD-09c1 defines progressing records before the live controller consumes them.
	# Refuse even a stopped v2 history: its restart selection and fractional phase
	# cannot be represented by this controller's fixed-time reset path yet.
	if decoded.timeline.format != VisualTimeline.FORMAT:
		return {ok = false, errors = ["progressing visual checkpoints require the solar progression controller"]}
	var staged: Dictionary = _prepare_checkpoint_lighting(decoded.config)
	if not staged.ok:
		return {ok = false, errors = ["could not prepare checkpoint lighting"]}
	_accident_checkpoint_restoring = not prepared_economics.is_empty()
	var physics_restored: bool = session.restore_checkpoint(decoded.physics)
	_accident_checkpoint_restoring = false
	if not physics_restored:
		return {ok = false, errors = ["physics checkpoint is invalid or incompatible"]}
	if not prepared_economics.is_empty():
		_accident_report.clear_report()
		_accident_restored = false
		_accident_paired_history = true
		_accident_reload_pending = false
		_accident_settlement.restore_checkpoint(economic_restore.settlement)
		_accident_ground_stable = economic_restore.presentation.ground_stable
		_accident_settled_pending = economic_restore.presentation.settled_pending or (economic_restore.settlement.settled and _accident_ground_stable)
		_accident_incident.commit_restore(prepared_economics)
	# Existing checkpoints contain no scenario envelope. Never label a restored flight with stale seed provenance.
	_forget_scenario()
	sky_config = sky_restore.config.duplicate(true)
	_sky_edits = sky_restore.edits.duplicate(true)
	Atmosphere.configure_appearance(sky_config, SkyConfig.mean_wind_ned(session.weather_configuration()))
	if not sky_restore.legacy:
		Atmosphere.restore_cloud_transport(sky_restore.transport)
	if not _commit_lighting(staged, decoded.config):
		return {ok = false, physics_restored = true, economics_restored = not prepared_economics.is_empty(), errors = ["physics restored, but visual scene changed during restoration"]}
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
	_refresh_sky()
	if _storm_fx != null:
		_storm_fx.reset()
		_update_storm(session.sim.time(), session.sim.paused)
	if has_water_render:
		if not _crash_director.restore_water_checkpoint(water_restore):
			return {ok = false, physics_restored = true, economics_restored = not prepared_economics.is_empty(), errors = ["physics restored, but water aftermath could not be restored"]}
	elif _crash_director != null:
		_crash_director.reset()
	_note = "Checkpoint restored; visual context: " + _visual_context_status
	return {ok = true, context_status = _visual_context_status, economics_restored = not prepared_economics.is_empty(), errors = []}


func _water_checkpoint_digest(visual: Dictionary, water_render: Dictionary) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes([visual, water_render]))
	return hashing.finish().hex_encode()


func _has_exact_keys(source: Dictionary, expected: Array[String]) -> bool:
	if source.size() != expected.size():
		return false
	for key: Variant in source.keys():
		if typeof(key) != TYPE_STRING or not expected.has(str(key)):
			return false
	return true


## FW-78/82: validate a paused appearance edit before any lighting/preferences are committed.
func prepare_sky_edit(raw: Variant) -> Dictionary:
	var checked: Dictionary = SkyConfig.validate(raw)
	if not checked.ok:
		return checked
	if session == null or not session.sim.paused or _scripted or _capturing or _env == null or not startup_error.is_empty():
		return {ok = false, errors = ["sky editing requires a paused production flight"]}
	if _sky_edits.size() >= 4096 and checked.config != sky_config:
		return {ok = false, errors = ["sky edit history is full; restart before another edit"]}
	return checked


func apply_sky_config(raw: Variant) -> Dictionary:
	var checked: Dictionary = prepare_sky_edit(raw)
	if not checked.ok:
		return checked
	if checked.config == sky_config:
		return {ok = true, changed = false, errors = []}
	if not Atmosphere.configure_appearance(checked.config, SkyConfig.mean_wind_ned(session.weather_configuration()), session.sim.time()):
		return {ok = false, errors = ["could not prepare cloud appearance"]}
	sky_config = checked.config
	_refresh_sky()
	_sky_edits.append({tick = session.sim.tick, config = sky_config.duplicate(true), transport = Atmosphere.cloud_transport_checkpoint()})
	if recorder != null and recorder.recording:
		recorder.trace.meta.sky_context = JSON.stringify(_sky_context(), "", true, true)
	return {ok = true, changed = true, errors = []}


func _sky_context() -> Dictionary:
	return {config = sky_config.duplicate(true), config_identity = SkyConfig.identity(sky_config),
		profile = SkyConfig.validate(sky_config).profile, transport = Atmosphere.cloud_transport_checkpoint(),
		edits = _sky_edits.duplicate(true)}


## Restore the retained flight's renderer after a Workshop world used the shared sky uniforms.
func restore_sky_presentation(transport: Dictionary) -> void:
	var retained_exposure: float = _env.tonemap_exposure
	Atmosphere.configure_appearance(sky_config, SkyConfig.mean_wind_ned(session.weather_configuration()))
	Atmosphere.restore_cloud_transport(transport)
	_refresh_sky(retained_exposure)


func _refresh_sky(retained_exposure: float = -1.0) -> void:
	var snapshot: Dictionary = _lighting if lighting_config.get("mode", "legacy") != "legacy" else {}
	Atmosphere.update_environment(_env, snapshot)
	if retained_exposure > 0.0:
		# A retained paused world already has an adapted exposure; do not reset it to the sky baseline.
		_env.tonemap_exposure = retained_exposure
		World.Exposure.set_value(retained_exposure)
	Atmosphere.update_sun(_sun, snapshot)
	Atmosphere.update_cloud_appearance(_field_node)
	Atmosphere.update_clouds(_env, session.sim.time())
	World.refresh_star_cloud_appearance(_env)
	World.refresh_weather_appearance(_env, session.sim.time())
	if _storm_fx != null:
		_storm_fx.configure(sky_config)
		_update_storm(session.sim.time(), session.sim.paused)


func _update_storm(clock_s: float, paused: bool) -> void:
	if _storm_fx == null or _camera == null or sky_config.preset != "electrical_storm":
		return
	_storm_fx.bind_storm_bank(World.storm_bank_node(_env))
	_storm_fx.set_cell_transport(Atmosphere.cloud_transport_checkpoint())
	_storm_fx.set_cloud_state(Atmosphere.cloud_state_snapshot())
	if _soundscape_audio != null:
		_storm_fx.set_sound_speed(float(_soundscape_audio.snapshot().sound_speed))
	_storm_fx.update_at(clock_s, _camera.global_position, paused, _env.tonemap_exposure)


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
	var next_scenario: Dictionary = {}
	if not flight_scenario.is_empty():
		next_scenario = ScenarioConfig.customize_lighting(flight_scenario, checked.config)
		if next_scenario.is_empty():
			return {ok = false, changed = false, errors = ["Could not prepare the customized flight scenario."]}
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
	if not flight_scenario.is_empty():
		flight_scenario = next_scenario
		_note = tr("Custom from Natural Random")
		if recorder.recording:
			# Preserve the trace's initial scenario; append edits at their physical tick boundary.
			var edits: Array = JSON.parse_string(recorder.trace.meta.get("flight_scenario_edits", "[]"))
			edits.append({tick = session.sim.tick, scenario = flight_scenario.duplicate(true)})
			recorder.trace.meta.flight_scenario_edits = JSON.stringify(edits, "", true, true)
		scenario_changed.emit(flight_scenario.duplicate(true))
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
	if _field_node != null and _field_node.has_meta("lake_identity"):
		hashing.update(str(_field_node.get_meta("lake_identity")).to_utf8_buffer())
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
	if sky_config != SkyConfig.defaults() or not _sky_edits.is_empty():
		meta.sky_context = JSON.stringify(_sky_context(), "", true, true)
	meta.aircraft_visual_family = str(_airplane.get("visual_family", ""))
	meta.aircraft_model_manifest_sha256 = str(_airplane.get("model_manifest_sha256", ""))
	var build := BuildInfo.current()
	meta.app_build = build.describe if build.source == "export" else "development"
	meta.app_version = build.parsed.semver if build.source == "export" else build.version + " (development)"
	meta.visual_night_options = JSON.stringify(night_options, "", true, true)
	if not flight_scenario.is_empty():
		meta.flight_scenario = JSON.stringify(flight_scenario, "", true, true)
	if _visual_context_status != "present":
		meta.visual_context_status = _visual_context_status
	if _visual_context_status != "present" or not _visual_timeline.events.is_empty():
		meta.visual_timeline = JSON.stringify(_visual_timeline, "", true, true)
	if lighting_config.get("mode", "legacy") != "legacy" or _visual_context_status != "present" or not _visual_timeline.events.is_empty():
		# Self-contained optional header, copied/frozen by Recorder; CSV columns and physics identity stay unchanged.
		meta.visual_context = JSON.stringify(TimeOfDayLighting.context(lighting_config, _lighting), "", true, true)
	return meta


func _update_flight_log_label() -> void:
	if _flight_log_label == null:
		var layer := CanvasLayer.new()
		layer.layer = 25
		add_child(layer)
		_flight_log_label = Label.new()
		layer.add_child(_flight_log_label)
		_flight_log_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_flight_log_label.offset_left = -520
		_flight_log_label.offset_right = -16
		_flight_log_label.offset_top = -54
		_flight_log_label.offset_bottom = -16
		_flight_log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_flight_log_label.clip_text = true
		var background := StyleBoxFlat.new()
		background.bg_color = Color(0.03, 0.05, 0.08, 0.86)
		background.content_margin_left = 12
		background.content_margin_right = 12
		_flight_log_label.add_theme_stylebox_override("normal", background)
		_flight_log_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		_flight_log_label.add_theme_constant_override("shadow_offset_x", 1)
		_flight_log_label.add_theme_constant_override("shadow_offset_y", 1)
		_flight_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flight_log_label.text = "REC %.1f s · F10 stop · F11 mark" % flight_log.seconds() if flight_log.recording else flight_log.note
	_flight_log_label.tooltip_text = flight_log.note


## CR-30: only accepted contact evidence enters costs. VFX severity never enters this path.
func _on_accident_contacts() -> void:
	if _accident_incident == null or _accident_checkpoint_restoring:
		return
	if _accident_source_hash != str(session.aircraft.get("input_identity", {}).get("sha256", "")):
		_accident_reload_pending = true
		return # Rebind at the frame boundary; no catalog or archive I/O in an accepted callback.
	_accident_restored = _accident_restored or (not _accident_paired_history and session.pause_reason == "checkpoint restored (recorded inputs)")
	_accident_incident.observe(session.contact_events(), _accident_bindings, not session.crash.is_empty(), _accident_restored)
	if _accident_incident.has_damage() and not _accident_incident.terminal:
		_observe_accident_settlement()


func _observe_accident_settlement() -> void:
	var state: PackedFloat64Array = session.sim.state
	var speed_squared := 0.0
	var rate_squared := 0.0
	for axis in 3:
		speed_squared += state[RB.VEL + axis] * state[RB.VEL + axis]
		rate_squared += state[RB.RATE + axis] * state[RB.RATE + axis]
	var grounded := false
	for compression: float in session.gear_compressions(state):
		grounded = grounded or compression > 0.00001
	if not grounded:
		grounded = session.touches_ground(state) # A belly slide can settle with its wheels clear.
	var speed := sqrt(speed_squared)
	var rate := sqrt(rate_squared)
	_accident_ground_stable = AccidentSettlement.is_stable(grounded, speed, rate)
	if _accident_settlement.observe(session.sim.tick, session.sim.dt(), grounded, speed, rate):
		_accident_settled_pending = true
	if not _accident_ground_stable:
		if _accident_settled_pending:
			_accident_settlement.reset() # Nothing was shown; a later landing can earn a fresh dwell.
		_accident_settled_pending = false # A go-around before the next frame cannot open a stale card.


## All valuation, UI publication and persistence run outside accepted simulation callbacks.
func _update_accident_report() -> void:
	if _accident_reload_pending:
		var archived: Dictionary = _accident_incident.archive()
		_begin_accident_ledger()
		_accident_report.clear_report()
		if not archived.is_empty():
			_accident_report.show_archived(archived)
		_accident_restored = true # Earlier contacts under the changed identity were not retained.
		_on_accident_contacts()
	var archive_result: int = _accident_incident.flush()
	if archive_result != OK and archive_result != _accident_archive_error:
		_note = tr("Accident report could not be saved; it remains available for this session.")
	_accident_archive_error = archive_result
	if _accident_settled_pending and not _accident_incident.terminal:
		_accident_report.show_settled(_accident_incident.report)
		_accident_settled_pending = false
	elif not _accident_ground_stable:
		_accident_report.dismiss_settled()


func _begin_accident_ledger() -> void:
	_accident_source_hash = str(session.aircraft.get("input_identity", {}).get("sha256", ""))
	_accident_bindings = session.contact_contract()
	_accident_incident.begin(aircraft_id, _accident_source_hash)
	_accident_restored = false
	_accident_paired_history = false
	_accident_settlement.reset()
	_accident_settled_pending = false
	_accident_ground_stable = false
	_accident_reload_pending = false


func _on_accident_assessment(report: Dictionary, terminal: bool) -> void:
	_accident_report.show_assessment(report, terminal)


func _exit_tree() -> void:
	if _accident_incident != null:
		_accident_incident.archive()
	if flight_log != null:
		flight_log.stop("flight closed")


## One file never mixes two flights.
func _on_resetting() -> void:
	if _accident_incident != null and not _accident_checkpoint_restoring:
		var archived: Dictionary = _accident_incident.archive()
		_begin_accident_ledger()
		_accident_report.clear_report()
		if not archived.is_empty():
			_accident_report.show_archived(archived)
	_sky_edits.clear()
	Atmosphere.configure_appearance(sky_config, SkyConfig.mean_wind_ned(session.weather_configuration()))
	if _storm_fx != null:
		_storm_fx.reset()
	if not flight_scenario.is_empty() and (session.aircraft.get("input_identity", {}).get("sha256", "") != flight_scenario.aircraft_identity \
			or session.weather_configuration() != flight_scenario.weather_config):
		_forget_scenario() # developer reload/environment replacement is no longer the accepted random draw
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
## --field-lighting=club|airfield|off, --campfire=on|off (FW-71 visual options; direct routes ignore saved preferences),
## --experimental-aircraft-data=<absolute JSON path> (research-only Ugly Stik wing-polar candidate)
func _user_args() -> Dictionary:
	var args := {}
	for a in user_args:
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else true
	return args


func set_user_args(args: PackedStringArray) -> void:
	user_args = args.duplicate()


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


func _build_world() -> bool:
	_airplane = AirplaneBuilder.build(aircraft_id, NAN, workshop_trial.get("presentation", {}))
	if _airplane.is_empty():
		startup_error = "Aircraft model failed its manifest and scene binding checks: " + aircraft_id
		return false
	var snapshot: Dictionary = _lighting if lighting_config.get("mode", "legacy") != "legacy" else {}
	Atmosphere.configure_appearance(sky_config)
	var built: Dictionary = World.build(self, field, _build_field, {}, snapshot, night_options)
	_field_world_lighting = bool(built.conditions.time_of_day)
	_env = built.environment
	_world_environment = built.world_environment
	_sun = built.sun

	_airplane.root.scale = Vector3.ONE * float(workshop_trial.get("scale", 1.0))
	add_child(_airplane.root)
	_extent = Shadow.model_extent(_airplane.root) * float(workshop_trial.get("scale", 1.0))
	_shadow = Shadow.create(self)
	Shadow.bind_model(_shadow, _airplane.root)
	_night_kit = World.dress_aircraft(_airplane.root) # FW-35: night kit from dusk, after the extent is measured
	_camera = PilotCamera.create(self, field.pilot)
	_storm_fx = Lightning.new()
	_storm_fx.name = "ElectricalStorm"
	add_child(_storm_fx)
	_storm_fx.configure(sky_config)
	var storm_args: Dictionary = _user_args()
	_storm_fx.set_audio_enabled(not _scripted and not storm_args.has("capture") and str(storm_args.get("soundscape", "on")) != "off")
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
	return true


## Commits a validated presentation change to this flight's field world.
func set_night_options(profile: String, campfire: bool) -> bool:
	var checked: Dictionary = Preferences.validate_night_options({"field_lighting": profile, "campfire": campfire})
	if not checked.get("ok", false):
		return false
	night_options = checked.options.duplicate(true)
	World.set_night_options(profile, campfire)
	return true


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


func _surface_rotations_for_render(c: Dictionary) -> Dictionary:
	if _scripted:
		return Commands.hinge_rotations(c, session.throws_deg())
	return ControlSurfaces.hinge_rotations_from_surfaces(session.surface_angles_deg())


func _render_pose(pose: Dictionary, c: Dictionary, prop_angle: float) -> void:
	_last_render_pose = pose
	_airplane.root.transform = Frames.root_transform(pose.basis, pose.pos, _cg_model)
	# root_transform replaces the basis each frame; restore the presentation-only uniform scale.
	_airplane.root.scale = Vector3.ONE * float(workshop_trial.get("scale", 1.0))
	_airplane.propeller.rotation.z = prop_angle * float(_airplane.get("propeller_spin_sign", 1.0))
	AirplaneBuilder.apply_surfaces(_airplane, _surface_rotations_for_render(c))
	if session != null and session.flaps_available():
		var flap_state: Dictionary = session.flap_state()
		AirplaneBuilder.apply_flaps(_airplane, float(flap_state.get("angle_deg", 0.0)))
	AirplaneBuilder.apply_throttle(_airplane, float(c.get("throttle", 0.0))) # US-V09c carburettor lever, visual only
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
	_update_storm(clock_s, false) # deterministic capture includes the selected event phase
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
		args = " ".join(user_args).replace(png_path, png_path.get_file()),
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
		format = "openrc-visual-evidence v1", lighting = TimeOfDayLighting.context(lighting_config, _lighting),
		world_lighting = {enabled = _field_world_lighting, state = Atmosphere.state.duplicate(true) if _field_world_lighting else {}},
		storm_bank = World.weather_snapshot(_env),
		electrical_storm = _storm_fx.snapshot() if _storm_fx != null else {},
		sky = _sky_context(),
		night_options = night_options.duplicate(true), provenance = VisualEvidence.provenance(),
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
