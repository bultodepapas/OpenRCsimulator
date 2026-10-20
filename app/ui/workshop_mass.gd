extends ConfirmationDialog
## Isolated measured-mass proposal dialog. The Workshop owns history, staleness and ancestry.

const Widgets := preload("res://ui/widgets.gd")
const MassEdit := preload("res://workshop/mass_edit.gd")
const Compiler := preload("res://workshop/compiler.gd")
const UiTheme := preload("res://ui/ui_theme.gd")

signal recipe_proposed(recipe: Dictionary)
signal cancelled

const MAX_DISPLAYED_ERRORS := 1200

var scroll: ScrollContainer
var content: VBoxContainer
var inventory_list: VBoxContainer
var source_details_button: Button
var selected_detail_label: Label
var technical_error_label: Label
var component_picker: OptionButton
var mass_input: LineEdit
var source_input: LineEdit
var stage_button: Button
var weighing_state_label: Label
var observed_mass_input: LineEdit
var observed_cg_inputs: Array[LineEdit] = []
var report_label: Label
var proposal_label: Label
var status_label: Label
var cancel_button: Button
var apply_button: Button
var _base: Dictionary = {}
var _recipe: Dictionary = {}
var _inspection: Dictionary = {}
var _staged_edits: Array = []
var _measurement_dirty := false
var _configured := false
var _syncing := false
var _base_metrics: Dictionary = {}
var _recipe_edits_valid := true
var _localized_controls: Array[Control] = []
var _last_component_index := -1


func _init() -> void:
	name = "WorkshopMassDialog"
	title = tr("Measured component mass")
	min_size = Vector2i(560, 360)
	theme = UiTheme.build()
	_build()


func configure(base: Dictionary, recipe: Dictionary) -> void:
	_base = base.duplicate(true)
	_recipe = recipe.duplicate(true)
	_staged_edits = []
	var input_edits: Variant = _recipe.get("mass_edits", [])
	_recipe_edits_valid = input_edits is Array
	if _recipe_edits_valid:
		_staged_edits = input_edits.duplicate(true)
	_configured = true
	_refresh_inventory()
	_refresh_staged_summary()
	_load_selected_measurement()
	_initialize_observation()
	if not _recipe_edits_valid:
		_show_error(tr("The recipe mass_edits value must be an array."))


