# PT1h-R7: live debug bridge for coding agents. Opt-in (environment OPENRC_DEBUG_BRIDGE, debug builds only), it
# listens on 127.0.0.1 for newline-delimited JSON requests {"id", "cmd", ...args} and answers one JSON line each:
# state, live logs, the visible UI (press/focus/type by text, no mouse), keys, pilot sticks, pause/step,
# screenshots, route shortcuts (fly/home/restart), live sampling, performance counters, property get/set/call and
# Expression evaluation against AppRoot. State changes are logged as "event" records. Client and command reference:
# tools/debug/README.md.
# Pattern after godot-mcp-runtime (MIT, github.com/Erodenn/godot-mcp-runtime): loopback TCP, token, ALWAYS mode.
# It never changes the launch route or project settings; everything it does is an explicit request.
# Threads: a network thread owns the sockets and the JSONL file, answers help/ping/logs and state (from the snapshot
# the main thread publishes each frame while a client is active) at once, and queues every other command for the
# main thread, which runs it in _process. A slow-rendering frame therefore never delays a ping, log or state read.
extends Node

const DebugLog := preload("res://debug/debug_log.gd")
const Spec := preload("res://spec.gd")
const RB := preload("res://physics/rigid_body.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const ControlsReference := preload("res://ui/controls_reference.gd")
const ControllerActions := preload("res://input/controller_actions.gd")
const ScreenStack := preload("res://ui/screen_stack.gd")
## AppRoot openers by screen name (each takes an optional focus-return control).
const SCREEN_OPENERS := {pause = "open_pause", settings = "open_settings", controls = "open_controls", help = "open_help",
	weather = "open_weather", time_of_day = "open_time_of_day", overlays = "open_overlays",
	failures = "open_failures_settings", companions = "open_companions_settings", natural_random = "open_natural_random",
	workshop = "open_workshop"}
const MENU_ACTIONS := {accept = &"ui_accept", navigate_up = &"ui_up", navigate_down = &"ui_down",
	navigate_left = &"ui_left", navigate_right = &"ui_right"}
const CameraViews := ["pilot", "chase", "orbit", "closeup"]

const ENV_BRIDGE := "OPENRC_DEBUG_BRIDGE"
const ENV_TOKEN := "OPENRC_DEBUG_TOKEN"
const ENV_LOG := "OPENRC_DEBUG_LOG"
const ENV_OUT := "OPENRC_DEBUG_OUT"
const DEFAULT_PORT := 47870
const MAX_CLIENTS := 8
const MAX_LINE_BYTES := 1 << 20
const MAX_OUT_BYTES := 64 << 20
const UI_LIMIT := 400
const NODE_LIMIT := 600
## Commands the network thread answers itself; everything else touches the scene and runs on the main thread.
const THREAD_COMMANDS := ["help", "ping", "logs", "state"]
## Keep publishing state snapshots this long after the last request (idle sessions cost nothing).
const SNAPSHOT_IDLE_MS := 30000
## Publish at most this often (a state read is then at most this old, or one frame on a slow renderer).
const SNAPSHOT_INTERVAL_MS := 50
const COMMANDS := {
	"help": "this list",
	"ping": "liveness: pid, engine version, frame, fps",
	"state": "route, screens, focus, fps, log counts; flight: aircraft, tick, pause/holds/crash, pose, commands",
	"fly": "aircraft=<catalog id> start=<runway|airborne|...>: from Home, select and fly (no menu navigation)",
	"home": "end the flight and return to Home (like Pause > Exit; a recorder may ask first)",
	"restart": "restart the flight (Pause > Restart flight)",
	"view": "name=pilot|chase|orbit|closeup: camera view (no name: the current one)",
	"record": "action=start|stop|mark|status: the flight log (.orfl), like F10/F11",
	"perf": "frame/physics time, fps, memory, objects, nodes, orphans, draw calls, simulation step cost",
	"frames": "window=<n> hitch_ms=<ms> factor=<x> reset=<bool>: frame-time percentiles, 1 % low, hitches with causes",
	"break": "expr=<expression> name=<s> pause=<bool> once=<bool> wait=<bool> | list=true | clear=<name|all>: tick watchpoint",
	"objects": "top=<n> baseline=<bool> diff=<bool>: live nodes by class/script, orphan nodes, totals (leak hunting)",
	"profile": "seconds=<s> | since=<log seq> top=<n> sort=self|total: GDScript functions by time (launch --script-profile)",
	"sample": "exprs={name: expr} every_ticks=<n> count=<m>: values each n simulation ticks (live telemetry)",
	"assert": "expr=<expression> message=<s>: ok when truthy, else an error (for repro scripts)",
	"find": "name=<glob> type=<class> under=<path> limit=<n>: nodes by name pattern and class",
	"get": "node=<path> prop=<property>: one property (or all script variables when prop is empty)",
	"set": "node=<path> prop=<property> value=<json>: assign; arrays become vectors/colours when the property is one",
	"call": "node=<path> method=<name> args=[...]: call a method and return its result",
	"logs": "since=<seq> limit=<n> level=<error,warning,...> summary=<bool>: log records after a cursor, or grouped",
	"ui": "all=<bool> labels=<bool> text=<substring>: visible controls of the top dialog/popup/screen (or everything)",
	"open": "screen=<pause|settings|controls|help|weather|time_of_day|overlays|failures|companions|natural_random|workshop> (none: list)",
	"close": "close the top dialog, popup or menu screen (like Esc/Back)",
	"control": "name=<controller action> hold=<bool>: what a bound controller button does; no name lists them",
	"shortcuts": "the keyboard table for the current vehicle (keys usable with key name=), controller actions, input map",
	"prefs": "the saved preferences and display settings as the app holds them now",
	"methods": "node=<path> private=<bool>: script methods with argument names (call them with call)",
	"mouse": "action=click|double|right|move|down|up|drag|wheel x= y= | text=|path= [to_x= to_y=] [amount=]",
	"press": "text=<label>|path=<node> mode=accept|signal: activate a button like Enter on the focused control",
	"focus": "text=|path=: give a control keyboard focus",
	"type": "text=<s> submit=<bool> [into=<label>|path=]: insert text into the focused (or named) LineEdit/TextEdit",
	"select": "path=|text= index=<i>|item=<label>: OptionButton/ItemList item or TabBar tab; popup=true: open PopupMenu",
	"set_value": "path=|text= value=<v>: set a Range (slider/spin box) value",
	"key": "name=<W|Escape|F2|Shift+F|Ctrl+S...> action=tap|press|release hold_s=<s>: keyboard event (see shortcuts)",
	"action": "name=<input action> action=tap|press|release: input-map action event",
	"sticks": "roll pitch yaw (-1..1, pitch + = stick back) throttle (0..1 target) for_s=<s> | release=true",
	"drive": "throttle (0..1) steering (-1..1) brake (0..1) reverse=<bool> for_s=<s> | release=true: RC ground vehicle",
	"pause": "freeze the flight simulation (sim only; menus keep running)",
	"resume": "the pilot's continue (refused during menus, crash, calibration)",
	"step": "ticks=<n>: advance a paused flight exactly n physics ticks, then pause",
	"time_scale": "value=<x>: Engine.time_scale (0.05..16)",
	"window": "size=<WxH> mode=windowed|fullscreen: OS window (1920x1080 is the primary target); no args reports it",
	"wait": "frames=<n> | seconds=<s> | until=<expr> timeout_s=<s>",
	"screenshot": "path=<png|jpg> format=png|jpg max_width=<px>: viewport picture (needs a renderer: Xvfb, not --headless)",
	"eval": "expr=<GDScript expression> node=<path>: evaluate on AppRoot (inputs: app, tree, bridge, engine singletons)",
	"nodes": "path=<node> depth=<n>: scene-tree outline",
	"quit": "code=<n>: quit the engine after replying",
}

var port := DEFAULT_PORT
var token := "":
	set(value):
		_net_mutex.lock()
		token = value
		_net_mutex.unlock()
var log_path := ""
var debug_log := DebugLog.new()
var app: Node
## Smoothed main-thread overhead of the bridge per frame (µs), excluding the work commands request; perf and state.
var bridge_usec := 0.0
var _server := TCPServer.new()
var _thread := Thread.new()
var _net_mutex := Mutex.new()
var _stopping := false
var _inbox: Array[Dictionary] = [] # requests for the main thread
var _outbox: Array[Dictionary] = [] # replies for the network thread to send
var _dropped: Array[int] = [] # disconnected peers whose pending work the main thread forgets
var _snapshot := {} # last published state reply (jsonable), with its frame
var _last_request_ms := 0
var _snapshot_ms := 0
var _display_name := ""
var _clients := {} # network thread only: peer id -> {peer, buffer}
var _next_peer_id := 1
var _pending: Array[Dictionary] = []
var _current := {} # the request being dispatched on the main thread: {peer_id, id}, for replies sent by workers
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
var out_dir := ""
var _samples: Array[Dictionary] = []
var _watch := {}
var _rate_mark := {msec = 0, tick = -1}
## Frame history (PT1h-R8): wall time per frame, physics ticks per frame, and recent hitches with their context.
const FRAME_CAPACITY := 7200
var _frame_ms := PackedFloat64Array()
var _frame_ticks := PackedInt32Array()
var _frame_count := 0
var _frame_last_us := 0
var _frame_ema_ms := 0.0
var _frame_physics_ticks := 0
var _frame_monitors := {}
var _frame_log_seq := 0
var hitch_ms := 50.0
var hitch_factor := 3.0
var _hitches: Array[Dictionary] = []
var _breaks: Array[Dictionary] = []
var _objects_baseline := {}
var _drive_vehicle: Node
var _drive_until_tick := -1
var realtime_factor := -1.0


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
	out_dir = OS.get_environment(ENV_OUT)
	if not log_path.is_empty():
		_log_file = FileAccess.open(log_path, FileAccess.WRITE)
		if _log_file == null:
			push_warning("debug bridge: cannot write %s: %s" % [log_path, error_string(FileAccess.get_open_error())])
	_display_name = DisplayServer.get_name()
	var err := _server.listen(port, "127.0.0.1")
	if err != OK:
		push_error("debug bridge: cannot listen on 127.0.0.1:%d: %s" % [port, error_string(err)])
		return
	print("debug bridge: listening on 127.0.0.1:%d (pid %d)" % [_server.get_local_port(), OS.get_process_id()])
	_thread.start(_serve)


func _exit_tree() -> void:
	_restore_sticks()
	_release_drive()
	_net_mutex.lock()
	_stopping = true
	_net_mutex.unlock()
	if _thread.is_started():
		_thread.wait_to_finish() # its last pass sends queued replies (quit) and the remaining log lines
	OS.remove_logger(debug_log)


func _process(_delta: float) -> void:
	var started := Time.get_ticks_usec()
	_record_frame(started)
	_net_mutex.lock()
	var inbox := _inbox
	_inbox = []
	var dropped := _dropped
	_dropped = []
	var active := Time.get_ticks_msec() - _last_request_ms < SNAPSHOT_IDLE_MS
	_net_mutex.unlock()
	for peer_id: int in dropped:
		_forget_peer(peer_id)
	var handlers_started := Time.get_ticks_usec()
	for item: Dictionary in inbox:
		_handle(item.peer_id, item.id, item.request)
	_run_scheduled()
	_run_pending()
	# The work a command asked for (building a flight, a screenshot readback) is not bridge overhead.
	started += Time.get_ticks_usec() - handlers_started
	_observe()
	var now_ms := Time.get_ticks_msec()
	_net_mutex.lock()
	var invalidated := _snapshot.is_empty()
	_net_mutex.unlock()
	if active and (invalidated or now_ms - _snapshot_ms >= SNAPSHOT_INTERVAL_MS):
		_snapshot_ms = now_ms
		# Plain values only (no objects): the network thread converts it when it sends, off the frame.
		var snapshot: Dictionary = _cmd_state({})
		snapshot.frame = Engine.get_process_frames()
		snapshot.ms = now_ms
		_net_mutex.lock()
		_snapshot = snapshot
		_net_mutex.unlock()
	bridge_usec = lerpf(bridge_usec, float(Time.get_ticks_usec() - started), 0.05)


# ---- network thread -------------------------------------------------------------------------------------------

func _serve() -> void:
	while true:
		_net_mutex.lock()
		var stopping := _stopping
		_net_mutex.unlock()
		while _server.is_connection_available():
			var peer := _server.take_connection()
			if _clients.size() >= MAX_CLIENTS:
				peer.disconnect_from_host()
				continue
			peer.set_no_delay(true)
			_clients[_next_peer_id] = {peer = peer, buffer = PackedByteArray(), out = PackedByteArray(), closing = false}
			_next_peer_id += 1
		for peer_id: int in _clients.keys():
			_read_client(peer_id)
		_send_outbox()
		for peer_id: int in _clients.keys():
			_flush_client(peer_id)
		_write_log_file()
		if stopping:
			_drain_clients()
			break
		OS.delay_msec(2)
	for client: Dictionary in _clients.values():
		client.peer.disconnect_from_host()
	_clients.clear()
	_server.stop()


func _read_client(peer_id: int) -> void:
	var client: Dictionary = _clients[peer_id]
	var peer: StreamPeerTCP = client.peer
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_drop_client(peer_id)
		return
	if client.closing:
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
				_close_with(peer_id, {ok = false, error = "request line exceeds %d bytes" % MAX_LINE_BYTES})
			return
		var line: String = client.buffer.slice(0, newline).get_string_from_utf8().strip_edges()
		client.buffer = client.buffer.slice(newline + 1)
		if not line.is_empty() and not _route_line(peer_id, line):
			return # the connection is closing: nothing after an invalid line runs


## Send what fits without blocking; a client that stops reading only fills its own buffer, never stalls the bridge.
func _flush_client(peer_id: int) -> void:
	if not _clients.has(peer_id):
		return
	var client: Dictionary = _clients[peer_id]
	if not client.out.is_empty():
		var sent: Array = client.peer.put_partial_data(client.out)
		if sent[0] == OK:
			client.out = client.out.slice(int(sent[1]))
		elif sent[0] != ERR_BUSY:
			_drop_client(peer_id)
			return
	if client.closing and client.out.is_empty():
		client.peer.disconnect_from_host()
		_drop_client(peer_id)
	elif client.out.size() > MAX_OUT_BYTES:
		_drop_client(peer_id) # a reader this far behind is gone or stuck


## Bounded final flush when the engine quits, so the reply to quit and other queued replies still leave.
func _drain_clients() -> void:
	var deadline := Time.get_ticks_msec() + 500
	while Time.get_ticks_msec() < deadline:
		var waiting := false
		for peer_id: int in _clients.keys():
			_clients[peer_id].peer.poll()
			_flush_client(peer_id)
			waiting = waiting or (_clients.has(peer_id) and not _clients[peer_id].out.is_empty())
		if not waiting:
			return
		OS.delay_msec(1)


func _queue_bytes(peer_id: int, bytes: PackedByteArray) -> void:
	if _clients.has(peer_id):
		_clients[peer_id].out.append_array(bytes)


## Answer once, then close: used for protocol violations so the rest of the stream is never interpreted.
func _close_with(peer_id: int, reply: Dictionary) -> void:
	_queue_bytes(peer_id, _encode(reply))
	_clients[peer_id].closing = true
	_clients[peer_id].buffer = PackedByteArray()


func _drop_client(peer_id: int) -> void:
	if not _clients.has(peer_id):
		return
	_clients.erase(peer_id)
	_net_mutex.lock()
	_dropped.append(peer_id)
	_net_mutex.unlock()


## Network thread: validate one request line, answer thread-safe commands, queue the rest for the main thread.
## Returns false when the line was invalid and the connection is now closing. A web page can POST to 127.0.0.1;
## its HTTP request line is not JSON, so the connection closes before the body could be read as a command.
func _route_line(peer_id: int, line: String) -> bool:
	var parser := JSON.new() # parse_string would log an engine error for every malformed line
	var request: Variant = parser.data if parser.parse(line) == OK else null
	if not request is Dictionary or not request.has("cmd"):
		_close_with(peer_id, {ok = false, error = "expected one JSON object with \"cmd\" per line; closing"})
		return false
	var id: Variant = request.get("id")
	if id is float and id == floorf(id):
		id = int(id) # JSON numbers parse as floats
	_net_mutex.lock()
	var expected := token
	_last_request_ms = Time.get_ticks_msec()
	var snapshot := _snapshot
	_net_mutex.unlock()
	if not expected.is_empty() and not _same_secret(str(request.get("token", "")), expected):
		_close_with(peer_id, {id = id, ok = false, error = "bad or missing token; closing"})
		return false
	var cmd := str(request.cmd)
	if cmd in THREAD_COMMANDS and not _bool(request.get("fresh", false)):
		var reply := _thread_reply(cmd, request, snapshot)
		if not reply.is_empty():
			reply.id = id
			_queue_bytes(peer_id, _encode(reply))
			return true
	_net_mutex.lock()
	_inbox.append({peer_id = peer_id, id = id, request = request})
	_net_mutex.unlock()
	return true


## Constant-time comparison: the time taken does not reveal how much of a guessed token matched.
static func _same_secret(given: String, expected: String) -> bool:
	var a := given.to_utf8_buffer()
	var b := expected.to_utf8_buffer()
	var difference := a.size() ^ b.size()
	for i in b.size():
		difference |= (a[i] if i < a.size() else 0) ^ b[i]
	return difference == 0


## Replies built only from thread-safe sources: constants, the locked log and the published snapshot.
## Empty means "ask the main thread" (no snapshot yet, or an older frame than the one just finished).
func _thread_reply(cmd: String, request: Dictionary, snapshot: Dictionary) -> Dictionary:
	match cmd:
		"help":
			return _ok(COMMANDS)
		"logs":
			return _cmd_logs(request)
		"ping":
			return _ok({pid = OS.get_process_id(), godot = Engine.get_version_info().string,
				frame = Engine.get_process_frames(), fps = Engine.get_frames_per_second(), display = _display_name,
				log_seq = debug_log.last_seq(), log_counts = debug_log.counts(),
				route = snapshot.get("result", {}).get("route", "unknown"), out_dir = out_dir})
		"state":
			var age_ms := Time.get_ticks_msec() - int(snapshot.get("ms", 0))
			if snapshot.is_empty() or (int(snapshot.frame) < Engine.get_process_frames() - 1 and age_ms > 2 * SNAPSHOT_INTERVAL_MS):
				return {}
			var reply: Dictionary = snapshot.duplicate(true)
			reply.result.snapshot_frame = reply.frame
			reply.result.snapshot_age_ms = age_ms
			reply.erase("frame")
			reply.erase("ms")
			return reply
	return {}


func _send_outbox() -> void:
	_net_mutex.lock()
	var outbox := _outbox
	_outbox = []
	_net_mutex.unlock()
	for item: Dictionary in outbox:
		_queue_bytes(item.peer_id, item.bytes)


static func _encode(reply: Dictionary) -> PackedByteArray:
	return (JSON.stringify(jsonable(reply), "", false, true) + "\n").to_utf8_buffer()


# ---- main thread dispatch -------------------------------------------------------------------------------------

func _physics_process(_delta: float) -> void:
	_frame_physics_ticks += 1
	# Before the session samples input and the simulation steps: a step or drive ends exactly at its tick.
	_finish_step()
	_check_breaks()
	_expire_drive()
	_collect_samples()
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


func _forget_peer(peer_id: int) -> void:
	for item: Dictionary in _pending:
		if item.peer_id != peer_id:
			continue
		if not item.job.is_empty():
			_samples.erase(item.job) # an abandoned sample stops collecting
		if item.on_timeout.is_valid():
			item.on_timeout.call() # its cleanup (e.g. awaiting a screenshot encoder) still runs
	_pending = _pending.filter(func(item: Dictionary) -> bool: return item.peer_id != peer_id)


func _handle(peer_id: int, id: Variant, request: Dictionary) -> void:
	var reply: Dictionary
	var cmd := str(request.cmd)
	if not COMMANDS.has(cmd):
		reply = _fail("unknown command '%s'; try help" % cmd)
	else:
		_current = {peer_id = peer_id, id = id}
		var result: Variant = call("_cmd_" + cmd, request)
		# A script error inside a handler returns nothing; its message is already in the log.
		reply = result if result is Dictionary and not result.is_empty() \
			else _fail("'%s' failed with a script error; see logs level=script_error" % cmd)
	if reply.has("pending"):
		var given: Variant = _number(request.get("timeout_s", reply.get("timeout_s", 30.0)))
		var timeout_s: float = given if given != null else 30.0
		_pending.append({peer_id = peer_id, id = id, check = reply.pending, job = reply.get("job", {}),
			on_timeout = reply.get("on_timeout", Callable()),
			deadline_ms = Time.get_ticks_msec() + int(clampf(timeout_s, 0.0, 3600.0) * 1000.0)})
		return
	_reply(peer_id, id, reply)


func _run_pending() -> void:
	for item: Dictionary in _pending.duplicate():
		var result: Variant = item.check.call()
		if result == null and Time.get_ticks_msec() < item.deadline_ms:
			continue
		_pending.erase(item)
		if not item.job.is_empty():
			_samples.erase(item.job) # a timed-out sample stops collecting
		var final: Dictionary = result if result is Dictionary \
			else (item.on_timeout.call() if item.on_timeout.is_valid() else _fail("timed out"))
		if not final.get("_replied", false): # else a worker already sent the reply
			_reply(item.peer_id, item.id, final)


func _reply(peer_id: int, id: Variant, reply: Dictionary) -> void:
	reply.id = id
	var bytes := _encode(reply)
	_net_mutex.lock()
	_outbox.append({peer_id = peer_id, bytes = bytes})
	# Read-after-write: a client that sees this reply must not then read a snapshot taken before the command.
	_snapshot = {}
	_net_mutex.unlock()


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
		fps = Engine.get_frames_per_second(), display = DisplayServer.get_name(), log_seq = debug_log.last_seq(),
		log_counts = debug_log.counts(), route = _route(), out_dir = out_dir})


