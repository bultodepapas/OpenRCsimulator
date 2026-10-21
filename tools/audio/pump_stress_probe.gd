## Native stress probe for the bounded glow-audio worker. This is an audio presentation test,
## not a flight or physics validation.
## Usage: godot --path app --audio-driver WASAPI --script ../tools/audio/pump_stress_probe.gd -- [--out=<report.json>]
extends SceneTree

const Pump := preload("res://audio/glow_audio_pump.gd")
const Voice := preload("res://audio/glow_voice.gd")

const DEFAULT_OUTPUT_PATH := "res://../tmp/audio-aud15/pump-stress.json"
const REQUIRED_DRIVER_NAME := "WASAPI"
const EXPECTED_DURATION_S := 125.0
const DURATION_TOLERANCE_S := 0.12
const PRIME_TIMEOUT_S := 3.0
const CAPTURE_RING_SECONDS := 2.0
const GENERATOR_BUFFER_SECONDS := 0.2
const BUSY_STALL_SECONDS := 0.6
const BUSY_STALL_TOLERANCE_S := 0.02
const BUSY_STALL_PHASE_OFFSET_S := 1.0
const MAX_FPS := 60
const CAPTURE_BUS_INDEX := 0
const TELEMETRY := {
	"family": "glow_2t",
	"rpm": 7405.0,
	"max_rpm": 10000.0,
	"running": true,
	"firing_fraction": 1.0,
	"load": 0.55,
	"throttle": 0.55,
	"blade_count": 2,
}
const PHASE_DISTANCE_M: Array[float] = [3.0, 1250.0, 2100.0, 3.0, 2100.0]
const PHASE_GAIN_DB: Array[float] = [-20.0, -70.0, -92.0, -20.0, -92.0]

var _output_path := ""
var _argument_error := ""


func _initialize() -> void:
	Engine.max_fps = MAX_FPS
	_parse_args()
	call_deferred("_run")


func _parse_args() -> void:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var index := 0
	while index < user_args.size():
		var argument: String = user_args[index]
		if argument.begins_with("--out="):
			_output_path = argument.trim_prefix("--out=")
		elif argument == "--out":
			if index + 1 >= user_args.size():
				_argument_error = "--out needs a JSON path"
				break
			index += 1
			_output_path = user_args[index]
		index += 1
	if _output_path.is_empty():
		_output_path = ProjectSettings.globalize_path(DEFAULT_OUTPUT_PATH)
	elif not _output_path.is_absolute_path():
		_output_path = ProjectSettings.globalize_path("res://..").path_join(_output_path)


