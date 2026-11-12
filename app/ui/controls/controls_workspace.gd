# UI-15-UX-03/04: presentation glue for the Controls workspace in controller_setup.gd. It owns the left device rail
# (one DeviceCard per device, Keyboard always last), the device picture panel and the picture's live input.
# The host decides everything that matters: which cards exist, their statuses, which device is selected, how a card
# activation changes the draft (through the same path as the flight device picker) and which control an action row
# highlights. This node never reads profiles from storage, never captures input and never changes a binding.
# Live input uses the host's preview readers (the same axis/button preview providers as the Flight axes and Extra
# channels tabs) only while the picture is visible, at most every SAMPLE_INTERVAL; buffers are preallocated and the
# picture and binding chips redraw only when a sample changes.
extends Node

const UiTheme := preload("res://ui/ui_theme.gd")
const Widgets := preload("res://ui/widgets.gd")
const DeviceCard := preload("res://ui/controls/device_card.gd")
const DevicePicture := preload("res://ui/controls/device_picture.gd")

## A card was activated by the player (pointer, keyboard or gamepad). The host applies the selection.
signal card_activated(device_id: int)

const SAMPLE_INTERVAL := 0.04
const AXIS_COUNT := 10
const GAMEPAD_AXES := 6
## Godot JoyButton indices a gamepad picture can show (A … paddles and touchpad).
const GAMEPAD_BUTTONS := 21
const MAX_BUTTONS := 128

var rail: ScrollContainer
var rail_list: VBoxContainer
var picture_panel: PanelContainer
var picture_box: VBoxContainer
var picture: DevicePicture
var picture_title: Label
var picture_hint: Label
## UI-15-UX-05: a host view shown large under the picture (the Flight axes response curve); empty otherwise.
var context_box: VBoxContainer
## (device_id: int, axis: int) -> float and (device_id: int, button: int) -> bool, from the host.
var read_axis := Callable()
var read_button := Callable()
## () -> bool: the host screen is shown (not covered, not hidden). Polling stops otherwise.
var host_visible := Callable()
## Live samples taken since creation (tests prove hidden pictures cost nothing).
var samples := 0

var _cards: Dictionary = {} # device id -> DeviceCard
var _device_id := -1
var _kind := "keyboard"
var _axis_list := PackedInt32Array()
var _picture_buttons := PackedInt32Array()
var _button_list := PackedInt32Array()
var _axes := PackedFloat64Array()
var _pressed := PackedByteArray()
var _held_keys: Dictionary = {}
var _chips: Dictionary = {} # control id ("button:3", "key:65") -> Array of BindingChip
var _focus_id := ""
var _hover_id := ""
var _capture_id := ""
var _clock := 0.0


func _init() -> void:
	name = "ControlsWorkspace"
	_axes.resize(AXIS_COUNT)
	_axes.fill(0.0)
	_pressed.resize(MAX_BUTTONS)
	_pressed.fill(0)
	rail = ScrollContainer.new()
	rail.name = "DeviceRail"
	rail.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rail.follow_focus = true
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_list = VBoxContainer.new()
	rail_list.name = "DeviceCards"
	rail_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail_list.add_theme_constant_override("separation", 10)
	rail.add_child(rail_list)
	var heading := Widgets.label("DEVICES", "SectionLabel")
	heading.name = "DeviceRailHeading"
	rail_list.add_child(heading)
	picture_panel = PanelContainer.new()
	picture_panel.name = "DevicePicturePanel"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.CARD, 0.55)
	style.border_color = Color(UiTheme.SURFACE_LIGHT, 0.14)
	style.set_border_width_all(1)
	style.set_corner_radius_all(UiTheme.RADIUS + 3)
	style.set_content_margin_all(12.0)
	picture_panel.add_theme_stylebox_override("panel", style)
	picture_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	picture_box = VBoxContainer.new()
	picture_box.name = "DevicePictureBox"
	picture_box.add_theme_constant_override("separation", 12)
	picture_panel.add_child(picture_box)
	var info := VBoxContainer.new()
	info.name = "DevicePictureInfo"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	# A compact one-line caption: the device name is already on its rail card and in the header.
	picture_title = Widgets.label("", "SectionLabel")
	picture_title.name = "DevicePictureTitle"
	picture_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	picture_title.max_lines_visible = 1
	picture_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.add_child(picture_title)
	picture_box.add_child(info)
	picture = DevicePicture.new()
	picture.name = "DevicePicture"
	picture.custom_minimum_size = Vector2(300.0, 180.0)
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	picture_box.add_child(picture)
	picture.set_device("keyboard")
	picture_hint = Widgets.label("", "SecondaryLabel", true)
	picture_hint.name = "DevicePictureHint"
	picture_hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	picture_box.add_child(picture_hint)
	context_box = VBoxContainer.new()
	context_box.name = "DevicePictureContext"
	context_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	context_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	context_box.visible = false
	picture_box.add_child(context_box)
	# The picture keeps its drawing's aspect at the column width (top-aligned under the title).
	picture_box.resized.connect(_fit_picture_height)