func _cmd_state(_request: Dictionary) -> Dictionary:
	var out := {frame = Engine.get_process_frames(), fps = Engine.get_frames_per_second(), time_scale = Engine.time_scale,
		tree_paused = get_tree().paused, log_seq = debug_log.last_seq(), route = _route(), screens = _screen_ids(),
		focus = _path(get_viewport().gui_get_focus_owner()), sticks_override = _sticks.duplicate(),
		log_counts = debug_log.counts(), realtime_factor = realtime_factor, bridge_usec = bridge_usec}
	var session := _session()
	if session != null:
		out.flight = _flight_state(session)
	return _ok(out)


func _cmd_logs(request: Dictionary) -> Dictionary:
	if _bool(request.get("summary", false)):
		return _log_summary(request)
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
	var out := {scope = _path(scope), focus = _path(get_viewport().gui_get_focus_owner()), controls = items}
	if scope is Window and scope != get_tree().root:
		out.window = {type = scope.get_class(), title = scope.title}
		if scope is PopupMenu:
			out.window.items = _item_labels(scope)
	return _ok(out)


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
	return _settle(int(request.get("frames", 1)), {pressed = path, mode = mode})


func _cmd_focus(request: Dictionary) -> Dictionary:
	var found := _find_control(request)
	if found.has("error"):
		return _fail(found.error)
	found.control.grab_focus()
	return _settle(1, {focused = _path(found.control)})


