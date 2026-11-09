extends SceneTree
## Native GUI delivery boundaries, without starting the simulator or controller service.

const DEVICE := 15
var checks := 0
var failures := 0


class QuietApp extends "res://app_root.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass


func _initialize() -> void:
	_run.call_deferred()


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func radio(name: String, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.device = DEVICE
	event.action = name
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	return event


func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	if pressed and code >= KEY_SPACE and code <= KEY_ASCIITILDE: event.unicode = code
	event.pressed = pressed
	root.push_input(event)


func global_key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	root.gui_embed_subwindows = true
	var app := QuietApp.new()
	app.window_focus_probe = func() -> bool: return true
	root.add_child(app)
	var surface := Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(surface)
	var column := VBoxContainer.new()
	column.position = Vector2(100, 100)
	column.size = Vector2(360, 300)
	surface.add_child(column)
	var a := Button.new()
	a.text = "A"
	column.add_child(a)
	var b := Button.new()
	b.text = "B"
	column.add_child(b)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 10
	spin.step = 0.5
	spin.value = 3.5
	column.add_child(spin)
	await process_frame
	await process_frame
	var calls := {"a": 0, "b": 0}
	a.pressed.connect(func() -> void: calls.a += 1)
	b.pressed.connect(func() -> void: calls.b += 1)
	check("fixture has real buttons and embedded viewport", root.gui_embed_subwindows and a.is_inside_tree() and b.is_inside_tree())

	# A cleanup release must not complete B's unrelated, still-held keyboard press.
	a.grab_focus()
	app._deliver_radio_menu_action(radio("ui_accept", true))
	check("radio press on A waits for release", a.has_focus() and calls.a == 0 and calls.b == 0)
	b.grab_focus()
	key(KEY_ENTER, true)
	check("keyboard press on B waits for release", b.has_focus() and calls.b == 0)
	app._deliver_radio_menu_action(radio("ui_accept", false))
	check("cleanup release for A cannot activate B", calls.a == 0 and calls.b == 0)
	key(KEY_ENTER, false)
	check("B's own keyboard release still activates B exactly once", calls.a == 0 and calls.b == 1, str(calls))

	# Even with unchanged focus, a new surface/context cannot inherit a held press.
	a.grab_focus()
	app._deliver_radio_menu_action(radio("ui_accept", true))
	app._radio_menu_epoch += 1
	app._deliver_radio_menu_action(radio("ui_accept", false))
	check("context change cancels a held Accept on the same A", calls.a == 0 and a.has_focus(), str(calls))
	key(KEY_ENTER, true)
	key(KEY_ENTER, false)
	check("focus and keyboard remain usable after cancellation", calls.a == 1 and calls.b == 1, str(calls))
	app._deliver_radio_menu_action(radio("ui_accept", true))
	var reset_release := radio("ui_accept", false)
	reset_release.set_meta("openrc_radio_reset", true)
	app._deliver_radio_menu_action(reset_release)
	check("explicit cleanup release cancels a press in the same context", calls.a == 1 and a.has_focus(), str(calls))

	# Semantic navigation must respect the native editable property.
	spin.editable = false
	spin.get_line_edit().grab_focus()
	check("noneditable SpinBox line edit has actual GUI focus", spin.get_line_edit().has_focus())
	var before := spin.value
	app._deliver_radio_menu_action(radio("ui_right", true))
	app._deliver_radio_menu_action(radio("ui_right", false))
	check("Right cannot change a noneditable SpinBox", spin.value == before, str([before, spin.value]))
	spin.editable = true
	spin.get_line_edit().unedit()
	app._deliver_radio_menu_action(radio("ui_right", true))
	app._deliver_radio_menu_action(radio("ui_right", false))
	check("Right still adjusts an editable SpinBox by one step", spin.value == before + spin.step, str(spin.value))
	spin.value = 3.5

	# Compare the same unsaved edit through native Escape and guarded radio Back.
	var editor := spin.get_line_edit()
	editor.grab_focus()
	editor.edit()
	editor.select_all()
	for code: Key in [KEY_8, KEY_PERIOD, KEY_5]:
		key(code, true)
		key(code, false)
	check("native Escape fixture starts with uncommitted typed edit", editor.is_editing() and spin.value == 3.5 and editor.text == "8.5", editor.text)
	global_key(KEY_ESCAPE, true)
	check("native Escape is held in the global input state", Input.is_action_pressed("ui_cancel"))
	await process_frame
	await process_frame
	var native := {"text": editor.text, "editing": editor.is_editing(), "value": spin.value}
	check("native Escape cancels editing without changing value", not native.editing and native.value == 3.5 and native.text == "3.5", str(native))
	global_key(KEY_ESCAPE, false)
	check("native Escape is released from global input state", not Input.is_action_pressed("ui_cancel"))
	b.grab_focus()
	await process_frame
	check("native Escape leaves no unsaved value on focus loss", editor.text == "3.5" and spin.value == 3.5)
	editor.grab_focus()
	editor.edit()
	editor.select_all()
	for code: Key in [KEY_8, KEY_PERIOD, KEY_5]:
		key(code, true)
		key(code, false)
	check("radio Back fixture starts with real typed input", editor.is_editing() and spin.value == 3.5 and editor.text == "8.5", editor.text)
	app._deliver_radio_menu_action(radio("ui_cancel", true))
	app._deliver_radio_menu_action(radio("ui_cancel", false))
	await process_frame
	await process_frame
	var via_radio := {"text": editor.text, "editing": editor.is_editing(), "value": spin.value}
	check("radio Back matches native Escape for an unsaved SpinBox edit", via_radio == native, str({"native": native, "radio": via_radio}))
	b.grab_focus()
	await process_frame
	check("radio Back leaves no unsaved value on focus loss", editor.text == "3.5" and spin.value == 3.5)

	surface.free()
	app.free()
	await process_frame
	print("Radio menu delivery: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
