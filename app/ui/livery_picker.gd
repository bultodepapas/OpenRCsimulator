## F4U-20-R3: a static gallery. Browsing and keyboard focus never request a 3D model.
extends CanvasLayer
const Screen = preload("res://ui/screen.gd")
const Widgets = preload("res://ui/widgets.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
signal selected(id: String)
signal close_requested
var buttons: Array[Button] = []
var cancel_button: Button
var panel: PanelContainer
var scroll: ScrollContainer
var grid: GridContainer
var _screen: Control
var _selected_index := 0
var _chosen := false
var _images: Array[TextureRect] = []
var _paths: Array[String] = []
var _previews: Dictionary = {}
var _pending: Array[int] = []

func _init(choices: Array = [], current := "", aircraft_name := "", previews: Dictionary = {}) -> void:
	name = "LiveryPicker"
	layer = 12
	_previews = previews
	_screen = Screen.mount(self, "Modal")
	_screen.escape_before_gui = true
	_screen.close_requested.connect(func() -> void: close_requested.emit())
	_screen.dim(0.70)
	var center: CenterContainer = _screen.center(24)
	panel = PanelContainer.new()
	panel.theme_type_variation = "Card"
	center.add_child(panel)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	panel.add_child(shell)
	shell.add_child(Widgets.label("Paint schemes", "TitleLabel", true))
	shell.add_child(Widgets.label(aircraft_name, "SectionLabel", true, false))
	shell.add_child(Widgets.label("Choose a paint for your next flight.", "SecondaryLabel", true))
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	shell.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for index in choices.size():
		var choice: Dictionary = choices[index]
		var active: bool = choice.id == current or current.is_empty() and index == 0
		if active: _selected_index = index
		var button := Widgets.button(str(choice.label), "PrimaryButton" if active else "", "Skin_" + str(choice.id))
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.text = str(choice.label) + ("\n" + tr("Selected") if active else "")
		button.tooltip_text = str(choice.label)
		button.set_meta("livery_id", str(choice.id))
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", _screen.theme.get_font_size("font_size", "Button"))
		button.clip_text = false
		# Keep the Button's text for accessibility and automation. A real layout
		# draws the name below a fixed image area, so long names cannot clip or shrink it.
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			button.add_theme_color_override(state, Color.TRANSPARENT)
		var content := VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(content)
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 8
		content.offset_right = -8
		content.offset_top = 8
		content.offset_bottom = -8
		var picture := TextureRect.new()
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size.y = 104
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(picture)
		_images.append(picture)
		_paths.append(str(choice.get("thumbnail", "")))
		var label := Widgets.label(("✓ " if active else "") + str(choice.label), "", true, false)
		label.add_theme_font_size_override("font_size", _screen.theme.get_font_size("font_size", "Button"))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(label)
		content.minimum_size_changed.connect(func() -> void: button.custom_minimum_size.y = content.get_combined_minimum_size().y + 16)
		button.pressed.connect(_choose.bind(str(choice.id)))
		grid.add_child(button)
		buttons.append(button)
	cancel_button = Widgets.button("Back")
	cancel_button.pressed.connect(func() -> void: close_requested.emit())
	shell.add_child(cancel_button)
	_screen.resized.connect(_resize)
	_screen.theme_changed.connect(_resize)

func _ready() -> void:
	_resize()
	_focus_selected.call_deferred()
	for index in buttons.size():
		if _previews.has(_paths[index]): _images[index].texture = _previews[_paths[index]]
		elif not _paths[index].is_empty(): _pending.append(index)
	if _pending.has(_selected_index):
		_pending.erase(_selected_index)
		_pending.push_front(_selected_index)
	if not _pending.is_empty(): get_tree().process_frame.connect(_load_next_preview, CONNECT_ONE_SHOT)

func _load_next_preview() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or _pending.is_empty(): return
	# One small texture per frame: opening the gallery never synchronously uploads
	# thirteen textures. Home owns a bounded cache for reopening this aircraft's gallery.
	var index: int = _pending.pop_front()
	var texture := load(_paths[index]) as Texture2D
	_images[index].texture = texture
	_previews[_paths[index]] = texture
	if not _pending.is_empty(): get_tree().process_frame.connect(_load_next_preview, CONNECT_ONE_SHOT)

func _focus_selected() -> void:
	await get_tree().process_frame
	if not is_inside_tree(): return
	if buttons.is_empty(): cancel_button.grab_focus()
	else:
		buttons[_selected_index].grab_focus()
		scroll.ensure_control_visible(buttons[_selected_index])

func _resize() -> void:
	if not is_inside_tree(): return
	var available := _screen.size - Vector2(48, 48)
	panel.custom_minimum_size = Vector2(minf(1320, available.x), minf(930, available.y))
	grid.columns = (5 if panel.custom_minimum_size.x >= 1180 else 4) if UiTheme.text_scale < 1.5 else 2
	for picture in _images:
		picture.custom_minimum_size.y = 104 if UiTheme.text_scale < 1.5 else 56
	_sync_focus()

func _sync_focus() -> void:
	for index in buttons.size():
		var button := buttons[index]
		button.focus_neighbor_left = button.get_path_to(buttons[index - 1] if index % grid.columns > 0 else button)
		button.focus_neighbor_right = button.get_path_to(buttons[index + 1] if index % grid.columns < grid.columns - 1 and index + 1 < buttons.size() else button)
		button.focus_neighbor_top = button.get_path_to(buttons[index - grid.columns] if index >= grid.columns else button)
		button.focus_neighbor_bottom = button.get_path_to(buttons[index + grid.columns] if index + grid.columns < buttons.size() else cancel_button)
		button.focus_previous = button.get_path_to(buttons[index - 1] if index > 0 else cancel_button)
		button.focus_next = button.get_path_to(buttons[index + 1] if index + 1 < buttons.size() else cancel_button)
	if not buttons.is_empty():
		cancel_button.focus_neighbor_top = cancel_button.get_path_to(buttons.back())
		cancel_button.focus_next = cancel_button.get_path_to(buttons[0])
		cancel_button.focus_previous = cancel_button.get_path_to(buttons.back())

func _choose(id: String) -> void:
	if _chosen: return
	_chosen = true
	selected.emit(id)
