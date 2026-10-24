# PT1h-R7: the agent debug bridge end to end over real loopback TCP inside this process, against a stand-in
# AppRoot (fake flight session and simulation, two buttons, a slider): protocol and errors, the token, log capture,
# eval, UI listing and press by label, slider values, the sticks override on the keyboard seam (including a seam
# re-installed behind its back), exact pause/step and wait. The real app route is checked in tools/debug/README.md.
# Run: godot --headless --path . --script res://tests/test_debug_bridge.gd
extends SceneTree

const DebugBridge := preload("res://debug/debug_bridge.gd")
const PORT := 47911

var _failures := 0


class FakeSim extends Node:
	var tick := 0
	var paused := false
	var stop_at_tick := -1
	var fault_reason := ""
	var state := PackedFloat64Array([1.0, 2.0, -30.0, 12.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

	func dt() -> float:
		return 1.0 / Engine.physics_ticks_per_second

	func time() -> float:
		return tick * dt()

	func set_paused(value: bool) -> void:
		paused = value

	func _physics_process(_delta: float) -> void:
		if paused or (stop_at_tick >= 0 and tick >= stop_at_tick):
			return
		tick += 1


class FakeSession extends Node:
	var sim := FakeSim.new()
	var commands := {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	var raw := {}
	var holds := {}
	var crash := {}
	var pause_reason := ""
	var keyboard_reader: Callable = func() -> Dictionary: return {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = 0.0}
	var read_raw: Callable = keyboard_reader

	func _ready() -> void:
		process_physics_priority = -1
		add_child(sim)

	func _physics_process(_delta: float) -> void:
		raw = read_raw.call()
		commands.roll = raw.roll
		commands.throttle = clampf(commands.throttle + raw.throttle * 0.5 * sim.dt(), 0.0, 1.0)

	func resume() -> void:
		if holds.is_empty():
			sim.set_paused(false)


class FakeFlight extends Node:
	var session := FakeSession.new()
	var aircraft_id := "fake-plane"

	func _ready() -> void:
		add_child(session)


class FakeApp extends Node:
	var flight: Node
	var home: Node
	var presses := 0


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	_run()


func _run() -> void:
	OS.set_environment(DebugBridge.ENV_BRIDGE, str(PORT))
	var app := FakeApp.new()
	app.name = "AppRoot"
	var flight := FakeFlight.new()
	app.flight = flight
	app.add_child(flight)
	var ui := VBoxContainer.new()
	app.add_child(ui)
	var fly := Button.new()
	fly.text = "Fly"
	fly.name = "Fly"
	fly.pressed.connect(func() -> void: app.presses += 1)
	ui.add_child(fly)
	var flaps := Button.new()
	flaps.text = "Flaps"
	flaps.disabled = true
	ui.add_child(flaps)
	var slider := HSlider.new()
	slider.name = "Wind"
	slider.max_value = 10.0
	slider.step = 0.5
	ui.add_child(slider)
	root.add_child(app)
	var bridge: Node = DebugBridge.new()
	app.add_child(bridge)
	await process_frame
	await _protocol(bridge)
	await _ui(app, slider)
	await _sticks(flight.session)
	await _step(flight.session)
	bridge.queue_free()
	await process_frame
	print("debug bridge: %d failed" % _failures if _failures > 0 else "all debug bridge checks passed")
	quit(1 if _failures > 0 else 0)


func _protocol(bridge: Node) -> void:
	var help: Dictionary = await _call({id = 7, cmd = "help"})
	_check("help lists every command, echoes the id", help.ok and help.id == 7 and help.result.has("step"), str(help))
	var unknown: Dictionary = await _call({cmd = "nope"})
	_check("unknown command is an error", not unknown.ok and str(unknown.error).contains("unknown command"))
	var junk: Dictionary = await _raw_line("not json")
	_check("malformed line is an error", not junk.ok)
	bridge.token = "s3cret"
	var refused: Dictionary = await _call({cmd = "ping"})
	var allowed: Dictionary = await _call({cmd = "ping", token = "s3cret"})
	_check("token is enforced when set", not refused.ok and allowed.ok and allowed.result.pid == OS.get_process_id())
	bridge.token = ""
	var before: int = bridge.debug_log.last_seq()
	push_warning("bridge-test warning")
	print("bridge-test info")
	var logs: Dictionary = await _call({cmd = "logs", since = before, level = "warning"})
	var records: Array = logs.result.records
	_check("logs capture push_warning with its script location, filtered by level",
		records.size() == 1 and records[0].text == "bridge-test warning" and str(records[0].get("script", "")).contains("test_debug_bridge.gd"),
		str(records))
	var everything: Dictionary = await _call({cmd = "logs", since = before})
	_check("logs capture print", everything.result.records.any(func(r: Dictionary) -> bool: return r.text == "bridge-test info"))
	var value: Dictionary = await _call({cmd = "eval", expr = "flight.aircraft_id + str(flight.session.sim.state[2])"})
	_check("eval reads AppRoot properties", value.ok and value.result == "fake-plane-30.0", str(value))
	var broken: Dictionary = await _call({cmd = "eval", expr = "flight.("})
	_check("eval parse errors are reported", not broken.ok and str(broken.error).begins_with("parse error"))
	var state: Dictionary = await _call({cmd = "state"})
	_check("state decodes the flight pose", state.ok and state.result.route == "flight"
		and is_equal_approx(state.result.flight.height_m, 30.0) and is_equal_approx(state.result.flight.speed_mps, 12.0)
		and state.result.flight.aircraft == "fake-plane", str(state.result.get("flight")))
	var json_safe: Variant = DebugBridge.jsonable({a = Vector3(1, 2, 3), b = NAN, c = PackedFloat64Array([0.5])})
	_check("jsonable converts vectors, non-finite floats and packed arrays", json_safe.a == [1.0, 2.0, 3.0]
		and json_safe.b == "nan" and json_safe.c == [0.5], str(json_safe))


func _ui(app: Node, slider: HSlider) -> void:
	var listing: Dictionary = await _call({cmd = "ui"})
	var labels: Array = listing.result.controls.map(func(c: Dictionary) -> String: return c.text)
	_check("ui lists visible buttons and ranges", labels.has("Fly") and labels.has("Flaps") and labels.has("Wind"), str(labels))
	var pressed: Dictionary = await _call({cmd = "press", text = "fly", mode = "signal"})
	_check("press by label (case-insensitive) activates the button", pressed.ok and app.presses == 1, str(pressed))
	var accepted: Dictionary = await _call({cmd = "press", text = "Fly"})
	_check("press through focus + ui_accept", accepted.ok and accepted.result.mode == "accept" and app.presses == 2, str(accepted))
	var disabled: Dictionary = await _call({cmd = "press", text = "Flaps"})
	_check("a disabled button is refused", not disabled.ok and str(disabled.error).contains("disabled"))
	var missing: Dictionary = await _call({cmd = "press", text = "Land"})
	_check("an unknown label is refused", not missing.ok)
	var set: Dictionary = await _call({cmd = "set_value", text = "Wind", value = 4.5})
	_check("set_value moves a Range", set.ok and is_equal_approx(slider.value, 4.5), str(set))


func _sticks(session: Node) -> void:
	var reply: Dictionary = await _call({cmd = "sticks", roll = 0.4, throttle = 0.25})
	await physics_frame
	await physics_frame
	_check("sticks override the keyboard seam", reply.ok and is_equal_approx(session.raw.roll, 0.4), str(session.raw))
	session.read_raw = session.keyboard_reader # a menu closing re-installs the keyboard reader
	await physics_frame
	await physics_frame
	_check("the override survives a re-installed reader", is_equal_approx(session.raw.roll, 0.4), str(session.raw))
	var settled: Dictionary = await _call({cmd = "wait", seconds = 0.2})
	_check("the throttle target is approached by the keyboard rate", settled.ok and session.commands.throttle > 0.0
		and session.commands.throttle <= 0.25 + 1e-9, str(session.commands))
	var released: Dictionary = await _call({cmd = "sticks", release = true})
	await physics_frame # the signal precedes the nodes' physics callbacks: the second frame has sampled
	await physics_frame
	_check("release restores the keyboard reader", released.ok and session.read_raw == session.keyboard_reader
		and session.raw.roll == 0.0)


func _step(session: Node) -> void:
	var paused: Dictionary = await _call({cmd = "pause"})
	var start: int = session.sim.tick
	var stepped: Dictionary = await _call({cmd = "step", ticks = 30})
	_check("step advances exactly n ticks and pauses again", paused.ok and stepped.ok
		and stepped.result.tick == start + 30 and session.sim.paused and session.sim.stop_at_tick == -1, str(stepped))
	session.holds.menu = true
	var held: Dictionary = await _call({cmd = "resume"})
	_check("resume reports a hold instead of flying", not held.ok and str(held.error).contains("menu"), str(held))
	session.holds.clear()
	var resumed: Dictionary = await _call({cmd = "resume"})
	_check("resume flies again", resumed.ok and not session.sim.paused)
	var waited: Dictionary = await _call({cmd = "wait", until = "flight.session.sim.tick > %d" % (start + 40), timeout_s = 5})
	_check("wait until an expression holds", waited.ok and session.sim.tick > start + 40, str(waited))
	var timeout: Dictionary = await _call({cmd = "wait", until = "false", timeout_s = 0.1})
	_check("wait times out with an error", not timeout.ok and timeout.error == "timed out")


func _call(payload: Dictionary) -> Dictionary:
	return await _raw_line(JSON.stringify(payload))


func _raw_line(line: String) -> Dictionary:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", PORT)
	var deadline := Time.get_ticks_msec() + 5000
	while peer.get_status() != StreamPeerTCP.STATUS_CONNECTED and Time.get_ticks_msec() < deadline:
		await process_frame
		peer.poll()
	peer.put_data((line + "\n").to_utf8_buffer())
	var buffer := PackedByteArray()
	while buffer.find(10) < 0 and Time.get_ticks_msec() < deadline:
		await process_frame
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			buffer.append_array(peer.get_partial_data(available)[1])
	peer.disconnect_from_host()
	var reply: Variant = JSON.parse_string(buffer.get_string_from_utf8())
	return reply if reply is Dictionary else {ok = false, error = "no reply"}