func _cmd_type(request: Dictionary) -> Dictionary:
	# An open dialog is its own viewport with its own focus.
	var window := _top_window()
	var control: Control = (window if window != null else get_viewport()).gui_get_focus_owner()
	if request.has("path") or request.has("into"):
		var found := _find_control({path = request.path} if request.has("path") else {text = request.into})
		if found.has("error"):
			return _fail(found.error)
		control = found.control
	if not (control is LineEdit or control is TextEdit):
		return _fail("no LineEdit/TextEdit focused; name one with into=<label or placeholder> or path=")
	control.insert_text_at_caret(str(request.get("text", "")))
	if control is LineEdit:
		control.text_changed.emit(control.text)
		if _bool(request.get("submit", false)):
			control.text_submitted.emit(control.text)
	else:
		control.text_changed.emit()
	return _settle(1, {control = _path(control), text = control.text})


func _cmd_select(request: Dictionary) -> Dictionary:
	var target: Object
	if _bool(request.get("popup", false)):
		target = _top_window()
		if not target is PopupMenu:
			return _fail("no open PopupMenu")
	else:
		var found := _find_control(request)
		if found.has("error"):
			return _fail(found.error)
		target = found.control
	var labels := _item_labels(target)
	if labels.is_empty() and not (target is OptionButton or target is ItemList or target is TabBar or target is PopupMenu):
		return _fail("%s is not an OptionButton, ItemList, TabBar or PopupMenu" % target.get_class())
	var given_index: Variant = _number(request.get("index", -1))
	if given_index == null:
		return _fail("index must be a number")
	var index := int(given_index)
	if request.has("item"):
		var wanted := str(request.item).to_lower()
		var partial: Array[int] = []
		index = -1
		for i in labels.size():
			var label := str(labels[i]).to_lower()
			if label == wanted:
				index = i
				break
			if label.contains(wanted):
				partial.append(i)
		if index < 0:
			if partial.size() != 1:
				return _fail("item '%s' not unique or not found in %s" % [request.item, labels])
			index = partial[0]
	if index < 0 or index >= labels.size():
		return _fail("index out of range 0..%d (items %s)" % [labels.size() - 1, labels])
	if target is OptionButton or target is ItemList:
		target.select(index)
		target.item_selected.emit(index)
	elif target is TabBar:
		target.current_tab = index # emits tab_changed
	elif target is PopupMenu:
		target.id_pressed.emit(target.get_item_id(index))
		target.index_pressed.emit(index)
		target.hide()
	return _settle(1, {selected = index, item = labels[index]})


static func _item_labels(target: Object) -> Array:
	if target is OptionButton or target is ItemList or target is PopupMenu:
		return range(target.item_count).map(func(i: int) -> String: return target.get_item_text(i))
	if target is TabBar:
		return range(target.tab_count).map(func(i: int) -> String: return target.get_tab_title(i))
	return []


func _cmd_set_value(request: Dictionary) -> Dictionary:
	var found := _find_control(request)
	if found.has("error"):
		return _fail(found.error)
	if not found.control is Range:
		return _fail("%s is not a Range" % _path(found.control))
	found.control.value = float(request.get("value", 0.0)) # Range emits value_changed itself
	return _settle(1, _control_info(found.control))


func _cmd_key(request: Dictionary) -> Dictionary:
	var raw_name: Variant = request.get("name", "")
	if raw_name is float and raw_name == floorf(raw_name):
		raw_name = int(raw_name) # JSON makes key 1 the number 1.0
	var parts := str(raw_name).split("+")
	var keycode := OS.find_keycode_from_string(parts[parts.size() - 1])
	if keycode == KEY_NONE:
		return _fail("unknown key name '%s' (examples: W, Escape, Enter, Space, F2, Up, Shift+F; see shortcuts)" % request.get("name", ""))
	var modifiers := PackedStringArray()
	for part: String in parts.slice(0, parts.size() - 1):
		var modifier := part.strip_edges().to_lower()
		if modifier not in ["shift", "ctrl", "alt", "meta", "cmd"]:
			return _fail("unknown modifier '%s' (Shift, Ctrl, Alt, Meta)" % part)
		modifiers.append(modifier)
	var make := func(pressed: bool) -> InputEvent:
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		event.shift_pressed = modifiers.has("shift")
		event.ctrl_pressed = modifiers.has("ctrl")
		event.alt_pressed = modifiers.has("alt")
		event.meta_pressed = modifiers.has("meta") or modifiers.has("cmd")
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
	return _settle(1, {action = action})


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
	var values := {}
	for key: String in ["roll", "pitch", "yaw", "throttle", "for_s"]:
		if request.has(key):
			values[key] = _number(request[key])
			if values[key] == null:
				return _fail("%s must be a number" % key)
	if _sticks_session != session:
		_restore_sticks()
		_sticks_session = session
		_sticks_original = session.read_raw
		_sticks_reader = _read_override
	for axis: String in ["roll", "pitch", "yaw"]:
		_sticks[axis] = clampf(values.get(axis, _sticks.get(axis, 0.0)), -1.0, 1.0)
	if values.has("throttle"):
		_sticks.throttle = clampf(values.throttle, 0.0, 1.0)
	_sticks_until_tick = -1
	if values.has("for_s"):
		_sticks_until_tick = int(session.sim.tick) + maxi(1, roundi(values.for_s / session.sim.dt()))
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


func _cmd_drive(request: Dictionary) -> Dictionary:
	var vehicle: Variant = app.get("ground_vehicle")
	if vehicle == null or not "scripted_controls" in vehicle or vehicle.get("session") == null:
		return _fail("no RC ground vehicle (start one: call node=AppRoot method=start_ground_vehicle args=[\"mt8-bisonte\"])")
	if _bool(request.get("release", false)):
		_release_drive()
		return _ok({released = true})
	var values := {}
	for key: String in ["throttle", "steering", "brake", "for_s"]:
		values[key] = _number(request.get(key, 0.0))
		if values[key] == null:
			return _fail("%s must be a number" % key)
	var controls := {throttle = clampf(values.throttle, 0.0, 1.0), steering = clampf(values.steering, -1.0, 1.0),
		brake = clampf(values.brake, 0.0, 1.0), reverse = _bool(request.get("reverse", false)), source = "debug_bridge",
		armed = true}
	_drive_vehicle = vehicle
	_drive_until_tick = -1
	if request.has("for_s"):
		_drive_until_tick = int(vehicle.session.tick) + maxi(1, roundi(values.for_s * Engine.physics_ticks_per_second))
	vehicle.scripted_controls = func(_tick: int) -> Dictionary: return controls.duplicate()
	return _ok({controls = controls, until_tick = _drive_until_tick})


func _expire_drive() -> void:
	if _drive_until_tick >= 0 and is_instance_valid(_drive_vehicle) and int(_drive_vehicle.session.tick) >= _drive_until_tick:
		_release_drive()


