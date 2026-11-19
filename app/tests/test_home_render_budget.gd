extends SceneTree
## VQ-07h I2: Home's 3D scale steps down only while Home misses the refresh, reverts when pixels are not the
## limit, yields to other writers, restores the player's scale when Home is covered or left, and keeps a
## visit's decision across overlays without measuring again.

const Budget := preload("res://render/home_render_budget.gd")
const Reconstruction := preload("res://render/reconstruction.gd")
var checks := 0
var failures := 0
var now_usec := 1_000_000
var top := true
var focused := true


class FakeScreens extends RefCounted:
	var top_id := "home"

	func is_top(id: String) -> bool:
		return id == top_id


class FakeAppRoot extends Node:
	var screens := FakeScreens.new()


func check(label: String, passed: bool) -> void:
	checks += 1
	if not passed:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	_run.call_deferred()


func make_budget(host: Node) -> Node:
	var budget: Node = Budget.new()
	budget.may_adjust = func() -> bool: return top
	budget.window_active = func() -> bool: return focused
	budget.target_interval_ms = func() -> float: return 1000.0 / 120.0
	budget.clock_usec = func() -> int: return now_usec
	host.add_child(budget)
	budget.set_process(false) # frames are driven explicitly below
	return budget


## Runs `frames` frames whose interval is `ms`.
func drive(budget: Node, frames: int, ms: float) -> void:
	for i in frames:
		now_usec += int(ms * 1000.0)
		budget._process(ms / 1000.0)


## Settle, then two measurement windows at `ms` per frame (two slow windows are needed for a step).
func window(budget: Node, ms: float) -> void:
	drive(budget, Budget.SETTLE_FRAMES + 2 * Budget.SAMPLE_FRAMES + 2, ms)


## A VSync-shaped window: one frame in `missed_every` misses one refresh (two intervals), the rest are on time.
func vsync_window(budget: Node, interval_ms: float, missed_every: int) -> void:
	for i in Budget.SETTLE_FRAMES + 2 * Budget.SAMPLE_FRAMES + 2:
		drive(budget, 1, interval_ms * (2.0 if i % missed_every == 0 else 1.0))


func reason(view: Viewport) -> String:
	return str(view.get_meta(Budget.META, {}).get("reason", ""))


