extends VBoxContainer
## Capability-driven inspector. Emits complete proposals; its owner validates and records one shared history.
const Profile := preload("res://workshop/presentation.gd")
const Widgets := preload("res://ui/widgets.gd")
signal profile_changed(profile: Dictionary)
signal validity_changed(page: String, pending: bool)
const COLORS := {"White":"#FFFFFFFF", "Red":"#E54646FF", "Blue":"#327DE8FF", "Gold":"#F0B739FF", "Green":"#40B982FF", "Purple":"#A871D8FF", "Black":"#20252BFF"}
var page_kind := "appearance"
var _bindings: Dictionary = {}
var _profile: Dictionary = {}
var _slot: OptionButton
var _color: OptionButton
var _picker: ColorPickerButton
var _color_cancel: Button
var _custom_color: LineEdit
var _error: Label
var _enabled: CheckButton
var _shape: OptionButton
var _mode: OptionButton
var _palette_selector: OptionButton
var _palette_mode: OptionButton
var _palette_buttons: Array[Button] = []
var _copy_target: OptionButton
var _copy_button: Button
var _legacy_amount_row: HBoxContainer
var _legacy_amount_value: Label
var _marking_box: VBoxContainer
var _marking_slot: OptionButton
var _marking_text: LineEdit
var _marking_color: OptionButton
var _fields: Dictionary = {}
var _field_rows: Dictionary = {}
var _controls: VBoxContainer
var _note: Label
var _legacy_amount_note: Label
var _advanced: VBoxContainer
var _advanced_button: Button
var _syncing := false
var _shown_slot := 0
var _shown_palette := 0
var _shown_marking := 0

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var heading := Label.new()
	heading.text = tr("Appearance" if page_kind == "appearance" else "Smoke")
	heading.theme_type_variation = "CardTitle"
	add_child(heading)
	_note = label("Paint changes only the selected registered region." if page_kind == "appearance" else "Show smoke is a visual effect. Source exhaust follows the running engine.")
	if page_kind == "smoke":
		label("Smoke preset").theme_type_variation = "SectionLabel"
		var presets := OptionButton.new()
		presets.name = "SmokePreset"
		for text: String in ["Choose a smoke preset…", "Clear Trainer", "Twin Ribbons", "Tricolor", "Tail Comet", "Rainbow Burst", "Classic Exhaust", "Pastel Cloud", "Alternating Tips", "Monochrome Dark"]: presets.add_item(tr(text))
		presets.item_selected.connect(func(index: int) -> void:
			if index > 0: apply_preset(index)
			presets.select(0))
		add_child(presets)
	label("Paint region" if page_kind == "appearance" else "Smoke emitter").theme_type_variation = "SectionLabel"
	_slot = OptionButton.new()
	_slot.name = "PaintRegion" if page_kind == "appearance" else "SmokeEmitter"
	_slot.fit_to_longest_item = false
	_slot.clip_text = true
	_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot.item_selected.connect(_select_slot)
	add_child(_slot)
	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", 10)
	add_child(_controls)
	if page_kind == "smoke":
		_enabled = CheckButton.new()
		_enabled.text = tr("Enable this emitter")
		_enabled.toggled.connect(func(value: bool) -> void: change("enabled", value))
		_controls.add_child(_enabled)
	var color_label := label("Color", _controls)
	_color = OptionButton.new()
	for text: String in COLORS: _color.add_item(tr(text))
	_color.add_item(tr("Custom color"))
	if page_kind == "appearance":
		_color.add_item("Stock")
		_color.set_item_disabled(COLORS.size() + 1, true)
	_color.item_selected.connect(func(index: int) -> void:
		if index < COLORS.size(): change("color", COLORS.values()[index]))
	_controls.add_child(_color)
	var custom := HBoxContainer.new()
	_custom_color = LineEdit.new()
	_custom_color.name = "PresentationColor"
	_custom_color.placeholder_text = "#RRGGBBAA"
	_custom_color.max_length = 9
	_custom_color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom_color.text_changed.connect(func(text: String) -> void:
		if _syncing: return
		if page_kind == "smoke": _sync_picker_from_hex(text)
		validity_changed.emit(page_kind, has_pending_color() or has_pending_marking()))
	_custom_color.text_submitted.connect(func(_value: String) -> void: apply_color())
	custom.add_child(_custom_color)
	if page_kind == "smoke":
		_picker = ColorPickerButton.new()
		Widgets.fit_color_picker_popup(_picker)
		_picker.name = "SmokeColorPicker"
		_picker.tooltip_text = tr("Choose any sRGB color and alpha, then Apply color to keep it.")
		_picker.edit_alpha = true
		_picker.custom_minimum_size = Vector2(44.0, 32.0)
		_picker.color_changed.connect(_on_picker_color_changed)
		custom.add_child(_picker)
	var apply := Button.new()
	apply.text = tr("Apply color")
	apply.pressed.connect(apply_color)
	custom.add_child(apply)
	if page_kind == "smoke":
		_color_cancel = Button.new()
		_color_cancel.name = "CancelSmokeColor"
		_color_cancel.text = tr("Cancel")
		_color_cancel.pressed.connect(cancel_pending_edit)
		custom.add_child(_color_cancel)
	_controls.add_child(custom)
	if page_kind == "appearance":
		var reset_region := Button.new()
		reset_region.text = tr("Restore selected region")
		reset_region.pressed.connect(reset_paint_region)
		_controls.add_child(reset_region)
		build_markings()
	if page_kind == "smoke":
		_palette_selector = options("Color steps", [])
		_palette_selector.name = "SmokePaletteStep"
		_palette_selector.item_selected.connect(_select_palette_step)
		_palette_mode = options("Palette transition", ["step", "smooth"])
		_palette_mode.name = "SmokePaletteMode"
		_palette_mode.item_selected.connect(func(index: int) -> void:
			if _syncing: return
			change("palette_mode", "step" if index == 0 else "smooth"))
		var palette_actions := HFlowContainer.new()
		for spec: Array in [[tr("Add color step"), 1], [tr("Remove last step"), -1], [tr("Use single color"), 0]]:
			var action := Button.new()
			action.text = spec[0]
			action.pressed.connect(edit_palette.bind(spec[1]))
			palette_actions.add_child(action)
			_palette_buttons.append(action)
		_controls.add_child(palette_actions)
		number_field("step_s", "Step duration / palette period", 0.05, 8.0, 0.05, "s")
		_legacy_amount_row = HBoxContainer.new()
		_legacy_amount_row.name = "SmokeLegacyAmountRow"
		_field_rows["amount"] = _legacy_amount_row
		var legacy_amount_label := label("Legacy amount", _legacy_amount_row)
		legacy_amount_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_legacy_amount_value = label("", _legacy_amount_row)
		_legacy_amount_value.name = "SmokeLegacyAmountValue"
		_controls.add_child(_legacy_amount_row)
		_legacy_amount_row.visible = false
		_legacy_amount_note = label("The v1 amount is shown for reference and is read-only. Edit density or emission rate to create a v2 draft; the saved v1 revision stays unchanged.", _controls)
		_legacy_amount_note.name = "SmokeLegacyAmountNote"
		_legacy_amount_note.visible = false
		number_field("density", "Density", 0.0, 2.0, 0.05, "×")
		number_field("emission_rate_hz", "Emission rate", 1.0, 240.0, 1.0, "puffs/s")
		number_field("width_m", "Width", 0.01, 2.0, 0.01, "m")
		number_field("lifetime_s", "Puff lifetime", 0.1, 8.0, 0.1, "s")
		_shape = options("Shape", ["ribbon", "cloud", "fan"])
		_shape.item_selected.connect(func(index: int) -> void: change("shape", ["ribbon", "cloud", "fan"][index]))
		_mode = options("Emission", ["hold", "burst", "pulse"])
		_mode.item_selected.connect(func(index: int) -> void:
			if _syncing: return
			var entry := current_entry()
			entry.mode = ["hold", "burst", "pulse"][index]
			entry.burst_s = 3.0 if index == 1 else 0.0
			entry.pulse_period_s = 1.0 if index == 2 else 0.0
			entry.pulse_duty = 0.5 if index == 2 else 0.0
			commit_entry(entry))
		number_field("burst_s", "Burst duration", 0.1, 8.0, 0.1, "s")
		number_field("pulse_period_s", "Pulse period", 0.1, 8.0, 0.1, "s")
		number_field("pulse_duty", "Pulse on fraction", 0.05, 0.95, 0.05, "×")
		number_field("phase_offset_s", "Palette phase offset", 0.0, 60.0, 0.05, "s")
		number_field("jet_speed_mps", "Jet speed", 0.0, 30.0, 0.1, "m/s")
		number_field("turbulence_mps", "Turbulence", 0.0, 5.0, 0.05, "m/s")
		number_field("dispersion_m2_s", "Dispersion", 0.0, 2.0, 0.01, "m²/s")
		number_field("buoyancy_mps", "Buoyancy", -2.0, 3.0, 0.05, "m/s")
		number_field("drag_s", "Drag", 0.05, 3.0, 0.05, "s")
		number_field("velocity_inheritance", "Outlet velocity", 0.0, 1.0, 0.05, "×")
		_build_copy_controls()
		label("Duration controls new emission; existing puffs fade for their full lifetime.", _controls)
		_build_advanced_group(custom, color_label)
	_error = label("")
	_error.theme_type_variation = "ErrorLabel"
	configure(_bindings, _profile)

