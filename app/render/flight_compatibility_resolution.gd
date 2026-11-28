extends RefCounted
## Compatibility fallback for the flight viewport. Intervals use the monotonic clock
## and the engine's draw counter. A step earns its place with a measured pacing gain.

const Reconstruction := preload("res://render/reconstruction.gd")
const STATUS_META := &"openrc_flight_dynamic_resolution"
const MIN_SCALE_PERCENT := 67
const _SAMPLE_COUNT := 60
const _SAMPLE_USEC := 2_000_000
const _SETTLE_USEC := 2_000_000
const _RECOVERY_DWELL_USEC := 12_000_000
const _RECOVERY_RETRY_USEC := 25_000_000
const _SLOW_RATIO := 1.05
const _HEADROOM_RATIO := 0.8
const _GAIN_RATIO := 0.95

var clock_usec := Callable(Time, "get_ticks_usec")
var draw_count := Callable(Engine, "get_frames_drawn")

var _viewport: WeakRef
var _flight_id := 0
var _target := 0
var _output := Vector2i.ZERO
var _reconstruction: Variant
var _status: Dictionary = {}
var _scales: Array[float] = []
var _level := 0
var _written := -1.0
var _parked := false
var _last_draw := -1
var _last_usec := -1
var _settle_until := 0
var _recover_after := 0
var _intervals := PackedInt64Array()
var _sampled_usec := 0
var _slow_windows := 0
var _fast_windows := 0
var _trial_from := -1
var _trial_reference_usec := 0.0


func tick(viewport: Viewport, flight_id: int, active: bool, config: Dictionary) -> void:
	var target := int(config.get("dynamic_resolution_fps", 0))
	if not is_instance_valid(viewport) or not active or flight_id == 0 or target <= 0:
		stop(viewport)
		return
	var reconstruction: Variant = viewport.get_meta(Reconstruction.POLICY_META, {})
	var output := Reconstruction.viewport_output_size(viewport)
	var now := int(clock_usec.call())
	if (
		_viewport == null or viewport != _viewport.get_ref() or flight_id != _flight_id
		or target != _target or output != _output or not is_same(reconstruction, _reconstruction)
	):
		stop(viewport)
		_viewport = weakref(viewport)
		_flight_id = flight_id
		_target = target
		_output = output
		_reconstruction = reconstruction
		_begin(viewport, now)
	if _parked:
		return
	if (
		viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_BILINEAR
		or not is_equal_approx(viewport.scaling_3d_scale, _scales[_level])
	):
		_written = -1.0
		_park(viewport, "viewport_owner_changed")
		return
	_sample(viewport, now)


func stop(_current_viewport: Viewport) -> void:
	var viewport := _viewport.get_ref() as Viewport if _viewport != null else null
	if is_instance_valid(viewport):
		if _owns_write(viewport):
			viewport.scaling_3d_scale = _scales[-1]
		if is_same(viewport.get_meta(STATUS_META, {}), _status):
			viewport.remove_meta(STATUS_META)
	_viewport = null
	_reconstruction = null
	_status = {}
	_scales.clear()
	_written = -1.0
	_parked = false
	_trial_from = -1
	_last_draw = -1
	_last_usec = -1
	_reset_window()


func _begin(viewport: Viewport, now: int) -> void:
	if (
		not _reconstruction is Dictionary or _reconstruction.get("provider") != "native"
		or viewport.scaling_3d_mode != Viewport.SCALING_3D_MODE_BILINEAR
	):
		_park(viewport, "native_bilinear_required")
		return
	if Engine.max_fps > 0 and Engine.max_fps < _target:
		_park(viewport, "target_exceeds_frame_cap")
		return
	var window := viewport as Window
	if window != null and DisplayServer.window_get_vsync_mode(window.get_window_id()) != DisplayServer.VSYNC_DISABLED:
		var refresh := DisplayServer.screen_get_refresh_rate(window.current_screen)
		if refresh > 0.0 and _target > ceili(refresh):
			_park(viewport, "target_exceeds_refresh_rate")
			return
	var ceiling := float(_reconstruction.get("scale", 0.0))
	if not is_equal_approx(viewport.scaling_3d_scale, ceiling):
		_park(viewport, "viewport_owner_changed")
		return
	var previous_size := Vector2i.ZERO
	for scale: float in [MIN_SCALE_PERCENT / 100.0, 0.75, 0.85, ceiling]:
		if scale > ceiling:
			continue
		var size := Vector2i(Vector2(_output) * scale)
		if size != previous_size and size.x > 0 and size.y > 0:
			_scales.append(scale)
			previous_size = size
	# If the ceiling shares the same input pixels as the preceding rung, retain the player's value.
	if not _scales.is_empty():
		_scales[-1] = ceiling
	if _scales.size() < 2:
		_park(viewport, "no_legal_scale_range")
		return
	_level = _scales.size() - 1
	_recover_after = now + _RECOVERY_DWELL_USEC
	_settle_until = now + _SETTLE_USEC
	_publish(viewport, "observing", "warming")


