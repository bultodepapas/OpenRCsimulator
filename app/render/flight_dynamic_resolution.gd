extends RefCounted
## Flight viewport scale writer for the experimental completed-GPU-frame engine.

const Policy := preload("res://render/flight_resolution_policy.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
const TimingLease := preload("res://render/render_timing_lease.gd")
const MIN_SCALE_PERCENT := 75
const EXPERIMENT_FLAG := "--experimental-dynamic-resolution"
const SAMPLE_METHOD := &"viewport_get_completed_gpu_frame"
const SUPPORT_METHOD := &"viewport_supports_completed_gpu_frame"
const SAMPLE_TOGGLE_METHOD := &"viewport_set_completed_gpu_sampling"
const STATUS_META := &"openrc_flight_dynamic_resolution"

var _policy: RefCounted
var _lease := 0
var _fixed := 1.0
var _written := -1.0
var _reconstruction: Variant
var _flight_id := 0
var _target := 0
var _output := Vector2i.ZERO
var _scales: Array[float] = []
var _failed := false
var _restore_since := -1
var _restore_generation := -1
var _failure_reason := ""
var _confirmed_frame: Dictionary = {}


static func supports(viewport: Viewport) -> bool:
	if not EXPERIMENT_FLAG in OS.get_cmdline_user_args() \
			or DisplayServer.get_name() == "headless" or not is_instance_valid(viewport):
		return false
	return RenderingServer.has_method(SAMPLE_METHOD) and RenderingServer.has_method(SUPPORT_METHOD) \
		and RenderingServer.has_method(SAMPLE_TOGGLE_METHOD) \
		and bool(RenderingServer.call(SUPPORT_METHOD, viewport.get_viewport_rid()))


func tick(viewport: Viewport, flight_id: int, active: bool, config: Dictionary) -> void:
	var fps := int(config.get("dynamic_resolution_fps", 0))
	if flight_id == 0 or fps <= 0:
		stop(viewport)
		return
	if not active:
		if _lease != 0:
			_restore(viewport)
			_publish(viewport, "fixed_requested", "flight_suspended" if not _failed else _failure_reason)
		_flight_id = 0 # Next active frame opens a fresh evidence window.
		return
	var reconstruction: Variant = viewport.get_meta(Reconstruction.POLICY_META, null)
	var output := Reconstruction.viewport_output_size(viewport)
	if flight_id != _flight_id or fps != _target or output != _output or not is_same(reconstruction, _reconstruction):
		stop(viewport)
		_reconstruction = reconstruction
		_output = output
		_flight_id = flight_id
		_target = fps
		if not _begin(viewport):
			return
	if _restore_since >= 0:
		_verify_fixed(viewport)
		return
	if _failed or _policy == null:
		return
	if viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_BILINEAR \
			or not is_equal_approx(viewport.scaling_3d_scale, _fixed if _written < 0.0 else _written):
		_fail(viewport, "viewport_owner_changed")
		return
	var raw: Variant = RenderingServer.call(SAMPLE_METHOD, viewport.get_viewport_rid())
	var sample: Dictionary = raw if raw is Dictionary else {}
	if not sample.is_empty() and sample.get("output_size") != _output:
		sample = {}
	var next: int = _policy.observe(sample, Time.get_ticks_usec())
	if _policy.retired:
		_fail(viewport, _policy.reason)
		return
	if not sample.is_empty() and _policy.pending_level < 0 and sample.generation == _policy.generation \
			and sample.generation != _confirmed_frame.get("generation", -1):
		var input: Vector2i = sample.input_size
		_confirmed_frame = {frame_id = sample.frame_id, generation = sample.generation,
			input_size = [input.x, input.y], output_size = [_output.x, _output.y]}
	if next >= 0:
		_written = _scales[next]
		viewport.scaling_3d_scale = _written
		_publish(viewport, "apply_pending", _policy.reason)
	else:
		_publish(viewport, "apply_pending" if _policy.pending_level >= 0 else "observing", _policy.reason)


func stop(viewport: Viewport) -> void:
	if _lease != 0 or _policy != null:
		_restore(viewport)
	if is_instance_valid(viewport) and viewport.has_meta(STATUS_META):
		viewport.remove_meta(STATUS_META)
	_reconstruction = null
	_flight_id = 0
	_failed = false


func _begin(viewport: Viewport) -> bool:
	if not supports(viewport) or not _reconstruction is Dictionary or _reconstruction.get("provider") != "native" \
			or viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_BILINEAR:
		_publish(viewport, "fixed", "completed_gpu_source_unavailable")
		return false
	if Engine.max_fps > 0 and Engine.max_fps < _target:
		_publish(viewport, "fixed", "target_exceeds_frame_cap")
		return false
	var window := viewport as Window
	if window != null and DisplayServer.window_get_vsync_mode(window.get_window_id()) != DisplayServer.VSYNC_DISABLED:
		var refresh := DisplayServer.screen_get_refresh_rate(window.current_screen)
		if refresh > 0.0 and _target > ceili(refresh):
			_publish(viewport, "fixed", "target_exceeds_refresh_rate")
			return false
	_fixed = float(_reconstruction.get("scale", 0.0))
	if not is_equal_approx(viewport.scaling_3d_scale, _fixed):
		_publish(viewport, "fixed_unverified", "viewport_owner_changed")
		return false
	var ladder: Array[Vector2i] = []
	_scales.clear()
	var floor_scale := MIN_SCALE_PERCENT / 100.0
	var floor_size := Vector2i(ceili(_output.x * floor_scale), ceili(_output.y * floor_scale))
	for scale: float in [floor_scale, 0.85, _fixed]:
		# The server scales a Vector2 using its real_t precision and truncates per axis.
		var size := Vector2i(Vector2(_output) * scale)
		if scale > _fixed or size.x < floor_size.x or size.y < floor_size.y or size in ladder:
			continue
		ladder.append(size)
		_scales.append(scale)
	if ladder.size() < 2 or not is_equal_approx(_scales[-1], _fixed):
		_publish(viewport, "fixed", "no_legal_scale_range")
		return false
	_lease = TimingLease.acquire(viewport, "flight dynamic resolution")
	if _lease == 0:
		_publish(viewport, "fixed", "timing_unavailable")
		return false
	RenderingServer.call(SAMPLE_TOGGLE_METHOD, viewport.get_viewport_rid(), true)
	_policy = Policy.new(ladder, _target, Time.get_ticks_usec())
	_publish(viewport, "observing", "warming")
	return true


func _fail(viewport: Viewport, reason: String) -> void:
	_failed = true
	_failure_reason = reason
	if _owns_write(viewport):
		_restore_generation = _policy.generation
		_restore_since = Time.get_ticks_usec()
		viewport.scaling_3d_scale = _fixed
		_written = -1.0
		_policy = null
		_publish(viewport, "fixed_requested", reason)
	else:
		_restore(viewport)
		_publish(viewport, "fixed_unverified", reason)


func _verify_fixed(viewport: Viewport) -> void:
	var report: Variant = RenderingServer.call(SAMPLE_METHOD, viewport.get_viewport_rid())
	var now := Time.get_ticks_usec()
	var expected: Vector2i = Vector2i(Vector2(_output) * _fixed)
	var observed: bool = report is Dictionary and int(report.get("recorded_usec", -1)) > _restore_since \
		and int(report.get("generation", -1)) > _restore_generation \
		and report.get("input_size") == expected and report.get("output_size") == _output \
		and is_finite(float(report.get("gpu_usec", 0.0))) and float(report.get("gpu_usec", 0.0)) > 0.0
	if observed or now - _restore_since >= Policy.APPLY_TIMEOUT_USEC:
		_restore(viewport)
		_publish(viewport, "fixed" if observed else "fixed_unverified", _failure_reason)


func _owns_write(viewport: Viewport) -> bool:
	return _written >= 0.0 and is_instance_valid(viewport) \
			and is_same(viewport.get_meta(Reconstruction.POLICY_META, null), _reconstruction) \
			and viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR \
			and is_equal_approx(viewport.scaling_3d_scale, _written)


func _restore(viewport: Viewport) -> void:
	if _owns_write(viewport):
		viewport.scaling_3d_scale = _fixed
	if _lease != 0 and is_instance_valid(viewport):
		RenderingServer.call(SAMPLE_TOGGLE_METHOD, viewport.get_viewport_rid(), false)
	TimingLease.release(_lease)
	_lease = 0
	_policy = null
	_written = -1.0
	_restore_since = -1
	_confirmed_frame = {}


func _publish(viewport: Viewport, state: String, reason: String) -> void:
	var status := {state = state, reason = reason, target_fps = _target,
		configured_scale = viewport.scaling_3d_scale}
	if not _confirmed_frame.is_empty() and state == "observing":
		status.completed_frame = _confirmed_frame
	if status != viewport.get_meta(STATUS_META, {}):
		viewport.set_meta(STATUS_META, status)
