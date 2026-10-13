extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Store := preload("res://workshop/store.gd")
const WorkshopPreview := preload("res://ui/workshop_preview.gd")

signal closed
signal trial_requested(payload: Dictionary)

const LAYER := 20
const VARIANT_ROOT := "user://aircraft_variants"
const FACTOR_MIN := 0.75
const FACTOR_MAX := 1.25
const FACTOR_STEP := 0.05
const SCALE_OPTIONS := [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
const FACTOR_CAPABILITIES := {
	"weight_multiplier": "weight",
	"power_multiplier": "power",
	"control_multiplier": "controls",
}
const PRESETS := {
	"mini": {"scale": 0.75, "mass_policy": "constant_wing_loading", "weight_multiplier": 1.0, "power_multiplier": 0.9, "control_multiplier": 0.9},
	"giant": {"scale": 1.5, "mass_policy": "geometric", "weight_multiplier": 1.0, "power_multiplier": 1.1, "control_multiplier": 1.1},
	"light": {"scale": 1.0, "mass_policy": "constant_wing_loading", "weight_multiplier": 0.8, "power_multiplier": 1.0, "control_multiplier": 1.0},
	"heavy": {"scale": 1.0, "mass_policy": "constant_wing_loading", "weight_multiplier": 1.2, "power_multiplier": 1.15, "control_multiplier": 1.0},
	"fast": {"scale": 1.0, "mass_policy": "constant_wing_loading", "weight_multiplier": 1.0, "power_multiplier": 1.2, "control_multiplier": 1.15},
	"agile": {"scale": 1.0, "mass_policy": "geometric", "weight_multiplier": 0.9, "power_multiplier": 1.0, "control_multiplier": 1.2},
}

## Set before adding this screen to the ScreenStack. Defaults to the current catalog aircraft.
var initial_aircraft_id := Catalog.DEFAULT_ID

## Public handles for UI integration and focused Workshop checks.
var variant_name_input: LineEdit:
	get:
		return _variant_name
var save_button: Button:
	get:
		return _save_button

var _screen: Control
var _base_selector: OptionButton
var _variant_selector: OptionButton
var _variant_name: LineEdit
var _save_button: Button
var _load_button: Button
var _delete_button: Button
var _scale_selector: OptionButton
var _mass_policy_selector: OptionButton
var _factor_sliders: Dictionary = {}
var _factor_values: Dictionary = {}
var _factor_hints: Dictionary = {}
var _preset_buttons: Dictionary = {}
var _summary_label: Label
var _errors_label: Label
var _status_label: Label
var _capabilities_label: Label
var _aircraft_summary_label: Label
var _aircraft_status_label: Label
var _validation_label: Label
var _trial_button: Button
var _undo_button: Button
var _preview: WorkshopPreview
var _delete_dialog: ConfirmationDialog

var _base_id := ""
var _base: Dictionary = {}
var _base_bytes := PackedByteArray()
var _workshop_descriptor: Dictionary = {}
var _recipe: Dictionary = {}
var _compiled: Dictionary = {"ok": false, "errors": ["Choose an aircraft to begin."]}
var _capabilities: Dictionary = {}
var _selected_variant_id := ""
var _undo_recipe: Dictionary = {}
var _undo_available := false
var _slider_gesture := false
var _syncing_controls := false
var _closing := false
var _trial_pending := false


func _init() -> void:
	name = "Workshop"
	layer = LAYER
	_screen = Screen.mount(self, "Screen")
	_screen.kind = Screen.Kind.MODAL
	_screen.close_requested.connect(_request_close)
	_screen.dim(0.72, "WorkshopDim")
	_build_ui()
	_build_delete_dialog()


func _ready() -> void:
	_load_catalog_aircraft(initial_aircraft_id, false)
	_refresh_variants()
	_sync_controls()
	_compile_recipe()
	_base_selector.grab_focus.call_deferred()


func _enter_tree() -> void:
	if _trial_pending:
		_trial_pending = false
		if is_instance_valid(_trial_button):
			_trial_button.disabled = not bool(_compiled.get("ok", false))


## A start failure returns to the same Workshop instance; show the reason below its actions.
func reject_start(message: String = "The trial could not start.") -> void:
	set_note(message)


func set_note(message: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = tr(message) if message != "" else ""
		_status_label.visible = message != ""
	if _trial_pending:
		_trial_pending = false
	if is_instance_valid(_trial_button):
		_trial_button.disabled = not bool(_compiled.get("ok", false))


## Test and integration seam: update the recipe through the same constraints as the visible controls.
func set_recipe(recipe: Dictionary, remember_current := true) -> void:
	if _base.is_empty():
		return
	var next: Dictionary = Compiler.defaults()
	next.merge(recipe, true)
	_set_recipe(next, remember_current)


func get_recipe() -> Dictionary:
	return _recipe.duplicate(true)


func get_compiled() -> Dictionary:
	return _compiled.duplicate(true)


func set_variant_name(value: String) -> void:
	if is_instance_valid(_variant_name):
		_variant_name.text = value


func save_named_variant() -> void:
	_save_variant()


func set_aircraft(id: String) -> void:
	if not is_node_ready():
		initial_aircraft_id = id
		return
	_selected_variant_id = ""
	if is_instance_valid(_variant_selector):
		_variant_selector.select(0)
	if is_instance_valid(_variant_name):
		_variant_name.clear()
	_load_catalog_aircraft(id, false)
	_sync_controls()
	_sync_variant_actions()


func _build_ui() -> void:
	var outer := MarginContainer.new()
	outer.name = "WorkshopMargins"
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 24)
	outer.add_theme_constant_override("margin_top", 18)
	outer.add_theme_constant_override("margin_right", 24)
	outer.add_theme_constant_override("margin_bottom", 18)
	_screen.add_child(outer)

	var shell := PanelContainer.new()
	shell.name = "WorkshopPanel"
	shell.theme_type_variation = "Sidebar"
	shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(shell)

	var page := VBoxContainer.new()
	page.name = "WorkshopPage"
	page.add_theme_constant_override("separation", 12)
	shell.add_child(page)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label("Aircraft Workshop", "TitleLabel")
	title.name = "WorkshopTitle"
	heading.add_child(title)
	var introduction := _label("Build a variant from any aircraft in the catalog. Changes are experimental.", "SecondaryLabel", true)
	introduction.name = "WorkshopIntroduction"
	heading.add_child(introduction)
	header.add_child(heading)
	var close_button := _button("Close", "", "CloseWorkshop")
	close_button.pressed.connect(_request_close)
	header.add_child(close_button)
	page.add_child(header)

	var body_scroll := ScrollContainer.new()
	body_scroll.name = "WorkshopScroll"
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body_scroll)

	var columns := HBoxContainer.new()
	columns.name = "WorkshopColumns"
	columns.add_theme_constant_override("separation", 18)
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(columns)

	var left := VBoxContainer.new()
	left.name = "AircraftColumn"
	left.custom_minimum_size.x = 390
	left.size_flags_horizontal = Control.SIZE_FILL
	left.add_theme_constant_override("separation", 10)
	columns.add_child(left)
	_build_aircraft_panel(left)
	_build_variants_panel(left)
	_build_presets_panel(left)

	var right := VBoxContainer.new()
	right.name = "RecipeColumn"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	columns.add_child(right)
	_build_recipe_panel(right)
	_build_results_panel(right)

	var footer := HBoxContainer.new()
	footer.name = "WorkshopActions"
	footer.add_theme_constant_override("separation", 10)
	var reset_button := _button("Reset", "", "ResetRecipe")
	reset_button.pressed.connect(_reset_recipe)
	footer.add_child(reset_button)
	_undo_button = _button("Undo", "", "UndoRecipe")
	_undo_button.disabled = true
	_undo_button.pressed.connect(_undo)
	footer.add_child(_undo_button)
	_status_label = _label("", "SecondaryLabel", true)
	_status_label.name = "WorkshopStatus"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.visible = false
	footer.add_child(_status_label)
	_trial_button = _button("Test fly", "PrimaryButton", "TestFly")
	_trial_button.custom_minimum_size = Vector2(190, 54)
	_trial_button.pressed.connect(_request_trial)
	footer.add_child(_trial_button)
	page.add_child(footer)


