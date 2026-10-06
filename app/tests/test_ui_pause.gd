# UI-02/UI-03: the pause menu over the real flight, with real key events (tests/ui_driver.gd), and End flight back
# to Home. Headless with --audio-driver Dummy, which mixes in real time, so the bus peak meter tells sound from silence.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_pause.gd
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")
const PREFS := "user://test_ui_pause_settings.cfg"

var _failures := 0
var ui: RefCounted
var app: Node


func _check(label: String, ok: bool, detail := "") -> void:
	if ok:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _key_down(code: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)


func _peak_db() -> float:
	return maxf(AudioServer.get_bus_peak_volume_left_db(0, 0), AudioServer.get_bus_peak_volume_right_db(0, 0))


func _run() -> void:
	TranslationServer.set_locale("en")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	app = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = PREFS
	root.add_child(app)
	await ui.settle()
	await ui.tap(KEY_ENTER) # Fly
	await _wait(0.4)
	var main: Node = app.flight
	var session: Node = main.session
	_check("flying with engine sound", not session.sim.paused and _peak_db() > -100.0, "%.1f dB" % _peak_db())

	# --- UI-02: Esc opens the pause menu and freezes everything.
	await ui.tap(KEY_ESCAPE)
	_check("Esc opens the pause menu, focus on Continue", app.pause_menu != null and ui.focus_name() == "Continue", ui.focus_name())
	_check("the session is held and paused", session.holds.has("menu") and session.sim.paused)
	var tick: int = session.sim.tick
	var prop: float = main._prop_angle
	await _wait(0.5)
	_check("simulation frozen (tick %d)" % tick, session.sim.tick == tick)
	_check("propeller frozen", main._prop_angle == prop)
	_check("engine sound paused and silent (%.1f dB)" % _peak_db(), main._engine_audio.stream_paused and _peak_db() <= -150.0)
	var commands: Dictionary = session.commands.duplicate()
	await ui.tap(KEY_DOWN)
	_check("Down navigates the menu -> Restart", ui.focus_name() == "Restart", ui.focus_name())
	await ui.tap(KEY_UP)
	_check("navigation keys never reach the flight commands", session.commands == commands)
	await ui.tap(KEY_R)
	await ui.tap(KEY_T)
	await ui.tap(KEY_P)
	_check("R, T and P do nothing behind the menu", session.sim.tick == tick and session.sim.paused and not main.recorder.recording)

	await ui.tap(KEY_ESCAPE)
	_check("Esc again: back to the flight", app.pause_menu == null and session.holds.is_empty() and not session.sim.paused)
	await _wait(0.4)
	_check("flying again: ticks, sound", session.sim.tick > tick and not main._engine_audio.stream_paused and _peak_db() > -100.0,
		"%.1f dB" % _peak_db())

	# --- Keys held while the menu closes stay masked until released.
	app.open_pause()
	await ui.settle()
	_key_down(KEY_RIGHT, true)
	await ui.settle()
	app.continue_flight()
	await _wait(0.4)
	_check("a key held through Continue does not fly", session.raw.roll == 0.0 and absf(session.commands.roll) < 1e-9, str(session.raw))
	_key_down(KEY_RIGHT, false)
	await ui.settle()
	_key_down(KEY_RIGHT, true)
	await _wait(0.3)
	_check("pressed again after release, it flies", session.raw.roll == 1.0 and session.commands.roll > 0.5, str(session.raw))
	_key_down(KEY_RIGHT, false)
	await _wait(0.3)

	# --- A crash shown under the menu: its countdown stops, Continue lets it finish and restart.
	var near: PackedFloat64Array = session.sim.state
	near[2] = 0.1
	session.sim.state = near
	session.sim.previous = near
	await _wait(0.2)
	_check("crash shown", not session.crash.is_empty())
	app.open_pause()
	await ui.settle()
	_check("menu explains the crash", "Crashed" in app.pause_menu.status_label.text, app.pause_menu.status_label.text)
	var left: int = session.crash.get("ticks_left", -1)
	await _wait(1.0)
	_check("crash countdown frozen under the menu (%d ticks left)" % left, session.crash.get("ticks_left", -1) == left)
	app.continue_flight()
	_check("Continue does not fly through the crash", app.pause_menu == null and session.sim.paused and not session.crash.is_empty())
	await _wait(1.8)
	_check("then the crash restarts the flight by itself", session.crash.is_empty() and not session.sim.paused)

	# --- Losing focus pauses (simulation.gd) and shows the menu.
	# The real path (research 24): SceneTree releases held keys, then propagates to every node.
	notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	notification(NOTIFICATION_APPLICATION_FOCUS_IN) # coming back never resumes by itself
	await ui.settle()
	_check("focus lost -> paused with the menu open", app.pause_menu != null and session.sim.paused)
	await ui.tap(KEY_ENTER) # Continue
	_check("Enter on Continue resumes", app.pause_menu == null and not session.sim.paused)

	# --- Esc during the radio calibration leaves the wizard, not the flight.
	session.calibration = RcCalibration.new()
	await ui.tap(KEY_ESCAPE)
	_check("Esc in the calibration wizard cancels it, no menu", session.calibration == null and app.pause_menu == null)
	session.resume()

	# --- A flight that cannot fly: Continue disabled and explained; Restart recovers.
	session.sim.fault_reason = "test fault"
	session.pause_reason = "simulation fault: test fault"
	app.open_pause()
	await ui.settle()
	var pm: CanvasLayer = app.pause_menu
	_check("fault: Continue disabled, focus on Restart, reason shown", pm.continue_button.disabled and ui.focus_name() == "Restart"
		and pm.status_label.text.begins_with("This flight cannot continue"), pm.status_label.text)
	app.continue_flight()
	_check("fault: Continue refused, menu stays", app.pause_menu != null and session.sim.paused)
	await ui.tap(KEY_ENTER) # Restart (focused)
	await _wait(0.3)
	_check("Restart: a fresh trimmed flight", app.pause_menu == null and not session.sim.paused and session.sim.fault_reason == ""
		and session.sim.time() < 0.5, "t=%.2f" % session.sim.time())

	# --- UI-03: End flight saves an active trace, then shows Home.
	var recorder: RefCounted = main.recorder # outlives the flight scene, which End frees
	recorder.start(session.trace_meta())
	await _wait(0.3)
	app.open_pause()
	await ui.settle()
	await ui.tap(KEY_DOWN)
	await ui.tap(KEY_DOWN)
	await ui.tap(KEY_DOWN)
	_check("End flight reachable by keyboard", ui.focus_name() == "End", ui.focus_name())
	await ui.tap(KEY_ENTER)
	var note: String = recorder.note
	var path := note.get_slice("trace saved: ", 1).get_slice(" (", 0)
	_check("End flight saved the trace", note.begins_with("trace saved") and FileAccess.file_exists(path), note)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	await ui.settle()
	_check("back on Home, flight freed", app.flight == null and app.home != null and app.home_scene != null and _count(root, "FlightSession") == 0)
	_check("focus on Fly again", ui.focus_name() == "Fly", ui.focus_name())

	# --- A trace that cannot be saved: the menu says so; End again ends without it.
	await ui.tap(KEY_ENTER) # Fly
	await _wait(0.2)
	app.flight.recorder = FakeRecorder.new()
	app.open_pause()
	await ui.settle()
	app.end_flight()
	_check("failed save: still in the flight, the menu explains", app.flight != null and app.pause_menu.note_label.visible
		and "Could not save" in app.pause_menu.note_label.text, app.pause_menu.note_label.text)
	app.end_flight()
	await ui.settle()
	_check("End again: Home, without the trace", app.flight == null and app.home != null)

	# --- Five Home -> Fly -> End cycles leave nothing behind.
	var counts := []
	for i in 5:
		await ui.settle()
		await ui.settle()
		counts.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		await ui.tap(KEY_ENTER)
		await _wait(0.2)
		app.open_pause()
		await ui.settle()
		app.end_flight()
	await ui.settle()
	await ui.settle()
	counts.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_check("5 cycles: same node count on Home every time %s" % str(counts), counts.min() == counts.max())
	_check("5 cycles: no session, engine sound or pause menu left", _count(root, "FlightSession") == 0
		and root.find_children("engine_sound", "", true, false).is_empty() and root.find_children("PauseMenu", "", true, false).is_empty())

	app.queue_free()
	await process_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("all UI pause checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


static func _count(n: Node, script_name: String) -> int:
	var count := 0
	for c in n.find_children("*", "Node", true, false):
		var s: Script = c.get_script()
		if s != null and s.resource_path.get_file().get_basename() == script_name.to_snake_case():
			count += 1
	return count


## Stands in for the recorder when the disk refuses the trace.
class FakeRecorder extends RefCounted:
	var recording := true
	var note := ""

	func stop(_path := "") -> Error:
		recording = false
		note = "trace save failed: error %d" % ERR_CANT_CREATE
		return ERR_CANT_CREATE

	func detach() -> void:
		recording = false

	func seconds() -> float:
		return 0.0