func _release_drive() -> void:
	if is_instance_valid(_drive_vehicle):
		_drive_vehicle.scripted_controls = Callable()
	_drive_vehicle = null
	_drive_until_tick = -1


## pause, resume and step act on flight simulations; the RC truck has its own garage pause (and drive).
func _flight_session() -> Node:
	var session := _session()
	return session if session != null and app.get("flight") != null else null


func _cmd_pause(_request: Dictionary) -> Dictionary:
	var session := _flight_session()
	if session == null:
		return _fail("no flight (the RC truck pauses through its garage: press text=Garage)")
	session.sim.set_paused(true)
	return _ok(_flight_state(session))


func _cmd_resume(_request: Dictionary) -> Dictionary:
	var session := _flight_session()
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
	var session := _flight_session()
	if session == null:
		return _fail("no flight")
	if not session.sim.paused:
		return _fail("pause first: step advances a paused flight")
	if _step_target >= 0:
		return _fail("a step is already running")
	var requested_ticks: Variant = _number(request.get("ticks", 1))
	if requested_ticks == null:
		return _fail("ticks must be a number")
	var ticks := clampi(int(requested_ticks), 1, 240 * 600)
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
		var scale: Variant = _number(request.value)
		if scale == null:
			return _fail("value must be a number")
		Engine.time_scale = clampf(scale, 0.05, 16.0)
	return _ok({time_scale = Engine.time_scale, max_physics_steps_per_frame = Engine.max_physics_steps_per_frame})


