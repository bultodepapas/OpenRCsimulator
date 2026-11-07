# PT1h-R14: framing, numeric admission, disconnected requests, rewind span and checkpoint file contracts.
# Run through tools/godot/run_checked.py; all file writes are in a disposable user:// directory.
extends SceneTree
const Bridge = preload("res://debug/debug_bridge.gd")
var failed := 0
var checked := 0

class FakeSim extends Node:
	var paused := true
	var tick := 0
	var fault_reason := ""
	var stop_at_tick := -1
	var state := PackedFloat64Array([0,0,0,0,0,0,1,0,0,0,0,0,0])
	func dt() -> float: return 1.0 / 240.0
	func time() -> float: return tick * dt()
	func set_paused(value: bool) -> void:
		if not value and not fault_reason.is_empty(): return
		paused = value

class FakeSession extends Node:
	var sim := FakeSim.new()
	var holds := {}
	var crash := {}
	var pause_reason := ""
	var commands := {}
	var raw := {}
	var restored := ""
	func checkpoint() -> Dictionary:
		return {simulation = {tick = sim.tick, state = sim.state.duplicate(), stop_at_tick = sim.stop_at_tick}}
	func checkpoint_json() -> String:
		return JSON.stringify({tick = sim.tick, note = "café 日本 🚁"})
	func restore_checkpoint_json(text: String) -> bool:
		restored = text
		return true

class FakeFlight extends Node:
	var session := FakeSession.new()
	var aircraft_id := "fake-plane"

class FakeApp extends Node:
	var flight := FakeFlight.new()
	var ground_vehicle: Node
	var home: Node
	var screens: Node

func _initialize() -> void:
	call_deferred("run")

func check(label: String, condition: bool, detail: Dictionary = {}) -> void:
	checked += 1
	print("%s %s %s" % ["ok" if condition else "FAIL", label, JSON.stringify(detail)])
	if not condition:
		failed += 1

func read_probe(bridge: Node, peer: StreamPeerTCP, bytes: PackedByteArray) -> Dictionary:
	bridge._clients[1] = {peer = peer, buffer = bytes, out = PackedByteArray(), closing = false}
	bridge._read_client(1)
	var info: Dictionary = bridge._clients.get(1, {})
	var reply: Variant = JSON.parse_string(info.out.get_string_from_utf8()) if info.has("out") else null
	return {closing = info.get("closing"), reply = reply}

