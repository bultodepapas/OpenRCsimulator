# Update notice (MENU-PLAN UI-16): a small card at Home's top right, over the backdrop and outside the column, when
# a newer release is published: the version, Download (the release page in the browser: the ZIPs, their checksums
# and the first-launch notes live there), Later (this session only) and Skip this version (remembered). It never
# takes the focus by itself; the buttons are reachable with the keyboard like any other. English source strings;
# the sentences with the version and size are built with tr() and rebuilt when the language changes.
# DT-UPD-04a (docs/plans/github-updates.md): the second line states this platform's download size when the
# release advertises an exact package for it. Downloading and installing stay with the browser and the player.
extends PanelContainer

const Widgets := preload("res://ui/widgets.gd")
const UpdateCheck := preload("res://app_state/update_check.gd")

## Download was pressed: `url` is the trusted release page (app_state/update_check.gd notice).
signal download_requested(url: String)
## Skip this version was pressed for the release tagged `tag`; the card is hidden. (`hidden` is CanvasItem's own
## signal.)
signal hide_requested(tag: String)
## Later was pressed: the card is hidden for this session; nothing is remembered.
signal later_requested(tag: String)

const MARGIN := 24

var info := {}
var label: Label
## The download size line; hidden when the release has no known package size for this platform.
var detail: Label
var download_button: Button
var later_button: Button
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
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 2)
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(texts)
	label = Widgets.label("", "SecondaryLabel", false, false) # built with tr()
	label.name = "Text"
	texts.add_child(label)
	detail = Widgets.label("", "SecondaryLabel", false, false)
	detail.name = "Size"
	detail.visible = false
	texts.add_child(detail)
	download_button = Widgets.button("Download", "", "Download")
	download_button.pressed.connect(func() -> void: download_requested.emit(str(info.get("url", ""))))
	later_button = Widgets.button("Later", "", "Later")
	later_button.pressed.connect(_on_later)
	hide_button = Widgets.button("Skip this version", "", "SkipVersion")
	hide_button.pressed.connect(_on_hide)
	var buttons: Array[Button] = [download_button, later_button, hide_button]
	for index in buttons.size():
		buttons[index].add_theme_font_size_override("font_size", 16)
		buttons[index].size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(buttons[index])
	for index in buttons.size():
		if index > 0:
			buttons[index].focus_neighbor_left = buttons[index].get_path_to(buttons[index - 1])
		if index < buttons.size() - 1:
			buttons[index].focus_neighbor_right = buttons[index].get_path_to(buttons[index + 1])


## Shows `info` ({ tag, version, url, published, size? }); calling it again with another release replaces the
## text.
func show_release(release: Dictionary) -> void:
	info = release.duplicate()
	_update_texts()
	visible = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and label != null:
		_update_texts()


func _update_texts() -> void:
	label.text = tr("Update available: %s") % str(info.get("version", ""))
	var size := int(info.get("size", 0))
	detail.visible = size > 0
	detail.text = tr("Download: %s") % UpdateCheck.format_bytes(size) if size > 0 else ""
	download_button.tooltip_text = tr("Opens the release page in your browser.")
	later_button.tooltip_text = tr("Hides this notice until you open the game again.")
	hide_button.tooltip_text = tr("Hides this notice until a newer version is published.")


func _on_hide() -> void:
	visible = false
	hide_requested.emit(str(info.get("tag", "")))


func _on_later() -> void:
	visible = false
	later_requested.emit(str(info.get("tag", "")))
