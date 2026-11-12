# UI-15-UX-03/04/08: DevicePicture, DeviceCard, ResponseCurve and BindingChip — control ids and rects per device,
# highlight and live-press state, keyboard flight keys, Mode 1/2 throttle placement, card accessible text, the curve
# sampled through ControllerProfile (same function, not a copy), chip labels and redraw-on-change discipline.
# Run: godot --headless --path . --audio-driver Dummy --script res://tests/test_controls_components.gd
extends SceneTree

const UiTheme := preload("res://ui/ui_theme.gd")
const DevicePicture := preload("res://ui/controls/device_picture.gd")
const DeviceCard := preload("res://ui/controls/device_card.gd")
const ResponseCurve := preload("res://ui/controls/response_curve.gd")
const BindingChip := preload("res://ui/controls/binding_chip.gd")
const ControllerProfile := preload("res://input/controller_profile.gd")
const ControlsReference := preload("res://ui/controls_reference.gd")

var _failures := 0
var _count := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_count += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


## Fixed QWERTY names: headless has no keyboard layout (key_labels.gd).
static func _qwerty(physical: Key) -> Key:
	return physical


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var host := Control.new()
	host.theme = UiTheme.build()
	host.size = Vector2(1920, 1080)
	root.add_child(host)
	await _picture_tests(host)
	_card_tests(host)
	_curve_tests(host)
	_chip_tests(host)
	host.queue_free()
	await process_frame
	print("controls components: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures > 0 else 0)


func _picture_tests(host: Control) -> void:
	var picture := DevicePicture.new()
	picture.key_mapper = _qwerty
	host.add_child(picture)
	picture.size = Vector2(620, 380)
	_check("picture never takes focus", picture.focus_mode == Control.FOCUS_NONE)
	var gamepad_ids := ["button:%d" % JOY_BUTTON_A, "button:%d" % JOY_BUTTON_B, "button:%d" % JOY_BUTTON_X,
		"button:%d" % JOY_BUTTON_Y, "button:%d" % JOY_BUTTON_BACK, "button:%d" % JOY_BUTTON_START,
		"button:%d" % JOY_BUTTON_LEFT_SHOULDER, "button:%d" % JOY_BUTTON_RIGHT_SHOULDER,
		"button:%d" % JOY_BUTTON_LEFT_STICK, "button:%d" % JOY_BUTTON_RIGHT_STICK,
		"button:%d" % JOY_BUTTON_DPAD_UP, "button:%d" % JOY_BUTTON_DPAD_DOWN, "button:%d" % JOY_BUTTON_DPAD_LEFT,
		"button:%d" % JOY_BUTTON_DPAD_RIGHT, "axis:0", "axis:1", "axis:2", "axis:3", "axis:4", "axis:5"]
	for family in ["xbox", "playstation", "nintendo", "generic"]:
		picture.set_device("gamepad", family)
		_check("%s: device kind/family" % family, picture.device_kind() == "gamepad" and picture.device_family() == family)
		var missing := []
		var outside := []
		for id: String in gamepad_ids:
			var rect := picture.control_rect(id)
			if rect.size == Vector2.ZERO:
				missing.append(id)
			elif not Rect2(Vector2(-1, -1), picture.size + Vector2(2, 2)).encloses(rect):
				outside.append(id)
		_check("%s: every JoyButton/JoyAxis control has a rect" % family, missing.is_empty(), str(missing))
		_check("%s: every rect lies inside the picture" % family, outside.is_empty(), str(outside))
		var first := picture.control_rect("button:%d" % JOY_BUTTON_A)
		picture.set_device("gamepad", family)
		picture.set_axes(PackedFloat64Array([0.7, -0.4, 0.2, 0.1, 1.0, 0.0]))
		picture.set_pressed_buttons([JOY_BUTTON_A])
		_check("%s: rects stay put with live input and repeated set_device" % family,
			picture.control_rect("button:%d" % JOY_BUTTON_A) == first)
		_check("%s: a stick's X and Y share one rect" % family,
			picture.control_rect("axis:0") == picture.control_rect("axis:1")
			and picture.control_rect("axis:2") == picture.control_rect("axis:3"))
		var faces := [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]
		var overlap := false
		for i in faces.size():
			for j in range(i + 1, faces.size()):
				overlap = overlap or picture.control_rect("button:%d" % faces[i]).intersects(picture.control_rect("button:%d" % faces[j]))
		_check("%s: face buttons do not overlap" % family, not overlap)
		_check("%s: control under a face button's centre is that button" % family,
			picture.control_at(picture.control_rect("button:%d" % JOY_BUTTON_B).get_center()) == "button:%d" % JOY_BUTTON_B)
		picture.set_pressed_buttons([])
	picture.set_device("gamepad", "playstation")
	_check("PlayStation places the left stick below the D-pad (symmetric sticks)",
		picture.control_rect("axis:0").get_center().y > picture.control_rect("button:%d" % JOY_BUTTON_DPAD_UP).get_center().y)
	picture.set_device("gamepad", "xbox")
	_check("Xbox places the left stick above the D-pad (offset sticks)",
		picture.control_rect("axis:0").get_center().y < picture.control_rect("button:%d" % JOY_BUTTON_DPAD_UP).get_center().y)
	picture.set_device("gamepad", "auto")
	_check("an unknown family draws the generic layout", picture.device_family() == "generic")

	# Rect scaling: doubling the area doubles the rect (vector layout, 1080p → 4K).
	picture.set_device("gamepad", "xbox")
	var small_rect := picture.control_rect("button:%d" % JOY_BUTTON_Y)
	picture.size = Vector2(1240, 760)
	var big_rect := picture.control_rect("button:%d" % JOY_BUTTON_Y)
	_check("rects scale with the picture", big_rect.size.is_equal_approx(small_rect.size * 2.0)
		and is_equal_approx(picture.picture_scale(), 2.0), "%s %s" % [small_rect, big_rect])
	picture.size = Vector2(620, 380)

	# Highlight and leader anchors.
	picture.highlight("button:%d" % JOY_BUTTON_Y)
	_check("highlight records the control", picture.highlighted_id == "button:%d" % JOY_BUTTON_Y)
	var before := picture.redraw_requests
	picture.highlight("button:%d" % JOY_BUTTON_Y)
	_check("re-highlighting the same control does not redraw", picture.redraw_requests == before)
	picture.highlight("button:999")
	_check("an unknown id clears the highlight", picture.highlighted_id == "")
	var y_rect := picture.control_rect("button:%d" % JOY_BUTTON_Y)
	var anchor := picture.leader_anchor("button:%d" % JOY_BUTTON_Y, Vector2(picture.size.x + 50.0, y_rect.get_center().y))
	_check("leader anchor toward a chip on the right is the rect's right edge",
		anchor.is_equal_approx(Vector2(y_rect.end.x, y_rect.get_center().y)), str(anchor))
	_check("right-hand controls lead to the right, left-hand controls to the left",
		picture.leader_side("button:%d" % JOY_BUTTON_Y) == SIDE_RIGHT and picture.leader_side("axis:0") == SIDE_LEFT)
	_check("unknown id has no anchor", not picture.leader_anchor("axis:42").is_finite())

	# Hover reports the control under the pointer once per change.
	var hovered: Array[String] = []
	picture.control_hovered.connect(func(id: String) -> void: hovered.append(id))
	var motion := InputEventMouseMotion.new()
	motion.position = picture.control_rect("button:%d" % JOY_BUTTON_A).get_center()
	picture._gui_input(motion)
	picture._gui_input(motion)
	motion.position = Vector2(2, 2)
	picture._gui_input(motion)
	_check("control_hovered fires on enter and leave only", hovered == ["button:%d" % JOY_BUTTON_A, ""], str(hovered))

	# Redraw only on change.
	picture.set_axes(PackedFloat64Array([0.3, 0.3, 0.0, 0.0, 0.0, 0.0]))
	before = picture.redraw_requests
	picture.set_axes(PackedFloat64Array([0.3, 0.3, 0.0, 0.0, 0.0, 0.0]))
	picture.set_axes(PackedFloat64Array([0.301, 0.3, 0.0, 0.0, 0.0, 0.0]))
	picture.set_pressed_buttons([])
	_check("unchanged or sub-epsilon samples do not redraw", picture.redraw_requests == before)
	picture.set_pressed_buttons([JOY_BUTTON_LEFT_SHOULDER])
	_check("a new press redraws once and is reported", picture.redraw_requests == before + 1
		and picture.is_button_pressed(JOY_BUTTON_LEFT_SHOULDER) and not picture.is_button_pressed(JOY_BUTTON_A))

	# Radio: Mode 1/2 throttle placement and switch lamps.
	picture.set_device("radio")
	picture.set_radio_channels({"roll": 0, "pitch": 1, "throttle": 2, "yaw": 3})
	picture.set_radio_controls([{"button": 4, "label": "Sa"}, {"axis": 6, "label": "S1"}])
	picture.set_stick_mode(2)
	await process_frame
	var left_gimbal: Control = picture.get_node_or_null("LeftGimbal")
	var right_gimbal: Control = picture.get_node_or_null("RightGimbal")
	_check("radio uses two StickGimbalViews", left_gimbal != null and right_gimbal != null)
	_check("Mode 2: throttle on the left stick", picture.throttle_side() == "left"
		and picture.control_rect("axis:2").get_center().x < picture.size.x * 0.5
		and picture.control_rect("axis:2") == picture.control_rect("axis:3")
		and left_gimbal != null and bool(left_gimbal.one_ended_y) and not bool(right_gimbal.one_ended_y))
	picture.set_stick_mode(1)
	await process_frame
	left_gimbal = picture.get_node_or_null("LeftGimbal")
	right_gimbal = picture.get_node_or_null("RightGimbal")
	_check("Mode 1: throttle on the right stick, pitch on the left", picture.throttle_side() == "right"
		and picture.control_rect("axis:2").get_center().x > picture.size.x * 0.5
		and picture.control_rect("axis:1").get_center().x < picture.size.x * 0.5
		and right_gimbal != null and bool(right_gimbal.one_ended_y) and not bool(left_gimbal.one_ended_y))
	_check("gimbal child sits on its control rect", right_gimbal != null
		and Rect2(right_gimbal.position, right_gimbal.size).is_equal_approx(picture.control_rect("axis:2")))
	_check("radio switch lamp and pot have rects", picture.has_control("button:4") and picture.has_control("axis:6"))
	picture.set_axes(PackedFloat64Array([0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
	_check("radio roll value reaches the right gimbal's X", right_gimbal != null
		and is_equal_approx(right_gimbal.stick().x, 0.5), str(right_gimbal.stick() if right_gimbal else null))
	picture.highlight("button:4")
	_check("radio lamp can be highlighted", picture.highlighted_id == "button:4")
	picture.set_stick_mode(2)
	picture.set_device("joystick")
	_check("a raw joystick is drawn as the generic transmitter", picture.device_kind() == "radio")

	# Keyboard: flight keys, pressed keys, highlight.
	picture.set_device("keyboard")
	picture.set_vehicle_type(ControlsReference.AIRPLANE)
	await process_frame
	var missing_keys := []
	for row: Array in ControlsReference.flight_table():
		for key: Variant in row[0]:
			if not picture.has_control("key:%d" % int(key)) or picture.cap_state(int(key)) != "flight":
				missing_keys.append(key)
	_check("every airplane flight key is a lit cap", missing_keys.is_empty(), str(missing_keys))
	var shortcut_missing := []
	for row: Array in ControlsReference.shortcut_table():
		for key: Variant in row[0]:
			if not picture.has_control("key:%d" % int(key)) and not int(key) in [KEY_ENTER, KEY_KP_ENTER, KEY_F2]:
				shortcut_missing.append(key)
	_check("shortcut keys are on the map (Enter excepted)", picture.has_control("key:%d" % KEY_F2)
		and shortcut_missing.is_empty(), str(shortcut_missing))
	_check("an unused key is dimmed", picture.cap_state(KEY_Q) == "unused")
	picture.set_pressed_keys([KEY_W])
	_check("a held key lights its cap", picture.cap_state(KEY_W) == "pressed" and picture.is_key_pressed(KEY_W))
	before = picture.redraw_requests
	picture.set_pressed_keys([KEY_W])
	_check("same held keys do not restyle or redraw", picture.redraw_requests == before)
	picture.set_pressed_keys([])
	_check("releasing restores the flight state", picture.cap_state(KEY_W) == "flight")
	picture.highlight("key:%d" % KEY_F)
	_check("keyboard highlight", picture.cap_state(KEY_F) == "highlight")
	var w_cap: Control = picture.get_node_or_null("Key%d" % KEY_W)
	_check("keyboard caps are KeyCaps named in the layout", w_cap != null and w_cap.get_child(0) is Label
		and (w_cap.get_child(0) as Label).text == "W")
	_check("keyboard cap sits on its rect", w_cap != null and Rect2(w_cap.position, w_cap.size).is_equal_approx(picture.control_rect("key:%d" % KEY_W)),
		"%s %s %s" % [Rect2(w_cap.position, w_cap.size) if w_cap else null, picture.control_rect("key:%d" % KEY_W),
		w_cap.get_combined_minimum_size() if w_cap else null])
	picture.set_vehicle_type(ControlsReference.ROTORCRAFT)
	_check("rotorcraft marks its own flight keys", picture.cap_state(KEY_W) == "flight" and picture.cap_state(KEY_B) == "normal")
	picture.queue_free()


func _card_tests(host: Control) -> void:
	var card := DeviceCard.new()
	card.display_name = "Xbox Wireless Controller"
	card.kind = "gamepad"
	card.family = "xbox"
	card.set_statuses(["menus", "connected", "bogus", "needs_setup"])
	host.add_child(card)
	card.size = card.get_combined_minimum_size()
	_check("card is focusable and toggles", card.focus_mode == Control.FOCUS_ALL and card.toggle_mode)
	_check("statuses keep the fixed display order and drop unknown ids",
		card.statuses() == PackedStringArray(["connected", "needs_setup", "menus"]), str(card.statuses()))
	_check("kind and chip words", card.kind_text() == "Gamepad"
		and card.status_texts() == PackedStringArray(["Connected", "Needs setup", "Menus"]))
	_check("accessible name is name, kind and status",
		card.accessibility_name == "Xbox Wireless Controller, Gamepad, Connected, Needs setup, Menus", card.accessibility_name)
	_check("tooltip keeps the full name", card.tooltip_text == "Xbox Wireless Controller")
	card.set_selected(true)
	_check("selected state", card.is_selected() and card.accessibility_description.contains("selected"))
	card.display_name = "A very long transmitter name reported by the USB joystick descriptor of this radio"
	card.size = Vector2(300, card.get_combined_minimum_size().y)
	_check("a long name is ellipsized but stays whole in the tooltip", card.name_is_truncated()
		and card.tooltip_text.ends_with("of this radio"))
	card.kind = "radio"
	card.set_statuses(["calibrated", "flight"])
	_check("radio card text", card.accessibility_name.ends_with(", Radio, Calibrated, Flight"), card.accessibility_name)
	card.kind = "keyboard"
	_check("keyboard kind", card.kind_text() == "Keyboard")
	card.kind = "nonsense"
	_check("unknown kinds fall back to gamepad", card.kind == "gamepad")
	card.queue_free()


func _curve_tests(host: Control) -> void:
	var curve := ResponseCurve.new()
	host.add_child(curve)
	curve.size = Vector2(360, 320)
	var profile := ControllerProfile.defaults("gamepad", "mode2")
	profile.roll.deadzone = 0.12
	profile.roll.expo = 0.45
	curve.set_channel(profile, "roll")
	_check("gamepad roll applies shaping", curve.is_shaping_applied() and not curve.is_absolute())
	var worst := 0.0
	for index in curve.sample_count():
		var x := curve.input_at(index)
		worst = maxf(worst, absf(curve.sample_output(index) - ControllerProfile.condition_axis(x, profile.roll, "gamepad")))
	_check("curve equals ControllerProfile.condition_axis (deadzone + expo)", worst < 1e-12, str(worst))
	var middle := curve.sample_count() / 2
	_check("deadzone flattens the centre", is_zero_approx(curve.sample_output(middle))
		and is_zero_approx(curve.sample_output(middle + 2)))
	_check("full deflection is full output", is_equal_approx(curve.sample_output(curve.sample_count() - 1), 1.0)
		and is_equal_approx(curve.sample_output(0), -1.0))
	profile.roll.invert = true
	curve.set_channel(profile, "roll")
	worst = 0.0
	for index in curve.sample_count():
		var x := curve.input_at(index)
		worst = maxf(worst, absf(curve.sample_output(index) - ControllerProfile.channel_value(x, "roll", profile)))
	_check("inverted curve equals ControllerProfile.channel_value", worst < 1e-12
		and curve.sample_output(curve.sample_count() - 1) < -0.99, str(worst))
	# Calibrated endpoints: the plotted x is the physical stick position, not the raw value.
	profile.roll.invert = false
	profile.roll.min = -0.8
	profile.roll.center = 0.1
	profile.roll.max = 0.9
	curve.set_channel(profile, "roll")
	worst = 0.0
	for index in curve.sample_count():
		var x := curve.input_at(index)
		worst = maxf(worst, absf(curve.sample_output(index) - ControllerProfile.condition_axis(x, profile.roll, "gamepad")))
	_check("calibrated endpoints map back to the same shaped output", worst < 1e-9, str(worst))
	# Live dot.
	curve.set_raw_value(0.9)
	_check("live dot at full raw deflection", curve.is_live() and is_equal_approx(curve.live_point().x, 1.0)
		and is_equal_approx(curve.live_point().y, 1.0), str(curve.live_point()))
	curve.set_raw_value(0.5)
	var expected := ControllerProfile.channel_value(0.5, "roll", profile)
	_check("live output is ControllerProfile.channel_value of the raw sample",
		is_equal_approx(curve.live_point().y, expected), "%s %s" % [curve.live_point(), expected])
	var before := curve.redraw_requests
	curve.set_raw_value(0.5)
	curve.set_raw_value(0.5005)
	_check("unchanged live samples do not redraw", curve.redraw_requests == before)
	curve.set_channel(profile, "roll")
	_check("an identical channel does not recompute or redraw", curve.redraw_requests == before)
	# Disabled appearance: absolute trigger throttle and radio shaping.
	var trigger := ControllerProfile.defaults("gamepad", "trigger_absolute")
	curve.set_channel(trigger, "throttle")
	_check("trigger throttle preset: shaping disabled, absolute", not curve.is_shaping_applied() and curve.is_absolute()
		and curve.input_range() == Vector2(0.0, 1.0))
	worst = 0.0
	for index in curve.sample_count():
		worst = maxf(worst, absf(curve.sample_output(index) - curve.input_at(index)))
	_check("absolute trigger curve is the linear endpoint map", worst < 1e-12, str(worst))
	var rate := ControllerProfile.defaults("gamepad", "mode2")
	curve.set_channel(rate, "throttle")
	_check("stick-rate throttle keeps shaping", curve.is_shaping_applied() and not curve.is_absolute())
	var radio := ControllerProfile.defaults("radio", "radio_custom")
	curve.set_channel(radio, "roll")
	_check("radio channels are drawn linear and disabled", not curve.is_shaping_applied()
		and is_equal_approx(curve.sample_output(curve.sample_count() - 1), 1.0))
	curve.queue_free()


func _chip_tests(host: Control) -> void:
	var chip := BindingChip.new()
	chip.key_mapper = _qwerty
	host.add_child(chip)
	chip.set_binding({"type": "button", "button": JOY_BUTTON_LEFT_SHOULDER}, "xbox")
	_check("button chip: family label and glyph", chip.label_text() == "LB" and chip.has_glyph())
	chip.set_binding({"type": "button", "button": JOY_BUTTON_LEFT_SHOULDER}, "playstation")
	_check("glyph family is presentation only", chip.label_text() == "L1")
	chip.action_name = "Throttle cut"
	_check("accessible name has action and control", chip.accessibility_name == "Throttle cut: L1", chip.accessibility_name)
	chip.conflict = true
	_check("conflict joins the accessible name", chip.accessibility_name == "Throttle cut: L1, conflict")
	chip.conflict = false
	chip.set_binding({"type": "axis", "axis": 5, "sign": 1})
	_check("axis chip label", chip.label_text() == "Axis 5 +" and not chip.has_glyph(), chip.label_text())
	chip.set_binding({"type": "axis", "axis": 4, "off": -1.0, "on": 0.6})
	_check("AUX axis chip shows endpoints", chip.label_text().begins_with("Axis 4"), chip.label_text())
	chip.set_binding({"type": "key", "physical_keycode": KEY_A, "shift": true})
	_check("key chip uses the layout name", chip.is_key() and chip.label_text() == "A"
		and chip.accessibility_name == "Throttle cut: Shift+A", chip.accessibility_name)
	chip.set_binding({"type": "key", "physical_keycode": KEY_LEFT})
	_check("arrow key chip names the arrow", chip.label_text() == "Left arrow")
	chip.set_binding({"type": "switch", "label": "Sa", "buttons": [3, 4], "invert": false})
	_check("switch chip names the physical positions", chip.label_text() == "Sa Up · Button 3 / Sa Down · Button 4",
		chip.label_text())
	chip.set_label("Sa Up")
	_check("caller label overrides", chip.label_text() == "Sa Up")
	chip.set_label("")
	chip.set_binding({"type": "unbound"})
	_check("unbound chip", chip.is_unbound() and chip.label_text() == "Unbound")
	var before := chip.redraw_requests
	chip.set_binding({"type": "unbound"})
	chip.live_pressed = false
	_check("unchanged chip state does not redraw", chip.redraw_requests == before)
	chip.live_pressed = true
	_check("live press redraws once", chip.redraw_requests == before + 1)
	_check("chip minimum size fits its text", chip.get_combined_minimum_size().x > 20.0)
	chip.queue_free()