func _build_advanced_group(color_row: Control, color_label: Control) -> void:
	_advanced = VBoxContainer.new()
	_advanced.name = "SmokeMoreOptions"
	_advanced.add_theme_constant_override("separation", 10)
	_advanced.visible = false
	_advanced.add_child(HSeparator.new())
	label("Advanced smoke settings", _advanced).theme_type_variation = "SectionLabel"
	var basic: Array = [_enabled, color_label, _color, color_row, _legacy_amount_row, _legacy_amount_note, _field_rows.density,
		_field_rows.emission_rate_hz, _field_rows.width_m, _field_rows.lifetime_s, _shape,
		_controls.get_child(_shape.get_index() - 1)]
	for child: Node in _controls.get_children():
		if child in basic: continue
		_controls.remove_child(child)
		_advanced.add_child(child)
	_advanced_button = Button.new()
	_advanced_button.name = "SmokeMoreOptionsButton"
	_advanced_button.text = tr("More options")
	_advanced_button.toggle_mode = true
	_advanced_button.toggled.connect(func(expanded: bool) -> void:
		_advanced.visible = expanded
		_advanced_button.text = tr("Fewer options" if expanded else "More options"))
	_controls.add_child(_advanced_button)
	_controls.add_child(_advanced)

func _build_copy_controls() -> void:
	var row := HBoxContainer.new()
	_copy_target = OptionButton.new()
	_copy_target.name = "SmokeCopyTarget"
	_copy_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_copy_target.add_item(tr("Copy to another emitter…"))
	row.add_child(_copy_target)
	_copy_button = Button.new()
	_copy_button.name = "SmokeCopySettings"
	_copy_button.text = tr("Copy settings")
	_copy_button.tooltip_text = tr("Make a one-time copy of this emitter's settings. Later edits stay independent.")
	_copy_button.pressed.connect(copy_settings_to_target)
	row.add_child(_copy_button)
	_controls.add_child(row)

