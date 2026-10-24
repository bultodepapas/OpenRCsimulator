# PT1h-R7: live debug bridge for coding agents. Opt-in (environment OPENRC_DEBUG_BRIDGE, debug builds only), it
# listens on 127.0.0.1 for newline-delimited JSON requests {"id", "cmd", ...args} and answers one JSON line each:
# state, live logs, the visible UI (press/focus/type by text, no mouse), keys, pilot sticks, pause/step,
# screenshots and Expression evaluation against AppRoot. Client and command reference: tools/debug/README.md.
# Pattern after godot-mcp-runtime (MIT, github.com/Erodenn/godot-mcp-runtime): loopback TCP, token, ALWAYS mode.
# It never changes the launch route or project settings; everything it does is an explicit request.
extends Node

const DebugLog := preload("res://debug/debug_log.gd")
const Spec := preload("res://spec.gd")
const RB := preload("res://physics/rigid_body.gd")

const ENV_BRIDGE := "OPENRC_DEBUG_BRIDGE"
const ENV_TOKEN := "OPENRC_DEBUG_TOKEN"
const ENV_LOG := "OPENRC_DEBUG_LOG"
const DEFAULT_PORT := 47870
const MAX_CLIENTS := 8
const MAX_LINE_BYTES := 1 << 20
const UI_LIMIT := 400
const NODE_LIMIT := 600
const COMMANDS := {
	help = "this list",
	ping = "liveness: pid, engine version, frame, fps",
	state = "route, screens, focus, fps; flight: aircraft, tick, pause/holds/crash, pose, commands",
	logs = "since=<seq> limit=<n> level=<error,warning,...>: engine/script log records after a cursor",
	ui = "all=<bool> labels=<bool> text=<substring>: visible controls of the top screen (or everything)",
	press = "text=<label>|path=<node> mode=accept|signal: activate a button like Enter on the focused control",
	focus = "text=|path=: give a control keyboard focus",
	type = "text=<s> submit=<bool> [path=]: insert text into the focused (or named) LineEdit/TextEdit",
	select = "path=|text= index=<i>: choose an OptionButton/ItemList item",
	set_value = "path=|text= value=<v>: set a Range (slider/spin box) value",
	key = "name=<W|Escape|F2|...> action=tap|press|release hold_s=<s>: keyboard event (flight keys too)",
	action = "name=<input action> action=tap|press|release: input-map action event",
	sticks = "roll pitch yaw (-1..1, pitch + = stick back) throttle (0..1 target) for_s=<s> | release=true",
	pause = "freeze the flight simulation (sim only; menus keep running)",
	resume = "the pilot's continue (refused during menus, crash, calibration)",
	step = "ticks=<n>: advance a paused flight exactly n physics ticks, then pause",
	time_scale = "value=<x>: Engine.time_scale (0.05..16)",
	wait = "frames=<n> | seconds=<s> | until=<expr> timeout_s=<s>",
	screenshot = "path=<png> max_width=<px>: viewport picture (needs a renderer: Xvfb, not --headless)",
	eval = "expr=<GDScript expression> node=<path>: evaluate on AppRoot (inputs: app, tree, bridge)",
	nodes = "path=<node> depth=<n>: scene-tree outline",
	quit = "code=<n>: quit the engine after replying",
}

var port := DEFAULT_PORT
var token := ""
var log_path := ""
var debug_log := DebugLog.new()
var app: Node
var _server := TCPServer.new()
var _clients: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
var _scheduled: Array[Dictionary] = []
var _log_file: FileAccess
var _log_file_seq := 0
var _shot_index := 0
var _sticks := {}
var _sticks_until_tick := -1
var _sticks_session: Node
var _sticks_original: Callable
var _sticks_reader: Callable
var _step_sim: Node
var _step_target := -1


## The environment opts in; release templates never open the socket.
static func requested() -> bool:
	var value := OS.get_environment(ENV_BRIDGE).strip_edges().to_lower()
	return OS.is_debug_build() and not value.is_empty() and value not in ["0", "off", "false", "no"]


