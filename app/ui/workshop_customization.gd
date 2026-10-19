extends VBoxContainer
## Capability-driven inspector. Emits complete proposals; its owner validates and records one shared history.
const Profile := preload("res://workshop/presentation.gd")
signal profile_changed(profile: Dictionary)
const COLORS := {"White":"#FFFFFFFF", "Red":"#E54646FF", "Blue":"#327DE8FF", "Gold":"#F0B739FF", "Green":"#40B982FF", "Purple":"#A871D8FF", "Black":"#20252BFF"}
var page_kind := "appearance"
var _bindings: Dictionary = {}
var _profile: Dictionary = {}
var _slot: OptionButton
var _color: OptionButton
var _custom_color: LineEdit
var _error: Label
var _enabled: CheckButton
var _shape: OptionButton
var _mode: OptionButton
var _fields: Dictionary = {}
var _controls: VBoxContainer
var _note: Label
var _syncing := false

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var heading := Label.new()
	heading.text = "Appearance" if page_kind == "appearance" else "Smoke"
	heading.theme_type_variation = "SectionLabel"
	add_child(heading)
	_note = label("Paint changes only the selected registered region." if page_kind == "appearance" else "Show smoke is a visual effect. Source exhaust follows the running engine.")
	if page_kind == "smoke":
		var presets := OptionButton.new()
		presets.name = "SmokePreset"
		for text: String in ["Choose a smoke preset…", "Clear Trainer", "Twin Ribbons", "Tricolor", "Tail Comet", "Rainbow Burst", "Classic Exhaust"]: presets.add_item(text)
		presets.item_selected.connect(func(index: int) -> void:
			if index > 0: apply_preset(index)
			presets.select(0))
		add_child(presets)
	_slot = OptionButton.new()
	_slot.name = "PaintRegion" if page_kind == "appearance" else "SmokeEmitter"
	_slot.fit_to_longest_item = false
	_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slot.item_selected.connect(func(_index: int) -> void: sync_fields())
	add_child(_slot)
	_controls = VBoxContainer.new()
	_controls.add_theme_constant_override("separation", 10)
	add_child(_controls)
	if page_kind == "smoke":
		_enabled = CheckButton.new()
		_enabled.text = "Enable this emitter"
		_enabled.toggled.connect(func(value: bool) -> void: change("enabled", value))
		_controls.add_child(_enabled)
	_color = OptionButton.new()
	for text: String in COLORS: _color.add_item(text)
	_color.add_item("Custom color")
	_color.item_selected.connect(func(index: int) -> void:
		if index < COLORS.size(): change("color", COLORS.values()[index]))
	_controls.add_child(_color)
	var custom := HBoxContainer.new()
	_custom_color = LineEdit.new()
	_custom_color.name = "PresentationColor"
	_custom_color.placeholder_text = "#RRGGBBAA"
	_custom_color.max_length = 9
	_custom_color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_custom_color.text_submitted.connect(func(_value: String) -> void: apply_color())
	custom.add_child(_custom_color)
	var apply := Button.new()
	apply.text = "Apply color"
	apply.pressed.connect(apply_color)
	custom.add_child(apply)
	_controls.add_child(custom)
	if page_kind == "smoke":
		number_field("amount", "Amount", 0.0, 1.0, 0.05, "×")
		number_field("width_m", "Width", 0.01, 2.0, 0.01, "m")
		number_field("lifetime_s", "Puff lifetime", 0.1, 8.0, 0.1, "s")
		_shape = options("Shape", ["ribbon", "fan"])
		_shape.item_selected.connect(func(index: int) -> void: change("shape", ["ribbon", "fan"][index]))
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
		label("Duration controls new emission; existing puffs fade for their full lifetime.", _controls)
	_error = label("")
	_error.theme_type_variation = "ErrorLabel"
	configure(_bindings, _profile)

func label(text: String, parent: Node = self) -> Label:
	var result := Label.new()
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(result)
	return result

func options(title: String, values: Array) -> OptionButton:
	label(title, _controls)
	var result := OptionButton.new()
	for value: String in values: result.add_item(value.capitalize())
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
	value.value_changed.connect(func(next: float) -> void: change(key, next))
	row.add_child(value)
	_controls.add_child(row)
	_fields[key] = value

func configure(bindings: Dictionary, profile: Dictionary) -> void:
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
	if _slot.item_count == 0:
		_slot.add_item("No registered regions" if page_kind == "appearance" else "No registered emitters")
		_note.text = "This model has no registered customization for this page."
	_syncing = false
	sync_fields()