func _cmd_window(request: Dictionary) -> Dictionary:
	if request.has("mode"):
		var modes := {windowed = DisplayServer.WINDOW_MODE_WINDOWED, fullscreen = DisplayServer.WINDOW_MODE_FULLSCREEN,
			exclusive = DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, maximized = DisplayServer.WINDOW_MODE_MAXIMIZED}
		if not modes.has(str(request.mode)):
			return _fail("mode must be one of %s" % [modes.keys()])
		DisplayServer.window_set_mode(modes[str(request.mode)])
	if request.has("size"):
		var parts := str(request.size).to_lower().split("x")
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			return _fail("size must look like 1920x1080")
		DisplayServer.window_set_size(Vector2i(parts[0].to_int(), parts[1].to_int()))
	var started := Engine.get_process_frames()
	var deadline := Time.get_ticks_msec() + 5000
	return {pending = func() -> Variant:
		# The root viewport follows the OS window some frames later; wait for it (at most 5 s).
		if Engine.get_process_frames() < started + 2 or (Time.get_ticks_msec() < deadline
				and Vector2i(get_tree().root.size) != DisplayServer.window_get_size()):
			return null
		var out := {window = [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
			viewport = [get_tree().root.size.x, get_tree().root.size.y], mode = DisplayServer.window_get_mode(),
			screen = [DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y], display = DisplayServer.get_name()}
		if Vector2i(get_tree().root.size) != DisplayServer.window_get_size():
			out.warning = "the viewport did not follow the window (Xvfb has no window manager); relaunch with --resolution"
		return _ok(out)}


func _cmd_wait(request: Dictionary) -> Dictionary:
	if request.has("until"):
		var expression := Expression.new()
		if expression.parse(str(request.until), _input_names()) != OK:
			return _fail("parse error: " + expression.get_error_text())
		var last := ["never evaluated"]
		return {pending = func() -> Variant:
			var value: Variant = expression.execute(_input_values(), app, false)
			if expression.has_execute_failed():
				last[0] = "last evaluation failed: " + expression.get_error_text()
				return null
			if not value:
				last[0] = "last value " + JSON.stringify(jsonable(value))
				return null
			return _ok({frame = Engine.get_process_frames(), value = value}),
			timeout_s = 10.0, on_timeout = func() -> Dictionary: return _fail("timed out; " + last[0])}
	if request.has("seconds"):
		var until := Time.get_ticks_msec() + int(float(request.seconds) * 1000.0)
		return {pending = func() -> Variant:
			if Time.get_ticks_msec() < until:
				return null
			return _ok({frame = Engine.get_process_frames()}),
			timeout_s = float(request.seconds) + 5.0}
	return _settle(maxi(1, int(request.get("frames", 1))), {})


func _cmd_screenshot(request: Dictionary) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return _fail("no renderer under --headless; launch under Xvfb or a desktop")
	var format := str(request.get("format", str(request.get("path", "")).get_extension().to_lower()))
	format = "jpg" if format in ["jpg", "jpeg"] else "png"
	_shot_index += 1
	var default_dir := out_dir.path_join("shots") if not out_dir.is_empty() else "user://debug_bridge"
	var path := str(request.get("path", default_dir.path_join("shot-%d-%03d.%s" % [OS.get_process_id(), _shot_index, format])))
	var width_limit: Variant = _number(request.get("max_width", 0))
	if width_limit == null:
		return _fail("max_width must be a number")
	var max_width := int(width_limit)
	var drawn := [false]
	var task := [-1]
	var saved := {}
	var target := _current.duplicate()
	RenderingServer.frame_post_draw.connect(func() -> void: drawn[0] = true, CONNECT_ONE_SHOT)
	return {pending = func() -> Variant:
		if not drawn[0]:
			return null
		if task[0] < 0:
			# Read back on the main thread (the renderer's); scale and encode on a worker so the frame does not hitch.
			var image := get_viewport().get_texture().get_image()
			if image == null or image.is_empty():
				return _fail("the viewport returned no image")
			var absolute := ProjectSettings.globalize_path(path)
			task[0] = WorkerThreadPool.add_task(func() -> void:
				if max_width > 0 and image.get_width() > max_width:
					image.resize(max_width, roundi(image.get_height() * float(max_width) / image.get_width()), Image.INTERPOLATE_LANCZOS)
				DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
				var err: Error = image.save_jpg(absolute, 0.85) if format == "jpg" else image.save_png(absolute)
				var info := {path = absolute, width = image.get_width(), height = image.get_height(), format = format}
				# Reply from the worker as soon as the file exists, not one rendered frame later.
				_reply(target.peer_id, target.id, _ok(info) if err == OK \
					else _fail("cannot save %s: %s" % [absolute, error_string(err)]))
				saved.done = true,
				false, "debug bridge screenshot")
			return null
		if not WorkerThreadPool.is_task_completed(task[0]):
			return null
		WorkerThreadPool.wait_for_task_completion(task[0])
		return {_replied = true},
		timeout_s = 20.0, on_timeout = func() -> Dictionary:
			if task[0] >= 0:
				WorkerThreadPool.wait_for_task_completion(task[0]) # every pool task must be awaited once
			return {_replied = true} if saved.get("done", false) else _fail("timed out")}


func _cmd_eval(request: Dictionary) -> Dictionary:
	var base: Node = app
	if request.has("node"):
		base = _node(str(request.node))
		if base == null:
			return _fail("no node at '%s'" % request.node)
	var expression := Expression.new()
	if expression.parse(str(request.get("expr", "")), _input_names()) != OK:
		return _fail("parse error: " + expression.get_error_text())
	var value: Variant = expression.execute(_input_values(), base, false)
	if expression.has_execute_failed():
		return _fail("execution failed: " + expression.get_error_text())
	return _ok(value)


## Expression inputs: app, tree, bridge, then every engine singleton by name (Expression cannot reach them itself:
## `Performance.get_monitor(...)`, `OS.get_static_memory_usage()`, `RenderingServer...` work through these).
func _input_names(extra: Array = []) -> PackedStringArray:
	var names := PackedStringArray(["app", "tree", "bridge"])
	names.append_array(Engine.get_singleton_list())
	names.append_array(PackedStringArray(extra))
	return names


func _input_values(extra: Array = []) -> Array:
	var values: Array = [app, get_tree(), self]
	for singleton: String in Engine.get_singleton_list():
		values.append(Engine.get_singleton(singleton))
	values.append_array(extra)
	return values


func _cmd_nodes(request: Dictionary) -> Dictionary:
	var root: Node = _node(str(request.get("path", "/root")))
	if root == null:
		return _fail("no node at '%s'" % request.get("path", ""))
	var count := [0]
	return _ok(_outline(root, clampi(int(request.get("depth", 2)), 0, 12), count))


func _cmd_quit(request: Dictionary) -> Dictionary:
	get_tree().quit.call_deferred(int(request.get("code", 0)))
	return _ok({quitting = true})


func _cmd_fly(request: Dictionary) -> Dictionary:
	if _vehicle() != null:
		return _fail("already in an activity; use home first")
	var screens: Variant = app.get("screens")
	if screens == null or not screens.is_top("home"):
		return _fail("fly starts from Home (screens: %s)" % [_screen_ids()])
	if request.has("aircraft"):
		var id := str(request.aircraft)
		if not Catalog.has(id):
			return _fail("unknown aircraft '%s'; flyable: %s" % [id, ", ".join(Catalog.flyable_ids())])
		app.set_aircraft(id)
	if request.has("start"):
		app.set_start_choice(str(request.start))
	app.start_flight()
	return {pending = func() -> Variant:
		var session := _session()
		# Rendered launch creates the session before its staged loading screen closes.
		# Commands following `fly` must see the usable route and its launch review.
		if session == null or not session.is_inside_tree() or _screen_ids().has("loading"):
			return null
		return _ok(_flight_state(session)),
		timeout_s = 240.0}


func _cmd_home(_request: Dictionary) -> Dictionary:
	if app.get("flight") == null:
		return _fail("no flight to end")
	if not _screen_ids().has("pause"):
		app.open_pause()
	app.end_flight()
	var started := Engine.get_process_frames()
	return {pending = func() -> Variant:
		if app.get("flight") == null and app.get("home") != null:
			return _ok({route = _route(), screens = _screen_ids()})
		if Engine.get_process_frames() - started > 120:
			return _fail("still in flight after 120 frames; screens %s (a recorder may be asking: check ui)" % [_screen_ids()])
		return null,
		timeout_s = 60.0}


func _cmd_restart(_request: Dictionary) -> Dictionary:
	if app.get("flight") == null:
		return _fail("no flight to restart")
	if not _screen_ids().has("pause"):
		app.open_pause()
	app.restart_flight()
	return _settle(2, {restarted = true})


func _cmd_view(request: Dictionary) -> Dictionary:
	var flight: Variant = app.get("flight")
	var rig: Variant = flight.get("_rig") if flight != null else null
	if rig == null:
		return _fail("no flight camera rig")
	if request.has("name"):
		var id := str(request.name)
		if not CameraViews.has(id) or not rig.set_view(id):
			return _fail("unknown view '%s'; views: %s" % [id, CameraViews])
	return _ok({view = rig.view, views = CameraViews})


func _cmd_record(request: Dictionary) -> Dictionary:
	var flight: Variant = app.get("flight")
	var recorder: Variant = flight.get("flight_log") if flight != null else null
	if recorder == null:
		return _fail("this flight has no flight log")
	var action := str(request.get("action", "status"))
	var err := OK
	match action:
		"start":
			if not recorder.recording:
				err = recorder.start(str(request.get("path", "")))
		"stop":
			if recorder.recording:
				err = recorder.stop("stopped by debug bridge")
		"mark":
			if not recorder.recording:
				return _fail("not recording")
			recorder.mark(str(request.get("label", "debug bridge marker")))
		"status":
			pass
		_:
			return _fail("action must be start, stop, mark or status")
	if err != OK:
		return _fail("flight log %s failed: %s" % [action, error_string(err)])
	return _ok({recording = recorder.recording, path = ProjectSettings.globalize_path(recorder.path) if not str(recorder.path).is_empty() else "",
		seconds = recorder.seconds()})


func _cmd_perf(_request: Dictionary) -> Dictionary:
	var monitors := {
		fps = Performance.TIME_FPS, process_ms = Performance.TIME_PROCESS, physics_process_ms = Performance.TIME_PHYSICS_PROCESS,
		static_memory_mib = Performance.MEMORY_STATIC, static_memory_peak_mib = Performance.MEMORY_STATIC_MAX,
		objects = Performance.OBJECT_COUNT, resources = Performance.OBJECT_RESOURCE_COUNT, nodes = Performance.OBJECT_NODE_COUNT,
		orphan_nodes = Performance.OBJECT_ORPHAN_NODE_COUNT, draw_calls = Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
		objects_in_frame = Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, primitives_in_frame = Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
		video_memory_mib = Performance.RENDER_VIDEO_MEM_USED,
	}
	var out := {}
	for key: String in monitors:
		var value: float = Performance.get_monitor(monitors[key])
		if key.ends_with("_ms"):
			value *= 1000.0
		elif key.ends_with("_mib"):
			value /= 1048576.0
		out[key] = value
	out.physics_ticks_per_second = Engine.physics_ticks_per_second
	out.max_physics_steps_per_frame = Engine.max_physics_steps_per_frame
	out.realtime_factor = realtime_factor
	out.bridge_usec = bridge_usec
	out.renderer = RenderingServer.get_current_rendering_method()
	out.adapter = RenderingServer.get_video_adapter_name()
	var session := _session()
	if session != null:
		out.sim_step_usec = session.sim.get("step_usec")
	return _ok(out)


func _cmd_sample(request: Dictionary) -> Dictionary:
	var session := _session()
	if session == null:
		return _fail("no simulation to sample")
	var raw: Variant = request.get("exprs", {})
	var sources := {}
	if raw is Dictionary:
		sources = raw
	elif raw is Array or raw is String:
		for item: Variant in (raw if raw is Array else [raw]):
			sources[str(item)] = str(item)
	if sources.is_empty():
		return _fail("give exprs={\"name\": \"expression\"} (inputs: app, tree, bridge, session, sim, s = sim.state)")
	var compiled := {}
	for column: Variant in sources:
		var expression := Expression.new()
		if expression.parse(str(sources[column]), _input_names(["session", "sim", "s"])) != OK:
			return _fail("%s: parse error: %s" % [column, expression.get_error_text()])
		compiled[str(column)] = expression
	var job := {session = session, exprs = compiled, every = maxi(1, int(request.get("every_ticks", 24))),
		count = clampi(int(request.get("count", 10)), 1, 100000), rows = [], last_tick = -1, error = ""}
	_samples.append(job)
	return {pending = func() -> Variant:
		if job.error.is_empty() and job.rows.size() < job.count:
			return null
		_samples.erase(job)
		if not job.error.is_empty():
			return _fail(job.error)
		return _ok({columns = ["tick", "time_s"] + compiled.keys(), rows = job.rows}),
		timeout_s = 600.0, job = job}


func _collect_samples() -> void:
	for job: Dictionary in _samples:
		if not job.error.is_empty() or job.rows.size() >= job.count:
			continue
		if not is_instance_valid(job.session) or not job.session.is_inside_tree():
			job.error = "the simulation ended after %d rows" % job.rows.size()
			continue
		var sim: Node = job.session.sim
		var tick: int = sim.tick
		if job.last_tick >= 0 and tick - int(job.last_tick) < int(job.every):
			continue
		job.last_tick = tick
		var row: Array = [tick, sim.time()]
		for column: String in job.exprs:
			var expression: Expression = job.exprs[column]
			var value: Variant = expression.execute(_input_values([job.session, sim, sim.state]), app, false)
			if expression.has_execute_failed():
				job.error = "%s failed at tick %d: %s" % [column, tick, expression.get_error_text()]
				break
			row.append(jsonable(value))
		job.rows.append(row)


func _cmd_assert(request: Dictionary) -> Dictionary:
	var result := _cmd_eval(request)
	if not result.ok:
		return result
	if result.result:
		return _ok({value = result.result})
	return _fail("assertion failed: %s (value %s)" % [request.get("message", request.get("expr", "")), JSON.stringify(jsonable(result.result))])


func _cmd_find(request: Dictionary) -> Dictionary:
	var under := _node(str(request.get("under", "/root")))
	if under == null:
		return _fail("no node at '%s'" % request.get("under", ""))
	var pattern := str(request.get("name", "*"))
	var type := str(request.get("type", ""))
	var limit := clampi(int(request.get("limit", 100)), 1, 2000)
	var found: Array = []
	var stack: Array[Node] = [under]
	while not stack.is_empty() and found.size() < limit:
		var node: Node = stack.pop_back()
		if str(node.name).matchn(pattern) and (type.is_empty() or node.is_class(type) or _script_class(node) == type):
			var info := {path = _path(node), type = node.get_class()}
			if node.get_script() != null:
				info.script = node.get_script().resource_path
			found.append(info)
		var children := node.get_children()
		children.reverse()
		stack.append_array(children)
	return _ok({nodes = found, truncated = found.size() >= limit})


static func _script_class(node: Node) -> String:
	var script: Variant = node.get_script()
	return str(script.get_global_name()) if script != null else ""


func _cmd_get(request: Dictionary) -> Dictionary:
	var node := _node(str(request.get("node", "")))
	if node == null:
		return _fail("no node at '%s'" % request.get("node", ""))
	var prop := str(request.get("prop", ""))
	if prop.is_empty():
		var values := {}
		for property: Dictionary in node.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				values[property.name] = node.get(property.name)
		return _ok(values)
	return _ok(node.get_indexed(NodePath(prop)))


func _cmd_set(request: Dictionary) -> Dictionary:
	var node := _node(str(request.get("node", "")))
	if node == null:
		return _fail("no node at '%s'" % request.get("node", ""))
	var prop := NodePath(str(request.get("prop", "")))
	if prop.get_name_count() + prop.get_subname_count() == 0 or not str(prop).get_slice(":", 0) in node:
		return _fail("%s has no property '%s' (get node=... lists them)" % [_path(node), prop])
	var current: Variant = node.get_indexed(prop)
	var value: Variant = _coerce(request.get("value"), current)
	var before := debug_log.last_seq()
	node.set_indexed(prop, value)
	var errors := _errors_since(before)
	if not errors.is_empty():
		return _fail("set %s failed: %s" % [prop, errors])
	return _ok({before = current, after = node.get_indexed(prop)})


## JSON gives numbers, arrays and objects; match the property's current type where it is unambiguous.
static func _coerce(value: Variant, like: Variant) -> Variant:
	if value is Array:
		match typeof(like):
			TYPE_VECTOR2: return Vector2(value[0], value[1])
			TYPE_VECTOR2I: return Vector2i(value[0], value[1])
			TYPE_VECTOR3: return Vector3(value[0], value[1], value[2])
			TYPE_VECTOR3I: return Vector3i(value[0], value[1], value[2])
			TYPE_COLOR: return Color(value[0], value[1], value[2], value[3] if value.size() > 3 else 1.0)
			TYPE_PACKED_FLOAT64_ARRAY: return PackedFloat64Array(value)
	if value is float and typeof(like) == TYPE_INT and value == floorf(value):
		return int(value)
	if value is String and typeof(like) == TYPE_STRING_NAME:
		return StringName(value)
	return value


func _cmd_call(request: Dictionary) -> Dictionary:
	var node := _node(str(request.get("node", "")))
	if node == null:
		return _fail("no node at '%s'" % request.get("node", ""))
	var method := str(request.get("method", ""))
	if not node.has_method(method):
		return _fail("%s has no method '%s'" % [_path(node), method])
	var args: Variant = request.get("args", [])
	var before := debug_log.last_seq()
	var result: Variant = node.callv(method, args if args is Array else [args])
	# A wrong argument count or an error inside the method only logs and returns null: report it as a failure.
	var errors := _errors_since(before)
	if not errors.is_empty():
		return _fail("%s(...) failed: %s" % [method, errors])
	return _ok(result)


func _errors_since(seq: int) -> String:
	var texts: Array = debug_log.since(seq, 5, PackedStringArray(["error", "script_error"])).map(
		func(record: Dictionary) -> String: return str(record.text))
	return "; ".join(texts)


func _cmd_open(request: Dictionary) -> Dictionary:
	var screen := str(request.get("screen", ""))
	if screen.is_empty():
		return _ok(SCREEN_OPENERS.keys())
	if not SCREEN_OPENERS.has(screen):
		return _fail("unknown screen '%s'; screens: %s" % [screen, SCREEN_OPENERS.keys()])
	if not app.has_method(SCREEN_OPENERS[screen]):
		return _fail("this app root cannot open %s" % screen)
	var before := [_screen_ids(), _top_window()]
	app.call(SCREEN_OPENERS[screen])
	var until := Engine.get_process_frames() + 1
	return {pending = func() -> Variant:
		if Engine.get_process_frames() < until:
			return null
		if _screen_ids() == before[0] and _top_window() == before[1]:
			return _fail("%s did not open here (route %s, screens %s)" % [screen, _route(), _screen_ids()])
		return _ok({opened = screen, screens = _screen_ids(), focus = _path(get_viewport().gui_get_focus_owner())})}


func _cmd_close(_request: Dictionary) -> Dictionary:
	var window := _top_window()
	if window != null:
		if window is ConfirmationDialog:
			window.get_cancel_button().pressed.emit() # the dialog's own cancel path: hides and emits canceled
		else:
			window.hide()
		return _settle(1, {closed = window.get_class()})
	var screens: Variant = app.get("screens")
	if screens == null or screens.top() == null or screens.is_top("home"):
		return _fail("nothing to close (no dialog or menu screen above Home)")
	var surface: Control = ScreenStack._surface(screens.top())
	if surface == null or not surface.has_signal("close_requested"):
		return _fail("the top screen has no close request")
	var closing: Array = _screen_ids()
	surface.close_requested.emit()
	return _settle(1, {closed = closing.back()})


func _cmd_control(request: Dictionary) -> Dictionary:
	var id := str(request.get("name", ""))
	if id.is_empty():
		return _ok(ControllerActions.ACTIONS)
	var definition: Dictionary = ControllerActions.action_definition(id)
	if definition.is_empty():
		return _fail("unknown controller action '%s'; control (no name) lists them" % id)
	var in_menu := not _screen_ids().is_empty() or _top_window() != null or app.get("flight") == null
	if id == "pause":
		return _cmd_close(request) if in_menu and not _screen_ids().is_empty() else _cmd_open({screen = "pause"})
	if id == "calibrate":
		return _cmd_open({screen = "controls"})
	if id == "back":
		return _cmd_close(request)
	if MENU_ACTIONS.has(id):
		return _cmd_action({name = MENU_ACTIONS[id]})
	var flight: Variant = app.get("flight")
	if flight == null:
		return _fail("'%s' needs a flight" % id)
	if id == "throttle_cut":
		if not flight.session.has_method("set_controller_cut"):
			return _fail("this session has no throttle cut")
		flight.session.set_controller_cut(_bool(request.get("hold", true)))
		return _ok({throttle_cut = _bool(request.get("hold", true))})
	if id == "restart_flight":
		return _cmd_restart(request)
	if not flight.controller_action(id):
		return _fail("'%s' was not accepted now (menu open, wrong vehicle or state)" % id)
	return _settle(1, {action = id})


func _cmd_shortcuts(_request: Dictionary) -> Dictionary:
	var flight: Variant = app.get("flight")
	var vehicle_type: String = ControlsReference.AIRPLANE
	if flight != null and Catalog.is_rotorcraft(str(flight.get("aircraft_id"))):
		vehicle_type = ControlsReference.ROTORCRAFT
	var table := func(rows: Array) -> Array:
		return rows.map(func(row: Array) -> Dictionary:
			return {keys = row[0].map(func(k: int) -> String: return OS.get_keycode_string(k)), action = row[1]})
	var actions := {}
	for action: StringName in InputMap.get_actions():
		if not str(action).begins_with("ui_"):
			actions[str(action)] = InputMap.action_get_events(action).map(func(e: InputEvent) -> String: return e.as_text())
	return _ok({vehicle = vehicle_type, sticks = table.call(ControlsReference.flight_table(vehicle_type)),
		shortcuts = table.call(ControlsReference.shortcut_table(vehicle_type)),
		controller_actions = ControllerActions.ACTIONS.map(func(a: Dictionary) -> String: return "%s (%s)" % [a.id, a.context]),
		input_actions = actions,
		note = "press keys with key name=<key> (modifiers: Shift+C); controller actions with control name=<id>"})


func _cmd_prefs(_request: Dictionary) -> Dictionary:
	var out := {path = ProjectSettings.globalize_path(str(app.get("preferences_path"))), preferences = app.get("preferences")}
	var display: Variant = app.get("display_preferences")
	if display != null:
		out.display = display.get("config")
	out.note = "change settings through the UI (open screen=settings) or AppRoot setters (methods node=AppRoot)"
	return _ok(out)


func _cmd_methods(request: Dictionary) -> Dictionary:
	var node := _node(str(request.get("node", "AppRoot")))
	if node == null or node.get_script() == null:
		return _fail("no scripted node at '%s'" % request.get("node", ""))
	var private := _bool(request.get("private", false))
	var seen := {}
	var out: Array = []
	for method: Dictionary in node.get_script().get_script_method_list():
		var method_name := str(method.name)
		if seen.has(method_name) or method_name.begins_with("@") or (method_name.begins_with("_") and not private): # @: property accessors
			continue
		seen[method_name] = true
		var args: Array = method.args.map(func(a: Dictionary) -> String: return str(a.name))
		var defaults: int = method.default_args.size()
		for i in defaults:
			args[args.size() - defaults + i] += "?"
		out.append("%s(%s)" % [method_name, ", ".join(args)])
	out.sort()
	return _ok({node = _path(node), script = node.get_script().resource_path, methods = out})


func _cmd_mouse(request: Dictionary) -> Dictionary:
	var at := Vector2(float(request.get("x", 0.0)), float(request.get("y", 0.0)))
	if request.has("text") or request.has("path"):
		var found := _find_control(request)
		if found.has("error"):
			return _fail(found.error)
		at = _screen_center(found.control)
	var action := str(request.get("action", "click"))
	var button: MouseButton = {left = MOUSE_BUTTON_LEFT, right = MOUSE_BUTTON_RIGHT, middle = MOUSE_BUTTON_MIDDLE}.get(
		str(request.get("button", "right" if action == "right" else "left")), MOUSE_BUTTON_LEFT)
	var now := Time.get_ticks_msec()
	var events: Array = [[0, _motion(at, 0)]]
	match action:
		"move":
			pass
		"click", "right":
			events += [[0, _button(at, button, true, false)], [40, _button(at, button, false, false)]]
		"double":
			events += [[0, _button(at, button, true, false)], [30, _button(at, button, false, false)],
				[60, _button(at, button, true, true)], [90, _button(at, button, false, false)]]
		"down":
			events.append([0, _button(at, button, true, false)])
		"up":
			events.append([0, _button(at, button, false, false)])
		"drag":
			var to := Vector2(float(request.get("to_x", at.x)), float(request.get("to_y", at.y)))
			var mask := MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
			events.append([0, _button(at, button, true, false)])
			for i in range(1, 11):
				events.append([i * 30, _motion(at.lerp(to, i / 10.0), mask, (to - at) / 10.0)])
			events.append([340, _button(to, button, false, false)])
		"wheel":
			var amount := int(request.get("amount", 1))
			var wheel := MOUSE_BUTTON_WHEEL_UP if amount > 0 else MOUSE_BUTTON_WHEEL_DOWN
			for i in absi(amount):
				events += [[i * 20, _button(at, wheel, true, false)], [i * 20 + 10, _button(at, wheel, false, false)]]
		_:
			return _fail("action must be click, double, right, move, down, up, drag or wheel")
	var last := 0
	var mine: Array = []
	for item: Array in events:
		_scheduled.append({at_ms = now + int(item[0]), event = item[1]})
		mine.append(item[1])
		last = maxi(last, int(item[0]))
	var until := now + last
	return {pending = func() -> Variant:
		# Only this gesture's events count; another command's held key may still be scheduled.
		if Time.get_ticks_msec() < until or _scheduled.any(func(entry: Dictionary) -> bool: return mine.has(entry.event)):
			return null
		var result := {action = action, at = [at.x, at.y], screens = _screen_ids(), focus = _path(get_viewport().gui_get_focus_owner())}
		if not Rect2(Vector2.ZERO, Vector2(get_tree().root.size)).has_point(at):
			result.warning = "outside the %s window: the GUI ignores it" % [get_tree().root.size]
		return _ok(result),
		timeout_s = 10.0}


## A control's centre in window pixels: its canvas position, an embedded window's offset, then the root's stretch.
func _screen_center(control: Control) -> Vector2:
	var center := control.get_global_rect().get_center()
	var window := control.get_window()
	if window != get_tree().root:
		center += Vector2(window.position)
	return get_tree().root.get_final_transform() * center


static func _motion(at: Vector2, mask: int, relative := Vector2.ZERO) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.button_mask = mask
	event.relative = relative
	return event


static func _button(at: Vector2, button: MouseButton, pressed: bool, double: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = button
	event.pressed = pressed
	event.double_click = double
	if pressed and button <= MOUSE_BUTTON_MIDDLE:
		event.button_mask = 1 << (button - 1)
	return event


# ---- frame history and hitches (PT1h-R8) -----------------------------------------------------------------------

const _HITCH_MONITORS := {
	pipelines = [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH,
		Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW,
		Performance.PIPELINE_COMPILATIONS_SPECIALIZATION],
	objects = [Performance.OBJECT_COUNT], nodes = [Performance.OBJECT_NODE_COUNT],
	resources = [Performance.OBJECT_RESOURCE_COUNT], orphans = [Performance.OBJECT_ORPHAN_NODE_COUNT],
	static_memory = [Performance.MEMORY_STATIC],
}


## One sample per frame at the start of the bridge's _process: the wall time since the previous frame and the
## counter deltas over that interval. A long interval becomes a "hitch" event naming what changed during it.
func _record_frame(now_us: int) -> void:
	var monitors := {}
	for key: String in _HITCH_MONITORS:
		var total := 0.0
		for monitor: int in _HITCH_MONITORS[key]:
			total += Performance.get_monitor(monitor)
		monitors[key] = total
	var ticks := _frame_physics_ticks
	_frame_physics_ticks = 0
	if _frame_last_us == 0:
		_frame_last_us = now_us
		_frame_monitors = monitors
		_frame_log_seq = debug_log.last_seq()
		_frame_ms.resize(FRAME_CAPACITY)
		_frame_ticks.resize(FRAME_CAPACITY)
		return
	var ms := (now_us - _frame_last_us) / 1000.0
	_frame_last_us = now_us
	var index := _frame_count % FRAME_CAPACITY
	_frame_ms[index] = ms
	_frame_ticks[index] = ticks
	_frame_count += 1
	# Typical = median of the previous (up to) 60 frames, refreshed every 15: robust to the hitches themselves and to
	# long startup frames, and it adapts to slow renderers (llvmpipe frames are seconds long, and not hitches).
	if _frame_count % 15 == 1 or _frame_ema_ms == 0.0:
		_frame_ema_ms = _recent_median(mini(_frame_count - 1, 60))
	var threshold := maxf(hitch_ms, hitch_factor * _frame_ema_ms)
	if _frame_ema_ms > 0.0 and ms > threshold:
		_hitch(ms, threshold, ticks, monitors)
	_frame_monitors = monitors
	_frame_log_seq = debug_log.last_seq()


## Median of the `count` frames before the newest one (0 when there are none).
func _recent_median(count: int) -> float:
	if count <= 0:
		return 0.0
	var values := PackedFloat64Array()
	for i in count:
		values.append(_frame_ms[(_frame_count - 2 - i + FRAME_CAPACITY) % FRAME_CAPACITY])
	values.sort()
	return values[floori(values.size() / 2.0)]


func _hitch(ms: float, threshold: float, ticks: int, monitors: Dictionary) -> void:
	var deltas := {}
	for key: String in monitors:
		var change: float = monitors[key] - float(_frame_monitors.get(key, monitors[key]))
		if change != 0.0:
			deltas[key] = change / 1048576.0 if key == "static_memory" else change
	if deltas.has("static_memory"):
		deltas.static_memory_mib = snappedf(deltas.static_memory, 0.01)
		deltas.erase("static_memory")
	var causes: Array = []
	if deltas.get("pipelines", 0.0) > 0.0:
		causes.append("pipeline/shader compilation")
	if ticks >= Engine.max_physics_steps_per_frame:
		causes.append("physics catch-up (%d ticks, the per-frame maximum)" % ticks)
	if absf(deltas.get("nodes", 0.0)) >= 50.0 or deltas.get("resources", 0.0) >= 20.0:
		causes.append("scene/resource construction")
	var lines: Array = debug_log.since(_frame_log_seq, 8, PackedStringArray(["info", "warning", "error", "script_error"])).map(
		func(entry: Dictionary) -> String: return str(entry.text).left(160))
	var record := {frame = Engine.get_process_frames(), ms = snappedf(ms, 0.1), threshold_ms = snappedf(threshold, 0.1),
		physics_ticks = ticks, deltas = deltas, causes = causes, route = _route(), screens = _screen_ids(), log = lines,
		process_ms = snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		physics_ms = snappedf(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.01)}
	var session := _session()
	if session != null:
		record.tick = session.sim.tick
	_hitches.append(record)
	if _hitches.size() > 200:
		_hitches.pop_front()
	debug_log.event("hitch %.0f ms%s" % [ms, (": " + ", ".join(causes)) if not causes.is_empty() else ""], record)


func _cmd_frames(request: Dictionary) -> Dictionary:
	for key: String in ["hitch_ms", "factor"]:
		if request.has(key):
			var value: Variant = _number(request[key])
			if value == null or value <= 0.0:
				return _fail("%s must be a positive number" % key)
			if key == "hitch_ms":
				hitch_ms = value
			else:
				hitch_factor = value
	if _bool(request.get("reset", false)):
		_frame_count = 0
		_hitches.clear()
	var available := mini(_frame_count, FRAME_CAPACITY)
	var window_value: Variant = _number(request.get("window", available))
	var window := clampi(int(window_value) if window_value != null else available, 0, available)
	var times := PackedFloat64Array()
	var catch_up := 0
	for i in window:
		var index := (_frame_count - 1 - i) % FRAME_CAPACITY
		times.append(_frame_ms[index])
		if _frame_ticks[index] >= Engine.max_physics_steps_per_frame:
			catch_up += 1
	var out := {frames = window, hitch_ms = hitch_ms, factor = hitch_factor, typical_ms = snappedf(_frame_ema_ms, 0.01),
		hitches = _hitches.slice(maxi(0, _hitches.size() - 20)), hitch_total = _hitches.size(),
		physics_catch_up_frames = catch_up, max_physics_steps_per_frame = Engine.max_physics_steps_per_frame}
	if window > 0:
		var sorted := times.duplicate()
		sorted.sort()
		var worst := sorted.slice(sorted.size() - maxi(1, floori(sorted.size() / 100.0)))
		var mean := 0.0
		for value: float in times:
			mean += value
		mean /= window
		var worst_mean := 0.0
		for value: float in worst:
			worst_mean += value
		worst_mean /= worst.size()
		out.merge({mean_ms = snappedf(mean, 0.01), p50_ms = _percentile(sorted, 0.5), p95_ms = _percentile(sorted, 0.95),
			p99_ms = _percentile(sorted, 0.99), max_ms = snappedf(sorted[sorted.size() - 1], 0.01),
			fps_mean = snappedf(1000.0 / mean, 0.1), fps_1pct_low = snappedf(1000.0 / worst_mean, 0.1)})
	return _ok(out)


static func _percentile(sorted: PackedFloat64Array, q: float) -> float:
	return snappedf(sorted[clampi(int(ceil(q * sorted.size())) - 1, 0, sorted.size() - 1)], 0.01)


# ---- simulation watchpoints (PT1h-R8) --------------------------------------------------------------------------

func _cmd_break(request: Dictionary) -> Dictionary:
	if _bool(request.get("list", false)):
		return _ok(_breaks.map(func(b: Dictionary) -> Dictionary:
			return {name = b.name, expr = b.source, pause = b.pause, once = b.once, hits = b.hits, last_tick = b.last_tick}))
	if request.has("clear"):
		var target := str(request.clear)
		var before := _breaks.size()
		_breaks = _breaks.filter(func(b: Dictionary) -> bool: return target != "all" and b.name != target)
		return _ok({cleared = before - _breaks.size()})
	if _flight_session() == null:
		return _fail("watchpoints run on flight ticks: fly first")
	var source := str(request.get("expr", ""))
	var expression := Expression.new()
	if source.is_empty() or expression.parse(source, _input_names(["session", "sim", "s"])) != OK:
		return _fail("parse error: " + expression.get_error_text() if not source.is_empty() else "give expr=<expression>")
	var watch := {name = str(request.get("name", "break%d" % (_breaks.size() + 1))), source = source,
		expression = expression, pause = _bool(request.get("pause", true)), once = _bool(request.get("once", false)),
		hits = 0, last_tick = -1, was_true = false, hit = {}}
	_breaks = _breaks.filter(func(b: Dictionary) -> bool: return b.name != watch.name)
	_breaks.append(watch)
	if not _bool(request.get("wait", false)):
		return _ok({name = watch.name, pause = watch.pause, once = watch.once})
	return {pending = func() -> Variant:
		if watch.hit.is_empty():
			return null
		return _ok(watch.hit),
		timeout_s = 600.0}


## Before each tick (priority -10): edge-triggered, so a condition that stays true fires once per entry.
func _check_breaks() -> void:
	if _breaks.is_empty():
		return
	var session := _flight_session()
	if session == null:
		return
	var sim: Node = session.sim
	if sim.paused:
		return
	for watch: Dictionary in _breaks.duplicate():
		var value: Variant = watch.expression.execute(_input_values([session, sim, sim.state]), app, false)
		if watch.expression.has_execute_failed():
			_breaks.erase(watch)
			debug_log.event("break %s removed: %s" % [watch.name, watch.expression.get_error_text()], {expr = watch.source})
			continue
		var now_true := bool(value) if (value is bool or value is int or value is float) else value != null
		if now_true and not watch.was_true:
			watch.hits += 1
			watch.last_tick = sim.tick
			if watch.pause:
				sim.set_paused(true)
			watch.hit = {name = watch.name, tick = sim.tick, time_s = sim.time(), value = jsonable(value),
				paused = sim.paused, state = jsonable(_flight_state(session))}
			debug_log.event("break %s at tick %d" % [watch.name, sim.tick], {expr = watch.source, value = jsonable(value)})
			if watch.once:
				_breaks.erase(watch)
		watch.was_true = now_true


# ---- log triage, object census, script profile (PT1h-R8) -------------------------------------------------------

## Groups records after a cursor by level, text with numbers masked, and script location (network-thread safe).
func _log_summary(request: Dictionary) -> Dictionary:
	var levels := PackedStringArray()
	if request.has("level"):
		levels = str(request.level).split(",", false)
	var digits := RegEx.create_from_string("0x[0-9a-fA-F]+|[-+]?\\d+(\\.\\d+)?")
	var groups := {}
	var since_value: Variant = _number(request.get("since", 0))
	for record: Dictionary in debug_log.since(int(since_value) if since_value != null else 0, DebugLog.CAPACITY, levels):
		var key := "%s|%s|%s" % [record.level, digits.sub(str(record.text), "#", true), record.get("script", "")]
		if not groups.has(key):
			groups[key] = {level = record.level, text = str(record.text).left(300), script = record.get("script", ""),
				count = 0, first_seq = record.seq, first_frame = record.frame}
		groups[key].count += 1
		groups[key].last_seq = record.seq
		groups[key].last_frame = record.frame
	var rows: Array = groups.values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.count > b.count if a.count != b.count else a.first_seq < b.first_seq)
	return _ok({groups = rows, last_seq = debug_log.last_seq(), dropped = debug_log.dropped})


func _cmd_objects(request: Dictionary) -> Dictionary:
	var census := {}
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var key := _object_key(node)
		census[key] = int(census.get(key, 0)) + 1
		stack.append_array(node.get_children(true))
	var orphan_census := {}
	var orphan_samples: Array = []
	for id: int in ClassDB.class_call_static("Node", "get_orphan_node_ids"):
		var orphan: Object = instance_from_id(id)
		if orphan == null:
			continue
		var key := _object_key(orphan)
		orphan_census[key] = int(orphan_census.get(key, 0)) + 1
		if orphan_samples.size() < 20:
			orphan_samples.append({key = key, name = str(orphan.name), children = orphan.get_child_count()})
	var totals := {objects = Performance.get_monitor(Performance.OBJECT_COUNT), nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		resources = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), orphans = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		static_memory_mib = snappedf(OS.get_static_memory_usage() / 1048576.0, 0.01), tree_nodes = census.values().reduce(func(a: int, b: int) -> int: return a + b, 0)}
	var top_value: Variant = _number(request.get("top", 25))
	var top := clampi(int(top_value) if top_value != null else 25, 1, 500)
	var out := {totals = totals, orphans = _top_counts(orphan_census, top), orphan_samples = orphan_samples,
		classes = _top_counts(census, top)}
	if _bool(request.get("diff", false)):
		if _objects_baseline.is_empty():
			return _fail("no baseline: run objects baseline=true first")
		out.diff = {totals = _deltas(_objects_baseline.totals, totals, top), classes = _deltas(_objects_baseline.census, census, top),
			orphans = _deltas(_objects_baseline.orphans, orphan_census, top)}
	if _bool(request.get("baseline", false)):
		_objects_baseline = {totals = totals, census = census, orphans = orphan_census}
		out.baseline = "saved"
	return _ok(out)