func _init() -> void:
	name = "DebugBridge"
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -10 # before the session samples this tick's input
	OS.add_logger(debug_log)


func _ready() -> void:
	app = get_parent()
	var value := OS.get_environment(ENV_BRIDGE).strip_edges()
	if value.is_valid_int() and value.to_int() > 1:
		port = value.to_int()
	token = OS.get_environment(ENV_TOKEN)
	log_path = OS.get_environment(ENV_LOG)
	if not log_path.is_empty():
		_log_file = FileAccess.open(log_path, FileAccess.WRITE)
		if _log_file == null:
			push_warning("debug bridge: cannot write %s: %s" % [log_path, error_string(FileAccess.get_open_error())])
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		push_error("debug bridge: cannot listen on 127.0.0.1:%d: %s" % [port, error_string(err)])
		return
	print("debug bridge: listening on 127.0.0.1:%d (pid %d)" % [_server.get_local_port(), OS.get_process_id()])


func _exit_tree() -> void:
	_restore_sticks()
	_server.stop()
	for client: Dictionary in _clients:
		client.peer.disconnect_from_host()
	_clients.clear()
	OS.remove_logger(debug_log)
	_write_log_file()


func _process(_delta: float) -> void:
	while _server.is_listening() and _server.is_connection_available():
		var peer := _server.take_connection()
		if _clients.size() >= MAX_CLIENTS:
			peer.disconnect_from_host()
			continue
		peer.set_no_delay(true)
		_clients.append({peer = peer, buffer = PackedByteArray()})
	for client: Dictionary in _clients.duplicate():
		_poll_client(client)
	_run_scheduled()
	_run_pending()
	_finish_step()
	_write_log_file()


func _physics_process(_delta: float) -> void:
	if _sticks.is_empty():
		return
	if not is_instance_valid(_sticks_session):
		_sticks.clear()
		return
	if _sticks_until_tick >= 0 and int(_sticks_session.sim.tick) >= _sticks_until_tick:
		_restore_sticks()
		return
	# A menu closing re-installs the keyboard reader (HeldKeys): keep the override on top while it is active.
	if _sticks_session.read_raw != _sticks_reader:
		_sticks_original = _sticks_session.read_raw
		_sticks_session.read_raw = _sticks_reader


func _poll_client(client: Dictionary) -> void:
	var peer: StreamPeerTCP = client.peer
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_drop(client)
		return
	var available := peer.get_available_bytes()
	if available > 0:
		var got: Array = peer.get_partial_data(available)
		if got[0] == OK:
			client.buffer.append_array(got[1])
	while true:
		var newline: int = client.buffer.find(10)
		if newline < 0:
			if client.buffer.size() > MAX_LINE_BYTES:
				_send(peer, {ok = false, error = "request line exceeds %d bytes" % MAX_LINE_BYTES})
				_drop(client)
			return
		var line: String = client.buffer.slice(0, newline).get_string_from_utf8().strip_edges()
		client.buffer = client.buffer.slice(newline + 1)
		if not line.is_empty():
			_handle(peer, line)


func _drop(client: Dictionary) -> void:
	_clients.erase(client)
	_pending = _pending.filter(func(item: Dictionary) -> bool: return item.peer != client.peer)


func _handle(peer: StreamPeerTCP, line: String) -> void:
	var parser := JSON.new() # parse_string would log an engine error for every malformed line
	var request: Variant = parser.data if parser.parse(line) == OK else null
	if not request is Dictionary or not request.has("cmd"):
		_send(peer, {ok = false, error = "expected one JSON object with \"cmd\" per line"})
		return
	var id: Variant = request.get("id")
	if id is float and id == floorf(id):
		id = int(id) # JSON numbers parse as floats
	if not token.is_empty() and str(request.get("token", "")) != token:
		_send(peer, {id = id, ok = false, error = "bad or missing token"})
		return
	var reply: Dictionary
	var cmd := str(request.cmd)
	if not COMMANDS.has(cmd):
		reply = _fail("unknown command '%s'; try help" % cmd)
	else:
		reply = call("_cmd_" + cmd, request)
	if reply.has("pending"):
		var timeout_s: float = float(request.get("timeout_s", reply.get("timeout_s", 30.0)))
		_pending.append({peer = peer, id = id, check = reply.pending,
			deadline_ms = Time.get_ticks_msec() + int(clampf(timeout_s, 0.0, 3600.0) * 1000.0)})
		return
	reply.id = id
	_send(peer, reply)


