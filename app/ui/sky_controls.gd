## FW-78: detached sky draft shared by Home and the paused visual editor.
extends VBoxContainer

const SkyConfig := preload("res://environment/sky_appearance_config.gd")
const Widgets := preload("res://ui/widgets.gd")
signal focus_order_changed
signal night_requested

const MOTIONS := ["legacy", "follow_wind", "still", "aloft"]
const MOTION_LABELS := ["Classic motion", "Follow wind", "Still", "Wind aloft"]
const FLASHES := ["full", "reduced", "off"]
const FLASH_LABELS := ["Full", "Reduced", "Off"]
var draft: Dictionary
var preset_buttons: Dictionary = {}
var motion_picker: OptionButton
var flash_picker: OptionButton
var speed_input: SpinBox
var direction_input: SpinBox
var volume_input: HSlider
var night_button: Button
var _aloft: VBoxContainer
var _storm: VBoxContainer
var _description: Label
var _changing := false


func _init(initial: Variant = null) -> void:
	name = "SkyControls"
	add_theme_constant_override("separation", 12)
	var checked: Dictionary = SkyConfig.validate(SkyConfig.defaults() if initial == null else initial)
	draft = checked.config if checked.ok else SkyConfig.defaults()
	add_child(Widgets.label("Choose the cloudscape. Time and flight wind stay as selected.", "SecondaryLabel", true))
	var gallery := GridContainer.new()
	gallery.name = "SkyGallery"
	gallery.columns = 2
	gallery.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gallery.add_theme_constant_override("h_separation", 12)
	gallery.add_theme_constant_override("v_separation", 10)
	add_child(gallery)
	for entry: Dictionary in SkyConfig.presets():
		var card := Button.new()
		card.name = "Sky_" + str(entry.id)
		card.toggle_mode = true
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(300, 128)
		card.tooltip_text = str(entry.description)
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 8
		content.offset_top = 8
		content.offset_right = -8
		content.offset_bottom = -8
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(content)
		var picture := TextureRect.new()
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		picture.custom_minimum_size.y = 82
		picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var image_path: String = "res://assets/sky/weather/previews/%s.png" % entry.id
		if ResourceLoader.exists(image_path):
			picture.texture = load(image_path) as Texture2D
		content.add_child(picture)
		var label := Widgets.label(str(entry.name), "", false)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(label)
		card.pressed.connect(select_preset.bind(str(entry.id)))
		gallery.add_child(card)
		preset_buttons[str(entry.id)] = card
	_description = Widgets.label("", "SecondaryLabel", true)
	_description.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_description)
	motion_picker = _picker("Cloud motion", MOTION_LABELS)
	motion_picker.name = "CloudMotion"
	motion_picker.item_selected.connect(_motion_selected)
	_aloft = VBoxContainer.new()
	add_child(_aloft)
	speed_input = _number(_aloft, "Wind aloft speed (m/s)", 0.0, 50.0, 0.1)
	direction_input = _number(_aloft, "Wind aloft direction FROM (°)", 0.0, 359.0, 1.0)
	speed_input.value_changed.connect(func(value: float) -> void: draft.wind_aloft_speed_mps = value)
	direction_input.value_changed.connect(func(value: float) -> void: draft.wind_aloft_from_deg = value)
	add_child(Widgets.label("Still freezes cloud movement. Flight wind and storm flashes have separate controls.", "SecondaryLabel", true))
	_storm = VBoxContainer.new()
	_storm.add_theme_constant_override("separation", 10)
	add_child(_storm)
	flash_picker = _picker("Flashes", FLASH_LABELS, _storm)
	flash_picker.name = "StormFlashes"
	flash_picker.item_selected.connect(func(index: int) -> void: draft.flashes = FLASHES[index])
	_storm.add_child(Widgets.label("Thunder volume", "SecondaryLabel"))
	volume_input = HSlider.new()
	volume_input.name = "ThunderVolume"
	volume_input.max_value = 1.0
	volume_input.step = 0.05
	volume_input.custom_minimum_size.y = 30
	volume_input.value_changed.connect(func(value: float) -> void: draft.thunder_volume = value)
	_storm.add_child(volume_input)
	night_button = Button.new()
	night_button.name = "ViewStormAtNight"
	night_button.text = "View at night"
	night_button.pressed.connect(func() -> void: night_requested.emit())
	_storm.add_child(night_button)
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh()


func select_preset(id: String) -> void:
	var next: Dictionary = SkyConfig.for_preset(id)
	if next.is_empty():
		return
	# Shape selection does not discard an explicitly chosen motion, seed or audio preference.
	next.seed = draft.seed
	next.motion = draft.motion if draft.motion != "legacy" or id == "classic" else "follow_wind"
	next.wind_aloft_speed_mps = draft.wind_aloft_speed_mps
	next.wind_aloft_from_deg = draft.wind_aloft_from_deg
	next.flashes = draft.flashes
	next.thunder_volume = draft.thunder_volume
	draft = next
	_refresh()


func read_draft() -> Dictionary:
	speed_input.apply()
	direction_input.apply()
	return SkyConfig.validate(draft)


func focus_controls() -> Array[Control]:
	var result: Array[Control] = []
	for button: Button in preset_buttons.values():
		result.append(button)
	result.append(motion_picker)
	if _aloft.visible:
		result.append(speed_input.get_line_edit())
		result.append(direction_input.get_line_edit())
	if _storm.visible:
		result.append(flash_picker)
		result.append(volume_input)
		if not night_button.disabled:
			result.append(night_button)
	return result


func _motion_selected(index: int) -> void:
	if _changing:
		return
	draft.motion = MOTIONS[index]
	_refresh()


func _refresh() -> void:
	_changing = true
	for entry: Dictionary in SkyConfig.presets():
		var button: Button = preset_buttons[str(entry.id)]
		button.set_pressed_no_signal(entry.id == draft.preset)
		button.tooltip_text = tr(str(entry.description))
		button.accessibility_name = tr(str(entry.name))
		button.accessibility_description = button.tooltip_text
		if entry.id == draft.preset:
			_description.text = tr(str(entry.description))
	for index: int in MOTION_LABELS.size():
		motion_picker.set_item_text(index, tr(MOTION_LABELS[index]))
	motion_picker.select(MOTIONS.find(draft.motion))
	# Legacy drift belongs only to the original appearance.
	motion_picker.set_item_disabled(0, draft.preset != "classic")
	_aloft.visible = draft.motion == "aloft"
	speed_input.set_value_no_signal(float(draft.wind_aloft_speed_mps))
	direction_input.set_value_no_signal(float(draft.wind_aloft_from_deg))
	_storm.visible = draft.preset == "electrical_storm"
	for index: int in FLASH_LABELS.size():
		flash_picker.set_item_text(index, tr(FLASH_LABELS[index]))
	flash_picker.select(FLASHES.find(draft.flashes))
	volume_input.set_value_no_signal(float(draft.thunder_volume))
	_changing = false
	focus_order_changed.emit()


func _picker(label_text: String, options: Array, parent: VBoxContainer = null) -> OptionButton:
	if parent == null:
		parent = self
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(Widgets.label(label_text, "SecondaryLabel"))
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for option: String in options:
		picker.add_item(tr(option))
	row.add_child(picker)
	parent.add_child(row)
	return picker


func _number(parent: VBoxContainer, label_text: String, minimum: float, maximum: float, increment: float) -> SpinBox:
	var row := HBoxContainer.new()
	var label := Widgets.label(label_text, "SecondaryLabel")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = increment
	input.custom_minimum_size.x = 150.0
	row.add_child(input)
	parent.add_child(row)
	return input
