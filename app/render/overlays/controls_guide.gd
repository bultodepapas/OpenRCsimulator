# HUD-11-R2: read-only, profile-aware controls reference. Uses the existing keyboard
# table and effective controller bindings, including remaps and AUX reservations.
extends "res://render/overlays/overlay_frame.gd"

const Reference := preload("res://ui/controls_reference.gd")
const Keys := preload("res://ui/key_labels.gd")
const Actions := preload("res://input/controller_actions.gd")
const Prompts := preload("res://ui/controller_prompts.gd")
const ARROWS := { KEY_LEFT: "←", KEY_RIGHT: "→", KEY_UP: "↑", KEY_DOWN: "↓" }
const CHANNELS := { roll = "Roll", pitch = "Pitch", yaw = "Rudder", throttle = "Throttle" }

var keyboard_button: Button
var controller_button: Button
var source_label: Label
var scroll: ScrollContainer
var rows: VBoxContainer
var _context := {}
var _show_controller := false
var _equipment_state := {}
var _equipment_labels := {}


func _init() -> void:
	super("controls", tr("Control guide"))
	custom_minimum_size.x = 288
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	body.add_child(tabs)
	keyboard_button = _tab(tr("Keyboard"), tabs, false)
	controller_button = _tab(tr("Controller"), tabs, true)
	source_label = text_label("", 12, UiTheme.TEXT_2)
	source_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(source_label)
	scroll = ScrollContainer.new()
	scroll.name = "Commands"
	scroll.custom_minimum_size = Vector2(272, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP # reading the list must not zoom the camera
	scroll.focus_mode = Control.FOCUS_NONE
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	body.add_child(scroll)
	rows = VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.mouse_filter = Control.MOUSE_FILTER_PASS
	rows.add_theme_constant_override("separation", 5)
	scroll.add_child(rows)
	var footer := text_label(tr("Reopen: Esc → Flight overlays"), 12, UiTheme.TEXT_2)
	body.add_child(footer)
	refresh({})
	_rebuild()


func _tab(caption: String, parent: HBoxContainer, controller: bool) -> Button:
	var button := Button.new()
	button.text = caption
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 13)
	button.custom_minimum_size.y = 26
	button.pressed.connect(func() -> void:
		_show_controller = controller
		_rebuild())
	parent.add_child(button)
	return button


func refresh(context: Dictionary) -> void:
	var stable := context.duplicate()
	_equipment_state = stable.get("equipment_state", {})
	stable.erase("equipment_state")
	if stable == _context:
		_update_equipment_state()
		return
	var source_changed: bool = stable.get("connected", false) != _context.get("connected", false) \
		or stable.get("device_name", "") != _context.get("device_name", "")
	_context = stable.duplicate(true)
	if source_changed:
		_show_controller = bool(context.get("connected", false))
	_rebuild()


func _rebuild() -> void:
	_equipment_labels.clear()
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	keyboard_button.set_pressed_no_signal(not _show_controller)
	controller_button.set_pressed_no_signal(_show_controller)
	controller_button.disabled = not bool(_context.get("connected", false))
	scroll.scroll_vertical = 0
	if _show_controller:
		_controller_rows()
	else:
		_keyboard_rows()
	_update_equipment_state()


func _keyboard_rows() -> void:
	source_label.text = tr("Keyboard shortcuts remain available.") if _context.get("connected", false) else tr("Active input · Keyboard")
	source_label.tooltip_text = source_label.text
	_section(tr("Flight"))
	for row: Array in Reference.FLIGHT:
		_row(tr(row[1]), key_text(row[0]))
	_note(tr("↓ pulls the nose up. W adds power; S reduces it."))
	if _context.get("connected", false):
		_note(tr("Flight axes use the selected controller."))
	_section(tr("Shortcuts"))
	# Recovery and camera first, then every other shared shortcut, including future additions.
	var priority := [KEY_ESCAPE, KEY_R, KEY_C, KEY_Z]
	for preferred: bool in [true, false]:
		for row: Array in Reference.SHORTCUTS:
			if priority.has(row[0][0]) == preferred:
				_row(tr(row[1]), key_text(row[0]))


func _controller_rows() -> void:
	var profile: Dictionary = _context.get("profile", {})
	var gamepad: bool = profile.get("kind", "radio") == "gamepad"
	var family := str(profile.get("presentation", {}).get("glyph_family", "auto"))
	var info: Dictionary = _context.get("device_info", {})
	source_label.text = str(_context.get("device_name", tr("Controller")))
	source_label.tooltip_text = source_label.text
	var bindings := Actions.effective_bindings(profile, _context.get("capabilities", {}))
	_equipment_rows(profile, bindings, gamepad, family, info)
	_section(tr("Flight"))
	for channel: String in CHANNELS:
		_row(tr(CHANNELS[channel]), axis_text(profile.get(channel, {}), gamepad, family, info))
	if profile.get("throttle_mode", "") == "stick_rate":
		_note(tr("Throttle holds when you release the stick."))
	elif profile.get("throttle_mode", "") == "trigger_absolute":
		_note(tr("Release the trigger for idle throttle."))
	_section(tr("Shortcuts"))
	for action: Dictionary in Actions.ACTIONS:
		var action_id := str(action.id)
		if action.context == "menu" or action_id.begins_with("helicopter_"):
			continue
		if _context.has("capabilities") and action_id in ["gear_toggle", "smoke_toggle", "flaps_cycle"]:
			continue # already shown with availability in the aircraft section
		var binding: Dictionary = bindings.get(action_id, {})
		if binding.get("type", "unbound") == "unbound":
			continue
		var prompt := Prompts.prompt(binding, family, info)
		if not gamepad and binding.get("type", "") == "button":
			prompt = { text = tr("Button %d") % int(binding.button), texture_path = "" }
		_row(tr(action.label), prompt.text, prompt.texture_path)
	for channel: String in ["smoke", "flaps", "gear"]:
		if _context.has("capabilities"):
			continue
		var binding: Dictionary = profile.get("aux", {}).get(channel, {})
		if binding.get("type", "") not in ["axis", "button"]:
			continue
		var prompt := Prompts.prompt(binding, family if gamepad else "generic", info)
		if binding.type == "axis":
			prompt.text = tr("Axis %d") % int(binding.axis)
		elif not gamepad:
			prompt.text = tr("Button %d") % int(binding.button)
		_row(tr({ smoke = "Smoke AUX", flaps = "Flaps", gear = "Gear request" }[channel]), prompt.text)
	_row(tr("Pause"), Keys.label(KEY_ESCAPE))
	_row(tr("Restart flight"), Keys.label(KEY_R))
	_note(tr("Aircraft capabilities determine which auxiliary controls are available."))


