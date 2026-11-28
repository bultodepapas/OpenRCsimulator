extends AcceptDialog
## The importer previews and installs local photos through the Home screen.

signal flight_requested(revision: String)

const Source = preload("res://landscapes/phoenix_source.gd")
const Library = preload("res://landscapes/phoenix_library.gd")
const Panorama = preload("res://ui/phoenix_panorama.gdshader")
const PANEL_YAW := [0.0, PI / 2.0, PI, -PI / 2.0, 0.0, 0.0]
const PANEL_PITCH := [0.0, 0.0, 0.0, 0.0, PI / 2.0, -PI / 2.0]
## UI-40q (UI-40 I-2): where each photo panel looks (yaw +90° turns right, pitch +90° looks up; see the panorama shader).
const PANEL_NAMES := ["Ahead", "Right", "Behind", "Left", "Sky", "Ground"]

var library_root := Library.ROOT
var _files: FileDialog
var _folder_button: Button
var _file_button: Button
var _stop_button: Button
var _search: LineEdit
var _sites: ItemList
var _photo: TextureRect
var _panorama: ShaderMaterial
var _bearing := Vector2.ZERO
var _dragging := false
var _caption: Label
var _status: Label
var _install: Button
var _remove: Button
var _fly: Button
var _face_buttons: Array[Button] = []
var _source_sites: Array = []
var _installed_sites: Array[Dictionary] = []
var _selection := {}
var _preview := {}
var _worker: Thread
var _mutex := Mutex.new()
var _cancelled := false
var _job := ""


func _ready() -> void:
	title = tr("Import scenery")
	ok_button_text = tr("Close")
	transient = true
	exclusive = true
	set_meta("landscape_import_popup", true)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 9)
	add_child(body)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	_folder_button = _button(actions, "Choose folder", _choose_source.bind(true))
	_file_button = _button(actions, "Choose file", _choose_source.bind(false))
	_stop_button = _button(actions, "Cancel operation", _cancel_operation)
	_stop_button.hide()

	var columns := HSplitContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(columns)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 230
	columns.add_child(sidebar)
	_search = LineEdit.new()
	_search.name = "SearchScenery"
	_search.placeholder_text = tr("Search scenery")
	_search.text_changed.connect(func(_query: String) -> void: _populate())
	sidebar.add_child(_search)
	_sites = ItemList.new()
	_sites.name = "SceneryResults"
	_sites.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sites.item_selected.connect(_select)
	sidebar.add_child(_sites)

	var preview_column := VBoxContainer.new()
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(preview_column)
	_caption = Label.new()
	_caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	preview_column.add_child(_caption)
	_photo = TextureRect.new()
	_photo.name = "SceneryPanel"
	_photo.custom_minimum_size = Vector2(170, 150)
	_photo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_photo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_photo.mouse_filter = Control.MOUSE_FILTER_STOP
	_photo.gui_input.connect(_aim_preview)
	_photo.resized.connect(_update_orientation)
	preview_column.add_child(_photo)
	var panels := HBoxContainer.new()
	panels.alignment = BoxContainer.ALIGNMENT_CENTER
	preview_column.add_child(panels)
	var group := ButtonGroup.new()
	for index in 6:
		var button := _button(panels, tr(PANEL_NAMES[index]), _show_panel.bind(index))
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = tr("Look toward panel %d") % (index + 1)
		button.disabled = true
		_face_buttons.append(button)

	_status = Label.new()
	_status.name = "SceneryStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 2
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.text = tr("Choose a scenery file or folder from the Phoenix RC simulator, or reopen an installed preview.")
	body.add_child(_status)
	var install_actions := HBoxContainer.new()
	body.add_child(install_actions)
	_install = _button(install_actions, "Install preview", _install_preview)
	_remove = _button(install_actions, "Remove preview", _confirm_remove)
	_fly = _button(install_actions, "Fly calibrated runway", _fly_selected)
	_fly.name = "FlyImportedScenery"
	_fly.tooltip_text = tr("Experimental flight in calm air with an estimated runway, start and ground.")

	_files = FileDialog.new()
	_files.set_meta("landscape_import_popup", true)
	_files.access = FileDialog.ACCESS_FILESYSTEM
	_files.file_selected.connect(scan_source)
	_files.dir_selected.connect(scan_source)
	add_child(_files)
	visibility_changed.connect(_on_visibility_changed)
	_set_busy(false)
	set_process(false)


