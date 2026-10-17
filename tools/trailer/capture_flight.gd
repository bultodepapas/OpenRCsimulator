## Live production-flight frame capture for trailer source shots.
## Run outside the app scene: Godot --path app --fixed-fps 60 --script <absolute path> -- --out-dir=<absolute path>.
## This driver instantiates the real main scene and never changes app/ sources or physics.
extends SceneTree

const MainScene := preload("res://main.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")

const DEFAULT_FPS := 60
const DEFAULT_WIDTH := 1920
const DEFAULT_HEIGHT := 1080
const MAX_CRASH_PREROLL_S := 30.0

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
	_main.start_choice = "airborne"
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
	for key: String in ["wind-speed", "wind-from", "gust-speed", "gust-up", "gust-duration", "gust-period", "gust-delay"]:
		if _options.has(key):
			_main.user_args.append("--%s=%s" % [key, str(_options[key])])
	root.add_child(_main)
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
	if _main._panel != null:
		_main._panel.visible = _shot == "controls"
	if _main._hud != null:
		_main._hud.visible = _shot == "controls"
	_main._rig.set_view("chase")
	_main._rig.auto_zoom = false
	_main._camera.fov = 38.0
	var project_root: String = ProjectSettings.globalize_path("res://")
	var director_path: String = project_root.path_join("../tools/trailer/flight_director.gd").simplify_path()
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
	if _failure.is_empty():
		_write_manifest(true)
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
	# Begin the deliverable on the real impact; all saved frames then show the live crash/report aftermath.
	await _capture_frames(8 * _fps, preroll)


func _capture_frames(count: int, preroll: int) -> void:
	for index: int in range(count):
		await process_frame
		await RenderingServer.frame_post_draw
		_director.record_presented_frame(index, preroll)
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


func _write_manifest(ok: bool) -> void:
	var session: Node = _main.session if _main != null else null
	var report: Dictionary = _main._accident_incident.report.duplicate(true) if _main != null and _main._accident_incident != null else {}
	var archive_path := str(_main.accident_archive_path) if _main != null else ""
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
		movie_writer_lead_frames_expected = int(_options.get("writer-lead-frames", 3)),
		seconds = float(_frame_count) / float(_fps),
		engine = Engine.get_version_info().string,
		fixed_fps_argument_required = 60,
		physics_ticks_per_second = Engine.physics_ticks_per_second,
		physical_flight = session != null and session.physics_enabled and session.is_flyable(),
		start_choice = str(session.start_choice) if session != null else "",
		soft_hull_contacts = bool(session.soft_hull_contacts) if session != null else false,
		sky_config = _main.sky_config.duplicate(true) if _main != null else {},
		weather_config = session.weather_configuration() if session != null else {},
		flight_tick_end = int(session.sim.tick) if session != null else -1,
		flight_time_end_s = float(session.sim.time()) if session != null else 0.0,
		crash = session.crash.duplicate(true) if session != null and not session.crash.is_empty() else {},
		accident_report = report,
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
