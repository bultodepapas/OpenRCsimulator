extends RefCounted
## Opt-in rendering and memory observations for one viewport.

const Reconstruction := preload("res://render/reconstruction.gd")
const TimingLease := preload("res://render/render_timing_lease.gd")

const GPU_TIMING_NOTE := "GPU timing may be delayed; zero is ambiguous between unavailable and zero measured time."
const RENDER_MEMORY_NOTE := "Rendering memory values are engine estimates in bytes, not process RSS or free VRAM."
const STATIC_MEMORY_NOTE := "Godot static memory may be unavailable in release builds and can report zero."
## Per-sample `render_gpu_status` codes (VQ-01c, graphics audit M0). FrameSamples stores only finite numbers with a
## fixed key set, so the status is an integer with this codebook in the metadata. No code means a fresh GPU result:
## the stock viewport getter returns a cached last reading with no completed-frame identity or age.
const GPU_STATUS_NOT_MEASURED := 0 ## timing unavailable, not started/stopped, or viewport gone
const GPU_STATUS_ZERO_AMBIGUOUS := 1 ## measured, reading is zero: unavailable or zero time
const GPU_STATUS_POSITIVE_UNVERIFIED := 2 ## positive cached reading; freshness and frame association unverified
const GPU_STATUS_INVALID := 3 ## non-finite or negative reading, recorded as 0.0 ms
const GPU_STATUS_CODEBOOK := {
	"0": "not_measured",
	"1": "zero_ambiguous",
	"2": "positive_freshness_unverified",
	"3": "invalid_reading",
}

var _started: bool = false
var _stopped: bool = false
var _headless: bool = false
var _measurement_enabled: bool = false
var _timing_lease: int = 0
var _viewport_rid: RID
var _viewport_ref: WeakRef
var _gpu_poll_count: int = 0
var _positive_gpu_poll_count: int = 0
var _invalid_value_count: int = 0
var _sample_invalid_value_count: int = 0
var _metadata: Dictionary = {
	"format": "openrc-frame-diagnostics",
	"version": 2,
	"render_gpu_status_codebook": GPU_STATUS_CODEBOOK,
	"render_gpu_freshness": "unverified: no completed render identity or sample age is exposed by the viewport timer",
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
	_metadata["os_version"] = OS.get_version()
	_metadata["architecture"] = Engine.get_architecture_name()
	_metadata["vsync_mode"] = DisplayServer.window_get_vsync_mode()
	_metadata["max_fps"] = Engine.max_fps
	# A Metal API string or macOS version does not prove MTL3/MTL4 command submission.
	_metadata["metal_command_backend"] = "not_observed"
	_metadata["presentation_timing"] = "not_collected; viewport timers and process intervals are not presentation timestamps"
	_metadata["cpu_model"] = OS.get_processor_name()
	_metadata["cpu_logical_thread_count"] = OS.get_processor_count()
	_metadata["adapter_name"] = RenderingServer.get_video_adapter_name()
	_metadata["adapter_vendor"] = RenderingServer.get_video_adapter_vendor()
	_metadata["adapter_api_version"] = RenderingServer.get_video_adapter_api_version()
	_metadata["rendering_method"] = RenderingServer.get_current_rendering_method()
	_metadata["rendering_driver"] = RenderingServer.get_current_rendering_driver_name()
	if is_instance_valid(viewport):
		_metadata["viewport_size"] = [viewport.get_visible_rect().size.x, viewport.get_visible_rect().size.y]
		_metadata["viewport_size_scope"] = "viewport coordinates; native drawable pixels require platform verification"
		_metadata["reconstruction_at_start"] = Reconstruction.describe(viewport)
	var unavailable_reason: String = _timing_gate(display_server, _metadata["os_name"], _metadata["rendering_method"])
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
	# Shared with other consumers of this viewport (debug bridge probe, ablation): stopping one cannot switch
	# timing off under another.
	_timing_lease = TimingLease.acquire(viewport, "frame_diagnostics")
	if _timing_lease == 0:
		_metadata["render_timing_available"] = false
		_metadata["render_timing_unavailable_reason"] = "viewport measurement lease unavailable"
		return
	_metadata["render_timing_owner"] = "shared viewport lease"
	_metadata["render_timing_other_owners_at_start"] = TimingLease.owners(viewport).size() - 1
	_measurement_enabled = true


func sample() -> Dictionary:
	var result: Dictionary = _empty_sample()
	if not _started or _stopped:
		return result
	_sample_invalid_value_count = 0
	if _measurement_enabled:
		if _has_live_viewport():
			result["render_cpu_ms"] = _finite_nonnegative(RenderingServer.viewport_get_measured_render_time_cpu(_viewport_rid))
			var invalid_before: int = _sample_invalid_value_count
			var gpu_ms: float = _finite_nonnegative(RenderingServer.viewport_get_measured_render_time_gpu(_viewport_rid))
			result["render_gpu_ms"] = gpu_ms
			result["render_gpu_status"] = gpu_status_code(gpu_ms, _sample_invalid_value_count != invalid_before)
			_gpu_poll_count += 1
			if gpu_ms > 0.0:
				_positive_gpu_poll_count += 1
			result["frame_setup_cpu_ms"] = _finite_nonnegative(RenderingServer.get_frame_setup_time_cpu())
		else:
			_measurement_enabled = false
			TimingLease.release(_timing_lease)
			_timing_lease = 0
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
	if _has_live_viewport():
		result["reconstruction_at_report"] = Reconstruction.describe(_viewport_ref.get_ref())
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
	if _has_live_viewport():
		_metadata["reconstruction_at_report"] = Reconstruction.describe(_viewport_ref.get_ref())
	# Turns the engine flag off only when no other consumer still holds this viewport; a freed viewport's RID is
	# never written.
	TimingLease.release(_timing_lease)
	_timing_lease = 0
	_measurement_enabled = false
	_metadata["viewport_measurement_enabled"] = false
	_viewport_ref = null
	_viewport_rid = RID()


func _empty_sample() -> Dictionary:
	return {
		"render_cpu_ms": 0.0,
		"render_gpu_ms": 0.0,
		"render_gpu_status": GPU_STATUS_NOT_MEASURED,
		"frame_setup_cpu_ms": 0.0,
		"memory_static_bytes": 0.0,
		"render_video_memory_bytes": 0.0,
		"render_texture_memory_bytes": 0.0,
		"render_buffer_memory_bytes": 0.0,
		"resource_count": 0.0,
		"orphan_node_count": 0.0,
		"invalid_value_count": 0,
	}


## Status code for one measured poll; `invalid` means the raw reading was replaced by 0.0.
static func gpu_status_code(gpu_ms: float, invalid: bool) -> int:
	if invalid:
		return GPU_STATUS_INVALID
	return GPU_STATUS_POSITIVE_UNVERIFIED if gpu_ms > 0.0 else GPU_STATUS_ZERO_AMBIGUOUS


func _has_live_viewport() -> bool:
	if _viewport_ref == null or not _viewport_rid.is_valid():
		return false
	var viewport: Object = _viewport_ref.get_ref()
	return is_instance_valid(viewport)


## Instance seam over the static policy so headless tests can exercise the timing-lease wiring.
func _timing_gate(display_server: String, os_name: String, rendering_method: String) -> String:
	return _timing_unavailable_reason(display_server, os_name, rendering_method)


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
