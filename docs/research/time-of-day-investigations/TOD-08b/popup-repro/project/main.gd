extends Control

var _choice: OptionButton
var _events: PackedStringArray = PackedStringArray()
var _popup_observed: bool = false

func _ready() -> void:
	var column := VBoxContainer.new()
	column.position = Vector2(40, 40)
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	var label := Label.new()
	label.text = "Press Enter to open; Down then Enter selects"
	column.add_child(label)
	_choice = OptionButton.new()
	_choice.name = "Choice"
	for text in ["Legacy", "Dawn", "Noon", "Night"]:
		_choice.add_item(text)
	var native_requested: bool = OS.get_environment("POPUP_REPRO_FORCE_NATIVE") == "1"
	var subwindows: bool = DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS)
	_choice.get_popup().force_native = native_requested and subwindows
	_choice.item_selected.connect(_on_selected)
	column.add_child(_choice)
	_write("ready; subwindows=" + str(subwindows) + "; force_native=" + str(_choice.get_popup().force_native))
	_choice.grab_focus.call_deferred()

func _process(_delta: float) -> void:
	if not _popup_observed and _choice != null and _choice.get_popup().visible:
		_popup_observed = true
		_write("popup_visible=true")

func _on_selected(index: int) -> void:
	_write("selected=" + str(index))

func _write(text: String) -> void:
	_events.append(text)
	var path: String = OS.get_environment("POPUP_REPRO_MARKER")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(_events) + "\n")
		file.close()