static func _object_key(object: Object) -> String:
	var script: Variant = object.get_script()
	return object.get_class() + (":" + str(script.resource_path).get_file() if script != null and not str(script.resource_path).is_empty() else "")


static func _top_counts(counts: Dictionary, top: int) -> Array:
	var rows: Array = counts.keys().map(func(k: String) -> Array: return [k, counts[k]])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return rows.slice(0, top)


static func _deltas(before: Dictionary, after: Dictionary, top: int) -> Array:
	var rows: Array = []
	for key: Variant in after.keys() + before.keys().filter(func(k: Variant) -> bool: return not after.has(k)):
		var change: float = float(after.get(key, 0)) - float(before.get(key, 0))
		if change != 0.0:
			rows.append([key, change])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return absf(a[1]) > absf(b[1]))
	return rows.slice(0, top)


## Parses the local debugger's script profile (launch --profile: -d --profiling --ignore-error-breaks), which the
## engine prints about once a second: a FRAME line, then per function "n:path::line::name" and its total/self/calls.
func _cmd_profile(request: Dictionary) -> Dictionary:
	# Window: seconds=<s> back from now, else from the time of main-log record since=<seq>, else everything kept.
	var from_ms := 0
	var seconds: Variant = _number(request.get("seconds", -1))
	var since_value: Variant = _number(request.get("since", 0))
	if seconds != null and seconds > 0.0:
		from_ms = Time.get_ticks_msec() - int(seconds * 1000.0)
	elif since_value != null and since_value > 0:
		from_ms = maxi(0, debug_log.time_of(int(since_value))) # a forgotten record (-1) means "everything kept"
	var header := RegEx.create_from_string("^\\d+:(.+)::(\\d+)::(.+)$")
	var timing := RegEx.create_from_string("total: ([0-9.e-]+)/\\d+ %\\s+self: ([0-9.e-]+)/\\d+ % tcalls: (\\d+)")
	var functions := {}
	var samples := 0
	var script_s := 0.0
	var frame_s := 0.0
	var current := ""
	for text: String in debug_log.profile_since(from_ms):
		for line: String in text.split("\n"):
			line = line.strip_edges()
			if line.begins_with("FRAME: total:"):
				samples += 1
				var parts := line.split(" ", false)
				frame_s += parts[2].to_float()
				script_s += parts[4].get_slice("/", 0).to_float()
				continue
			var matched := header.search(line)
			if matched != null:
				current = "%s:%s %s" % [matched.get_string(1), matched.get_string(2), matched.get_string(3)]
				continue
			matched = timing.search(line)
			if matched != null and not current.is_empty():
				var entry: Dictionary = functions.get(current, {function = current, total_ms = 0.0, self_ms = 0.0, calls = 0, samples = 0})
				entry.total_ms += matched.get_string(1).to_float() * 1000.0
				entry.self_ms += matched.get_string(2).to_float() * 1000.0
				entry.calls += matched.get_string(3).to_int()
				entry.samples += 1
				functions[current] = entry
				current = ""
	if samples == 0:
		return _fail("no script profile in the log: launch with debugctl.py launch --profile")
	var key := "total_ms" if str(request.get("sort", "self")) == "total" else "self_ms"
	var rows: Array = functions.values()
	for row: Dictionary in rows:
		for field: String in ["total_ms", "self_ms"]:
			row[field + "_per_sample"] = snappedf(row[field] / samples, 0.001)
			row.erase(field)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a[key + "_per_sample"] > b[key + "_per_sample"])
	var top_value: Variant = _number(request.get("top", 20))
	return _ok({samples = samples, frame_ms_per_sample = snappedf(frame_s * 1000.0 / samples, 0.001),
		script_ms_per_sample = snappedf(script_s * 1000.0 / samples, 0.001),
		functions = rows.slice(0, clampi(int(top_value) if top_value != null else 20, 1, 500)),
		note = "samples are the engine's ~1 s profile prints (one frame each); profiling adds overhead"})