func _build_aircraft_panel(parent: VBoxContainer) -> void:
	var card := _card("BaseAircraftCard")
	parent.add_child(card)
	var content := _card_content(card)
	content.add_child(_section_label("AIRCRAFT"))
	_base_selector = OptionButton.new()
	_base_selector.name = "BaseAircraft"
	_base_selector.focus_mode = Control.FOCUS_ALL
	_base_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry: Dictionary in Catalog.ENTRIES:
		_base_selector.add_item(str(entry.get("name", entry.get("id", "Aircraft"))))
		var index := _base_selector.item_count - 1
		_base_selector.set_item_metadata(index, str(entry.get("id", "")))
		_base_selector.set_item_tooltip(index, str(entry.get("summary", "")) + "\n" + str(entry.get("status_note", "")))
	_base_selector.item_selected.connect(_on_base_selected)
	content.add_child(_base_selector)
	_aircraft_summary_label = _label("", "SecondaryLabel", true)
	_aircraft_summary_label.name = "AircraftSummary"
	content.add_child(_aircraft_summary_label)
	_aircraft_status_label = _label("", "SecondaryLabel", true)
	_aircraft_status_label.name = "AircraftStatus"
	content.add_child(_aircraft_status_label)

	_preview = WorkshopPreview.new()
	_preview.name = "AircraftPreview"
	_preview.custom_minimum_size = Vector2(380, 250)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_preview)
	var preview_caption := _label("Still preview · no flight simulation", "SecondaryLabel")
	preview_caption.name = "PreviewCaption"
	content.add_child(preview_caption)
	_validation_label = _label("Experimental build · schema validation does not establish flight behavior.", "SecondaryLabel", true)
	_validation_label.name = "ValidationLimit"
	content.add_child(_validation_label)


