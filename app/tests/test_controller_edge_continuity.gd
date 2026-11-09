extends SceneTree

const Shell := preload("res://app_root.gd")
const Main := preload("res://main.gd")
const Session := preload("res://sim/flight_session.gd")
const Registry := preload("res://input/controller_registry.gd")
const Profile := preload("res://input/controller_profile.gd")
const Store := preload("res://input/controller_profile_store.gd")
const Screen := preload("res://ui/screen.gd")
const UiInput := preload("res://ui/ui_input.gd")
const Fixtures := preload("res://tests/test_jeti_setup.gd")

var checks := 0
var failures := 0

class RoutingShell extends Shell:
	var restarts := 0
	func _ready() -> void: pass
	func _request_flight_restart() -> void: restarts += 1

class FixtureService extends Node:
	var registry := Registry.new()
	var store := Fixtures.FakeStore.new()
	var flight_profile := Profile.defaults("joystick", "radio_custom")
	var ui_profile := Profile.defaults()
	func profile_for_device(id: int) -> Dictionary:
		return (ui_profile if id == 8 else flight_profile).duplicate(true)
	func is_ui_gamepad(id: int) -> bool:
		return id == 8 and ui_profile.get("kind", "") == "gamepad" and bool(registry.device_for_id(id).get("connected", false))
	func save_settings_from_setup(candidate: Dictionary, flight_id: int, ui_id: int) -> Dictionary:
		var result: Dictionary = store.save_profile(candidate)
		if result.ok:
			flight_profile = candidate.duplicate(true)
			registry.select_device("ui", ui_id)
			registry.select_device("flight", flight_id)
		return result

func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)

func motion(axis: int, value: float, device := 7) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	return event