func _sample(viewport: Viewport, now: int) -> void:
	var drawn := int(draw_count.call())
	if drawn == _last_draw:
		return
	var contiguous := drawn == _last_draw + 1
	var interval := now - _last_usec
	_last_draw = drawn
	_last_usec = now
	if now < _settle_until or not contiguous:
		return
	var target_usec := 1_000_000.0 / _target
	# Discard pauses and shader/streaming stalls. They would skew both the trial and its reference.
	if interval < 1000 or interval > maxf(100_000.0, target_usec * 4.0):
		return
	_intervals.append(interval)
	_sampled_usec += interval
	if _intervals.size() < _SAMPLE_COUNT or _sampled_usec < _SAMPLE_USEC:
		return
	_intervals.sort()
	var p75 := float(_intervals[ceili(_intervals.size() * 0.75) - 1])
	_intervals.clear()
	_sampled_usec = 0
	_decide(viewport, now, p75, target_usec)


func _decide(viewport: Viewport, now: int, p75: float, budget: float) -> void:
	if _trial_from >= 0:
		var from := _trial_from
		_trial_from = -1
		if _level < from and p75 > _trial_reference_usec * _GAIN_RATIO:
			_apply(viewport, from, now, "no_measured_gain")
			_park(viewport, "no_measured_gain")
			return
		if _level > from and p75 > budget * _SLOW_RATIO:
			_apply(viewport, from, now, "recovery_no_headroom")
			_recover_after = now + _RECOVERY_RETRY_USEC
			return
		_publish(viewport, "observing", "trial_kept")
		return
	_slow_windows = _slow_windows + 1 if p75 > budget * _SLOW_RATIO else 0
	_fast_windows = _fast_windows + 1 if p75 < budget * _HEADROOM_RATIO else 0
	if _slow_windows >= 2 and _level > 0:
		_trial_from = _level
		_trial_reference_usec = p75
		_apply(viewport, _level - 1, now, "testing_lower_scale")
	elif _fast_windows >= 3 and _level < _scales.size() - 1 and now >= _recover_after:
		_trial_from = _level
		_apply(viewport, _level + 1, now, "testing_higher_scale")
	else:
		_publish(viewport, "observing", "scale_floor" if _level == 0 and _slow_windows >= 2 else "holding")


func _apply(viewport: Viewport, level: int, now: int, reason: String) -> void:
	_level = level
	viewport.scaling_3d_scale = _scales[level]
	_written = _scales[level]
	_settle_until = now + _SETTLE_USEC
	_recover_after = now + _RECOVERY_DWELL_USEC
	_reset_window()
	_publish(viewport, "observing", reason)


func _reset_window() -> void:
	_intervals.clear()
	_sampled_usec = 0
	_slow_windows = 0
	_fast_windows = 0


func _owns_write(viewport: Viewport) -> bool:
	return (
		_written >= 0.0 and is_same(viewport.get_meta(Reconstruction.POLICY_META, {}), _reconstruction)
		and viewport.scaling_3d_mode == Viewport.SCALING_3D_MODE_BILINEAR
		and is_equal_approx(viewport.scaling_3d_scale, _written)
	)


func _park(viewport: Viewport, reason: String) -> void:
	_parked = true
	_publish(viewport, "fixed", reason)


func _publish(viewport: Viewport, state: String, reason: String) -> void:
	var value := {state = state, reason = reason, target_fps = _target,
		configured_scale = viewport.scaling_3d_scale, source = "rendered_frame_interval"}
	if value != _status:
		_status = value
		viewport.set_meta(STATUS_META, _status)
