extends SceneTree

const Sound := preload("res://render/engine_sound.gd")
const DEFAULT_CYCLES := 50
const MAX_DRAIN_FRAMES := 120

var _fps_requested := 30
var _cycles := DEFAULT_CYCLES
var _driver_label := ""
var _out_path := ""
var _exit_before_drain := false
var _source_refs: Array[WeakRef] = []
var _playback_refs: Array[WeakRef] = []
var _parents: Array[Node3D] = []
var _failure := ""


func _initialize() -> void:
	_parse_user_args()
	_run.call_deferred()


func _parse_user_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fps="):
			_fps_requested = int(arg.trim_prefix("--fps="))
		elif arg.begins_with("--cycles="):
			_cycles = int(arg.trim_prefix("--cycles="))
		elif arg.begins_with("--driver="):
			_driver_label = arg.trim_prefix("--driver=")
		elif arg.begins_with("--out="):
			_out_path = arg.trim_prefix("--out=")
		elif arg == "--exit-before-drain":
			_exit_before_drain = true
	if _fps_requested not in [30, 60, 144]:
		_failure = "--fps must be 30, 60, or 144"
	if _cycles < 1 or _cycles > 50:
		_failure = "--cycles must be between 1 and 50"


func _run() -> void:
	if not _failure.is_empty():
		_write_and_quit({probe = "g3b-audio-lifecycle-stress", status = "failed", failure = _failure})
		return
	Engine.max_fps = _fps_requested
	get_root().audio_listener_enable_3d = true
	AudioServer.set_bus_mute(0, true)
	var camera := Camera3D.new()
	get_root().add_child(camera)
	camera.make_current()
	var listener := AudioListener3D.new()
	get_root().add_child(listener)
	listener.make_current()
	await process_frame
	await process_frame
	var baseline := _object_counts()
	for index in _cycles:
		var parent := Node3D.new()
		parent.position = Vector3(0.0, 0.0, -1.0)
		get_root().add_child(parent)
		_parents.append(parent)
		var player: AudioStreamPlayer3D = Sound.create(parent)
		var source_ref: WeakRef = weakref(player.stream)
		var playback: AudioStreamGeneratorPlayback = player.get_stream_playback() as AudioStreamGeneratorPlayback
		if playback == null:
			_failure = "AudioStreamGeneratorPlayback unavailable at cycle %d" % index
			parent.free()
			break
		_source_refs.append(source_ref)
		_playback_refs.append(weakref(playback))
		source_ref = null
		Sound.update(player, 0.0, 6000.0, 30000.0)
		playback = null
	# Let the mixer own all 50 active playback refs before tearing the nodes
	# down together. Four frames spans a Dummy driver's ~93 ms output burst.
	for _frame in 4:
		await process_frame
	var cycles_completed := _source_refs.size()
	var counts_before_free := _object_counts()
	var pin_violations_while_active := _pin_invariant_violations()
	for parent in _parents:
		parent.free()
	_parents.clear()
	var counts_immediate := _object_counts()
	var sources_immediate := _alive_count(_source_refs)
	var playbacks_immediate := _alive_count(_playback_refs)
	var pin_violations := _pin_invariant_violations()
	if _exit_before_drain:
		var early_result := {
			probe = "g3b-audio-lifecycle-stress",
			status = "ok" if pin_violations == 0 else "failed",
			interpretation = "Intentional immediate-quit diagnostic; pending playback/source weak refs are expected until the mixer processes stop fades.",
			fps_requested = _fps_requested,
			audio_driver_requested = _requested_audio_driver(),
			audio_driver_runtime = AudioServer.get_driver_name(),
			cycles_requested = _cycles,
			cycles_completed = _source_refs.size(),
			counts_before_free = counts_before_free,
			counts_immediately_after_free = counts_immediate,
			weakrefs_alive_immediately = {sources = sources_immediate, playbacks = playbacks_immediate},
			playback_alive_without_source_observations = pin_violations,
			exited_before_mixer_drain = true,
		}
		_source_refs.clear()
		_playback_refs.clear()
		_write_and_quit(early_result)
		return
	var drain_frames := 0
	while drain_frames < MAX_DRAIN_FRAMES and (_alive_count(_source_refs) > 0 or _alive_count(_playback_refs) > 0):
		await process_frame
		drain_frames += 1
		pin_violations = maxi(pin_violations, _pin_invariant_violations())
	var sources_after_drain := _alive_count(_source_refs)
	var playbacks_after_drain := _alive_count(_playback_refs)
	# Performance monitors can lag changes by up to one second; sample final
	# resource/object counts after dropping our WeakRef instrumentation and its
	# documented update window, so object totals do not count the probe itself.
	_source_refs.clear()
	_playback_refs.clear()
	for _frame in _fps_requested + 2:
		await process_frame
	var counts_final := _object_counts()
	var resource_delta: int = int(counts_final.resource_count) - int(baseline.resource_count)
	var object_delta: int = int(counts_final.object_count) - int(baseline.object_count)
	var node_delta: int = int(counts_final.node_count) - int(baseline.node_count)
	var result := {
		probe = "g3b-audio-lifecycle-stress",
		status = "ok" if _failure.is_empty() and sources_after_drain == 0 and playbacks_after_drain == 0 and pin_violations == 0 and resource_delta == 0 and node_delta == 0 else "failed",
		failure = _failure,
		interpretation = "AudioServer playback cleanup probe; Object/Resource counters are sampled after the mixer drain and monitor update window, not immediately on Node.free().",
		fps_requested = _fps_requested,
		audio_driver_requested = _requested_audio_driver(),
		audio_driver_runtime = AudioServer.get_driver_name(),
		cycles_requested = _cycles,
		cycles_completed = cycles_completed,
		baseline_object_counts = baseline,
		counts_before_free = counts_before_free,
		counts_immediately_after_free = counts_immediate,
		counts_after_mixer_drain = counts_final,
		resource_count_delta_after_drain = resource_delta,
		object_count_delta_after_drain = object_delta,
		node_count_delta_after_drain = node_delta,
		weakrefs_alive_immediately = {sources = sources_immediate, playbacks = playbacks_immediate},
		weakrefs_alive_after_drain = {sources = sources_after_drain, playbacks = playbacks_after_drain},
		playback_alive_without_source_observations = pin_violations,
		playback_alive_without_source_while_active = pin_violations_while_active,
		mixer_drain_frames = drain_frames,
		maximum_mixer_drain_frames = MAX_DRAIN_FRAMES,
	}
	_write_and_quit(result)


