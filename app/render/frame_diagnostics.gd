extends RefCounted
## Opt-in rendering and memory observations for one viewport.

const GPU_TIMING_NOTE := "GPU timing may be delayed; zero is ambiguous between unavailable and zero measured time."
const RENDER_MEMORY_NOTE := "Rendering memory values are engine estimates in bytes, not process RSS or free VRAM."
const STATIC_MEMORY_NOTE := "Godot static memory may be unavailable in release builds and can report zero."

var _started: bool = false
var _stopped: bool = false
var _headless: bool = false
var _measurement_enabled: bool = false
var _viewport_rid: RID
var _viewport_ref: WeakRef
var _gpu_poll_count: int = 0
var _positive_gpu_poll_count: int = 0
var _invalid_value_count: int = 0
var _sample_invalid_value_count: int = 0
var _metadata: Dictionary = {
	"format": "openrc-frame-diagnostics",
	"version": 1,
	"headless": false,
	"native_display": false,
	"display_server": "",
	"os_name": "",
	"render_timing_available": false,
	"render_timing_unavailable_reason": "not started",
	"viewport_scope": "provided viewport only",
	"render_cpu_scope": "Viewport rendering CPU only; excludes script and other engine CPU.",
	"frame_setup_cpu_scope": "Engine-wide rendering setup CPU time, shared across viewports.",
	"gpu_timing_note": GPU_TIMING_NOTE,
	"render_memory_note": RENDER_MEMORY_NOTE,
	"static_memory_note": STATIC_MEMORY_NOTE,
	"cpu_model": "",
	"cpu_logical_thread_count": 0,
	"adapter_name": "",
	"adapter_vendor": "",
	"adapter_api_version": "",
	"rendering_method": "",
	"rendering_driver": "",
}


func start(viewport: Viewport) -> void:
	if _started:
		return
	_started = true
	var display_server: String = DisplayServer.get_name()
	_headless = display_server == "headless"
	_metadata["headless"] = _headless
	_metadata["native_display"] = not _headless
	_metadata["display_server"] = display_server
	_metadata["os_name"] = OS.get_name()
	_metadata["cpu_model"] = OS.get_processor_name()
	_metadata["cpu_logical_thread_count"] = OS.get_processor_count()
	_metadata["adapter_name"] = RenderingServer.get_video_adapter_name()
	_metadata["adapter_vendor"] = RenderingServer.get_video_adapter_vendor()
	_metadata["adapter_api_version"] = RenderingServer.get_video_adapter_api_version()
	_metadata["rendering_method"] = RenderingServer.get_current_rendering_method()
	_metadata["rendering_driver"] = RenderingServer.get_current_rendering_driver_name()
	var unavailable_reason: String = _timing_unavailable_reason(display_server, _metadata["os_name"], _metadata["rendering_method"])
	if not unavailable_reason.is_empty():
		_metadata["render_timing_unavailable_reason"] = unavailable_reason
		return
	if not is_instance_valid(viewport):
		_metadata["render_timing_unavailable_reason"] = "provided viewport is no longer valid"
		return
	_metadata["render_timing_available"] = true
	_metadata["render_timing_unavailable_reason"] = ""
	_viewport_rid = viewport.get_viewport_rid()
	if not _viewport_rid.is_valid():
		_metadata["render_timing_available"] = false
		_metadata["render_timing_unavailable_reason"] = "provided viewport has no valid render RID"
		return
	_viewport_ref = weakref(viewport)
	RenderingServer.viewport_set_measure_render_time(_viewport_rid, true)
	_measurement_enabled = true


func sample() -> Dictionary:
	var result: Dictionary = _empty_sample()
	if not _started or _stopped:
		return result
	_sample_invalid_value_count = 0
	if _measurement_enabled:
		if _has_live_viewport():
			result["render_cpu_ms"] = _finite_nonnegative(RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid))
			var gpu_ms: float = _finite_nonnegative(RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid))
			result["render_gpu_ms"] = gpu_ms
			_gpu_poll_count += 1
			if gpu_ms > 0.0:
				_positive_gpu_poll_count += 1
			result["frame_setup_cpu_ms"] = _finite_nonnegative(RenderingServer.get_frame_setup_time_cpu())
		else:
			_measurement_enabled = false
			_metadata["render_timing_available"] = false
			_metadata["render_timing_unavailable_reason"] = "provided viewport was freed before sampling"
	result["memory_static_bytes"] = _monitor_value(Performance.MEMORY_STATIC)
	result["render_video_memory_bytes"] = _monitor_value(Performance.RENDER_VIDEO_MEM_USED)
	result["render_texture_memory_bytes"] = _monitor_value(Performance.RENDER_TEXTURE_MEM_USED)
	result["render_buffer_memory_bytes"] = _monitor_value(Performance.RENDER_BUFFER_MEM_USED)
	result["resource_count"] = _monitor_value(Performance.OBJECT_RESOURCE_COUNT)
	result["orphan_node_count"] = _monitor_value(Performance.OBJECT_ORPHAN_NODE_COUNT)
	result["invalid_value_count"] = _sample_invalid_value_count
	return result


func metadata() -> Dictionary:
	var result: Dictionary = _metadata.duplicate(true)
	result["enabled"] = _started
	result["started"] = _started
	result["active"] = _started and not _stopped
	result["stopped"] = _stopped
	result["viewport_measurement_enabled"] = _measurement_enabled
	result["gpu_polls_including_warmup"] = _gpu_poll_count
	result["gpu_positive_polls"] = _positive_gpu_poll_count
	result["invalid_numeric_value_count"] = _invalid_value_count
	return result


func stop() -> void:
	if not _started or _stopped:
		return
	_stopped = true
	if _measurement_enabled and _has_live_viewport():
		RenderingServer.viewport_set_measure_render_time(_viewport_rid, false)
	_measurement_enabled = false
	_metadata["viewport_measurement_enabled"] = false
	_viewport_ref = null
	_viewport_rid = RID()


func _empty_sample() -> Dictionary:
	return {
		"render_cpu_ms": 0.0,
		"render_gpu_ms": 0.0,
		"frame_setup_cpu_ms": 0.0,
		"memory_static_bytes": 0.0,
		"render_video_memory_bytes": 0.0,
		"render_texture_memory_bytes": 0.0,
		"render_buffer_memory_bytes": 0.0,
		"resource_count": 0.0,
		"orphan_node_count": 0.0,
		"invalid_value_count": 0,
	}


func _has_live_viewport() -> bool:
	if _viewport_ref == null or not _viewport_rid.is_valid():
		return false
	var viewport: Object = _viewport_ref.get_ref()
	return is_instance_valid(viewport)


static func _timing_unavailable_reason(display_server: String, os_name: String, rendering_method: String) -> String:
	if display_server == "headless":
		return "headless display has no viewport rendering timings"
	if os_name == "macOS" and rendering_method == "gl_compatibility":
		return "disabled conservatively because Godot documents Visual Profiler as unsupported on macOS with the Compatibility renderer"
	return ""


func _monitor_value(monitor: Performance.Monitor) -> float:
	return _finite_nonnegative(Performance.get_monitor(monitor))


func _finite_nonnegative(value: Variant) -> float:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		_sample_invalid_value_count += 1
		_invalid_value_count += 1
		return 0.0
	var number: float = float(value)
	if not is_finite(number) or number < 0.0:
		_sample_invalid_value_count += 1
		_invalid_value_count += 1
		return 0.0
	return number