func _run_pending() -> void:
	for item: Dictionary in _pending.duplicate():
		var result: Variant = item.check.call()
		if result == null and Time.get_ticks_msec() < item.deadline_ms:
			continue
		_pending.erase(item)
		var reply: Dictionary = result if result is Dictionary else _fail("timed out")
		reply.id = item.id
		_send(item.peer, reply)


func _send(peer: StreamPeerTCP, reply: Dictionary) -> void:
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data((JSON.stringify(jsonable(reply), "", false, true) + "\n").to_utf8_buffer())


static func _ok(result: Variant = null) -> Dictionary:
	return {ok = true, result = result}


static func _fail(message: String) -> Dictionary:
	return {ok = false, error = message}


func _write_log_file() -> void:
	if _log_file == null:
		return
	var records := debug_log.since(_log_file_seq, 1000)
	for record: Dictionary in records:
		_log_file.store_line(JSON.stringify(record))
		_log_file_seq = int(record.seq)
	if not records.is_empty():
		_log_file.flush()


# ---- commands -------------------------------------------------------------------------------------------------

func _cmd_help(_request: Dictionary) -> Dictionary:
	return _ok(COMMANDS)


func _cmd_ping(_request: Dictionary) -> Dictionary:
	return _ok({pid = OS.get_process_id(), godot = Engine.get_version_info().string, frame = Engine.get_process_frames(),
		fps = Engine.get_frames_per_second(), display = DisplayServer.get_name(), log_seq = debug_log.last_seq()})


func _cmd_state(_request: Dictionary) -> Dictionary:
	var out := {frame = Engine.get_process_frames(), fps = Engine.get_frames_per_second(), time_scale = Engine.time_scale,
		tree_paused = get_tree().paused, log_seq = debug_log.last_seq(), route = _route(), screens = _screen_ids(),
		focus = _path(get_viewport().gui_get_focus_owner()), sticks_override = _sticks.duplicate()}
	var session := _session()
	if session != null:
		out.flight = _flight_state(session)
	return _ok(out)


func _cmd_logs(request: Dictionary) -> Dictionary:
	var levels := PackedStringArray()
	if request.has("level"):
		levels = str(request.level).split(",", false)
	var records := debug_log.since(int(request.get("since", 0)), clampi(int(request.get("limit", 200)), 1, 2000), levels)
	return _ok({records = records, last_seq = debug_log.last_seq(), dropped = debug_log.dropped})


func _cmd_ui(request: Dictionary) -> Dictionary:
	var scope: Node = get_tree().root if _bool(request.get("all", false)) else _ui_scope()
	var items: Array = []
	var filter := str(request.get("text", "")).to_lower()
	for control: Control in _controls(scope, _bool(request.get("labels", false))):
		var info := _control_info(control)
		if filter.is_empty() or str(info.text).to_lower().contains(filter):
			items.append(info)
		if items.size() >= UI_LIMIT:
			break
	return _ok({scope = _path(scope), focus = _path(get_viewport().gui_get_focus_owner()), controls = items})


