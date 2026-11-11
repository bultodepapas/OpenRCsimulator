extends AcceptDialog
## Library dialog of the Aircraft Creator (AC-14): saved drafts and saved aircraft.
##
## Shows the rows the wizard reads from the store and reports the player's intents (open, archive,
## restore, show archived). It never reads or writes the store itself, so a damaged entry can only
## cost its own Open: the wizard shows the store's message here and the list stays as it is.
## Names and dates are player data and are shown as they are; everything else is translated.

signal open_requested(kind: String, id: String)
signal archive_requested(kind: String, id: String, archived: bool)
signal show_archived_toggled(show_archived: bool)

const Widgets := preload("res://ui/widgets.gd")

const KIND_DRAFT := "draft"
const KIND_AIRCRAFT := "aircraft"

var _show_archived: CheckButton
var _message: Label
var _lists := {}
var _empty_texts := {KIND_DRAFT: "No drafts yet.", KIND_AIRCRAFT: "No saved aircraft yet."}


func _init() -> void:
	name = "CreatorLibrary"
	title = "Aircraft library"
	ok_button_text = "Close"
	var scroll := ScrollContainer.new()
	scroll.name = "LibraryScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(560, 320)
	add_child(scroll)
	var column := VBoxContainer.new()
	column.name = "LibraryLayout"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	_show_archived = CheckButton.new()
	_show_archived.name = "ShowArchived"
	_show_archived.text = "Show archived"
	_show_archived.toggled.connect(func(pressed: bool) -> void: show_archived_toggled.emit(pressed))
	column.add_child(_show_archived)
	_message = Widgets.label("", "ErrorLabel", true, false)
	_message.name = "LibraryMessage"
	_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_message.visible = false
	column.add_child(_message)
	for kind: String in [KIND_DRAFT, KIND_AIRCRAFT]:
		column.add_child(Widgets.label("Drafts" if kind == KIND_DRAFT else "Saved aircraft", "SectionLabel", true))
		var list := VBoxContainer.new()
		list.name = "DraftList" if kind == KIND_DRAFT else "AircraftList"
		list.add_theme_constant_override("separation", 6)
		column.add_child(list)
		_lists[kind] = list


func show_archived() -> bool:
	return _show_archived.button_pressed


## Replaces the rows. `drafts` and `aircraft` are the store's listings. Without `writable` the
## Archive and Restore buttons are disabled and `reason` (translated) says why.
func populate(drafts: Array, aircraft: Array, writable: bool, reason: String) -> void:
	_fill(KIND_DRAFT, drafts, writable, reason)
	_fill(KIND_AIRCRAFT, aircraft, writable, reason)


## A translated message above the lists, or "" to hide it.
func set_message(text: String) -> void:
	_message.text = text
	_message.visible = not text.is_empty()


## Focuses the first Open button, or Show archived when the lists are empty.
func focus_first() -> void:
	for kind: String in [KIND_DRAFT, KIND_AIRCRAFT]:
		for row: Node in (_lists[kind] as Node).get_children():
			var open := row.find_child("Open", true, false) as Button
			if open != null:
				open.grab_focus()
				return
	_show_archived.grab_focus()


## Local date and time of a Unix time, in a form that needs no translation.
static func when(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var moment := Time.get_datetime_dict_from_unix_time(unix + bias)
	return "%04d-%02d-%02d %02d:%02d" % [int(moment.year), int(moment.month), int(moment.day), int(moment.hour), int(moment.minute)]


func _fill(kind: String, rows: Array, writable: bool, reason: String) -> void:
	var list: VBoxContainer = _lists[kind]
	for child: Node in list.get_children():
		list.remove_child(child)
		child.queue_free()
	if rows.is_empty():
		var empty := Widgets.label(str(_empty_texts[kind]), "SecondaryLabel", true)
		empty.name = "Empty"
		list.add_child(empty)
		return
	var index := 0
	for entry: Variant in rows:
		if not entry is Dictionary:
			continue
		var row_data: Dictionary = entry
		var id := str(row_data.get("draft_id" if kind == KIND_DRAFT else "aircraft_uuid", ""))
		var archived := bool(row_data.get("archived", false))
		var row := HBoxContainer.new()
		row.name = ("Draft%d" if kind == KIND_DRAFT else "Aircraft%d") % index
		row.add_theme_constant_override("separation", 8)
		row.set_meta("id", id)
		list.add_child(row)
		var details := PackedStringArray()
		if kind == KIND_DRAFT:
			details.append(when(int(row_data.get("updated_unix", 0))))
		else:
			details.append(when(int(row_data.get("created_unix", 0))))
			details.append(tr("Versions: %s") % int(row_data.get("revisions", 0)))
		if archived:
			details.append(tr("Archived"))
		var text := Widgets.label("%s\n%s" % [str(row_data.get("name", "")), " · ".join(details)], "", true, false)
		text.name = "Entry"
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.custom_minimum_size.x = 200
		row.add_child(text)
		var open := Widgets.button("Open", "", "Open")
		open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		open.pressed.connect(func() -> void: open_requested.emit(kind, id))
		row.add_child(open)
		var archive := Widgets.button("Restore" if archived else "Archive", "", "Archive")
		archive.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		archive.disabled = not writable
		archive.tooltip_text = "" if writable else reason
		archive.pressed.connect(func() -> void: archive_requested.emit(kind, id, not archived))
		row.add_child(archive)
		index += 1