func _build() -> void:
	get_ok_button().hide()
	get_ok_button().disabled = true
	var apply_action := add_button("", true, "apply_mass_build")
	apply_action.name = "ApplyMassBuild"
	apply_action.theme_type_variation = "PrimaryButton"
	_localize_control(apply_action, "Apply to a new build")
	custom_action.connect(_on_custom_action)
	_localize_control(get_cancel_button(), "Cancel")
	get_cancel_button().name = "Cancel"
	canceled.connect(_on_cancel)
	close_requested.connect(_on_cancel)
	about_to_popup.connect(_focus_cancel)
	scroll = ScrollContainer.new()
	scroll.name = "MassDialogScroll"
	scroll.custom_minimum_size = Vector2(0.0, 180.0)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	content = VBoxContainer.new()
	content.name = "MassDialogContent"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)

	content.add_child(_label(
		"Record a measured component mass. Geometry stays fixed.",
		"SecondaryLabel", true))
	inventory_list = VBoxContainer.new()
	inventory_list.name = "InventoryRows"
	inventory_list.add_theme_constant_override("separation", 6)
	content.add_child(_label("Measured component", "SectionLabel", false))
	component_picker = OptionButton.new()
	component_picker.name = "MassComponent"
	component_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	component_picker.fit_to_longest_item = false
	component_picker.clip_text = true
	component_picker.item_selected.connect(_on_component_selected)
	content.add_child(component_picker)
	selected_detail_label = _label("", "SecondaryLabel", true)
	selected_detail_label.name = "SelectedComponentDetails"
	content.add_child(selected_detail_label)
	var mass_row := _field_row("Mass (kg)", "MassKg")
	mass_input = mass_row.get_node("Value") as LineEdit
	mass_input.placeholder_text = "0.250"
	mass_input.max_length = 32
	mass_input.text_changed.connect(_on_measurement_changed)
	content.add_child(mass_row)
	var source_row := _field_row("Measurement source", "MeasurementSource")
	source_input = source_row.get_node("Value") as LineEdit
	source_input.placeholder_text = tr("Scale and component identification")
	source_input.max_length = MassEdit.MAX_SOURCE_LENGTH
	source_input.text_changed.connect(_on_measurement_changed)
	content.add_child(source_row)
	stage_button = Widgets.button("", "", "StageMeasurement")
	_localize_control(stage_button, "Add or update measurement")
	stage_button.pressed.connect(_stage_selected_measurement)
	content.add_child(stage_button)
	var staged_row := PanelContainer.new()
	staged_row.theme_type_variation = "Card"
	status_label = _label("No measured components staged.", "SecondaryLabel", true)
	status_label.name = "StagedSummary"
	staged_row.add_child(status_label)
	content.add_child(staged_row)

	content.add_child(_label("Weighing comparison and fixed-station proposal", "SectionLabel", false))
	weighing_state_label = _label("Weighing state: source declaration", "SecondaryLabel", true)
	weighing_state_label.name = "WeighingState"
	content.add_child(weighing_state_label)
	observed_mass_input = (_field_row("Observed total mass (kg)", "ObservedMass").get_node("Value") as LineEdit)
	observed_mass_input.name = "ObservedMassKg"
	observed_mass_input.max_length = 32
	content.add_child(observed_mass_input.get_parent())
	var axes := VBoxContainer.new()
	axes.name = "ObservedCgAxes"
	axes.add_theme_constant_override("separation", 8)
	for axis_spec: Array in [["x aft (m)", "CGXAft"], ["y right (m)", "CGYRight"], ["z up (m)", "CGZUp"]]:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(_label(str(axis_spec[0]), "SecondaryLabel", false))
		var axis_input := LineEdit.new()
		axis_input.name = str(axis_spec[1])
		axis_input.placeholder_text = "0.000"
		axis_input.max_length = 32
		cell.add_child(axis_input)
		observed_cg_inputs.append(axis_input)
		axes.add_child(cell)
	content.add_child(axes)
	var analysis_actions := HFlowContainer.new()
	analysis_actions.add_theme_constant_override("separation", 8)
	var report_button := Widgets.button("", "", "CheckMassTarget")
	_localize_control(report_button, "Check mass and CG")
	report_button.pressed.connect(_show_target_report)
	analysis_actions.add_child(report_button)
	var solve_button := Widgets.button("", "", "SolveFixedStation")
	_localize_control(solve_button, "Propose fixed-station mass")
	solve_button.pressed.connect(_show_fixed_station_proposal)
	analysis_actions.add_child(solve_button)
	content.add_child(analysis_actions)
	report_label = _label("", "SecondaryLabel", true)
	report_label.name = "TargetReport"
	content.add_child(report_label)
	proposal_label = _label("", "SecondaryLabel", true)
	proposal_label.name = "FixedStationProposal"
	content.add_child(proposal_label)
	source_details_button = Widgets.button("", "", "SourceDetailsToggle")
	source_details_button.toggle_mode = true
	source_details_button.button_pressed = false
	source_details_button.toggled.connect(_toggle_source_details)
	content.add_child(source_details_button)
	inventory_list.visible = false
	content.add_child(inventory_list)
	technical_error_label = _label("", "SecondaryLabel", true)
	technical_error_label.name = "TechnicalValidationDetails"
	technical_error_label.visible = false
	content.add_child(technical_error_label)

	var error := _label("", "ErrorLabel", true)
	error.name = "MassDialogError"
	error.visible = false
	error.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(error)
	cancel_button = get_cancel_button()
	apply_button = apply_action
	cancel_button.grab_focus.call_deferred()


func _ready() -> void:
	if theme == null:
		theme = UiTheme.build()
	cancel_button.grab_focus.call_deferred()


func _focus_cancel() -> void:
	get_cancel_button().grab_focus.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_language()


func _refresh_language() -> void:
	title = tr("Measured component mass")
	for control: Control in _localized_controls:
		if is_instance_valid(control):
			control.set("text", tr(str(control.get_meta("locale_en", ""))))
	if _configured:
		_refresh_staged_summary()
		weighing_state_label.text = "%s: %s" % [tr("Weighing state (fixed to source declaration)"), str(_inspection.get("weighing_state", "unknown"))]
		_toggle_source_details(source_details_button.button_pressed)
		_refresh_selected_detail()
	source_input.placeholder_text = tr("Scale and component identification")