func _build_variants_panel(parent: VBoxContainer) -> void:
	var card := _card("SavedVariantsCard")
	parent.add_child(card)
	var content := _card_content(card)
	content.add_child(_section_label("SAVED BUILDS"))
	_variant_selector = OptionButton.new()
	_variant_selector.name = "SavedVariant"
	_variant_selector.focus_mode = Control.FOCUS_ALL
	_variant_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_variant_selector.item_selected.connect(_on_variant_selected)
	content.add_child(_variant_selector)

	var variant_actions := HBoxContainer.new()
	variant_actions.add_theme_constant_override("separation", 8)
	_load_button = _button("Load", "", "LoadVariant")
	_load_button.disabled = true
	_load_button.pressed.connect(_load_selected_variant)
	variant_actions.add_child(_load_button)
	_delete_button = _button("Delete", "", "DeleteVariant")
	_delete_button.disabled = true
	_delete_button.pressed.connect(_confirm_delete_selected)
	variant_actions.add_child(_delete_button)
	content.add_child(variant_actions)

	_variant_name = LineEdit.new()
	_variant_name.name = "VariantName"
	_variant_name.placeholder_text = tr("Name this build")
	_variant_name.max_length = 64
	_variant_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_variant_name.text_changed.connect(_on_variant_name_changed)
	content.add_child(_variant_name)
	_save_button = _button("Save build", "", "SaveVariant")
	_save_button.disabled = true
	_save_button.pressed.connect(_save_variant)
	content.add_child(_save_button)


func _build_presets_panel(parent: VBoxContainer) -> void:
	var card := _card("PresetsCard")
	parent.add_child(card)
	var content := _card_content(card)
	content.add_child(_section_label("STARTING PRESETS"))
	var grid := GridContainer.new()
	grid.name = "PresetGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for preset_id: String in ["mini", "giant", "light", "heavy", "fast", "agile"]:
		var preset_button := _button(preset_id.capitalize(), "", "Preset" + preset_id.capitalize())
		preset_button.pressed.connect(_apply_preset.bind(preset_id))
		grid.add_child(preset_button)
		_preset_buttons[preset_id] = preset_button
	content.add_child(grid)
	var note := _label("Presets change only adjustments supported by the selected airframe.", "SecondaryLabel", true)
	content.add_child(note)


