# UI-03-R1: quit policy, real manual trace saving and Window-close lifecycle.
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const HOME_PREFS := "user://test_ui_quit_home.cfg"
const DIRECT_PREFS := "user://test_ui_quit_direct.cfg"
const WORKSHOP_PREFS := "user://test_ui_quit_workshop.cfg"
const SCRATCH_TRACE_DIR := "user://test_ui_quit"

var failures := 0
var ui: RefCounted


class QuitProbeAppRoot extends "res://app_root.gd":
	var quit_requests := 0

	func _request_app_quit() -> void:
		quit_requests += 1


class ScratchRecorder extends "res://sim/recorder.gd":
	var scratch_path := ""

	func stop(path := "") -> Error:
		return super.stop(scratch_path if path.is_empty() else path)


class FailOnceRecorder extends RefCounted:
	var recording := true
	var stop_calls := 0
	var note := ""

	func stop(_path := "") -> Error:
		stop_calls += 1
		recording = false
		return ERR_CANT_CREATE

	func detach() -> void:
		recording = false

	func seconds() -> float:
		return 0.0


func _initialize() -> void:
	_run.call_deferred()


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _run() -> void:
	ui = UiDriver.new(self)
	TranslationServer.set_locale("en")
	var initial_auto_accept := auto_accept_quit
	await _check_home_route(initial_auto_accept)
	await _check_direct_recording_and_failed_save(initial_auto_accept)
	await _check_workshop_suspended_recording()
	set_auto_accept_quit(initial_auto_accept)
	print("UI quit: %d failed" % failures)
	quit(1 if failures else 0)


func _check_home_route(initial_auto_accept: bool) -> void:
	var app := QuitProbeAppRoot.new()
	app.user_args = PackedStringArray()
	app.preferences_path = HOME_PREFS
	root.add_child(app)
	await process_frame
	await process_frame
	_check("AppRoot disables automatic close while Home is active", not auto_accept_quit)
	_check("Home route is present", app.home != null and app.flight == null)
	var policy_connected := false
	for connection: Dictionary in app.home.quit_requested.get_connections():
		var handler: Callable = connection.callable
		if handler.get_object() == app and handler.get_method() == "quit_app":
			policy_connected = true
	_check("Home Quit is wired to the AppRoot quit policy", policy_connected)
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await process_frame
	_check("same-frame Window close requests coalesce on Home", app.quit_requests == 1, str(app.quit_requests))
	await ui.close_app(app)
	_check("AppRoot restores the host close policy after Home removal", auto_accept_quit == initial_auto_accept)
	_remove_prefs(HOME_PREFS)