func _refresh_inventory() -> void:
	for child: Node in inventory_list.get_children():
		inventory_list.remove_child(child)
		child.queue_free()
	component_picker.clear()
	if not _configured:
		return
	_inspection = MassEdit.inspect(_base)
	if not bool(_inspection.get("ok", false)):
		_show_error(_errors_text(_inspection.get("errors", [])), true)
		component_picker.disabled = true
		stage_button.disabled = true
		return
	for row_variant: Variant in _inspection.inventory:
		var row: Dictionary = row_variant
		var row_text := _label("", "SecondaryLabel", true)
		var position: Array = row.get("position_le_m", [])
		var position_text := "[—, —, —] m"
		if position.size() == 3:
			position_text = "[%.3f, %.3f, %.3f] m" % [float(position[0]), float(position[1]), float(position[2])]
		var provenance := "%s · %s" % [str(row.get("mass_kind", "")), str(row.get("mass_source", ""))]
		var detail := "%s · %s kg · %s · LE %s" % [str(row.get("id", "")), "%.4f" % float(row.get("mass_kg", 0.0)), provenance, position_text]
		if not bool(row.get("editable", false)):
			detail += "\n" + tr("Unavailable: ") + str(row.get("reason", ""))
		row_text.text = "%s\n%s" % [str(row.get("name", "")), detail]
		inventory_list.add_child(row_text)
		if bool(row.get("editable", false)):
			component_picker.add_item(str(row.get("name", "")))
			component_picker.set_item_metadata(component_picker.item_count - 1, str(row.get("id", "")))
	component_picker.disabled = component_picker.item_count == 0
	stage_button.disabled = component_picker.item_count == 0
	if component_picker.item_count > 0:
		component_picker.select(0)
		_last_component_index = 0
		_on_component_selected(0)
	source_details_button.text = "%s (%d)" % [tr("Show source inventory details"), _inspection.inventory.size()]
	weighing_state_label.text = "%s: %s" % [tr("Weighing state (fixed to source declaration)"), str(_inspection.get("weighing_state", "unknown"))]


func _on_component_selected(index: int) -> void:
	if _measurement_dirty and _last_component_index >= 0:
		component_picker.select(_last_component_index)
		_show_error(tr("Stage or correct the current measurement before changing components."))
		return
	_last_component_index = index
	_load_selected_measurement()


func _load_selected_measurement() -> void:
	if not _configured or component_picker == null or component_picker.item_count == 0:
		return
	var item_id := str(component_picker.get_item_metadata(component_picker.selected))
	var staged: Dictionary = _find_edit(item_id)
	var source_item: Dictionary = _source_item(item_id)
	_refresh_selected_detail()
	if not staged.is_empty():
		mass_input.text = str(staged.get("mass_kg", ""))
		source_input.text = str(staged.get("source", ""))
	else:
		mass_input.text = str(source_item.get("mass_kg", ""))
		source_input.text = ""
	_measurement_dirty = false


func _refresh_selected_detail() -> void:
	if not _configured or component_picker == null or component_picker.item_count == 0:
		return
	var item_id := str(component_picker.get_item_metadata(component_picker.selected))
	var source_item: Dictionary = _source_item(item_id)
	selected_detail_label.text = tr("Source mass: %.4f kg") % float(source_item.get("mass_kg", 0.0))


func _on_measurement_changed(_text: String) -> void:
	if not _syncing:
		_measurement_dirty = true


func _stage_selected_measurement() -> void:
	var error := _error_node()
	if not _configured or not bool(_inspection.get("ok", false)):
		_show_error(tr("Aircraft source is unavailable."))
		return
	if not _recipe_edits_valid:
		_show_error(tr("The recipe mass_edits value must be an array."))
		return
	if component_picker.item_count == 0:
		_show_error(tr("No source inventory components are available for measurement."))
		return
	var id := str(component_picker.get_item_metadata(component_picker.selected))
	var parsed := _parse_mass(mass_input.text)
	if not parsed.ok:
		_show_error(tr("Enter a finite component mass in kilograms within the source bounds."))
		return
	var next_edits: Array = _staged_edits.duplicate(true)
	var found := false
	for index: int in range(next_edits.size()):
		var edit: Variant = next_edits[index]
		if edit is Dictionary and str(edit.get("id", "")) == id:
			next_edits[index] = {"id": id, "mass_kg": parsed.mass_kg, "source": source_input.text}
			found = true
			break
	if not found:
		if next_edits.size() >= MassEdit.MAX_EDITS:
			_show_error(tr("The 32 component-measurement limit has been reached."))
			return
		next_edits.append({"id": id, "mass_kg": parsed.mass_kg, "source": source_input.text})
	var checked: Dictionary = MassEdit.apply_to_validated_base(_base, next_edits)
	if not bool(checked.get("ok", false)):
		_show_error(_errors_text(checked.get("errors", [])), true)
		return
	_staged_edits = next_edits
	_measurement_dirty = false
	_last_component_index = component_picker.selected
	_refresh_staged_summary()
	_clear_error()
	_refresh_target_base()
	_show_target_report()


