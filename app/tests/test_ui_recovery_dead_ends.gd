# UI-31 (UI-30 audit PS-1…PS-12): no reachable flight state may hold the simulation without a visible next action.
# Real key events (tests/ui_driver.gd) on the production shell; a synthetic pad covers the controller routes.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_recovery_dead_ends.gd
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const KEYBOARD_PREFS := "user://test_ui_recovery_keyboard.cfg"
const PAD_PREFS := "user://test_ui_recovery_pad.cfg"

var _failures := 0
var ui: RefCounted


## A wizard whose next Enter completes it, without a radio. Its empty profile is refused and never saved.
class FinishingWizard extends "res://input/rc_calibration.gd":
	func advance(_axes: PackedFloat64Array) -> bool:
		return true


class AlwaysFailRecorder extends RefCounted:
	var recording := true
	var stop_calls := 0
	var note := ""

	func stop(_path := "") -> Error:
		stop_calls += 1
		recording = false
		note = "trace save failed: error %d" % ERR_CANT_CREATE
		return ERR_CANT_CREATE

	func detach() -> void:
		recording = false

	func seconds() -> float:
		return 0.0


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	await _keyboard_routes()
	await _controller_routes()
	print("UI recovery dead ends: %d failed" % _failures)
	quit(1 if _failures else 0)


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _new_app(prefs: String) -> Node:
	for suffix in ["", ".display", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs + suffix))
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = prefs
	root.add_child(app)
	await ui.settle()
	return app


func _keyboard_routes() -> void:
	TranslationServer.set_locale("en")
	var app := await _new_app(KEYBOARD_PREFS)
	await ui.tap(KEY_ENTER) # Fly
	await _wait(0.3)
	var main: Node = app.flight
	var session: Node = main.session
	session.profiles_path = "user://test_ui_recovery_rc.cfg" # never the pilot's real calibration file
	_check("keyboard flight is running", not session.sim.paused and app.pause_menu == null)

	# --- PS-1: the wizard is visible whatever overlay preset is active, and ending it reopens Pause.
	session.calibration = RcCalibration.new()
	session.sim.set_paused(true)
	await ui.settle()
	var card := main.get_node_or_null("CalibrationCard") as CanvasLayer
	var prompt := card.find_child("Prompt", true, false) as Label if card != null else null
	_check("calibration card is shown during the wizard", card != null and card.visible
		and prompt != null and prompt.text.begins_with("Centre the sticks"), prompt.text if prompt != null else "no card")
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("Esc cancels the wizard and opens Pause with the result", session.calibration == null
		and app.screens.is_top("pause") and session.sim.paused
		and app.pause_menu.status_label.text.contains("Radio calibration cancelled"), app.pause_menu.status_label.text if app.pause_menu != null else "no Pause")
	_check("calibration card hides with the wizard", card != null and not card.visible)
	app.continue_flight()
	await ui.settle()
	_check("Continue after a cancelled wizard flies again", app.pause_menu == null and not session.sim.paused)
	session.calibration = FinishingWizard.new()
	session.sim.set_paused(true)
	await ui.settle()
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("the final Enter opens Pause instead of leaving a frozen flight", session.calibration == null
		and app.screens.is_top("pause") and session.sim.paused)
	# The shell persists through the controller store, which refuses this profile-less wizard: the result says so.
	_check("Pause reports the calibration result", app.pause_menu != null
		and app.pause_menu.status_label.text.begins_with("Radio calibration was not saved"), app.pause_menu.status_label.text if app.pause_menu != null else "no Pause")
	app.continue_flight()
	await ui.settle()

	# --- PS-4: Continue never closes Pause while another hold would keep the flight frozen.
	app.open_pause()
	await ui.settle()
	session.hold("test tool")
	app.continue_flight()
	await ui.settle()
	_check("Continue with another hold keeps Pause and explains it", app.screens.is_top("pause")
		and app.pause_menu.note_label.visible, app.pause_menu.note_label.text if app.pause_menu != null else "no Pause")
	session.release("test tool")
	app.continue_flight()
	await ui.settle()
	_check("Continue flies once the other hold is gone", app.pause_menu == null and not session.sim.paused)

	# --- PS-10: the flight-log label never draws over menus.
	await ui.tap(KEY_F10)
	var log_label := main.get("_flight_log_label") as Label
	var log_layer := log_label.get_parent() as CanvasLayer if log_label != null else null
	_check("flight-log label is shown while flying", log_layer != null and log_layer.visible)
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("flight-log label hides with the overlays under Pause", app.pause_menu != null and log_layer != null and not log_layer.visible)
	app.continue_flight()
	await ui.settle()
	_check("flight-log label returns with the overlays", log_layer != null and log_layer.visible)
	await ui.tap(KEY_F10)

	# --- PS-11: Restart saves an active trace first; a failed save is an explicit decision.
	var failing := AlwaysFailRecorder.new()
	var original_recorder: RefCounted = main.recorder
	main.recorder = failing
	app.open_pause()
	await ui.settle()
	var tick_before: int = session.sim.tick
	app.restart_flight()
	await ui.settle()
	var recovery := app.get("_trace_recovery_dialog") as ConfirmationDialog
	_check("Restart with a failed trace save asks before resetting", recovery != null and recovery.visible
		and failing.stop_calls == 1 and session.sim.tick == tick_before and app.screens.is_top("pause"))
	if recovery != null:
		recovery.custom_action.emit("discard")
	await ui.settle()
	_check("Discard then restarts the flight", app.get("_trace_recovery_dialog") == null and app.pause_menu == null
		and not session.sim.paused and failing.stop_calls == 1)
	main.recorder = original_recorder

	# --- PS-12: losing the OS window focus pauses at once, not only on application focus loss. An embedded dialog
	# also takes focus from the root viewport; that alone must not pause (the probe still reports OS focus).
	propagate_window_focus_out()
	await ui.settle()
	_check("embedded focus change while the OS window keeps focus does not pause", app.pause_menu == null and not session.sim.paused)
	app.window_focus_probe = func() -> bool: return false
	propagate_window_focus_out()
	await ui.settle()
	_check("OS window focus-out opens Pause", app.pause_menu != null and session.sim.paused)
	app.window_focus_probe = func() -> bool: return true
	app.continue_flight()
	await ui.settle()

	# --- PS-7: helicopter R uses the shared restart transaction.
	app.end_flight()
	await ui.settle()
	app.set_aircraft("xcell-60-research")
	await ui.settle()
	app.start_flight()
	await _wait(0.3)
	var heli: Node = app.flight
	_check("helicopter flight starts", heli != null and Catalog.is_rotorcraft(str(heli.get("aircraft_id"))))
	if heli != null:
		_check("helicopter exposes the shared restart request", heli.has_signal("restart_requested")
			and not heli.restart_requested.get_connections().is_empty())
		if app.pause_menu != null:
			app.continue_flight()
			await ui.settle()
		await ui.tap(KEY_R)
		await ui.settle()
		_check("helicopter R restarts through the shell", app.pause_menu == null and heli.session.is_flyable())
	app.queue_free()
	await ui.settle()


