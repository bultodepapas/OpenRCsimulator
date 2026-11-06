# PT1h-R7: the agent debug bridge end to end over real loopback TCP inside this process, against a stand-in
# AppRoot (fake flight session and simulation, two buttons, a slider): protocol and errors, the token, log capture,
# eval, UI listing and press by label, slider values, the sticks override on the keyboard seam (including a seam
# re-installed behind its back), exact pause/step and wait; tick sampling, assert, find/get/set/call, performance
# counters, state-change events; select by item text (OptionButton, TabBar, PopupMenu), key modifiers, dialogs on top
# of the UI scope (internal OK/Cancel buttons), close, mouse clicks, methods, shortcuts and controller actions; and the
# network thread answering ping/state/logs while the main thread is blocked in a slow frame. PT1h-R9: the rewind ring
# (attempts, timeline cut, pilot/recorded inputs), watchpoints on self-pausing ticks, render commands refused
# headless, the layer census, and the interleaved ablation statistics against a fake probe with drift. The real app routes (fly/home/restart/view/record) are checked in
# tools/debug/README.md.
# Run: godot --headless --path . --script res://tests/test_debug_bridge.gd
extends SceneTree

const DebugBridge := preload("res://debug/debug_bridge.gd")
const RenderProbe := preload("res://debug/render_probe.gd")
const PORT := 47911

var _failures := 0