func _refresh_staged_summary() -> void:
	if status_label == null:
		return
	if _staged_edits.is_empty():
		status_label.text = tr("No measured components staged.")
		return
	var ids := PackedStringArray()
	for edit: Variant in _staged_edits:
		if edit is Dictionary:
			ids.append(str(edit.get("id", "")))
	status_label.text = "%s (%d): %s" % [tr("Staged measurements"), ids.size(), ", ".join(ids)]


func _initialize_observation() -> void:
	if not _configured or not bool(_inspection.get("ok", false)):
		return
	_base_metrics = {"mass_kg": _inspection.mass_kg, "cg_le_m": _inspection.cg_le_m.duplicate(true)}
	observed_mass_input.text = "%.6f" % float(_base_metrics.mass_kg)
	for axis: int in range(3):
		observed_cg_inputs[axis].text = "%.6f" % float(_base_metrics.cg_le_m[axis])
	_refresh_target_base()


func _refresh_target_base() -> void:
	if not _configured or not bool(_inspection.get("ok", false)):
		return
	var checked: Dictionary = MassEdit.apply_to_validated_base(_base, _staged_edits) if not _staged_edits.is_empty() else {"ok": true, "raw": _base}
	_base_metrics = MassEdit.inspect(checked.raw) if checked.ok else _inspection


func _show_target_report() -> void:
	if not _configured or not bool(_inspection.get("ok", false)):
		return
	var observation := _read_observation()
	if not observation.ok:
		report_label.text = tr("Enter a positive finite mass and three finite CG coordinates.")
		return
	var state := str(_inspection.get("weighing_state", ""))
	var report: Dictionary = MassEdit.target_consistency_report(
		_active_target_base(),
		observation.mass_kg, observation.cg_le_m, state)
	if not bool(report.get("ok", false)):
		report_label.text = _errors_text(report.get("errors", []))
		return
	var residual: Array = report.cg_residual_m
	var cg_status := tr("within tolerance") if report.cg_within_source_tolerance else tr("outside tolerance")
	var range_status := tr("inside source range") if report.observed_mass_within_source_range else tr("outside source range")
	report_label.text = "%s %.6f kg · Δ %+.6f kg · %s\nCG Δ [x,y,z] = [%+.5f, %+.5f, %+.5f] m · %s (±%.4f m) · %s" % [
		tr("Reference"), float(report.source_mass_kg), float(report.mass_residual_kg),
		range_status, float(residual[0]), float(residual[1]), float(residual[2]), cg_status, float(report.cg_tolerance_m),
		tr("state") + ": " + state,
	]


func _show_fixed_station_proposal() -> void:
	if component_picker.item_count == 0:
		proposal_label.text = tr("Select an available source component first.")
		return
	var observation := _read_observation()
	if not observation.ok:
		proposal_label.text = tr("Enter a positive finite mass and three finite CG coordinates.")
		return
	var report_base := _active_target_base()
	var component_id := str(component_picker.get_item_metadata(component_picker.selected))
	var result: Dictionary = MassEdit.solve_fixed_station(
		report_base, component_id, observation.mass_kg, observation.cg_le_m, str(_inspection.get("weighing_state", "")))
	if not bool(result.get("ok", false)):
		proposal_label.text = _errors_text(result.get("errors", []))
		return
	var proposal: Dictionary = result.proposal
	var mass: Dictionary = proposal.get("mass", {})
	proposal_label.text = "%s %s: %.6f kg (%s).\n%s [%+.5f, %+.5f, %+.5f] m. %s" % [
		tr("Proposal only"), str(proposal.get("id", "")), float(mass.get("value", NAN)), str(mass.get("kind", "")),
		tr("Predicted CG x/y/z"),
		float(result.predicted_cg_le_m[0]), float(result.predicted_cg_le_m[1]), float(result.predicted_cg_le_m[2]),
		tr("This derived value is not applied or labelled as a measurement."),
	]


func _on_apply() -> void:
	if not _configured or not bool(_inspection.get("ok", false)):
		_show_error(tr("Aircraft source is unavailable."))
		return
	if not _recipe_edits_valid:
		_show_error(tr("The recipe mass_edits value must be an array."))
		return
	if _measurement_dirty:
		_stage_selected_measurement()
		if _measurement_dirty:
			return
	if _staged_edits.is_empty():
		_show_error(tr("Stage at least one measured component before applying."))
		return
	var core: Dictionary = MassEdit.apply_to_validated_base(_base, _staged_edits)
	if not bool(core.get("ok", false)):
		_show_error(_errors_text(core.get("errors", [])), true)
		return
	var candidate_recipe := _recipe.duplicate(true)
	candidate_recipe["mass_edits"] = _staged_edits.duplicate(true)
	var compiled: Dictionary = Compiler.compile(_base, candidate_recipe)
	if not bool(compiled.get("ok", false)):
		_show_error(_errors_text(compiled.get("errors", [])), true)
		return
	_clear_error()
	recipe_proposed.emit(candidate_recipe)


