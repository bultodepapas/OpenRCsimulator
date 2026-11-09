extends SceneTree
## UI-12-GP-02: actual Window ingress and synchronous GUI delivery with synthetic hardware events.
const Profile := preload("res://input/controller_profile.gd")
const Menu := preload("res://input/radio_menu.gd")
const UiInput := preload("res://ui/ui_input.gd")
const Driver := preload("res://tests/ui_driver.gd")
const Surface := preload("res://ui/screen.gd")
const DEVICE := 15
var checks := 0
var failures := 0
var app: Node
var ui: RefCounted
var prefs := "user://test_radio_menu_journey_%d.cfg" % OS.get_process_id()

class QuietApp extends "res://app_root.gd":
	func _start_update_check() -> void: pass

func check(label: String, ok: bool) -> void:
	checks += 1
	print("ok " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func _initialize() -> void: _run.call_deferred()

func axis(index: int, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = DEVICE
	event.axis = index
	event.axis_value = value
	Input.parse_input_event(event)
	await ui.settle()

func button(index: int, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = DEVICE
	event.button_index = index
	event.pressed = pressed
	Input.parse_input_event(event)
	await ui.settle()

func click(index := 10) -> void:
	await button(index, true)
	await button(index, false)

func prime() -> void:
	await axis(0, 0.0)
	await axis(1, 0.0)
	await button(10, false)
	await button(11, false)
	await button(12, false)

func move(index: int, value: float) -> void:
	await axis(index, value)
	await axis(index, 0.0)

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	root.gui_embed_subwindows = true
	ui = Driver.new(self)
	app = QuietApp.new()
	app.user_args = PackedStringArray()
	app.preferences_path = prefs
	app.window_focus_probe = func() -> bool: return true
	root.add_child(app)
	root.size = Vector2i(1920, 1080)
	await ui.settle()
	var devices := [{"id": DEVICE, "name": "Synthetic radio", "kind": "radio", "known": false,
		"guid": "journey-radio", "vendor_id": 1209, "product_id": 500, "serial_number": "A"}]
	app.controllers.enumerate_devices = func() -> Array: return devices
	app.controllers.refresh()
	var profile := Profile.defaults("radio", "radio_custom")
	profile.association = {"guid": "journey-radio", "vendor_id": 1209, "product_id": 500, "serial_number": "A"}
	profile.actions["accept"] = {"type": "button", "button": 10}
	profile.actions["back"] = {"type": "button", "button": 11}
	profile.actions["pause"] = {"type": "button", "button": 12}
	profile = Menu.verified_profile(profile)
	var saved: Dictionary = app.controllers.save_settings_from_setup(profile, DEVICE, DEVICE)
	check("verified radio commits both selected roles", saved.ok and UiInput.selected_radio_id() == DEVICE)
	check("radio has no raw native joypad UI mappings", UiInput.joypad_ui_events().is_empty())
	await ui.settle()
	check("startup reports the required fresh observations", is_instance_valid(app._radio_menu_hint) and app._radio_menu_hint.visible)
	await prime()
	check("real Window ingress arms semantic menu input", app._radio_menu_input.ready_for_commands())
	check("ordinary root is not reported as a popup", app._radio_menu_popup() == null)
	app.home.help_button.grab_focus()
	await click()
	check("radio Accept opens Home Help", app.screens.is_top("help"))
	await button(11, true)
	check("one radio Back closes Help", app.screens.is_top("home"))
	await button(11, true)
	check("held Back does not close or activate Home", app.screens.is_top("home"))
	await button(11, false)

	app.home.controls_button.grab_focus()
	await click()
	check("radio Accept opens Controls", app.screens.is_top("controls"))
	var setup: Node = app.screens.top()
	var picker: OptionButton = setup.flight_device_picker
	picker.grab_focus()
	await click()
	check("radio Accept opens real embedded OptionButton", picker.get_popup().visible)
	check("nonexclusive PopupMenu enters the context identity", app._radio_menu_popup() == picker.get_popup())
	var old_index: int = picker.get_popup().get_focused_item()
	await move(1, -1.0) # radio pitch is inverted: negative physical = menu Down
	check("raw radio movement reaches router while popup owns input", picker.get_popup().get_focused_item() != old_index)
	await click(11)
	check("Back dismisses popup without closing Controls", not picker.get_popup().visible and app.screens.is_top("controls"))
	check("closed popup leaves context identity", app._radio_menu_popup() == null)
	picker.grab_focus()
	await click()
	await button(12, true)
	check("guarded Pause dismisses an embedded popup once", not picker.get_popup().visible and app.screens.is_top("controls"))
	await button(12, true)
	check("held popup Pause cannot close its parent", app.screens.is_top("controls"))
	await button(12, false)

	setup.select_section("profile")
	await ui.settle()
	setup.profile_name_edit.grab_focus()
	setup.profile_name_edit.edit()
	await click(11)
	check("first Back exits text editing without closing Controls", app.screens.is_top("controls") and not setup.profile_name_edit.is_editing())
	await click(11)
	check("next Back closes Controls", app.screens.is_top("home"))

	await _numeric_and_batch_boundary()
	await _focus_and_reconnect(devices)
	await _flight_journey()
	await ui.close_app(app)
	for suffix: String in ["", ".display", ".controllers", ".controllers.rollback", ".controllers.tmp", ".renderer"]:
		var target := prefs + suffix
		if FileAccess.file_exists(target): DirAccess.remove_absolute(ProjectSettings.globalize_path(target))
	print("Radio menu journey: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _numeric_and_batch_boundary() -> void:
	var layer := CanvasLayer.new()
	var surface: Control = Surface.mount(layer)
	var column := VBoxContainer.new()
	column.position = Vector2(500, 200)
	column.size = Vector2(300, 300)
	surface.add_child(column)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 10
	spin.step = 0.5
	spin.value = 3
	column.add_child(spin)
	var editor := LineEdit.new()
	column.add_child(editor)
	var next := Button.new()
	next.text = "Next"
	column.add_child(next)
	surface.close_requested.connect(func() -> void:
		if app.screens.is_top("numeric_fixture"): app.screens.pop())
	app.screens.push("numeric_fixture", layer)
	await ui.settle()
	spin.get_line_edit().grab_focus()
	spin.get_line_edit().unedit()
	await move(0, 1.0)
	check("radio Right adjusts focused SpinBox through its step", spin.value == 3.5)
	await move(1, -1.0)
	check("radio navigation enters plain text field without auto-edit", editor.has_focus() and not editor.is_editing())
	await click(11)
	check("Back closes numeric surface once", app.screens.is_top("home"))
	# A native cancel hides deferred. A queued Accept in this same frame must
	# never activate the parent Controls button after the popup closes.
	app.open_controls()
	await ui.settle()
	var setup: Node = app.screens.top()
	setup.ui_device_picker.grab_focus()
	await click()
	var popup: PopupMenu = setup.ui_device_picker.get_popup()
	check("batch guard fixture popup opens", popup.visible)
	for data: Array in [[11, true], [10, true], [10, false]]:
		var event := InputEventJoypadButton.new()
		event.device = DEVICE
		event.button_index = data[0]
		event.pressed = data[1]
		Input.parse_input_event(event)
	await ui.settle()
	check("same-frame Back and Accept stay inside original popup context", app.screens.is_top("controls") and not popup.visible)
	await button(11, false)
	await click(11)

func _focus_and_reconnect(devices: Array) -> void:
	var focused := [true]
	app.window_focus_probe = func() -> bool: return focused[0]
	focused[0] = false
	await ui.settle()
	focused[0] = true
	await ui.settle()
	app.home.help_button.grab_focus()
	await click()
	check("focus recovery cannot infer center from polled zeros", app.screens.is_top("home"))
	await prime()
	await click()
	check("fresh observations recover after focus loss", app.screens.is_top("help"))
	await click(11)
	devices.clear()
	app.controllers.refresh()
	await ui.settle()
	check("disconnect removes radio menu ownership", UiInput.selected_radio_id() == -1 and app._radio_menu_input == null)
	devices.append({"id": DEVICE, "name": "Synthetic radio", "kind": "radio", "known": false,
		"guid": "journey-radio", "vendor_id": 1209, "product_id": 500, "serial_number": "A"})
	app.controllers.refresh()
	await ui.settle()
	# Explicitly reselect after loss; saved software proof does not restore live samples.
	app.controllers.select_devices(DEVICE, DEVICE)
	await ui.settle()
	check("reconnected router requires new center evidence", app._radio_menu_input != null and not app._radio_menu_input.sticks_centered())
	await prime()
	check("same handle with new generation recovers deliberately", app._radio_menu_input.ready_for_commands())
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await prime()
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	check("focus round trip discards background center and release evidence", not app._radio_menu_input.sticks_centered())
	await prime()

func _flight_journey() -> void:
	app.set_start_choice("airborne")
	app.home.fly_button.grab_focus()
	await click()
	check("radio Accept launches the real flight scene", app.flight != null and app.home == null)
	var session: Node = app.flight.session
	session.physics_enabled = false
	var axes := PackedFloat64Array([0, 0, -1, 0, 0, 0, 0, 0, 0, 0])
	session.read_axis = func(_id: int, index: int) -> float: return axes[index]
	session.read_button = func(_id: int, _index: int) -> bool: return false
	await axis(2, -1.0)
	await axis(3, 0.0)
	await prime()
	for i in 80: session._physics_process(1.0 / 240.0)
	check("calibrated fixture arms while Pause keeps the session held", session.radio.armed and session.sim.paused)
	if app.pause_menu != null:
		app.pause_menu.continue_button.grab_focus()
		await axis(0, 0.9)
		await click()
		check("menu roll input cannot carry into flight on Resume", app.screens.is_top("pause") and session.sim.paused)
		await axis(0, 0.0)
		app.pause_menu.continue_button.grab_focus()
		await click()
	check("radio Accept resumes after readiness", app.screens.top() == null and not session.sim.paused)
	await click(12)
	check("physical radio Pause opens Pause from flight", app.screens.is_top("pause"))
	app.pause_menu.session_options_button.grab_focus()
	await click()
	check("radio Accept opens Session options", app.pause_menu._open_group == "session")
	await click(11)
	check("one radio Back collapses Session options without resuming", app.screens.is_top("pause") and app.pause_menu._open_group.is_empty())
	app.pause_menu.settings_button.grab_focus()
	await click()
	check("radio Accept opens Settings from Pause", app.screens.is_top("settings"))
	await click(11)
	check("radio Back returns Settings to Pause", app.screens.is_top("pause"))
	await click(11)
	check("next deliberate Back resumes flight", app.screens.top() == null and not session.sim.paused)
	# Show a bounded software assessment through the production accident UI;
	# this verifies menu routing, not a simulated impact or damage model.
	app.flight._accident_report.show_assessment({"outcome": "repairable", "coverage_complete": false}, true)
	await ui.settle()
	check("production accident card enters radio menu context", app.flight.accident_menu_active())
	await click(11)
	check("radio Back minimizes the accident card", not app.flight.accident_menu_active())
	app.flight._accident_report.show_assessment({"outcome": "repairable", "coverage_complete": false}, true)
	await ui.settle()
	await click(12)
	check("radio Pause opens Pause over the accident card", app.screens.is_top("pause"))
	await axis(0, 0.9)
	app.restart_flight()
	await ui.settle()
	check("restart preserves Pause while the menu roll input is displaced", app.screens.is_top("pause") and session.sim.paused)
	await axis(0, 0.0)
	app.end_flight()
	await ui.settle()
	check("ending flight restores Home with verified radio ownership", app.screens.is_top("home") and UiInput.selected_radio_id() == DEVICE)
