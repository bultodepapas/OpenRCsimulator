# PT1h-R7: the agent debug bridge end to end over real loopback TCP inside this process, against a stand-in
# AppRoot (fake flight session and simulation, two buttons, a slider): protocol and errors, the token, log capture,
# eval, UI listing and press by label, slider values, the sticks override on the keyboard seam (including a seam
# re-installed behind its back), exact pause/step and wait; tick sampling, assert, find/get/set/call, performance
# counters, state-change events; select by item text (OptionButton, TabBar, PopupMenu), key modifiers, dialogs on top
# of the UI scope (internal OK/Cancel buttons), close, mouse clicks, methods, shortcuts and controller actions; and the
# network thread answering ping/state/logs while the main thread is blocked in a slow frame. The real app routes (fly/home/restart/view/record) are checked in
# tools/debug/README.md.
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
	var camera_fov := 60.0
	var offset := Vector3.ZERO

	func scaled(x: float, k: float) -> float:
		return x * k

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
	await _tools(bridge, flight)
	await _everything(bridge, app, ui)
	await _threaded()
	await _stale_snapshot(bridge)
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



func _tools(bridge: Node, flight: Node) -> void:
	var session: Node = flight.session
	session.sim.set_paused(false)
	var sampled: Dictionary = await _call({cmd = "sample", exprs = {height = "-s[2]", roll = "session.commands.roll"},
		every_ticks = 5, count = 4})
	var rows: Array = sampled.result.rows if sampled.ok else []
	_check("sample returns one row per n simulation ticks", sampled.ok
		and sampled.result.columns == ["tick", "time_s", "height", "roll"] and rows.size() == 4
		and rows[1][0] - rows[0][0] == 5 and rows[3][0] - rows[0][0] == 15 and is_equal_approx(rows[0][2], 30.0), str(sampled))
	var bad_sample: Dictionary = await _call({cmd = "sample", exprs = {x = "nope_missing"}, count = 2})
	_check("a failing sample expression is reported", not bad_sample.ok and str(bad_sample.error).contains("x failed"), str(bad_sample))
	_check("finished samples are released", bridge._samples.is_empty())
	var passed: Dictionary = await _call({cmd = "assert", expr = "flight.session.sim.tick > 0"})
	var failed: Dictionary = await _call({cmd = "assert", expr = "flight.aircraft_id == 'other'", message = "wrong plane"})
	_check("assert passes truthy and fails falsy with its message", passed.ok and not failed.ok
		and str(failed.error).contains("wrong plane"), str(failed))
	var found: Dictionary = await _call({cmd = "find", name = "Fly*", type = "Button"})
	_check("find matches name glob and class", found.ok and found.result.nodes.size() == 1
		and str(found.result.nodes[0].path).ends_with("/Fly"), str(found))
	var path := str(bridge.get_tree().root.get_path_to(flight))
	var got: Dictionary = await _call({cmd = "get", node = path, prop = "aircraft_id"})
	var all: Dictionary = await _call({cmd = "get", node = path})
	_check("get reads one property or all script variables", got.ok and got.result == "fake-plane"
		and all.ok and all.result.has("camera_fov"), str(all))
	var set: Dictionary = await _call({cmd = "set", node = path, prop = "offset", value = [1, 2, 3]})
	var sub: Dictionary = await _call({cmd = "set", node = path, prop = "offset:y", value = 5})
	_check("set coerces arrays to vectors and sets sub-properties", set.ok and sub.ok
		and flight.offset == Vector3(1, 5, 3), str(flight.offset))
	var called: Dictionary = await _call({cmd = "call", node = path, method = "scaled", args = [2.5, 4]})
	var missing: Dictionary = await _call({cmd = "call", node = path, method = "nope"})
	_check("call returns the result and refuses unknown methods", called.ok and is_equal_approx(called.result, 10.0)
		and not missing.ok)
	var perf: Dictionary = await _call({cmd = "perf"})
	_check("perf reports engine counters and the simulation step", perf.ok and perf.result.nodes > 0
		and perf.result.has("orphan_nodes") and perf.result.has("sim_step_usec"), str(perf))
	var before: int = bridge.debug_log.last_seq()
	session.sim.set_paused(true)
	await process_frame
	await process_frame
	var events: Dictionary = await _call({cmd = "logs", since = before, level = "event"})
	var texts: Array = events.result.records.map(func(r: Dictionary) -> String: return r.text)
	_check("a pause is logged as an event with its tick", texts.has("paused: true")
		and events.result.records[0].detail.has("tick"), str(texts))
	var no_view: Dictionary = await _call({cmd = "view", name = "chase"})
	var no_log: Dictionary = await _call({cmd = "record"})
	_check("view and record explain a missing seam", not no_view.ok and not no_log.ok)
	var state: Dictionary = await _call({cmd = "state"})
	_check("state counts log levels", state.result.log_counts.get("warning", 0) >= 1, str(state.result.log_counts))


