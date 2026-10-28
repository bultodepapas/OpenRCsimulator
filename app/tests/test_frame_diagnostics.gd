extends SceneTree

const FrameDiagnostics := preload("res://render/frame_diagnostics.gd")
const SAMPLE_KEYS: Array[String] = [
	"frame_setup_cpu_ms",
	"invalid_value_count",
	"memory_static_bytes",
	"orphan_node_count",
	"render_buffer_memory_bytes",
	"render_cpu_ms",
	"render_gpu_ms",
	"render_texture_memory_bytes",
	"render_video_memory_bytes",
	"resource_count",
]

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	await _run_checks()
	print("%d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _run_checks() -> void:
	var headless: bool = DisplayServer.get_name() == "headless"
	var expect_native: bool = "--native" in OS.get_cmdline_user_args()
	_check("requested native run has a native display", not expect_native or not headless, DisplayServer.get_name())
	_check("headless and macOS Compatibility timing exclusions are explicit", not FrameDiagnostics._timing_unavailable_reason("headless", "Windows", "forward_plus").is_empty() and not FrameDiagnostics._timing_unavailable_reason("macOS", "macOS", "gl_compatibility").is_empty() and FrameDiagnostics._timing_unavailable_reason("Windows", "Windows", "forward_plus").is_empty())
	var observer = FrameDiagnostics.new()
	_check("pre-start sample has stable finite schema", _sample_is_valid(observer.sample()), str(observer.sample()))
	_check("observer begins disabled", not observer.metadata().enabled, str(observer.metadata()))
	var invalid_probe = FrameDiagnostics.new()
	var invalid_values: Array = [NAN, INF, -1.0, "not numeric"]
	for invalid_value in invalid_values:
		var previous_invalid_count: int = invalid_probe.metadata().invalid_numeric_value_count
		var invalid_fallback: float = invalid_probe._finite_nonnegative(invalid_value)
		_check("invalid measurement becomes zero and is counted", invalid_fallback == 0.0 and invalid_probe.metadata().invalid_numeric_value_count == previous_invalid_count + 1, str(invalid_probe.metadata()))
	var root_viewport: Viewport = get_root()
	observer.start(root_viewport)
	var started: Dictionary = observer.metadata()
	_check("platform and presentation limits remain explicit", started.os_version == OS.get_version()
		and started.architecture == Engine.get_architecture_name() and started.metal_command_backend == "not_observed"
		and started.presentation_timing.contains("not_collected") and started.vsync_mode == DisplayServer.window_get_vsync_mode(), str(started))
	_check("diagnostics record main-view reconstruction", started.reconstruction_at_start.scale == root_viewport.scaling_3d_scale
		and started.reconstruction_at_start.msaa_3d == root_viewport.msaa_3d, str(started))
	var expected_timing_available: bool = FrameDiagnostics._timing_unavailable_reason(DisplayServer.get_name(), OS.get_name(), started.rendering_method).is_empty()
	_check("start records device identity and scope", started.enabled and started.started and started.cpu_model is String and started.rendering_method is String and started.render_cpu_scope is String, str(started))
	_check("timing availability is explicit for this display and renderer", started.render_timing_available == expected_timing_available and started.viewport_measurement_enabled == expected_timing_available, str(started))
	observer.start(root_viewport)
	_check("repeated start does not reset or duplicate polls", observer.metadata().gpu_polls_including_warmup == 0, str(observer.metadata()))
	var samples_valid: bool = true
	var observed_gpu_polls: int = 0
	var observed_positive_gpu_polls: int = 0
	for _i in 4:
		await process_frame
		var current: Dictionary = observer.sample()
		samples_valid = samples_valid and _sample_is_valid(current)
		if expected_timing_available:
			observed_gpu_polls += 1
			if current.render_gpu_ms > 0.0:
				observed_positive_gpu_polls += 1
	_check("active samples keep a stable finite schema", samples_valid, str(samples_valid))
	var before_stop: Dictionary = observer.metadata()
	_check("GPU polling counters match observations including warm-up", before_stop.gpu_polls_including_warmup == observed_gpu_polls and before_stop.gpu_positive_polls == observed_positive_gpu_polls, str(before_stop))
	_check("unavailable timing performs no GPU polls", expected_timing_available or before_stop.gpu_polls_including_warmup == 0, str(before_stop))
	_check("available native timing samples the GPU", not expected_timing_available or before_stop.gpu_polls_including_warmup > 0, str(before_stop))
	observer.stop()
	observer.stop()
	await process_frame
	var after_stop: Dictionary = observer.metadata()
	_check("stopped diagnostics retain final reconstruction", not expected_timing_available or
		after_stop.get("reconstruction_at_report", {}) == before_stop.get("reconstruction_at_report", {}), str(after_stop))
	var stopped_sample: Dictionary = observer.sample()
	_check("stop is idempotent and disables measurement", after_stop.stopped and not after_stop.active and not after_stop.viewport_measurement_enabled, str(after_stop))
	_check("stopped samples do not poll again", after_stop.gpu_polls_including_warmup == before_stop.gpu_polls_including_warmup and after_stop.gpu_positive_polls == before_stop.gpu_positive_polls, str(after_stop))
	_check("stopped sample retains finite schema", _sample_is_valid(stopped_sample), str(stopped_sample))
	_check("CPU and GPU readings stop after stop", stopped_sample.render_cpu_ms == 0.0 and stopped_sample.render_gpu_ms == 0.0 and stopped_sample.frame_setup_cpu_ms == 0.0, str(stopped_sample))
	await _test_viewport_is_not_retained(root_viewport)


func _test_viewport_is_not_retained(root_viewport: Viewport) -> void:
	var ephemeral: SubViewport = SubViewport.new()
	root_viewport.add_child(ephemeral)
	await process_frame
	var weak_viewport: WeakRef = weakref(ephemeral)
	var observer = FrameDiagnostics.new()
	observer.start(ephemeral)
	ephemeral.queue_free()
	ephemeral = null
	await process_frame
	await process_frame
	var resolved: Object = weak_viewport.get_ref()
	_check("observer does not retain its viewport node", not is_instance_valid(resolved), "viewport remains valid")
	var after_free_sample: Dictionary = observer.sample()
	var after_free_metadata: Dictionary = observer.metadata()
	_check("sampling after viewport deletion keeps finite schema", _sample_is_valid(after_free_sample), str(after_free_sample))
	_check("freed viewport is marked unavailable before another RID poll", not after_free_metadata.viewport_measurement_enabled and not after_free_metadata.render_timing_available, str(after_free_metadata))
	observer.stop()
	_check("stop after viewport deletion is safe", observer.metadata().stopped, str(observer.metadata()))


func _sample_is_valid(sample: Dictionary) -> bool:
	var expected: Array[String] = SAMPLE_KEYS.duplicate()
	var actual: Array = sample.keys()
	expected.sort()
	actual.sort()
	if actual != expected:
		return false
	for value in sample.values():
		if (typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT) or not is_finite(float(value)) or float(value) < 0.0:
			return false
	return true


func _check(label: String, success: bool, detail: String = "") -> void:
	_checks += 1
	if success:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL ", label, " ", detail)
