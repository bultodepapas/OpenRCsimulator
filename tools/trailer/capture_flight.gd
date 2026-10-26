## Live production-flight frame capture for trailer source shots.
## Run outside the app scene: Godot --path app --fixed-fps 60 --script <absolute path> -- --out-dir=<absolute path>.
## This driver instantiates the real main scene and never changes app/ sources or physics.
extends SceneTree

const MainScene := preload("res://main.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const WorldConditions := preload("res://render/world/conditions.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Trial := preload("res://workshop/trial.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const CameraSettings := preload("res://render/camera/camera_settings.gd")
const Exposure := preload("res://render/world/exposure.gd")

const DEFAULT_FPS := 60
const DEFAULT_WIDTH := 1920
const DEFAULT_HEIGHT := 1080
const MAX_CRASH_PREROLL_S := 30.0
const CRASH_CLIP_APPROACH_FRAMES := 120
const CRASH_CLIP_POST_IMPACT_FRAMES := 360
const CRASH_RESTART_AFTER_IMPACT_FRAMES := 240

var _options: Dictionary = {}
var _main: Node
var _director: Node
var _out_dir := ""
var _shot := "stik-bank"
var _fps := DEFAULT_FPS
var _width := DEFAULT_WIDTH
var _height := DEFAULT_HEIGHT
var _seconds := 4.0
var _frame_count := 0
var _image_count := 0
var _sample_every := 1
var _save_images := true
var _failure := ""
var _preserved_report: Dictionary = {}
var _preserved_crash: Dictionary = {}
var _preserved_prop_strike: Dictionary = {}
var _impact_preroll_frames := -1
var _restart_result := false
var _restart_frame := -1
var _restart_movie_frame := -1
var _restart_tick_before := -1
var _restart_tick_after := -1
var _details_frame := -1
var _report_layer_hidden_before_impact := false
var _report_layer_reveal_frame := -1


func _initialize() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	root.size = Vector2i(DEFAULT_WIDTH, DEFAULT_HEIGHT)
	root.msaa_3d = Viewport.MSAA_4X
	call_deferred("_run")


func _run() -> void:
	_options = _parse_options(OS.get_cmdline_user_args())
	_out_dir = str(_options.get("out-dir", ""))
	if _out_dir.is_empty():
		push_error("capture_flight requires --out-dir=<absolute path>")
		quit(2)
		return
	if not _out_dir.is_absolute_path():
		push_error("--out-dir must be an absolute path")
		quit(2)
		return
	var directory_error := DirAccess.make_dir_recursive_absolute(_out_dir)
	if directory_error != OK:
		push_error("Could not create capture directory: %s (%s)" % [_out_dir, error_string(directory_error)])
		quit(1)
		return
	_fps = int(_options.get("fps", DEFAULT_FPS))
	_width = int(_options.get("width", DEFAULT_WIDTH))
	_height = int(_options.get("height", DEFAULT_HEIGHT))
	_seconds = float(_options.get("seconds", 4.0))
	_shot = str(_options.get("shot", "stik-bank"))
	_sample_every = maxi(1, int(_options.get("sample-every", 1)))
	_save_images = not OS.get_cmdline_user_args().has("--movie-only")
	if _fps != 60 or _width != 1920 or _height != 1080 or _seconds <= 0.0:
		push_error("Trailer capture requires 1920x1080, 60 fps, and a positive duration")
		quit(2)
		return
	TranslationServer.set_locale("en")
	_main = MainScene.new()
	_main.name = "Main"
	_main.interactive_start = true
	_main.aircraft_id = str(_options.get("aircraft", "jensen-das-ugly-stik-60"))
	# Build the same validated, detached presentation snapshot used by Workshop trials.
	# This capture-only option never saves a variant or changes aircraft physics.
	if _options.has("lighting-preset"):
		var lighting := Presentation.LightingProfile.preset(str(_options["lighting-preset"]))
		var described := Customization.describe(_main.aircraft_id)
		if lighting.is_empty() or not described.get("ok", false):
			push_error("Capture requires a known lighting preset and an admitted aircraft companion.")
			_main.free()
			quit(2)
			return
		var profile := Presentation.defaults(described.bindings)
		profile.lighting = lighting
		var frozen := Trial.freeze({"base_id": _main.aircraft_id,
			"base_bytes": FileAccess.get_file_as_bytes(Catalog.entry(_main.aircraft_id).data),
			"recipe": {}, "presentation_profile": profile})
		if not frozen.get("ok", false):
			push_error("Lighting capture trial refused: " + str(frozen.get("errors", [])))
			_main.free()
			quit(2)
			return
		_main.workshop_trial = frozen
	_main.start_choice = str(_options.get("start", "airborne"))
	if _shot == "lighting-pilot":
		_main.camera_preferences = CameraSettings.normalized({
			"camera_view": "pilot", "camera_auto_zoom": false, "camera_magnifier": "on"})
	_main.overlays_enabled = _shot == "controls"
	if _options.has("sky"):
		_main.sky_config = SkyConfig.for_preset(str(_options.sky))
	elif _shot == "storm":
		_main.sky_config = SkyConfig.for_preset("electrical_storm")
	_main.accident_archive_path = _out_dir.path_join("incident-%d.json" % Time.get_ticks_usec())
	_main.user_args = PackedStringArray([
		"--accident-report=on",
		"--crash-effects=on",
		"--smoke-pump=on",
		"--failures=0",
		"--failure-seed=0",
	])
	if _options.has("alt"):
		_main.user_args.append("--alt=" + str(_options.alt))
	if _options.has("sky"):
		_main.user_args.append("--sky=" + str(_options.sky))
	for key: String in ["wind-speed", "wind-from", "gust-speed", "gust-up", "gust-duration", "gust-period", "gust-delay", "time_of_day"]:
		if _options.has(key):
			_main.user_args.append("--%s=%s" % [key, str(_options[key])])
	root.add_child(_main)
	# Hide only the presentation CanvasLayer before the real flight input starts; the incident ledger remains live.
	if _main._accident_report != null:
		_main._accident_report.visible = false
		_report_layer_hidden_before_impact = true
	await process_frame
	await RenderingServer.frame_post_draw
	if not _main.startup_error.is_empty() or _main.session == null or not _main.session.is_flyable():
		_failure = str(_main.startup_error)
		if _failure.is_empty() and _main.session != null:
			_failure = str(_main.session.start_error)
		push_error("Production flight startup failed: " + _failure)
		_write_manifest(false)
		quit(1)
		return
	if _main._accident_report == null:
		_failure = "Crash capture requires the native accident report CanvasLayer."
		push_error(_failure)
		_write_manifest(false)
		quit(1)
		return
	if not _report_layer_hidden_before_impact:
		_main._accident_report.visible = false
		_report_layer_hidden_before_impact = true
	if _main._panel != null:
		_main._panel.visible = _shot == "controls"
	if _main._hud != null:
		_main._hud.visible = _shot == "controls"
	if _shot != "lighting-pilot":
		_main._rig.set_view("chase")
		_main._rig.auto_zoom = false
		_main._camera.fov = 38.0
	var project_root: String = ProjectSettings.globalize_path("res://")
	var director_path: String = project_root.path_join("../tools/trailer/flight_director.gd").simplify_path()
	if _options.has("director-script"):
		director_path = str(_options["director-script"])
		if not director_path.is_absolute_path():
			_failure = "--director-script must be an absolute path"
			_write_manifest(false)
			quit(2)
			return
	var director_script: Script = load(director_path) as Script
	if director_script == null:
		_failure = "Could not load external flight director at " + director_path
		push_error(_failure)
		_write_manifest(false)
		quit(1)
		return
	_director = director_script.new()
	_director.name = "TrailerFlightDirector"
	_director.configure(_main, _shot, _seconds, _fps)
	root.add_child(_director)
	# Let the real world, interpolated airplane, particles, and camera finish one full presented interval.
	await process_frame
	await RenderingServer.frame_post_draw
	if _shot == "crash":
		await _capture_crash_report()
	else:
		await _capture_frames(int(round(_seconds * _fps)), 0)
	_write_manifest(_failure.is_empty())
	# Let production exit hooks dispose lighting, audio and scene-owned resources.
	# The director must stop first because its process callback reads the live scene.
	if is_instance_valid(_director):
		_director.free()
	if is_instance_valid(_main):
		_main.queue_free()
	await process_frame
	await process_frame
	quit(1 if not _failure.is_empty() else 0)


func _capture_crash_report() -> void:
	var preroll := 0
	while _main.session.crash.is_empty() and preroll < int(MAX_CRASH_PREROLL_S * _fps):
		await process_frame
		await RenderingServer.frame_post_draw
		preroll += 1
	if _main.session.crash.is_empty():
		_failure = "No physical crash occurred within %.1f s; no report clip was captured." % MAX_CRASH_PREROLL_S
		push_error(_failure)
		return
	_impact_preroll_frames = preroll
	# The movie writer runs from process launch. Retain a 2s approach plus 6s aftermath in the source,
	# so the editor can cut a truthful 8s beat around this actual impact. Restart is the final 2s.
	await _capture_frames(CRASH_CLIP_POST_IMPACT_FRAMES, preroll)


func _capture_frames(count: int, preroll: int) -> void:
	var previous_lighting_tick := -1
	var lighting_capture_requested := _lighting_capture_requested()
	for index: int in range(count):
		if _shot == "crash" and index == 60:
			# Let the viewer see the actual impact and wreck for one second before revealing the native report.
			_main._accident_report.visible = true
			_report_layer_reveal_frame = index
			if not _main.controller_action("details"):
				_failure = "Native accident report details action was unavailable at the scheduled reveal frame."
				push_error(_failure)
				return
			_details_frame = index
		if _shot == "crash" and index == CRASH_RESTART_AFTER_IMPACT_FRAMES:
			_preserved_report = _main._accident_incident.report.duplicate(true) if _main._accident_incident != null else {}
			_preserved_crash = _main.session.crash.duplicate(true)
			_preserved_prop_strike = _main.session.prop_strike.duplicate(true)
			_restart_tick_before = int(_main.session.sim.tick)
			_restart_frame = index
			_restart_movie_frame = int(_options.get("writer-lead-frames", 3)) + preroll + index
			_restart_result = bool(_main.controller_action("restart"))
			if not _restart_result:
				_failure = "Native accident report did not accept the restart action after the incident snapshot."
				push_error(_failure)
				return
			_restart_tick_after = int(_main.session.sim.tick)
			_director.resume_after_report_restart()
		await process_frame
		await RenderingServer.frame_post_draw
		if lighting_capture_requested:
			var sim: Node = _main.session.sim
			if sim.paused or not sim.fault_reason.is_empty() or not _main.session.crash.is_empty() \
					or (previous_lighting_tick >= 0 and sim.tick <= previous_lighting_tick):
				_failure = "Lighting capture interrupted: tick=%d paused=%s fault=%s holds=%s" % [
					sim.tick, sim.paused, sim.fault_reason, str(_main.session.holds)]
				push_error(_failure)
				return
			previous_lighting_tick = sim.tick
		var director_record_count_before := _director_frame_record_count() if lighting_capture_requested else -1
		_director.record_presented_frame(index, preroll)
		if lighting_capture_requested and not _ensure_lighting_frame_evidence(index, director_record_count_before):
			return
		_frame_count += 1
		if not _save_images:
			if index % _fps == 0:
				print("FLIGHT_CAPTURE_FRAME ", index, " tick=", _main.session.sim.tick)
			continue
		if index % _sample_every != 0 and index != count - 1:
			continue
		var image: Image = root.get_texture().get_image()
		if image.get_width() != _width or image.get_height() != _height:
			_failure = "Rendered frame size was %dx%d, expected %dx%d" % [image.get_width(), image.get_height(), _width, _height]
			push_error(_failure)
			return
		var frame_path := _out_dir.path_join("frame_%05d.png" % index)
		var save_error := image.save_png(frame_path)
		if save_error != OK:
			_failure = "Could not save frame %s: %s" % [frame_path, error_string(save_error)]
			push_error(_failure)
			return
		_image_count += 1
		if index % _fps == 0:
			print("FLIGHT_CAPTURE_FRAME ", index, " tick=", _main.session.sim.tick)


func _lighting_capture_requested() -> bool:
	return _options.has("lighting-preset") or _shot in ["lighting-pass", "lighting-pilot"]


func _director_frame_record_count() -> int:
	if not is_instance_valid(_director):
		return -1
	var records: Variant = _director.get("frame_records")
	return records.size() if typeof(records) == TYPE_ARRAY else -1


func _ensure_lighting_frame_evidence(frame_index: int, record_count_before: int) -> bool:
	if record_count_before < 0:
		return _lighting_capture_failure("Lighting capture director has no readable frame_records array.")
	var records: Variant = _director.get("frame_records")
	if typeof(records) != TYPE_ARRAY or records.size() != record_count_before + 1:
		return _lighting_capture_failure("Lighting capture director did not append exactly one record for frame %d." % frame_index)
	var record_index: int = records.size() - 1
	var record_value: Variant = records[record_index]
	if typeof(record_value) != TYPE_DICTIONARY:
		return _lighting_capture_failure("Lighting capture director's frame %d record is not a dictionary." % frame_index)
	var record: Dictionary = record_value
	if typeof(record.get("frame")) != TYPE_INT or int(record.frame) != frame_index:
		return _lighting_capture_failure("Lighting capture director's last record does not match frame %d." % frame_index)
	var current_tick: int = int(_main.session.sim.tick)
	if typeof(record.get("sim_tick")) != TYPE_INT or int(record.sim_tick) != current_tick:
		return _lighting_capture_failure("Lighting capture director's frame %d record does not match live tick %d." % [frame_index, current_tick])
	var lighting: Variant = _main.get("_rgb_lighting")
	if not is_instance_valid(lighting) or not lighting.has_method("budget_info"):
		return _lighting_capture_failure("Lighting capture has no live RGB lighting budget source.")
	var budget_value: Variant = lighting.call("budget_info")
	if typeof(budget_value) != TYPE_DICTIONARY or budget_value.is_empty():
		return _lighting_capture_failure("Lighting capture's live RGB budget information is missing or invalid.")
	var actual_exposure: float = Exposure.last
	if not is_finite(actual_exposure):
		return _lighting_capture_failure("Lighting capture's live world exposure is not finite.")
	if record.has("aircraft_lighting"):
		if typeof(record.aircraft_lighting) != TYPE_DICTIONARY or record.aircraft_lighting != budget_value:
			return _lighting_capture_failure("Frame %d records aircraft_lighting inconsistent with the live RGB budget." % frame_index)
	else:
		record["aircraft_lighting"] = budget_value.duplicate(true)
	if record.has("world_exposure"):
		var recorded_exposure: Variant = record.world_exposure
		if typeof(recorded_exposure) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(recorded_exposure)) \
				or float(recorded_exposure) != actual_exposure:
			return _lighting_capture_failure("Frame %d records world_exposure inconsistent with the live world exposure." % frame_index)
	else:
		record["world_exposure"] = actual_exposure
	records[record_index] = record
	_director.set("frame_records", records)
	return true