func _run() -> void:
	var report := _base_report()
	var scene := Node3D.new()
	root.add_child(scene)
	var listener := AudioListener3D.new()
	scene.add_child(listener)
	listener.make_current()
	var player := AudioStreamPlayer3D.new()
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.max_distance = 0.0
	player.max_db = 6.0
	player.pitch_scale = 0.9642
	player.attenuation_filter_db = 0.0
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = Voice.RATE
	generator.buffer_length = GENERATOR_BUFFER_SECONDS
	player.stream = generator
	scene.add_child(player)
	player.play()
	player.stream_paused = true
	var pump = Pump.new()
	var capture := AudioEffectCapture.new()
	capture.buffer_length = CAPTURE_RING_SECONDS
	var capture_effect_added := false
	var setup_error := ""
	if AudioServer.get_bus_count() <= CAPTURE_BUS_INDEX:
		setup_error = "AudioServer has no capture bus"
	else:
		AudioServer.add_bus_effect(CAPTURE_BUS_INDEX, capture)
		capture_effect_added = true
	var started := false
	if not _argument_error.is_empty():
		setup_error = _argument_error
	if setup_error.is_empty():
		started = pump.start(player.get_stream_playback(), TELEMETRY, Voice.RATE)
		if not started:
			setup_error = "GlowAudioPump.start failed"
	
	var prime_start_usec := Time.get_ticks_usec()
	var prime_elapsed_s := 0.0
	while setup_error.is_empty() and not pump.is_primed():
		prime_elapsed_s = float(Time.get_ticks_usec() - prime_start_usec) / 1000000.0
		if prime_elapsed_s >= PRIME_TIMEOUT_S or not pump.is_running():
			break
		await process_frame
	prime_elapsed_s = float(Time.get_ticks_usec() - prime_start_usec) / 1000000.0
	var prime_stats: Dictionary = pump.stats()
	var primed: bool = pump.is_primed()
	var worker_mode_ok := started and bool(prime_stats.get("running", false)) \
		and not bool(prime_stats.get("fallback", false))
	var prime_ok := primed and prime_elapsed_s <= PRIME_TIMEOUT_S and worker_mode_ok \
		and str(prime_stats.get("worker_error", "")).is_empty()
	report["driver"] = AudioServer.get_driver_name()
	report["prime_seconds"] = prime_elapsed_s
	report["prime_stats"] = prime_stats
	report["gates"] = {
		"native_driver": report.driver == REQUIRED_DRIVER_NAME,
		"worker_started_without_fallback": worker_mode_ok,
		"bounded_prime": primed and prime_elapsed_s <= PRIME_TIMEOUT_S,
		"worker_error_free_at_prime": str(prime_stats.get("worker_error", "")).is_empty(),
	}
	if not prime_ok or report.driver != REQUIRED_DRIVER_NAME:
		var preflight_failures: Array[String] = []
		if not setup_error.is_empty():
			preflight_failures.append(setup_error)
		if report.driver != REQUIRED_DRIVER_NAME:
			preflight_failures.append("required native driver is %s, got %s" % [REQUIRED_DRIVER_NAME, report.driver])
		if not prime_ok:
			preflight_failures.append("worker did not prime in bounded time without fallback/error")
		report["failures"] = preflight_failures
		report["passed"] = false
		report["preflight_failed"] = true
		report["post_join_stats"] = await _cleanup(pump, player, scene, capture, capture_effect_added)
		_write_and_exit(report, 1)
		return

	player.stream_paused = false
	capture.clear_buffer()
	var capture_start_usec := Time.get_ticks_usec()
	var captured_frames := 0
	var samples: Array[Dictionary] = []
	var busy_stalls: Array[Dictionary] = []
	var phase_seen: Array[bool] = [false, false, false, false, false]
	var last_second := -1
	var last_stall_phase := -1
	var cpu_accumulator := 0.1
	while true:
		var elapsed_s := float(Time.get_ticks_usec() - capture_start_usec) / 1000000.0
		if elapsed_s >= EXPECTED_DURATION_S:
			break
		var phase_index := mini(int(elapsed_s / 25.0), PHASE_DISTANCE_M.size() - 1)
		phase_seen[phase_index] = true
		player.position = Vector3(0.0, 0.0, -PHASE_DISTANCE_M[phase_index])
		player.volume_db = PHASE_GAIN_DB[phase_index]
		var available_frames: int = capture.get_frames_available()
		if available_frames > 0:
			captured_frames += capture.get_buffer(available_frames).size()
		if elapsed_s >= float(phase_index) * 25.0 + BUSY_STALL_PHASE_OFFSET_S \
				and last_stall_phase != phase_index:
			var stall_start_usec := Time.get_ticks_usec()
			while Time.get_ticks_usec() - stall_start_usec < int(BUSY_STALL_SECONDS * 1000000.0):
				cpu_accumulator = sin(cpu_accumulator + 0.0001)
			var stall_elapsed_s := float(Time.get_ticks_usec() - stall_start_usec) / 1000000.0
			busy_stalls.append({"phase": phase_index, "seconds": stall_elapsed_s})
			last_stall_phase = phase_index
		if int(elapsed_s) != last_second:
			var pump_stats: Dictionary = pump.stats()
			samples.append({
				"t": elapsed_s,
				"phase": phase_index,
				"captured_frames": captured_frames,
				"pcm_lag_ms": 1000.0 * (elapsed_s - float(captured_frames) / AudioServer.get_mix_rate()),
				"pump": pump_stats,
				"capture_discarded_frames": capture.get_discarded_frames(),
			})
			last_second = int(elapsed_s)
		await process_frame

	var wall_duration_s := float(Time.get_ticks_usec() - capture_start_usec) / 1000000.0
	var final_available_frames: int = capture.get_frames_available()
	if final_available_frames > 0:
		captured_frames += capture.get_buffer(final_available_frames).size()
	var mix_rate_hz: float = AudioServer.get_mix_rate()
	var pcm_duration_s := float(captured_frames) / mix_rate_hz if mix_rate_hz > 0.0 else 0.0
	var capture_discarded_frames: int = capture.get_discarded_frames()
	var final_stats: Dictionary = pump.stats()
	var phase_coverage_ok := true
	for phase_check_index: int in phase_seen.size():
		phase_coverage_ok = phase_coverage_ok and phase_seen[phase_check_index]
	var busy_stalls_ok := busy_stalls.size() == PHASE_DISTANCE_M.size()
	for stall_check_index: int in mini(busy_stalls.size(), PHASE_DISTANCE_M.size()):
		var stall: Dictionary = busy_stalls[stall_check_index]
		busy_stalls_ok = busy_stalls_ok and int(stall.get("phase", -1)) == stall_check_index \
			and absf(float(stall.get("seconds", NAN)) - BUSY_STALL_SECONDS) <= BUSY_STALL_TOLERANCE_S
	var wall_duration_ok := absf(wall_duration_s - EXPECTED_DURATION_S) <= DURATION_TOLERANCE_S
	var pcm_duration_ok := absf(pcm_duration_s - wall_duration_s) <= DURATION_TOLERANCE_S
	var final_source_identity: Dictionary = _source_identity()
	var initial_source_identity: Dictionary = report.get("source_identity", {})
	var gates := {
		"native_driver": AudioServer.get_driver_name() == REQUIRED_DRIVER_NAME,
		"wall_duration_within_120ms": wall_duration_ok,
		"captured_pcm_within_120ms_of_wall": pcm_duration_ok,
		"all_five_phases_seen": phase_coverage_ok,
		"five_600ms_busy_stalls": busy_stalls_ok,
		"worker_still_running_and_primed": bool(final_stats.get("running", false)) and bool(final_stats.get("primed", false)),
		"worker_did_not_fallback": not bool(final_stats.get("fallback", false)),
		"zero_generator_skips": false,
		"zero_capture_drops": capture_discarded_frames == 0,
		"no_worker_error": false,
		"source_hashes_present": _source_hashes_present(final_source_identity),
		"source_identity_unchanged": final_source_identity == initial_source_identity,
	}
	report["driver"] = AudioServer.get_driver_name()
	report["wall_seconds"] = wall_duration_s
	report["pcm_seconds"] = pcm_duration_s
	report["duration_error_s"] = pcm_duration_s - wall_duration_s
	report["captured_frames"] = captured_frames
	report["mix_rate_hz"] = mix_rate_hz
	report["final_stats"] = final_stats
	report["capture_discarded_frames"] = capture_discarded_frames
	report["output_latency_s"] = AudioServer.get_output_latency()
	report["samples"] = samples
	report["busy_stalls"] = busy_stalls
	report["phase_seen"] = phase_seen
	report["cpu_accumulator"] = cpu_accumulator
	report["final_source_identity"] = final_source_identity
	var post_join_stats: Dictionary = await _cleanup(pump, player, scene, capture, capture_effect_added)
	report["post_join_stats"] = post_join_stats
	gates["worker_did_not_fallback"] = not bool(final_stats.get("fallback", false)) \
		and not bool(post_join_stats.get("fallback", false))
	gates["zero_generator_skips"] = int(final_stats.get("skips", -1)) == 0 \
		and int(post_join_stats.get("skips", -1)) == 0
	gates["no_worker_error"] = str(final_stats.get("worker_error", "")).is_empty() \
		and str(post_join_stats.get("worker_error", "")).is_empty()
	var passed := true
	var failures: Array[String] = []
	for gate_name: String in gates:
		passed = passed and bool(gates[gate_name])
		if not bool(gates[gate_name]):
			failures.append(gate_name)
	report["gates"] = gates
	report["failures"] = failures
	report["passed"] = passed
	report["preflight_failed"] = false
	_write_and_exit(report, 0 if passed else 1)