func run() -> void:
	var listener := TCPServer.new()
	var port := 0
	for attempt in 100:
		var candidate := 20000 + randi() % 40000
		if listener.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			break
	if port == 0:
		printerr("FAIL no disposable port")
		quit(1)
		return
	var client := StreamPeerTCP.new()
	var err := client.connect_to_host("127.0.0.1", port)
	var deadline := Time.get_ticks_msec() + 3000
	while not listener.is_connection_available() and Time.get_ticks_msec() < deadline:
		client.poll()
		OS.delay_msec(1)
	if err != OK or not listener.is_connection_available():
		printerr("FAIL no local socket")
		quit(1)
		return
	var peer: StreamPeerTCP = listener.take_connection()
	peer.poll()
	var bridge: Node = Bridge.new()
	bridge._display_name = DisplayServer.get_name()
	bridge._last_request_ms = -100000
	var prefix := '{"id":1,"cmd":"ping","filler":"'
	var suffix := '"}'
	var over := prefix + "x".repeat(Bridge.MAX_LINE_BYTES + 1 - prefix.length() - suffix.length()) + suffix
	var exact := prefix + "x".repeat(Bridge.MAX_LINE_BYTES - prefix.length() - suffix.length()) + suffix
	check("test constructed exact and oversized lines", exact.to_utf8_buffer().size() == Bridge.MAX_LINE_BYTES and over.to_utf8_buffer().size() == Bridge.MAX_LINE_BYTES + 1)
	var small_result := read_probe(bridge, peer, ('{"id":1,"cmd":"ping"}\n').to_utf8_buffer())
	check("live peer valid control passes", small_result.reply != null and small_result.reply.ok and not small_result.closing, small_result)
	var exact_result := read_probe(bridge, peer, (exact + "\n").to_utf8_buffer())
	check("exact-limit line passes", exact_result.reply != null and exact_result.reply.ok and not exact_result.closing, exact_result)
	var incomplete := read_probe(bridge, peer, over.to_utf8_buffer())
	check("oversized partial line refused", incomplete.closing and incomplete.reply != null and not incomplete.reply.ok, incomplete)
	var complete := read_probe(bridge, peer, (over + "\n").to_utf8_buffer())
	check("oversized complete line refused", complete.closing and complete.reply != null and not complete.reply.ok, complete)
	# Real TCP: fill to exactly MAX without a newline, then send the final payload byte
	# together with the newline. No receive buffer is injected for this witness.
	bridge._clients[2] = {peer = peer, buffer = PackedByteArray(), out = PackedByteArray(), closing = false}
	var wire := over.to_utf8_buffer()
	client.poll()
	var sent := 0
	var transfer_ok := true
	while sent < Bridge.MAX_LINE_BYTES and transfer_ok:
		var next := mini(sent + 16384, Bridge.MAX_LINE_BYTES)
		if client.put_data(wire.slice(sent, next)) != OK:
			transfer_ok = false
			break
		sent = next
		var chunk_deadline := Time.get_ticks_msec() + 3000
		while bridge._clients[2].buffer.size() < sent and Time.get_ticks_msec() < chunk_deadline:
			peer.poll()
			bridge._read_client(2)
			OS.delay_msec(1)
		if not bridge._clients.has(2) or bridge._clients[2].closing or bridge._clients[2].buffer.size() != sent:
			transfer_ok = false
	var final_bytes := wire.slice(Bridge.MAX_LINE_BYTES)
	final_bytes.append(10)
	if transfer_ok and client.put_data(final_bytes) == OK:
		var last_deadline := Time.get_ticks_msec() + 3000
		peer.poll()
		while peer.get_available_bytes() < final_bytes.size() and Time.get_ticks_msec() < last_deadline:
			OS.delay_msec(1)
			peer.poll()
		bridge._read_client(2)
		var peer_state: Dictionary = bridge._clients.get(2, {})
		var socket_reply: Variant = JSON.parse_string(peer_state.out.get_string_from_utf8()) if peer_state.has("out") else null
		check("real TCP oversized complete line refused", peer_state.get("closing", false) and socket_reply != null and not socket_reply.ok, {sent = sent + final_bytes.size(), closing = peer_state.get("closing"), reply = socket_reply})
	else:
		check("real TCP oversized complete line refused", false, {sent = sent})
	bridge._clients.clear()
	peer.disconnect_from_host()
	client.disconnect_from_host()
	listener.stop()

	bridge._last_request_ms = -100000
	var old_scale := Engine.time_scale
	bridge._inbox.append({peer_id = 9001, id = 17, request = {cmd = "time_scale", value = 0.5}})
	bridge._dropped.append(9001)
	bridge._process(0.016)
	check("already-dropped peer does not mutate time scale", is_equal_approx(Engine.time_scale, old_scale), {time_scale = Engine.time_scale})
	Engine.time_scale = old_scale
	bridge._inbox.append({peer_id = 9002, id = 18, request = {cmd = "wait", seconds = 30}})
	bridge._dropped.append(9002)
	bridge._process(0.016)
	var abandoned: bool = bridge._pending.any(func(item: Dictionary) -> bool: return item.peer_id == 9002)
	check("already-dropped peer leaves no orphan pending wait", not abandoned, {pending_count = bridge._pending.size()})
	bridge._forget_peer(9002)
	var overflow: Variant = Bridge._number("1e400")
	var finite_value: Variant = Bridge._number("1e2")
	check("overflow numeric string refused", overflow == null and Bridge._number("-1e400") == null, {parsed = str(overflow)})
	check("numeric controls stay valid or refused", finite_value == 100.0 and Bridge._number(INF) == null, {finite = finite_value})
	check("finite controls and malformed values", Bridge._number("-2.5e-2") == -0.025 and Bridge._number("1e-400") == 0.0
		and Bridge._number("not a number") == null and Bridge._number(NAN) == null and Bridge._number(true) == null)
	var refused: Dictionary = bridge._cmd_time_scale({value = "1e400"})
	check("overflow command preserves time scale", not refused.ok and Engine.time_scale == old_scale)
	bridge._inbox.append({peer_id = 9003, id = 19, request = {cmd = "time_scale", value = 0.75}})
	bridge._process(0.016)
	check("live queued request still executes", Engine.time_scale == 0.75)
	Engine.time_scale = old_scale
	bridge._handle(9004, 20, {cmd = "wait", seconds = 30})
	bridge._dropped.append(9004)
	bridge._process(0.016)
	check("disconnect removes previously dispatched pending work", bridge._pending.is_empty())
	var fake := FakeApp.new()
	fake.add_child(fake.flight)
	fake.flight.add_child(fake.flight.session)
	fake.flight.session.add_child(fake.flight.session.sim)
	bridge.app = fake
	_retention(bridge, fake.flight.session)
	_checkpoint(bridge, fake.flight.session)
	bridge.app = null
	fake.free()
	OS.remove_logger(bridge.debug_log)
	bridge.free()
	print("debug bridge contracts: %d checks, %d failures" % [checked, failed])
	quit(1 if failed else 0)


