# F1: actual Input dispatch and connection signals, with fake metadata (never query fake hardware).
extends SceneTree

const Report = preload("res://input/input_report.gd")
const AppRoot = preload("res://app_root.gd")
const PATH: String = "user://test_input_report_e2e.json"
const PREFS: String = "user://test_input_report_never_created.cfg"
var _now: int = 1000000
var _checks: int = 0
var _failures: int = 0


func check(label: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL ", label)


func motion(id: int, axis: int, value: float) -> void:
	var event: InputEventJoypadMotion = InputEventJoypadMotion.new()
	event.device = id
	event.axis = axis as JoyAxis
	event.axis_value = value
	Input.parse_input_event(event)


func _initialize() -> void:
	_run()


func _run() -> void:
	var original_accumulation: bool = Input.use_accumulated_input
	Input.use_accumulated_input = true
	var reporter: Report = Report.new()
	reporter.quit_on_finish = false
	reporter.duration_s = 1.0
	reporter.output_path = PATH
	reporter.clock_usec = func() -> int: return _now
	reporter.connected_devices = func() -> Array[int]: return [15, 14]
	reporter.device_info = func(id: int) -> Dictionary:
		return {name = "Fake %d" % id, guid = "fake-%d" % id, vendor_id = "4617", product_id = "20308", raw_name = "Fake raw"}
	root.add_child(reporter)
	await process_frame
	check("report disables accumulation", not Input.use_accumulated_input)
	check("all startup devices enumerated", reporter.data.snapshot().size() == 2)
	_now += 1000
	motion(15, 0, 0.5)
	motion(14, 2, -1.0)
	_now += 2000
	motion(15, 0, -0.75)
	Input.joy_connection_changed.emit(15, false)
	_now += 1000
	motion(15, 0, 1.0) # late event must not extend the disconnected session
	Input.joy_connection_changed.emit(15, true)
	motion(15, 9, 0.3)
	Input.joy_connection_changed.emit(13, true) # hotplug, no movement
	var sessions: Array[Dictionary] = reporter.data.snapshot()
	check("dispatch reaches collector with exact timestamps", sessions[0].axes[0].events == 2 and sessions[0].axes[0].mean_event_spacing_usec == 2000.0)
	check("multiple devices collect independently", sessions[1].axes_seen == [2] and sessions[1].axes[2].min == -1.0)
	check("hotplug and reconnect produce separate sessions", sessions.size() == 4 and sessions[2].device_id == 15 and sessions[2].axes_seen == [9] and sessions[3].axes_seen.is_empty())
	check("disconnect stops sampling old session", not sessions[0].connected and sessions[0].disconnected_at_usec == 3000 and reporter.data.rejected_events == 1)
	_now += 1000000
	reporter._process(0.0) # deadline uses the monotonic clock, not the render delta
	check("deadline finishes report", not reporter.report.is_empty() and reporter.report.complete)
	check("finish restores accumulation", Input.use_accumulated_input)
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	check("saved report includes metadata and all sessions", saved is Dictionary and saved.format == Report.FORMAT and saved.devices.size() == 4 and saved.os != "" and saved.build.has("source"))
	check("SDL decimal-string USB identifiers serialize as numbers", saved.devices[0].vendor_id == 4617 and saved.devices[0].product_id == 20308)
	check("observed duration records actual wall interval", saved.observed_duration_s == 1.004 and saved.requested_duration_s == 1.0)
	check("timing limitations are explicit", "Not USB report interval" in saved.timing and "unseen axes are unknown" in saved.axis_semantics)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(PATH)
	motion(14, 2, 1.0)
	Input.joy_connection_changed.emit(12, true)
	check("completion stops collecting", reporter.data.snapshot().size() == 4 and reporter.data.snapshot()[1].axes[2].events == 1)
	check("finish is idempotent", reporter.finish() == OK and FileAccess.get_file_as_bytes(PATH) == bytes)
	reporter.free()

	# Actual app entry point: invalid field path would fail either flight/Home route; report must never read it.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	var app: AppRoot = AppRoot.new()
	app.user_args = ["--input-report", "--t=3600"]
	app.field_path = "res://deliberately-missing-field.json" # lint:ignore res_path -- missing route sentinel
	app.preferences_path = PREFS
	root.add_child(app)
	check("report route creates no Home or flight", app.home == null and app.home_scene == null and app.flight == null and not app.has_home)
	check("only diagnostic child created", app.get_child_count() == 1 and app.get_child(0) is Report)
	check("preferences never read or written", app.preferences.is_empty() and not FileAccess.file_exists(PREFS))
	app.free() # early shutdown must also disconnect and restore accumulation
	check("early shutdown restores accumulation", Input.use_accumulated_input)
	Input.use_accumulated_input = original_accumulation
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("F1 e2e: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures else 0)
