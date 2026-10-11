# Optional warm CPU comparison for the old and G3b Sound.synthesize APIs.
# Run against either tree with:
# Godot_v4.7.2-stable_win64_console.exe --headless --path <tree>/app --script <this-file> -- --out=<json-path>
extends SceneTree

const Sound := preload("res://render/engine_sound.gd")
const VOICE_PATH := "res://render/engine_voice.gd"
const RATE := 22050.0
const FRAMES := 22050
const RUNS := 7
const RPM := 5100.0
const MAX_RPM := 11149.0
const AMPLITUDE := 0.5


func _median(values: Array[int]) -> float:
	values.sort()
	return float(values[values.size() / 2])


func _mono_stats(samples: PackedFloat32Array) -> Dictionary:
	var max_abs := 0.0
	var square_sum := 0.0
	var valid := samples.size() == FRAMES
	for value in samples:
		valid = valid and is_finite(value)
		max_abs = maxf(max_abs, absf(value))
		square_sum += float(value) * float(value)
	return {
		"sample_count": samples.size(),
		"max_abs": max_abs,
		"rms": sqrt(square_sum / maxf(float(samples.size()), 1.0)),
		"valid": valid,
	}


func _stereo_stats(samples: PackedVector2Array) -> Dictionary:
	var max_abs := 0.0
	var square_sum := 0.0
	var valid := samples.size() == FRAMES
	for value in samples:
		valid = valid and is_finite(value.x) and is_finite(value.y)
		max_abs = maxf(max_abs, maxf(absf(value.x), absf(value.y)))
		square_sum += float(value.x) * float(value.x) + float(value.y) * float(value.y)
	return {
		"frame_count": samples.size(),
		"max_abs": max_abs,
		"rms_per_channel": sqrt(square_sum / maxf(2.0 * float(samples.size()), 1.0)),
		"valid": valid,
	}


func _out_path() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with("--out="):
			return args[i].trim_prefix("--out=")
	return ""


func _measure_synthesis() -> Dictionary:
	# One untimed call warms script execution and (on the candidate) the lookup tables.
	Sound.synthesize(0.217, RPM / 60.0, AMPLITUDE, 256, RATE)
	var times: Array[int] = []
	var last_samples := PackedFloat32Array()
	for _run in RUNS:
		var start_usec := Time.get_ticks_usec()
		var result: Array = Sound.synthesize(0.217, RPM / 60.0, AMPLITUDE, FRAMES, RATE)
		var elapsed_usec := Time.get_ticks_usec() - start_usec
		times.append(elapsed_usec)
		last_samples = result[0]
	var median_usec := _median(times)
	var stats := _mono_stats(last_samples)
	stats["median_7_runs_usec"] = median_usec
	stats["median_usec_per_audio_second"] = median_usec / (float(FRAMES) / RATE)
	stats["frequency_hz"] = RPM / 60.0
	return stats


func _measure_runtime_render(voice_script: Script) -> Dictionary:
	# Warm static tables separately, outside the seven timed complete render blocks.
	var warm: Object = voice_script.new()
	warm.call("reset", RPM, MAX_RPM)
	warm.call("render", RPM, MAX_RPM, 256)
	var times: Array[int] = []
	var last_samples := PackedVector2Array()
	for _run in RUNS:
		var voice: Object = voice_script.new()
		voice.call("reset", RPM, MAX_RPM)
		var start_usec := Time.get_ticks_usec()
		last_samples = voice.call("render", RPM, MAX_RPM, FRAMES)
		var elapsed_usec := Time.get_ticks_usec() - start_usec
		times.append(elapsed_usec)
	var median_usec := _median(times)
	var stats := _stereo_stats(last_samples)
	stats["median_7_runs_usec"] = median_usec
	stats["median_usec_per_audio_second"] = median_usec / (float(FRAMES) / RATE)
	stats["frequency_hz"] = RPM / 60.0
	return stats


func _initialize() -> void:
	var voice_script: Script = load(VOICE_PATH) as Script if ResourceLoader.exists(VOICE_PATH) else null
	var initialize_usec := 0
	if voice_script != null:
		var before := Time.get_ticks_usec()
		voice_script.prepare()
		initialize_usec = Time.get_ticks_usec() - before
	var report := {
		"benchmark": "G3b warm engine voice CPU",
		"variant": "candidate" if voice_script != null else "baseline",
		"godot": Engine.get_version_info().string,
		"rate_hz": RATE,
		"runs": RUNS,
		"frames_per_run": FRAMES,
		"table_initialize_usec": initialize_usec,
		"measurement": "Elapsed wall time; warm medians exclude one-time table preparation.",
		"synthesis": _measure_synthesis(),
		"runtime_render": _measure_runtime_render(voice_script) if voice_script != null else {"available": false},
	}
	var rendered := JSON.stringify(report, "\t")
	var target := _out_path()
	if target.is_empty():
		print(rendered)
	else:
		var file := FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			printerr("could not write benchmark JSON to %s (error %d)" % [target, FileAccess.get_open_error()])
			quit(1)
			return
		file.store_string(rendered + "\n")
		print("wrote %s" % target)
	quit(0)