func _retention(bridge: Node, session: Node) -> void:
	var previous_hz := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 240
	var armed: Dictionary = bridge._cmd_rewind({arm = true, every_s = 0.25, keep_s = 1.0})
	check("one second retains both endpoints", armed.ok and bridge._rewind.capacity == 5)
	session.sim.paused = false
	for tick in range(300):
		session.sim.tick = tick
		bridge._rewind.capture(session)
	var aligned: Dictionary = bridge._rewind.find({seconds = 1.0}, 240, session.sim.dt())
	var between: Dictionary = bridge._rewind.find({seconds = 1.0}, 299, session.sim.dt())
	check("full advertised duration is available on and between sample ticks", not aligned.has("error")
		and not between.has("error") and aligned.tick == 0 and between.tick == 0)
	bridge._cmd_rewind({arm = false})
	bridge._cmd_rewind({arm = true, every_s = 0.25, keep_s = 0.26})
	check("fractional interval rounds up before adding endpoint", bridge._rewind.capacity == 3)
	bridge._cmd_rewind({arm = true, every_s = 0.25, keep_s = 0.01})
	check("shorter-than-cadence window still has two endpoints", bridge._rewind.capacity == 2)
	bridge._cmd_rewind({arm = true, every_s = 0.25, keep_s = 1.0e6})
	check("rewind remains bounded by documented capacity", bridge._rewind.capacity == 100000)
	var huge: Dictionary = bridge._cmd_rewind({arm = true, every_s = 0.25, keep_s = 1.0e300})
	check("huge finite retention stays capped without integer overflow", huge.ok and bridge._rewind.capacity == 100000)
	var too_far: Dictionary = bridge._cmd_rewind({arm = true, every_s = 1.0e300, keep_s = 1.0})
	check("unrepresentable cadence is refused without changing the ring", not too_far.ok and bridge._rewind.every_ticks == 60)
	bridge._cmd_rewind({arm = false})
	session.sim.paused = true
	Engine.physics_ticks_per_second = previous_hz


func _checkpoint(bridge: Node, session: Node) -> void:
	var directory := ProjectSettings.globalize_path("user://debug-checkpoint-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var path := directory.path_join("checkpoint with spaces.json")
	var reply: Dictionary = bridge._cmd_checkpoint({action = "save", path = path})
	var text: String = session.checkpoint_json()
	check("checkpoint creates parents and reports actual UTF-8 bytes", reply.ok
		and reply.result.bytes == text.to_utf8_buffer().size() and FileAccess.get_file_as_string(path) == text)
	session.sim.tick += 1
	var replaced: Dictionary = bridge._cmd_checkpoint({action = "save", path = path})
	check("checkpoint replacement publishes complete new content", replaced.ok
		and FileAccess.get_file_as_string(path) == session.checkpoint_json())
	var loaded: Dictionary = bridge._cmd_checkpoint({action = "load", path = path})
	check("checkpoint reload receives identical Unicode JSON", loaded.has("pending") and session.restored == session.checkpoint_json())
	var refused: Dictionary = bridge._cmd_checkpoint({action = "save", path = directory})
	check("directory destination refused without changing prior checkpoint", not refused.ok
		and FileAccess.get_file_as_string(path) == session.checkpoint_json())
	var files := DirAccess.get_files_at(directory)
	check("successful and refused saves leave no temporary siblings", files.size() == 1 and files[0] == path.get_file())
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)