func _build_recipe_panel(parent: VBoxContainer) -> void:
	var card := _card("RecipeCard")
	parent.add_child(card)
	var content := _card_content(card)
	content.add_child(_section_label("AIRFRAME RECIPE · EXPERIMENTAL"))

	var selector_grid := GridContainer.new()
	selector_grid.name = "RecipeSelectors"
	selector_grid.columns = 2
	selector_grid.add_theme_constant_override("h_separation", 16)
	selector_grid.add_theme_constant_override("v_separation", 8)
	selector_grid.add_child(_label("Airframe scale", "SecondaryLabel"))
	_scale_selector = OptionButton.new()
	_scale_selector.name = "Scale"
	_scale_selector.focus_mode = Control.FOCUS_ALL
	_scale_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for scale: float in SCALE_OPTIONS:
		_scale_selector.add_item("%d%%" % roundi(scale * 100.0))
		_scale_selector.set_item_metadata(_scale_selector.item_count - 1, scale)
	_scale_selector.item_selected.connect(_on_scale_selected)
	selector_grid.add_child(_scale_selector)
	selector_grid.add_child(_label("Mass scaling", "SecondaryLabel"))
	_mass_policy_selector = OptionButton.new()
	_mass_policy_selector.name = "MassPolicy"
	_mass_policy_selector.focus_mode = Control.FOCUS_ALL
	_mass_policy_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mass_policy_selector.add_item("Constant wing loading")
	_mass_policy_selector.set_item_metadata(0, "constant_wing_loading")
	_mass_policy_selector.add_item("Geometric")
	_mass_policy_selector.set_item_metadata(1, "geometric")
	_mass_policy_selector.item_selected.connect(_on_mass_policy_selected)
	_mass_policy_selector.tooltip_text = tr("Constant wing loading preserves wing loading as size changes. Geometric scales mass with volume.")
	selector_grid.add_child(_mass_policy_selector)
	content.add_child(selector_grid)

	var factor_hint := _label("Multipliers are constrained to 0.75×–1.25× for this experimental editor.", "SecondaryLabel", true)
	content.add_child(factor_hint)
	_add_factor_row(content, "weight_multiplier", "Weight multiplier")
	_add_factor_row(content, "power_multiplier", "Power multiplier")
	_add_factor_row(content, "control_multiplier", "Control response")

	_capabilities_label = _label("", "SecondaryLabel", true)
	_capabilities_label.name = "Capabilities"
	content.add_child(_capabilities_label)


func _build_results_panel(parent: VBoxContainer) -> void:
	var card := _card("BuildResultsCard")
	parent.add_child(card)
	var content := _card_content(card)
	content.add_child(_section_label("BUILD CHECK"))
	_errors_label = _label("", "SecondaryLabel", true)
	_errors_label.name = "BuildErrors"
	_errors_label.visible = false
	content.add_child(_errors_label)
	_summary_label = _label("", "SecondaryLabel", true)
	_summary_label.name = "BuildSummary"
	_summary_label.custom_minimum_size.y = 78
	content.add_child(_summary_label)


func _add_factor_row(parent: VBoxContainer, key: String, caption: String) -> void:
	var row := VBoxContainer.new()
	row.name = key.capitalize()
	row.add_theme_constant_override("separation", 3)
	var heading := HBoxContainer.new()
	var caption_label := _label(caption + " · Experimental", "SecondaryLabel")
	caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(caption_label)
	var value_label := _label("1.00×", "SecondaryLabel")
	value_label.name = key.capitalize() + "Value"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(value_label)
	row.add_child(heading)
	var slider := HSlider.new()
	slider.name = key.capitalize() + "Slider"
	slider.focus_mode = Control.FOCUS_ALL
	slider.min_value = FACTOR_MIN
	slider.max_value = FACTOR_MAX
	slider.step = FACTOR_STEP
	slider.tick_count = 11
	slider.ticks_on_borders = true
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_factor_value_changed.bind(key))
	slider.drag_started.connect(_on_slider_drag_started)
	slider.drag_ended.connect(_on_slider_drag_ended)
	row.add_child(slider)
	var hint := _label("", "SecondaryLabel", true)
	hint.name = key.capitalize() + "Support"
	row.add_child(hint)
	parent.add_child(row)
	_factor_sliders[key] = slider
	_factor_values[key] = value_label
	_factor_hints[key] = hint


func _build_delete_dialog() -> void:
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = tr("Delete saved build?")
	_delete_dialog.dialog_text = tr("Delete this saved build from this device?")
	_delete_dialog.confirmed.connect(_delete_selected_variant)
	add_child(_delete_dialog)