func label(text: String, parent: Node = self) -> Label:
	var result := Label.new()
	result.text = tr(text)
	result.theme_type_variation = "SecondaryLabel"
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(result)
	return result

func options(title: String, values: Array) -> OptionButton:
	label(title, _controls)
	var result := OptionButton.new()
	for value: String in values: result.add_item(tr(value.capitalize()))
	_controls.add_child(result)
	return result

func number_field(key: String, title: String, low: float, high: float, step: float, suffix: String) -> void:
	var row := HBoxContainer.new()
	var title_label := label(title, row)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var value := SpinBox.new()
	value.name = "Smoke" + key.to_pascal_case()
	value.min_value = low
	value.max_value = high
	value.step = step
	value.suffix = suffix
	value.custom_minimum_size.x = 130
	value.get_line_edit().expand_to_text_length = true
	value.value_changed.connect(func(next: float) -> void: change(key, next))
	row.add_child(value)
	_controls.add_child(row)
	_fields[key] = value
	_field_rows[key] = row

func configure(bindings: Dictionary, profile: Dictionary) -> void:
	var retain_buffer := is_instance_valid(_custom_color) and _bindings == bindings and has_pending_color()
	var buffer := _custom_color.text if retain_buffer else ""
	var retain_marking := is_instance_valid(_marking_text) and _bindings == bindings and has_pending_marking()
	var marking_buffer := _marking_text.text if retain_marking else ""
	var marking_color_buffer := _marking_color.selected if retain_marking else 0
	_bindings = bindings.duplicate(true)
	_profile = profile.duplicate(true)
	if not is_instance_valid(_slot): return
	var selected := str(_slot.get_item_metadata(_slot.selected)) if _slot.selected >= 0 else ""
	_syncing = true
	_slot.clear()
	for slot: Dictionary in _bindings.get("paint_slots" if page_kind == "appearance" else "smoke_slots", []):
		_slot.add_item(tr(str(slot.label)))
		_slot.set_item_metadata(_slot.item_count - 1, slot.id)
		if slot.id == selected: _slot.select(_slot.item_count - 1)
	_controls.visible = _slot.item_count > 0
	_slot.disabled = _slot.item_count == 0
	_note.text = tr("Paint changes only the selected registered region.") if page_kind == "appearance" else _smoke_version_note()
	if _slot.item_count == 0:
		_slot.add_item("No registered regions" if page_kind == "appearance" else "No registered emitters")
		_note.text = tr("This model has no registered customization for this page.")
	_syncing = false
	sync_fields(false)
	if page_kind == "appearance":
		sync_markings(true, false)
		if retain_marking:
			_marking_text.text = marking_buffer
			_marking_color.select(marking_color_buffer)
	if retain_buffer:
		_custom_color.text = buffer
	validity_changed.emit(page_kind, has_pending_color() or has_pending_marking())

func _smoke_version_note() -> String:
	if _profile.get("smoke", []).is_empty():
		return tr("Choose a preset or enable an emitter, then adjust its color and shape.")
	if int(_profile.get("version", Profile.VERSION)) == 1:
		return tr("This saved smoke profile uses older settings. Editing updates the draft; the saved build stays unchanged.")
	return tr("Show smoke is a visual effect. Source exhaust follows the running engine.")

func _display_smoke_entry(entry: Dictionary) -> Dictionary:
	var result: Dictionary = Profile.normalize_smoke_entry(entry, int(_profile.get("version", Profile.VERSION)))
	if bool(result.get("ok", false)):
		var normalized: Dictionary = Profile.smoke_v2_defaults()
		normalized.merge(result.value, true)
		return normalized
	# Keep malformed or unsupported source values visible without silently repairing them.
	var fallback: Dictionary = Profile.smoke_v2_defaults()
	fallback.merge(entry, true)
	return fallback

