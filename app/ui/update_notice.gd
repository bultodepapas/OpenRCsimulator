# Update notice (MENU-PLAN UI-16): a small card at Home's top right, over the backdrop and outside the column, when
# a newer release is published: the version, Download (the release page in the browser: the ZIPs, their checksums
# and the first-launch notes live there) and Hide (this version, remembered). It never takes the focus by itself;
# the two buttons are reachable with the keyboard like any other. English source strings; the sentence with the
# version is built with tr() and rebuilt when the language changes.
extends PanelContainer

const Widgets := preload("res://ui/widgets.gd")

## Download was pressed: `url` is the trusted release page (app_state/update_check.gd notice).
signal download_requested(url: String)
## Hide was pressed for the release tagged `tag`; the card is hidden. (`hidden` is CanvasItem's own signal.)
signal hide_requested(tag: String)

const MARGIN := 24

var info := {}
var label: Label
var download_button: Button
var hide_button: Button


func _init() -> void:
	name = "UpdateNotice"
	theme_type_variation = "Notice"
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	offset_top = MARGIN
	offset_right = -MARGIN
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	label = Widgets.label("", "SecondaryLabel", false, false) # built with tr()
	label.name = "Text"
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	download_button = Widgets.button("Download", "", "Download")
	download_button.add_theme_font_size_override("font_size", 16)
	download_button.pressed.connect(func() -> void: download_requested.emit(str(info.get("url", ""))))
	row.add_child(download_button)
	hide_button = Widgets.button("Hide", "", "Hide")
	hide_button.add_theme_font_size_override("font_size", 16)
	hide_button.pressed.connect(_on_hide)
	row.add_child(hide_button)
	download_button.focus_neighbor_right = download_button.get_path_to(hide_button)
	hide_button.focus_neighbor_left = hide_button.get_path_to(download_button)


## Shows `info` ({ tag, version, url, published }); calling it again with another release replaces the text.
func show_release(release: Dictionary) -> void:
	info = release.duplicate()
	_update_texts()
	visible = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and label != null:
		_update_texts()


func _update_texts() -> void:
	label.text = tr("Update available: %s") % str(info.get("version", ""))
	download_button.tooltip_text = tr("Opens the release page in your browser.")
	hide_button.tooltip_text = tr("Hides this notice until a newer version is published.")


func _on_hide() -> void:
	visible = false
	hide_requested.emit(str(info.get("tag", "")))
