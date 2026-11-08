# UI-32-R8: directional names for the vector keycaps, live language and layout updates.
# Properties and node structure do not replace a target screen-reader listening test.
extends SceneTree

const KeyCap := preload("res://ui/key_cap.gd")
const KeyLabels := preload("res://ui/key_labels.gd")
const HelpScreen := preload("res://ui/help_screen.gd")
const Reference := preload("res://ui/controls_reference.gd")
const UiDriver := preload("res://tests/ui_driver.gd")

var checks := 0
var failures := 0
var ui: RefCounted


# AccessibilityServer has no value getter. Record the calls at the server boundary;
# native accessibility-tree inspection still checks that the platform exposes them.
class AccessibilityRecorder extends RefCounted:
	var role := -1
	var value := ""
	var role_calls := 0
	var value_calls := 0

	func update_set_role(_element: RID, new_role: int) -> void:
		role_calls += 1
		role = new_role

	func update_set_value(_element: RID, new_value: String) -> void:
		value_calls += 1
		value = new_value


func _check(ok: bool, message: String, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", message, " ", detail)


func _initialize() -> void:
	ui = UiDriver.new(self)
	_run.call_deferred()


func _check_help_row(help: CanvasLayer, action: String, expected: Array[String]) -> void:
	var matched := false
	for table: GridContainer in help._key_tables:
		for i: int in range(1, table.get_child_count(), 2):
			var label: Label = table.get_child(i)
			if label.text != action:
				continue
			var caps: HBoxContainer = table.get_child(i - 1)
			if caps.get_child_count() == 2:
				var first: PanelContainer = caps.get_child(0)
				var second: PanelContainer = caps.get_child(1)
				matched = first.accessibility_name == expected[0] and second.accessibility_name == expected[1] \
					and first.get_child(0) is KeyCap.Arrow and second.get_child(0) is KeyCap.Arrow \
					and label.atr(label.text) == TranslationServer.translate(action)
	_check(matched, "%s: action adjacent to its named arrows" % action)


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	var keys: Array[Key] = [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]
	var directions: Array[String] = ["left", "right", "up", "down"]
	var names := {
		"en": ["Left arrow", "Right arrow", "Up arrow", "Down arrow"],
		"es": ["Flecha izquierda", "Flecha derecha", "Flecha arriba", "Flecha abajo"],
		"ja": ["左矢印", "右矢印", "上矢印", "下矢印"],
		"zh_Hans": ["左方向键", "右方向键", "上方向键", "下方向键"],
	}
	var caps: Array[PanelContainer] = []
	for i: int in keys.size():
		var cap: PanelContainer = KeyCap.for_key(keys[i], func(_key: Key) -> Key: return KEY_RIGHT)
		root.add_child(cap)
		caps.append(cap)
		var arrow: Control = cap.get_child(0)
		_check(arrow is KeyCap.Arrow and arrow.direction == directions[i] and arrow.keycap_decoration,
			"physical %s keeps its vector and decorative child despite mapper" % directions[i])
		_check(cap.focus_mode == Control.FOCUS_NONE and arrow.focus_mode == Control.FOCUS_NONE,
			"%s keycap adds no focus stop" % directions[i])
	var standalone := KeyCap.Arrow.new()
	_check(not standalone.keycap_decoration, "standalone button glyphs are not marked as keycap decoration")
	standalone.free()

	# The same instantiated nodes must change language; the visual arrow objects stay in place.
	for locale: String in ["en", "es", "ja", "zh_Hans", "en"]:
		TranslationServer.set_locale(locale)
		await ui.settle()
		for i: int in keys.size():
			_check(caps[i].accessibility_name == names[locale][i], "%s %s translated direction" % [locale, directions[i]],
				str(caps[i].accessibility_name))
			var recorder := AccessibilityRecorder.new()
			caps[i].call("_update_arrow_accessibility", RID(), recorder)
			_check(recorder.role_calls == 1 and recorder.role == AccessibilityServer.ROLE_STATIC_TEXT
				and recorder.value_calls == 1 and recorder.value == names[locale][i],
				"%s %s static text publishes its translated value" % [locale, directions[i]], recorder.value)
			_check(caps[i].get_child(0).direction == directions[i], "%s %s retains drawing" % [locale, directions[i]])
	for cap: PanelContainer in caps:
		cap.free()

	# The mapper is per instance; app focus restores a live Help legend after a layout change.
	var layout := {KEY_A: KEY_Q}
	var mapper := func(key: Key) -> Key: return layout.get(key, key)
	var letter: PanelContainer = KeyCap.for_key(KEY_A, mapper)
	root.add_child(letter)
	_check(letter.get_child(0).text == "Q", "physical A initially follows injected layout")
	layout[KEY_A] = KEY_Z
	letter.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(letter.get_child(0).text == "Z", "existing keycap updates when the application regains focus")
	var fixed: PanelContainer = KeyCap.make("A")
	root.add_child(fixed)
	fixed.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(fixed.get_child(0).text == "A", "literal keycaps remain literal")
	var enter: PanelContainer = KeyCap.for_key(KEY_ENTER)
	root.add_child(enter)
	TranslationServer.set_locale("es")
	await ui.settle()
	_check(enter.get_child(0).text == "Intro", "existing named non-arrow key updates on locale change", enter.get_child(0).text)
	letter.free()
	fixed.free()
	enter.free()

	for vehicle: String in [Reference.AIRPLANE, Reference.ROTORCRAFT]:
		TranslationServer.set_locale("en")
		var help: CanvasLayer = HelpScreen.new(null, vehicle)
		root.add_child(help)
		await ui.settle()
		_check(help.close_button.has_focus(), "%s Help retains Close focus" % vehicle)
		for locale: String in ["en", "es", "ja"]:
			TranslationServer.set_locale(locale)
			await ui.settle()
			var horizontal: Array[String] = [names[locale][0], names[locale][1]]
			var vertical: Array[String] = [names[locale][2], names[locale][3]]
			_check_help_row(help, "Cyclic roll" if vehicle == Reference.ROTORCRAFT else "Roll", horizontal)
			_check_help_row(help, "Cyclic pitch" if vehicle == Reference.ROTORCRAFT else "Pitch", vertical)
		help._help_scroll.grab_focus()
		await ui.tap(KEY_END)
		_check(help._help_scroll.has_focus() and help._help_scroll.get_v_scroll_bar().value > 0.0,
			"%s keyboard can scroll Help" % vehicle)
		await ui.tap(KEY_HOME)
		_check(help._help_scroll.has_focus() and help._help_scroll.get_v_scroll_bar().value == 0.0,
			"%s keyboard returns to start" % vehicle)
		help.free()
		await process_frame

	TranslationServer.set_locale("en")
	print("Keycap semantics: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