func propagate_window_focus_out() -> void:
	root.propagate_notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)


func _controller_routes() -> void:
	var app := await _new_app(PAD_PREFS)
	var devices: Array = [{"id": 15, "name": "Synthetic Xbox", "known": true, "guid": "recovery-test-pad"}]
	app.controllers.enumerate_devices = func() -> Array: return devices
	app.controllers.refresh()
	app.start_flight()
	var session: Node = app.flight.session
	var fake_axes := {1: 0.03084}
	session.read_axis = func(_id: int, axis: int) -> float: return float(fake_axes.get(axis, 0.0))
	session.read_button = func(_id: int, _button: int) -> bool: return false
	session.radio.confirmed_gamepad_connection = func(id: int) -> bool: return id == 15
	await _wait(0.35)
	_check("pad flight starts ready", session.radio.armed and not session.sim.paused and app.pause_menu == null)

	# --- PS-2: a lost controller puts Controller settings at the top of Pause and focuses it.
	app.open_pause()
	await ui.settle()
	_check("ready controller: no recovery action", app.pause_menu != null and not app.pause_menu.controller_recovery_button.visible)
	app.continue_flight()
	await ui.settle()
	session.controller_disconnected()
	app.open_pause()
	await ui.settle()
	_check("lost controller: Controller settings is visible without opening a group", app.pause_menu != null
		and app.pause_menu.controller_recovery_button.visible and app.pause_menu._open_group == "")
	_check("lost controller: focus is on the recovery action", ui.focus_name() == "ControllerRecovery", ui.focus_name())
	await ui.tap(KEY_ENTER)
	await ui.settle()
	_check("recovery action opens Controller settings", app.screens.is_top("controls"))
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("closing Controller settings returns to Pause", app.screens.is_top("pause"))

	# --- PS-3: a Workshop trial with a selected controller launches like a Home flight.
	app.end_flight()
	await ui.settle()
	app.open_workshop()
	await ui.settle()
	var source: PackedByteArray = FileAccess.get_file_as_bytes(Catalog.entry(Catalog.DEFAULT_ID).data)
	app._start_workshop_trial({base_id = Catalog.DEFAULT_ID, base_bytes = source, recipe = {scale = 1.0}})
	var trial: Node = app.flight
	if trial != null:
		trial.session.read_axis = func(_id: int, axis: int) -> float: return float(fake_axes.get(axis, 0.0))
		trial.session.read_button = func(_id: int, _button: int) -> bool: return false
		trial.session.radio.confirmed_gamepad_connection = func(id: int) -> bool: return id == 15
	await _wait(0.35)
	_check("trial with a controller is never frozen without a menu", trial != null
		and (app.pause_menu != null or not trial.session.sim.paused),
		"paused=%s pause_menu=%s" % [trial.session.sim.paused if trial != null else "none", app.pause_menu != null])
	app.queue_free()
	await ui.settle()
