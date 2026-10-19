# UI-03-R1: quit policy, real manual trace saving and Window-close lifecycle.
extends SceneTree

const Catalog := preload("res://app_state/aircraft_catalog.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
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
	var retained_trace := true

	func stop(_path := "") -> Error:
		stop_calls += 1
		recording = false
		if stop_calls == 1:
			note = "trace save failed: error %d" % ERR_CANT_CREATE
			return ERR_CANT_CREATE
		note = "trace saved: retained trace"
		return OK

	func detach() -> void:
		recording = false

	func seconds() -> float:
		return 0.0


class AlwaysFailRecorder extends RefCounted:
	var recording := true
	var stop_calls := 0
	var note := ""
	var retained_trace := true

	func stop(_path := "") -> Error:
		stop_calls += 1
		recording = false
		note = "trace save failed: error %d" % ERR_CANT_CREATE
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

	# The Recorder contract stops even when the save fails. Recovery must keep the retained Trace explicit.
	app.quit_requests = 0
	var failed_recorder := FailOnceRecorder.new()
	app.flight.recorder = failed_recorder
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await ui.settle()
	var session: Node = app.flight.session
	var failed_dialog := app.get("_trace_recovery_dialog") as ConfirmationDialog
	_check("duplicate failed Window close saves only once", failed_recorder.stop_calls == 1,
		"stop_calls=%d" % failed_recorder.stop_calls)
	_check("failed close opens explicit recovery with Stay as the default",
		failed_dialog != null and failed_dialog.visible and failed_dialog.get_ok_button().text == "Stay"
		and "was not saved" in failed_dialog.dialog_text and app.quit_requests == 0,
		failed_dialog.dialog_text if failed_dialog != null else "no recovery dialog")
	_check("close decision holds the flight and masks it until the decision",
		session.holds.has("exit_guard") and session.sim.paused)
	app.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await ui.settle()
	_check("repeated Window close while recovery is open does not stop twice or stack dialogs",
		failed_recorder.stop_calls == 1 and app.get("_trace_recovery_dialog") == failed_dialog)
	if failed_dialog != null:
		failed_dialog.custom_action.emit("retry")
	await ui.settle()
	_check("Retry saves the retained trace and completes quit exactly once",
		failed_recorder.stop_calls == 2 and failed_recorder.note.begins_with("trace saved:")
		and app.quit_requests == 1 and app._trace_recovery.pending_count() == 0,
		"stops=%d quits=%d" % [failed_recorder.stop_calls, app.quit_requests])
	_check("successful retry releases the exit hold", not session.holds.has("exit_guard"))

	# An explicit Quit after failure must show the decision again; accepting a second Quit is not Discard.
	app.quit_requests = 0
	var always_fails := AlwaysFailRecorder.new()
	app.flight.recorder = always_fails
	var previous_window_size: Vector2i = root.size
	root.size = Vector2i(1280, 720) # Headless SceneTree starts at 64×64; exercise a normal desktop viewport.
	await ui.settle()
	var previous_text_scale: float = UiTheme.text_scale
	UiTheme.text_scale = 2.0
	app.quit_app()
	await ui.settle()
	var stay_dialog := app.get("_trace_recovery_dialog") as ConfirmationDialog
	var message_label := stay_dialog.get_label() if stay_dialog != null else null
	var desktop_size: Vector2i = root.size
	_check("trace recovery uses the shared theme, wraps, and stays within the viewport at 200%",
		stay_dialog != null and stay_dialog.theme.default_font_size >= 40
		and message_label != null and message_label.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART
		and stay_dialog.size.x <= desktop_size.x and stay_dialog.size.y <= desktop_size.y,
		"font=%s size=%s viewport=%s" % [str(stay_dialog.theme.default_font_size) if stay_dialog != null else "none",
		str(stay_dialog.size) if stay_dialog != null else "none", str(desktop_size)])
	if stay_dialog != null:
		stay_dialog.confirmed.emit()
	await ui.settle()
	UiTheme.text_scale = previous_text_scale
	root.size = previous_window_size
	await ui.settle()
	_check("Stay keeps an always-failing trace pending and the app open",
		app.quit_requests == 0 and always_fails.stop_calls == 1 and app._trace_recovery.pending_count() == 1)
	app.quit_app()
	await ui.settle()
	var repeated_dialog := app.get("_trace_recovery_dialog") as ConfirmationDialog
	_check("a later Quit reopens recovery without an implicit discard or repeated stop",
		repeated_dialog != null and always_fails.stop_calls == 1 and app.quit_requests == 0)
	if repeated_dialog != null:
		repeated_dialog.custom_action.emit("discard")
	await ui.settle()
	_check("only explicit Discard trace and continue resolves the failed trace",
		always_fails.stop_calls == 1 and app.quit_requests == 1 and app._trace_recovery.pending_count() == 0)
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
	app.open_workshop()
	await ui.settle()
	var live_editor: Node = app.screens.top()
	live_editor.set_variant_name("Unsaved Home draft")
	app.quit_app()
	await ui.settle()
	var live_guard := live_editor.get("_guard_dialog") as ConfirmationDialog
	_check("quit guards a live dirty Workshop before any flight or route change",
		live_guard != null and live_guard.get_parent() == app and live_editor.has_unsaved_changes()
		and app.flight == null and app.screens.top() == live_editor)
	if live_guard != null:
		live_guard.canceled.emit()
	await ui.settle()
	_check("Cancel from the live Workshop quit guard keeps the editor and draft",
		live_editor.has_unsaved_changes() and app.flight == null and app.screens.top() == live_editor)
	var live_close_button := live_editor.find_child("CloseWorkshop", true, false) as Button
	_check("Home Workshop exposes Back to Home", live_close_button != null and live_close_button.text == "Back to Home")
	var menu_back := InputEventJoypadButton.new()
	menu_back.device = -1 # Bind every joystick, including UiDriver's isolated fake device.
	menu_back.button_index = JOY_BUTTON_B
	var added_menu_back := not InputMap.action_has_event("ui_cancel", menu_back)
	if added_menu_back:
		InputMap.action_add_event("ui_cancel", menu_back)
	await ui.joy_button(JOY_BUTTON_B)
	if added_menu_back:
		InputMap.action_erase_event("ui_cancel", menu_back)
	await ui.settle()
	var close_guard := live_editor.get("_guard_dialog") as ConfirmationDialog
	_check("menu-pad ui_cancel reaches the editor close guard", close_guard != null)
	if close_guard != null:
		close_guard.custom_action.emit("discard")
	await ui.settle()
	_check("editor Close uses its own guard and returns to Home", app.screens.is_top("home")
		and app.screens.top() == app.home)
	app.start_flight()
	await process_frame
	if app.flight == null:
		_check("Workshop fixture starts its original flight", false)
		await ui.close_app(app)
		_remove_prefs(WORKSHOP_PREFS)
		return
	var original: Node = app.flight
	app.open_pause()
	await ui.settle()
	app.open_workshop()
	var editor: Node = app.screens.top()
	var close_button := editor.find_child("CloseWorkshop", true, false) as Button
	_check("Workshop opened from Pause exposes its context-specific return label",
		str(editor.get("return_destination")) == "Pause" and close_button != null
		and close_button.text == "Back to Pause",
		"top=%s pause_top=%s destination=%s label=%s" % [str(app.screens.top()), str(app.screens.is_top("pause")),
		str(editor.get("return_destination")), close_button.text if close_button != null else "no Back button"])
	editor.set_variant_name("Unsaved trial draft")
	_check("Workshop test fixture has a dirty retained draft", editor.has_unsaved_changes())
	var aircraft_data: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	app._start_workshop_trial({base_id = Catalog.DEFAULT_ID, base_bytes = aircraft_data, recipe = {scale = 1.0}})
	_check("Workshop trial suspends the original flight", app.flight != null
		and app.flight != original and app._workshop_previous_flight == original and not original.is_inside_tree())
	var trial := app.flight
	var trial_recorder := AlwaysFailRecorder.new()
	var retained_recorder := FailOnceRecorder.new()
	trial.recorder = trial_recorder
	original.recorder = retained_recorder
	app.open_pause()
	await ui.settle()
	var trial_pause: Node = app.pause_menu
	var return_actions := 0
	for candidate: Node in trial_pause.find_children("*", "Button", true, false):
		if candidate is Button and candidate.visible and candidate.text == "Return to Workshop":
			return_actions += 1
	_check("trial Pause uses Resume trial and one direct Return to Workshop",
		trial_pause.continue_button.text == "Resume trial" and trial_pause.restart_button.text == "Restart trial"
		and trial_pause.end_button.get_parent() != trial_pause.exit_options_container
		and not trial_pause.workshop_button.visible and return_actions == 1,
		"return actions=%d" % return_actions)
	_check("trial flight hint matches Escape-to-Pause and the visible return action",
		str(trial.get("_note")).contains("Esc opens Pause") and str(trial.get("_note")).contains("Return to Workshop"),
		str(trial.get("_note")))
	app.continue_flight()
	await ui.settle()
	_check("trial resumes before the quit decision", app.flight == trial and not trial.session.sim.paused)

	app.quit_app()
	await ui.settle()
	var editor_guard := editor.get("_guard_dialog") as ConfirmationDialog
	_check("quit inspects the detached dirty Workshop before stopping either recorder",
		editor_guard != null and editor_guard.get_parent() == app and editor.has_unsaved_changes()
		and trial_recorder.stop_calls == 0 and retained_recorder.stop_calls == 0
		and app.flight == trial and app._workshop_previous_flight == original
		and trial.session.holds.has("exit_guard") and original.session.holds.has("exit_guard"),
		"trial=%d retained=%d" % [trial_recorder.stop_calls, retained_recorder.stop_calls])
	app.quit_app()
	_check("repeated Quit remains coalesced on the same detached-editor decision",
		trial_recorder.stop_calls == 0 and retained_recorder.stop_calls == 0
		and editor.get("_guard_dialog") == editor_guard)
	if editor_guard != null:
		editor_guard.canceled.emit()
	await ui.settle()
	_check("cancel preserves draft, both recorder states, and the running trial",
		editor.has_unsaved_changes() and trial_recorder.recording and retained_recorder.recording
		and trial_recorder.stop_calls == 0 and retained_recorder.stop_calls == 0
		and not trial.session.holds.has("exit_guard") and not original.session.holds.has("exit_guard")
		and not trial.session.sim.paused and original.session.sim.paused,
		"trial paused=%s original paused=%s" % [trial.session.sim.paused, original.session.sim.paused])

	# Discard authorizes this attempt only. A later trace Stay keeps the draft dirty, so the next quit asks again.
	app.quit_app()
	await ui.settle()
	var discard_guard := editor.get("_guard_dialog") as ConfirmationDialog
	if discard_guard != null:
		discard_guard.custom_action.emit("discard")
	await ui.settle()
	var trial_failure_dialog := app.get("_trace_recovery_dialog") as ConfirmationDialog
	_check("draft Discard proceeds to trial trace save, without touching the retained recorder yet",
		editor.has_unsaved_changes() and trial_recorder.stop_calls == 1 and not trial_recorder.recording
		and retained_recorder.stop_calls == 0 and retained_recorder.recording
		and trial_failure_dialog != null and app.quit_requests == 0,
		"trial=%d retained=%d" % [trial_recorder.stop_calls, retained_recorder.stop_calls])
	if trial_failure_dialog != null:
		trial_failure_dialog.custom_action.emit("discard")
	await ui.settle()
	var retained_failure_dialog := app.get("_trace_recovery_dialog") as ConfirmationDialog
	_check("trial Discard resolves only its trace before the retained recorder's failure",
		editor.has_unsaved_changes() and trial_recorder.stop_calls == 1 and retained_recorder.stop_calls == 1
		and not retained_recorder.recording and retained_failure_dialog != null
		and app._trace_recovery.pending_count() == 1 and app.quit_requests == 0)
	if retained_failure_dialog != null:
		retained_failure_dialog.confirmed.emit() # Stay
	await ui.settle()
	_check("trace Stay leaves the draft and retained trace pending independently",
		editor.has_unsaved_changes() and trial_recorder.stop_calls == 1 and retained_recorder.stop_calls == 1
		and not retained_recorder.recording and app._trace_recovery.pending_count() == 1
		and app.quit_requests == 0 and not trial.session.sim.paused)

	app.quit_app()
	await ui.settle()
	var second_guard := editor.get("_guard_dialog") as ConfirmationDialog
	_check("a later quit still prompts for the dirty draft after trace Stay", second_guard != null)
	if second_guard != null:
		second_guard.custom_action.emit("discard")
	await ui.settle()
	var retry_retained_dialog := app.get("_trace_recovery_dialog") as ConfirmationDialog
	_check("discarded trial trace stays resolved while retained failure is offered again",
		trial_recorder.stop_calls == 1 and retained_recorder.stop_calls == 1
		and retry_retained_dialog != null and app._trace_recovery.pending_count() == 1
		and app.quit_requests == 0)
	if retry_retained_dialog != null:
		retry_retained_dialog.custom_action.emit("retry")
	await ui.settle()
	_check("Retry saves only the retained trace and completes quit",
		trial_recorder.stop_calls == 1 and retained_recorder.stop_calls == 2
		and retained_recorder.note.begins_with("trace saved:")
		and app._trace_recovery.pending_count() == 0 and app.quit_requests == 1,
		"trial=%d retained=%d" % [trial_recorder.stop_calls, retained_recorder.stop_calls])

	# A real Return action remains the final route owner after both recorder outcomes are resolved.
	app._return_to_workshop()
	await ui.settle()
	_check("Return to Workshop restores the original flight and same dirty editor",
		app.flight == original and app._workshop_previous_flight == null
		and app.screens.is_top("workshop") and app.screens.top() == editor and editor.has_unsaved_changes())
	await ui.close_app(app)
	_remove_prefs(WORKSHOP_PREFS)


func _remove_prefs(path: String) -> void:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	if FileAccess.file_exists(absolute + ".display"):
		DirAccess.remove_absolute(absolute + ".display")