func _cmd_press(request: Dictionary) -> Dictionary:
	var found := _find_control(request)
	if found.has("error"):
		return _fail(found.error)
	var control: Control = found.control
	if not control is BaseButton:
		return _fail("%s is a %s, not a button" % [_path(control), control.get_class()])
	if control.disabled:
		return _fail("%s is disabled" % _path(control))
	var mode := str(request.get("mode", "accept" if control.focus_mode != Control.FOCUS_NONE else "signal"))
	var path := _path(control) # the press may free the control (a closing menu)
	if mode == "accept":
		control.grab_focus()
		for pressed: bool in [true, false]:
			var event := InputEventAction.new()
			event.action = &"ui_accept"
			event.pressed = pressed
			Input.parse_input_event(event)
	elif control.toggle_mode:
		control.button_pressed = not control.button_pressed
	else:
		control.pressed.emit()
	return _settle(int(request.get("frames", 3)), {pressed = path, mode = mode})


func _cmd_focus(request: Dictionary) -> Dictionary:
	var found := _find_control(request)
	if found.has("error"):
		return _fail(found.error)
	found.control.grab_focus()
	return _settle(1, {focused = _path(found.control)})


func _cmd_type(request: Dictionary) -> Dictionary:
	var control: Control = get_viewport().gui_get_focus_owner()
	if request.has("path"):
		var found := _find_control({path = request.path})
		if found.has("error"):
			return _fail(found.error)
		control = found.control
	if not (control is LineEdit or control is TextEdit):
		return _fail("no LineEdit/TextEdit focused or named")
	control.insert_text_at_caret(str(request.get("text", "")))
	if control is LineEdit:
		control.text_changed.emit(control.text)
		if _bool(request.get("submit", false)):
			control.text_submitted.emit(control.text)
	else:
		control.text_changed.emit()
	return _settle(1, {control = _path(control), text = control.text})


func _cmd_select(request: Dictionary) -> Dictionary:
	var found := _find_control(request)
	if found.has("error"):
		return _fail(found.error)
	var control: Control = found.control
	var index := int(request.get("index", -1))
	if control is OptionButton:
		if index < 0 or index >= control.item_count:
			return _fail("index out of range 0..%d" % (control.item_count - 1))
		control.select(index)
		control.item_selected.emit(index)
	elif control is ItemList:
		if index < 0 or index >= control.item_count:
			return _fail("index out of range 0..%d" % (control.item_count - 1))
		control.select(index)
		control.item_selected.emit(index)
	else:
		return _fail("%s is not an OptionButton or ItemList" % _path(control))
	return _settle(2, _control_info(control))


func _cmd_set_value(request: Dictionary) -> Dictionary:
	var found := _find_control(request)
	if found.has("error"):
		return _fail(found.error)
	if not found.control is Range:
		return _fail("%s is not a Range" % _path(found.control))
	found.control.value = float(request.get("value", 0.0)) # Range emits value_changed itself
	return _settle(2, _control_info(found.control))


func _cmd_key(request: Dictionary) -> Dictionary:
	var keycode := OS.find_keycode_from_string(str(request.get("name", "")))
	if keycode == KEY_NONE:
		return _fail("unknown key name '%s' (examples: W, Escape, Enter, Space, F2, Up)" % request.get("name", ""))
	var make := func(pressed: bool) -> InputEvent:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		return event
	return _emit_input(make, request)


func _cmd_action(request: Dictionary) -> Dictionary:
	var action := StringName(str(request.get("name", "")))
	if not InputMap.has_action(action):
		return _fail("unknown input action '%s'" % action)
	var make := func(pressed: bool) -> InputEvent:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		event.strength = 1.0 if pressed else 0.0
		return event
	return _emit_input(make, request)


func _emit_input(make: Callable, request: Dictionary) -> Dictionary:
	var action := str(request.get("action", "tap"))
	if action not in ["tap", "press", "release"]:
		return _fail("action must be tap, press or release")
	if action != "release":
		Input.parse_input_event(make.call(true))
	if action == "release":
		Input.parse_input_event(make.call(false))
	elif action == "tap":
		_scheduled.append({at_ms = Time.get_ticks_msec() + int(float(request.get("hold_s", 0.05)) * 1000.0),
			event = make.call(false)})
	return _settle(2, {action = action})


