extends SceneTree

const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const Reference := preload("res://reference/atmosphere.gd")
const Candidate := preload("res://render/atmosphere.gd")
const PRESETS: Array[String] = ["classic", "prestorm"]
const SAMPLE_COUNT := 5
const DEFAULT_ITERATIONS := 30000
const DEFAULT_WARMUP := 1500
const SIM_FPS := 60.0

var _reference_environment: Environment
var _candidate_environment: Environment
var _observed_checksum := 0.0


func _initialize() -> void:
	var iterations := _int_argument("cloud-candidate-iterations", DEFAULT_ITERATIONS)
	var warmup := _int_argument("cloud-candidate-warmup", DEFAULT_WARMUP)
	if iterations < 1000 or warmup < 0:
		printerr("cloud candidate benchmark requires iterations >= 1000 and warmup >= 0")
		quit(2)
		return
	for preset_id: String in PRESETS:
		_measure_preset(preset_id, iterations, warmup)
	print("checksum=%.3f" % _observed_checksum)
	quit(0)


func _measure_preset(preset_id: String, iterations: int, warmup: int) -> void:
	var selection: Dictionary = SkyConfig.for_preset(preset_id)
	if selection.is_empty():
		printerr("unknown benchmark preset: %s" % preset_id)
		quit(2)
		return
	for include_snapshot: bool in [false, true]:
		_prepare_pair(preset_id)
		_benchmark_reference(warmup, SIM_FPS, include_snapshot)
		_prepare_pair(preset_id)
		_benchmark_candidate(warmup, SIM_FPS, include_snapshot)
		var reference_samples: Array[int] = []
		var candidate_samples: Array[int] = []
		for sample_index in SAMPLE_COUNT:
			_prepare_pair(preset_id)
			if sample_index % 2 == 0:
				reference_samples.append(_benchmark_reference(iterations, SIM_FPS, include_snapshot))
				_prepare_pair(preset_id)
				candidate_samples.append(_benchmark_candidate(iterations, SIM_FPS, include_snapshot))
			else:
				candidate_samples.append(_benchmark_candidate(iterations, SIM_FPS, include_snapshot))
				_prepare_pair(preset_id)
				reference_samples.append(_benchmark_reference(iterations, SIM_FPS, include_snapshot))
		var reference_median := _median(reference_samples)
		var candidate_median := _median(candidate_samples)
		var workload := "update+snapshot" if include_snapshot else "update-only"
		var delta_percent := (float(candidate_median) / maxf(float(reference_median), 1.0) - 1.0) * 100.0
		print("preset=%s layers=%d workload=%s iterations=%d fps=%.0f ref_median_us=%d candidate_median_us=%d delta_percent=%.1f"
			% [preset_id, int(SkyConfig.validate(selection).profile.renderer.cloud_layers.size()), workload,
				iterations, SIM_FPS, reference_median, candidate_median, delta_percent])


func _prepare_pair(preset_id: String) -> void:
	var selection: Dictionary = SkyConfig.for_preset(preset_id)
	selection["seed"] = 4703
	selection["motion"] = "follow_wind"
	var mean_wind := [7.0, -3.0, 0.4]
	if not Reference.configure_appearance(selection, mean_wind, 0.0):
		printerr("reference rejected benchmark appearance: %s" % preset_id)
		quit(2)
		return
	# Both scripts share the process-wide RenderingServer global parameter in this probe.
	Candidate._cloud_registered = Reference._cloud_registered
	if not Candidate.configure_appearance(selection, mean_wind, 0.0):
		printerr("candidate rejected benchmark appearance: %s" % preset_id)
		quit(2)
		return
	_reference_environment = Reference.environment()
	_candidate_environment = Candidate.environment()


func _benchmark_reference(iterations: int, fps: float, include_snapshot: bool) -> int:
	var checksum := 0.0
	var started := Time.get_ticks_usec()
	for frame_index in iterations:
		Reference.update_clouds(_reference_environment, float(frame_index) / fps)
		if include_snapshot:
			var snapshot: Dictionary = Reference.cloud_state_snapshot()
			checksum += _snapshot_value(snapshot)
	_observed_checksum += checksum
	return Time.get_ticks_usec() - started


func _benchmark_candidate(iterations: int, fps: float, include_snapshot: bool) -> int:
	var checksum := 0.0
	var started := Time.get_ticks_usec()
	for frame_index in iterations:
		Candidate.update_clouds(_candidate_environment, float(frame_index) / fps)
		if include_snapshot:
			var snapshot: Dictionary = Candidate.cloud_state_snapshot()
			checksum += _snapshot_value(snapshot)
	_observed_checksum += checksum
	return Time.get_ticks_usec() - started


func _snapshot_value(snapshot: Dictionary) -> float:
	var offset: Vector2 = snapshot.offset
	return float(snapshot.cloud_layers.size()) + offset.x + offset.y


func _median(samples: Array[int]) -> int:
	var ordered := samples.duplicate()
	ordered.sort()
	return ordered[ordered.size() / 2]


func _int_argument(name: String, fallback: int) -> int:
	var prefix := "--%s=" % name
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			if argument.trim_prefix(prefix).is_valid_int():
				return argument.trim_prefix(prefix).to_int()
	return fallback
