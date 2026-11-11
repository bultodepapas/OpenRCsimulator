extends VBoxContainer
## Moving parts of the Aircraft Creator's Controls step (AC-17): which part of a GLB model turns
## with which control, about which of its own axes, and in which direction.
##
## Presentation only: the bindings never reach the compiled physics. The panel shows the parts the
## visual builder lists, pre-fills axis and direction from `suggest_binding` when a part is chosen,
## and reports the whole bindings dictionary on every change. Validation stays in the domain: the
## wizard hands the problems back with `show_problems`. An STL has no parts.

signal bindings_changed(bindings: Dictionary)
signal movement_toggled(on: bool)

const Widgets := preload("res://ui/widgets.gd")
const VisualBuilder := preload("res://workshop/creator/visual_builder.gd")
const Parts := preload("res://workshop/creator/visual_parts.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")

## Role, slot within the role and caption of each row.
const SLOTS: Array[Array] = [
	["aileron_left", 0, "Left aileron"], ["aileron_right", 0, "Right aileron"], ["elevator", 0, "Elevator"],
	["elevator", 1, "Elevator, second part"], ["rudder", 0, "Rudder"], ["propeller", 0, "Propeller"],
]
const AXIS_NAMES: PackedStringArray = ["X", "Y", "Z"]
const NOT_BOUND := "Not bound"
const STL_NOTE := "An STL model is one rigid shape, so none of its parts can move with the controls."
const SHOW_MOVEMENT := "Show movement"
const STOP_MOVEMENT := "Stop movement"

var _source: InspectedSource
var _placement := {}
var _shown_parts: Array = []
var _rows := {}
## Field prefix of the current bindings ("bindings/controls/elevator/0") -> row key ("elevator/1").
var _field_rows := {}
var _syncing := false
var _no_model: Label
var _stl_note: Label
var _glb_box: VBoxContainer
var _general_error: Label
var _origin_note: Label
var _movement: Button


func _init() -> void:
	name = "MovingParts"
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(Widgets.label("Moving parts", "SectionLabel", true))
	_no_model = _text("Import a model first", "SecondaryLabel")
	_no_model.name = "PartsNoModel"
	add_child(_no_model)
	_stl_note = _text(STL_NOTE, "SecondaryLabel")
	_stl_note.name = "PartsStlNote"
	_stl_note.visible = false
	add_child(_stl_note)
	_glb_box = VBoxContainer.new()
	_glb_box.name = "PartsList"
	_glb_box.add_theme_constant_override("separation", 10)
	_glb_box.visible = false
	add_child(_glb_box)
	_glb_box.add_child(_text("Choose the model part that moves with each control, then check the movement on the preview and change the axis or direction if it is wrong.", "SecondaryLabel"))
	for slot: Array in SLOTS:
		_add_row(str(slot[0]), int(slot[1]), str(slot[2]))
	_general_error = _text("", "ErrorLabel", false)
	_general_error.name = "PartsError"
	_general_error.visible = false
	_glb_box.add_child(_general_error)
	_origin_note = _text("", "SecondaryLabel", false)
	_origin_note.name = "PartsOriginNote"
	_origin_note.visible = false
	_glb_box.add_child(_origin_note)
	_movement = Widgets.button(SHOW_MOVEMENT, "", "ShowMovement")
	_movement.toggle_mode = true
	_movement.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_movement.toggled.connect(func(pressed: bool) -> void:
		_movement.text = STOP_MOVEMENT if pressed else SHOW_MOVEMENT
		movement_toggled.emit(pressed))
	_glb_box.add_child(_movement)
	_fill_part_lists()


# --- Public interface -------------------------------------------------------------------------

## Shows the parts of `source` (null: no model) and selects what `bindings` names. Rebuilds the
## part lists only when the source changed. Emits nothing.
func show_model(source: InspectedSource, placement: Dictionary, bindings: Dictionary) -> void:
	_placement = placement.duplicate(true)
	if source != _source:
		_source = source
		_shown_parts = []
		if source != null and source.format() == InspectedSource.FORMAT_GLB:
			var listed: Dictionary = VisualBuilder.list_parts(source)
			if listed.ok:
				_shown_parts = listed.value
		_fill_part_lists()
	var glb := source != null and source.format() == InspectedSource.FORMAT_GLB
	_no_model.visible = source == null
	_stl_note.visible = source != null and not glb
	_glb_box.visible = glb
	if not glb and _movement.button_pressed:
		_movement.button_pressed = false
	_apply(bindings)


## True when a GLB is shown: only then are there parts to bind.
func has_parts() -> bool:
	return _glb_box.visible