func _run_scheduled() -> void:
	var now := Time.get_ticks_msec()
	for item: Dictionary in _scheduled.duplicate():
		if now >= item.at_ms:
			_scheduled.erase(item)
			Input.parse_input_event(item.event)


func _cmd_sticks(request: Dictionary) -> Dictionary:
	var session := _session()
	if session == null or not "read_raw" in session:
		return _fail("no flight session with a keyboard input seam")
	if _bool(request.get("release", false)):
		_restore_sticks()
		return _ok({released = true})
	if _sticks_session != session:
		_restore_sticks()
		_sticks_session = session
		_sticks_original = session.read_raw
		_sticks_reader = _read_override
	for axis: String in ["roll", "pitch", "yaw"]:
		_sticks[axis] = clampf(float(request.get(axis, _sticks.get(axis, 0.0))), -1.0, 1.0)
	if request.has("throttle"):
		_sticks.throttle = clampf(float(request.throttle), 0.0, 1.0)
	_sticks_until_tick = -1
	if request.has("for_s"):
		_sticks_until_tick = int(session.sim.tick) + maxi(1, roundi(float(request.for_s) / session.sim.dt()))
	session.read_raw = _sticks_reader
	var warning := ""
	if "radio" in session and session.radio.connected:
		warning = "a radio/gamepad is connected: it flies instead of the keyboard seam"
	return _ok({sticks = _sticks.duplicate(), until_tick = _sticks_until_tick, warning = warning})


## Keyboard-seam sample: roll/pitch/yaw are stick targets; throttle is turned into the key rate that reaches the
## requested position (the keyboard throttle is an up/down rate, see Commands.step_commands).
func _read_override() -> Dictionary:
	var raw := {roll = float(_sticks.get("roll", 0.0)), pitch = float(_sticks.get("pitch", 0.0)),
		yaw = float(_sticks.get("yaw", 0.0)), throttle = 0.0}
	if _sticks.has("throttle") and is_instance_valid(_sticks_session):
		var current: float = float(_sticks_session.commands.throttle)
		var per_tick: float = Spec.CONTROLS.throttle_rate * _sticks_session.sim.dt()
		raw.throttle = clampf((float(_sticks.throttle) - current) / per_tick, -1.0, 1.0)
	return raw


func _restore_sticks() -> void:
	if is_instance_valid(_sticks_session) and _sticks_session.read_raw == _sticks_reader and _sticks_original.is_valid():
		_sticks_session.read_raw = _sticks_original
	_sticks.clear()
	_sticks_until_tick = -1
	_sticks_session = null


func _cmd_pause(_request: Dictionary) -> Dictionary:
	var session := _session()
	if session == null:
		return _fail("no flight")
	session.sim.set_paused(true)
	return _ok(_flight_state(session))


func _cmd_resume(_request: Dictionary) -> Dictionary:
	var session := _session()
	if session == null:
		return _fail("no flight")
	if session.has_method("resume"):
		session.resume()
	else:
		session.sim.set_paused(false)
	var state := _flight_state(session)
	return _ok(state) if not state.paused else _fail("still paused: reason '%s', holds %s, crashed %s" % [
		state.pause_reason, state.holds, state.crashed])


func _cmd_step(request: Dictionary) -> Dictionary:
	var session := _session()
	if session == null:
		return _fail("no flight")
	if not session.sim.paused:
		return _fail("pause first: step advances a paused flight")
	if _step_target >= 0:
		return _fail("a step is already running")
	var ticks := clampi(int(request.get("ticks", 1)), 1, 240 * 600)
	_step_sim = session.sim
	_step_target = int(session.sim.tick) + ticks
	session.sim.stop_at_tick = _step_target
	session.sim.set_paused(false)
	var sim: Node = session.sim
	return {pending = func() -> Variant:
		if _step_target >= 0 and is_instance_valid(sim) and not sim.fault_reason.is_empty():
			_finish_step(true)
		if _step_target >= 0:
			return null
		return _ok(_flight_state(session)) if is_instance_valid(session) else _fail("flight ended"),
		timeout_s = 60.0 + ticks / 240.0}