func _check_direct_recording_and_failed_save(initial_auto_accept: bool) -> void:
	# A host that had disabled auto-accept before AppRoot must keep that policy after it leaves.
	set_auto_accept_quit(false)
	var app := QuitProbeAppRoot.new()
	app.user_args = PackedStringArray(["--quick-flight"])
	app.preferences_path = DIRECT_PREFS
	root.add_child(app)
	await process_frame
	await process_frame
	_check("direct route starts without Home", app.flight != null and not app.has_home)
	_check("AppRoot keeps a host-disabled close policy", not auto_accept_quit)
	if app.flight == null:
		await ui.close_app(app)
		set_auto_accept_quit(initial_auto_accept)
		return

	var previous_recorder: RefCounted = app.flight.recorder
	previous_recorder.detach()
	var scratch_trace_path := ProjectSettings.globalize_path(SCRATCH_TRACE_DIR).path_join(
		"%d-%d.csv" % [OS.get_process_id(), Time.get_ticks_usec()])
	var recorder := ScratchRecorder.new(app.flight.session.sim, app.flight.session.electrical_state,
		app.flight.session.mass_properties)
	recorder.scratch_path = scratch_trace_path
	app.flight.recorder = recorder
	recorder.start(app.flight.session.trace_meta())
	await process_frame
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await process_frame
	var trace_note: String = recorder.note
	var saved_trace_path := trace_note.get_slice("trace saved: ", 1).get_slice(" (", 0)
	_check("Window close saves a real manual Recorder trace", trace_note.begins_with("trace saved:")
		and not saved_trace_path.is_empty() and FileAccess.file_exists(saved_trace_path), trace_note)
	var trace_csv := FileAccess.get_file_as_string(saved_trace_path) if FileAccess.file_exists(saved_trace_path) else ""
	_check("saved trace contains the versioned CSV header and samples",
		trace_csv.contains("# format: openrc-trace") and trace_csv.contains("tick,t_s")
		and trace_csv.get_slice_count("\n") >= 4,
		"CSV lines=%d" % trace_csv.get_slice_count("\n"))
	_check("successful close reaches the final quit seam once", app.quit_requests == 1, str(app.quit_requests))
	if not saved_trace_path.is_empty() and FileAccess.file_exists(saved_trace_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_trace_path))
	var trace_dir := ProjectSettings.globalize_path(SCRATCH_TRACE_DIR)
	if DirAccess.dir_exists_absolute(trace_dir):
		DirAccess.remove_absolute(trace_dir)

	# The Recorder contract deliberately stops even when the save fails. Only a later explicit Quit discards it.
	app.quit_requests = 0
	var failed_recorder := FailOnceRecorder.new()
	app.flight.recorder = failed_recorder
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await process_frame
	_check("duplicate failed Window close saves only once", failed_recorder.stop_calls == 1,
		"stop_calls=%d" % failed_recorder.stop_calls)
	_check("failed Window close keeps the app open and reports the error on direct flight",
		app.quit_requests == 0 and not failed_recorder.recording and app.pause_menu != null
		and app.pause_menu.note_label.visible and "Could not save" in app.pause_menu.note_label.text,
		app.pause_menu.note_label.text if app.pause_menu != null else "no Pause menu")
	if app.pause_menu != null:
		app.pause_menu.quit_requested.emit()
	_check("second explicit Quit discards the failed recording without stopping again",
		failed_recorder.stop_calls == 1 and app.quit_requests == 1,
		"stops=%d quits=%d" % [failed_recorder.stop_calls, app.quit_requests])
	await ui.close_app(app)
	_check("AppRoot restores a previously disabled host close policy", not auto_accept_quit)
	set_auto_accept_quit(initial_auto_accept)
	_remove_prefs(DIRECT_PREFS)


func _check_workshop_suspended_recording() -> void:
	var app := QuitProbeAppRoot.new()
	app.user_args = PackedStringArray()
	app.preferences_path = WORKSHOP_PREFS
	root.add_child(app)
	await process_frame
	await process_frame
	app.start_flight()
	await process_frame
	if app.flight == null:
		_check("Workshop fixture starts its original flight", false)
		await ui.close_app(app)
		_remove_prefs(WORKSHOP_PREFS)
		return
	var original: Node = app.flight
	original.session.sim.process_mode = Node.PROCESS_MODE_DISABLED
	app.open_pause()
	app.open_workshop()
	var editor: Node = app.screens.top()
	var workshop_failure := FailOnceRecorder.new()
	original.recorder = workshop_failure
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await process_frame
	var workshop_status := editor.get("_status_label") as Label
	_check("failed close appears on the active Workshop screen above Pause",
		workshop_failure.stop_calls == 1 and app.quit_requests == 0 and workshop_status != null
		and workshop_status.visible and "Could not save" in workshop_status.text,
		workshop_status.text if workshop_status != null else "no Workshop status label")
	var failed_recorder := FailOnceRecorder.new()
	original.recorder = failed_recorder
	var aircraft_data: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	app._start_workshop_trial({base_id = Catalog.DEFAULT_ID, base_bytes = aircraft_data, recipe = {scale = 1.0}})
	_check("Workshop trial suspends the original flight", app.flight != null
		and app.flight != original and app._workshop_previous_flight == original and not original.is_inside_tree())
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await process_frame
	_check("failed save of the suspended flight blocks Window close once",
		failed_recorder.stop_calls == 1 and app.quit_requests == 0,
		"stops=%d quits=%d" % [failed_recorder.stop_calls, app.quit_requests])
	_check("suspended-flight failure is visible over the Workshop trial",
		app.pause_menu != null and app.pause_menu.note_label.visible
		and "Could not save" in app.pause_menu.note_label.text,
		app.pause_menu.note_label.text if app.pause_menu != null else "no Pause menu")
	if app.pause_menu != null:
		app.pause_menu.quit_requested.emit()
	_check("second explicit Quit discards the suspended failed trace",
		failed_recorder.stop_calls == 1 and app.quit_requests == 1)
	await ui.close_app(app)
	_remove_prefs(WORKSHOP_PREFS)


func _remove_prefs(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	if FileAccess.file_exists(absolute + ".display"):
		DirAccess.remove_absolute(absolute + ".display")
