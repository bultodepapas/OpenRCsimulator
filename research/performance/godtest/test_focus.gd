extends SceneTree
## Exercise the driver with deterministic display and focus observations.

class FocusDriver extends "res://debug/godtest_driver.gd":
	var window_focus_probe: Callable
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _fail(reason: String) -> void:
		failure = reason
		running = false
		_end("failed", reason)


var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var key := "OPENRC_GODTEST_SEATLESS_WAYLAND"
	var had_value := OS.has_environment(key)
	var previous := OS.get_environment(key)
	OS.unset_environment(key)
	await _case("headless", false, false, true, false)
	await _case("Wayland", true, false, true, false)
	await _case("Wayland", false, true, true, false)
	await _case("Wayland", false, false, false, false)
	OS.set_environment(key, "1")
	await _case("Wayland", true, false, true, false)
	await _case("Wayland", false, false, true, true)
	await _case("X11", false, false, false, false)
	if had_value: OS.set_environment(key, previous)
	else: OS.unset_environment(key)
	print("GOD_FOCUS_TESTS: ", failures, " failed")
	quit(0 if failures == 0 else 1)


func _case(display: String, immediate: bool, delayed: bool, accepted: bool, override_used: bool) -> void:
	var driver := FocusDriver.new()
	root.add_child(driver)
	driver.running = true
	driver.app = driver
	var polls: Array[String] = []
	var probe := func() -> bool:
		polls.append(str(driver.phase.get("name", "")))
		return immediate or (delayed and polls.size() >= 3)
	var ok := await driver._observe_window_focus(display, probe, 1000000 if delayed else 0)
	var waited := display != "headless" and not immediate
	_check(ok == accepted and driver.failure.is_empty() == accepted, "focus decision")
	_check(driver.identity.get("window_focused_before_selection") == (immediate or delayed)
		if display != "headless" else polls.is_empty(), "observed focus")
	_check(driver.window_focus_probe.is_valid() == override_used and
		driver.identity.has("window_focus_probe_override") == override_used, "override receipt")
	_check(driver.identity.get("seatless_wayland", false) ==
		(display == "Wayland" and OS.get_environment("OPENRC_GODTEST_SEATLESS_WAYLAND") == "1"), "seatless receipt")
	_check(driver.phase.is_empty() and driver.phases.size() == int(waited), "closed wait")
	if waited and not driver.phases.is_empty():
		var wait_record: Dictionary = driver.phases[0]
		_check(wait_record.name == "focus_wait" and not wait_record.requested and
			wait_record.status == ("complete" if accepted else "failed"), "wait receipt")
	if delayed:
		_check(polls == ["", "focus_wait", "focus_wait"], "delayed focus belongs to wait")
	driver.free()


func _check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