func _object_counts() -> Dictionary:
	return {
		object_count = int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		resource_count = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		node_count = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		orphan_node_count = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
	}


func _alive_count(refs: Array[WeakRef]) -> int:
	var count := 0
	for reference in refs:
		var instance: Object = reference.get_ref()
		if instance != null:
			count += 1
		instance = null
	return count


func _pin_invariant_violations() -> int:
	var violations := 0
	for index in mini(_source_refs.size(), _playback_refs.size()):
		var playback: Object = _playback_refs[index].get_ref()
		var playback_alive := playback != null
		playback = null
		if not playback_alive:
			continue
		var source: Object = _source_refs[index].get_ref()
		if source == null:
			violations += 1
		source = null
	return violations


func _requested_audio_driver() -> String:
	if not _driver_label.is_empty():
		return _driver_label
	for index in OS.get_cmdline_args().size():
		var args := OS.get_cmdline_args()
		if args[index] == "--audio-driver" and index + 1 < args.size():
			return str(args[index + 1])
		if args[index].begins_with("--audio-driver="):
			return args[index].trim_prefix("--audio-driver=")
	return "default"


func _write_and_quit(result: Dictionary) -> void:
	var json := JSON.stringify(result, "\t", true)
	print(json)
	if not _out_path.is_empty():
		var file := FileAccess.open(_out_path, FileAccess.WRITE)
		if file == null:
			printerr("Could not write audio lifecycle report: ", _out_path, " (", FileAccess.get_open_error(), ")")
		else:
			file.store_string(json + "\n")
			file.close()
	quit(0 if result.get("status", "failed") == "ok" else 1)