class KeySpy extends Node:
	var seen: Array[String] = []

	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			seen.append(event.as_text_physical_keycode() if event.keycode == KEY_NONE else event.as_text())


func _everything(bridge: Node, app: Node, ui: Container) -> void:
	var options := OptionButton.new()
	options.name = "Language"
	for label: String in ["English", "Español", "Deutsch"]:
		options.add_item(label)
	ui.add_child(options)
	var tabs := TabBar.new()
	tabs.name = "Pages"
	for title: String in ["Flight", "Aircraft", "Practice"]:
		tabs.add_tab(title)
	ui.add_child(tabs)
	var clicks := [0]
	var target := Button.new()
	target.text = "Mouse target"
	target.position = Vector2(4, 4) # a headless --script root window is 64×64: the GUI ignores points outside it
	target.size = Vector2(50, 30)
	target.pressed.connect(func() -> void: clicks[0] += 1)
	app.add_child(target)
	await process_frame
	var chose: Dictionary = await _call({cmd = "select", text = "Language", item = "español"})
	var tabbed: Dictionary = await _call({cmd = "select", text = "Pages", item = "Pract"})
	var refused: Dictionary = await _call({cmd = "select", text = "Language", item = "nope"})
	_check("select by item label: OptionButton exact (case-insensitive), TabBar unique prefix, unknown refused",
		chose.ok and options.selected == 1 and tabbed.ok and tabs.current_tab == 2 and not refused.ok, str([chose, tabbed]))
	var spy := KeySpy.new()
	root.add_child(spy)
	var shifted: Dictionary = await _call({cmd = "key", name = "Shift+F"})
	var bad: Dictionary = await _call({cmd = "key", name = "Hyper+F"})
	_check("key sends modifiers and refuses unknown ones", shifted.ok and spy.seen.has("Shift+F") and not bad.ok, str(spy.seen))
	spy.queue_free()
	var dialog := ConfirmationDialog.new()
	dialog.title = "Discard trace?"
	dialog.ok_button_text = "Discard"
	var answers := []
	dialog.confirmed.connect(func() -> void: answers.append("ok"))
	dialog.canceled.connect(func() -> void: answers.append("cancel"))
	app.add_child(dialog)
	dialog.popup_centered()
	await process_frame
	var listing: Dictionary = await _call({cmd = "ui"})
	var labels: Array = listing.result.controls.map(func(c: Dictionary) -> String: return c.text)
	_check("an open dialog becomes the UI scope with its internal buttons", listing.result.get("window", {}).get("title") == "Discard trace?"
		and labels.has("Discard") and labels.has("Cancel") and not labels.has("Fly"), str(listing.result))
	var confirmed: Dictionary = await _call({cmd = "press", text = "Discard"})
	_check("press confirms a dialog", confirmed.ok and answers == ["ok"] and not dialog.visible, str([confirmed, answers]))
	dialog.popup_centered()
	await process_frame
	var closed: Dictionary = await _call({cmd = "close"})
	_check("close cancels the top dialog", closed.ok and answers == ["ok", "cancel"] and not dialog.visible, str([closed, answers]))
	var popup := PopupMenu.new()
	popup.add_item("Copy")
	popup.add_item("Paste", 7)
	var picked := []
	popup.id_pressed.connect(func(id: int) -> void: picked.append(id))
	app.add_child(popup)
	popup.popup(Rect2i(10, 10, 100, 60))
	await process_frame
	var popped: Dictionary = await _call({cmd = "select", popup = true, item = "paste"})
	_check("select picks a PopupMenu item by label", popped.ok and picked == [7] and not popup.visible, str(popped))
	var clicked: Dictionary = await _call({cmd = "mouse", text = "Mouse target"})
	_check("mouse clicks a control at its centre", clicked.ok and clicks[0] == 1 and Vector2(clicked.result.at[0], clicked.result.at[1]) == target.get_global_rect().get_center(), str(clicked))
	var methods: Dictionary = await _call({cmd = "methods", node = str(root.get_path_to(app.flight))})
	_check("methods lists script methods with arguments", methods.ok and methods.result.methods.has("scaled(x, k)"), str(methods))
	var shortcuts: Dictionary = await _call({cmd = "shortcuts"})
	var keys: Array = shortcuts.result.shortcuts.map(func(r: Dictionary) -> String: return ",".join(r.keys)) if shortcuts.ok else []
	_check("shortcuts come from the controls reference with key names", shortcuts.ok and shortcuts.result.vehicle == "airplane"
		and keys.has("F10,F11") and shortcuts.result.input_actions.has("smoke_pump"), str(keys))
	var listed: Dictionary = await _call({cmd = "control"})
	var unknown: Dictionary = await _call({cmd = "control", name = "warp_drive"})
	_check("control lists controller actions and refuses unknown ids", listed.ok and listed.result.size() > 20 and not unknown.ok)
	var hinted := Button.new()
	hinted.text = "DRIVE · Enter"
	var other := Button.new()
	other.text = "Free drive"
	var drives := [0]
	hinted.pressed.connect(func() -> void: drives[0] += 1)
	ui.add_child(hinted)
	ui.add_child(other)
	await process_frame
	var tiered: Dictionary = await _call({cmd = "press", text = "drive", mode = "signal"})
	_check("a label without its key hint beats a substring elsewhere", tiered.ok and drives[0] == 1, str(tiered))
	var no_truck: Dictionary = await _call({cmd = "drive", throttle = 0.5})
	_check("drive explains how to start a ground vehicle", not no_truck.ok and str(no_truck.error).contains("start_ground_vehicle"))
	hinted.queue_free()
	other.queue_free()
	var screen: Dictionary = await _call({cmd = "open", screen = "garage"})
	_check("open refuses unknown screens", not screen.ok and str(screen.error).contains("settings"))
	options.queue_free()
	tabs.queue_free()
	target.queue_free()
	dialog.queue_free()
	popup.queue_free()