func _sync_copy_targets(source_slot: String) -> void:
	if not is_instance_valid(_copy_target):
		return
	var kind := ""
	for slot: Dictionary in _bindings.get("smoke_slots", []):
		if str(slot.get("id", "")) == source_slot:
			kind = str(slot.get("kind", ""))
			break
	_copy_target.clear()
	_copy_target.add_item(tr("Copy to another emitter…"))
	_copy_target.set_item_metadata(0, "")
	for slot: Dictionary in _bindings.get("smoke_slots", []):
		if str(slot.get("id", "")) == source_slot or str(slot.get("kind", "")) != kind:
			continue
		_copy_target.add_item(tr(str(slot.get("label", slot.get("id", "Emitter")))))
		_copy_target.set_item_metadata(_copy_target.item_count - 1, str(slot.get("id", "")))
	_copy_target.select(0)
	_copy_target.disabled = _copy_target.item_count <= 1
	_copy_button.disabled = _copy_target.disabled

func current_entry() -> Dictionary:
	if _slot.item_count == 0 or _slot.get_item_metadata(_slot.selected) == null: return {}
	var id := str(_slot.get_item_metadata(_slot.selected))
	for entry: Dictionary in _profile.get("paint" if page_kind == "appearance" else "smoke", []):
		if entry.slot == id: return entry.duplicate(true)
	if page_kind == "appearance": return {slot = id, color = "#FFFFFFFF", pattern = "solid", accent = "none"}
	var defaults: Dictionary = Profile.smoke_v2_defaults()
	defaults.merge({slot = id, enabled = false, color = "#FFFFFFFF", amount = 0.5, width_m = 0.12,
		lifetime_s = 3.0, shape = "ribbon", mode = "hold", burst_s = 0.0,
		pulse_period_s = 0.0, pulse_duty = 0.0, palette = [], step_s = 0.0}, true)
	return defaults

func sync_fields(notify := true) -> void:
	if not is_instance_valid(_custom_color): return
	var entry := current_entry()
	if entry.is_empty(): return
	var display_entry := _display_smoke_entry(entry) if page_kind == "smoke" else entry
	_syncing = true
	var color := selected_color(entry)
	_custom_color.text = color
	if page_kind == "smoke":
		_picker.color = Color.from_string(color, Color.WHITE) if not color.is_empty() else Color.WHITE
	_color.select(COLORS.size() + 1 if color.is_empty() else (COLORS.values().find(color) if color in COLORS.values() else COLORS.size()))
	if page_kind == "smoke":
		var selected_index := maxi(_palette_selector.selected, 0)
		_palette_selector.clear()
		if entry.palette.is_empty(): _palette_selector.add_item(tr("Single color"))
		else:
			for index in entry.palette.size(): _palette_selector.add_item(tr("Step %d") % (index + 1))
		_palette_selector.select(mini(selected_index, _palette_selector.item_count - 1))
		_palette_buttons[0].disabled = entry.palette.size() >= Profile.MAX_PALETTE_COLORS
		_palette_buttons[1].disabled = entry.palette.is_empty()
		_palette_buttons[2].disabled = entry.palette.is_empty()
		_palette_mode.select(1 if str(display_entry.get("palette_mode", "step")) == "smooth" else 0)
		_palette_mode.disabled = entry.palette.size() < 2
		_enabled.set_pressed_no_signal(entry.enabled)
		_shape.select(["ribbon", "cloud", "fan"].find(entry.shape))
		_mode.select(["hold", "burst", "pulse"].find(entry.mode))
		var legacy_profile := int(_profile.get("version", Profile.VERSION)) == Profile.LEGACY_VERSION
		var legacy_amount_present: bool = legacy_profile and _profile.get("smoke", []).any(
			func(candidate: Dictionary) -> bool: return str(candidate.get("slot", "")) == str(entry.get("slot", "")) and candidate.has("amount"))
		_legacy_amount_row.visible = legacy_amount_present
		_legacy_amount_value.text = String.num(float(entry.get("amount", 0.0)), 2)
		_legacy_amount_note.visible = legacy_amount_present
		for key: String in _fields:
			var values: Dictionary = display_entry if key != "amount" else entry
			if values.has(key): _fields[key].set_value_no_signal(values[key])
			var relevant: bool = (key != "burst_s" or entry.mode == "burst") \
				and (key not in ["pulse_period_s", "pulse_duty"] or entry.mode == "pulse") \
				and (key not in ["step_s", "phase_offset_s"] or entry.palette.size() > 1)
			_fields[key].editable = relevant
			_field_rows[key].visible = relevant
		_sync_copy_targets(str(entry.slot))
	_syncing = false
	_shown_slot = _slot.selected
	if page_kind == "smoke": _shown_palette = _palette_selector.selected
	if notify: validity_changed.emit(page_kind, has_pending_color() or has_pending_marking())