func _fit_picture_height() -> void:
	var width := picture_box.size.x
	if width <= 0.0:
		return
	# The key map is wider than the controller and transmitter drawings.
	var aspect := 0.5 if picture.device_kind() == "keyboard" else DevicePicture.DESIGN.y / DevicePicture.DESIGN.x
	# With a context view below (the response curve) the picture leaves it most of the height.
	var share := 0.4 if context_box.visible else 0.7
	var target := clampf(width * aspect, 160.0, maxf(160.0, picture_panel.size.y * share))
	if absf(picture.custom_minimum_size.y - target) > 1.0:
		picture.custom_minimum_size.y = target


func _process(delta: float) -> void:
	_clock += delta
	if _clock < SAMPLE_INTERVAL:
		return
	_clock = 0.0
	if is_live():
		sample()


## The picture is on screen and the host is shown; nothing is polled otherwise.
func is_live() -> bool:
	if picture == null or not picture.is_visible_in_tree():
		return false
	return not host_visible.is_valid() or bool(host_visible.call())


# --- Rail ---------------------------------------------------------------------------------------------------------

## Entries in display order: {id, name, kind, family, statuses, selected}. Cards are reused by id and rebuilt only
## when the device list changes; focus stays on a reused card.
func set_cards(entries: Array) -> void:
	var wanted: Dictionary = {}
	for entry: Dictionary in entries:
		wanted[int(entry.get("id", -1))] = true
	for id: int in _cards.keys():
		if not wanted.has(id):
			var stale: Button = _cards[id]
			_cards.erase(id)
			stale.queue_free()
			rail_list.remove_child(stale)
	var index := 1 # after the heading
	for entry: Dictionary in entries:
		var id := int(entry.get("id", -1))
		var card: Button = _cards.get(id)
		if card == null:
			card = DeviceCard.new()
			card.name = "DeviceCard_Keyboard" if id < 0 else "DeviceCard_%d" % id
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.pressed.connect(_on_card_pressed.bind(id))
			rail_list.add_child(card)
			_cards[id] = card
		if card.get_index() != index:
			rail_list.move_child(card, index)
		card.display_name = str(entry.get("name", ""))
		card.kind = str(entry.get("kind", "gamepad"))
		card.family = str(entry.get("family", "generic"))
		card.set_statuses(entry.get("statuses", []))
		card.set_selected(bool(entry.get("selected", false)))
		index += 1


func card_for(device_id: int) -> Button:
	return _cards.get(device_id)


func card_ids() -> Array:
	var ids: Array = []
	for child in rail_list.get_children():
		for id: int in _cards:
			if _cards[id] == child:
				ids.append(id)
	return ids


func _on_card_pressed(device_id: int) -> void:
	# A toggle button flips itself; the host's selection is the truth and refreshes every card.
	var card: Button = _cards.get(device_id)
	if card != null:
		card.set_selected(true)
	card_activated.emit(device_id)


# --- Picture --------------------------------------------------------------------------------------------------------

## Show the selected flight device. `kind` is "gamepad", "radio", "joystick" or "keyboard"; `channels` the draft
## profile's flight channels; `lamps` the radio switch row entries (see DevicePicture.set_radio_controls).
func show_device(device_id: int, kind: String, family: String, stick_mode: int, channels: Dictionary, lamps: Array,
		title: String, hint: String, vehicle_type: String) -> void:
	var next_kind := "keyboard" if device_id < 0 else kind
	if device_id != _device_id or next_kind != _kind:
		_clear_live()
	_device_id = device_id
	_kind = next_kind
	picture.set_stick_mode(stick_mode)
	picture.set_radio_channels(channels)
	picture.set_radio_controls(lamps)
	picture.set_vehicle_type(vehicle_type)
	picture.set_device(next_kind, family)
	_fit_picture_height()
	picture_title.text = title
	picture_hint.text = hint
	picture_hint.visible = not hint.is_empty()
	_axis_list = PackedInt32Array()
	_picture_buttons = PackedInt32Array()
	match picture.device_kind():
		"gamepad":
			for axis in GAMEPAD_AXES:
				_axis_list.append(axis)
			for button in GAMEPAD_BUTTONS:
				_picture_buttons.append(button)
		"radio":
			for id in picture.control_ids():
				var number := int(id.get_slice(":", 1))
				if id.begins_with("axis:") and not _axis_list.has(number) and number < AXIS_COUNT:
					_axis_list.append(number)
				elif id.begins_with("button:") and not _picture_buttons.has(number):
					_picture_buttons.append(number)
	_rebuild_button_list()
	_apply_highlight()


func device_kind() -> String:
	return picture.device_kind()


func watched_axes() -> PackedInt32Array:
	return _axis_list


func watched_buttons() -> PackedInt32Array:
	return _button_list


