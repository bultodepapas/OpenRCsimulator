extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Parameters := preload("res://workshop/parameters.gd")
const Store := preload("res://workshop/store.gd")
const WorkshopPreview := preload("res://ui/workshop_preview.gd")

signal closed
signal trial_requested(payload: Dictionary)

const LAYER := 20
const VARIANT_ROOT := "user://aircraft_variants"
const FACTOR_STEP := 0.05
const HISTORY_LIMIT := 32
const SCALE_OPTIONS := [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
const FACTOR_CAPABILITIES := {
	"weight_multiplier": "weight",
	"power_multiplier": "power",
	"control_multiplier": "controls",
	"tank_capacity_multiplier": "tank_capacity",
}
const PRESETS := {
	"mini": {"scale": 0.5, "mass_policy": "constant_wing_loading", "weight_multiplier": 1.0, "power_multiplier": 1.0, "control_multiplier": 0.9},
	"giant": {"scale": 2.0, "mass_policy": "constant_wing_loading", "weight_multiplier": 1.0, "power_multiplier": 1.0, "control_multiplier": 1.0},
	"light": {"scale": 1.0, "mass_policy": "constant_wing_loading", "weight_multiplier": 0.8, "power_multiplier": 1.0, "control_multiplier": 1.0},
	"heavy": {"scale": 1.0, "mass_policy": "constant_wing_loading", "weight_multiplier": 1.2, "power_multiplier": 1.15, "control_multiplier": 1.0},
	"fast": {"scale": 1.0, "mass_policy": "constant_wing_loading", "weight_multiplier": 1.0, "power_multiplier": 1.2, "control_multiplier": 1.15},
	"agile": {"scale": 1.0, "mass_policy": "geometric", "weight_multiplier": 0.9, "power_multiplier": 1.0, "control_multiplier": 1.2},
	"slow": {"scale": 1.0, "mass_policy": "constant_wing_loading", "weight_multiplier": 0.65, "power_multiplier": 0.65, "control_multiplier": 0.8},
}
const PRESET_LABELS := {"mini": "Mini", "giant": "Giant", "light": "Light", "heavy": "Heavy", "fast": "More power", "agile": "More travel", "slow": "Light / low power"}

## Set before adding this screen to the ScreenStack. Defaults to the current catalog aircraft.
var initial_aircraft_id := Catalog.DEFAULT_ID
var variants_root := VARIANT_ROOT
var return_destination := "Home"
var _baseline: Dictionary = {}
var _library_dialog: AcceptDialog
var _name_dialog: ConfirmationDialog
var _guard_dialog: ConfirmationDialog
var _guard_name: LineEdit
var _guard_error: Label
var _navigation_proceed: Callable
var _navigation_cancel: Callable
var _navigation_focus: Control
var _library_button: Button
var _build_identity: Label
var _page_buttons: Dictionary = {}
var _page_nodes: Dictionary = {}
var _active_page := "setup"
var _compact := false
var _compact_view := false
var _view_button: Button
var _inspector: ScrollContainer
var _header: BoxContainer
var _footer: BoxContainer
var _identity_line: BoxContainer
var _comparison_grid: GridContainer
var _all_values: CheckButton
var _factor_inputs: Dictionary = {}
var _invalid_fields: Dictionary = {}
var _pending_numbers: Dictionary = {}
var _delete_target: Dictionary = {}
var _last_deleted_generation := ""
var _library_source_id := ""
var _interaction_focus: NodePath
var _interaction_scroll := 0
var _name_before := ""
var _name_as_copy := false

## Public handles for UI integration and focused Workshop checks.
var variant_name_input: LineEdit:
	get:
		return _variant_name
var save_button: Button:
	get:
		return _save_button

var _screen: Control
var _body_scroll: ScrollContainer
var _layout_panel: PanelContainer
var _columns: BoxContainer
var _aircraft_column: VBoxContainer
var _recipe_selectors: GridContainer
var _preset_grid: GridContainer
var _settle_frames := 3
var _base_selector: OptionButton
var _variant_selector: OptionButton
var _variant_name: LineEdit
var _save_button: Button
var _copy_button: Button
var _load_button: Button
var _delete_button: Button
var _restore_button: Button
var _last_deleted_id := ""
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
var _scale_support_hint: Label
var _mass_support_hint: Label
var _aircraft_summary_label: Label
var _aircraft_status_label: Label
var _validation_label: Label
var _trial_button: Button
var _undo_button: Button
var _redo_button: Button
var _preview: WorkshopPreview
var _delete_dialog: ConfirmationDialog

var _base_id := ""
var _base: Dictionary = {}
var _base_bytes := PackedByteArray()
var _workshop_descriptor: Dictionary = {}
var _base_summary: Dictionary = {}
var _base_model: Dictionary = {}
var _saved_variant_id := ""
var _saved_variant_revision := 0
var _saved_compiler_version := ""
var _variant_dependencies: Dictionary = {}
var _recipe: Dictionary = {}
var _compiled: Dictionary = {"ok": false, "errors": ["Choose an aircraft to begin."]}
var _capabilities: Dictionary = {}
var _selected_variant_id := ""
var _undo_history: Array[Dictionary] = []
var _redo_history: Array[Dictionary] = []
var _slider_dragging := false
var _slider_gesture := false
var _syncing_controls := false
var _closing := false
var _trial_pending := false


func _init() -> void:
	name = "Workshop"
	layer = LAYER
	_screen = Screen.mount(self, "Screen")
	_screen.kind = Screen.Kind.MODAL
	_screen.dismiss_option_popup_first = true
	_screen.escape_before_gui = true
	_screen.close_requested.connect(_request_close)
	_screen.dim(0.72, "WorkshopDim")
	_build_ui()
	_build_delete_dialog()


func _ready() -> void:
	_resize_layout()
	_load_catalog_aircraft(initial_aircraft_id, false)
	_refresh_variants()
	_sync_controls()
	_compile_recipe()
	_mark_baseline()
	_focus_default.call_deferred()


func _enter_tree() -> void:
	if _trial_pending:
		_trial_pending = false
		if is_instance_valid(_trial_button):
			_trial_button.disabled = not _edit_valid()
		_restore_interaction.call_deferred()


func _process(_delta: float) -> void:
	_settle_frames -= 1
	if _settle_frames <= 0:
		_body_scroll.scroll_vertical = 0
		_body_scroll.follow_focus = true
		set_process(false)


func _focus_default() -> void:
	if is_inside_tree() and bool(_screen.get("_active")) and is_instance_valid(_library_button):
		_library_button.grab_focus()


func reject_start(message: String = "The trial could not start.") -> void:
	set_note(message)


func set_note(message: String) -> void:
	if is_instance_valid(_status_label):
		_status_label.text = tr(message) if message != "" else ""
		_status_label.visible = message != ""
		if message != "": _reveal_status.call_deferred()
	if _trial_pending:
		_trial_pending = false
	if is_instance_valid(_trial_button):
		_trial_button.disabled = not bool(_compiled.get("ok", false))


func _reveal_status() -> void:
	pass # Status is pinned; ordinary notices never scroll or steal editor focus.


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
		_refresh_identity()


func save_named_variant() -> void:
	_save_variant()


func save_variant_copy() -> void:
	var original_id := _saved_variant_id
	_saved_variant_id = ""
	_save_variant()
	if _saved_variant_id == "":
		_saved_variant_id = original_id


func set_aircraft(id: String, discard_changes := false) -> void:
	if not is_node_ready():
		initial_aircraft_id = id
		return
	if discard_changes:
		_replace_aircraft(id)
	else:
		request_navigation("Open another aircraft", _replace_aircraft.bind(id))


func _build_ui() -> void:
	var outer := CenterContainer.new()
	outer.name = "WorkshopMargins"
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.offset_left = 24
	outer.offset_top = 18
	outer.offset_right = -24
	outer.offset_bottom = -18
	_screen.add_child(outer)
	_layout_panel = PanelContainer.new()
	_layout_panel.name = "WorkshopPanel"
	_layout_panel.theme_type_variation = "Sidebar"
	outer.add_child(_layout_panel)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	_layout_panel.add_child(page)

	_header = BoxContainer.new()
	_header.add_theme_constant_override("separation", 16)
	page.add_child(_header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := _label("Aircraft Workshop", "CardTitle")
	title.name = "WorkshopTitle"
	heading.add_child(title)
	_build_identity = _label("", "SecondaryLabel", true, false)
	_build_identity.name = "BuildIdentity"
	heading.add_child(_build_identity)
	_header.add_child(heading)
	var back := _button("Back to Pause" if return_destination == "Pause" else "Back to Home", "", "CloseWorkshop")
	back.pressed.connect(_request_close)
	_header.add_child(back)

	_identity_line = BoxContainer.new()
	_identity_line.add_theme_constant_override("separation", 8)
	page.add_child(_identity_line)
	_library_button = _button("Library", "", "OpenLibrary")
	_library_button.pressed.connect(_open_library)
	_identity_line.add_child(_library_button)
	var group := ButtonGroup.new()
	for spec: Array in [["setup", "Flight setup"], ["compare", "Compare"]]:
		var tab := _button(spec[1], "", "Page" + str(spec[0]).capitalize())
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = spec[0] == "setup"
		tab.pressed.connect(_set_page.bind(spec[0]))
		_identity_line.add_child(tab)
		_page_buttons[spec[0]] = tab
	var flexible := Control.new()
	flexible.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_identity_line.add_child(flexible)
	_view_button = _button("Preview", "", "CompactPreview")
	_view_button.pressed.connect(_toggle_compact_view)
	_identity_line.add_child(_view_button)

	_columns = HBoxContainer.new()
	_columns.name = "WorkshopColumns"
	_columns.add_theme_constant_override("separation", 24)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(_columns)
	_aircraft_column = VBoxContainer.new()
	_aircraft_column.name = "AircraftColumn"
	_aircraft_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aircraft_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_child(_aircraft_column)
	_preview = WorkshopPreview.new()
	_preview.name = "AircraftPreview"
	_preview.custom_minimum_size = Vector2(0, 240)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_aircraft_column.add_child(_preview)
	var caption := _label("Still preview · no flight simulation", "SecondaryLabel", true)
	caption.name = "PreviewCaption"
	_aircraft_column.add_child(caption)

	_inspector = ScrollContainer.new()
	_inspector.name = "WorkshopScroll"
	_body_scroll = _inspector
	_inspector.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_inspector.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_inspector.follow_focus = true
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.add_child(_inspector)
	var inspector_body := VBoxContainer.new()
	inspector_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_body.add_theme_constant_override("separation", 16)
	_inspector.add_child(inspector_body)
	var setup := VBoxContainer.new()
	setup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup.add_theme_constant_override("separation", 16)
	inspector_body.add_child(setup)
	_page_nodes.setup = setup
	_build_presets_panel(setup)
	_build_recipe_panel(setup)
	var history := HBoxContainer.new()
	history.add_theme_constant_override("separation", 8)
	for action: Array in [["Reset this page", "ResetRecipe", _reset_recipe], ["Undo", "UndoRecipe", _undo], ["Redo", "RedoRecipe", _redo]]:
		var button := _button(action[0], "", action[1])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(action[2])
		history.add_child(button)
		if action[1] == "UndoRecipe": _undo_button = button
		if action[1] == "RedoRecipe": _redo_button = button
	setup.add_child(history)
	var compare := VBoxContainer.new()
	compare.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_body.add_child(compare)
	_page_nodes.compare = compare
	_build_results_panel(compare)
	compare.visible = false

	_errors_label = _label("", "ErrorLabel", true)
	_errors_label.name = "BuildErrors"
	inspector_body.add_child(_errors_label)
	_footer = BoxContainer.new()
	_footer.add_theme_constant_override("separation", 12)
	page.add_child(_footer)
	var notes := VBoxContainer.new()
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(notes)
	_validation_label = _label("", "SecondaryLabel", true)
	_validation_label.name = "ValidationLimit"
	notes.add_child(_validation_label)
	_status_label = _label("", "SecondaryLabel", true)
	_status_label.name = "WorkshopStatus"
	notes.add_child(_status_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_footer.add_child(actions)
	_save_button = _button("Save build", "", "SaveVariant")
	_save_button.pressed.connect(_request_save)
	actions.add_child(_save_button)
	_trial_button = _button("Test fly", "PrimaryButton", "TestFly")
	_trial_button.custom_minimum_size = Vector2(190, 54)
	_trial_button.pressed.connect(_request_trial)
	actions.add_child(_trial_button)
	_build_library()
	_build_name_dialog()
	_screen.resized.connect(_resize_layout)
	_screen.theme_changed.connect(_resize_layout)


func _resize_layout() -> void:
	if not is_inside_tree(): return
	var available := _screen.size - Vector2(48, 36)
	_layout_panel.custom_minimum_size = Vector2(maxf(0, available.x), maxf(0, available.y))
	var enlarged := preload("res://ui/ui_theme.gd").text_scale > 1.25
	_compact = available.x < 1050 or enlarged
	_header.vertical = available.x < 700
	_identity_line.vertical = available.x < 650
	_footer.vertical = available.x < 1100 or enlarged
	_inspector.custom_minimum_size.x = 0 if _compact else (520 if available.x >= 1550 else 400)
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_FILL
	_aircraft_column.visible = not _compact or _compact_view
	_inspector.visible = not _compact or not _compact_view
	_view_button.visible = _compact
	_view_button.text = tr("Edit") if _compact_view else tr("Preview")
	_recipe_selectors.columns = 1 if enlarged else 2
	_preset_grid.columns = 2 if enlarged else 3
	_trial_button.custom_minimum_size.x = 0 if enlarged else 190
	if _active_page == "compare" and _compact:
		_compact_view = false
		_aircraft_column.visible = false
		_inspector.visible = true
	if is_instance_valid(_library_dialog) and _library_dialog.visible:
		_library_dialog.popup_centered_clamped(Vector2i(680, 520), 0.9)


func _build_aircraft_panel(parent: VBoxContainer) -> void:
	var card := _card("BaseAircraftCard")
	parent.add_child(card)
	var content := _card_content(card)
	content.add_child(_section_label("AIRCRAFT"))
	_base_selector = OptionButton.new()
	_base_selector.fit_to_longest_item = false
	_base_selector.name = "BaseAircraft"
	_base_selector.focus_mode = Control.FOCUS_ALL
	_base_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry: Dictionary in Catalog.airplane_flyable_entries():
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
	_preview.custom_minimum_size = Vector2(0, 250)
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(_preview)
	var preview_caption := _label("Still preview · no flight simulation", "SecondaryLabel", true)
	preview_caption.name = "PreviewCaption"
	content.add_child(preview_caption)
	_validation_label = _label("Experimental simulation; handling may differ from a real aircraft.", "SecondaryLabel", true)
	_validation_label.name = "ValidationLimit"
	content.add_child(_validation_label)


func _build_variants_panel(parent: VBoxContainer) -> void:
	var card := _card("SavedVariantsCard")
	parent.add_child(card)
	var content := _card_content(card)
	content.add_child(_section_label("SAVED BUILDS"))
	_variant_selector = OptionButton.new()
	_variant_selector.fit_to_longest_item = false
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
	_restore_button = _button("Undo delete", "", "RestoreVariant")
	_restore_button.disabled = true
	_restore_button.pressed.connect(_restore_last_deleted)
	variant_actions.add_child(_restore_button)
	content.add_child(variant_actions)

	_variant_name = LineEdit.new()
	_variant_name.name = "VariantName"
	_variant_name.placeholder_text = tr("Name this build")
	_variant_name.max_length = 64
	_variant_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_variant_name.text_changed.connect(_on_variant_name_changed)
	_name_dialog = null
	_variant_name.visible = false
	content.add_child(_variant_name)
	_copy_button = _button("Save a copy", "", "CopyVariant")
	_copy_button.pressed.connect(_request_copy)
	content.add_child(_copy_button)
	var rename := _button("Name or rename this build", "", "RenameBuild")
	rename.pressed.connect(func() -> void: _show_name_dialog(false))
	content.add_child(rename)


func _build_presets_panel(parent: VBoxContainer) -> void:
	var card := _card("PresetsCard")
	parent.add_child(card)
	var content := _card_content(card)
	content.add_child(_section_label("STARTING PRESETS"))
	var grid := GridContainer.new()
	_preset_grid = grid
	grid.name = "PresetGrid"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for preset_id: String in PRESETS:
		var preset_button := _button(PRESET_LABELS[preset_id], "", "Preset" + preset_id.capitalize())
		preset_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preset_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_recipe_selectors = selector_grid
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
	_mass_policy_selector.fit_to_longest_item = false
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

	var factor_hint := _label("1× keeps the original value. Changes apply to a new trial flight.", "SecondaryLabel", true)
	content.add_child(factor_hint)
	_add_factor_row(content, "weight_multiplier", "Weight multiplier")
	_add_factor_row(content, "power_multiplier", "Power multiplier")
	_add_factor_row(content, "control_multiplier", "Control travel")
	_add_factor_row(content, "tank_capacity_multiplier", "Tank capacity")

	_scale_support_hint = _label("", "SecondaryLabel", true)
	_scale_support_hint.name = "ScaleSupport"
	content.add_child(_scale_support_hint)
	_mass_support_hint = _label("", "SecondaryLabel", true)
	_mass_support_hint.name = "MassSupport"
	content.add_child(_mass_support_hint)

	_capabilities_label = _label("", "SecondaryLabel", true)
	_capabilities_label.name = "Capabilities"
	content.add_child(_capabilities_label)


func _build_results_panel(parent: VBoxContainer) -> void:
	parent.add_child(_label("Original and draft", "CardTitle"))
	parent.add_child(_label("Experimental values · static estimates, not measured flight performance.", "SecondaryLabel", true))
	_all_values = CheckButton.new()
	_all_values.text = "All values"
	_all_values.name = "AllBuildValues"
	_all_values.toggled.connect(func(_value: bool) -> void: _refresh_comparison())
	parent.add_child(_all_values)
	_comparison_grid = GridContainer.new()
	_comparison_grid.columns = 4
	_comparison_grid.add_theme_constant_override("h_separation", 12)
	_comparison_grid.add_theme_constant_override("v_separation", 12)
	parent.add_child(_comparison_grid)
	_summary_label = _label("", "SecondaryLabel", true)
	_summary_label.name = "BuildSummary"
	_summary_label.visible = false
	var details := _button("Technical details", "", "BuildDetails")
	details.pressed.connect(func() -> void: _summary_label.visible = not _summary_label.visible)
	parent.add_child(details)
	parent.add_child(_summary_label)


func _add_factor_row(parent: VBoxContainer, key: String, caption: String) -> void:
	var row := VBoxContainer.new()
	row.name = key.capitalize()
	row.add_theme_constant_override("separation", 3)
	var heading := HBoxContainer.new()
	var caption_label := _label(caption, "SecondaryLabel", true)
	caption_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(caption_label)
	var value_label := _label("1.00×", "SecondaryLabel")
	value_label.name = key.capitalize() + "Value"
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(value_label)
	var entry := LineEdit.new()
	entry.name = key.capitalize() + "Entry"
	entry.custom_minimum_size.x = 100
	entry.expand_to_text_length = false
	entry.text_changed.connect(_number_changed.bind(key))
	entry.text_submitted.connect(func(_value: String) -> void: _commit_number(key))
	entry.focus_exited.connect(_commit_number.bind(key))
	heading.add_child(entry)
	_factor_inputs[key] = entry
	row.add_child(heading)
	var slider := HSlider.new()
	slider.name = key.capitalize() + "Slider"
	slider.focus_mode = Control.FOCUS_ALL
	var bounds := _factor_bounds(key)
	slider.min_value = bounds.x
	slider.max_value = bounds.y
	slider.step = FACTOR_STEP
	slider.tick_count = roundi((bounds.y - bounds.x) / FACTOR_STEP) + 1
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


func _factor_bounds(key: String) -> Vector2:
	match key:
		"weight_multiplier":
			return Vector2(Parameters.MIN_WEIGHT_MULTIPLIER, Parameters.MAX_WEIGHT_MULTIPLIER)
		"power_multiplier":
			return Vector2(Parameters.MIN_POWER_MULTIPLIER, Parameters.MAX_POWER_MULTIPLIER)
		"control_multiplier":
			return Vector2(Parameters.MIN_CONTROL_MULTIPLIER, Parameters.MAX_CONTROL_MULTIPLIER)
		"tank_capacity_multiplier":
			return Vector2(Parameters.MIN_TANK_CAPACITY_MULTIPLIER, Parameters.MAX_TANK_CAPACITY_MULTIPLIER)
	return Vector2.ONE


func _build_delete_dialog() -> void:
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = tr("Delete saved build?")
	_delete_dialog.exclusive = true
	_delete_dialog.theme = _screen.theme
	_delete_dialog.dialog_text = tr("Delete this saved build from this device?")
	_delete_dialog.confirmed.connect(_delete_selected_variant)
	_delete_dialog.canceled.connect(func() -> void:
		if _delete_button.is_visible_in_tree(): _delete_button.grab_focus())
	_library_dialog.add_child(_delete_dialog)


func _load_catalog_aircraft(id: String, preserve_recipe: bool) -> void:
	_workshop_descriptor.clear()
	_base_summary.clear()
	_base_model.clear()
	_saved_variant_id = ""
	_saved_variant_revision = 0
	_saved_compiler_version = ""
	_variant_dependencies.clear()
	var entry := Catalog.entry(id)
	var rejected_rotorcraft := not entry.is_empty() and Catalog.is_rotorcraft(id)
	if entry.is_empty() or rejected_rotorcraft:
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
	var source_bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if source_bytes.is_empty():
		_base = {}
		_base_bytes = PackedByteArray()
		_compiled = {"ok": false, "errors": ["Aircraft source bytes could not be read."]}
		if is_instance_valid(_preview):
			_preview.set_aircraft(_base_id, 1.0)
		_update_aircraft_description(entry)
		return
	var parser := JSON.new()
	if parser.parse(source_bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		_base = {}
		_base_bytes = PackedByteArray()
		_compiled = {"ok": false, "errors": ["Aircraft source is not a valid JSON object."]}
		if is_instance_valid(_preview):
			_preview.set_aircraft(_base_id, 1.0)
		_update_aircraft_description(entry)
		return
	_base = (parser.data as Dictionary).duplicate(true)
	var validation: Dictionary = AircraftData.validate_and_derive(_base.duplicate(true))
	if not bool(validation.get("ok", false)):
		_base = {}
		_base_bytes = PackedByteArray()
		_compiled = {"ok": false, "errors": validation.get("errors", ["Aircraft data could not be validated."])}
		if is_instance_valid(_preview):
			_preview.set_aircraft(_base_id, 1.0)
		_update_aircraft_description(entry)
		return
	_base_bytes = source_bytes
	_refresh_base_summary()
	if not preserve_recipe:
		_recipe = Compiler.defaults()
		_clear_history()
	_capabilities = Compiler.capabilities(_base)
	_selected_variant_id = ""
	_update_aircraft_description(entry)
	_update_capabilities()
	_update_undo_button()
	if is_instance_valid(_preview):
		_preview.set_aircraft(_base_id, _preview_scale())
	_compile_recipe()
	if rejected_rotorcraft:
		set_note("The fixed-wing Workshop cannot load a rotorcraft.")


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
	var variants: Array = Store.list_variants(variants_root)
	for variant: Dictionary in variants:
		var variant_id := str(variant.get("id", ""))
		if variant_id == "":
			continue
		var source_name := str(Catalog.entry(str(variant.get("base_id", ""))).get("name", tr("Unavailable aircraft")))
		var current := tr("Current") + " · " if variant_id == _saved_variant_id else ""
		_variant_selector.add_item(current + str(variant.get("name", variant_id)) + " · " + source_name + " · " + tr("revision %d") % int(variant.get("revision", 0)))
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
	if not is_instance_valid(_save_button): return
	_save_button.disabled = not _edit_valid()
	_copy_button.disabled = _save_button.disabled
	_refresh_identity()


func _on_base_selected(index: int) -> void:
	_library_source_id = str(_base_selector.get_item_metadata(index))
	_update_aircraft_description(Catalog.entry(_library_source_id))


func _on_variant_selected(index: int) -> void:
	_selected_variant_id = str(_variant_selector.get_item_metadata(index))
	_sync_variant_actions()


func _load_variant_snapshot(selected_id: String) -> void:
	if selected_id == "":
		return
	var result: Dictionary = Store.load_variant(selected_id, variants_root)
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
	var next_base_id := str(variant.get("base_id", ""))
	if Catalog.entry(next_base_id).is_empty():
		set_note("The saved build refers to an unknown catalog aircraft.")
		return
	if Catalog.is_rotorcraft(next_base_id):
		set_note("This saved build belongs to a rotorcraft and cannot be loaded into the fixed-wing Workshop.")
		return
	var next_recipe: Dictionary = Compiler.defaults()
	next_recipe.merge(variant.get("recipe", {}), true)
	var checked: Dictionary = Parameters.validate(next_recipe)
	if not checked.ok:
		set_note(_messages(checked.errors, "The saved build could not be loaded."))
		return
	_invalid_fields.clear()
	_pending_numbers.clear()
	_base_id = next_base_id
	_base = (variant.base as Dictionary).duplicate(true)
	_base_bytes = snapshot_bytes.duplicate()
	_refresh_base_summary()
	var saved_descriptor: Variant = variant.get("workshop_descriptor", {})
	_workshop_descriptor = saved_descriptor.duplicate(true) if saved_descriptor is Dictionary else {}
	_saved_variant_id = str(variant.get("id", ""))
	_saved_variant_revision = int(variant.get("revision", 0))
	_saved_compiler_version = str(variant.get("compiler_version", ""))
	var saved_dependencies: Variant = variant.get("dependencies", {})
	_variant_dependencies = saved_dependencies.duplicate(true) if saved_dependencies is Dictionary else {}
	# Record identity/name have dedicated fields; legacy recipe copies must not
	# override rename, Save a copy, or the ancestry of a retained deleted draft.
	_recipe = checked.values.duplicate(true)
	_recipe.erase("id")
	_recipe.erase("name")
	_clear_history()
	_capabilities = Compiler.capabilities(_base)
	_variant_name.text = str(variant.get("name", ""))
	_select_base(_base_id)
	_update_aircraft_description(Catalog.entry(_base_id))
	_update_capabilities()
	_sync_controls()
	_preview.set_aircraft(_base_id, _preview_scale())
	_compile_recipe()
	if variant.get("recovered_from_manifest_backup", false):
		set_note(tr("Recovered revision %d from backup. Review it before saving.") % _saved_variant_revision)
	else:
		set_note("Saved build loaded. Review the experimental values before a trial.")
	_sync_variant_actions()
	_mark_baseline()
	_close_library()


func _save_variant() -> bool:
	for key: String in _pending_numbers.keys(): _commit_number(key)
	if not _edit_valid(): return false
	var display_name := _variant_name.text.strip_edges()
	if display_name.is_empty() or not bool(_compiled.get("ok", false)):
		return false
	var result: Dictionary = Store.save_variant(
		display_name,
		_base_id,
		_base_bytes,
		_recipe.duplicate(true),
		_saved_variant_id,
		variants_root,
		_workshop_descriptor.duplicate(true),
		_variant_dependencies.duplicate(true),
		_saved_variant_revision if not _saved_variant_id.is_empty() else -1
	)
	if not bool(result.get("ok", false)):
		set_note(_messages(result.get("errors", []), "The build could not be saved."))
		return false
	var variant: Dictionary = result.get("variant", {})
	var saved_descriptor: Variant = variant.get("workshop_descriptor", {})
	_workshop_descriptor = saved_descriptor.duplicate(true) if saved_descriptor is Dictionary else {}
	_saved_variant_id = str(variant.get("id", ""))
	_saved_variant_revision = int(variant.get("revision", 0))
	_saved_compiler_version = str(variant.get("compiler_version", ""))
	var saved_dependencies: Variant = variant.get("dependencies", {})
	_variant_dependencies = saved_dependencies.duplicate(true) if saved_dependencies is Dictionary else {}
	set_note(tr("Saved build: %s") % str(variant.get("name", display_name)))
	_refresh_variants()
	_select_variant(str(variant.get("id", "")))
	_sync_variant_actions()
	_mark_baseline()
	return true


func _confirm_delete_selected() -> void:
	if _selected_variant_id.is_empty(): return
	var loaded: Dictionary = Store.load_variant(_selected_variant_id, variants_root)
	if not loaded.get("ok", false):
		set_note(_messages(loaded.get("errors", []), "The saved build could not be loaded."))
		return
	_delete_target = {id = str(loaded.variant.id), revision = int(loaded.variant.revision)}
	_delete_dialog.dialog_text = tr("Delete %s · revision %d?") % [str(loaded.variant.name), _delete_target.revision]
	_delete_dialog.popup_centered_clamped(Vector2i(560, 180), 0.9)
	_delete_dialog.get_cancel_button().grab_focus()


func _delete_selected_variant() -> void:
	if _delete_target.is_empty(): return
	var deleting_id := str(_delete_target.id)
	var revision := int(_delete_target.revision)
	_delete_target.clear()
	var result: Dictionary = Store.delete_variant(deleting_id, variants_root, revision)
	if not bool(result.get("ok", false)):
		set_note(_messages(result.get("errors", []), "The saved build could not be deleted."))
		return
	_last_deleted_id = deleting_id
	_last_deleted_generation = str(result.get("trash_generation", ""))
	_restore_button.disabled = false
	if _saved_variant_id == deleting_id:
		_saved_variant_id = ""
		_saved_variant_revision = 0
		_saved_compiler_version = ""
		_baseline.clear()
		_baseline["deleted_saved_build"] = true
	_refresh_variants()
	_refresh_identity()
	set_note("Saved build deleted. Its open draft is still available as a copy.")


func _restore_last_deleted() -> void:
	if _last_deleted_id.is_empty():
		return
	var result: Dictionary = Store.restore_variant(_last_deleted_id, variants_root, _last_deleted_generation)
	if not bool(result.get("ok", false)):
		set_note(_messages(result.get("errors", []), "The saved build could not be restored."))
		return
	_refresh_variants()
	_select_variant(_last_deleted_id)
	_sync_variant_actions()
	_last_deleted_id = ""
	_last_deleted_generation = ""
	_restore_button.disabled = true
	set_note("Saved build restored. Load it to continue editing that revision.")


func _select_variant(id: String) -> void:
	if id == "":
		return
	for index in _variant_selector.item_count:
		if str(_variant_selector.get_item_metadata(index)) == id:
			_variant_selector.select(index)
			_selected_variant_id = id
			return


func _on_variant_name_changed(_text: String) -> void:
	_refresh_identity()


func _on_scale_selected(index: int) -> void:
	if _syncing_controls or _base.is_empty():
		return
	if _recipe.get("scale", 1.0) == _scale_selector.get_item_metadata(index):
		return
	_capture_undo()
	_recipe["scale"] = float(_scale_selector.get_item_metadata(index))
	_preview.set_aircraft(_base_id, _preview_scale())
	_compile_recipe()


func _on_mass_policy_selected(index: int) -> void:
	if _syncing_controls or _base.is_empty():
		return
	if _recipe.get("mass_policy", "") == _mass_policy_selector.get_item_metadata(index):
		return
	_capture_undo()
	_recipe["mass_policy"] = str(_mass_policy_selector.get_item_metadata(index))
	_compile_recipe()


func _on_factor_value_changed(value: float, key: String) -> void:
	if _syncing_controls or _base.is_empty():
		return
	if is_equal_approx(float(_recipe.get(key, 1.0)), value):
		return
	if not _slider_gesture:
		_capture_undo()
		_slider_gesture = _slider_dragging
	var bounds := _factor_bounds(key)
	_recipe[key] = clampf(value, bounds.x, bounds.y)
	_factor_values[key].text = String.num(value, 4) + "×"
	_invalid_fields.erase(key)
	_pending_numbers.erase(key)
	_factor_inputs[key].text = String.num(value, 4)
	_compile_recipe()


func _on_slider_drag_started() -> void:
	if not _syncing_controls:
		_slider_dragging = true
		_slider_gesture = false


func _on_slider_drag_ended(_changed: bool) -> void:
	_slider_gesture = false
	_slider_dragging = false


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
	set_note(tr("Applied the %s preset where this aircraft supports it.") % tr(PRESET_LABELS[preset_id]))


func _reset_recipe() -> void:
	if _base.is_empty():
		return
	_set_recipe(Compiler.defaults(), true)
	set_note("Recipe reset to defaults. Use Undo to restore the previous values.")


func _undo() -> void:
	if _undo_history.is_empty():
		return
	_redo_history.append(_recipe.duplicate(true))
	var previous: Dictionary = _undo_history.pop_back()
	_set_recipe(previous, false)
	_update_undo_button()
	set_note("Previous recipe restored.")


func _redo() -> void:
	if _redo_history.is_empty():
		return
	_undo_history.append(_recipe.duplicate(true))
	var next: Dictionary = _redo_history.pop_back()
	_set_recipe(next, false)
	_update_undo_button()
	set_note("Recipe change reapplied.")


func _set_recipe(next_recipe: Dictionary, remember_current: bool) -> void:
	var checked: Dictionary = Parameters.validate(next_recipe)
	if not checked.ok:
		set_note(_messages(checked.errors, "The recipe could not be applied."))
		return
	var next: Dictionary = checked.values
	next.erase("id")
	next.erase("name")
	if next == _recipe:
		return
	if remember_current:
		_capture_undo()
	_recipe = next
	_invalid_fields.clear()
	_pending_numbers.clear()
	_sync_controls()
	if is_instance_valid(_preview):
		_preview.set_aircraft(_base_id, _preview_scale())
	_compile_recipe()


func _preview_scale() -> float:
	return float(_recipe.get("scale", 1.0)) if bool(_capabilities.get("scale", false)) else 1.0


func _refresh_base_summary() -> void:
	_base_summary.clear()
	_base_model.clear()
	if _base.is_empty():
		return
	var baseline: Dictionary = Compiler.compile(_base.duplicate(true), Compiler.defaults())
	if not bool(baseline.get("ok", false)):
		return
	_base_summary = baseline.get("summary", {}).duplicate(true)
	var data: Dictionary = baseline.get("data", {})
	var model: Variant = data.get("model", {})
	if model is Dictionary:
		_base_model = model.duplicate(true)


func _capture_undo() -> void:
	_undo_history.append(_recipe.duplicate(true))
	if _undo_history.size() > HISTORY_LIMIT:
		_undo_history.pop_front()
	_redo_history.clear()
	_update_undo_button()


func _clear_history() -> void:
	_undo_history.clear()
	_redo_history.clear()
	_slider_gesture = false
	_slider_dragging = false
	_update_undo_button()


func _update_undo_button() -> void:
	if is_instance_valid(_undo_button):
		_undo_button.disabled = _undo_history.is_empty()
	if is_instance_valid(_redo_button):
		_redo_button.disabled = _redo_history.is_empty()


func _sync_controls() -> void:
	if not is_instance_valid(_scale_selector) or _recipe.is_empty():
		return
	_syncing_controls = true
	var scale := float(_recipe.get("scale", 1.0))
	while _scale_selector.item_count > SCALE_OPTIONS.size():
		_scale_selector.remove_item(_scale_selector.item_count - 1)
	if scale not in SCALE_OPTIONS:
		_scale_selector.add_item(String.num(scale * 100.0, 4) + "%")
		_scale_selector.set_item_metadata(_scale_selector.item_count - 1, scale)
	for index in _scale_selector.item_count:
		if float(_scale_selector.get_item_metadata(index)) == scale:
			_scale_selector.select(index)
			break
	_scale_selector.disabled = not bool(_capabilities.get("scale", false))
	var policy := str(_recipe.get("mass_policy", "constant_wing_loading"))
	for index in _mass_policy_selector.item_count:
		if str(_mass_policy_selector.get_item_metadata(index)) == policy:
			_mass_policy_selector.select(index)
			break
	_mass_policy_selector.disabled = not bool(_capabilities.get("weight", false))
	for key: String in FACTOR_CAPABILITIES:
		var bounds := _factor_bounds(key)
		var value := float(_recipe.get(key, 1.0))
		# Range preserves its exact value when step is restored; avoid quantizing a loaded recipe.
		_factor_sliders[key].step = 0.0
		_factor_sliders[key].set_value_no_signal(value)
		_factor_sliders[key].step = FACTOR_STEP
		_factor_values[key].text = String.num(value, 4) + "×"
		_factor_inputs[key].text = String.num(value, 4)
		var supported := bool(_capabilities.get(str(FACTOR_CAPABILITIES[key]), false))
		_factor_sliders[key].editable = supported
		_factor_inputs[key].editable = supported
		if supported and key == "tank_capacity_multiplier":
			_factor_hints[key].text = tr("Estimated sizing proposal; tank dimensions scale uniformly. Fill fraction and blend density are preserved.")
		elif not supported and key == "tank_capacity_multiplier":
			_factor_hints[key].text = tr("No declared finite tank.")
		else:
			_factor_hints[key].text = (
				tr("Range %.2f×–%.2f× · experimental adjustment.") % [bounds.x, bounds.y]
				if supported else tr("Not available for this engine type.")
			)
	_syncing_controls = false
	_update_capabilities()
	_update_undo_button()
	_sync_save_button()


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
		unavailable.append(tr("control travel"))
	if not bool(_capabilities.get("tank_capacity", false)):
		unavailable.append(tr("tank capacity"))
	var notes := PackedStringArray()
	if unavailable.is_empty():
		notes.append(tr("Try different sizes, weights, tank capacities and power levels. Values are estimates for experimentation."))
	if not unavailable.is_empty():
		notes.append(tr("Unsupported adjustments: %s. Those values stay unchanged.") % ", ".join(unavailable))
	_capabilities_label.text = "\n".join(notes)
	_capabilities_label.visible = not notes.is_empty()
	var limitation := tr("Not available for this engine type.")
	var classification: Dictionary = _capabilities.get("classification", {})
	var transform_reasons: Array = classification.get("compiler_transform_reasons", [])
	var transform_reason := "; ".join(PackedStringArray(transform_reasons)) if not transform_reasons.is_empty() else limitation
	_scale_support_hint.text = tr("Scaling unavailable: %s") % transform_reason if not bool(_capabilities.get("scale", false)) else ""
	_scale_support_hint.visible = _scale_support_hint.text != ""
	_mass_support_hint.text = tr("Mass and weight unavailable: %s") % transform_reason if not bool(_capabilities.get("weight", false)) else ""
	_mass_support_hint.visible = _mass_support_hint.text != ""


func _compile_recipe() -> void:
	if _base.is_empty():
		_compiled = {"ok": false, "errors": ["Load an aircraft with valid flight data first."], "summary": {}}
	else:
		_compiled = Compiler.compile(_base.duplicate(true), _recipe.duplicate(true))
	var valid := bool(_compiled.get("ok", false))
	_trial_button.disabled = not valid or not _invalid_fields.is_empty()
	_errors_label.text = _messages(_compiled.get("errors", []), "")
	_errors_label.visible = not valid and _errors_label.text != ""
	var compiled_data: Dictionary = _compiled.get("data", {})
	var compiled_model: Variant = compiled_data.get("model", {})
	_summary_label.text = _format_summary(
		_compiled.get("summary", {}),
		compiled_model if compiled_model is Dictionary else {}
	)
	if valid:
		_validation_label.text = tr("Ready for a trial · start in the air")
	else:
		_validation_label.text = tr("Build blocked until the listed validation errors are resolved.")
	_sync_save_button()
	_refresh_comparison()


func _format_summary(summary_value: Variant, model: Dictionary) -> String:
	if not summary_value is Dictionary or summary_value.is_empty():
		return tr("No build values are available.")
	var summary: Dictionary = summary_value
	var lines := PackedStringArray()
	var scale_percent := String.num(float(summary.get("scale", 1.0)) * 100.0, 4)
	var mass_policy: String = tr("Constant wing loading") if summary.get("mass_policy", "constant_wing_loading") == "constant_wing_loading" else tr("Geometric")
	lines.append(tr("Scale %s%% · %s mass · weight ×%.2f · power ×%.2f · control travel ×%.2f") % [
		scale_percent,
		mass_policy,
		float(summary.get("weight_multiplier", 1.0)),
		float(summary.get("power_multiplier", 1.0)),
		float(summary.get("control_multiplier", 1.0)),
	])
	if bool(summary.get("capabilities", {}).get("tank_capacity", false)):
		lines.append(tr("Tank capacity ×%.2f · estimated sizing; fill and density are preserved.")
			% float(summary.get("tank_capacity_multiplier", 1.0)))
	lines.append(tr("Base → proposed"))
	var metrics := [
		{"key": "wing_span_m", "label": "Wing span", "unit": "m", "digits": 2},
		{"key": "wing_area_m2", "label": "Wing area", "unit": "m²", "digits": 2},
		{"key": "mass_kg", "label": "Mass", "unit": "kg", "digits": 2},
		{"key": "wing_loading_kg_m2", "label": "Wing loading", "unit": "kg/m²", "digits": 2},
		{"key": "fuel_capacity_l", "label": "Tank capacity", "unit": "l", "digits": 2},
		{"key": "max_rpm", "label": "Maximum RPM", "unit": "rpm", "digits": 0},
		{"key": "static_thrust_n", "label": "Static thrust", "unit": "N", "digits": 2},
		{"key": "static_power_w", "label": "Static power", "unit": "W", "digits": 1},
	]
	for metric: Dictionary in metrics:
		var key := str(metric.key)
		if not summary.has(key):
			continue
		var current := float(summary[key])
		if _base_summary.has(key):
			lines.append(_format_metric_change(
				tr(str(metric.label)), float(_base_summary[key]), current,
				str(metric.unit), int(metric.digits)
			))
		else:
			lines.append("%s: %s %s" % [tr(str(metric.label)), _format_metric_number(current, int(metric.digits)), str(metric.unit)])
	var base_cg_percent := _cg_percent(_base_model)
	var current_cg_percent := _cg_percent(model)
	if is_finite(base_cg_percent) and is_finite(current_cg_percent):
		lines.append(_format_metric_change(tr("CG (% chord)"), base_cg_percent, current_cg_percent, "%", 1))
	return "\n".join(lines)


func _format_metric_change(label: String, base_value: float, current_value: float, unit: String, digits: int) -> String:
	var delta := current_value - base_value
	var delta_text := ("+" if delta >= 0.0 else "−") + _format_metric_number(absf(delta), digits)
	var percent_text := tr("n/a")
	if absf(base_value) > 1.0e-12:
		var percent_delta := delta / absf(base_value) * 100.0
		percent_text = ("+" if percent_delta >= 0.0 else "−") + _format_metric_number(absf(percent_delta), 1) + "%"
	return "%s: %s → %s %s (Δ %s %s, %s)" % [
		label,
		_format_metric_number(base_value, digits),
		_format_metric_number(current_value, digits),
		unit,
		delta_text,
		unit,
		percent_text,
	]


func _format_metric_number(value: float, digits: int) -> String:
	if digits <= 0:
		return str(roundi(value))
	if digits == 1:
		return "%.1f" % value
	return "%.2f" % value


func _cg_percent(model: Dictionary) -> float:
	var cg: Variant = model.get("cg_le", null)
	var reference: Dictionary = model.get("reference", {})
	var chord := float(reference.get("c", 0.0))
	if not cg is PackedFloat64Array or cg.is_empty() or chord <= 0.0:
		return NAN
	return float(cg[0]) / chord * 100.0


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
	if _trial_pending: return
	if _library_dialog.visible or _name_dialog.visible or (is_instance_valid(_guard_dialog) and _guard_dialog.visible): return
	for key: String in _pending_numbers.keys(): _commit_number(key)
	if not _edit_valid():
		set_note("Resolve the build errors before starting a trial.")
		return
	if Catalog.is_rotorcraft(_base_id):
		set_note("The fixed-wing Workshop cannot start a rotorcraft trial.")
		return
	if not Catalog.can_fly(_base_id):
		set_note("This catalog aircraft has no flight model and cannot start a trial.")
		return
	_capture_interaction()
	_trial_button.disabled = true
	_trial_pending = true
	trial_requested.emit({
		"base_id": _base_id,
		"recipe": _recipe.duplicate(true),
		"base": _base.duplicate(true),
		"base_bytes": _base_bytes,
		"workshop_descriptor": _workshop_descriptor.duplicate(true),
		"variant_id": _saved_variant_id,
		"variant_revision": _saved_variant_revision,
		"compiler_version": _saved_compiler_version,
		"dependencies": _variant_dependencies.duplicate(true),
		"compiled": _compiled.duplicate(true),
	})


func _request_close() -> void:
	if is_instance_valid(_guard_dialog) and _guard_dialog.visible: return
	var focused := get_viewport().gui_get_focus_owner()
	for key: String in _factor_inputs:
		if focused == _factor_inputs[key] and (_pending_numbers.has(key) or _invalid_fields.has(key)):
			_pending_numbers.erase(key)
			_invalid_fields.erase(key)
			_factor_inputs[key].text = String.num(float(_recipe.get(key, 1.0)), 4)
			_compile_recipe()
			return
	if _compact and _compact_view:
		_compact_view = false
		_resize_layout()
		_view_button.grab_focus()
		return
	if _closing: return
	request_navigation("Back to Pause" if return_destination == "Pause" else "Back to Home", _finish_close)


func _label(text: String, variation := "SecondaryLabel", wrap := false, translate := true) -> Label:
	var result := Widgets.label(text, variation, wrap or variation in ["TitleLabel", "SectionLabel"], translate)
	return result


func _section_label(text: String) -> Label:
	var result := _label(text, "SectionLabel")
	return result


func _button(text: String, variation := "", node_name := "") -> Button:
	return Widgets.button(text, variation, node_name)


func _card(node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	return panel


func _card_content(panel: PanelContainer) -> VBoxContainer:
	var content := VBoxContainer.new()
	content.name = "CardContent"
	content.add_theme_constant_override("separation", 8)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(content)
	return content


func _build_library() -> void:
	_library_dialog = AcceptDialog.new()
	_library_dialog.name = "WorkshopLibrary"
	_library_dialog.title = tr("Aircraft library")
	_library_dialog.theme = _screen.theme
	_library_dialog.exclusive = true
	_library_dialog.ok_button_text = tr("Back to editor")
	_library_dialog.confirmed.connect(_close_library)
	_library_dialog.canceled.connect(_close_library)
	add_child(_library_dialog)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	_library_dialog.add_child(body)
	body.add_child(_label("Stock aircraft", "CardTitle"))
	_base_selector = OptionButton.new()
	_base_selector.name = "BaseAircraft"
	_base_selector.fit_to_longest_item = false
	for entry: Dictionary in Catalog.airplane_flyable_entries():
		_base_selector.add_item(str(entry.get("name", entry.get("id", "Aircraft"))))
		_base_selector.set_item_metadata(_base_selector.item_count - 1, str(entry.id))
	_base_selector.item_selected.connect(_on_base_selected)
	body.add_child(_base_selector)
	var open_stock := _button("New build from selected aircraft", "", "OpenStockAircraft")
	open_stock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	open_stock.pressed.connect(func() -> void:
		var target := str(_base_selector.get_item_metadata(_base_selector.selected))
		_close_library()
		request_navigation("Open another aircraft", _replace_aircraft.bind(target)))
	body.add_child(open_stock)
	_aircraft_summary_label = _label("", "SecondaryLabel", true)
	_aircraft_status_label = _label("", "SecondaryLabel", true)
	body.add_child(_aircraft_summary_label)
	body.add_child(_aircraft_status_label)
	_build_variants_panel(body)


func _build_name_dialog() -> void:
	_name_dialog = ConfirmationDialog.new()
	_name_dialog.name = "SaveBuildDialog"
	_name_dialog.title = tr("Save build")
	_name_dialog.theme = _screen.theme
	_name_dialog.exclusive = true
	_name_dialog.dialog_hide_on_ok = false
	_name_dialog.ok_button_text = tr("Save build")
	_name_dialog.confirmed.connect(func() -> void:
		var succeeded := false
		if _name_as_copy:
			var previous := _saved_variant_id
			_saved_variant_id = ""
			succeeded = _save_variant()
			if not succeeded: _saved_variant_id = previous
		else:
			succeeded = _save_variant()
		if succeeded: _name_dialog.hide())
	_name_dialog.canceled.connect(func() -> void:
		_variant_name.text = _name_before
		_refresh_identity())
	add_child(_name_dialog)
	# The name field is created with library controls; saving a new draft can show it here.


func _open_library() -> void:
	_refresh_variants()
	_select_base(_base_id)
	_trial_button.disabled = true
	_library_dialog.popup_centered_clamped(Vector2i(680, 520), 0.9)
	_base_selector.grab_focus()


func _close_library() -> void:
	_library_dialog.hide()
	_trial_button.disabled = not _edit_valid() or _trial_pending
	if _library_button.is_visible_in_tree(): _library_button.grab_focus()


func _request_save() -> void:
	for key: String in _pending_numbers.keys(): _commit_number(key)
	if not _edit_valid():
		_set_page("setup")
		return
	if _variant_name.text.strip_edges().is_empty():
		_show_name_dialog(false)
	else:
		_save_variant()


func _request_copy() -> void:
	_show_name_dialog(true)


func _show_name_dialog(as_copy: bool) -> void:
	if not _edit_valid(): return
	_close_library()
	_name_as_copy = as_copy
	_name_before = _variant_name.text
	_variant_name.reparent(_name_dialog)
	_variant_name.visible = true
	_name_dialog.title = tr("Save a copy") if as_copy else tr("Save build")
	_name_dialog.popup_centered_clamped(Vector2i(560, 180), 0.9)
	_variant_name.grab_focus()



func _replace_aircraft(id: String) -> void:
	_selected_variant_id = ""
	_variant_selector.select(0)
	_variant_name.clear()
	_invalid_fields.clear()
	_pending_numbers.clear()
	_load_catalog_aircraft(id, false)
	_sync_controls()
	_sync_variant_actions()
	_mark_baseline()
	_close_library()


func _load_selected_variant() -> void:
	if _selected_variant_id.is_empty(): return
	var target := _selected_variant_id
	_close_library()
	request_navigation("Open saved build", _load_variant_snapshot.bind(target))


func _set_page(page: String) -> void:
	if not _page_nodes.has(page): return
	_active_page = page
	_compact_view = false
	for id: String in _page_nodes:
		_page_nodes[id].visible = id == page
		_page_buttons[id].set_pressed_no_signal(id == page)
	_body_scroll.scroll_vertical = 0
	_resize_layout()


func _toggle_compact_view() -> void:
	_compact_view = not _compact_view
	_resize_layout()


func _draft_payload() -> Dictionary:
	return {base_id = _base_id, base_bytes = _base_bytes.duplicate(), recipe = _recipe.duplicate(true),
		name = _variant_name.text.strip_edges(), descriptor = _workshop_descriptor.duplicate(true),
		dependencies = _variant_dependencies.duplicate(true), compiler = _saved_compiler_version}


func has_unsaved_changes() -> bool:
	return not _invalid_fields.is_empty() or not _pending_numbers.is_empty() \
		or (not _baseline.is_empty() and _draft_payload() != _baseline)


func _mark_baseline() -> void:
	_baseline = _draft_payload()
	_refresh_identity()


func _refresh_identity() -> void:
	if not is_instance_valid(_build_identity): return
	var display_name := _variant_name.text.strip_edges()
	if display_name.is_empty(): display_name = tr("Unsaved build")
	var state := tr("Unsaved changes") if has_unsaved_changes() else (tr("Saved") if not _saved_variant_id.is_empty() else tr("New build"))
	var revision := " · " + tr("revision %d") % _saved_variant_revision if _saved_variant_revision > 0 else ""
	_build_identity.text = "%s · %s%s · %s" % [display_name, tr(str(Catalog.entry(_base_id).get("name", _base_id))), revision, state]


func _edit_valid() -> bool:
	return bool(_compiled.get("ok", false)) and _invalid_fields.is_empty()


func _finish_close() -> void:
	if _closing: return
	_closing = true
	closed.emit()


func request_navigation(destination: String, proceed: Callable, cancel: Callable = Callable(), dialog_host: Node = null) -> void:
	if is_instance_valid(_guard_dialog): return
	if not has_unsaved_changes():
		proceed.call()
		return
	_navigation_proceed = proceed
	_navigation_cancel = cancel
	_navigation_focus = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	_guard_dialog = ConfirmationDialog.new()
	_guard_dialog.name = "UnsavedBuildDialog"
	_guard_dialog.title = tr("Unsaved changes")
	_guard_dialog.dialog_text = tr("Save this build before continuing?") + "\n" + tr(destination)
	_guard_dialog.theme = _screen.theme
	_guard_dialog.exclusive = true
	_guard_dialog.dialog_hide_on_ok = false
	_guard_dialog.ok_button_text = tr("Save and continue")
	_guard_dialog.cancel_button_text = tr("Cancel")
	_guard_dialog.add_button(tr("Discard changes"), false, "discard")
	_guard_dialog.confirmed.connect(_navigation_save)
	_guard_dialog.canceled.connect(_navigation_abort)
	_guard_dialog.custom_action.connect(func(action: String) -> void:
		if action == "discard": _navigation_finish())
	var host: Node = dialog_host if dialog_host != null else self
	host.add_child(_guard_dialog)
	var body := VBoxContainer.new()
	_guard_dialog.add_child(body)
	_guard_name = LineEdit.new()
	_guard_name.placeholder_text = tr("Name this build")
	_guard_name.max_length = 64
	_guard_name.text = _variant_name.text
	body.add_child(_guard_name)
	_guard_error = _label("", "ErrorLabel", true)
	body.add_child(_guard_error)
	_guard_dialog.get_ok_button().disabled = not _edit_valid()
	if not _edit_valid(): _guard_error.text = tr("This build cannot be saved until its errors are resolved.")
	_guard_dialog.popup_centered_clamped(Vector2i(600, 260), 0.9)
	_guard_dialog.get_cancel_button().grab_focus()


func _navigation_save() -> void:
	for key: String in _pending_numbers.keys(): _commit_number(key)
	var name_value := _guard_name.text.strip_edges()
	if name_value.is_empty():
		_guard_error.text = tr("Name this build before saving.")
		_guard_name.grab_focus()
		return
	_variant_name.text = name_value
	if _save_variant():
		_navigation_finish()
	else:
		_guard_error.text = _status_label.text


func _navigation_finish() -> void:
	var next := _navigation_proceed
	_clear_navigation()
	if next.is_valid(): next.call()


func _navigation_abort() -> void:
	var cancel := _navigation_cancel
	var focus := _navigation_focus
	_clear_navigation()
	if is_instance_valid(focus) and focus.is_inside_tree() and focus.is_visible_in_tree(): focus.grab_focus()
	if cancel.is_valid(): cancel.call()


func _clear_navigation() -> void:
	if is_instance_valid(_guard_dialog):
		_guard_dialog.hide()
		_guard_dialog.queue_free()
	_guard_dialog = null
	_navigation_proceed = Callable()
	_navigation_cancel = Callable()
	_navigation_focus = null


func _number_changed(value: String, key: String) -> void:
	if _syncing_controls: return
	var bounds := _factor_bounds(key)
	var number := value.to_float()
	if not value.is_valid_float() or not is_finite(number) or number < bounds.x or number > bounds.y:
		_invalid_fields[key] = tr("Enter a value from %.2f to %.2f.") % [bounds.x, bounds.y]
	else:
		_invalid_fields.erase(key)
	if value == String.num(float(_recipe.get(key, 1.0)), 4):
		_pending_numbers.erase(key)
	else:
		_pending_numbers[key] = value
	_trial_button.disabled = not _edit_valid()
	_sync_save_button()
	if _invalid_fields.has(key): set_note(_invalid_fields[key])


func _commit_number(key: String) -> void:
	if not _pending_numbers.has(key) or _invalid_fields.has(key): return
	var value := str(_pending_numbers[key]).to_float()
	_pending_numbers.erase(key)
	var next := _recipe.duplicate(true)
	next[key] = value
	_set_recipe(next, true)


func _refresh_comparison() -> void:
	if not is_instance_valid(_comparison_grid): return
	for child in _comparison_grid.get_children():
		_comparison_grid.remove_child(child)
		child.queue_free()
	for title: String in ["Value", "Original", "Draft", "Difference"]:
		_comparison_cell(tr(title))
	var summary: Dictionary = _compiled.get("summary", {})
	var rows := 0
	for spec: Array in [["wing_span_m", "Wing span (m)"], ["wing_area_m2", "Wing area (m²)"], ["mass_kg", "Mass (kg)"], ["wing_loading_kg_m2", "Wing loading (kg/m²)"], ["fuel_capacity_l", "Tank capacity (l)"], ["max_rpm", "Maximum RPM"], ["static_thrust_n", "Static thrust (N)"], ["static_power_w", "Static power (W)"]]:
		var key := str(spec[0])
		if not summary.has(key) or not _base_summary.has(key): continue
		var before := float(_base_summary[key])
		var after := float(summary[key])
		if not _all_values.button_pressed and is_equal_approx(before, after): continue
		_comparison_cell(tr(spec[1]))
		_comparison_cell(_format_metric_number(before, 2))
		_comparison_cell(_format_metric_number(after, 2))
		_comparison_cell(("+" if after >= before else "−") + _format_metric_number(absf(after - before), 2))
		rows += 1
	if rows == 0: _comparison_cell(tr("No changes from the original."))


func _comparison_cell(value: String) -> void:
	var cell := _label(value, "SecondaryLabel", true, false)
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_comparison_grid.add_child(cell)


func _capture_interaction() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	_interaction_focus = get_path_to(focus) if focus != null and is_ancestor_of(focus) else NodePath()
	_interaction_scroll = _body_scroll.scroll_vertical


func _restore_interaction() -> void:
	_body_scroll.scroll_vertical = _interaction_scroll
	var focus := get_node_or_null(_interaction_focus) as Control if not _interaction_focus.is_empty() else null
	if focus != null and focus.is_visible_in_tree(): focus.grab_focus()
