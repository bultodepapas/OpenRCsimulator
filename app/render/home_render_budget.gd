extends Node
## VQ-07h I2: holds Home at the display refresh by lowering its 3D resolution only when Home misses it.
##
## Home is the most expensive screen: its low view fills the frame with shaded ground. At 4K with every option
## on, an RTX 3090 needs 8.5 ms of GPU per Home frame (refresh budget 8.3 ms), and an M1 at 1080p runs Home at
## 51 fps with product defaults; half resolution removed 62 % of Home's GPU time. This child of the Home scene
## measures frame intervals in rolling windows while Home is the focused top screen. After two consecutive slow
## windows (median above the refresh interval, or more than 15 % of frames far above it, as VSync shows a miss)
## it steps the viewport's 3D scale down (x0.85, then x0.7 of the player's scale). A step that does not cut the
## mean interval means pixels are no longer the limit: the previous step returns (the player's scale after a
## first step) and the budget stops for this visit. On an M1 at product defaults, x0.85 took Home from 51 to
## 58-59 fps at 60 Hz.
##
## Ownership is narrow. It acts only on native (bilinear) and FSR 1 scaling, never on temporal reconstruction.
## It owns the scale only while the viewport holds the value it wrote under the same reconstruction policy
## (Reconstruction.apply writes a new policy object every time), so Settings, a resize or any other writer takes
## the viewport back and is never overwritten. A screen over Home, focus loss or minimising restores the
## player's scale; uncovering Home under the same player setting re-applies the step already kept, without a
## new measurement. Leaving Home forgets everything. Flight never sees the override.

const Reconstruction := preload("res://render/reconstruction.gd")
const STEPS := [1.0, 0.85, 0.7]
const SETTLE_FRAMES := 90 # discarded after a start or a scale change: pipelines and streaming settle
const SAMPLE_FRAMES := 90
const SLOW_RATIO := 1.08 # a median interval above the refresh interval by more than this misses it
const MISS_RATIO := 1.25 # under VSync a missed refresh shows as a frame far above the interval...
# ...and more than 15 % of such frames also misses it, whatever the median says. An M1 Home keeps 5-9 % of
# misses that a lower scale does not remove (not GPU work), so a lower share would chase them.
const MISS_SHARE := 0.15
const GAIN_RATIO := 0.95 # a step must cut the mean interval by at least 5 % to count as pixel-bound
const OUTLIER_RATIO := 4.0 # a frame this far above the target (a stall or a pause) is not a GPU measurement
const OUTLIER_MS := 100.0
const MIN_TARGET_MS := 1000.0 / 240.0 # never chase refresh rates above 240 Hz
const META := &"home_render_budget"

## True while Home is the visible top screen. Default: AppRoot's screen stack has "home" on top.
var may_adjust: Callable = _home_is_top
## True while the window can show Home: focused and not minimised.
var window_active: Callable = _window_is_active
## Target frame interval in ms. Default: the display refresh (or a lower frame cap).
var target_interval_ms: Callable = _refresh_interval_ms
var clock_usec: Callable = func() -> int: return Time.get_ticks_usec()

var _state := "idle" # idle | settle | sample | stopped (no further steps this visit) | covered
var _base_scale := 1.0
var _base_policy: Variant = null # the reconstruction policy object the player's scale came with
var _step := 0
var _done := false # the last decision ended stepping for this visit (no gain or floor)
var _set_scale := -1.0 # the value this budget wrote; -1 = not owning the viewport scale
var _owned_policy: Variant = null
var _frames := 0
var _intervals: PackedFloat64Array = PackedFloat64Array()
var _last_usec := 0
var _previous_mean := 0.0
var _judging := false # the first window after a step decides whether the step bought anything
var _slow_windows := 0 # consecutive slow windows; two are needed, so a loading spike never costs resolution


func _ready() -> void:
	process_priority = 1000 # after Home's own frame work


func _exit_tree() -> void:
	# Leaving Home (flight start, a vehicle route, a rebuild): restore and forget this visit entirely.
	_restore(get_viewport() if is_inside_tree() else null)
	_forget()
	_state = "idle"
	_last_usec = 0


func _process(_delta: float) -> void:
	var now: int = int(clock_usec.call())
	var interval := (now - _last_usec) / 1000.0 if _last_usec > 0 else 0.0
	_last_usec = now
	var viewport := get_viewport()
	if viewport == null:
		return
	if not bool(may_adjust.call()) or not bool(window_active.call()) or not _supported_mode(viewport):
		if _state != "idle" and _state != "covered":
			_restore(viewport)
			_state = "covered" # keep this visit's decision for when Home is shown again
		return
	if _set_scale >= 0.0 and not _owns(viewport):
		# Settings, a resize or another writer applied a value: it owns the viewport now; measure again from it.
		_set_scale = -1.0
		_state = "idle"
	if _state == "covered":
		_uncover(viewport)
		return
	if _state == "idle":
		_begin(viewport)
		return
	if _state == "stopped":
		return
	_frames += 1
	if _state == "settle":
		if _frames >= SETTLE_FRAMES:
			_restart("sample")
		return
	var target: float = float(target_interval_ms.call())
	if interval <= 0.0 or interval > maxf(OUTLIER_RATIO * target, OUTLIER_MS):
		return
	_intervals.append(interval)
	if _intervals.size() < SAMPLE_FRAMES:
		return
	_decide(viewport, _intervals, target)


