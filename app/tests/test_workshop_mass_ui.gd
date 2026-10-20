extends SceneTree

const DialogScript := preload("res://ui/workshop_mass.gd")
const MassEdit := preload("res://workshop/mass_edit.gd")
const Compiler := preload("res://workshop/compiler.gd")
const UiDriver := preload("res://tests/ui_driver.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const BASE_PATH := "res://data/aircraft/jensen_ugly_stik_60.json"

var _failures := 0
var _checks := 0
var _ui: RefCounted


func _initialize() -> void:
	_ui = UiDriver.new(self)
	_run.call_deferred()


func _check(label: String, condition: bool, detail := "") -> void:
	_checks += 1
	if condition:
		print("ok   ", label)
	else:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _find(node: Node, child_name: String) -> Node:
	if child_name.contains("/"):
		return node.get_node_or_null(NodePath(child_name))
	return node.find_child(child_name, true, false)


func _activate(button: Control) -> void:
	button.grab_focus()
	await _ui.settle()
	await _ui.tap(KEY_ENTER)


func _run() -> void:
	TranslationServer.set_locale("en")
	UiTheme.text_scale = 1.0
	root.size = Vector2i(1280, 720)
	var parser := JSON.new()
	var base_text := FileAccess.get_file_as_string(BASE_PATH)
	_check("aircraft source fixture loads", parser.parse(base_text) == OK and parser.data is Dictionary)
	if not parser.data is Dictionary:
		quit(1)
		return
	var base: Dictionary = parser.data
	var original := base.duplicate(true)
	var inspection: Dictionary = MassEdit.inspect(base)
	_check("mass editor inspection succeeds", bool(inspection.get("ok", false)), str(inspection.get("errors", [])))
	if not inspection.get("ok", false):
		quit(1)
		return
	var second_id := ""
	var second_row: Dictionary = {}
	for row_variant: Variant in inspection.inventory:
		var row: Dictionary = row_variant
		if bool(row.get("editable", false)) and str(row.get("id", "")) != "item_engine_main":
			second_id = str(row.get("id", ""))
			second_row = row
			break
	_check("source contains a second eligible component", not second_id.is_empty())
	if second_id.is_empty():
		quit(1)
		return
	var engine_row: Dictionary = {}
	for row_variant: Variant in inspection.inventory:
		var row: Dictionary = row_variant
		if str(row.get("id", "")) == "item_engine_main": engine_row = row
	var first_edit := {
		"id": "item_engine_main", "mass_kg": float(engine_row.mass_kg),
		"source": "existing calibrated scale record",
	}
	var recipe := Compiler.defaults()
	recipe["mass_edits"] = [first_edit]
	var dialog: ConfirmationDialog = DialogScript.new()
	dialog.configure(base, recipe)
	var proposals: Array[Dictionary] = []
	var cancellations := [0]
	dialog.recipe_proposed.connect(func(candidate: Dictionary) -> void: proposals.append(candidate))
	dialog.cancelled.connect(func() -> void: cancellations[0] += 1)
	root.add_child(dialog)
	dialog.popup_centered_clamped(Vector2i(820, 560), 0.9)
	await _ui.settle()
	_check("native confirmation modal starts with Cancel focus", dialog.gui_get_focus_owner() == dialog.get_cancel_button(), str(dialog.gui_get_focus_owner()))
	_check("panel and vertical scroll are present at 720p", _find(dialog, "MassDialogScroll") is ScrollContainer)
	_check("inventory disclosure starts collapsed beside the measurement form",
		_find(dialog, "InventoryRows").get_child_count() == inspection.inventory.size()
		and not (_find(dialog, "InventoryRows") as Control).visible)
	await _activate(_find(dialog, "SourceDetailsToggle") as Button)
	_check("source details reveal stable IDs, LE positions, provenance and refusal reasons",
		(_find(dialog, "InventoryRows") as Control).visible
		and str(_find(dialog, "InventoryRows").get_child(0).get("text")).contains("item_")
		and str(_find(dialog, "InventoryRows").get_child(0).get("text")).contains("LE"))
	var fuel_reason_visible := false
	for card: Node in _find(dialog, "InventoryRows").get_children():
		var text := str(card.get("text"))
		if text.contains("item_fuel_main") and text.contains("Unavailable:") and text.contains("fuel"):
			fuel_reason_visible = true
	_check("unavailable finite-fuel reason is visible", fuel_reason_visible)
	await _activate(_find(dialog, "SourceDetailsToggle") as Button)
	_check("source-declared empty-tanks state is explicit", ( _find(dialog, "WeighingState") as Label).text.contains("empty_tanks"))

	var picker := _find(dialog, "MassComponent") as OptionButton
	var target_index := -1
	for index: int in range(picker.item_count):
		if str(picker.get_item_metadata(index)) == second_id:
			target_index = index
			break
	var selected_detail := str(_find(dialog, "SelectedComponentDetails").get("text"))
	_check("component picker shows source names while IDs stay in metadata and primary details stay concise",
		target_index >= 0 and picker.get_item_text(target_index) == str(second_row.get("name", ""))
		and str(picker.get_item_metadata(target_index)) == second_id
		and selected_detail.begins_with("Source mass:") and not selected_detail.contains("item_")
		and not selected_detail.contains("LE"))
	if target_index >= 0:
		picker.select(target_index)
		picker.item_selected.emit(target_index)
	var mass_input := _find(dialog, "MassDialogScroll/MassDialogContent/MassKg/Value") as LineEdit
	var source_input := _find(dialog, "MassDialogScroll/MassDialogContent/MeasurementSource/Value") as LineEdit
	mass_input.text = "%.6f" % float(second_row.mass_kg)
	source_input.text = "component isolated on calibrated scale"
	dialog.call("_on_measurement_changed", mass_input.text)
	var alternate_index := 0 if target_index != 0 else 1
	if picker.item_count > alternate_index:
		picker.select(alternate_index)
		picker.item_selected.emit(alternate_index)
		_check("changing selection preserves a pending measurement", picker.selected == target_index
			and mass_input.text == "%.6f" % float(second_row.mass_kg)
			and source_input.text == "component isolated on calibrated scale")
	await _activate(_find(dialog, "StageMeasurement") as Button)
	_check("staging validates and preserves the existing measured entry", dialog.get("_staged_edits").size() == 2
		and dialog.get("_staged_edits")[0].id == "item_engine_main"
		and dialog.get("_staged_edits")[1].id == second_id)
	_check("staging does not mutate the source record", base == original)
	_check("read-only target report presents residuals", str((_find(dialog, "TargetReport") as Label).text).contains("CG Δ"))

	await _activate(_find(dialog, "SolveFixedStation") as Button)
	_check("fixed-station action is a derived proposal only", str((_find(dialog, "FixedStationProposal") as Label).text).contains("derived")
		and str((_find(dialog, "FixedStationProposal") as Label).text).contains("not applied"))
	await _activate(dialog.get_cancel_button())
	_check("Cancel dismisses without proposing a recipe", proposals.is_empty() and cancellations[0] > 0 and not dialog.visible)
	dialog.queue_free()
	await _ui.settle()

	# The accepted Apply action validates both the mass core and the complete compiler result.
	var apply_dialog: ConfirmationDialog = DialogScript.new()
	apply_dialog.configure(base, recipe)
	var apply_proposals: Array[Dictionary] = []
	apply_dialog.recipe_proposed.connect(func(candidate: Dictionary) -> void: apply_proposals.append(candidate))
	root.add_child(apply_dialog)
	apply_dialog.popup_centered_clamped(Vector2i(820, 560), 0.9)
	await _ui.settle()
	var apply_picker := _find(apply_dialog, "MassComponent") as OptionButton
	for index: int in range(apply_picker.item_count):
		if str(apply_picker.get_item_metadata(index)) == second_id:
			apply_picker.select(index)
			apply_picker.item_selected.emit(index)
	var apply_mass := _find(apply_dialog, "MassDialogScroll/MassDialogContent/MassKg/Value") as LineEdit
	var apply_source := _find(apply_dialog, "MassDialogScroll/MassDialogContent/MeasurementSource/Value") as LineEdit
	apply_mass.text = "%.6f" % float(second_row.mass_kg)
	apply_source.text = "component isolated on calibrated scale"
	await _activate(_find(apply_dialog, "StageMeasurement") as Button)
	await _activate(_find(apply_dialog, "ApplyMassBuild") as Button)
	_check("Apply emits only a fully compiled new-build recipe", apply_proposals.size() == 1
		and apply_proposals[0].mass_edits.size() == 2 and Compiler.compile(base, apply_proposals[0]).ok,
		str(_find(apply_dialog, "MassDialogError").text))
	_check("proposed recipe retains the earlier component measurement", apply_proposals.size() == 1
		and apply_proposals[0].mass_edits[0] == first_edit and base == original)
	apply_dialog.queue_free()
	await _ui.settle()

	# Compiler rejection is shown in the modal and does not publish a partial proposal.
	var invalid_recipe := recipe.duplicate(true)
	invalid_recipe.scale = 0.95
	var invalid_dialog: ConfirmationDialog = DialogScript.new()
	invalid_dialog.configure(base, invalid_recipe)
	var invalid_proposals := [0]
	invalid_dialog.recipe_proposed.connect(func(_candidate: Dictionary) -> void: invalid_proposals[0] += 1)
	root.add_child(invalid_dialog)
	invalid_dialog.popup_centered_clamped(Vector2i(820, 560), 0.9)
	await _ui.settle()
	await _activate(_find(invalid_dialog, "ApplyMassBuild") as Button)
	_check("compiler failure is visible and emits nothing", invalid_proposals[0] == 0
		and (_find(invalid_dialog, "MassDialogError") as Label).visible
		and (_find(invalid_dialog, "TechnicalValidationDetails") as Label).text.contains("mass_edits"),
		str((_find(invalid_dialog, "TechnicalValidationDetails") as Label).text))
	invalid_dialog.queue_free()
	await _ui.settle()

	# Locale and enlarged text use the same native modal and scrollable content.
	TranslationServer.set_locale("es")
	UiTheme.text_scale = 2.0
	var spanish_dialog: ConfirmationDialog = DialogScript.new()
	spanish_dialog.configure(base, Compiler.defaults())
	root.add_child(spanish_dialog)
	spanish_dialog.popup_centered_clamped(Vector2i(900, 620), 0.9)
	await _ui.settle()
	var view := Rect2(Vector2.ZERO, Vector2(root.size))
	_check("Spanish title, action and Cancel are localized", spanish_dialog.title == "Masa medida de componentes"
		and (_find(spanish_dialog, "StageMeasurement") as Button).text == "Agregar o actualizar medición"
		and spanish_dialog.get_cancel_button().text == "Cancelar"
		and str((_find(spanish_dialog, "MassDialogContent") as VBoxContainer).get_child(0).get("text"))
			== "Registra la masa medida del componente. Se conserva la geometría."
		and str(_find(spanish_dialog, "SelectedComponentDetails").get("text")).begins_with("Masa de origen:"))
	_check("200 percent text remains inside the 720p viewport with vertical scrolling",
		view.encloses(Rect2(spanish_dialog.position, Vector2(spanish_dialog.size)))
		and (_find(spanish_dialog, "MassDialogScroll") as ScrollContainer).horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED
		and (_find(spanish_dialog, "MassDialogScroll") as ScrollContainer).size.y > 0.0,
		"pos=%s size=%s scroll=%s" % [spanish_dialog.position, spanish_dialog.size, (_find(spanish_dialog, "MassDialogScroll") as ScrollContainer).size])
	spanish_dialog.queue_free()
	await _ui.settle()
	UiTheme.text_scale = 1.0
	TranslationServer.set_locale("en")
	print("Workshop mass dialog: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)