func _run() -> void:
	var view := root
	view.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	view.scaling_3d_scale = 1.0
	var host := Node3D.new()
	root.add_child(host)

	var fast := make_budget(host)
	window(fast, 7.0)
	check("a Home that holds the refresh keeps the player's scale", is_equal_approx(view.scaling_3d_scale, 1.0))
	check("the decision is published", reason(view) == "holds")
	drive(fast, Budget.SAMPLE_FRAMES + 2, 16.7)
	check("one slow window (a loading spike) costs no resolution", is_equal_approx(view.scaling_3d_scale, 1.0)
		and reason(view) == "slow")
	drive(fast, Budget.SAMPLE_FRAMES, 16.7)
	check("a Home that slows down after holding still steps down", is_equal_approx(view.scaling_3d_scale, 0.85))
	fast.free()
	check("freeing the budget restores the player's scale", is_equal_approx(view.scaling_3d_scale, 1.0)
		and not view.has_meta(Budget.META))

	var pixel_bound := make_budget(host)
	window(pixel_bound, 16.7)
	check("a missed refresh steps the scale down", is_equal_approx(view.scaling_3d_scale, 0.85))
	window(pixel_bound, 8.0)
	check("a step that restores the refresh is kept", is_equal_approx(view.scaling_3d_scale, 0.85) and reason(view) == "holds")
	top = false
	drive(pixel_bound, 1, 8.0)
	check("another screen over Home restores the player's scale", is_equal_approx(view.scaling_3d_scale, 1.0)
		and not view.has_meta(Budget.META))
	top = true
	drive(pixel_bound, 1, 8.0)
	check("uncovering Home re-applies the kept step at once", is_equal_approx(view.scaling_3d_scale, 0.85))
	focused = false
	drive(pixel_bound, 1, 8.0)
	check("losing focus restores the player's scale", is_equal_approx(view.scaling_3d_scale, 1.0))
	focused = true
	host.remove_child(pixel_bound)
	check("leaving Home restores the player's scale", is_equal_approx(view.scaling_3d_scale, 1.0))
	host.add_child(pixel_bound)
	window(pixel_bound, 7.0)
	check("a re-added Home measures afresh instead of reusing the old visit", is_equal_approx(view.scaling_3d_scale, 1.0)
		and reason(view) == "holds")
	pixel_bound.free()

	var vsync := make_budget(host)
	vsync_window(vsync, 1000.0 / 120.0, 10)
	check("a 10 % background of missed refreshes alone does not step", is_equal_approx(view.scaling_3d_scale, 1.0)
		and reason(view) == "holds")
	vsync.free()
	vsync = make_budget(host)
	vsync_window(vsync, 1000.0 / 120.0, 4)
	check("frequent missed refreshes step down even when the median is on time", is_equal_approx(view.scaling_3d_scale, 0.85))
	vsync_window(vsync, 1000.0 / 120.0, 1000)
	check("a step that removes the misses is kept", is_equal_approx(view.scaling_3d_scale, 0.85) and reason(view) == "holds")
	vsync.free()
	check("free after a kept step restores", is_equal_approx(view.scaling_3d_scale, 1.0))

	var outliers := make_budget(host)
	drive(outliers, Budget.SETTLE_FRAMES + 1, 7.0)
	for i in 2 * Budget.SAMPLE_FRAMES:
		drive(outliers, 1, 500.0 if i % 45 == 0 else 7.0) # stalls and pauses are not GPU measurements
	check("stalls do not count as slow frames", is_equal_approx(view.scaling_3d_scale, 1.0) and reason(view) == "holds")
	outliers.free()

	var not_pixels := make_budget(host)
	window(not_pixels, 16.7)
	window(not_pixels, 16.6)
	check("a step that buys nothing reverts to the player's scale", is_equal_approx(view.scaling_3d_scale, 1.0)
		and reason(view) == "not pixel-bound")
	window(not_pixels, 16.7)
	check("and the budget stays stopped for this visit", is_equal_approx(view.scaling_3d_scale, 1.0))
	top = false
	drive(not_pixels, 1, 16.7)
	top = true
	window(not_pixels, 16.7)
	check("an overlay does not restart a stopped visit", is_equal_approx(view.scaling_3d_scale, 1.0))
	not_pixels.free()

	var partial := make_budget(host)
	window(partial, 20.0)
	window(partial, 15.0)
	check("a second step follows a partial gain", is_equal_approx(view.scaling_3d_scale, 0.7))
	window(partial, 14.9)
	check("a second step without gain returns to the first, keeping its gain", is_equal_approx(view.scaling_3d_scale, 0.85)
		and reason(view) == "no further gain")
	partial.free()
	check("free after a kept partial step restores", is_equal_approx(view.scaling_3d_scale, 1.0))

	var floor_case := make_budget(host)
	window(floor_case, 20.0)
	window(floor_case, 15.0)
	window(floor_case, 12.0)
	check("the floor is 0.7 of the player's scale", is_equal_approx(view.scaling_3d_scale, 0.7) and reason(view) == "floor")
	floor_case.free()

	var yielding := make_budget(host)
	window(yielding, 16.7)
	check("yield fixture stepped", is_equal_approx(view.scaling_3d_scale, 0.85))
	view.scaling_3d_scale = 0.9 # Settings or a resize applies a new player value
	drive(yielding, 1, 16.7)
	host.remove_child(yielding)
	check("another writer's value is never overwritten on exit", is_equal_approx(view.scaling_3d_scale, 0.9))
	host.add_child(yielding)
	window(yielding, 16.7)
	check("the new player value is the new base", is_equal_approx(view.scaling_3d_scale, 0.9 * 0.85))
	yielding.free()
	check("free restores the new base", is_equal_approx(view.scaling_3d_scale, 0.9))
	view.scaling_3d_scale = 1.0

	var coincident := make_budget(host)
	window(coincident, 16.7)
	view.set_meta(Reconstruction.POLICY_META, {"scale": 0.85}) # a Reconstruction.apply that wrote the same value
	view.scaling_3d_scale = 0.85
	drive(coincident, 1, 16.7)
	coincident.free()
	check("a coincident write by Reconstruction is recognised and kept", is_equal_approx(view.scaling_3d_scale, 0.85))
	view.remove_meta(Reconstruction.POLICY_META)
	view.scaling_3d_scale = 1.0

	var switched := make_budget(host)
	window(switched, 16.7)
	view.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	drive(switched, 1, 16.7)
	check("a switch to temporal reconstruction gives the scale back", is_equal_approx(view.scaling_3d_scale, 1.0))
	window(switched, 16.7)
	check("temporal reconstruction is never touched", is_equal_approx(view.scaling_3d_scale, 1.0))
	switched.free()
	view.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR

	var unowned := make_budget(host)
	unowned.may_adjust = Callable(unowned, "_home_is_top")
	window(unowned, 16.7)
	check("without AppRoot's screen stack Home is not assumed on top", is_equal_approx(view.scaling_3d_scale, 1.0))
	unowned.free()

	var app_root := FakeAppRoot.new()
	root.add_child(app_root)
	var home := Node3D.new()
	app_root.add_child(home)
	var wired := make_budget(home)
	wired.may_adjust = Callable(wired, "_home_is_top")
	window(wired, 16.7)
	check("AppRoot's screen stack with Home on top lets the budget act", is_equal_approx(view.scaling_3d_scale, 0.85))
	app_root.screens.top_id = "settings"
	drive(wired, 1, 16.7)
	check("Settings over Home gets the player's scale", is_equal_approx(view.scaling_3d_scale, 1.0))
	app_root.free()

	var defaults := Budget.new()
	root.add_child(defaults)
	defaults.set_process(false)
	var interval: float = defaults._refresh_interval_ms()
	check("the default target is a sane refresh interval", interval >= Budget.MIN_TARGET_MS and interval <= 1000.0)
	Engine.max_fps = 30
	check("a lower frame cap sets the target", is_equal_approx(defaults._refresh_interval_ms(), 1000.0 / 30.0))
	Engine.max_fps = 0
	defaults.free()

	host.free()
	print("Home render budget: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)