## Frame-level change detection: one "event" log record per changed field, so `logs --follow` tells the story.
func _observe() -> void:
	var session := _session()
	var now := {route = _route(), screens = ",".join(_screen_ids())}
	if session != null:
		now.paused = _paused(session)
		now.crashed = "crash" in session and not session.crash.is_empty()
		now.fault = session.sim.fault_reason
		now.pause_reason = session.get("pause_reason")
		var tick: int = session.sim.tick
		var msec := Time.get_ticks_msec()
		if _rate_mark.tick < 0 or tick < _rate_mark.tick:
			_rate_mark = {msec = msec, tick = tick}
		elif msec - _rate_mark.msec >= 1000:
			realtime_factor = (tick - _rate_mark.tick) * session.sim.dt() / ((msec - _rate_mark.msec) / 1000.0)
			_rate_mark = {msec = msec, tick = tick}
	else:
		realtime_factor = -1.0
		_rate_mark = {msec = 0, tick = -1}
	for key: String in now: # flight-only fields simply stop when the route leaves the flight
		if _watch.get(key) != now[key] and not (now[key] is String and now[key].is_empty() and not _watch.has(key)):
			var detail := {from = _watch.get(key), to = now[key]}
			if session != null:
				detail.tick = session.sim.tick
			debug_log.event("%s: %s" % [key, now[key]], detail)
	_watch = now


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