func _lighting_capture_failure(message: String) -> bool:
	_failure = message
	push_error(_failure)
	return false


func _write_manifest(ok: bool) -> void:
	var session: Node = _main.session if _main != null else null
	var current_report: Dictionary = _main._accident_incident.report.duplicate(true) if _main != null and _main._accident_incident != null else {}
	var report: Dictionary = _preserved_report if not _preserved_report.is_empty() else current_report
	var archive_path := str(_main.accident_archive_path) if _main != null else ""
	var lead_frames := int(_options.get("writer-lead-frames", 3))
	var impact_movie_frame := lead_frames + _impact_preroll_frames if _impact_preroll_frames >= 0 else -1
	var clip_start_frame := maxi(0, impact_movie_frame - CRASH_CLIP_APPROACH_FRAMES) if impact_movie_frame >= 0 else -1
	var manifest := {
		format = "openrc-trailer-flight-capture v1",
		complete = ok and _failure.is_empty(),
		shot = _shot,
		aircraft_id = str(_main.aircraft_id) if _main != null else "",
		width = _width,
		height = _height,
		fps = _fps,
		frames = _frame_count,
		images_saved = _image_count,
		image_sample_every = _sample_every,
		image_sequence_enabled = _save_images,
		movie_file = str(_options.get("movie-file", "")),
		movie_writer_lead_frames_expected = lead_frames,
		movie_writer_cleanup_frames_expected = 1,
		movie_impact_frame_estimate = impact_movie_frame,
		movie_eight_second_clip_start_frame_estimate = clip_start_frame,
		movie_eight_second_clip_end_frame_estimate_exclusive = impact_movie_frame + CRASH_CLIP_POST_IMPACT_FRAMES if impact_movie_frame >= 0 else -1,
		movie_clip_approach_available_seconds_estimate = float(impact_movie_frame - clip_start_frame) / float(_fps) if impact_movie_frame >= 0 else 0.0,
		movie_clip_approach_frames_target = CRASH_CLIP_APPROACH_FRAMES,
		movie_clip_post_impact_frames_target = CRASH_CLIP_POST_IMPACT_FRAMES,
		seconds = float(_frame_count) / float(_fps),
		engine = Engine.get_version_info().string,
		fixed_fps_argument_required = 60,
		physics_ticks_per_second = Engine.physics_ticks_per_second,
		physical_flight = session != null and session.physics_enabled and session.is_flyable(),
		simulation_paused = session.sim.paused if session != null else false,
		simulation_fault = session.sim.fault_reason if session != null else "",
		session_holds = session.holds.duplicate(true) if session != null else {},
		start_choice = str(session.start_choice) if session != null else "",
		soft_hull_contacts = bool(session.soft_hull_contacts) if session != null else false,
		sky_config = _main.sky_config.duplicate(true) if _main != null else {},
		world_conditions = WorldConditions.resolve(),
		field_world_lighting = bool(_main._field_world_lighting) if _main != null else false,
		lighting_config = _main.lighting_config.duplicate(true) if _main != null else {},
		lighting_preset = str(_options.get("lighting-preset", "inherit")),
		capture_script_sha256 = FileAccess.get_sha256(get_script().resource_path),
		director_script_sha256 = FileAccess.get_sha256(_director.get_script().resource_path) if is_instance_valid(_director) else "",
		main_source_sha256 = FileAccess.get_sha256("res://main.gd"),
		customization_registry_sha256 = FileAccess.get_sha256("res://data/aircraft_customization.json"),
		camera_preferences = _main.camera_preferences.duplicate(true) if _main != null else {},
		root_msaa_3d = root.msaa_3d,
		workshop_identity = session.workshop_identity.duplicate(true) if session != null else {},
		workshop_presentation_identity = session.workshop_presentation_identity.duplicate(true) if session != null else {},
		director_script = str(_options.get("director-script", "tools/trailer/flight_director.gd")),
		weather_config = session.weather_configuration() if session != null else {},
		flight_tick_end = int(session.sim.tick) if session != null else -1,
		flight_time_end_s = float(session.sim.time()) if session != null else 0.0,
		crash = _preserved_crash if not _preserved_crash.is_empty() else (session.crash.duplicate(true) if session != null and not session.crash.is_empty() else {}),
		prop_strike = _preserved_prop_strike if not _preserved_prop_strike.is_empty() else (session.prop_strike.duplicate(true) if session != null else {}),
		accident_report = report,
		incident_snapshot_preserved_before_restart = not _preserved_report.is_empty(),
		report_canvas_layer_hidden_before_impact = _report_layer_hidden_before_impact,
		report_canvas_layer_reveal_frame_after_impact = _report_layer_reveal_frame,
		native_report_details_expanded_frame = _details_frame,
		restart = {
			action = "native_accident_report_restart",
			accepted = _restart_result,
			capture_frame = _restart_frame,
			movie_frame_estimate = _restart_movie_frame,
			tick_before = _restart_tick_before,
			tick_immediately_after_reset = _restart_tick_after,
		},
		accident_archive_path = archive_path,
		capture_error = _failure,
		frame_records = _director.frame_records if _director != null else [],
		physics_ticks = _director.tick_records if _director != null else [],
	}
	var file := FileAccess.open(_out_dir.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write capture manifest")
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("FLIGHT_CAPTURE_MANIFEST ", _out_dir.path_join("manifest.json"))


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var options := {}
	for arg: String in arguments:
		if not arg.begins_with("--"):
			continue
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
	return options
