extends SceneTree

const Observer := preload("res://tools/package_flight_observer.gd")

class FakeRig extends RefCounted:
	var auto_zoom := true

class FakeRadio extends RefCounted:
	var connected := false

class FakePilot extends RefCounted:
	func read_raw() -> Dictionary: return {}

class FakeSession extends Node:
	var physics_enabled := true
	var input_enabled := true
	var external_driver_enabled := false
	var radio := FakeRadio.new()
	var sim: Node
	var read_raw: Callable

class FakeScene extends Node:
	var _rig := FakeRig.new()
	var _shadow_mode := "sun"
	var watch: Node
	var input_actions := 0
	var invalidated_before_action := 0
	func _view_name() -> String: return "pilot"
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode not in [KEY_V, KEY_Z]: return
			input_actions += 1
			if is_instance_valid(watch) and watch.violations.input_ownership > 0:
				invalidated_before_action += 1
			if event.physical_keycode == KEY_V: _shadow_mode = "off" if _shadow_mode == "sun" else "sun"
			else: _rig.auto_zoom = not _rig.auto_zoom

var checks := 0
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(not Observer._tick_gap_invalid(100, 100), "same clock value is valid")
	_check(not Observer._tick_gap_invalid(100, 1_000_100), "one second is the inclusive limit")
	_check(Observer._tick_gap_invalid(100, 1_000_101), "a longer gap fails")
	_check(Observer._tick_gap_invalid(100, 99), "a backward clock fails")
	_check(Observer._tick_gap_invalid(0, 100), "missing earlier clock fails")
	var previous := 100
	var catch_up_tick := 1_000_101
	var step_saw_gap: bool = Observer._tick_gap_invalid(previous, catch_up_tick)
	previous = catch_up_tick
	var process_saw_gap: bool = Observer._tick_gap_invalid(previous, catch_up_tick)
	_check(step_saw_gap and not process_saw_gap, "catch-up step checks before overwriting the previous clock")
	_check_drawable_boundaries()
	_check_flight_local_scope_and_input()
	print("PACKAGE_FLIGHT_CLOCK_TEST checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_drawable_boundaries() -> void:
	var probe: Node = Observer.new()
	var before: Dictionary = {status = "observed", owner = "ordinary", evidence = "acquired_framebuffer_texture_not_scanout",
		scope = 3, attempts = 10, observed = 10, missed = 0, changes = 0, width = 1920, height = 1080,
		pixel_format = 80, query_before_usec = 150, query_after_usec = 160}
	var after: Dictionary = before.duplicate(true)
	after.attempts = 60
	after.observed = 60
	after.query_before_usec = 910
	after.query_after_usec = 920
	probe.drawable_requested = true
	probe.measured_start_usec = 200
	probe.measured_end_usec = 900
	probe.drawable_before = before
	probe.drawable_after = after
	_check(probe._drawable_status_valid(before), "typed ordinary acquisition status is valid")
	_check(probe._drawable_receipt().status == "observed", "matching boundaries observe the acquired texture")
	after.scope = 4
	probe.drawable_after = after
	_check(probe._drawable_receipt().status == "not_observed", "recreated surface is refused")
	after.scope = 3
	after.changes = 1
	probe.drawable_after = after
	_check(probe._drawable_receipt().status == "not_observed", "intervening extent change is refused")
	after.changes = 0
	after.query_before_usec = 899
	probe.drawable_after = after
	_check(probe._drawable_receipt().status == "not_observed", "post-snapshot must follow the sample")
	after.query_before_usec = 910
	after.pixel_format = 0
	_check(not probe._drawable_status_valid(after), "invalid texture format is refused")
	probe.drawable_requested = false
	_check(probe._drawable_receipt().status == "not_observed", "off observation cannot claim a drawable")
	probe.free()


func _check_flight_local_scope_and_input() -> void:
	var fake := FakeScene.new()
	get_root().add_child(fake)
	get_root().set_meta(&"openrc_reconstruction", {fallback = false, requested = "native", selected = "native", provider = "native"})
	var motion := InputEventMouseMotion.new()
	_check(not Observer._changes_live_input(motion), "passive pointer motion is allowed")
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	_check(Observer._changes_live_input(motion), "camera drag invalidates the synthetic run")
	_check(Observer._changes_live_input(InputEventJoypadMotion.new()), "controller input invalidates the synthetic run")
	for changed: String in ["shadow_mode", "auto_zoom"]:
		var probe: Node = Observer.new()
		fake.add_child(probe)
		probe.set_process(false)
		probe.scene = fake
		var original: Dictionary = probe._render_scope()
		_check(original.get("shadow_mode") == "sun" and original.get("auto_zoom") == true,
				"flight-local shadow and camera scope is captured")
		probe.initial_render_scope = original.duplicate(true)
		if changed == "shadow_mode": fake._shadow_mode = "off"
		else: fake._rig.auto_zoom = false
		probe._observe_render_scope(probe._render_scope())
		fake._shadow_mode = "sun"
		fake._rig.auto_zoom = true
		probe._observe_render_scope(probe._render_scope())
		_check(probe.violations.render_scope == 1 and not probe.failure.is_empty(),
				changed + " change stays failed after a later sampled restore")
		probe.sealed = true
		probe.free()
	for changed: String in ["shadow_mode", "auto_zoom"]:
		var probe: Node = Observer.new()
		fake.add_child(probe)
		probe.set_process(false)
		probe.scene = fake
		probe.initial_render_scope = probe._render_scope()
		probe.input_watch_active = true
		probe.set_process_input(true)
		fake.watch = probe
		fake.input_actions = 0
		fake.invalidated_before_action = 0
		var key := InputEventKey.new()
		key.physical_keycode = KEY_V if changed == "shadow_mode" else KEY_Z
		key.keycode = key.physical_keycode
		key.pressed = true
		get_root().push_input(key, true)
		get_root().push_input(key, true)
		probe._observe_render_scope(probe._render_scope())
		_check(probe.violations.input_ownership >= 1 and probe.violations.render_scope == 0
				and not probe.failure.is_empty(), changed + " input restored before sampling still fails")
		_check(fake.input_actions == 2 and fake.invalidated_before_action == 2
				and fake._shadow_mode == "sun" and fake._rig.auto_zoom,
				changed + " was delivered twice after the observer and restored")
		_check(probe._input_watch_valid(), "live input watch remains registered")
		probe.set_process_input(false)
		_check(not probe._input_watch_valid(), "disabled input watch is refused")
		probe.sealed = true
		probe.free()
	var disabled_probe: Node = Observer.new()
	fake.add_child(disabled_probe)
	disabled_probe.set_process(false)
	var fake_session := FakeSession.new()
	fake.add_child(fake_session)
	var fake_sim := Node.new()
	fake_session.add_child(fake_sim)
	fake_session.sim = fake_sim
	fake_session.set_physics_process(true)
	fake_sim.set_physics_process(true)
	var fake_pilot := FakePilot.new()
	fake_session.read_raw = fake_pilot.read_raw
	disabled_probe.session = fake_session
	disabled_probe.adapter = fake_pilot
	disabled_probe.input_watch_active = true
	disabled_probe.set_process_input(true)
	var old_tick_rate: int = Engine.physics_ticks_per_second
	var old_time_scale: float = Engine.time_scale
	Engine.physics_ticks_per_second = 240
	Engine.time_scale = 1.0
	_check(disabled_probe._ownership_valid(), "synthetic tick ownership accepts the active input watch")
	disabled_probe.set_process_input(false)
	fake.watch = disabled_probe
	fake.input_actions = 0
	var disabled_key := InputEventKey.new()
	disabled_key.physical_keycode = KEY_V
	disabled_key.keycode = KEY_V
	disabled_key.pressed = true
	get_root().push_input(disabled_key, true)
	get_root().push_input(disabled_key, true)
	_check(fake.input_actions == 2 and disabled_probe.violations.input_ownership == 0
			and not disabled_probe._ownership_valid(), "disabled watch misses dispatch and fails tick ownership")
	Engine.physics_ticks_per_second = old_tick_rate
	Engine.time_scale = old_time_scale
	disabled_probe.sealed = true
	disabled_probe.free()
	get_root().remove_meta(&"openrc_reconstruction")
	fake.free()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("PACKAGE_FLIGHT_CLOCK_TEST failure: ", label)