func has_pending_color() -> bool:
	if not is_instance_valid(_custom_color) or _syncing: return false
	var entry := current_entry()
	return not entry.is_empty() and _custom_color.text.to_upper() != selected_color(entry)

func _sync_picker_from_hex(text: String) -> void:
	if not is_instance_valid(_picker): return
	var value := text.to_upper()
	if value.length() == 9 and value.begins_with("#") and value.substr(1).is_valid_hex_number():
		_picker.color = Color.from_string(value, Color.WHITE)

func _on_picker_color_changed(color: Color) -> void:
	if _syncing or page_kind != "smoke": return
	_custom_color.text = "#" + color.to_html(true).to_upper()
	validity_changed.emit(page_kind, has_pending_color() or has_pending_marking())

func _select_slot(index: int) -> void:
	_slot.select(_shown_slot)
	if has_pending_color():
		_error.text = tr("Apply or cancel the edited color before changing regions or emitters.")
		_custom_color.grab_focus()
		return
	_slot.select(index)
	sync_fields()

func _select_palette_step(index: int) -> void:
	_palette_selector.select(_shown_palette)
	if has_pending_color():
		_error.text = tr("Apply or cancel the edited color before changing color steps.")
		_custom_color.grab_focus()
		return
	_palette_selector.select(index)
	sync_fields()

func _select_marking_slot(index: int) -> void:
	_marking_slot.select(_shown_marking)
	if has_pending_marking():
		_error.text = tr("Apply or cancel the edited inscription before changing panels.")
		_marking_text.grab_focus()
		return
	_marking_slot.select(index)
	sync_markings(false)

## Recovery stores raw UI text separately from the accepted, launchable profile.
func get_editor_state() -> Dictionary:
	return {
		"slot": str(_slot.get_item_metadata(_slot.selected)) if _slot.selected >= 0 and _slot.get_item_metadata(_slot.selected) != null else "",
		"palette_step": maxi(_palette_selector.selected, 0) if page_kind == "smoke" else 0,
		"color_text": _custom_color.text,
		"marking_slot": str(_marking_slot.get_item_metadata(_marking_slot.selected)) if page_kind == "appearance" and _marking_slot.selected >= 0 else "",
		"marking_text": _marking_text.text if page_kind == "appearance" else "",
		"marking_color": _marking_color.selected if page_kind == "appearance" else 0,
	}

func restore_editor_state(state: Dictionary) -> bool:
	var keys := ["slot", "palette_step", "color_text", "marking_slot", "marking_text", "marking_color"]
	if state.size() != keys.size(): return false
	for key: String in keys:
		if not state.has(key): return false
	for key: String in ["slot", "color_text", "marking_slot", "marking_text"]:
		if typeof(state[key]) != TYPE_STRING: return false
	if state.slot.length() > 80 or state.marking_slot.length() > 80 or state.color_text.length() > 9 or state.marking_text.length() > 12: return false
	for key: String in ["palette_step", "marking_color"]:
		if typeof(state[key]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(state[key])) or float(state[key]) != floor(float(state[key])): return false
	if state.palette_step < 0 or state.palette_step >= Profile.MAX_PALETTE_COLORS or state.marking_color < 0 or state.marking_color > COLORS.size(): return false
	var slot_index := _find_slot(_slot, state.slot)
	var marking_index := _find_slot(_marking_slot, state.marking_slot) if page_kind == "appearance" else -1
	if slot_index < 0 and not state.slot.is_empty(): return false
	if marking_index < 0 and not state.marking_slot.is_empty(): return false
	if page_kind == "smoke":
		if not state.marking_slot.is_empty() or not state.marking_text.is_empty() or state.marking_color != 0: return false
		# An unavailable palette step must not silently redirect a pending color.
		var entries: Array = _profile.get("smoke", [])
		var palette_size := 0
		for entry: Dictionary in entries:
			if entry.slot == state.slot: palette_size = entry.palette.size()
		if int(state.palette_step) >= maxi(1, palette_size): return false
	elif state.palette_step != 0: return false
	if slot_index >= 0: _slot.select(slot_index)
	if page_kind == "smoke": _palette_selector.select(int(state.palette_step))
	sync_fields(false)
	if page_kind == "appearance":
		if marking_index >= 0: _marking_slot.select(marking_index)
		sync_markings(false, false)
		_marking_text.text = state.marking_text
		_marking_color.select(int(state.marking_color))
	_custom_color.text = state.color_text
	validity_changed.emit(page_kind, has_pending_color() or has_pending_marking())
	return true

func _find_slot(selector: OptionButton, id: String) -> int:
	if not is_instance_valid(selector): return -1
	for index in selector.item_count:
		if selector.get_item_metadata(index) != null and str(selector.get_item_metadata(index)) == id: return index
	return -1

func pending_control() -> Control:
	return _marking_text if has_pending_marking() else _custom_color

func cancel_pending_edit() -> bool:
	if not has_pending_color() and not has_pending_marking(): return false
	sync_fields()
	if page_kind == "appearance": sync_markings()
	_error.text = ""
	return true