func button(index: int, pressed: bool, device := 7) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = index
	event.pressed = pressed
	return event

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_same_frame_remap()
	var shell := RoutingShell.new()
	var service := FixtureService.new()
	service.flight_profile.configured = true
	service.flight_profile.actions = {
		"restart_flight": {"type": "axis", "axis": 9, "sign": 1, "threshold": 0.65},
		"rates_toggle": {"type": "axis", "axis": 8, "sign": -1, "threshold": 0.65}}
	service.registry.update_devices([
		{id = 7, known = false, name = "Flight stick"},
		{id = 8, known = true, name = "Menu pad"},
		{id = 9, known = false, name = "Other flight stick"}])
	service.registry.select_device("flight", 7)
	service.registry.select_device("ui", 8)
	var session := Session.new()
	session.physics_enabled = false
	session.input_enabled = false
	session.external_controller_selection = true
	session.setup()
	session.radio.connect_device(7, {known = false, name = "Flight stick"}, service.flight_profile)
	session.rate_profile = "sport"
	var flight := Main.new()
	flight.session = session
	shell.flight = flight
	shell.controllers = service
	root.add_child(shell)
	service.registry.selection_changed.connect(func(role: String, id: int) -> void:
		if role == "flight": shell._clear_controller_actions(false)
		else: shell._controller_ui_changed(id))
	shell._input(motion(9, 0.8))
	shell._input(motion(8, -0.8))
	check("first observed ON assignments require OFF", shell.restarts == 0 and session.rate_profile == "sport")
	shell._input(motion(9, 0.0))
	shell._input(motion(8, 0.0))
	var pause := Screen.new()
	check("pause screen opened", shell.screens.push("pause", pause, null, false))
	shell._input(motion(9, 0.80))
	shell._input(motion(8, -0.80))
	shell.open_controls()
	check("actual Controls opens over pause", shell.screens.is_top("controls"))
	var setup: Node = shell.screens.top()
	check("unchanged profile saves through Controls", setup._save_profile(false))
	setup.request_close()
	check("Cancel/close returns to pause", shell.screens.is_top("pause"))
	shell.screens.pop(false, false)
	pause.free()
	shell._input(motion(9, 0.81))
	shell._input(motion(8, -0.81))
	check("held positive restart axis survives Controls", shell.restarts == 0)
	check("held negative rate axis survives Save", session.rate_profile == "sport")
	pause = Screen.new()
	shell.screens.push("pause", pause, null, false)
	shell.open_controls()
	setup = shell.screens.top()
	setup.request_close() # Cancel without saving while both axes remain ON.
	shell.screens.pop(false, false)
	pause.free()
	shell._input(motion(9, 0.82))
	shell._input(motion(8, -0.82))
	check("held axes also survive Cancel without firing", shell.restarts == 0 and session.rate_profile == "sport")
	shell._input(motion(9, 0.0))
	shell._input(motion(8, 0.0))
	shell._input(motion(9, 0.8))
	shell._input(motion(8, -0.8))
	check("restart re-arms after OFF", shell.restarts == 1)
	check("real rate consumer toggles after OFF", session.rate_profile == "normal")
	shell._input(motion(9, NAN))
	shell._input(motion(8, INF))
	shell._input(motion(9, 0.81))
	shell._input(motion(8, -0.81))
	check("nonfinite samples do not erase either held latch", shell.restarts == 1 and session.rate_profile == "normal")
	# A changed binding cannot use an unrelated or nonfinite sample as OFF.
	service.flight_profile.actions.restart_flight = {"type": "button", "button": 20}
	shell._clear_controller_actions(false)
	shell._input(button(21, false))
	shell._input(button(20, true))
	check("remapped held button waits for its own release", shell.restarts == 1)
	shell._input(button(20, false))
	shell._input(button(20, true))
	check("remapped button works after release", shell.restarts == 2)
	pause = Screen.new()
	shell.screens.push("pause", pause, null, false)
	shell.open_controls()
	setup = shell.screens.top()
	setup.request_close()
	shell.screens.pop(false, false)
	pause.free()
	shell._input(button(20, true))
	check("held restart button survives Controls without firing", shell.restarts == 2)
	service.flight_profile.actions.restart_flight = {"type": "axis", "axis": 9, "sign": -1, "threshold": 0.65}
	shell._clear_controller_actions(false)
	shell._input(motion(9, NAN))
	shell._input(motion(9, -0.8, 8))
	shell._input(motion(9, -0.8))
	check("foreign/nonfinite samples do not rearm a remapped axis", shell.restarts == 2)
	shell._input(motion(9, -0.55))
	shell._input(motion(9, -0.8))
	check("axis hysteresis is not mistaken for OFF", shell.restarts == 2)
	shell._input(motion(9, 0.0))
	shell._input(motion(9, -0.8))
	check("negative axis works after OFF", shell.restarts == 3)
	service.registry.select_device("flight", 9)
	shell._input(motion(9, -0.8, 9))
	check("new flight device requires OFF", shell.restarts == 3)
	shell._input(motion(9, 0.0, 9))
	shell._input(motion(9, -0.8, 9))
	check("new flight device works after OFF", shell.restarts == 4)
	service.registry.disconnect_device(9)
	service.registry.update_devices([{id = 7, known = false, name = "Flight stick"},
		{id = 8, known = true, name = "Menu pad"}, {id = 9, known = false, name = "Other flight stick"}])
	service.registry.select_device("flight", 9)
	shell._input(motion(9, -0.8, 9))
	check("reconnected device generation requires OFF", shell.restarts == 4)
	shell._input(motion(9, 0.0, 9))
	shell._input(motion(9, -0.8, 9))
	check("reconnected device re-arms after OFF", shell.restarts == 5)
	shell._clear_controller_actions()
	shell._input(motion(9, -0.8, 9))
	check("focus-loss reset requires OFF", shell.restarts == 5)
	shell._input(motion(9, 0.0, 9))
	shell._input(motion(9, -0.8, 9))
	check("focus-loss reset re-arms after OFF", shell.restarts == 6)
	await _test_editing_keys(shell, service)
	shell.flight = null
	session.free()
	flight.free()
	shell.free()
	service.free()
	print("controller edge continuity: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)


func _test_same_frame_remap() -> void:
	var old_key := InputEventKey.new()
	old_key.physical_keycode = KEY_F6
	var new_key := InputEventKey.new()
	new_key.physical_keycode = KEY_F7
	UiInput.set_gamepad(8, {"back": {"type": "key", "physical_keycode": int(KEY_F6)}})
	check("old custom Back is installed", InputMap.action_has_event("ui_cancel", old_key))
	UiInput.suspend_generated_cancel_key()
	UiInput.set_gamepad(8, {"back": {"type": "key", "physical_keycode": int(KEY_F7)}})
	UiInput.suspend_generated_cancel_key()
	check("same-frame reconfigured Back is also suspended", not InputMap.action_has_event("ui_cancel", new_key))
	UiInput.restore_generated_cancel_key()
	check("restore keeps only the new Back mapping", InputMap.action_has_event("ui_cancel", new_key) and not InputMap.action_has_event("ui_cancel", old_key))
	UiInput.isolate_joypads()


func _key(code: Key, character := 0, control := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = character
	event.ctrl_pressed = control
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _test_editing_keys(shell: RoutingShell, service: FixtureService) -> void:
	var path := "user://controller_edge_continuity_%d.cfg" % OS.get_process_id()
	var store := Store.new(path, path + ".legacy")
	var profile := Profile.defaults()
	profile["actions"]["back"] = {"type": "key", "physical_keycode": int(KEY_BACKSPACE)}
	var saved := store.save_profile(profile)
	var loaded := Store.new(path, path + ".legacy").load_all()
	check("Backspace mapping survives actual profile storage", saved.ok and loaded.ok and loaded.profiles.size() == 1, str([saved, loaded]))
	if not saved.ok or not loaded.ok or loaded.profiles.size() != 1:
		return
	service.ui_profile = loaded.profiles[0]
	shell._controller_ui_changed(8)
	var pause := Screen.new()
	shell.screens.push("pause", pause, null, false)
	shell.open_controls()
	var setup: Node = shell.screens.top()
	for _frame in 5:
		await process_frame
	setup.select_section("profile")
	await process_frame
	await process_frame
	var editor: LineEdit = setup.profile_name_edit
	editor.text = "AB"
	editor.grab_focus()
	editor.caret_column = 2
	await process_frame
	check("Controls text field owns focus", root.gui_get_focus_owner() == editor, str(root.gui_get_focus_owner()))
	await _key(KEY_BACKSPACE)
	check("saved Backspace edits focused text instead of closing Controls", shell.screens.is_top("controls") and is_instance_valid(editor) and editor.text == "A")
	if not shell.screens.is_top("controls") or not is_instance_valid(editor):
		if shell.screens.is_top("pause"): shell.screens.pop(false, false)
		pause.free()
		return
	profile["actions"]["back"] = {"type": "key", "physical_keycode": int(KEY_X)}
	saved = store.save_profile(profile)
	loaded = Store.new(path, path + ".legacy").load_all()
	check("printable Back mapping survives actual profile storage", saved.ok and loaded.ok and loaded.profiles.size() == 1)
	if saved.ok and loaded.ok and loaded.profiles.size() == 1:
		service.ui_profile = loaded.profiles[0]
		shell._controller_ui_changed(8)
		editor.text = "a"
		editor.grab_focus()
		editor.caret_column = 1
		await _key(KEY_X, 120)
		check("saved printable Back inserts text instead of closing Controls", editor.text == "ax" and shell.screens.is_top("controls"), str([editor.text, root.gui_get_focus_owner(), shell.screens.is_top("controls")]))
		var back_event := InputEventKey.new()
		back_event.physical_keycode = KEY_X
		back_event.keycode = KEY_X
		back_event.pressed = true
		shell._exit_request_active = true
		shell._input(back_event)
		var mapped_key := InputEventKey.new()
		mapped_key.physical_keycode = KEY_X
		check("active recovery retains its native Back mapping", InputMap.action_has_event("ui_cancel", mapped_key))
		back_event.pressed = false
		shell._input(back_event)
		shell._exit_request_active = false
		editor.text = "abc def"
		editor.caret_column = editor.text.length()
		await _key(KEY_BACKSPACE, 0, true)
		check("modified editing key stays in the editor", editor.text.length() < 7 and shell.screens.is_top("controls"))
		setup.save_button.grab_focus()
		await _key(KEY_X, 120)
		check("saved Back works again outside the editor", shell.screens.is_top("pause"))
		# Capture owns its keyboard event even when that key is also Back.
		shell.open_controls()
		setup = shell.screens.top()
		for _frame in 5:
			await process_frame
		setup.select_section("buttons")
		await process_frame
		var capture_button := setup.find_child("Remap_camera_cycle", true, false) as Button
		setup._start_capture("camera_cycle", capture_button)
		await _key(KEY_X, 120)
		check("remapping captures the saved Back key without closing Controls", shell.screens.is_top("controls") and not setup._is_capture_active())
		setup.select_section("profile")
		await process_frame
		var picker: OptionButton = setup.profile_kind_picker
		picker.grab_focus()
		picker.show_popup()
		await process_frame
		await _key(KEY_X, 120)
		check("saved Back dismisses an open option popup first", shell.screens.is_top("controls") and not picker.get_popup().visible)
		profile["actions"]["back"] = {"type": "button", "button": int(JOY_BUTTON_B)}
		profile["actions"]["pause"] = {"type": "key", "physical_keycode": int(KEY_X)}
		saved = store.save_profile(profile)
		loaded = Store.new(path, path + ".legacy").load_all()
		check("printable Pause mapping saves", saved.ok and loaded.ok and loaded.profiles.size() == 1)
		if saved.ok and loaded.ok and loaded.profiles.size() == 1:
			service.ui_profile = loaded.profiles[0]
			shell._controller_ui_changed(8)
			setup.select_section("profile")
			await process_frame
			editor = setup.profile_name_edit
			editor.text = "a"
			editor.grab_focus()
			editor.caret_column = 1
			await _key(KEY_X, 120)
			check("saved printable Pause edits text without closing", shell.screens.is_top("controls") and editor.text == "ax")
			setup.select_section("buttons")
			await process_frame
			capture_button = setup.find_child("Remap_camera_cycle", true, false) as Button
			setup._start_capture("camera_cycle", capture_button)
			await _key(KEY_X, 120)
			check("remapping captures the saved Pause key without closing", shell.screens.is_top("controls") and not setup._is_capture_active())
		# Escape first exits a live LineEdit edit; the next Escape closes the screen.
		setup.select_section("profile")
		await process_frame
		editor = setup.profile_name_edit
		editor.grab_focus()
		await _key(KEY_A, 97)
		var was_editing := editor.is_editing()
		await _key(KEY_ESCAPE)
		check("Escape leaves active text editing before closing", was_editing and shell.screens.is_top("controls"))
		if shell.screens.is_top("controls"):
			await _key(KEY_ESCAPE)
			check("Escape still closes Controls after editing", shell.screens.is_top("pause"), str(root.gui_get_focus_owner()))
		if shell.screens.is_top("pause"):
			shell.open_controls()
			shell._input(button(JOY_BUTTON_B, false, 8))
			shell._input(button(JOY_BUTTON_B, true, 8))
			check("selected menu controller Back still closes Controls", shell.screens.is_top("pause"))
	if shell.screens.is_top("controls"):
		setup.request_close()
	shell.screens.pop(false, false)
	pause.free()
	for suffix in ["", ".tmp", ".rollback", ".legacy"]:
		var output: String = path + suffix
		if FileAccess.file_exists(output):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(output))
