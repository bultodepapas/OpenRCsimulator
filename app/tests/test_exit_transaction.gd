extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const DraftStore := preload("res://workshop/draft_store.gd")

var failures := 0
var checks := 0
var scratch := ""
var blocker := ""
var ui: RefCounted


class ProbeRoot extends "res://app_root.gd":
	var quit_requests := 0
	func _request_app_quit() -> void:
		quit_requests += 1


## A real Recorder and Trace: only the output destination changes between attempts.
class DiskRecorder extends "res://sim/recorder.gd":
	var output_path := ""
	var stop_calls := 0
	func stop(path := "") -> Error:
		stop_calls += 1
		return super.stop(output_path if path.is_empty() else path)


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, passed: bool) -> void:
	checks += 1
	print(("ok   " if passed else "FAIL ") + label)
	if not passed:
		failures += 1


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	ui = UiDriver.new(self)
	scratch = "user://test_exit_transaction_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var directory := ProjectSettings.globalize_path(scratch)
	check("isolated fixture directory opens", DirAccess.make_dir_recursive_absolute(directory) == OK)
	blocker = directory.path_join("not_a_directory")
	var file := FileAccess.open(blocker, FileAccess.WRITE)
	check("blocked destination fixture opens", file != null)
	if file == null:
		quit(1)
		return
	file.store_string("file blocks its children")
	file.close()
	await _discard_cancel_and_retry()
	await _retry_and_leave()
	await _end_flight_transaction()
	await _workshop_recovery_transaction()
	await _incumbent_statistics_modal()
	_remove_fixture(directory)
	print("Exit transaction: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _make_app(tag: String) -> ProbeRoot:
	var app := ProbeRoot.new()
	app.user_args = PackedStringArray()
	app.preferences_path = scratch + "/preferences-" + tag + ".cfg"
	app.statistics_path = scratch + "/statistics-" + tag
	root.add_child(app)
	await ui.settle()
	app.start_flight()
	await ui.settle()
	check(tag + ": Home flight and real statistics observer start", is_instance_valid(app.flight)
		and is_instance_valid(app.statistics_service) and app.statistics_service.detector != null)
	return app


func _make_recorder(app: ProbeRoot) -> DiskRecorder:
	var old: RefCounted = app.flight.recorder
	if old != null:
		old.detach()
	var session: Node = app.flight.session
	var recorder := DiskRecorder.new(session.sim, session.electrical_state, session.mass_properties)
	recorder.output_path = blocker.path_join("trace.csv")
	app.flight.recorder = recorder
	recorder.start(session.trace_meta())
	return recorder


## The store is fully initialized first, then its real file writes encounter a file as parent.
func _block_statistics(app: ProbeRoot) -> String:
	var service: Node = app.statistics_service
	service._finish_write()
	var original: String = service.store._root_path
	service.store._root_path = blocker
	return original


func _inject_t() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_T
		event.physical_keycode = KEY_T
		event.pressed = pressed
		Input.parse_input_event(event)


func _wait_quit(app: ProbeRoot) -> void:
	var deadline := Time.get_ticks_usec() + 2_000_000
	while app.quit_requests == 0 and Time.get_ticks_usec() < deadline:
		await process_frame


func _discard_cancel_and_retry() -> void:
	var app := await _make_app("discard")
	if not is_instance_valid(app.flight) or not is_instance_valid(app.statistics_service) or app.statistics_service.detector == null:
		await ui.close_app(app)
		return
	var recorder := _make_recorder(app)
	var session: Node = app.flight.session
	session.hold("independent_test")
	var before_holds: Dictionary = session.holds.duplicate(true)
	var blocked_store := _block_statistics(app)
	var generation := recorder.recording_generation
	var bytes_before := recorder.trace._rows.to_byte_array()
	app.quit_app()
	_inject_t() # during the frame before the failed trace dialog is presented
	await ui.settle()
	var trace_dialog: ConfirmationDialog = app._trace_recovery_dialog
	check("failed real trace stays intact while input is blocked", is_instance_valid(trace_dialog)
		and trace_dialog.visible and recorder.recording_generation == generation
		and recorder.trace._rows.to_byte_array() == bytes_before and recorder.stop_calls == 1
		and not app.flight.is_processing_unhandled_input())
	if not is_instance_valid(trace_dialog):
		app.statistics_service.store._root_path = blocked_store
		await ui.close_app(app)
		return
	trace_dialog.custom_action.emit("discard")
	trace_dialog.confirmed.emit() # stale Stay cannot cancel its successor
	var statistics_dialog: ConfirmationDialog = app._statistics_save_dialog
	check("trace discard reaches the statistics decision under the same hold", is_instance_valid(statistics_dialog)
		and statistics_dialog.visible and app._exit_request_active and session.holds.has("exit_guard")
		and app._trace_recovery.discarded_count() == 1)
	if not is_instance_valid(statistics_dialog):
		app.statistics_service.store._root_path = blocked_store
		await ui.close_app(app)
		return
	app.quit_app() # repeated request joins the existing decision
	check("repeated quit does not replace the statistics window", app._statistics_save_dialog == statistics_dialog
		and app.quit_requests == 0 and recorder.stop_calls == 1)
	statistics_dialog.canceled.emit()
	await ui.settle()
	check("statistics Cancel preserves the prior pause and independent holds", app.quit_requests == 0
		and not app._exit_request_active and session.sim.paused and session.holds == before_holds
		and app._trace_recovery.discarded_count() == 1 and app.flight.is_processing_unhandled_input())
	app.quit_app()
	var repeated: ConfirmationDialog = app._statistics_save_dialog
	check("later quit keeps the original discard decision", is_instance_valid(repeated)
		and app._trace_recovery_dialog == null and recorder.stop_calls == 1)
	if not is_instance_valid(repeated):
		app.statistics_service.store._root_path = blocked_store
		await ui.close_app(app)
		return
	repeated.confirmed.emit() # blocked store forces another statistics decision
	_inject_t() # during the gap before Retry continues
	await ui.settle()
	var replacement: ConfirmationDialog = app._statistics_save_dialog
	check("failed statistics Retry replaces its window without accepting T", is_instance_valid(replacement)
		and replacement != repeated and app._exit_request_active and recorder.recording_generation == generation
		and not recorder.recording and app.quit_requests == 0)
	app.statistics_service.store._root_path = blocked_store
	if is_instance_valid(replacement):
		replacement.confirmed.emit()
		await _wait_quit(app)
	check("successful statistics Retry commits exactly one quit", app.quit_requests == 1)
	await ui.close_app(app)


func _retry_and_leave() -> void:
	var app := await _make_app("retry")
	if not is_instance_valid(app.flight) or not is_instance_valid(app.statistics_service) or app.statistics_service.detector == null:
		await ui.close_app(app)
		return
	var recorder := _make_recorder(app)
	var original_store := _block_statistics(app)
	var session: Node = app.flight.session
	var paused_before: bool = session.sim.paused
	var holds_before: Dictionary = session.holds.duplicate(true)
	app.quit_app()
	await ui.settle()
	var trace_dialog: ConfirmationDialog = app._trace_recovery_dialog
	check("retry fixture exposes the real failed trace", is_instance_valid(trace_dialog) and trace_dialog.visible)
	if not is_instance_valid(trace_dialog):
		app.statistics_service.store._root_path = original_store
		await ui.close_app(app)
		return
	var saved_trace := ProjectSettings.globalize_path(scratch).path_join("retried-trace.csv")
	recorder.output_path = saved_trace
	trace_dialog.custom_action.emit("retry")
	var statistics_dialog: ConfirmationDialog = app._statistics_save_dialog
	check("trace Retry saves before reporting statistics failure", FileAccess.file_exists(saved_trace)
		and recorder.stop_calls == 2 and is_instance_valid(statistics_dialog) and app._exit_request_active)
	if is_instance_valid(statistics_dialog):
		statistics_dialog.canceled.emit()
		await ui.settle()
		check("Cancel after trace Retry restores the prior running state and holds", session.sim.paused == paused_before
			and session.holds == holds_before and app.quit_requests == 0)
		app.quit_app()
		var repeated: ConfirmationDialog = app._statistics_save_dialog
		check("saved trace is not saved a second time on a later quit", is_instance_valid(repeated)
			and recorder.stop_calls == 2 and app._trace_recovery_dialog == null)
		if is_instance_valid(repeated):
			repeated.confirmed.emit() # Retry statistics while its disk is still blocked.
			repeated.confirmed.emit() # A duplicate callback cannot authorize another continuation.
		await ui.settle()
		var retried_statistics: ConfirmationDialog = app._statistics_save_dialog
		check("trace Retry followed by failed statistics Retry keeps its decision", is_instance_valid(retried_statistics)
			and retried_statistics != repeated and app._exit_request_active and app.quit_requests == 0)
		if is_instance_valid(retried_statistics):
			retried_statistics.custom_action.emit("discard") # Leave without saving statistics.
		await _wait_quit(app)
	check("explicit Leave completes the requested quit once", app.quit_requests == 1)
	app.statistics_service.store._root_path = original_store
	await ui.close_app(app)


func _end_flight_transaction() -> void:
	var app := await _make_app("end-flight")
	if not is_instance_valid(app.flight):
		await ui.close_app(app)
		return
	var recorder := _make_recorder(app)
	var original_store := _block_statistics(app)
	app.open_pause()
	await ui.settle()
	var session: Node = app.flight.session
	var original_holds: Dictionary = session.holds.duplicate(true)
	app.end_flight()
	await ui.settle()
	var trace_dialog: ConfirmationDialog = app._trace_recovery_dialog
	check("End flight first guards its failed trace", is_instance_valid(trace_dialog))
	if is_instance_valid(trace_dialog): trace_dialog.custom_action.emit("discard")
	var statistics_dialog: ConfirmationDialog = app._statistics_save_dialog
	check("End flight retains its destination through statistics failure", is_instance_valid(statistics_dialog)
		and app._exit_request_kind == "end_flight" and app.flight != null and app.quit_requests == 0)
	if is_instance_valid(statistics_dialog): statistics_dialog.canceled.emit()
	await ui.settle()
	check("Cancel preserves Pause, flight and original holds", app.flight != null and app.screens.is_top("pause")
		and session.sim.paused and session.holds == original_holds)
	app.end_flight()
	statistics_dialog = app._statistics_save_dialog
	check("second End preserves the recording discard decision", is_instance_valid(statistics_dialog)
		and app._trace_recovery_dialog == null and recorder.stop_calls == 1)
	app.statistics_service.store._root_path = original_store
	if is_instance_valid(statistics_dialog): statistics_dialog.confirmed.emit()
	await ui.settle()
	check("successful End returns Home without quitting or closing the app session", app.flight == null
		and app.home != null and app.quit_requests == 0 and not app._exit_request_active
		and not bool(app.statistics_service.data.clean_exit))
	await ui.close_app(app)


func _workshop_recovery_transaction() -> void:
	var app := await _make_app("workshop")
	if not is_instance_valid(app.flight) or not is_instance_valid(app.statistics_service) or app.statistics_service.detector == null:
		await ui.close_app(app)
		return
	var recorder := _make_recorder(app)
	var original_store := _block_statistics(app)
	app.open_pause()
	await ui.settle()
	app.open_workshop()
	await ui.settle()
	var editor: Node = app.screens.get_screen("workshop")
	check("Workshop is open over the retained flight", is_instance_valid(editor))
	if not is_instance_valid(editor):
		app.statistics_service.store._root_path = original_store
		await ui.close_app(app)
		return
	editor.recovery_enabled = true
	editor.recovery_root = scratch + "/workshop-recovery"
	editor._start_recovery()
	editor.set_recipe({"control_multiplier": 1.03})
	editor.set_variant_name("Exit transaction draft")
	check("dirty Workshop writes a recovery snapshot", editor._autosave_draft())
	var snapshot_path := ProjectSettings.globalize_path(editor.recovery_root).path_join("_workshop_recovery/snapshot.json")
	var bytes_before := FileAccess.get_file_as_bytes(snapshot_path)
	check("Workshop recovery has bytes and identity", not bytes_before.is_empty()
		and bool(DraftStore.load_snapshot(editor.recovery_root).get("ok", false)))
	app.quit_app()
	var guard: ConfirmationDialog = editor.get("_guard_dialog")
	check("quit asks about the dirty Workshop", is_instance_valid(guard))
	if is_instance_valid(guard):
		guard.custom_action.emit("discard")
		guard.custom_action.emit("discard") # A stale duplicate cannot advance the transaction twice.
		check("duplicate Workshop Discard cannot stop the trace twice", recorder.stop_calls == 1
			and app._exit_request_active and editor.get("_guard_dialog") == null)
	await ui.settle()
	var trace_dialog: ConfirmationDialog = app._trace_recovery_dialog
	check("discarding draft proceeds to the failed trace", is_instance_valid(trace_dialog) and recorder.stop_calls == 1)
	if is_instance_valid(trace_dialog): trace_dialog.confirmed.emit() # Stay
	await ui.settle()
	check("trace Stay preserves the live draft and exact recovery bytes", editor.has_unsaved_changes()
		and FileAccess.get_file_as_bytes(snapshot_path) == bytes_before and app.quit_requests == 0)
	app.quit_app()
	guard = editor.get("_guard_dialog")
	if is_instance_valid(guard): guard.custom_action.emit("discard")
	await ui.settle()
	trace_dialog = app._trace_recovery_dialog
	if is_instance_valid(trace_dialog): trace_dialog.custom_action.emit("discard")
	var stats_dialog: ConfirmationDialog = app._statistics_save_dialog
	check("trace Discard continues to the real failed statistics save", is_instance_valid(stats_dialog))
	if is_instance_valid(stats_dialog): stats_dialog.canceled.emit()
	await ui.settle()
	check("statistics Cancel preserves the live draft and exact recovery bytes", editor.has_unsaved_changes()
		and FileAccess.get_file_as_bytes(snapshot_path) == bytes_before and app.quit_requests == 0)
	app.quit_app()
	guard = editor.get("_guard_dialog")
	if is_instance_valid(guard): guard.custom_action.emit("discard")
	stats_dialog = app._statistics_save_dialog
	check("repeated quit reuses trace resolution but asks about statistics", is_instance_valid(stats_dialog)
		and app._trace_recovery_dialog == null and recorder.stop_calls == 1)
	app.statistics_service.store._root_path = original_store
	if is_instance_valid(stats_dialog):
		stats_dialog.confirmed.emit()
		await _wait_quit(app)
	check("terminal quit clears only the authorized draft recovery", app.quit_requests == 1
		and not DraftStore.load_snapshot(editor.recovery_root).exists)
	await ui.close_app(app)


func _incumbent_statistics_modal() -> void:
	var app := ProbeRoot.new()
	app.user_args = PackedStringArray()
	app.preferences_path = scratch + "/preferences-incumbent.cfg"
	app.statistics_path = scratch + "/statistics-incumbent"
	root.add_child(app)
	await ui.settle()
	check("idle statistics fixture is writable", is_instance_valid(app.statistics_service)
		and app.statistics_service.flush() and app.statistics_service.can_manage())
	app.open_statistics()
	await ui.settle()
	var screen: Node = app.screens.get_screen("statistics")
	check("statistics screen opens for the incumbent modal", is_instance_valid(screen))
	if not is_instance_valid(screen):
		await ui.close_app(app)
		return
	screen._open_management_dialog("reset", "session", "", "session")
	var incumbent: ConfirmationDialog = screen.get("_active_dialog")
	check("statistics reset starts as an exclusive decision", is_instance_valid(incumbent)
		and incumbent.visible and incumbent.exclusive)
	if not is_instance_valid(incumbent):
		await ui.close_app(app)
		return
	var original_store := _block_statistics(app)
	# Exercise the AppRoot close owner. Full native notification propagation is covered separately.
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await ui.settle()
	check("first close cancels the incumbent decision without starting departure", not is_instance_valid(screen.get("_active_dialog"))
		and not app._exit_request_active and app.quit_requests == 0)
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await ui.settle()
	var recovery: ConfirmationDialog = app._statistics_save_dialog
	check("second close presents failed statistics save as the only active decision", is_instance_valid(recovery)
		and recovery.visible and recovery.exclusive and app._exit_request_active and app.quit_requests == 0)
	if is_instance_valid(recovery): recovery.canceled.emit()
	await ui.settle()
	check("cancel returns to the unchanged statistics screen", app.screens.top() == screen
		and not app._exit_request_active and app.quit_requests == 0)
	app.statistics_service.store._root_path = original_store
	await ui.close_app(app)


func _remove_fixture(path: String) -> void:
	var prefix := ProjectSettings.globalize_path("user://test_exit_transaction_")
	if not path.begins_with(prefix):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for name: String in directory.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name: String in directory.get_directories():
		_remove_fixture(path.path_join(name))
	directory = null
	DirAccess.remove_absolute(path)
