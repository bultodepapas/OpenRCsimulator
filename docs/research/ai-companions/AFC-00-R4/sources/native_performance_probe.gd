## Native rendered cost fixture. Production AppRoot/Main/session callbacks remain
## enabled; only this process's player input adapter is replaced with neutral
## keyboard targets at the accepted trim throttle. This is not device validation.
extends SceneTree

const AppRoot := preload("res://app_root.gd")
const Commands := preload("res://input/commands.gd")

var _app: Node
var _output := ""
var _receipt: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	for argument: String in args:
		if argument.begins_with("--fixture-out="):
			_output = argument.trim_prefix("--fixture-out=")
	if _output.is_empty() or FileAccess.file_exists(_output) or not args.has("--quick-flight") or not args.has("--start=airborne"):
		printerr("Native fixture requires --quick-flight --start=airborne --fixture-out=<new JSON>.")
		quit(2)
		return
	# Request focus once before launch; subsequent focus losses retain the normal
	# pause policy and make the measurement invalid instead of silently resuming.
	root.grab_focus()
	await process_frame
	await process_frame
	if not root.has_focus():
		printerr("Native fixture could not acquire focus before launch.")
		quit(1)
		return
	_app = AppRoot.new()
	_app.user_args = args
	root.add_child(_app)
	if _app.flight == null or not _app.flight.startup_error.is_empty():
		printerr("Native fixture flight failed to start.")
		quit(1)
		return
	var session: Node = _app.flight.session
	if session.sim.tick != 0 or not session.input_enabled or not session.physics_enabled or session.start.is_empty():
		printerr("Native fixture must bind before the first physical tick.")
		quit(1)
		return
	# Disconnect only the fixture's adapter; no OS/device/profile/preference change.
	# Explicit selection prevents a later device connection from replacing it.
	session.radio.disconnect_device()
	session.external_controller_selection = true
	session.read_raw = Commands.neutral_raw
	session.commands = {roll = 0.0, pitch = 0.0, yaw = 0.0, throttle = float(session.start.throttle)}
	session.raw = Commands.neutral_raw()
	session.sim.inputs = session._inputs()
	_receipt = {format = "openrc-afc-native-input-fixture v1",
		input_adapter = "neutral keyboard targets; accepted initial trim throttle held",
		scope = "production rendered flight; synthetic input; no radio/device qualification",
		fixture_sha256 = FileAccess.get_sha256(get_script().resource_path),
		arguments = Array(args), initial = _endpoint(),
		focus_policy = "unchanged production AppRoot focus/pause handling"}
	_app.flight.tree_exiting.connect(_finish)
	print("AFC native fixture bound at tick 0; held trim throttle=", session.commands.throttle)

func _endpoint() -> Dictionary:
	var session: Node = _app.flight.session
	return {tick = session.sim.tick, time_s = session.sim.time(), state = Array(session.sim.state),
		commands = session.commands.duplicate(), inputs = Array(session.sim.inputs),
		paused = session.sim.paused, pause_reason = session.pause_reason, holds = session.holds.duplicate(true),
		window_focused = root.has_focus(), fault = session.sim.fault_reason,
		crashed = not session.crash.is_empty(), prop_strike = not session.prop_strike.is_empty(),
		input_enabled = session.input_enabled, physics_enabled = session.physics_enabled,
		world_identity = session.collision_world().get("identity", "")}

func _finish() -> void:
	_receipt.final = _endpoint()
	_receipt.active_flight_endpoint = _receipt.final.tick > 0 and not _receipt.final.paused \
		and not _receipt.final.crashed and not _receipt.final.prop_strike \
		and _receipt.final.fault.is_empty()
	var file := FileAccess.open(_output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write native input fixture receipt: " + _output)
		return
	file.store_string(JSON.stringify(_receipt, "\t"))
	file.close()
	print("AFC native fixture complete; active endpoint=", _receipt.active_flight_endpoint)