func _finish_step(force := false) -> void:
	if _step_target < 0:
		return
	if not is_instance_valid(_step_sim):
		_step_target = -1
		return
	if force or int(_step_sim.tick) >= _step_target or _step_sim.paused:
		_step_sim.set_paused(true)
		if _step_sim.stop_at_tick == _step_target:
			_step_sim.stop_at_tick = -1
		_step_target = -1


func _cmd_time_scale(request: Dictionary) -> Dictionary:
	if request.has("value"):
		Engine.time_scale = clampf(float(request.value), 0.05, 16.0)
	return _ok({time_scale = Engine.time_scale, max_physics_steps_per_frame = Engine.max_physics_steps_per_frame})


func _cmd_wait(request: Dictionary) -> Dictionary:
	if request.has("until"):
		var expression := Expression.new()
		if expression.parse(str(request.until), PackedStringArray(["app", "tree", "bridge"])) != OK:
			return _fail("parse error: " + expression.get_error_text())
		return {pending = func() -> Variant:
			var value: Variant = expression.execute([app, get_tree(), self], app, false)
			if expression.has_execute_failed() or not value:
				return null
			return _ok({frame = Engine.get_process_frames(), value = value}),
			timeout_s = 10.0}
	if request.has("seconds"):
		var until := Time.get_ticks_msec() + int(float(request.seconds) * 1000.0)
		return {pending = func() -> Variant:
			return _ok({frame = Engine.get_process_frames()}) if Time.get_ticks_msec() >= until else null,
			timeout_s = float(request.seconds) + 5.0}
	return _settle(maxi(1, int(request.get("frames", 1))), {})


func _cmd_screenshot(request: Dictionary) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return _fail("no renderer under --headless; launch under Xvfb or a desktop")
	_shot_index += 1
	var path := str(request.get("path", "user://debug_bridge/shot-%d-%03d.png" % [OS.get_process_id(), _shot_index]))
	var max_width := int(request.get("max_width", 0))
	var drawn := [false]
	RenderingServer.frame_post_draw.connect(func() -> void: drawn[0] = true, CONNECT_ONE_SHOT)
	return {pending = func() -> Variant:
		if not drawn[0]:
			return null
		var image := get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			return _fail("the viewport returned no image")
		if max_width > 0 and image.get_width() > max_width:
			image.resize(max_width, roundi(image.get_height() * float(max_width) / image.get_width()), Image.INTERPOLATE_LANCZOS)
		var absolute := ProjectSettings.globalize_path(path)
		DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
		var err := image.save_png(absolute)
		return _ok({path = absolute, width = image.get_width(), height = image.get_height()}) if err == OK \
			else _fail("cannot save %s: %s" % [absolute, error_string(err)]),
		timeout_s = 10.0}


func _cmd_eval(request: Dictionary) -> Dictionary:
	var base: Node = app
	if request.has("node"):
		base = _node(str(request.node))
		if base == null:
			return _fail("no node at '%s'" % request.node)
	var expression := Expression.new()
	if expression.parse(str(request.get("expr", "")), PackedStringArray(["app", "tree", "bridge"])) != OK:
		return _fail("parse error: " + expression.get_error_text())
	var value: Variant = expression.execute([app, get_tree(), self], base, false)
	if expression.has_execute_failed():
		return _fail("execution failed: " + expression.get_error_text())
	return _ok(value)


func _cmd_nodes(request: Dictionary) -> Dictionary:
	var root: Node = _node(str(request.get("path", "/root")))
	if root == null:
		return _fail("no node at '%s'" % request.get("path", ""))
	var count := [0]
	return _ok(_outline(root, clampi(int(request.get("depth", 2)), 0, 12), count))


func _cmd_quit(request: Dictionary) -> Dictionary:
	get_tree().quit.call_deferred(int(request.get("code", 0)))
	return _ok({quitting = true})


