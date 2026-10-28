## Player-facing template, offline guide and texture-only skin import.
extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const CustomSkin := preload("res://aircraft/custom_skin.gd")
const Languages := preload("res://i18n/languages.gd")
const KIT := "res://assets/skin-kit/skywalker-x8.zip"
const GUIDE := "res://assets/skin-kit/guide.html"
signal close_requested
signal imported(id: String)
var _aircraft_id := ""
var _screen: Control
var _status: Label
var _picker: FileDialog
var _saving := false
var _first: Button


func _init(aircraft_id := "skywalker-x8", shared_theme: Theme = null) -> void:
	name = "SkinTools"
	layer = 12
	_aircraft_id = aircraft_id
	_screen = Screen.mount(self, "Modal", shared_theme)
	_screen.escape_before_gui = true
	_screen.close_requested.connect(func() -> void:
		if _picker.visible: _picker.hide()
		else: close_requested.emit()
	)
	_screen.dim(0.70)
	var center: CenterContainer = _screen.center(24)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "Card"
	panel.custom_minimum_size.x = 640
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	box.add_child(Widgets.label("Create a skin", "TitleLabel", true))
	box.add_child(Widgets.label("X8 · Blender → .orskin", "SectionLabel", true, false))
	box.add_child(Widgets.label("Save the template, follow the guide with Claude or Codex, then load your .orskin file.", "", true))
	_first = Widgets.button("Save Blender template…", "PrimaryButton", "SaveSkinTemplate")
	_first.pressed.connect(save_template)
	box.add_child(_first)
	var guide := Widgets.button("Open skin guide", "", "OpenSkinGuide")
	guide.pressed.connect(open_guide)
	box.add_child(guide)
	var import_skin := Widgets.button("Load new skin…", "", "ImportSkin")
	import_skin.pressed.connect(choose_skin)
	box.add_child(import_skin)
	_status = Widgets.label("Choose an original paint at any time to restore it.", "SecondaryLabel", true)
	_status.custom_minimum_size.y = 60
	box.add_child(_status)
	var back := Widgets.button("Back")
	back.pressed.connect(func() -> void: close_requested.emit())
	box.add_child(back)
	_picker = FileDialog.new()
	_picker.name = "SkinFileDialog"
	_picker.access = FileDialog.ACCESS_FILESYSTEM
	_picker.use_native_dialog = false
	_picker.file_selected.connect(_file_selected)
	_screen.add_child(_picker)
	_screen.resized.connect(func() -> void: panel.custom_minimum_size.x = minf(700, _screen.size.x - 48))


func _ready() -> void:
	_first.grab_focus.call_deferred()


func choose_skin() -> void:
	_saving = false
	_picker.title = tr("Load new skin…")
	_picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_picker.filters = PackedStringArray(["*.orskin ; OpenRC skin"])
	_picker.current_file = ""
	_picker.popup_centered_clamped(Vector2i(900, 600), 0.9)


func save_template() -> void:
	_saving = true
	_picker.title = tr("Save Blender template…")
	_picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_picker.filters = PackedStringArray(["*.zip ; Blender template"])
	_picker.current_file = "skywalker-x8.zip"
	_picker.popup_centered_clamped(Vector2i(900, 600), 0.9)


func _file_selected(path: String) -> void:
	if _saving:
		if _copy_resource(KIT, path):
			_status.text = tr("Template saved. Extract the ZIP and open the skin guide.")
		else:
			_status.text = tr("Could not save the template. Check the destination and try again.")
		return
	var result := CustomSkin.import_file(path, _aircraft_id)
	if result.ok:
		imported.emit(str(result.id))
	else:
		_status.text = tr("Skin could not be loaded:") + "\n" + "\n".join(result.get("errors", []))


func open_guide() -> void:
	var path := "user://skin-guide.html"
	if not _write_guide(path, TranslationServer.get_locale()) or OS.shell_open(ProjectSettings.globalize_path(path)) != OK:
		_status.text = tr("Could not open the guide. Use guide.html inside the template ZIP.")


static func _write_guide(destination: String, locale: String) -> bool:
	var input := FileAccess.open(GUIDE, FileAccess.READ)
	if input == null: return false
	var source := input.get_as_text()
	var marker := 'data-default-locale="auto"'
	if not source.contains(marker): return false
	var code := Languages.supported_locale(locale)
	source = source.replace(marker, 'data-default-locale="' + code + '"')
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null: return false
	output.store_string(source)
	output.flush()
	return output.get_error() == OK


static func _copy_resource(source: String, destination: String) -> bool:
	var input := FileAccess.open(source, FileAccess.READ)
	if input == null: return false
	var output := FileAccess.open(destination, FileAccess.WRITE)
	if output == null: return false
	while input.get_position() < input.get_length():
		output.store_buffer(input.get_buffer(mini(1048576, input.get_length() - input.get_position())))
		if output.get_error() != OK: return false
	output.flush()
	return output.get_error() == OK