func change(key: String, value: Variant) -> void:
	if _syncing: return
	var entry := current_entry()
	if entry.is_empty(): return
	entry[key] = value
	if key == "color" and page_kind == "smoke" and not entry.palette.is_empty():
		entry.palette[clampi(_palette_selector.selected, 0, entry.palette.size() - 1)] = value
	commit_entry(entry)

func selected_color(entry: Dictionary) -> String:
	if page_kind == "appearance" and not _profile.get("paint", []).any(func(value: Dictionary) -> bool: return value.slot == entry.slot):
		return "" # Stock materials need not have a single flat color.
	if page_kind == "smoke" and not entry.get("palette", []).is_empty() and is_instance_valid(_palette_selector):
		return str(entry.palette[clampi(_palette_selector.selected, 0, entry.palette.size() - 1)])
	return str(entry.color)

func edit_palette(operation: int) -> void:
	var entry := current_entry()
	if operation == 0:
		entry.color = selected_color(entry)
		entry.palette = []
	elif operation > 0:
		if entry.palette.size() >= Profile.MAX_PALETTE_COLORS: return
		if entry.palette.is_empty(): entry.palette.append(entry.color)
		entry.palette.append(COLORS.values()[entry.palette.size() % COLORS.size()])
	else:
		if not entry.palette.is_empty(): entry.palette.pop_back()
	entry.step_s = 0.5 if entry.palette.size() > 1 else 0.0
	commit_entry(entry)

func apply_color() -> void:
	var text := _custom_color.text.to_upper()
	if text.length() != 9 or not text.begins_with("#") or not text.substr(1).is_valid_hex_number():
		_error.text = tr("Use #RRGGBBAA, for example #327DE8FF.")
		return
	change("color", text)

func _promote_v1_profile(profile: Dictionary) -> Dictionary:
	if int(profile.get("version", Profile.VERSION)) != 1:
		return {"ok": true, "profile": profile.duplicate(true), "report": {}}
	var migrated: Dictionary = Profile.migrate_v1(profile, _bindings, _bindings)
	if not bool(migrated.get("ok", false)):
		return migrated
	# Run the normal strict validator so the new draft carries the current canonical identity.
	var checked: Dictionary = Profile.validate(migrated.profile, _bindings)
	if not bool(checked.get("ok", false)):
		return {"ok": false, "errors": checked.get("errors", PackedStringArray()), "report": migrated.get("report", {})}
	return {"ok": true, "profile": checked.profile, "report": migrated.get("report", {})}

func _show_migration_note() -> void:
	var enabled_count := 0
	for entry: Dictionary in _profile.get("smoke", []):
		if bool(entry.get("enabled", false)):
			enabled_count += 1
	_note.text = tr("Created a v2 draft with %d enabled smoke outlet(s). Review density, rate, and motion before saving. The saved v1 revision is unchanged; v2 makes no claim of visual equivalence.") % enabled_count

func commit_entry(entry: Dictionary) -> bool:
	var next := _profile.duplicate(true)
	var migration_report: Variant = {}
	if page_kind == "smoke" and int(next.get("version", Profile.VERSION)) == 1:
		var old_entry: Dictionary = {}
		for candidate: Dictionary in next.get("smoke", []):
			if str(candidate.get("slot", "")) == str(entry.get("slot", "")):
				old_entry = candidate.duplicate(true)
				break
		var promotion := _promote_v1_profile(next)
		if not bool(promotion.get("ok", false)):
			_error.text = "\n".join(PackedStringArray(promotion.get("errors", PackedStringArray([tr("Legacy smoke migration is unavailable for this model.")]))))
			return false
		next = promotion.profile
		migration_report = promotion.get("report", {})
		var promoted_entry: Dictionary = {}
		for candidate: Dictionary in next.get("smoke", []):
			if str(candidate.get("slot", "")) == str(entry.get("slot", "")):
				promoted_entry = candidate.duplicate(true)
				break
		if promoted_entry.is_empty():
			promoted_entry = Profile.smoke_v2_defaults()
			promoted_entry.merge(entry, true)
		else:
			# Preserve migration-derived values unless this edit explicitly changed them.
			for key: Variant in entry.keys():
				if not old_entry.has(key) or old_entry[key] != entry[key]:
					promoted_entry[key] = entry[key]
		entry = promoted_entry
	var key := "paint" if page_kind == "appearance" else "smoke"
	var entries: Array = next.get(key, []).duplicate(true)
	for i in range(entries.size() - 1, -1, -1):
		if entries[i].slot == entry.slot: entries.remove_at(i)
	entries.append(entry)
	next[key] = entries
	if not propose(next): return false
	if not migration_report.is_empty(): _show_migration_note()
	return true

func copy_settings_to_target() -> bool:
	if page_kind != "smoke" or not is_instance_valid(_copy_target) or _copy_target.selected < 0:
		return false
	var promoting_legacy := int(_profile.get("version", Profile.VERSION)) == 1
	var source := current_entry()
	var target_slot := str(_copy_target.get_item_metadata(_copy_target.selected))
	if source.is_empty() or target_slot.is_empty() or target_slot == str(source.get("slot", "")):
		return false
	var copied := _display_smoke_entry(source)
	copied.slot = target_slot
	if not commit_entry(copied): return false
	if promoting_legacy:
		_note.text += " " + tr("Settings were copied once; later edits remain independent.")
	else:
		_note.text = tr("Copied once. The emitters will remain independent.")
	return true