func open_browser() -> void:
	title = tr("Import scenery")
	ok_button_text = tr("Close")
	_search.placeholder_text = tr("Search scenery")
	if _selection.is_empty() and _worker == null:
		_status.text = tr("Choose a scenery file or folder from the Phoenix RC simulator, or reopen an installed preview.")
	for index in _face_buttons.size():
		_face_buttons[index].text = tr(PANEL_NAMES[index])
		_face_buttons[index].tooltip_text = tr("Look toward panel %d") % (index + 1)
	_installed_sites = Library.entries(library_root)
	_populate()
	popup_centered_clamped(Vector2i(960, 690), 0.9)
	_folder_button.grab_focus()


func scan_source(path: String) -> void:
	_start("scan", Source.scan.bind(path, _is_cancelled), "Scanning scenery…")


func _choose_source(folder: bool) -> void:
	_files.file_mode = FileDialog.FILE_MODE_OPEN_DIR if folder else FileDialog.FILE_MODE_OPEN_FILE
	_files.title = tr("Choose a scenery folder") if folder else tr("Choose a scenery file")
	_files.filters = PackedStringArray(["*.pxf,*.pxi,*.zip ; " + tr("Import scenery")])
	_files.popup_centered_clamped(Vector2i(840, 560), 0.9)