class FakeSim extends Node:
	var tick := 0
	var paused := false
	var stop_at_tick := -1
	var fault_reason := ""
	var inputs := PackedFloat64Array([0.0, 0.0, 0.0, 0.5])
	var mass := 2.5
	var gravity := 9.81
	var last_loads := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
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

	func hold(reason: String) -> void:
		holds[reason] = true
		sim.set_paused(true)

	func release(reason: String) -> void:
		holds.erase(reason)

	# PT1h-R9 rewind seam: the real session's checkpoint boundary holds `simulation.inputs`, and a restore leaves
	# the session on recorded inputs (input_enabled = false).
	var input_enabled := true
	var restores := 0

	func checkpoint() -> Dictionary:
		return {simulation = {tick = sim.tick, inputs = PackedFloat64Array([0.0, 0.0, 0.0, 0.25]), state = sim.state.duplicate()}}

	# PT1h-R10 file seam: the real session carries float64 bits through its own JSON format.
	func checkpoint_json() -> String:
		var snapshot := checkpoint()
		snapshot.simulation.state = Array(snapshot.simulation.state)
		snapshot.simulation.inputs = Array(snapshot.simulation.inputs)
		return JSON.stringify(snapshot)

	func restore_checkpoint_json(text: String) -> bool:
		var parsed: Variant = JSON.parse_string(text)
		if not parsed is Dictionary or not parsed.has("simulation"):
			return false
		parsed.simulation.tick = int(parsed.simulation.tick)
		parsed.simulation.state = PackedFloat64Array(parsed.simulation.state)
		parsed.simulation.inputs = PackedFloat64Array(parsed.simulation.inputs)
		return restore_checkpoint(parsed)

	func air_data(_s: PackedFloat64Array) -> Dictionary:
		return {v_air = PackedFloat64Array([20.0, 0.0, 2.0]), V = sqrt(404.0), alpha = atan2(2.0, 20.0), beta = 0.0}

	func wind_at(_t: float, _s: PackedFloat64Array) -> PackedFloat64Array:
		return PackedFloat64Array([0.0, 3.0, 0.0])

	func restore_checkpoint(candidate: Dictionary) -> bool:
		sim.tick = candidate.simulation.tick
		sim.state = candidate.simulation.state.duplicate()
		sim.inputs = candidate.simulation.inputs.duplicate()
		input_enabled = false
		restores += 1
		return true


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
	await _read_after_write(bridge)
	await _hardening(flight.session)
	await _gap_tools(bridge, flight.session)
	await _render_and_rewind(bridge, app, flight.session)
	await _checkpoint_files(flight.session)
	await _gizmo_math(flight.session)
	_ablation_math()
	_ablation_pause_ownership(bridge, flight.session)
	_render_timing_status(bridge)
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
	var singletons: Dictionary = await _call({cmd = "eval",
		expr = "[OS.get_process_id(), Performance.get_monitor(Performance.OBJECT_NODE_COUNT) > 0, Engine.get_process_frames() > 0]"})
	_check("eval reaches engine singletons", singletons.ok and int(singletons.result[0]) == OS.get_process_id()
		and singletons.result[1] == true and singletons.result[2] == true, str(singletons))
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
	var moved: Dictionary = await _call({cmd = "set_value", text = "Wind", value = 4.5})
	_check("set_value moves a Range", moved.ok and is_equal_approx(slider.value, 4.5), str(moved))


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
	var pause_reply: Dictionary = await _call({cmd = "pause"})
	var start: int = session.sim.tick
	var stepped: Dictionary = await _call({cmd = "step", ticks = 30})
	_check("step advances exactly n ticks and pauses again", pause_reply.ok and stepped.ok
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
	_check("wait times out with the last evaluated value", not timeout.ok
		and str(timeout.error).begins_with("timed out") and str(timeout.error).contains("last value false"), str(timeout))



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
	var assigned: Dictionary = await _call({cmd = "set", node = path, prop = "offset", value = [1, 2, 3]})
	var sub: Dictionary = await _call({cmd = "set", node = path, prop = "offset:y", value = 5})
	_check("set coerces arrays to vectors and sets sub-properties", assigned.ok and sub.ok
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


func _everything(_bridge: Node, app: Node, ui: Container) -> void:
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
	var numeric: Dictionary = await _call({cmd = "key", name = 2})
	_check("a numeric key name is the digit key", numeric.ok, str(numeric))
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
	bridge._net_mutex.lock()
	bridge._last_request_ms = -bridge.SNAPSHOT_IDLE_MS # idle: the main thread stops publishing snapshots
	bridge._net_mutex.unlock()
	for i in 3:
		await process_frame
	await create_timer(3.0 * bridge.SNAPSHOT_INTERVAL_MS / 1000.0).timeout # older than the accepted age too
	bridge._net_mutex.lock()
	var old_snapshot: Dictionary = bridge._snapshot.duplicate(true)
	bridge._net_mutex.unlock()
	var old_age := Time.get_ticks_msec() - int(old_snapshot.get("ms", 0))
	var request_frame := Engine.get_process_frames()
	var state: Dictionary = await _call({cmd = "state"})
	_check("an old snapshot is never served: the main thread answers instead", state.ok
		and not old_snapshot.is_empty() and int(old_snapshot.frame) < request_frame - 1
		and old_age > 2 * bridge.SNAPSHOT_INTERVAL_MS
		and not state.result.has("snapshot_frame") and state.result.frame >= request_frame,
		"request_frame=%d old_frame=%s old_age=%d reply=%s" % [request_frame, old_snapshot.get("frame"), old_age, str(state).left(200)])


func _hardening(session: Node) -> void:
	# A web page POSTing to 127.0.0.1 sends an HTTP request line first: the bridge must answer once and close
	# before the body line could run as a command.
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", PORT)
	var deadline := Time.get_ticks_msec() + 5000
	while peer.get_status() != StreamPeerTCP.STATUS_CONNECTED and Time.get_ticks_msec() < deadline:
		await process_frame
		peer.poll()
	var before_pause: bool = session.sim.paused
	peer.put_data("POST / HTTP/1.1\nHost: 127.0.0.1\n\n{\"cmd\":\"pause\"}\n".to_utf8_buffer())
	var received := PackedByteArray()
	while peer.get_status() == StreamPeerTCP.STATUS_CONNECTED and Time.get_ticks_msec() < deadline:
		await process_frame
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			break
		var available := peer.get_available_bytes()
		if available > 0:
			received.append_array(peer.get_partial_data(available)[1])
	var lines := received.get_string_from_utf8().strip_edges().split("\n")
	_check("an HTTP request is answered once and closed; its body never runs", lines.size() == 1
		and lines[0].contains("closing") and peer.get_status() != StreamPeerTCP.STATUS_CONNECTED
		and session.sim.paused == before_pause, str(lines))
	var bad: Dictionary = await _call({cmd = "sticks", roll = 0.5, pitch = [1]})
	await physics_frame
	await physics_frame
	_check("a bad stick value is refused before anything is installed", not bad.ok
		and str(bad.error).contains("pitch") and session.read_raw == session.keyboard_reader, str(bad))
	var installed: Dictionary = await _call({cmd = "sticks", roll = 0.2})
	var released: Dictionary = await _call({cmd = "sticks", release = 1})
	_check("numeric booleans: release=1 releases", installed.ok and released.ok and released.result.has("released"))
	var path := str(root.get_path_to(session.get_parent()))
	var missing: Dictionary = await _call({cmd = "set", node = path, prop = "no_such_property", value = 3})
	_check("set refuses an unknown property", not missing.ok and str(missing.error).contains("no property"), str(missing))
	var index: Dictionary = await _call({cmd = "step", ticks = "many"})
	_check("a non-numeric argument is refused", not index.ok and str(index.error).contains("number"), str(index))


func _read_after_write(bridge: Node) -> void:
	await _call({cmd = "state"}) # snapshots on
	await process_frame
	await process_frame
	bridge._snapshot_ms = Time.get_ticks_msec() + 60000 # no periodic publish: only an invalidation can refresh it
	var changed: Dictionary = await _call({cmd = "sticks", roll = 0.3})
	var seen: Dictionary = await _call({cmd = "state"})
	bridge._snapshot_ms = 0
	await _call({cmd = "sticks", release = true})
	_check("a state read right after a command never shows the state before it", changed.ok and seen.ok
		and is_equal_approx(float(seen.result.sticks_override.get("roll", 0.0)), 0.3), str(seen).left(300))


## PT1h-R8: hitch recorder, tick watchpoints, grouped logs, object census and the script-profile parser.
func _gap_tools(bridge: Node, session: Node) -> void:
	for i in 20:
		await process_frame
	var before: int = bridge.debug_log.last_seq()
	OS.delay_msec(150) # one long frame
	await process_frame
	await process_frame
	var frames: Dictionary = await _call({cmd = "frames"})
	var hitches: Dictionary = await _call({cmd = "logs", since = before, level = "event"})
	var hitch_texts: Array = hitches.result.records.map(func(r: Dictionary) -> String: return r.text)
	_check("a long frame becomes a hitch event and frames reports percentiles", frames.ok and frames.result.frames > 10
		and frames.result.max_ms >= 140.0 and frames.result.p50_ms < 100.0 and frames.result.has("fps_1pct_low")
		and hitch_texts.any(func(t: String) -> bool: return t.begins_with("hitch 1")), str(hitch_texts))
	session.sim.set_paused(false)
	var target: int = session.sim.tick + 12
	var armed: Dictionary = await _call({cmd = "break", name = "at_target", expr = "sim.tick >= %d" % target, once = true, wait = true})
	_check("a watchpoint pauses the flight at the exact tick", armed.ok and int(armed.result.tick) == target
		and session.sim.paused and session.sim.tick == target, str(armed).left(200))
	var listed: Dictionary = await _call({cmd = "break", list = true})
	_check("a once watchpoint is removed after it fires", listed.ok and listed.result.is_empty())
	var bad: Dictionary = await _call({cmd = "break", expr = "sim.("})
	_check("a watchpoint with a parse error is refused", not bad.ok)
	var seq: int = bridge.debug_log.last_seq()
	for value in [3, 17, 250]:
		print("gap-test wheel load %d N at tick %d" % [value, value * 2])
	var summary: Dictionary = await _call({cmd = "logs", since = seq, summary = true})
	var groups: Array = summary.result.groups.filter(func(g: Dictionary) -> bool: return str(g.text).begins_with("gap-test"))
	_check("logs summary groups messages that differ only in numbers", groups.size() == 1 and groups[0].count == 3, str(groups))
	var baseline: Dictionary = await _call({cmd = "objects", baseline = true})
	var leaked: Array = []
	for i in 5:
		leaked.append(Node.new())
	var diff: Dictionary = await _call({cmd = "objects", diff = true})
	var orphan_rows: Array = diff.result.diff.orphans if diff.ok else []
	_check("objects diff names the class that grew", baseline.ok and diff.ok and orphan_rows.size() >= 1
		and orphan_rows[0][0] == "Node" and int(orphan_rows[0][1]) == 5, str(orphan_rows))
	for node: Node in leaked:
		node.free()
	print("FRAME: total: 0.004 script: 0.003/75 %\n0:res://sim/a.gd::10::step\n\ttotal: 0.003/75 % \tself: 0.001/25 % tcalls: 240\n1:res://sim/b.gd::4::forces\n\ttotal: 0.002/50 % \tself: 0.002/50 % tcalls: 960")
	var profile: Dictionary = await _call({cmd = "profile", since = seq})
	var top: Array = profile.result.functions if profile.ok else []
	_check("profile parses the engine's script profile, hottest self time first", profile.ok and profile.result.samples == 1
		and top.size() == 2 and str(top[0].function).ends_with("forces") and is_equal_approx(top[0].self_ms_per_sample, 2.0)
		and int(top[0].calls) == 960, str(profile).left(300))
	var flood_seq: int = bridge.debug_log.last_seq()
	push_warning("gap-test kept warning")
	for i in 5000: # --script-profile prints this much in a minute; it must not evict errors and warnings
		print("FRAME: total: 0.001 script: 0.001/50 %")
	var kept: Dictionary = await _call({cmd = "logs", since = flood_seq, level = "warning"})
	_check("profile lines never evict warnings from the main log", kept.ok and kept.result.records.size() == 1
		and kept.result.dropped == 0, str(kept).left(200))
	var flooded: Dictionary = await _call({cmd = "profile", seconds = 60})
	_check("profile reads its own ring", flooded.ok and flooded.result.samples >= 5000, str(flooded).left(160))

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

## PT1h-R9: rewind ring and attempts, a watchpoint on a tick that pauses itself, render commands without a renderer,
## the layer census.
func _render_and_rewind(_bridge: Node, app: Node, session: Node) -> void:
	session.sim.set_paused(false)
	var none: Dictionary = await _call({cmd = "rewind", seconds = 1})
	_check("rewind without snapshots explains how to arm", not none.ok and str(none.error).contains("arm=true"), str(none))
	var every_s := 10.0 / Engine.physics_ticks_per_second
	var armed: Dictionary = await _call({cmd = "rewind", arm = true, every_s = every_s, keep_s = 1000})
	var start: int = session.sim.tick
	while session.sim.tick < start + 45:
		await physics_frame
	session.sim.set_paused(true) # a slow frame may run several ticks before the reply: count against the real span
	var listed: Dictionary = await _call({cmd = "rewind", list = true})
	var kept: int = listed.result.snapshots
	var most: int = 2 + int((session.sim.tick - start) / 10.0)
	_check("armed rewind stores one checkpoint every n ticks", armed.ok and armed.result.every_ticks == 10
		and kept >= 4 and kept <= most, str([kept, most, listed]))
	session.commands.throttle = 0.9
	var target: int = start + 20
	var rewound: Dictionary = await _call({cmd = "rewind", tick = target})
	_check("rewind tick= restores the newest checkpoint at or before it, paused, pilot inputs back on",
		rewound.ok and int(rewound.result.rewound.tick) <= target and int(rewound.result.rewound.tick) > target - 10
		and session.sim.paused and session.input_enabled and is_equal_approx(session.commands.throttle, 0.25)
		and session.restores == 1, str(rewound).left(300))
	var after: Dictionary = await _call({cmd = "rewind", list = true})
	_check("restoring cuts the later checkpoints of that attempt",
		int(after.result.attempts[0].last_tick) == int(rewound.result.rewound.tick), str(after.result.attempts))
	var recorded: Dictionary = await _call({cmd = "rewind", tick = target, inputs = "recorded"})
	_check("inputs=recorded keeps the session on the restored inputs", recorded.ok and not session.input_enabled,
		str(recorded).left(200))
	session.input_enabled = true
	# A restart: the clock goes back, so a new attempt begins and the previous one stays reachable.
	session.sim.set_paused(false)
	var before_restart: int = session.sim.tick
	while session.sim.tick < before_restart + 25:
		await physics_frame
	session.sim.tick = 0
	while session.sim.tick < 15:
		await physics_frame
	var attempts: Dictionary = await _call({cmd = "rewind", list = true})
	var previous: Dictionary = await _call({cmd = "rewind", attempt = "previous", seconds = 0})
	_check("a clock reset starts a new attempt; attempt=previous restores the end of the earlier one",
		attempts.ok and attempts.result.current_attempt == 1 and previous.ok and int(previous.result.rewound.attempt) == 0
		and int(previous.result.rewound.tick) >= before_restart, str(previous).left(300))
	var too_old: Dictionary = await _call({cmd = "rewind", tick = 0, attempt = 0})
	_check("a tick older than the ring is refused with the kept range",
		(not too_old.ok and str(too_old.error).contains("keeps ticks")) or (too_old.ok and int(too_old.result.rewound.tick) == 0),
		str(too_old))
	await _call({cmd = "rewind", arm = false})
	# A tick that pauses the flight itself (a crash) must still trigger a watchpoint, at that tick.
	session.sim.set_paused(false)
	await _call({cmd = "break", name = "crash", expr = "not session.crash.is_empty()", pause = true})
	await physics_frame
	session.crash = {why = "test"}
	session.sim.tick += 1
	session.sim.set_paused(true)
	await physics_frame
	await physics_frame
	var hits: Dictionary = await _call({cmd = "break", list = true})
	_check("a watchpoint sees a tick that paused itself", hits.ok and hits.result[0].hits == 1
		and int(hits.result[0].last_tick) == session.sim.tick, str(hits))
	session.crash = {}
	await _call({cmd = "break", clear = "all"})
	# Render commands need a renderer; the census and view modes do not.
	var render: Dictionary = await _call({cmd = "render"})
	var ablate: Dictionary = await _call({cmd = "ablate"})
	_check("render and ablate refuse to run headless", not render.ok and not ablate.ok
		and str(render.error).contains("renderer") and str(ablate.error).contains("renderer"), str([render, ablate]))
	var modes: Dictionary = await _call({cmd = "viewmode"})
	var bogus: Dictionary = await _call({cmd = "viewmode", name = "x-ray"})
	_check("viewmode lists the debug draw modes and refuses unknown ones", modes.ok and modes.result.modes.has("overdraw")
		and modes.result.modes[0] == "normal" and not bogus.ok, str(modes).left(200))
	var scene := Node3D.new()
	scene.name = "Scene3D"
	var forest := Node3D.new()
	forest.name = "Forest"
	scene.add_child(forest)
	for i in 3:
		var tree_mesh := MeshInstance3D.new()
		tree_mesh.mesh = BoxMesh.new()
		forest.add_child(tree_mesh)
	var hidden := MeshInstance3D.new()
	hidden.name = "Hidden"
	hidden.mesh = BoxMesh.new()
	hidden.visible = false
	scene.add_child(hidden)
	var lamp := OmniLight3D.new()
	scene.add_child(lamp)
	app.add_child(scene)
	var layers: Dictionary = await _call({cmd = "layers", root = str(root.get_path_to(scene)), depth = 2})
	var forest_row: Array = layers.result.layers.filter(func(r: Dictionary) -> bool: return r.path == "Forest") if layers.ok else []
	_check("layers counts visible geometry and shadow casters per node, skipping hidden ones", layers.ok
		and forest_row.size() == 1 and forest_row[0].geometry == 3 and forest_row[0].shadow_casters == 3
		and not layers.result.layers.any(func(r: Dictionary) -> bool: return r.path == "Hidden"), str(layers).left(400))
	scene.queue_free()


## PT1h-R10: checkpoint files (bugit/bugitgo seam): save to an absolute path, load restores and hands control back.
func _checkpoint_files(session: Node) -> void:
	var relative: Dictionary = await _call({cmd = "checkpoint", action = "save", path = "checkpoint.json"})
	_check("checkpoint refuses a relative path", not relative.ok and str(relative.error).contains("absolute"), str(relative))
	var path := OS.get_user_data_dir().path_join("debug-bridge-test/checkpoint.json")
	session.sim.set_paused(true)
	var saved_tick: int = session.sim.tick
	var saved: Dictionary = await _call({cmd = "checkpoint", action = "save", path = path})
	session.sim.tick = saved_tick + 500
	session.input_enabled = true
	var loaded: Dictionary = await _call({cmd = "checkpoint", action = "load", path = path})
	_check("checkpoint save then load restores the tick, paused, with pilot inputs", saved.ok and loaded.ok
		and session.sim.tick == saved_tick and session.sim.paused and session.input_enabled
		and FileAccess.file_exists(path), str([saved, loaded]).left(300))
	var missing: Dictionary = await _call({cmd = "checkpoint", action = "load", path = path + ".none"})
	_check("checkpoint load of a missing file is refused", not missing.ok and str(missing.error).contains("no checkpoint"))
	DirAccess.remove_absolute(path)


## The flight-model numbers against hand values: identity attitude, body air velocity (20, 0, 2) m/s, loads
## (-2, 0, -30) N on 2.5 kg: load factor 30 / (2.5 · 9.81), the along-path force (F·v)/|v|, the wind speed.
func _gizmo_math(session: Node) -> void:
	var sim: Node = session.sim
	var saved_state: PackedFloat64Array = sim.state.duplicate()
	sim.state = PackedFloat64Array([0.0, 0.0, -30.0, 20.0, 0.0, 2.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	sim.last_loads = PackedFloat64Array([-2.0, 0.0, -30.0, 0.0, 0.5, 0.0])
	var parent := Node3D.new()
	root.add_child(parent)
	var gizmos: Node3D = preload("res://debug/flight_gizmos.gd").new()
	parent.add_child(gizmos)
	gizmos.configure(["axes", "velocity", "air", "wind", "forces", "moments", "trail", "label"])
	gizmos.update_from(session, {pos = Vector3(0, 30, 0), basis = Basis.IDENTITY})
	var last: Dictionary = gizmos.last
	var along := (-2.0 * 20.0 + -30.0 * 2.0) / sqrt(404.0)
	_check("gizmos: load factor, along-path force and wind from the committed loads and air data",
		is_equal_approx(last.load_factor, 30.0 / (2.5 * 9.81)) and absf(last.along_path_n - along) < 1.0e-4
		and is_equal_approx(last.wind_mps, 3.0) and is_equal_approx(last.alpha_deg, rad_to_deg(atan2(2.0, 20.0))), str(last))
	var mesh: ImmediateMesh = gizmos._lines
	_check("gizmos: lines and the label are drawn", mesh.get_surface_count() == 1 and gizmos._label.visible
		and gizmos._label.text.contains("n 1.22 g"), gizmos._label.text)
	gizmos.configure([])
	gizmos.update_from(session, {pos = Vector3(0, 30, 0), basis = Basis.IDENTITY})
	_check("gizmos: nothing shown draws nothing", mesh.get_surface_count() == 0 and not gizmos._label.visible)
	var none: Dictionary = await _call({cmd = "gizmos", show = "all"})
	var bad: Dictionary = await _call({cmd = "gizmos", show = "smoke"})
	var off: Dictionary = await _call({cmd = "gizmos", off = true})
	_check("gizmos command: refused layers, a non-3D flight waits for the next flight, off clears",
		none.ok and not none.result.flight and not bad.ok and off.ok, str([none, bad, off]).left(300))
	parent.queue_free()
	sim.state = saved_state
	sim.last_loads = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])


## A fake probe whose GPU time is 2 ms + 0.5 ms while the forest is visible + a linear drift: the interleaved
## A-B-A comparison must report the forest's 0.5 ms despite the drift, an inert target as insignificant, restore
## everything, and flag a target the app switches back on as overridden.
class FakeProbe extends "res://debug/render_probe.gd":
	var forest: Node3D
	var ticks := 0

	func _init() -> void:
		super(null)

	func sample() -> Dictionary:
		ticks += 1
		return {gpu_ms = 2.0 + (0.5 if forest.visible else 0.0) + 0.01 * ticks, draw_calls = 10 if forest.visible else 7,
			primitives = 100, objects = 5, root_cpu_ms = 0.1, gpu_timing_status = "synthetic_valid"}


func _ablation_math() -> void:
	var probe := FakeProbe.new()
	probe.forest = Node3D.new()
	var inert := Node3D.new()
	var stubborn := Node3D.new()
	var targets: Array = [probe._toggle("Forest", "layer", [[probe.forest, "visible"]], [false]),
		probe._toggle("Inert", "layer", [[inert, "visible"]], [false]),
		probe._toggle("Stubborn", "layer", [[stubborn, "visible"]], [false])]
	var run := RenderProbe.Ablation.new(probe, targets, 2, 6)
	var frames := 0
	var hidden_during_run := false
	while not run.advance():
		frames += 1
		stubborn.visible = true # the app turns it back on every frame
		hidden_during_run = hidden_during_run or not probe.forest.visible
	var result := run.result()
	var rows := {}
	for row: Dictionary in result.rows:
		rows[row.name] = row
	_check("ablation: interleaved baselines cancel drift and rank the real saving",
		absf(rows.Forest.saved_gpu_ms - 0.5) < 1.0e-6 and rows.Forest.significant and rows.Forest.saved_draw_calls == 3,
		str(rows.Forest))
	_check("ablation: an inert target is not significant", absf(rows.Inert.saved_gpu_ms) < 1.0e-6
		and not rows.Inert.significant, str(rows.Inert))
	_check("ablation: a target switched back on is flagged overridden", rows.Stubborn.overridden and not rows.Forest.overridden)
	_check("ablation: every target was off during its phase and is restored after", hidden_during_run and probe.forest.visible
		and inert.visible and frames + 1 == run.total_frames(), "frames=%d total=%d" % [frames, run.total_frames()])
	var aborted := RenderProbe.Ablation.new(probe, [probe._toggle("Forest", "layer", [[probe.forest, "visible"]], [false])], 2, 6)
	for i in 10:
		aborted.advance()
	var off_mid_run := not probe.forest.visible
	aborted.abort()
	_check("ablation: abort restores a target that is still off", off_mid_run and probe.forest.visible)
	for node: Node in [probe.forest, inert, stubborn]:
		node.free()


func _ablation_pause_ownership(bridge: Node, session: Node) -> void:
	session.holds.clear()
	session.sim.set_paused(false)
	_check("ablation owns a session hold", bridge._begin_ablation_pause(session) and session.sim.paused \
		and session.holds.size() == 1)
	var restored: Dictionary = bridge._finish_ablation_pause()
	_check("owned pause restores a running flight through resume", restored.restored and not session.sim.paused \
		and session.holds.is_empty(), str(restored))
	session.sim.set_paused(true)
	bridge._begin_ablation_pause(session)
	restored = bridge._finish_ablation_pause()
	_check("an already paused flight stays paused", restored.restored and session.sim.paused, str(restored))
	session.sim.set_paused(false)
	bridge._begin_ablation_pause(session)
	session.hold("menu")
	_check("new hold invalidates ablation", not bridge._ablation_pause_valid())
	restored = bridge._finish_ablation_pause()
	_check("ablation does not resume across another hold", session.sim.paused and session.holds.has("menu") \
		and restored.interrupted, str(restored))
	session.release("menu")
	session.sim.set_paused(false)
	bridge._begin_ablation_pause(session)
	bridge.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	restored = bridge._finish_ablation_pause()
	_check("focus loss prevents automatic resume", session.sim.paused and restored.interrupted, str(restored))
	session.sim.set_paused(false)
	bridge._begin_ablation_pause(session)
	bridge._cmd_pause({})
	restored = bridge._finish_ablation_pause()
	_check("an independent pause request is preserved", session.sim.paused and restored.interrupted, str(restored))
	session.sim.set_paused(false)
	bridge._begin_ablation_pause(session)
	var target := Node3D.new()
	var probe := FakeProbe.new()
	probe.forest = target
	var run := RenderProbe.Ablation.new(probe, [probe._toggle("target", "layer", [[target, "visible"]], [false])], 2, 6)
	for i in 8: run.advance() # first baseline ends and the target is switched off
	bridge._ablation = run
	_check("disconnect fixture has a live toggle", not target.visible)
	bridge._pending.append({peer_id = 9999, job = {}, on_timeout = func() -> Dictionary:
		return bridge._finish_ablation(run, {ok = false})})
	bridge._forget_peer(9999)
	_check("disconnect cleanup restores the toggle and owned hold", target.visible and bridge._ablation == null \
		and not session.sim.paused and session.holds.is_empty())
	target.free()


class SummaryProbe extends "res://debug/render_probe.gd":
	func _init() -> void:
		super(null)
	func set_measure(on: bool) -> void:
		measuring = on
	func config() -> Dictionary:
		return {vsync = "disabled", refresh_hz = 60.0, max_fps = 0}
	func viewport_rows() -> Array:
		return []


func _render_timing_status(bridge: Node) -> void:
	var previous: Variant = bridge._render
	bridge._render = SummaryProbe.new()
	var sample := {gpu_ms = 0.0, root_gpu_ms = 0.0, sub_gpu_ms = 0.0, root_cpu_ms = 1.0, setup_cpu_ms = 0.0,
		draw_calls = 1, shadow_draw_calls = 0, canvas_draw_calls = 0, primitives = 1, objects = 1,
		gpu_timing_status = "unavailable_or_zero"}
	var unavailable: Dictionary = bridge._render_summary([sample])
	_check("zero GPU observations never produce a CPU/headroom verdict", unavailable.bound.begins_with("unknown") \
		and unavailable.gpu_timing_status == "unavailable_or_zero" and unavailable.gpu_budget_status == "unavailable")
	sample.gpu_ms = 3.0
	sample.root_gpu_ms = 3.0
	sample.gpu_timing_status = "unverified_freshness"
	var positive: Dictionary = bridge._render_summary([sample])
	_check("positive GPU observations remain raw and unverified", positive.gpu_ms == 3.0 \
		and positive.gpu_timing_status == "unverified_freshness" and positive.bound.begins_with("unknown"))
	var probe := FakeProbe.new()
	probe.forest = Node3D.new()
	var run := RenderProbe.Ablation.new(probe, [{name = "a", kind = "layer"}], 2, 6)
	bridge._render.measuring = true
	bridge._ablation = run
	bridge._ablation_owned_measure = true
	_check("measurement setting cannot change during ablation", not bridge._cmd_render({measure = true}).ok)
	bridge._finish_ablation(run, {ok = false})
	_check("ablation restores its previously disabled measurement", not bridge._render.measuring)
	probe.forest.free()
	bridge._render = previous


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