func _load_catalog_aircraft(id: String, preserve_recipe: bool) -> void:
	_workshop_descriptor.clear()
	var entry := Catalog.entry(id)
	if entry.is_empty():
		entry = Catalog.entry(Catalog.DEFAULT_ID)
		id = Catalog.DEFAULT_ID
	_base_id = str(entry.get("id", Catalog.DEFAULT_ID))
	_select_base(_base_id)
	_capabilities = {"scale": false, "weight": false, "power": false, "controls": false}
	_update_capabilities()
	_selected_variant_id = ""
	var path := str(entry.get("data", ""))
	if path.is_empty():
		_base = {}
		_base_bytes = PackedByteArray()
		_compiled = {"ok": false, "errors": ["This catalog entry has no flight data."]}
		if is_instance_valid(_preview):
			_preview.set_aircraft(_base_id, 1.0)
		set_note("This aircraft is a visual preview and has no flight data.")
		_update_aircraft_description(entry)
		return
	var loaded := AircraftData.load_file(path)
	if not bool(loaded.get("ok", false)):
		_base = {}
		_base_bytes = PackedByteArray()
		_compiled = {"ok": false, "errors": loaded.get("errors", ["Aircraft data could not be loaded."])}
		if is_instance_valid(_preview):
			_preview.set_aircraft(_base_id, 1.0)
		_update_aircraft_description(entry)
		return
	var loaded_model: Dictionary = loaded.get("model", {})
	_base = loaded_model.duplicate(true)
	_base_bytes = FileAccess.get_file_as_bytes(path)
	if _base_bytes.is_empty():
		_compiled = {"ok": false, "errors": ["Source aircraft bytes could not be read."]}
		if is_instance_valid(_preview):
			_preview.set_aircraft(_base_id, 1.0)
		_update_aircraft_description(entry)
		return
	if not preserve_recipe:
		_recipe = Compiler.defaults()
		_undo_recipe.clear()
		_undo_available = false
	_capabilities = Compiler.capabilities(_base)
	_selected_variant_id = ""
	_update_aircraft_description(entry)
	_update_capabilities()
	_update_undo_button()
	if is_instance_valid(_preview):
		_preview.set_aircraft(_base_id, _preview_scale())
	_compile_recipe()


func _update_aircraft_description(entry: Dictionary) -> void:
	if is_instance_valid(_aircraft_summary_label):
		_aircraft_summary_label.text = tr(str(entry.get("summary", "")))
	if is_instance_valid(_aircraft_status_label):
		var status := str(entry.get("status", ""))
		var status_note := str(entry.get("status_note", ""))
		_aircraft_status_label.text = tr(status_note) if status_note != "" else tr(status.capitalize())
		_aircraft_status_label.visible = _aircraft_status_label.text != ""


func _select_base(id: String) -> void:
	if not is_instance_valid(_base_selector):
		return
	for index in _base_selector.item_count:
		if str(_base_selector.get_item_metadata(index)) == id:
			_base_selector.select(index)
			return


func _refresh_variants() -> void:
	_variant_selector.clear()
	_variant_selector.add_item(tr("Choose a saved build…"))
	_variant_selector.set_item_metadata(0, "")
	var variants: Array = Store.list_variants(VARIANT_ROOT)
	for variant: Dictionary in variants:
		var variant_id := str(variant.get("id", ""))
		if variant_id == "":
			continue
		_variant_selector.add_item(str(variant.get("name", variant_id)))
		_variant_selector.set_item_metadata(_variant_selector.item_count - 1, variant_id)
	_variant_selector.select(0)
	_selected_variant_id = ""
	_sync_variant_actions()


func _sync_variant_actions() -> void:
	var available := _selected_variant_id != ""
	_load_button.disabled = not available
	_delete_button.disabled = not available
	_sync_save_button()


func _sync_save_button() -> void:
	_save_button.disabled = _variant_name.text.strip_edges().is_empty() or not bool(_compiled.get("ok", false))


func _on_base_selected(index: int) -> void:
	var id := str(_base_selector.get_item_metadata(index))
	if id == "" or id == _base_id:
		return
	_selected_variant_id = ""
	_variant_selector.select(0)
	_variant_name.clear()
	_load_catalog_aircraft(id, false)
	_sync_controls()
	_sync_variant_actions()


func _on_variant_selected(index: int) -> void:
	_selected_variant_id = str(_variant_selector.get_item_metadata(index))
	_sync_variant_actions()


