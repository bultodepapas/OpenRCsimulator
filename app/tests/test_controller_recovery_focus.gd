extends SceneTree

const UiDriver := preload("res://tests/ui_driver.gd")
const Screen := preload("res://ui/screen.gd")
const Stack := preload("res://ui/screen_stack.gd")
const Help := preload("res://ui/help_screen.gd")

var checks := 0
var failures := 0
var ui: RefCounted


func check(label: String, condition: bool) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label)


func _initialize() -> void:
	_run.call_deferred()


func device(id: int) -> Dictionary:
	return {"id": id, "name": "Recovery pad %d" % id, "known": true, "guid": "recovery-pad-%d" % id, "serial_number": "recovery-%d" % id}


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	ui = UiDriver.new(self)
	await check_stack_fallbacks()
	var prefs := "user://recovery-focus-%d.cfg" % Time.get_ticks_usec()
	var app: Node = load("res://app_root.tscn").instantiate()
	app.user_args = PackedStringArray()
	app.preferences_path = prefs
	root.add_child(app)
	await ui.settle()
	var devices: Array = [device(15), device(16), device(17)]
	app.controllers.enumerate_devices = func() -> Array: return devices
	app.controllers.refresh()
	check("separate flight and menu controllers can be selected", app.controllers.select_devices(17, 15))
	app.start_flight()
	var session: Node = app.flight.session
	session.read_axis = func(_id: int, _axis: int) -> float: return 0.0
	session.read_button = func(_id: int, _button: int) -> bool: return false
	session.radio.confirmed_gamepad_connection = func(id: int) -> bool: return id in [15, 16, 17]
	await ui.settle()
	app.open_pause()
	app.pause_menu.restart_button.grab_focus()
	await ui.settle()
	check("queued initial Pause focus preserves a newer selection", app.pause_menu.restart_button.has_focus())
	for replacement: int in [-1, 16]:
		for hide_before_close: bool in [true, false]:
			devices.assign([device(15), device(16), device(17)])
			app.controllers.refresh()
			check("original flight controller is selected", app.controllers.select_devices(17, 15))
			devices.assign([device(15), device(16)])
			app.controllers.refresh()
			await ui.settle()
			var pause: Node = app.pause_menu
			pause.set_process(false) # deterministically exercise both production refresh orderings
			pause.refresh()
			pause.focus_controller_recovery()
			check("lost flight device exposes focused recovery on Pause", session._controller_lost and pause.controller_recovery_button.has_focus())
			await ui.joy_button(JOY_BUTTON_A)
			check("menu controller opens real Controls from recovery", app.screens.is_top("controls"))
			if not app.screens.is_top("controls"):
				await ui.close_app(app)
				quit(1)
				return
			var setup: Node = app.screens.top()
			var index: int = setup.flight_device_picker.get_item_index(replacement)
			setup.flight_device_picker.select(index)
			setup.flight_device_picker.item_selected.emit(index)
			setup.profile_saved.connect(func(_profile: Dictionary) -> void:
				session._poll_controller(false)
				if hide_before_close:
					pause.refresh())
			var frozen := var_to_bytes([session.sim.tick, session.sim.state, session.sim.continuous])
			setup.save_button.grab_focus()
			await ui.joy_button(JOY_BUTTON_A)
			check("Save recovers the flight role and retains the menu pad", app.screens.is_top("pause") and not session._controller_lost and app.controllers.registry.selected_device_id("flight") == replacement and app.controllers.registry.selected_device_id("ui") == 15)
			if not hide_before_close:
				check("late refresh starts with the visible recovery opener focused", pause.controller_recovery_button.has_focus())
				pause.refresh()
			await ui.settle()
			check("recovery hides the shortcut and focuses Resume (%s, before=%s)" % [replacement, hide_before_close], not pause.controller_recovery_button.visible and pause.continue_button.has_focus())
			check("recovery never resumes or advances flight", session.sim.paused and session.holds.has("menu") and var_to_bytes([session.sim.tick, session.sim.state, session.sim.continuous]) == frozen)
			for pressed: bool in [true, false]:
				var other_pad := InputEventJoypadButton.new()
				other_pad.device = 16
				other_pad.button_index = JOY_BUTTON_DPAD_DOWN
				other_pad.pressed = pressed
				Input.parse_input_event(other_pad)
			await ui.settle()
			check("a non-menu pad cannot move recovered focus", pause.continue_button.has_focus())
			await ui.joy_button(JOY_BUTTON_DPAD_DOWN)
			check("selected menu pad can navigate after recovery", pause.restart_button.has_focus())
			await ui.tap(KEY_UP)
			check("keyboard can navigate after recovery", pause.continue_button.has_focus())
			await ui.joy_button(JOY_BUTTON_DPAD_DOWN)
			await ui.joy_button(JOY_BUTTON_DPAD_DOWN)
			await ui.joy_button(JOY_BUTTON_A)
			check("selected pad Accept remains usable without resuming", pause._open_group == "session" and session.sim.paused)
			pause._toggle_group("")
			pause.restart_button.grab_focus()
			pause._refresh_controller_recovery()
			check("subsequent recovery refresh preserves newer focus", pause.restart_button.has_focus())
			pause.set_process(true)
	await ui.close_app(app)
	for suffix: String in ["", ".display", ".controllers", ".controllers.rollback", ".legacy_rc"]:
		if FileAccess.file_exists(prefs + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(prefs + suffix))
	print("controller recovery focus: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)


func check_stack_fallbacks() -> void:
	for mutation: String in ["valid", "hidden", "disabled", "nonfocusable", "queued", "freed"]:
		var host := Node.new()
		root.add_child(host)
		var stack := Stack.new(host)
		var lower := Screen.new()
		var opener := Button.new()
		var fallback := Button.new()
		lower.add_child(opener)
		lower.add_child(fallback)
		lower.focus_fallback = func() -> void: fallback.grab_focus()
		stack.push("lower", lower)
		opener.grab_focus()
		var upper := Screen.new()
		var editor := Button.new()
		upper.add_child(editor)
		stack.push("upper", upper, opener)
		editor.grab_focus()
		lower.ensure_focus()
		check("inactive lower surface does not steal focus (%s)" % mutation, editor.has_focus())
		match mutation:
			"hidden": opener.hide()
			"disabled": opener.disabled = true
			"nonfocusable": opener.focus_mode = Control.FOCUS_NONE
			"queued": opener.queue_free()
			"freed": opener.free()
		stack.pop()
		check("pop restores a valid opener or its fallback (%s)" % mutation, root.gui_get_focus_owner() == (opener if mutation == "valid" else fallback))
		await ui.settle()
		check("fallback remains stable after deferred deletion (%s)" % mutation, root.gui_get_focus_owner() == (opener if mutation == "valid" else fallback))
		stack.clear()
		host.free()
		await ui.settle()

	var host := Node.new()
	root.add_child(host)
	var stack := Stack.new(host)
	var lower := Screen.new()
	var fallback := Button.new()
	var newer := Button.new()
	lower.add_child(fallback)
	lower.add_child(newer)
	lower.focus_fallback = func() -> void: fallback.grab_focus()
	stack.push("lower", lower)
	newer.grab_focus()
	lower.ensure_focus()
	check("fallback preserves an existing valid selection", newer.has_focus())
	var fallback_calls := [0]
	lower.focus_fallback = func() -> void:
		fallback_calls[0] += 1
		fallback.grab_focus()
	lower.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_DISABLED
	lower.ensure_focus()
	check("exit-held recursive focus is not a usable opener", not Screen.can_focus(newer) and not Screen.can_focus(fallback))
	check("exit-held screen does not invoke its focus fallback", fallback_calls[0] == 0 and root.gui_get_focus_owner() == null)
	lower.focus_behavior_recursive = Control.FOCUS_BEHAVIOR_INHERITED
	lower.ensure_focus()
	check("released exit hold restores a usable fallback", fallback_calls[0] == 1 and fallback.has_focus())
	newer.grab_focus()
	var detached := Screen.new()
	detached.return_focus = fallback
	detached.close()
	check("closing a detached screen preserves newer valid focus", newer.has_focus())
	detached.free()
	var help := Help.new(newer)
	host.add_child(help)
	await ui.settle()
	check("standalone Help owns its Close button focus", help.close_button.has_focus())
	help.close()
	check("standalone Help returns its outgoing focus to the opener", newer.has_focus())
	help.free()
	await ui.settle()
	stack.push("upper", Screen.new(), newer)
	stack.pop(true, false)
	check("explicit no-restore pop does not invoke fallback", root.gui_get_focus_owner() == null)
	lower.ensure_focus.call_deferred()
	var upper := Screen.new()
	var editor := Button.new()
	upper.add_child(editor)
	stack.push("upper", upper, newer)
	editor.grab_focus()
	await ui.settle()
	check("queued fallback cannot steal focus from a newer surface", editor.has_focus())
	stack.clear()
	host.free()
	await ui.settle()
