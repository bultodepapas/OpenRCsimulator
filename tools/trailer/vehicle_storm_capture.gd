## External SceneTree capture for the native electrical-storm presentation.
## Run with tmp/trailer/runtime/app as the project; does not edit app sources.
extends SceneTree

const MainScene := preload("res://main.gd")
const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const StormEvents := preload("res://environment/storm_events.gd")

const FPS := 60
const WIDTH := 1920
const HEIGHT := 1080
const DEFAULT_SECONDS := 4.0 # Keep an audio tail after the 3 s trailer insert.
const DEFAULT_SEED := 1253

var _options: Dictionary = {}
var _main: Node
var _director: Node
var _record_effect: AudioEffectRecord
var _environment_bus := -1
var _output_dir := ""
var _movie_file := ""
var _failure := ""
var _frame_count := 0
var _event: Dictionary = {}
var _selected_seed := DEFAULT_SEED


func _initialize() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	root.size = Vector2i(WIDTH, HEIGHT)
	root.msaa_3d = Viewport.MSAA_4X
	call_deferred("_run")


func _run() -> void:
	_options = _parse_options(OS.get_cmdline_user_args())
	if _options.has("probe"):
		_probe_schedules()
		quit(OK)
		return
	_output_dir = str(_options.get("out-dir", ""))
	_movie_file = str(_options.get("movie-file", ""))
	if _output_dir.is_empty() or _movie_file.is_empty() or not _output_dir.is_absolute_path() or not _movie_file.is_absolute_path():
		push_error("vehicle_storm_capture requires absolute --out-dir and --movie-file paths")
		quit(2)
		return
	var dir_error := DirAccess.make_dir_recursive_absolute(_output_dir)
	if dir_error != OK:
		push_error("Could not create storm capture directory: " + error_string(dir_error))
		quit(1)
		return
	var seconds := float(_options.get("seconds", DEFAULT_SECONDS))
	if seconds < 3.0 or seconds > 8.0:
		push_error("storm source duration must be between 3 and 8 seconds")
		quit(2)
		return
	_selected_seed = int(_options.get("seed", DEFAULT_SEED))
	TranslationServer.set_locale("en")
	var sky: Dictionary = SkyConfig.for_preset("electrical_storm")
	sky.seed = _selected_seed
	sky.flashes = "full"
	sky.thunder_volume = 0.7
	_main = MainScene.new()
	_main.name = "Main"
	_main.interactive_start = true
	_main.aircraft_id = str(_options.get("aircraft", "jensen-das-ugly-stik-60"))
	_main.start_choice = "airborne"
	_main.overlays_enabled = false
	_main.sky_config = sky
	_main.accident_archive_path = _output_dir.path_join("incident-%d.json" % Time.get_ticks_usec())
	_main.user_args = PackedStringArray([
		"--accident-report=off", "--crash-effects=off", "--failures=0", "--failure-seed=0",
	])
	root.add_child(_main)
	await process_frame
	await RenderingServer.frame_post_draw
	if not _main.startup_error.is_empty() or _main.session == null or not _main.session.is_flyable():
		_failure = str(_main.startup_error)
		if _failure.is_empty() and _main.session != null:
			_failure = str(_main.session.start_error)
		push_error("Production scene startup failed: " + _failure)
		_write_manifest(false, seconds)
		quit(1)
		return
	if _main._panel != null:
		_main._panel.visible = false
	if _main._hud != null:
		_main._hud.visible = false
	_main.session.input_enabled = false
	_main._airplane.root.visible = false
	_main._rig.set_view("pilot")
	_main._rig.auto_zoom = false
	_main._rig.look = Vector2(0.0, 0.0)
	_main._rig.look_height = 0.0
	_main._update_storm(0.0, false)
	_event = _event_for_selected_seed()
	if _event.is_empty():
		_failure = "Selected visual seed has no native strike in the opening 3 s. Run --probe, then pass --seed=<seed>."
		push_error(_failure)
		_write_manifest(false, seconds)
		quit(1)
		return
	var director_path: String = ProjectSettings.globalize_path("res://").path_join("../tools/trailer/vehicle_storm_director.gd").simplify_path()
	var director_script: Script = load(director_path) as Script
	if director_script == null:
		_failure = "Could not load external storm director at " + director_path
		push_error(_failure)
		_write_manifest(false, seconds)
		quit(1)
		return
	_director = director_script.new()
	_director.name = "NativeStormCamera"
	_director.configure(_main, _event, seconds, FPS, _options)
	root.add_child(_director)
	_environment_bus = AudioServer.get_bus_index("OpenRC Environment")
	if _environment_bus >= 0:
		_record_effect = AudioEffectRecord.new()
		AudioServer.add_bus_effect(_environment_bus, _record_effect)
		_record_effect.set_recording_active(true)
	else:
		print("STORM_AUDIO_BUS_MISSING; MovieMaker AVI will retain the normal game mix")
	await process_frame
	await RenderingServer.frame_post_draw
	var count := int(round(seconds * FPS))
	for index: int in range(count):
		await process_frame
		await RenderingServer.frame_post_draw
		_frame_count += 1
		_director.record_presented_frame(index)
		if index % FPS == 0:
			print("STORM_CAPTURE_FRAME ", index, " sim_time=", _main.session.sim.time(), " event=", _main._storm_fx.snapshot().event_id)
	if _record_effect != null:
		_record_effect.set_recording_active(false)
		_save_environment_wav()
	_write_manifest(true, seconds)
	quit(OK)