func _load_selected_variant() -> void:
	if _selected_variant_id == "":
		return
	var result: Dictionary = Store.load_variant(_selected_variant_id, VARIANT_ROOT)
	if not bool(result.get("ok", false)):
		set_note(_messages(result.get("errors", []), "The saved build could not be loaded."))
		return
	var variant: Dictionary = result.get("variant", {})
	if variant.is_empty() or not variant.get("base", {}) is Dictionary:
		set_note("The saved build has no aircraft data.")
		return
	var snapshot_bytes: Variant = variant.get("base_bytes", PackedByteArray())
	if not snapshot_bytes is PackedByteArray or snapshot_bytes.is_empty():
		set_note("The saved build has no exact aircraft source snapshot.")
		return
	_base_id = str(variant.get("base_id", ""))
	if Catalog.entry(_base_id).is_empty():
		set_note("The saved build refers to an unknown catalog aircraft.")
		return
	_base = (variant.base as Dictionary).duplicate(true)
	_base_bytes = snapshot_bytes.duplicate()
	var saved_descriptor: Variant = variant.get("workshop_descriptor", {})
	_workshop_descriptor = saved_descriptor.duplicate(true) if saved_descriptor is Dictionary else {}
	_recipe = Compiler.defaults()
	if variant.get("recipe", {}) is Dictionary:
		_recipe.merge(variant.recipe, true)
	_capabilities = Compiler.capabilities(_base)
	_variant_name.text = str(variant.get("name", ""))
	_select_base(_base_id)
	_update_aircraft_description(Catalog.entry(_base_id))
	_update_capabilities()
	_sync_controls()
	_preview.set_aircraft(_base_id, _preview_scale())
	_compile_recipe()
	set_note("Saved build loaded. Review the experimental values before a trial.")
	_sync_variant_actions()


func _save_variant() -> void:
	var display_name := _variant_name.text.strip_edges()
	if display_name.is_empty() or not bool(_compiled.get("ok", false)):
		return
	var result: Dictionary = Store.save_variant(
		display_name,
		_base_id,
		_base_bytes,
		_recipe.duplicate(true),
		"",
		VARIANT_ROOT,
		_workshop_descriptor.duplicate(true)
	)
	if not bool(result.get("ok", false)):
		set_note(_messages(result.get("errors", []), "The build could not be saved."))
		return
	var variant: Dictionary = result.get("variant", {})
	var saved_descriptor: Variant = variant.get("workshop_descriptor", {})
	_workshop_descriptor = saved_descriptor.duplicate(true) if saved_descriptor is Dictionary else {}
	set_note(tr("Saved build: %s") % str(variant.get("name", display_name)))
	_refresh_variants()
	_select_variant(str(variant.get("id", "")))
	_sync_variant_actions()


func _confirm_delete_selected() -> void:
	if _selected_variant_id == "":
		return
	_delete_dialog.popup_centered()


func _delete_selected_variant() -> void:
	if _selected_variant_id == "":
		return
	var deleting_id := _selected_variant_id
	var result: Dictionary = Store.delete_variant(deleting_id, VARIANT_ROOT)
	if not bool(result.get("ok", false)):
		set_note(_messages(result.get("errors", []), "The saved build could not be deleted."))
		return
	_refresh_variants()
	set_note("Saved build deleted.")


func _select_variant(id: String) -> void:
	if id == "":
		return
	for index in _variant_selector.item_count:
		if str(_variant_selector.get_item_metadata(index)) == id:
			_variant_selector.select(index)
			_selected_variant_id = id
			return


func _on_variant_name_changed(_text: String) -> void:
	_sync_save_button()


func _on_scale_selected(index: int) -> void:
	if _syncing_controls or _base.is_empty():
		return
	_capture_undo()
	_recipe["scale"] = float(_scale_selector.get_item_metadata(index))
	_preview.set_aircraft(_base_id, _preview_scale())
	_compile_recipe()


func _on_mass_policy_selected(index: int) -> void:
	if _syncing_controls or _base.is_empty():
		return
	_capture_undo()
	_recipe["mass_policy"] = str(_mass_policy_selector.get_item_metadata(index))
	_compile_recipe()


func _on_factor_value_changed(value: float, key: String) -> void:
	if _syncing_controls or _base.is_empty():
		return
	if not _slider_gesture:
		_capture_undo()
	_recipe[key] = clampf(value, FACTOR_MIN, FACTOR_MAX)
	_factor_values[key].text = "%.2f×" % value
	_compile_recipe()


func _on_slider_drag_started() -> void:
	if not _syncing_controls:
		_capture_undo()
		_slider_gesture = true


func _on_slider_drag_ended(_changed: bool) -> void:
	_slider_gesture = false