func reset_paint_region() -> void:
	var entry := current_entry()
	if entry.is_empty(): return
	var next := _profile.duplicate(true)
	next.paint = next.paint.filter(func(value: Dictionary) -> bool: return value.slot != entry.slot)
	propose(next)

func propose(next: Dictionary) -> bool:
	# Local GDScript literals use StringName keys; the portable contract requires JSON string keys.
	var json_profile: Dictionary = JSON.parse_string(JSON.stringify(next, "", true, true))
	var checked := Profile.validate(json_profile, _bindings)
	if not checked.ok:
		_error.text = "\n".join(PackedStringArray(checked.errors))
		return false
	var raw := get_editor_state()
	var pending_color := has_pending_color()
	var previous_color := selected_color(current_entry()) if not current_entry().is_empty() else ""
	var pending_marking := has_pending_marking()
	var previous_marking := current_marking()
	_error.text = ""
	_profile = checked.profile
	profile_changed.emit(_profile.duplicate(true))
	sync_fields(false)
	# A different accepted setting must not consume unrelated, uncommitted text.
	var state := get_editor_state()
	if pending_color and raw.slot == state.slot and raw.palette_step == state.palette_step and previous_color == selected_color(current_entry()):
		state.color_text = raw.color_text
	if pending_marking and previous_marking == current_marking():
		state.marking_text = raw.marking_text
		state.marking_color = raw.marking_color
	restore_editor_state(state)
	return true

func build_markings() -> void:
	_marking_box = VBoxContainer.new()
	_marking_box.add_theme_constant_override("separation", 10)
	_controls.add_child(_marking_box)
	_marking_box.add_child(HSeparator.new())
	label("Registration", _marking_box).theme_type_variation = "SectionLabel"
	label("Registration panel", _marking_box)
	_marking_slot = OptionButton.new()
	_marking_slot.name = "RegistrationPanel"
	_marking_slot.fit_to_longest_item = false
	_marking_slot.clip_text = true
	_marking_slot.item_selected.connect(_select_marking_slot)
	_marking_box.add_child(_marking_slot)
	label("Registration text", _marking_box)
	_marking_text = LineEdit.new()
	_marking_text.name = "RegistrationText"
	_marking_text.placeholder_text = "RC-27"
	_marking_text.text_changed.connect(func(_text: String) -> void:
		if not _syncing: validity_changed.emit(page_kind, has_pending_color() or has_pending_marking()))
	_marking_text.text_submitted.connect(func(_text: String) -> void: apply_marking())
	_marking_box.add_child(_marking_text)
	label("Color", _marking_box)
	_marking_color = OptionButton.new()
	for text: String in COLORS: _marking_color.add_item(tr(text))
	_marking_color.add_item("Custom color")
	_marking_color.set_item_disabled(COLORS.size(), true)
	_marking_color.item_selected.connect(func(_index: int) -> void:
		if not _syncing: validity_changed.emit(page_kind, has_pending_color() or has_pending_marking()))
	_marking_box.add_child(_marking_color)
	var apply := Button.new()
	apply.text = tr("Apply inscription")
	apply.pressed.connect(apply_marking)
	_marking_box.add_child(apply)
	label("Up to 12 English or Spanish letters, digits, spaces or hyphens. Empty text removes the inscription.", _marking_box)

func current_marking() -> Dictionary:
	if not is_instance_valid(_marking_slot) or _marking_slot.selected < 0: return {}
	var id := str(_marking_slot.get_item_metadata(_marking_slot.selected))
	for entry: Dictionary in _profile.get("markings", []):
		if entry.slot == id: return entry.duplicate(true)
	return {"slot": id, "text": "", "color": "#FFFFFFFF"}

func sync_markings(refresh_slots := true, notify := true) -> void:
	if not is_instance_valid(_marking_box): return
	_syncing = true
	var slots: Array = _bindings.get("marking_slots", [])
	_marking_box.visible = not slots.is_empty()
	if refresh_slots:
		var selected := _marking_slot.selected
		_marking_slot.clear()
		for slot: Dictionary in slots:
			_marking_slot.add_item(tr(str(slot.label)))
			_marking_slot.set_item_metadata(_marking_slot.item_count - 1, slot.id)
		if not slots.is_empty(): _marking_slot.select(clampi(selected, 0, slots.size() - 1))
	var entry := current_marking()
	if not entry.is_empty():
		_marking_text.max_length = int(slots[_marking_slot.selected].max_chars)
		_marking_text.text = str(entry.text)
		_marking_color.select(COLORS.values().find(entry.color) if entry.color in COLORS.values() else COLORS.size())
	_syncing = false
	_shown_marking = _marking_slot.selected
	if notify: validity_changed.emit(page_kind, has_pending_color() or has_pending_marking())

