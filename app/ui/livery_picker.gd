## F4U-20-R3: a static gallery. Browsing and keyboard focus never request a 3D model.
extends CanvasLayer
const Screen = preload("res://ui/screen.gd")
const Widgets = preload("res://ui/widgets.gd")
const UiTheme = preload("res://ui/ui_theme.gd")
signal selected(id: String)
signal close_requested
signal create_skin_requested
signal load_skin_requested
var buttons: Array[Button] = []
var cancel_button: Button
var panel: PanelContainer
var scroll: ScrollContainer
var grid: GridContainer
var _screen: Control
var _selected_index := 0
var _chosen := false
var _images: Dictionary[int, TextureRect] = {}
var _paths: Dictionary[int, String] = {}
var _previews: Dictionary = {}
var _pending: Array[int] = []
var _labels: Array[Label] = []
var _font_size := -1
var _focus_columns := 0
var _skin_actions: Array[Button] = []

func _init(choices: Array = [], current := "", aircraft_name := "", previews: Dictionary = {}, shared_theme: Theme = null, custom_skins := false) -> void:
	name = "LiveryPicker"
	layer = 12
	_previews = previews
	_screen = Screen.mount(self, "Modal", shared_theme)
	_font_size = _screen.theme.get_font_size("font_size", "Button")
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
	shell.add_child(Widgets.label("Change skin", "TitleLabel", true))
	shell.add_child(Widgets.label(aircraft_name, "SectionLabel", true, false))
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
		button.add_theme_font_size_override("font_size", _font_size)
		button.clip_text = false
		var path := str(choice.get("thumbnail", ""))
		if path.is_empty():
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.resized.connect(_fit_named_choice.bind(button))
			button.theme_changed.connect(_fit_named_choice.bind(button))
		else:
			_paths[index] = path
			_add_thumbnail(index, button, ("✓ " if active else "") + str(choice.label))
		button.pressed.connect(_choose.bind(str(choice.id)))
		grid.add_child(button)
		buttons.append(button)
	if custom_skins:
		var actions := HFlowContainer.new()
		shell.add_child(actions)
		var create := Widgets.button("Create a skin", "", "CreateSkin")
		create.pressed.connect(func() -> void: create_skin_requested.emit())
		actions.add_child(create)
		var import_skin := Widgets.button("Load new skin…", "", "LoadSkin")
		import_skin.pressed.connect(func() -> void: load_skin_requested.emit())
		actions.add_child(import_skin)
		_skin_actions.assign([create, import_skin])
	cancel_button = Widgets.button("Back")
	cancel_button.pressed.connect(func() -> void: close_requested.emit())
	shell.add_child(cancel_button)
	_screen.resized.connect(_resize)
	_screen.theme_changed.connect(_resize)
	grid.sort_children.connect(_reveal_focused_choice, CONNECT_DEFERRED)
	scroll.resized.connect(_reveal_focused_choice, CONNECT_DEFERRED)
	if _images.is_empty():
		grid.minimum_size_changed.connect(_resize)
		panel.minimum_size_changed.connect(_resize)

func _fit_named_choice(button: Button) -> void:
	# The grid truncates fractional row minima but draws each button at a whole
	# pixel height. Round each row so even the last skin can scroll fully into view.
	button.custom_minimum_size.y = ceilf(button.get_minimum_size().y)

func _reveal_focused_choice() -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and focused.get_parent() == grid:
		scroll.ensure_control_visible(focused)

func _add_thumbnail(index: int, button: Button, caption: String) -> void:
	# The native button keeps its accessible name. The visible caption wraps below the image.
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
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(picture)
	_images[index] = picture
	var label := Widgets.label(caption, "", true, false)
	label.add_theme_font_size_override("font_size", _font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(label)
	_labels.append(label)
	content.minimum_size_changed.connect(func() -> void: button.custom_minimum_size.y = content.get_combined_minimum_size().y + 16)

func _ready() -> void:
	_resize()
	_focus_selected.call_deferred()
	for index: int in _paths:
		if _previews.has(_paths[index]): _images[index].texture = _previews[_paths[index]]
		else: _pending.append(index)
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
	if not is_inside_tree() or is_queued_for_deletion(): return
	await get_tree().process_frame
	if not is_inside_tree() or is_queued_for_deletion(): return
	if buttons.is_empty(): cancel_button.grab_focus()
	else:
		buttons[_selected_index].grab_focus()
		scroll.ensure_control_visible(buttons[_selected_index])

func _resize() -> void:
	if not is_inside_tree(): return
	var available := _screen.size - Vector2(48, 48)
	if _images.is_empty():
		grid.columns = 1
		panel.custom_minimum_size = Vector2(minf(720 * UiTheme.text_scale, available.x),
			minf(available.y, ceilf(panel.get_minimum_size().y + grid.get_combined_minimum_size().y)))
	else:
		panel.custom_minimum_size = Vector2(minf(1320, available.x), minf(930, available.y))
		grid.columns = (5 if panel.custom_minimum_size.x >= 1180 else 4) if UiTheme.text_scale < 1.5 else 2
		for picture: TextureRect in _images.values():
			picture.custom_minimum_size.y = 128 if UiTheme.text_scale < 1.5 else 56
	# Theme replacement also happens on a live viewport/compact-layout change.
	# Explicit card font overrides must follow it, not retain the opening size.
	var font_size := _screen.theme.get_font_size("font_size", "Button")
	if _font_size != font_size:
		_font_size = font_size
		for button in buttons:
			button.add_theme_font_size_override("font_size", font_size)
		for label in _labels:
			label.add_theme_font_size_override("font_size", font_size)
	if _focus_columns != grid.columns:
		_focus_columns = grid.columns
		_sync_focus()

func _sync_focus() -> void:
	var footer: Array[Button] = _skin_actions.duplicate()
	footer.append(cancel_button)
	for index in buttons.size():
		var button := buttons[index]
		button.focus_neighbor_left = button.get_path_to(buttons[index - 1] if index % grid.columns > 0 else button)
		button.focus_neighbor_right = button.get_path_to(buttons[index + 1] if index % grid.columns < grid.columns - 1 and index + 1 < buttons.size() else button)
		button.focus_neighbor_top = button.get_path_to(buttons[index - grid.columns] if index >= grid.columns else button)
		button.focus_neighbor_bottom = button.get_path_to(buttons[index + grid.columns] if index + grid.columns < buttons.size() else footer[0])
		button.focus_previous = button.get_path_to(buttons[index - 1] if index > 0 else cancel_button)
		button.focus_next = button.get_path_to(buttons[index + 1] if index + 1 < buttons.size() else footer[0])
	for index in footer.size():
		footer[index].focus_next = footer[index].get_path_to(footer[index + 1] if index + 1 < footer.size() else buttons[0] if not buttons.is_empty() else footer[0])
		footer[index].focus_previous = footer[index].get_path_to(footer[index - 1] if index > 0 else buttons.back() if not buttons.is_empty() else cancel_button)
	if not buttons.is_empty():
		cancel_button.focus_neighbor_top = cancel_button.get_path_to(buttons.back())
		cancel_button.focus_next = cancel_button.get_path_to(buttons[0])

func _choose(id: String) -> void:
	if _chosen: return
	_chosen = true
	selected.emit(id)