func _apply_preset(preset_id: String) -> void:
	if _base.is_empty() or not PRESETS.has(preset_id):
		return
	var next: Dictionary = Compiler.defaults()
	var preset: Dictionary = PRESETS[preset_id]
	var caps: Dictionary = Compiler.capabilities(_base)
	for key in ["scale", "mass_policy"]:
		if key == "scale" and not bool(caps.get("scale", false)):
			next[key] = _recipe.get(key, next[key])
		elif key == "mass_policy" and not bool(caps.get("weight", false)):
			next[key] = _recipe.get(key, next[key])
		else:
			next[key] = preset.get(key, next[key])
	for key: String in FACTOR_CAPABILITIES:
		var capability := str(FACTOR_CAPABILITIES[key])
		next[key] = preset.get(key, next.get(key, 1.0)) if bool(caps.get(capability, false)) else _recipe.get(key, next.get(key, 1.0))
	_set_recipe(next, true)
	set_note(tr("Applied the %s preset where this aircraft supports it.") % preset_id.capitalize())


func _reset_recipe() -> void:
	if _base.is_empty():
		return
	_set_recipe(Compiler.defaults(), true)
	set_note("Recipe reset to defaults. Use Undo to restore the previous values.")


func _undo() -> void:
	if not _undo_available:
		return
	var previous := _undo_recipe.duplicate(true)
	_undo_available = false
	_undo_recipe.clear()
	_set_recipe(previous, false)
	_update_undo_button()
	set_note("Previous recipe restored.")


func _set_recipe(next_recipe: Dictionary, remember_current: bool) -> void:
	if remember_current:
		_capture_undo()
	_recipe = Compiler.defaults()
	_recipe.merge(next_recipe, true)
	_sync_controls()
	if is_instance_valid(_preview):
		_preview.set_aircraft(_base_id, _preview_scale())
	_compile_recipe()


func _preview_scale() -> float:
	return float(_recipe.get("scale", 1.0)) if bool(_capabilities.get("scale", false)) else 1.0


func _capture_undo() -> void:
	_undo_recipe = _recipe.duplicate(true)
	_undo_available = true
	_update_undo_button()


func _update_undo_button() -> void:
	if is_instance_valid(_undo_button):
		_undo_button.disabled = not _undo_available


func _sync_controls() -> void:
	if not is_instance_valid(_scale_selector) or _recipe.is_empty():
		return
	_syncing_controls = true
	var scale := _nearest_scale(float(_recipe.get("scale", 1.0)))
	_recipe["scale"] = scale
	for index in _scale_selector.item_count:
		if is_equal_approx(float(_scale_selector.get_item_metadata(index)), scale):
			_scale_selector.select(index)
			break
	_scale_selector.disabled = not bool(_capabilities.get("scale", false))
	var policy := str(_recipe.get("mass_policy", "constant_wing_loading"))
	if policy not in ["constant_wing_loading", "geometric"]:
		policy = "constant_wing_loading"
		_recipe["mass_policy"] = policy
	for index in _mass_policy_selector.item_count:
		if str(_mass_policy_selector.get_item_metadata(index)) == policy:
			_mass_policy_selector.select(index)
			break
	_mass_policy_selector.disabled = not bool(_capabilities.get("weight", false))
	for key: String in FACTOR_CAPABILITIES:
		var value := clampf(float(_recipe.get(key, 1.0)), FACTOR_MIN, FACTOR_MAX)
		_recipe[key] = value
		_factor_sliders[key].set_value_no_signal(value)
		_factor_values[key].text = "%.2f×" % value
		var supported := bool(_capabilities.get(str(FACTOR_CAPABILITIES[key]), false))
		_factor_sliders[key].editable = supported
		_factor_hints[key].text = tr("Range 0.75×–1.25× · experimental adjustment.") if supported else tr("Unavailable for this aircraft; the saved value remains unchanged.")
	_syncing_controls = false
	_update_capabilities()
	_update_undo_button()
	_sync_save_button()


func _nearest_scale(requested: float) -> float:
	var nearest := float(SCALE_OPTIONS[0])
	var distance := absf(requested - nearest)
	for option: float in SCALE_OPTIONS:
		var candidate_distance := absf(requested - option)
		if candidate_distance < distance:
			nearest = option
			distance = candidate_distance
	return nearest


func _update_capabilities() -> void:
	if not is_instance_valid(_capabilities_label):
		return
	var unavailable := PackedStringArray()
	if not bool(_capabilities.get("scale", false)):
		unavailable.append(tr("scale"))
	if not bool(_capabilities.get("weight", false)):
		unavailable.append(tr("mass and weight"))
	if not bool(_capabilities.get("power", false)):
		unavailable.append(tr("power"))
	if not bool(_capabilities.get("controls", false)):
		unavailable.append(tr("control response"))
	var notes := PackedStringArray()
	var compiler_note := str(_capabilities.get("note", ""))
	if compiler_note != "":
		notes.append(compiler_note)
	if not unavailable.is_empty():
		notes.append(tr("Unsupported adjustments: %s. Those values stay unchanged.") % ", ".join(unavailable))
	_capabilities_label.text = "\n".join(notes)
	_capabilities_label.visible = not notes.is_empty()


