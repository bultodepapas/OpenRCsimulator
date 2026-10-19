# UI-02/UI-03: the pause menu over the real flight, with real key events (tests/ui_driver.gd), and End flight back
# to Home. Headless with --audio-driver Dummy, which mixes in real time, so the bus peak meter tells sound from silence.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_ui_pause.gd
extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")
const ScreenTheme := preload("res://ui/ui_theme.gd")
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
	await _run_pause_layout_checks()
	await _run()


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

	# --- UI-02: Esc opens the pause menu and freezes everything, including the large Spanish text case.
	var default_presentation: Dictionary = app.display_preferences.config.duplicate(true)
	var large_spanish_presentation: Dictionary = default_presentation.duplicate(true)
	large_spanish_presentation.ui_scale = 2.0
	TranslationServer.set_locale("es")
	app._apply_presentation(large_spanish_presentation)
	await ui.settle()
	await ui.tap(KEY_ESCAPE)
	await ui.settle()
	_check("200% Spanish opens Pause with Continue focused",
		ui.focus_name() == "Continue", ui.focus_name())
	TranslationServer.set_locale("en")
	app._apply_presentation(default_presentation)
	await ui.settle()
	_check("Esc opens the pause menu, focus on Continue", app.pause_menu != null and ui.focus_name() == "Continue", ui.focus_name())
	_check("secondary Pause actions use the quiet treatment",
		app.pause_menu.restart_button.theme_type_variation == "QuietButton"
		and app.pause_menu.settings_button.theme_type_variation == "QuietButton"
		and app.pause_menu.help_button.theme_type_variation == "QuietButton")
	_check("quiet Pause rows are left-aligned while Continue stays centered",
		app.pause_menu.restart_button.alignment == HORIZONTAL_ALIGNMENT_LEFT
		and app.pause_menu.settings_button.alignment == HORIZONTAL_ALIGNMENT_LEFT
		and app.pause_menu.session_options_button.alignment == HORIZONTAL_ALIGNMENT_LEFT
		and app.pause_menu.help_button.alignment == HORIZONTAL_ALIGNMENT_LEFT
		and app.pause_menu.continue_button.alignment == HORIZONTAL_ALIGNMENT_CENTER)
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

	await ui.tap(KEY_DOWN)
	await ui.tap(KEY_DOWN)
	_check("Session options follows the primary recovery actions", ui.focus_name() == "SessionOptions", ui.focus_name())
	await ui.tap(KEY_ENTER)
	_check("Session options expands its secondary actions", app.pause_menu.session_options_container.visible
		and app.pause_menu.workshop_button.is_visible_in_tree())
	_check("Settings stays on the primary pause list", app.pause_menu.settings_button.is_visible_in_tree())
	await ui.tap(KEY_ESCAPE)
	_check("Back first closes Session options", app.pause_menu != null and not app.pause_menu.session_options_container.visible
		and session.holds.has("menu") and session.sim.paused)
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

	# --- CR-22a: Continue returns to the persistent wreck; Restart recovers flight.
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
	_check("wreck persists after Continue until explicit restart", not session.crash.is_empty() and session.sim.paused)
	app.open_pause()
	await ui.settle()
	app.restart_flight()
	await ui.settle()
	_check("menu Restart clears the wreck and resumes flight", session.crash.is_empty() and not session.sim.paused and app.pause_menu == null)

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

	# A rejected runway restart must keep the same menu and frozen flight, including on keyboard.
	app.open_pause()
	var held_menu: Node = app.pause_menu
	var runway_field: Dictionary = session._runway_field
	session._runway_field = {}
	var rejected_state := var_to_bytes([session.sim.state, session.sim.aux, session.sim.continuous, session.sim.tick])
	app.restart_flight()
	await _wait(0.1)
	_check("rejected restart keeps its menu, hold and explanation", app.pause_menu == held_menu
		and session.holds.has("menu") and session.sim.paused and "Could not restart" in held_menu.note_label.text)
	_check("rejected restart preserves the frozen flight", rejected_state == var_to_bytes(
		[session.sim.state, session.sim.aux, session.sim.continuous, session.sim.tick]))
	session._runway_field = runway_field
	app.restart_flight()
	_check("retry after rejected restart resumes keyboard flight", app.pause_menu == null and not session.sim.paused
		and session.start_error.is_empty())

	for cycle in 3:
		await ui.tap(KEY_ESCAPE)
		_check("keyboard cycle %d pauses again" % cycle, app.pause_menu != null and session.sim.paused)
		app.restart_flight()
		await _wait(0.05)
		_check("keyboard cycle %d restarts and advances" % cycle, app.pause_menu == null and session.holds.is_empty()
			and not session.sim.paused and session.sim.tick > 0 and session.engine_running)
		_check("keyboard cycle %d stays at runway idle without throttle input" % cycle,
			session.commands.throttle == 0.0 and session.sim.inputs[3] == 0.0)
	await ui.tap(KEY_R)
	_check("keyboard R shares the successful restart flow", app.pause_menu == null and not session.sim.paused
		and session.start_error.is_empty())

	# --- UI-03: End flight saves an active trace, then shows Home.
	var recorder: RefCounted = main.recorder # outlives the flight scene, which End frees
	recorder.start(session.trace_meta())
	await _wait(0.3)
	app.open_pause()
	await ui.settle()
	await ui.tap(KEY_DOWN) # Restart
	await ui.tap(KEY_DOWN) # Session options
	await ui.tap(KEY_ENTER)
	var traversed_session_options: Array[String] = []
	for i in 8:
		if ui.focus_name() == app.pause_menu.failure_settings_button.name:
			break
		await ui.tap(KEY_DOWN)
		traversed_session_options.append(ui.focus_name())
	_check("failure settings are reachable by keyboard",
		ui.focus_name() == app.pause_menu.failure_settings_button.name, str(traversed_session_options))
	await ui.tap(KEY_ESCAPE) # Session options collapses before the pause screen closes
	var traversed_pause_controls: Array[String] = []
	for i in 8:
		if ui.focus_name() == app.pause_menu.exit_options_button.name:
			break
		await ui.tap(KEY_DOWN)
		traversed_pause_controls.append(ui.focus_name())
	_check("Exit options are reachable on the primary pause list",
		ui.focus_name() == app.pause_menu.exit_options_button.name, str(traversed_pause_controls))
	await ui.tap(KEY_ENTER)
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

	# --- A failed manual trace remains an explicit decision until Stay, Retry, or Discard.
	await ui.tap(KEY_ENTER) # Fly
	await _wait(0.2)
	var failed_recorder := FakeRecorder.new()
	app.flight.recorder = failed_recorder
	app.open_pause()
	await ui.settle()
	app.end_flight()
	await ui.settle()
	var recovery := app.get("_trace_recovery_dialog") as ConfirmationDialog
	var recovery_message := recovery.find_child("TraceRecoveryMessage", true, false) as Label if recovery != null else null
	_check("failed save opens explicit recovery with Stay as the safe default",
		recovery != null and recovery.visible and recovery.get_ok_button().text == "Stay"
		and recovery_message != null and "was not saved" in recovery_message.text
		and failed_recorder.stop_calls == 1,
		recovery_message.text if recovery_message != null else "no recovery dialog message")
	_check("failed-save decision keeps the current flight held", app.flight != null
		and app.flight.session.holds.has("exit_guard"))
	if recovery != null:
		recovery.confirmed.emit() # Stay cancels this End request without resolving the trace.
	await ui.settle()
	_check("Stay keeps the failed trace pending and the flight in place", app.flight != null
		and failed_recorder.stop_calls == 1
		and app._trace_recovery.pending_count() == 1)
	app.end_flight()
	await ui.settle()
	recovery = app.get("_trace_recovery_dialog") as ConfirmationDialog
	_check("a later End reoffers recovery without stopping or discarding implicitly",
		recovery != null and recovery.visible and failed_recorder.stop_calls == 1
		and app._trace_recovery.pending_count() == 1)
	if recovery != null:
		recovery.custom_action.emit("discard")
	await ui.settle()
	_check("only explicit Discard trace and continue ends the flight", app.flight == null
		and app.home != null and failed_recorder.stop_calls == 1
		and app._trace_recovery.pending_count() == 0)

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

	await ui.close_app(app)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	print("all UI pause checks passed" if _failures == 0 else "%d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _run_pause_layout_checks() -> void:
	var saved_text_scale := ScreenTheme.text_scale
	ScreenTheme.text_scale = 1.0
	for reference_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var layout_viewport := SubViewport.new()
		layout_viewport.size = reference_size
		layout_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(layout_viewport)
		var session := PauseLayoutSession.new()
		layout_viewport.add_child(session)
		var pause := load("res://ui/pause_menu.gd").new() as CanvasLayer
		layout_viewport.add_child(pause)
		pause.show_for(session)
		await process_frame
		await process_frame
		var scroll: ScrollContainer = pause.find_child("PauseScroll", true, false) as ScrollContainer
		var panel_rect: Rect2 = scroll.get_parent().get_global_rect()
		_check("default Pause fits %s without a scrollbar" % str(reference_size),
			not scroll.get_v_scroll_bar().visible,
			"screen=%s panel=%s scroll=%s" % [str(layout_viewport.size),
			str(panel_rect), str(scroll.get_global_rect())])
		_check("100% Pause rail stays at its original 384px width",
			is_equal_approx(panel_rect.size.x, 384.0), str(panel_rect))
		_check("default Resume stays inside the pause panel",
			scroll.get_global_rect().encloses(pause.continue_button.get_global_rect()))
		pause.queue_free()
		session.queue_free()
		layout_viewport.queue_free()
		await process_frame

	var teardown_parent := Node.new()
	root.add_child(teardown_parent)
	var teardown_session := PauseLayoutSession.new()
	teardown_parent.add_child(teardown_session)
	var teardown_pause := load("res://ui/pause_menu.gd").new() as CanvasLayer
	teardown_parent.add_child(teardown_pause)
	teardown_pause.show_for(teardown_session)
	var pending_focus := Callable(teardown_pause, "_focus_primary")
	teardown_pause.queue_free()
	await process_frame
	_check("pending Pause focus is disconnected when teardown frees the menu",
		not is_instance_valid(teardown_pause) and not process_frame.is_connected(pending_focus))
	teardown_session.queue_free()
	teardown_parent.queue_free()
	await process_frame

	var scale_viewport := SubViewport.new()
	scale_viewport.size = Vector2i(1920, 1080)
	scale_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(scale_viewport)
	var scale_parent := Node.new()
	scale_viewport.add_child(scale_parent)
	var scale_session := PauseLayoutSession.new()
	scale_parent.add_child(scale_session)
	var scale_pause := load("res://ui/pause_menu.gd").new() as CanvasLayer
	scale_parent.add_child(scale_pause)
	scale_pause.show_for(scale_session)
	await process_frame
	var scale_panel: PanelContainer = scale_pause.find_children("*", "PanelContainer", true, false)[0] as PanelContainer
	var scale_screen := scale_pause.get_node("Screen") as Control
	_check("live Pause starts with a 384px rail at 100%",
		is_equal_approx(scale_panel.custom_minimum_size.x, 384.0), str(scale_panel.custom_minimum_size))
	ScreenTheme.text_scale = 2.0
	scale_screen.theme = ScreenTheme.build()
	await process_frame
	_check("live theme change expands the Pause rail at 200%",
		scale_panel.custom_minimum_size.x > 384.0 and scale_panel.custom_minimum_size.x <= 768.0,
		str(scale_panel.custom_minimum_size))
	ScreenTheme.text_scale = 1.0
	scale_screen.theme = ScreenTheme.build()
	await process_frame
	_check("live theme revert restores the 384px Pause rail at 100%",
		is_equal_approx(scale_panel.custom_minimum_size.x, 384.0), str(scale_panel.custom_minimum_size))
	scale_pause.queue_free()
	scale_session.queue_free()
	scale_parent.queue_free()
	scale_viewport.queue_free()
	await process_frame

	ScreenTheme.text_scale = 2.0
	TranslationServer.set_locale("es")
	var enlarged_viewport := SubViewport.new()
	enlarged_viewport.size = Vector2i(1920, 1080)
	enlarged_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(enlarged_viewport)
	var delayed_session := PauseLayoutSession.new()
	delayed_session.pause_reason = "radio disconnected"
	enlarged_viewport.add_child(delayed_session)
	var enlarged_pause := load("res://ui/pause_menu.gd").new() as CanvasLayer
	enlarged_viewport.add_child(enlarged_pause)
	enlarged_pause.show_for(delayed_session)
	await process_frame
	await process_frame
	var enlarged_scroll: ScrollContainer = enlarged_pause.find_child("PauseScroll", true, false) as ScrollContainer
	var enlarged_panel_rect: Rect2 = enlarged_scroll.get_parent().get_global_rect()
	_check("200% Pause rail widens while staying within the viewport bound",
		enlarged_panel_rect.size.x >= 700.0 and enlarged_panel_rect.size.x <= 1920.0 * 0.45
		and enlarged_panel_rect.end.x <= 1920.0,
		str(enlarged_panel_rect))
	var continue_button: Button = enlarged_pause.continue_button
	continue_button.text = "Continuar" # SceneTree translation is bypassed in this detached viewport fixture.
	var button_style: StyleBox = continue_button.get_theme_stylebox("normal")
	var text_font: Font = continue_button.get_theme_font("font")
	var text_width: float = text_font.get_string_size(
		continue_button.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, continue_button.get_theme_font_size("font_size")
	).x
	var available_text_width: float = continue_button.size.x - button_style.get_content_margin(SIDE_LEFT) - button_style.get_content_margin(SIDE_RIGHT)
	_check("Spanish Continue stays on one line at 200% text",
		continue_button.text == "Continuar" and continue_button.autowrap_mode == TextServer.AUTOWRAP_WORD
		and text_width <= available_text_width,
		"text=%s width=%.1f available=%.1f mode=%d" % [continue_button.text, text_width, available_text_width,
		continue_button.autowrap_mode])
	var enlarged_column: VBoxContainer = enlarged_scroll.get_child(0) as VBoxContainer
	var pause_header: Control = enlarged_column.get_child(0) as Control
	enlarged_scroll.ensure_control_visible(continue_button)
	await process_frame
	var scroll_rect: Rect2 = enlarged_scroll.get_global_rect()
	var header_rect: Rect2 = pause_header.get_global_rect()
	var continue_rect: Rect2 = continue_button.get_global_rect()
	_check("200% Pause keeps its header and Continue visible together",
		scroll_rect.encloses(header_rect) and scroll_rect.encloses(continue_rect),
		"scroll=%s header=%s continue=%s scroll_y=%d max=%d" % [str(scroll_rect), str(header_rect),
		str(continue_rect), enlarged_scroll.scroll_vertical, enlarged_scroll.get_v_scroll_bar().max_value])
	_check("200% Continue remains enabled and keyboard-focusable",
		not continue_button.disabled and continue_button.focus_mode != Control.FOCUS_NONE)
	enlarged_pause._toggle_group("exit")
	_check("200% exit options open and Quit remains operable",
		enlarged_pause.exit_options_container.visible and enlarged_pause.quit_button.visible
		and not enlarged_pause.quit_button.disabled
		and enlarged_pause.quit_button.focus_mode != Control.FOCUS_NONE)
	enlarged_pause.queue_free()
	delayed_session.queue_free()
	enlarged_viewport.queue_free()
	await process_frame
	TranslationServer.set_locale("en")
	ScreenTheme.text_scale = saved_text_scale


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


class PauseLayoutSession extends Node:
	var pause_reason := ""
	var external_controller_selection := false
	var crash: Dictionary = {}

	func is_flyable() -> bool:
		return true