func _threaded() -> void:
	await process_frame # the snapshot is published while clients are active
	await process_frame
	var results := {}
	var worker := Thread.new()
	worker.start(func() -> void:
		var started := Time.get_ticks_msec()
		for cmd: String in ["ping", "state", "logs"]:
			results[cmd] = _blocking_call(JSON.stringify({cmd = cmd, since = 0}))
		results.ms = Time.get_ticks_msec() - started)
	OS.delay_msec(800) # a slow frame: the main thread cannot run any command meanwhile
	var finished_during_block := not worker.is_alive()
	worker.wait_to_finish()
	_check("the network thread answers ping, state and logs during a blocked frame", finished_during_block
		and results.ping.get("ok", false) and results.logs.get("ok", false)
		and results.state.get("result", {}).has("snapshot_frame") and int(results.ms) < 700, str(results).left(400))



func _stale_snapshot(bridge: Node) -> void:
	bridge._last_request_ms = -bridge.SNAPSHOT_IDLE_MS # idle: the main thread stops publishing snapshots
	for i in 3:
		await process_frame
	var state: Dictionary = await _call({cmd = "state"})
	_check("an old snapshot is never served: the main thread answers instead", state.ok
		and not state.result.has("snapshot_frame") and state.result.frame >= Engine.get_process_frames() - 1, str(state).left(200))

## A plain blocking client for a worker thread (the main-thread helper awaits frames).
static func _blocking_call(line: String) -> Dictionary:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", PORT)
	var deadline := Time.get_ticks_msec() + 2000
	while peer.get_status() != StreamPeerTCP.STATUS_CONNECTED and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		peer.poll()
	peer.put_data((line + "\n").to_utf8_buffer())
	var buffer := PackedByteArray()
	while buffer.find(10) < 0 and Time.get_ticks_msec() < deadline:
		OS.delay_msec(1)
		peer.poll()
		var available := peer.get_available_bytes()
		if available > 0:
			buffer.append_array(peer.get_partial_data(available)[1])
	peer.disconnect_from_host()
	var reply: Variant = JSON.parse_string(buffer.get_string_from_utf8()) if buffer.find(10) >= 0 else null
	return reply if reply is Dictionary else {ok = false, error = "no reply"}

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