func _equipment_rows(profile: Dictionary, bindings: Dictionary, gamepad: bool, family: String, info: Dictionary) -> void:
	if not _context.has("capabilities"):
		return
	_section(tr("This aircraft"))
	var capabilities: Dictionary = _context.capabilities
	for channel: String in ["gear", "smoke", "flaps"]:
		var action_id: String = {gear = "gear_toggle", smoke = "smoke_toggle", flaps = "flaps_cycle"}[channel]
		var caption := tr({gear = "Landing gear", smoke = "Smoke", flaps = "Flaps"}[channel])
		var available := bool(capabilities.get(channel, false))
		var aux: Dictionary = profile.get("aux", {}).get(channel, {})
		var binding: Dictionary = aux if aux.get("type", "") in ["button", "axis"] else bindings.get(action_id, {})
		var prompt := Prompts.prompt(binding, family if gamepad else "generic", info)
		if not aux.is_empty() and binding.get("type", "") == "axis":
			prompt.text = tr("Axis %d") % int(binding.axis)
		elif not gamepad and binding.get("type", "") == "button":
			prompt = {text = tr("Button %d") % int(binding.button), texture_path = ""}
		if not available:
			caption += "\n" + tr("Not available")
			if binding.get("type", "unbound") == "unbound":
				prompt.text = "—"
		elif binding.get("type", "unbound") == "unbound":
			caption += "\n" + tr("Assign in Controller settings")
		var label := _row(caption, prompt.text, prompt.texture_path)
		if available and binding.get("type", "unbound") != "unbound":
			_equipment_labels[channel] = {label = label, caption = caption}


func _update_equipment_state() -> void:
	var names := {up = "Up", down = "Down", extending = "Extending", retracting = "Retracting", on = "On", off = "Off"}
	for channel: String in _equipment_labels:
		var entry: Dictionary = _equipment_labels[channel]
		var state: Variant = _equipment_state.get(channel, "")
		if channel == "flaps" and state is Dictionary:
			var state_line := tr("Requested %.0f%% · actual %.1f°") % [float(state.get("requested", 0.0)) * 100.0, float(state.get("angle_deg", 0.0))]
			if bool(state.get("moving", false)):
				state_line += " · " + tr("Moving")
			if bool(state.get("overspeed", false)):
				state_line += " · " + tr("Overspeed advisory")
			entry.label.text = entry.caption + "\n" + state_line
			continue
		var state_name := str(state)
		entry.label.text = entry.caption + ("\n" + tr(names[state_name]) if names.has(state_name) else "")


func _section(caption: String) -> void:
	rows.add_child(text_label(caption.to_upper(), 11, UiTheme.FOCUS))


func _note(caption: String) -> void:
	var label := text_label(caption, 12, UiTheme.TEXT_2)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(label)


func _row(caption: String, binding: String, texture_path := "") -> Label:
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_PASS
	line.add_theme_constant_override("separation", 8)
	rows.add_child(line)
	var label := text_label(caption, 13, UiTheme.TEXT)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_child(label)
	var keycap := PanelContainer.new()
	keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keycap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	keycap.custom_minimum_size.x = 106
	var style := StyleBoxFlat.new()
	style.bg_color = UiTheme.KEYCAP.bg
	style.border_color = UiTheme.KEYCAP.edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	keycap.add_theme_stylebox_override("panel", style)
	line.add_child(keycap)
	var content := HBoxContainer.new()
	keycap.add_child(content)
	if not texture_path.is_empty():
		var icon := TextureRect.new()
		icon.texture = load(texture_path)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(20, 20)
		content.add_child(icon)
	var value := text_label(binding, 12, UiTheme.TEXT)
	value.custom_minimum_size.x = 76 if not texture_path.is_empty() else 94
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(value)
	line.tooltip_text = "%s: %s" % [caption, binding]
	return label


static func key_text(keys: Array) -> String:
	var labels := PackedStringArray()
	for key: int in keys:
		labels.append(ARROWS.get(key, Keys.label(key)))
	return " / ".join(labels)


static func axis_text(channel: Dictionary, gamepad: bool, family: String, info: Dictionary) -> String:
	var axis := int(channel.get("axis", -1))
	var caption := TranslationServer.translate("Axis %d") % axis
	if gamepad:
		match axis:
			0: caption = TranslationServer.translate("Left stick ↔")
			1: caption = TranslationServer.translate("Left stick ↕")
			2: caption = TranslationServer.translate("Right stick ↔")
			3: caption = TranslationServer.translate("Right stick ↕")
			4: caption = "L2" if Prompts.resolve_family(family, info) == "playstation" else "LT"
			5: caption = "R2" if Prompts.resolve_family(family, info) == "playstation" else "RT"
	return caption