func has_pending_marking() -> bool:
	if _syncing or not is_instance_valid(_marking_text) or not _marking_box.visible: return false
	var entry := current_marking()
	return not entry.is_empty() and (_marking_text.text != entry.text or (_marking_color.selected < COLORS.size() and COLORS.values()[_marking_color.selected] != entry.color))

func apply_marking() -> void:
	var entry := current_marking()
	if entry.is_empty(): return
	entry.text = _marking_text.text
	if _marking_color.selected < COLORS.size(): entry.color = COLORS.values()[_marking_color.selected]
	var next := _profile.duplicate(true)
	for index in range(next.markings.size() - 1, -1, -1):
		if next.markings[index].slot == entry.slot: next.markings.remove_at(index)
	if not entry.text.is_empty(): next.markings.append(entry)
	if propose(next): sync_markings()

func apply_preset(index: int) -> void:
	var next := _profile.duplicate(true)
	var migration_report: Variant = {}
	if int(next.get("version", Profile.VERSION)) == 1:
		var promotion := _promote_v1_profile(next)
		if not bool(promotion.get("ok", false)):
			_error.text = "\n".join(PackedStringArray(promotion.get("errors", PackedStringArray([tr("Legacy smoke migration is unavailable for this model.")]))))
			return
		next = promotion.profile
		migration_report = promotion.get("report", {})
	next.smoke = []
	var shows: Array = []
	var sources: Array = []
	for slot: Dictionary in _bindings.get("smoke_slots", []):
		# Multi-color presets use the paired tips and tail. Other authored mounts
		# remain selectable individually without exceeding the three-show budget.
		if slot.kind == "show" and slot.get("role", "") in ["wing_tip_left", "wing_tip_right", "tail"]: shows.append(slot)
		elif slot.kind == "source": sources.append(slot)
	if index == 1:
		if propose(next) and not migration_report.is_empty(): _show_migration_note()
		return
	var selected: Array = sources if index == 6 else shows
	if index == 6 and selected.size() > 1:
		selected.resize(1)
	if index == 8:
		selected = shows.filter(func(slot: Dictionary) -> bool: return str(slot.get("pair", "")) == "wing_tips")
	elif index == 9:
		selected = shows.filter(func(slot: Dictionary) -> bool: return str(slot.get("role", "")) == "tail")
		if selected.size() > 1: selected.resize(1)
		if selected.is_empty() and not shows.is_empty(): selected = [shows[0]]
	if selected.is_empty():
		_error.text = tr("This preset needs registered emitters that this model does not provide.")
		return
	var palette := ["#E54646FF", "#FFFFFFFF", "#327DE8FF"]
	var pastel_palette := ["#F7B7CFEE", "#B8E5D6EE", "#BAD7F7EE", "#F8E4A8EE"]
	for i in selected.size():
		var slot: Dictionary = selected[i]
		var is_tail: bool = slot.get("role", "") == "tail"
		if index in [4, 5] and not is_tail: continue
		if index == 2 and str(slot.get("pair", "")) != "wing_tips": continue
		var entry: Dictionary = Profile.smoke_v2_defaults()
		entry.merge({slot = slot.id, enabled = true, color = palette[i % palette.size()], amount = 0.6,
			width_m = 0.15, lifetime_s = 4.0, shape = "ribbon", mode = "hold", burst_s = 0.0,
			pulse_period_s = 0.0, pulse_duty = 0.0, palette = [], step_s = 0.0}, true)
		if index == 2: entry.color = ["#E54646FF", "#327DE8FF"][i % 2]
		if index in [4, 5]:
			entry.merge({color = "#F0B739FF", lifetime_s = 8.0, mode = "burst", burst_s = 5.0}, true)
		if index == 5: entry.merge({palette = palette + ["#40B982FF", "#A871D8FF"], step_s = 0.5, shape = "fan"}, true)
		if index == 6: entry.merge({color = "#FFFFFFFF", amount = 0.35, lifetime_s = 3.0}, true)
		if index == 7:
			entry.merge({color = pastel_palette[i % pastel_palette.size()], density = 0.8,
				shape = "cloud", palette = pastel_palette, palette_mode = "smooth", step_s = 1.1}, true)
		if index == 8:
			entry.merge({color = "#F7B735FF" if i == 0 else "#5EA6F7FF", phase_offset_s = 0.0 if i == 0 else 0.5}, true)
		if index == 9:
			entry.merge({color = "#30343AFF", density = 1.15, emission_rate_hz = 36.0, shape = "cloud"}, true)
		next.smoke.append(entry)
	if next.smoke.is_empty():
		_error.text = tr("This preset needs registered emitters that this model does not provide.")
		return
	if not propose(next): return
	if not migration_report.is_empty(): _show_migration_note()
	if not _profile.smoke.is_empty():
		var first_slot := str(_profile.smoke[0].slot)
		for item in _slot.item_count:
			if _slot.get_item_metadata(item) == first_slot:
				_slot.select(item)
				break
		sync_fields()