# ---- helpers --------------------------------------------------------------------------------------------------

func _settle(frames: int, result: Dictionary) -> Dictionary:
	var until := Engine.get_process_frames() + frames
	return {pending = func() -> Variant:
		if Engine.get_process_frames() < until:
			return null
		result.screens = _screen_ids()
		result.focus = _path(get_viewport().gui_get_focus_owner())
		return _ok(result)}


func _route() -> String:
	if app == null:
		return "none"
	if app.get("ground_vehicle") != null:
		return "ground_vehicle"
	if app.get("flight") != null:
		return "flight"
	if app.get("home") != null:
		return "home"
	return "starting"


func _session() -> Node:
	var flight: Variant = app.get("flight") if app != null else null
	if flight == null or not is_instance_valid(flight):
		return null
	var session: Variant = flight.get("session")
	return session if session is Node and is_instance_valid(session) and "sim" in session else null


func _screen_ids() -> Array:
	var screens: Variant = app.get("screens") if app != null else null
	var ids: Array = []
	if screens != null and "_entries" in screens:
		for entry: Dictionary in screens._entries:
			ids.append(entry.id)
	return ids


func _flight_state(session: Node) -> Dictionary:
	var sim: Node = session.sim
	var s: PackedFloat64Array = sim.state
	var out := {aircraft = app.flight.get("aircraft_id"), tick = sim.tick, time_s = sim.time(), paused = sim.paused,
		fault = sim.fault_reason, pause_reason = session.get("pause_reason"),
		holds = session.holds.keys() if "holds" in session else [], crashed = "crash" in session and not session.crash.is_empty(),
		radio_connected = "radio" in session and session.radio.connected, commands = session.get("commands"),
		raw = session.get("raw")}
	if s.size() >= RB.SIZE:
		var w := s[RB.ATT]
		var x := s[RB.ATT + 1]
		var y := s[RB.ATT + 2]
		var z := s[RB.ATT + 3]
		out.position_ned_m = [s[RB.POS], s[RB.POS + 1], s[RB.POS + 2]]
		out.height_m = -s[RB.POS + 2]
		out.velocity_body_mps = [s[RB.VEL], s[RB.VEL + 1], s[RB.VEL + 2]]
		out.speed_mps = sqrt(s[RB.VEL] ** 2 + s[RB.VEL + 1] ** 2 + s[RB.VEL + 2] ** 2)
		out.attitude_deg = {
			roll = rad_to_deg(atan2(2.0 * (w * x + y * z), 1.0 - 2.0 * (x * x + y * y))),
			pitch = rad_to_deg(asin(clampf(2.0 * (w * y - z * x), -1.0, 1.0))),
			heading = fposmod(rad_to_deg(atan2(2.0 * (w * z + x * y), 1.0 - 2.0 * (y * y + z * z))), 360.0)}
		out.rates_body_degps = [rad_to_deg(s[RB.RATE]), rad_to_deg(s[RB.RATE + 1]), rad_to_deg(s[RB.RATE + 2])]
	return out


func _ui_scope() -> Node:
	var screens: Variant = app.get("screens") if app != null else null
	if screens != null and screens.top() != null:
		return screens.top()
	return get_tree().root


func _controls(scope: Node, labels: bool) -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [scope]
	while not stack.is_empty() and out.size() < UI_LIMIT * 4:
		var node: Node = stack.pop_back()
		if node is CanvasLayer and not node.visible:
			continue
		if node is Control:
			if not node.is_visible_in_tree():
				continue
			if node is BaseButton or node is LineEdit or node is TextEdit or node is Range or node is ItemList \
					or node is TabBar or (labels and (node is Label or node is RichTextLabel)):
				out.append(node)
		var children := node.get_children()
		children.reverse()
		stack.append_array(children)
	return out