func _base_report() -> Dictionary:
	return {
		"format": "openrc-glow-pump-stress-v1",
		"started_utc": Time.get_datetime_string_from_system(true, true),
		"expected_wall_seconds": EXPECTED_DURATION_S,
		"duration_tolerance_s": DURATION_TOLERANCE_S,
		"prime_timeout_s": PRIME_TIMEOUT_S,
		"capture_ring_seconds": CAPTURE_RING_SECONDS,
		"generator_buffer_seconds": GENERATOR_BUFFER_SECONDS,
		"required_driver": REQUIRED_DRIVER_NAME,
		"max_fps": MAX_FPS,
		"telemetry": TELEMETRY.duplicate(true),
		"phase_schedule": _phase_schedule(),
		"source_identity": _source_identity(),
	}


func _phase_schedule() -> Array[Dictionary]:
	var schedule: Array[Dictionary] = []
	for phase_index: int in PHASE_DISTANCE_M.size():
		schedule.append({
			"phase": phase_index,
			"start_s": float(phase_index) * 25.0,
			"duration_s": 25.0,
			"source_distance_m": PHASE_DISTANCE_M[phase_index],
			"player_volume_db": PHASE_GAIN_DB[phase_index],
			"busy_stall_at_phase_s": BUSY_STALL_PHASE_OFFSET_S,
			"busy_stall_duration_s": BUSY_STALL_SECONDS,
		})
	return schedule