func current_entry() -> Dictionary:
	if _slot.item_count == 0 or _slot.get_item_metadata(_slot.selected) == null: return {}
	var id := str(_slot.get_item_metadata(_slot.selected))
	for entry: Dictionary in _profile.get("paint" if page_kind == "appearance" else "smoke", []):
		if entry.slot == id: return entry.duplicate(true)
	if page_kind == "appearance": return {slot = id, color = "#FFFFFFFF", pattern = "solid", accent = "none"}
	return {slot = id, enabled = false, color = "#FFFFFFFF", amount = 0.5, width_m = 0.12,
		lifetime_s = 3.0, shape = "ribbon", mode = "hold", burst_s = 0.0,
		pulse_period_s = 0.0, pulse_duty = 0.0, palette = [], step_s = 0.0}

func sync_fields() -> void:
	if not is_instance_valid(_custom_color): return
	var entry := current_entry()
	if entry.is_empty(): return
	_syncing = true
	_custom_color.text = entry.color
	_color.select(COLORS.values().find(entry.color) if entry.color in COLORS.values() else COLORS.size())
	if page_kind == "smoke":
		_enabled.set_pressed_no_signal(entry.enabled)
		_shape.select(["ribbon", "fan"].find(entry.shape))
		_mode.select(["hold", "burst", "pulse"].find(entry.mode))
		for key: String in _fields:
			_fields[key].set_value_no_signal(entry[key])
			_fields[key].editable = (key != "burst_s" or entry.mode == "burst") and (key not in ["pulse_period_s", "pulse_duty"] or entry.mode == "pulse")
	_syncing = false

func change(key: String, value: Variant) -> void:
	if _syncing: return
	var entry := current_entry()
	if entry.is_empty(): return
	entry[key] = value
	commit_entry(entry)

func apply_color() -> void:
	var text := _custom_color.text.to_upper()
	if text.length() != 9 or not text.begins_with("#") or not text.substr(1).is_valid_hex_number():
		_error.text = "Use #RRGGBBAA, for example #327DE8FF."
		return
	change("color", text)

func commit_entry(entry: Dictionary) -> void:
	var next := _profile.duplicate(true)
	var key := "paint" if page_kind == "appearance" else "smoke"
	var entries: Array = next.get(key, []).duplicate(true)
	for i in range(entries.size() - 1, -1, -1):
		if entries[i].slot == entry.slot: entries.remove_at(i)
	entries.append(entry)
	next[key] = entries
	propose(next)

func propose(next: Dictionary) -> void:
	var checked := Profile.validate(next, _bindings)
	if not checked.ok:
		_error.text = "\n".join(PackedStringArray(checked.errors))
		return
	_error.text = ""
	_profile = checked.profile
	profile_changed.emit(_profile.duplicate(true))
	sync_fields()

func apply_preset(index: int) -> void:
	var next := _profile.duplicate(true)
	next.smoke = []
	var shows: Array = []
	var sources: Array = []
	for slot: Dictionary in _bindings.get("smoke_slots", []):
		if slot.kind == "show": shows.append(slot)
		elif slot.kind == "source": sources.append(slot)
	if index == 1:
		propose(next)
		return
	var selected: Array = sources if index == 6 else shows
	if selected.is_empty():
		_error.text = "This preset needs registered emitters that this model does not provide."
		return
	var palette := ["#E54646FF", "#FFFFFFFF", "#327DE8FF"]
	for i in selected.size():
		var slot: Dictionary = selected[i]
		var is_tail: bool = slot.get("pair", "") == "tail"
		if index in [4, 5] and not is_tail: continue
		if index == 2 and str(slot.get("pair", "")) != "wing_tips": continue
		var entry := {slot = slot.id, enabled = true, color = palette[i % palette.size()], amount = 0.6,
			width_m = 0.15, lifetime_s = 4.0, shape = "ribbon", mode = "hold", burst_s = 0.0,
			pulse_period_s = 0.0, pulse_duty = 0.0, palette = [], step_s = 0.0}
		if index == 2: entry.color = ["#E54646FF", "#327DE8FF"][i % 2]
		if index in [4, 5]:
			entry.merge({color = "#F0B739FF", lifetime_s = 8.0, mode = "burst", burst_s = 5.0}, true)
		if index == 5: entry.merge({palette = palette + ["#40B982FF", "#A871D8FF"], step_s = 0.5, shape = "fan"}, true)
		if index == 6: entry.merge({color = "#FFFFFFFF", amount = 0.35, lifetime_s = 3.0}, true)
		next.smoke.append(entry)
	if next.smoke.is_empty():
		_error.text = "This preset needs registered emitters that this model does not provide."
		return
	propose(next)