func _control_info(control: Control) -> Dictionary:
	var info := {path = _path(control), type = control.get_class(), text = _label(control),
		focused = control.has_focus(), rect = [roundi(control.global_position.x), roundi(control.global_position.y),
			roundi(control.size.x), roundi(control.size.y)]}
	if control is BaseButton:
		info.disabled = control.disabled
		if control.toggle_mode:
			info.pressed = control.button_pressed
	if control is OptionButton:
		info.selected = control.selected
		info.items = range(control.item_count).map(func(i: int) -> String: return control.get_item_text(i))
	if control is Range:
		info.value = control.value
		info.min = control.min_value
		info.max = control.max_value
	if control is LineEdit:
		info.editable = control.editable
	return info


static func _label(control: Control) -> String:
	for property: String in ["text", "placeholder_text", "tooltip_text"]:
		if property in control and not str(control.get(property)).is_empty():
			return str(control.get(property))
	return str(control.name)


func _find_control(request: Dictionary) -> Dictionary:
	if request.has("path"):
		var node := _node(str(request.path))
		return {control = node} if node is Control else {error = "no Control at '%s'" % request.path}
	if not request.has("text"):
		return {error = "give text=<label> or path=<node>"}
	var wanted := str(request.text).to_lower()
	var scope: Node = get_tree().root if _bool(request.get("all", false)) else _ui_scope()
	var exact: Array[Control] = []
	var partial: Array[Control] = []
	for control: Control in _controls(scope, false):
		var label := _label(control).to_lower()
		if label == wanted:
			exact.append(control)
		elif label.contains(wanted):
			partial.append(control)
	var matches := exact if not exact.is_empty() else partial
	if matches.size() == 1:
		return {control = matches[0]}
	if matches.is_empty():
		return {error = "no visible control labelled '%s' in %s; list them with ui" % [request.text, _path(scope)]}
	return {error = "'%s' is ambiguous: %s; use path=" % [request.text, ", ".join(matches.map(func(c: Control) -> String:
		return _path(c)))]}


func _node(path: String) -> Node:
	if path.is_empty() or path == "/root":
		return get_tree().root
	return get_tree().root.get_node_or_null(NodePath(path.trim_prefix("/root/")))


func _path(node: Node) -> String:
	return str(get_tree().root.get_path_to(node)) if node != null and is_instance_valid(node) and node.is_inside_tree() else ""


func _outline(node: Node, depth: int, count: Array) -> Dictionary:
	count[0] += 1
	var info := {name = str(node.name), type = node.get_class(), children = node.get_child_count()}
	if node.get_script() != null:
		info.script = node.get_script().resource_path
	if node is CanvasItem or node is Node3D or node is CanvasLayer:
		info.visible = node.visible
	if depth > 0 and count[0] < NODE_LIMIT:
		var kids: Array = []
		for child: Node in node.get_children():
			if count[0] >= NODE_LIMIT:
				info.truncated = true
				break
			kids.append(_outline(child, depth - 1, count))
		info.nodes = kids
	return info


static func _bool(value: Variant) -> bool:
	return value if value is bool else str(value).to_lower() in ["1", "true", "yes", "on"]


## JSON-safe copy: non-finite floats become strings, vectors arrays, objects a short description.
static func jsonable(value: Variant, depth := 0) -> Variant:
	if depth > 10:
		return str(value)
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			return value if is_finite(value) else str(value)
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_QUATERNION:
			return [value.x, value.y, value.z, value.w]
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_DICTIONARY:
			var out := {}
			for key: Variant in value:
				out[str(key)] = jsonable(value[key], depth + 1)
			return out
		TYPE_OBJECT:
			if not is_instance_valid(value):
				return null
			if value is Node and value.is_inside_tree():
				return "<%s %s>" % [value.get_class(), value.get_path()]
			return "<%s#%d>" % [value.get_class(), value.get_instance_id()]
	if value is Array or (typeof(value) >= TYPE_PACKED_BYTE_ARRAY and typeof(value) <= TYPE_PACKED_VECTOR4_ARRAY):
		var items: Array = []
		for item: Variant in value:
			items.append(jsonable(item, depth + 1))
		return items
	return var_to_str(value)
