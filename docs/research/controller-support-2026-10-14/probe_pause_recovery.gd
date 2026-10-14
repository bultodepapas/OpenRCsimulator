extends SceneTree
const UiDriver := preload("res://tests/ui_driver.gd")
const PREFS := "user://native_pause_recovery_probe.cfg"
var output_path := "user://native_pause_recovery_probe.json"
var app: Node
var report := {"synthetic_axis_events": false, "probe": "Actual connected native gamepad at rest; isolated preferences; automated UI Enter presses."}

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output_path = arg.trim_prefix("--out=")
	_run.call_deferred()

func _run() -> void:
	for suffix in ["", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
	app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	root.title = "OpenRC — comprobando pausa y reinicio"
	root.grab_focus()
	await create_timer(0.7).timeout
	app.controllers.refresh()
	var selected: int = app.controllers.registry.selected_device_id("flight")
	var info: Dictionary = app.controllers.registry.device_for_id(selected)
	report["device"] = {"name": info.get("name", ""), "known": info.get("known", false), "kind": info.get("kind", "")}
	if selected < 0 or not bool(info.get("known", false)) or info.get("kind", "") != "gamepad":
		report["error"] = "No recognized native gamepad connected."
		_finish(false)
		return
	app.start_flight()
	var session: Node = app.flight.session
	var verifier: Callable = session.radio.confirmed_gamepad_connection
	session.radio.confirmed_gamepad_connection = Callable() # reproduce previous event-only contract
	session.radio.require_neutral(true, true)
	await create_timer(0.7).timeout
	report["previous_event_only_armed"] = session.radio.armed
	report["previous_seen_axes"] = session.radio._seen.keys()
	report["resting_axes"] = Array(session.radio.axes)
	app.continue_flight()
	report["previous_continue_blocked"] = app.pause_menu != null and session.sim.paused
	session.radio.confirmed_gamepad_connection = verifier
	session.radio.require_neutral(true, true)
	root.grab_focus()
	await create_timer(0.7).timeout
	report["focused"] = root.has_focus()
	report["connection_verified"] = bool(verifier.call(selected))
	report["fixed_neutral_armed"] = session.radio.armed
	report["fixed_still_paused"] = session.sim.paused
	if not session.radio.armed:
		report["error"] = "Live neutral gate was not ready; inspect focus and axis/button values."
		_finish(false)
		return
	var ui := UiDriver.new(self)
	app.pause_menu.continue_button.grab_focus()
	await ui.tap(KEY_ENTER)
	report["continue_succeeded"] = app.pause_menu == null and not session.sim.paused
	app.open_pause()
	await create_timer(0.3).timeout
	app.pause_menu.restart_button.grab_focus()
	await ui.tap(KEY_ENTER)
	report["restart_acknowledged"] = app.pause_menu != null and session.sim.paused and app.pause_menu.note_label.visible
	await create_timer(0.7).timeout
	report["restart_neutral_armed"] = session.radio.armed
	app.pause_menu.continue_button.grab_focus()
	await ui.tap(KEY_ENTER)
	report["continue_after_restart_succeeded"] = app.pause_menu == null and not session.sim.paused
	_finish(report.continue_succeeded and report.restart_neutral_armed and report.continue_after_restart_succeeded)

func _finish(passed: bool) -> void:
	report["passed"] = passed
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print(JSON.stringify(report))
	app.free()
	for suffix in ["", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS + suffix))
	await process_frame
	await process_frame
	quit(0 if passed else 1)