## Problems of the current bindings: field path -> translated text, plus an optional note
## (translated) shown under the rows while something is bound.
func show_problems(by_field: Dictionary, note: String) -> void:
	var general := PackedStringArray()
	var per_row := {}
	for field: String in by_field:
		var key := _row_key(field)
		if key.is_empty():
			general.append(str(by_field[field]))
		elif not per_row.has(key):
			per_row[key] = str(by_field[field])
	for key: String in _rows:
		var error: Label = _rows[key].error
		error.text = str(per_row.get(key, ""))
		error.visible = per_row.has(key)
	_general_error.text = "\n".join(general)
	_general_error.visible = not general.is_empty()
	_origin_note.text = note
	_origin_note.visible = not note.is_empty()


## The control a field path such as "bindings/controls/elevator/1/axis" names, or null.
func focus_target(path: String) -> Control:
	if not has_parts():
		return null
	var key := _row_key(path)
	if key.is_empty():
		return default_focus()
	var row: Dictionary = _rows[key]
	if path.ends_with("/axis"):
		return row.axis
	if path.ends_with("/sign"):
		return row.reversed
	return row.part


func default_focus() -> Control:
	return (_rows["aileron_left/0"].part as Control) if has_parts() else null


func pickers() -> Array[OptionButton]:
	var found: Array[OptionButton] = []
	for key: String in _rows:
		found.append(_rows[key].part as OptionButton)
		found.append(_rows[key].axis as OptionButton)
	return found


func is_movement_on() -> bool:
	return _movement.button_pressed


func stop_movement() -> void:
	if _movement.button_pressed:
		_movement.button_pressed = false


## Captions held outside auto-translation: the "Not bound" entry of every part list.
func refresh_texts() -> void:
	for key: String in _rows:
		var picker: OptionButton = _rows[key].part
		if picker.item_count > 0:
			picker.set_item_text(0, tr(NOT_BOUND))
		if picker.selected == 0:
			picker.text = tr(NOT_BOUND)


# --- Construction -----------------------------------------------------------------------------

func _text(text: String, variation: String, translate := true) -> Label:
	var control := Widgets.label(text, variation, true, translate)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.x = 110
	return control


func _add_row(role: String, slot: int, caption: String) -> void:
	var key := "%s/%d" % [role, slot]
	var suffix := role.to_pascal_case() + str(slot)
	var holder := VBoxContainer.new()
	holder.name = "Bind" + suffix
	holder.add_theme_constant_override("separation", 2)
	_glb_box.add_child(holder)
	var line := HFlowContainer.new()
	line.name = "Line"
	line.add_theme_constant_override("h_separation", 10)
	line.add_theme_constant_override("v_separation", 6)
	holder.add_child(line)
	var label := Widgets.label(caption, "SecondaryLabel", false)
	label.custom_minimum_size.x = 170
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(label)
	var part := OptionButton.new()
	part.name = "BindPart" + suffix
	part.accessibility_name = tr(caption)
	# Part names are the player's own data: only "Not bound" is translated, by refresh_texts.
	part.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	part.fit_to_longest_item = false
	part.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	part.custom_minimum_size.x = 200
	part.item_selected.connect(_on_part_selected.bind(key))
	Widgets.fit_option_popup(part)
	line.add_child(part)
	var axis := OptionButton.new()
	axis.name = "BindAxis" + suffix
	axis.accessibility_name = tr("Axis")
	axis.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for index: int in AXIS_NAMES.size():
		axis.add_item(AXIS_NAMES[index])
		axis.set_item_metadata(index, Parts.AXES[index])
	axis.item_selected.connect(func(_index: int) -> void: _changed())
	line.add_child(axis)
	var reversed := CheckButton.new()
	reversed.name = "BindReversed" + suffix
	reversed.text = "Reversed"
	reversed.toggled.connect(func(_pressed: bool) -> void: _changed())
	line.add_child(reversed)
	var error := _text("", "ErrorLabel", false)
	error.name = "BindError" + suffix
	error.visible = false
	holder.add_child(error)
	_rows[key] = {role = role, slot = slot, part = part, axis = axis, reversed = reversed, error = error}


func _fill_part_lists() -> void:
	_syncing = true
	for key: String in _rows:
		var picker: OptionButton = _rows[key].part
		picker.clear()
		picker.add_item(tr(NOT_BOUND))
		picker.set_item_metadata(0, -1)
		for part: Dictionary in _shown_parts:
			var label := str(part.name) if not str(part.name).is_empty() else tr("Part")
			picker.add_item("%s · #%d" % [label, int(part.node)])
			picker.set_item_metadata(picker.item_count - 1, int(part.node))
		picker.select(0)
	_syncing = false


# --- Bindings ---------------------------------------------------------------------------------