func _button(parent: Control, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 34
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _populate() -> void:
	_sites.clear()
	var query := _search.text.strip_edges().to_lower()
	for entry in _installed_sites:
		_add_site({title = entry.title, id = entry.id, installed = true}, query)
	for entry: Dictionary in _source_sites:
		_add_site(entry, query)


func _add_site(entry: Dictionary, query: String) -> void:
	var site_title := str(entry.get("title", ""))
	if not query.is_empty() and not site_title.to_lower().contains(query):
		return
	var installed := bool(entry.get("installed", false))
	var text := tr("%s (installed)") % site_title if installed else site_title
	var index := _sites.add_item(text)
	_sites.set_item_metadata(index, entry)
	_sites.set_item_tooltip(index, site_title if installed else str(entry.get("descriptor", site_title)))
	if entry == _selection:
		_sites.select(index)


func _select(index: int) -> void:
	if _worker != null:
		return
	_selection = _sites.get_item_metadata(index)
	_clear_preview()
	_caption.text = str(_selection.title)
	if _selection.get("installed", false):
		_start("preview", Library.load_preview.bind(_selection.id, _is_cancelled, library_root), "Opening preview…")
		return
	var error := str(_selection.get("error", ""))
	if not error.is_empty():
		_status.text = tr(error)
		_set_busy(false)
		return
	_start("preview", Library.prepare.bind(_selection, _is_cancelled), "Preparing panorama panels…")


func _install_preview() -> void:
	_start("install", Library.install.bind(_preview, _is_cancelled, library_root), "Installing scenery preview…")


func _fly_selected() -> void:
	if _fly.disabled:
		return
	var revision := str(_preview.id)
	hide()
	flight_requested.emit.call_deferred(revision)


func _confirm_remove() -> void:
	var id := str(_selection.get("id", ""))
	if id.is_empty():
		return
	var confirm := ConfirmationDialog.new()
	confirm.set_meta("landscape_import_popup", true)
	confirm.title = tr("Remove preview")
	confirm.dialog_text = tr("Remove the installed preview for %s?") % str(_selection.title)
	confirm.confirmed.connect(func() -> void:
		if Library.remove(id, library_root):
			_selection = {}
			_clear_preview()
			_installed_sites = Library.entries(library_root)
			_populate()
			_status.text = tr("Preview removed.")
		else:
			_status.text = tr("The preview could not be removed.")
		_set_busy(false)
		confirm.queue_free())
	confirm.canceled.connect(confirm.queue_free)
	add_child(confirm)
	confirm.popup_centered()


func _start(job: String, operation: Callable, message: String) -> void:
	if _worker != null:
		return
	_mutex.lock()
	_cancelled = false
	_mutex.unlock()
	_job = job
	_worker = Thread.new()
	if _worker.start(operation) != OK:
		_worker = null
		_status.text = tr("The scenery operation could not start.")
		_set_busy(false)
		return
	_status.text = tr(message)
	_set_busy(true)
	set_process(true)


func _process(_delta: float) -> void:
	if _worker == null or _worker.is_alive():
		return
	var result: Dictionary = _worker.wait_to_finish()
	_worker = null
	set_process(false)
	if not visible:
		_set_busy(false)
		return
	var error := str(result.get("error", ""))
	if not error.is_empty():
		var message := tr(error)
		_status.text = message % result.panel if result.has("panel") else message
	elif _job == "install":
		_installed_sites = Library.entries(library_root)
		if not _preview.is_empty():
			_selection = {title = _preview.title, id = result.id, installed = true}
		_populate()
		_status.text = tr("Installed locally. Preview only.")
		if not _preview.is_empty():
			_preview.calibration = Library.flight_calibration(result.id, library_root)
	elif _is_cancelled():
		_status.text = tr("Cancelled.")
	elif _job == "scan":
		_source_sites = result.get("sites", [])
		_populate()
		_status.text = tr("No Phoenix RC scenery was found in this source.") if _source_sites.is_empty() \
			else tr("Choose a site to preview its panorama panels.")
	else:
		_preview = result
		_caption.text = str(result.title)
		_setup_panorama()
		_show_panel(0)
		_status.text = tr("Preview only. Drag to look around or choose a numbered direction.") if _panorama != null \
			else tr("Preview only. Browse the six source panels.")
	if error.is_empty() and _job in ["install", "preview"] and not _preview.get("calibration", {}).is_empty():
		_status.text = tr("Experimental flight ready. Runway, start and ground are estimated.")
	_set_busy(false)


func _show_panel(index: int) -> void:
	if _preview.is_empty():
		return
	if _panorama == null:
		_photo.texture = ImageTexture.create_from_image(_preview.images[index])
	else:
		_bearing = Vector2(PANEL_YAW[index], PANEL_PITCH[index])
		_update_orientation()
	_face_buttons[index].set_pressed_no_signal(true)


func _setup_panorama() -> void:
	if not _preview.get("panorama", false):
		return
	_panorama = ShaderMaterial.new()
	_panorama.shader = Panorama
	for index in 6:
		var texture := ImageTexture.create_from_image(_preview.images[index])
		_panorama.set_shader_parameter("panel_%d" % (index + 1), texture)
		if index == 0:
			_photo.texture = texture
	_photo.stretch_mode = TextureRect.STRETCH_SCALE
	_photo.material = _panorama
	_photo.mouse_default_cursor_shape = Control.CURSOR_DRAG


func _aim_preview(event: InputEvent) -> void:
	if _panorama == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_dragging = (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
		if _dragging:
			_bearing.x = wrapf(_bearing.x - event.relative.x * 0.006, -PI, PI)
			_bearing.y = clampf(_bearing.y + event.relative.y * 0.006, -PI / 2.0, PI / 2.0)
			_update_orientation()


func _update_orientation() -> void:
	if _panorama != null:
		_panorama.set_shader_parameter("aspect", _photo.size.x / maxf(1, _photo.size.y))
		_panorama.set_shader_parameter("yaw", _bearing.x)
		_panorama.set_shader_parameter("pitch", _bearing.y)


func _clear_preview() -> void:
	_preview = {}
	_photo.texture = null
	_photo.material = null
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_photo.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_panorama = null
	_dragging = false
	_caption.text = ""


func _set_busy(busy: bool) -> void:
	_folder_button.disabled = busy
	_file_button.disabled = busy
	_search.editable = not busy
	_sites.mouse_filter = Control.MOUSE_FILTER_IGNORE if busy else Control.MOUSE_FILTER_STOP
	_sites.focus_mode = Control.FOCUS_NONE if busy else Control.FOCUS_ALL
	_stop_button.visible = busy
	_stop_button.disabled = false
	var installed := bool(_selection.get("installed", false))
	_install.disabled = busy or installed or _preview.is_empty()
	_remove.disabled = busy or not installed
	_fly.visible = installed and not _preview.get("calibration", {}).is_empty()
	_fly.disabled = busy or not _fly.visible
	for button in _face_buttons:
		button.disabled = _preview.is_empty()


func _cancel_operation() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()
	_stop_button.disabled = true


func _is_cancelled() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value


func _on_visibility_changed() -> void:
	if visible:
		return
	if _worker != null:
		_cancel_operation()
	_selection = {}
	_source_sites.clear()
	_sites.clear()
	_clear_preview()
	_status.text = tr("Choose a scenery file or folder from the Phoenix RC simulator, or reopen an installed preview.")
	_set_busy(_worker != null)


func _exit_tree() -> void:
	if _worker != null:
		_cancel_operation()
		_worker.wait_to_finish()