func _read_observation() -> Dictionary:
	var mass := _parse_mass(observed_mass_input.text, false)
	if not mass.ok:
		return {"ok": false}
	var cg: Array[float] = []
	for field: LineEdit in observed_cg_inputs:
		var coordinate := _parse_mass(field.text, false)
		if not coordinate.ok:
			return {"ok": false}
		cg.append(float(coordinate.value))
	return {"ok": cg.size() == 3, "mass_kg": float(mass.value), "cg_le_m": cg}


func _parse_mass(text: String, bounded := true) -> Dictionary:
	var normalized := text.strip_edges()
	if normalized.is_empty() or not normalized.is_valid_float():
		return {"ok": false}
	var value := float(normalized)
	if not is_finite(value) or (bounded and (value < MassEdit.MIN_INVENTORY_MASS_KG or value > MassEdit.MAX_INVENTORY_MASS_KG)):
		return {"ok": false}
	return {"ok": true, "value": value, "mass_kg": value}


func _active_target_base() -> Dictionary:
	if _staged_edits.is_empty():
		return _base
	var checked: Dictionary = MassEdit.apply_to_validated_base(_base, _staged_edits)
	return checked.raw if bool(checked.get("ok", false)) else _base


func _find_edit(id: String) -> Dictionary:
	for item: Variant in _staged_edits:
		if item is Dictionary and str(item.get("id", "")) == id:
			return item.duplicate(true)
	return {}


func _source_item(id: String) -> Dictionary:
	for row: Variant in _inspection.get("inventory", []):
		if row is Dictionary and str(row.get("id", "")) == id:
			return row
	return {}


func _field_row(label_text: String, row_name: String) -> VBoxContainer:
	var row := VBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 4)
	var label := _label(label_text, "SecondaryLabel", false)
	row.add_child(label)
	var input := LineEdit.new()
	input.name = "Value"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	return row


func _label(text: String, variation: String, wrap_text := false) -> Label:
	var label: Label = Widgets.label(tr(text), variation, wrap_text, false)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not text.is_empty():
		_set_locale_metadata(label, text)
	return label


func _localize_control(control: Control, english: String) -> void:
	control.set("text", tr(english))
	_set_locale_metadata(control, english)


func _set_locale_metadata(control: Control, english: String) -> void:
	control.set_meta("locale_en", english)
	_localized_controls.append(control)


func _error_node() -> Label:
	return find_child("MassDialogError", true, false) as Label


func _show_error(message: String, technical := false) -> void:
	var error := _error_node()
	if error == null:
		return
	if technical and technical_error_label != null:
		technical_error_label.text = message.left(MAX_DISPLAYED_ERRORS)
		technical_error_label.visible = true
		error.text = tr("The candidate did not pass validation. Review source inventory details for the reason.")
		if source_details_button != null:
			source_details_button.button_pressed = true
			_toggle_source_details(true)
	else:
		error.text = message.left(MAX_DISPLAYED_ERRORS)
	error.visible = true


func _clear_error() -> void:
	var error := _error_node()
	if error != null:
		error.text = ""
		error.visible = false
	if technical_error_label != null:
		technical_error_label.text = ""
		technical_error_label.visible = source_details_button.button_pressed


func _errors_text(value: Variant) -> String:
	var errors := PackedStringArray()
	if value is PackedStringArray:
		errors = value
	elif value is Array:
		for error: Variant in value:
			errors.append(str(error))
	return "; ".join(errors)


func _on_cancel() -> void:
	cancelled.emit()


func _toggle_source_details(shown: bool) -> void:
	if inventory_list != null:
		inventory_list.visible = shown
	if technical_error_label != null:
		technical_error_label.visible = shown and not technical_error_label.text.is_empty()
	if source_details_button != null and _inspection.get("inventory") is Array:
		var title := tr("Hide source inventory details") if shown \
			else tr("Show source inventory details")
		source_details_button.text = "%s (%d)" % [title, _inspection.inventory.size()]


func _on_custom_action(action: StringName) -> void:
	if action == &"apply_mass_build":
		_on_apply()