func _vehicle() -> Node:
	for key: String in ["flight", "ground_vehicle"]:
		var node: Variant = app.get(key) if app != null else null
		if node is Node and is_instance_valid(node):
			return node
	return null


func _session() -> Node:
	var vehicle := _vehicle()
	if vehicle == null:
		return null
	var session: Variant = vehicle.get("session")
	return session if session is Node and is_instance_valid(session) and "sim" in session else null


## Ground-vehicle sessions own their pause; flight sessions pause their simulation.
static func _paused(session: Node) -> bool:
	var own: Variant = session.get("paused")
	return own if own is bool else session.sim.paused


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
	var vehicle := _vehicle()
	var out := {aircraft = vehicle.get("aircraft_id") if vehicle != null else null, tick = sim.tick, time_s = sim.time(), paused = _paused(session),
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
	var window := _top_window()
	if window != null:
		return window
	var screens: Variant = app.get("screens") if app != null else null
	if screens != null and screens.top() != null:
		return screens.top()
	# No menu: the layer holding keyboard focus (an accident report, the truck garage) is what keys act on.
	var focused: Node = get_viewport().gui_get_focus_owner()
	while focused != null and not focused is CanvasLayer:
		focused = focused.get_parent()
	return focused if focused != null else get_tree().root


## The topmost visible embedded dialog or popup (they draw above every screen and take the input).
func _top_window() -> Window:
	var windows: Array = get_tree().root.get_embedded_subwindows()
	for i in range(windows.size() - 1, -1, -1):
		if windows[i] is Window and windows[i].visible:
			return windows[i]
	return null


func _controls(scope: Node, labels: bool) -> Array[Control]:
	var out: Array[Control] = []
	var stack: Array[Node] = [scope]
	while not stack.is_empty() and out.size() < UI_LIMIT * 4:
		var node: Node = stack.pop_back()
		if (node is CanvasLayer or node is Window) and not node.visible:
			continue
		if node is Control:
			if not node.is_visible_in_tree() or node is ScrollBar:
				continue
			var spin_text: bool = node is LineEdit and node.get_parent() is SpinBox
			if (node is BaseButton or node is LineEdit or node is TextEdit or node is Range or node is ItemList \
					or node is TabBar or (labels and (node is Label or node is RichTextLabel))) and not spin_text:
				out.append(node)
		# Internal children too: dialog OK/Cancel buttons and container tab bars are internal.
		var children := node.get_children(true)
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
	if control is TabBar:
		info.selected = control.current_tab
		info.items = _item_labels(control)
	if control is ItemList:
		info.items = _item_labels(control)
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
	# Best tier wins: exact label, label without its key hint ("DRIVE · Enter"), node name (an OptionButton shows its
	# choice, its name is stable), label prefix, then any substring.
	var tiers: Array = [[], [], [], [], []]
	for control: Control in _controls(scope, false):
		var label := _label(control).to_lower()
		if label == wanted:
			tiers[0].append(control)
		elif label.get_slice(" · ", 0).strip_edges() == wanted:
			tiers[1].append(control)
		elif str(control.name).to_lower() == wanted:
			tiers[2].append(control)
		elif label.begins_with(wanted):
			tiers[3].append(control)
		elif label.contains(wanted):
			tiers[4].append(control)
	var matches: Array = []
	for tier: Array in tiers:
		if not tier.is_empty():
			matches = tier
			break
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
	if value is bool:
		return value
	if value is int or value is float:
		return value != 0 # JSON gives 1 as 1.0
	return str(value).to_lower() in ["1", "true", "yes", "on"]


## A finite number from JSON (or a numeric string), else null: callers refuse instead of failing mid-command.
static func _number(value: Variant) -> Variant:
	if value is int or value is float:
		if not is_finite(float(value)):
			return null
		return float(value)
	if value is String and value.is_valid_float():
		return value.to_float()
	return null


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