func _decide(viewport: Viewport, intervals: PackedFloat64Array, target: float) -> void:
	var median := _median(intervals)
	var mean := 0.0
	var missed := 0
	for value in intervals:
		mean += value
		if target > 0.0 and value > target * MISS_RATIO:
			missed += 1
	mean /= intervals.size()
	var miss_share := float(missed) / intervals.size()
	var slow := target > 0.0 and (median > target * SLOW_RATIO or miss_share > MISS_SHARE)
	if _judging:
		_judging = false
		if mean > _previous_mean * GAIN_RATIO:
			# The last step bought nothing: return to the previous step (the player's scale if this was the
			# first) and stop for this visit. Earlier steps that did speed Home up are kept.
			_step -= 1
			_apply(viewport, _base_scale * float(STEPS[_step]))
			_stop(viewport, median, miss_share, "not pixel-bound" if _step == 0 else "no further gain")
			return
	# Keep watching in rolling windows: Home can grow heavier after it first appears (preview, streaming).
	_slow_windows = _slow_windows + 1 if slow else 0
	if _slow_windows < 2:
		_restart("sample")
		_publish(viewport, median, miss_share, "slow" if slow else "holds")
		return
	if _step + 1 >= STEPS.size():
		_stop(viewport, median, miss_share, "floor")
		return
	_step += 1
	_previous_mean = mean
	_judging = true
	_slow_windows = 0
	_apply(viewport, _base_scale * float(STEPS[_step]))
	_restart("settle")
	_publish(viewport, median, miss_share, "stepped")


func _begin(viewport: Viewport) -> void:
	_base_scale = viewport.scaling_3d_scale
	_base_policy = _policy(viewport)
	_forget()
	_restart("settle")


## Home shown again: under the same player setting the kept step returns at once; otherwise start afresh.
func _uncover(viewport: Viewport) -> void:
	var same_setting := is_equal_approx(viewport.scaling_3d_scale, _base_scale) \
		and is_same(_policy(viewport), _base_policy)
	if not same_setting:
		_begin(viewport)
		return
	if _step > 0:
		_apply(viewport, _base_scale * float(STEPS[_step]))
	if _done:
		_state = "stopped"
	else:
		_slow_windows = 0
		_judging = false
		_restart("settle")


func _stop(viewport: Viewport, median: float, miss_share: float, reason: String) -> void:
	_done = true
	_state = "stopped"
	_publish(viewport, median, miss_share, reason)


func _forget() -> void:
	_step = 0
	_done = false
	_judging = false
	_slow_windows = 0
	_previous_mean = 0.0
	_frames = 0
	_intervals = PackedFloat64Array()


func _restart(state: String) -> void:
	_state = state
	_frames = 0
	_intervals = PackedFloat64Array()


func _apply(viewport: Viewport, value: float) -> void:
	if is_equal_approx(value, _base_scale):
		_restore(viewport)
		return
	viewport.scaling_3d_scale = value
	_set_scale = value
	_owned_policy = _policy(viewport)


## The viewport still holds what this budget wrote, under the same reconstruction policy object.
func _owns(viewport: Viewport) -> bool:
	return _set_scale >= 0.0 and is_equal_approx(viewport.scaling_3d_scale, _set_scale) \
		and is_same(_policy(viewport), _owned_policy)


## Gives the player's scale back if this budget still owns the viewport's value; never overwrites another writer.
func _restore(viewport: Viewport) -> void:
	if viewport != null and _owns(viewport):
		viewport.scaling_3d_scale = _base_scale
	_set_scale = -1.0
	_owned_policy = null
	if viewport != null and viewport.has_meta(META):
		viewport.remove_meta(META)


func _publish(viewport: Viewport, median: float, miss_share: float, reason: String) -> void:
	viewport.set_meta(META, {"base_scale": _base_scale, "scale": viewport.scaling_3d_scale, "step": _step,
		"median_ms": snappedf(median, 0.01), "missed_share": snappedf(miss_share, 0.001),
		"target_ms": snappedf(float(target_interval_ms.call()), 0.01), "reason": reason})


static func _supported_mode(viewport: Viewport) -> bool:
	# Temporal reconstruction keeps history and provider state tied to its scale: never touch it. MetalFX
	# Spatial is excluded too, as Reconstruction tracks its provider status per mode.
	var mode := int(viewport.scaling_3d_mode)
	return mode == Viewport.SCALING_3D_MODE_BILINEAR or mode == Viewport.SCALING_3D_MODE_FSR


## The reconstruction policy object last applied to the viewport (null before any apply). get_meta() treats a
## null default as no default, so presence is checked first.
static func _policy(viewport: Viewport) -> Variant:
	return viewport.get_meta(Reconstruction.POLICY_META) if viewport.has_meta(Reconstruction.POLICY_META) else null


static func _median(values: PackedFloat64Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _home_is_top() -> bool:
	var host := get_parent().get_parent() if get_parent() != null else null
	var screens: Variant = host.get("screens") if host != null else null
	return screens != null and screens.has_method("is_top") and bool(screens.is_top("home"))


func _window_is_active() -> bool:
	var window := get_window()
	return window != null and window.has_focus() and window.mode != Window.MODE_MINIMIZED


func _refresh_interval_ms() -> float:
	var window := get_window()
	var hz := DisplayServer.screen_get_refresh_rate(window.current_screen if window != null else -1)
	if hz <= 1.0:
		hz = 60.0
	if Engine.max_fps > 0 and Engine.max_fps < hz:
		hz = float(Engine.max_fps)
	return maxf(1000.0 / hz, MIN_TARGET_MS)