## Selects what the bindings name. A node that is not among the listed parts shows "Not bound";
## the wizard reports it as a problem of that field.
func _apply(bindings: Dictionary) -> void:
	_syncing = true
	var placed := {}
	var controls: Dictionary = bindings.get("controls", {}) if bindings.get("controls", {}) is Dictionary else {}
	for role: String in Parts.CONTROL_ROLES:
		var listed: Array = controls.get(role, []) if controls.get(role, []) is Array else []
		for index: int in mini(listed.size(), 2):
			if listed[index] is Dictionary:
				placed["%s/%d" % [role, index]] = listed[index]
	if bindings.get("propeller") is Dictionary:
		placed["propeller/0"] = bindings.propeller
	for key: String in _rows:
		var row: Dictionary = _rows[key]
		var entry: Dictionary = placed.get(key, {})
		_select_part(row.part as OptionButton, int(entry.get("node", -1)) if not entry.is_empty() else -1)
		_select_axis(row.axis as OptionButton, str(entry.get("axis", Parts.DEFAULT_AXES[row.role])))
		(row.reversed as CheckButton).set_pressed_no_signal(not entry.is_empty() and float(entry.get("sign", 1)) < 0.0)
		(row.axis as OptionButton).disabled = entry.is_empty()
		(row.reversed as CheckButton).disabled = entry.is_empty()
	_map_fields(placed)
	_syncing = false


func _select_part(picker: OptionButton, node: int) -> void:
	for index: int in picker.item_count:
		if int(picker.get_item_metadata(index)) == node:
			picker.select(index)
			return
	picker.select(0)


func _select_axis(picker: OptionButton, axis: String) -> void:
	var index := Parts.AXES.find(axis)
	picker.select(index if index >= 0 else 0)


func _on_part_selected(index: int, key: String) -> void:
	if _syncing:
		return
	var row: Dictionary = _rows[key]
	var node := int((row.part as OptionButton).get_item_metadata(index))
	_syncing = true
	(row.axis as OptionButton).disabled = node < 0
	(row.reversed as CheckButton).disabled = node < 0
	if node >= 0:
		var suggested: Dictionary = VisualBuilder.suggest_binding(_source, _placement, node, str(row.role))
		var chosen: Dictionary = suggested.value if suggested.ok else {"axis": str(Parts.DEFAULT_AXES[row.role]), "sign": 1}
		_select_axis(row.axis as OptionButton, str(chosen.axis))
		(row.reversed as CheckButton).set_pressed_no_signal(int(chosen.sign) < 0)
	_syncing = false
	_changed()


func _changed() -> void:
	if _syncing:
		return
	bindings_changed.emit(_collect())


## The bindings the rows describe: {} when nothing is bound, else the fixed shape with whole numbers.
func _collect() -> Dictionary:
	var controls := {}
	var bound := {"format": Parts.FORMAT, "controls": controls}
	var fields := {}
	for slot: Array in SLOTS:
		var key := "%s/%d" % [slot[0], slot[1]]
		var row: Dictionary = _rows[key]
		var picker: OptionButton = row.part
		var node := int(picker.get_item_metadata(picker.selected)) if picker.selected >= 0 else -1
		if node < 0:
			continue
		var axis_picker: OptionButton = row.axis
		var entry := {"node": node, "axis": str(axis_picker.get_item_metadata(maxi(axis_picker.selected, 0))),
			"sign": -1 if (row.reversed as CheckButton).button_pressed else 1}
		var role := str(row.role)
		if role == Parts.PROPELLER:
			bound["propeller"] = entry
			fields["bindings/propeller"] = key
		else:
			if not controls.has(role):
				controls[role] = []
			# The list index, not the row, names the field of a problem: keep the mapping.
			fields["bindings/controls/%s/%d" % [role, (controls[role] as Array).size()]] = key
			(controls[role] as Array).append(entry)
	_field_rows = fields
	return {} if fields.is_empty() else bound


func _map_fields(placed: Dictionary) -> void:
	_field_rows.clear()
	for key: String in placed:
		var parts := key.split("/")
		if parts[0] == Parts.PROPELLER:
			_field_rows["bindings/propeller"] = key
		else:
			_field_rows["bindings/controls/%s/%s" % [parts[0], parts[1]]] = key


## The row a field path belongs to, or "" for a problem of the bindings as a whole.
func _row_key(path: String) -> String:
	var best := ""
	for prefix: String in _field_rows:
		if (path == prefix or path.begins_with(prefix + "/")) and prefix.length() > best.length():
			best = prefix
	if not best.is_empty():
		return str(_field_rows[best])
	var parts := path.split("/")
	if parts.size() >= 3 and parts[0] == "bindings" and parts[1] == "controls":
		for slot: Array in SLOTS:
			if str(slot[0]) == parts[2]:
				return "%s/%d" % [slot[0], slot[1]]
	return ""