## Binding chips by the control they show ("button:N", "axis:N", "key:K"); pressing that control makes them glow.
func set_chips(chips_by_control: Dictionary) -> void:
	for id: String in _chips:
		for chip: Control in _chips[id]:
			if is_instance_valid(chip) and not chips_by_control.has(id):
				chip.set("live_pressed", false)
	_chips = chips_by_control
	_rebuild_button_list()
	_refresh_chips()


## The control of the focused row ("" for none) and of the hovered row (wins while the pointer is over it).
func set_focus_control(control_id: String) -> void:
	_focus_id = control_id
	_apply_highlight()


func set_hover_control(control_id: String) -> void:
	_hover_id = control_id
	_apply_highlight()


## UI-15-UX-06: the control a running capture has detected so far; wins over hover and focus until cleared.
func set_capture_control(control_id: String) -> void:
	if control_id == _capture_id:
		return
	_capture_id = control_id
	_apply_highlight()


## Show `view` large under the picture (it is reparented here), or none with null. The host owns the view and takes
## it back by reparenting it elsewhere.
func set_context(view: Control) -> void:
	for child in context_box.get_children():
		if child != view:
			context_box.remove_child(child)
	if view != null and view.get_parent() != context_box:
		if view.get_parent() != null:
			view.get_parent().remove_child(view)
		context_box.add_child(view)
	var shown := view != null
	if context_box.visible != shown:
		context_box.visible = shown
		_fit_picture_height.call_deferred()


func _apply_highlight() -> void:
	if not _capture_id.is_empty():
		picture.highlight(_capture_id)
		return
	picture.highlight(_hover_id if not _hover_id.is_empty() else _focus_id)


# --- Live input -----------------------------------------------------------------------------------------------------

## One poll of the watched axes and buttons through the host's readers. Presentation only.
func sample() -> void:
	if _device_id < 0 or _kind == "keyboard":
		return
	samples += 1
	for axis in _axis_list:
		_axes[axis] = _read_axis(axis)
	picture.set_axes(_axes)
	var changed := false
	for button in _button_list:
		var down := 1 if _read_button(button) else 0
		if _pressed[button] != down:
			_pressed[button] = down
			changed = true
	if changed:
		var shown: Array[int] = []
		for button in _picture_buttons:
			if button < MAX_BUTTONS and _pressed[button] == 1:
				shown.append(button)
		picture.set_pressed_buttons(shown)
		_refresh_chips()


func is_button_down(button: int) -> bool:
	return button >= 0 and button < MAX_BUTTONS and _pressed[button] == 1


func _read_axis(axis: int) -> float:
	if not read_axis.is_valid():
		return 0.0
	var value: Variant = read_axis.call(_device_id, axis)
	return float(value) if typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)) else 0.0


func _read_button(button: int) -> bool:
	if not read_button.is_valid():
		return false
	var value: Variant = read_button.call(_device_id, button)
	return value if typeof(value) == TYPE_BOOL else false


## Keyboard keys are observed from events (never polled) and never consumed.
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or (event as InputEventKey).echo:
		return
	var key := event as InputEventKey
	var physical := int(key.physical_keycode) if key.physical_keycode != KEY_NONE else int(key.keycode)
	if physical == KEY_NONE or (key.pressed == _held_keys.has(physical)):
		return
	if key.pressed:
		if not is_live():
			return
		_held_keys[physical] = true
	else:
		_held_keys.erase(physical)
	if _kind == "keyboard":
		picture.set_pressed_keys(_held_keys.keys())
	_refresh_chips()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _held_keys.is_empty():
		_held_keys.clear()
		picture.set_pressed_keys([])
		_refresh_chips()


func _clear_live() -> void:
	_pressed.fill(0)
	_axes.fill(0.0)
	_held_keys.clear()
	picture.set_axes(_axes)
	picture.set_pressed_buttons([])
	picture.set_pressed_keys([])
	_refresh_chips()


func _rebuild_button_list() -> void:
	var next := _picture_buttons.duplicate()
	if _kind != "keyboard":
		for id: String in _chips:
			if id.begins_with("button:"):
				var button := int(id.get_slice(":", 1))
				if button >= 0 and button < MAX_BUTTONS and not next.has(button):
					next.append(button)
	_button_list = next


## Runs only when a sample or key event changed something; a switch chip listed under several buttons glows when
## any of them is down.
func _refresh_chips() -> void:
	var lit: Dictionary = {}
	for id: String in _chips:
		var down := false
		if id.begins_with("button:"):
			down = _kind != "keyboard" and is_button_down(int(id.get_slice(":", 1)))
		elif id.begins_with("key:"):
			down = _held_keys.has(int(id.get_slice(":", 1)))
		if down:
			for chip: Control in _chips[id]:
				lit[chip] = true
	for id: String in _chips:
		for chip: Control in _chips[id]:
			if is_instance_valid(chip):
				chip.set("live_pressed", lit.has(chip))