func _source_identity() -> Dictionary:
	return {
		"probe_sha256": FileAccess.get_sha256("res://../tools/audio/pump_stress_probe.gd"),
		"pump_sha256": FileAccess.get_sha256("res://audio/glow_audio_pump.gd"),
		"voice_sha256": FileAccess.get_sha256("res://audio/glow_voice.gd"),
		"godot_version": str(Engine.get_version_info().get("string", "")),
		"generator_sample_rate_hz": Voice.RATE,
	}


func _source_hashes_present(identity: Dictionary) -> bool:
	return not str(identity.get("probe_sha256", "")).is_empty() \
		and not str(identity.get("pump_sha256", "")).is_empty() \
		and not str(identity.get("voice_sha256", "")).is_empty() \
		and not str(identity.get("godot_version", "")).is_empty()


func _cleanup(pump: Variant, player: AudioStreamPlayer3D, scene: Node3D,
		capture: AudioEffectCapture, capture_effect_added: bool) -> Dictionary:
	# Join the sole producer before touching the stream/player resources it owns.
	var joined_stats: Dictionary = {}
	if pump != null:
		pump.stop()
		joined_stats = pump.stats()
	if is_instance_valid(player):
		player.stop()
	# Let the driver finish any callback that still references the capture effect.
	await create_timer(0.1).timeout
	if capture_effect_added and AudioServer.get_bus_count() > CAPTURE_BUS_INDEX:
		var effects_count: int = AudioServer.get_bus_effect_count(CAPTURE_BUS_INDEX)
		for effect_index: int in effects_count:
			if AudioServer.get_bus_effect(CAPTURE_BUS_INDEX, effect_index) == capture:
				AudioServer.remove_bus_effect(CAPTURE_BUS_INDEX, effect_index)
				break
	if is_instance_valid(scene):
		scene.free()
	return joined_stats


func _write_and_exit(report: Dictionary, exit_code: int) -> void:
	report["finished_utc"] = Time.get_datetime_string_from_system(true, true)
	var output_directory: String = _output_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(output_directory):
		var mkdir_error: Error = DirAccess.make_dir_recursive_absolute(output_directory)
		if mkdir_error != OK:
			push_error("Could not create report directory: " + output_directory)
			quit(1)
			return
	var file := FileAccess.open(_output_path, FileAccess.WRITE)
	if file == null:
		push_error("Could not open pump stress report: " + _output_path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("PUMP STRESS: ", JSON.stringify({
		"passed": report.get("passed", false),
		"report": _output_path,
		"driver": report.get("driver", ""),
		"wall_seconds": report.get("wall_seconds", 0.0),
		"pcm_seconds": report.get("pcm_seconds", 0.0),
		"gates": report.get("gates", {}),
		"failures": report.get("failures", []),
	}))
	quit(exit_code)