func _compile_recipe() -> void:
	if _base.is_empty():
		_compiled = {"ok": false, "errors": ["Load an aircraft with valid flight data first."], "summary": {}}
	else:
		_compiled = Compiler.compile(_base.duplicate(true), _recipe.duplicate(true))
	var valid := bool(_compiled.get("ok", false))
	_trial_button.disabled = not valid
	_errors_label.text = _messages(_compiled.get("errors", []), "")
	_errors_label.visible = not valid and _errors_label.text != ""
	_summary_label.text = _format_summary(_compiled.get("summary", {}))
	if valid:
		_validation_label.text = tr("Schema-valid experimental build · physical and pilot validation remain separate.")
	else:
		_validation_label.text = tr("Build blocked until the listed validation errors are resolved.")
	_sync_save_button()


func _format_summary(summary_value: Variant) -> String:
	var lines := PackedStringArray()
	if summary_value is Dictionary:
		_append_summary(summary_value, "", lines, 0)
	elif summary_value is Array:
		for item: Variant in summary_value:
			lines.append(str(item))
	if lines.is_empty():
		return tr("No build values are available.")
	return tr("Current values and changes") + "\n" + "\n".join(lines)


func _append_summary(values: Dictionary, prefix: String, lines: PackedStringArray, depth: int) -> void:
	for key: Variant in values.keys():
		var label := str(key).replace("_", " ").capitalize()
		label = tr(label)
		var path := label if prefix == "" else prefix + " · " + label
		var value: Variant = values[key]
		if value is Dictionary and depth < 2:
			if value.has("value") and value.has("unit"):
				lines.append("%s: %s %s" % [path, _format_value(value.value), str(value.unit)])
				for detail_key in ["base", "before", "after", "delta", "change"]:
					if value.has(detail_key):
						lines.append("%s · %s: %s" % [path, str(detail_key).capitalize(), _format_value(value[detail_key])])
			else:
				_append_summary(value, path, lines, depth + 1)
		elif value is Array:
			var items := PackedStringArray()
			for item: Variant in value:
				items.append(str(item))
			lines.append("%s: %s" % [path, ", ".join(items)])
		else:
			lines.append("%s: %s" % [path, _format_value(value)])


func _format_value(value: Variant) -> String:
	if value is float:
		return "%.3f" % float(value) if is_finite(float(value)) else str(value)
	if value is int:
		return str(value)
	if value is bool:
		return tr("yes") if value else tr("no")
	return str(value)


func _messages(value: Variant, fallback: String) -> String:
	var lines := PackedStringArray()
	if value is Array or value is PackedStringArray:
		for item: Variant in value:
			var message := str(item).strip_edges()
			if message != "":
				lines.append(tr(message))
	elif str(value).strip_edges() != "":
		lines.append(tr(str(value).strip_edges()))
	if lines.is_empty() and fallback != "":
		lines.append(tr(fallback))
	return "\n".join(lines)


func _request_trial() -> void:
	if not bool(_compiled.get("ok", false)):
		set_note("Resolve the build errors before starting a trial.")
		return
	if not Catalog.can_fly(_base_id):
		set_note("This catalog aircraft has no flight model and cannot start a trial.")
		return
	_trial_button.disabled = true
	_trial_pending = true
	trial_requested.emit({
		"base_id": _base_id,
		"recipe": _recipe.duplicate(true),
		"base": _base.duplicate(true),
		"base_bytes": _base_bytes,
		"workshop_descriptor": _workshop_descriptor.duplicate(true),
		"compiled": _compiled.duplicate(true),
	})


func _request_close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()


func _label(text: String, variation := "SecondaryLabel", wrap := false, translate := true) -> Label:
	var result := Widgets.label(text, variation, wrap, translate)
	return result


func _section_label(text: String) -> Label:
	var result := _label(text, "SectionLabel")
	return result


func _button(text: String, variation := "", node_name := "") -> Button:
	return Widgets.button(text, variation, node_name)


func _card(node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.theme_type_variation = "Card"
	return panel


func _card_content(panel: PanelContainer) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.name = "CardContent"
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	return content