func _event_for_selected_seed() -> Dictionary:
	var events: Variant = _main._storm_fx.get("_events")
	if events == null:
		return {}
	var event_value: Variant = events.call("_event_for_slot", 0)
	return event_value if event_value is Dictionary else {}


func _probe_schedules() -> void:
	var wanted := int(_options.get("count", 8))
	var max_seed := int(_options.get("max-seed", 50000))
	var found := 0
	var default_event := {}
	for seed: int in range(max_seed + 1):
		var events := StormEvents.new()
		events.configure({"preset": "electrical_storm", "seed": seed, "tick_rate_hz": FPS})
		var candidates := events.events_for_window(0, int(3.0 * FPS))
		if seed == DEFAULT_SEED and not candidates.is_empty():
			default_event = candidates[0]
		if candidates.is_empty():
			continue
		var event: Dictionary = candidates[0]
		if str(event.get("kind", "")) != "cloud_to_ground":
			continue
		if float(event.get("start_time_s", 9.0)) > 1.75:
			continue
		print("STORM_SEED_CANDIDATE ", JSON.stringify({"seed": seed, "event": event}))
		found += 1
		if found >= wanted:
			break
	print("STORM_DEFAULT_SEED_1253 ", JSON.stringify(default_event))
	print("STORM_SEED_CANDIDATES_TOTAL ", found)


func _save_environment_wav() -> void:
	if _record_effect == null:
		return
	var recording: AudioStreamWAV = _record_effect.get_recording()
	if recording == null:
		_failure = "AudioEffectRecord returned no environment recording"
		return
	var wav_path := _output_dir.path_join("native-environment.wav")
	if not recording.has_method("save_to_wav"):
		_failure = "AudioStreamWAV lacks save_to_wav on this Godot build"
		return
	var save_error: int = int(recording.call("save_to_wav", wav_path))
	if save_error != OK:
		_failure = "Could not save native environment WAV: " + error_string(save_error)
	else:
		print("STORM_ENVIRONMENT_WAV ", wav_path)


func _write_manifest(ok: bool, seconds: float) -> void:
	var lightning: Dictionary = _main._storm_fx.snapshot() if _main != null and _main._storm_fx != null else {}
	var evidence: Dictionary = _main.capture_evidence() if _main != null and _main.session != null else {}
	var audio: Dictionary = {}
	if _main != null and _main._storm_fx != null:
		var storm_audio: Node = _main._storm_fx.get("_audio")
		if storm_audio != null:
			var players: Array = []
			for index: int in storm_audio._players.size():
				var player: AudioStreamPlayer3D = storm_audio._players[index]
				players.append({
					playing = player.playing,
					started_at_s = float(storm_audio._player_started_at[index]),
					volume_db = float(player.volume_db),
					bus = str(player.bus),
					position_world_m = _vector_array(player.global_position),
				})
			audio = {
				enabled = bool(storm_audio._enabled) and bool(storm_audio._audio_allowed),
				clip = "res://assets/audio/storm/thunder_01.ogg",
				pending = storm_audio._pending.duplicate(true),
				players = players,
				sound_speed_mps = float(storm_audio._sound_speed_mps),
				environment_bus = AudioServer.get_bus_name(_environment_bus) if _environment_bus >= 0 else "",
				wav_file = _output_dir.path_join("native-environment.wav") if _record_effect != null else "",
			}
	var manifest := {
		format = "openrc-trailer-storm-capture v1",
		complete = ok and _failure.is_empty(),
		shot = "native_electrical_storm_environment",
		camera_mode = str(_options.get("camera", "near-channel")),
		movie_file = _movie_file,
		movie_writer_lead_frames_expected = 3,
		width = WIDTH,
		height = HEIGHT,
		fps = FPS,
		frames = _frame_count,
		seconds = float(_frame_count) / FPS,
		engine = Engine.get_version_info().string,
		visual_seed = _selected_seed,
		storm_event = _event.duplicate(true),
		lightning_snapshot_end = lightning,
		native_game_audio = audio,
		physical_simulation = {
			unchanged_by_capture = true,
			physics_enabled = bool(_main.session.physics_enabled) if _main != null else false,
			flight_tick_start = int(_director.first_tick) if _director != null else -1,
			flight_tick_end = int(_main.session.sim.tick) if _main != null else -1,
			flight_time_start_s = float(_director.first_time_s) if _director != null else 0.0,
			flight_time_end_s = float(_main.session.sim.time()) if _main != null else 0.0,
			capture_focus_pause_resumes = int(_director.capture_focus_resumes) if _director != null else 0,
			flight_unpaused_at_end = not bool(_main.session.sim.paused) if _main != null else false,
			aircraft_render_hidden = true,
			presentation_camera_only = true,
		},
		visual_evidence = evidence,
		frame_records = _director.frame_records if _director != null else [],
		capture_error = _failure,
	}
	var file := FileAccess.open(_output_dir.path_join("manifest.json"), FileAccess.WRITE)
	if file == null:
		push_error("Could not write storm manifest")
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("STORM_CAPTURE_MANIFEST ", _output_dir.path_join("manifest.json"))


func _parse_options(arguments: PackedStringArray) -> Dictionary:
	var options := {}
	for argument: String in arguments:
		if not argument.begins_with("--"):
			continue
		var pair := argument.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2:
			options[pair[0]] = pair[1]
		else:
			options[pair[0]] = true
	return options


func _vector_array(value: Vector3) -> Array[float]:
	return [float(value.x), float(value.y), float(value.z)]
