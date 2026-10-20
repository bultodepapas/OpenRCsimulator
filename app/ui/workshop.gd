extends CanvasLayer

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const AircraftData := preload("res://physics/aircraft_data.gd")
const Compiler := preload("res://workshop/compiler.gd")
const Parameters := preload("res://workshop/parameters.gd")
const Store := preload("res://workshop/store.gd")
const Bundle := preload("res://workshop/bundle.gd")
const LibraryPreferences := preload("res://workshop/library_preferences.gd")
const ProfileTransfer := preload("res://workshop/profile_transfer.gd")
const Presentation := preload("res://workshop/presentation.gd")
const Customization := preload("res://render/aircraft_customization.gd")
const CustomizationPanel := preload("res://ui/workshop_customization.gd")
const PAGE_IDS := ["appearance", "smoke", "setup", "compare"]
const WorkshopPreview := preload("res://ui/workshop_preview.gd")
const Thumbnail := preload("res://ui/workshop_thumbnail.gd")

signal closed
signal trial_requested(payload: Dictionary)

const LAYER := 20
const VARIANT_ROOT := "user://aircraft_variants"
const FACTOR_STEP := 0.05
const SCALE_STEP_RATIO := 1.1
const HISTORY_LIMIT := 32
const SCALE_OPTIONS := [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
var _factor_capabilities: Dictionary = {}

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
## Only the interactive application opts into recovery; tests/captures use isolated roots.
var recovery_enabled := false
var recovery_root := "user://workshop_recovery"
var _recovery_timer: Timer
var _recovery_dialog: ConfirmationDialog
var _recovery_text: Label
var _recovery_button: Button
var _recovery_loaded: Dictionary = {}
var _recovery_pending := false
var _recovery_restoring := false
var _recovery_requires_copy := false
var _recovery_last: Dictionary = {}
var _recovery_digest := "missing"
var return_destination := "Home":
	set(value):
		return_destination = "Pause" if value == "Pause" else "Home"
		if is_instance_valid(_screen):
			var back := _screen.find_child("CloseWorkshop", true, false) as Button
			if back != null: back.text = "Back to Pause" if return_destination == "Pause" else "Back to Home"
var _presentation: Dictionary = {}
var _presentation_bindings: Dictionary = {}
var _presentation_errors := PackedStringArray()
var _presentation_buffers: Dictionary = {}
var _customization_panels: Array = []
var _trial_conditions_label: Label
var trial_conditions := "":
	set(value):
		trial_conditions = value
		if is_instance_valid(_trial_conditions_label):
			_trial_conditions_label.text = value
			_trial_conditions_label.visible = not value.is_empty()
var trial_start_choice := "airborne"
var _baseline: Dictionary = {}
var _library_dialog: AcceptDialog
var _library_note: Label
var _bundle_dialog: FileDialog
var _export_button: Button
var _favorite_button: Button
var _favorites_only: CheckButton
var _build_search: LineEdit
var _favorites: Array = []
var _unavailable_favorite_ids: Array[String] = []
var _favorites_hint: Label
var _favorites_ok := true
var _library_summaries: Array[Dictionary] = []
var _thumbnail: Node
var _thumbnail_image: TextureRect
var _thumbnail_note: Label
var _thumbnail_selection := ""
var _thumbnail_identity: Dictionary = {}
var _mass_dialog: ConfirmationDialog
var _mass_button: Button
var _mass_snapshot: Dictionary = {}
var _copy_profile_button: Button
var _transfer_dialog: ConfirmationDialog
var _transfer_text: Label
var _transfer_proposal: Dictionary = {}
var _transfer_snapshot: Dictionary = {}
var _transfer_base_id := ""
var _bundle_export_bytes := PackedByteArray()
var _bundle_import := true
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
var _page_selector: OptionButton
var _action_notes: VBoxContainer
var _name_body: VBoxContainer
var _name_error: Label
var _review_button: Button
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
var _preset_selector: OptionButton
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
var _scale_smaller_button: Button
var _scale_larger_button: Button
var _scale_shortcut_buttons: Array[Button] = []
var _scale_readout: Label
var _mass_policy_selector: OptionButton
var _factor_sliders: Dictionary = {}
var _factor_values: Dictionary = {}
var _factor_hints: Dictionary = {}
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
	for definition: Dictionary in Parameters.definitions().parameters:
		if definition.kind == "number" and definition.key != "scale": _factor_capabilities[definition.key] = definition.capability
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
	if recovery_enabled: _start_recovery.call_deferred()


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
	if is_instance_valid(_library_note):
		_library_note.text = tr(message)
		_library_note.visible = not message.is_empty()
	if is_instance_valid(_status_label):
		_status_label.text = tr(message) if message != "" else ""
		_status_label.visible = message != ""
		_status_label.tooltip_text = message
	if _trial_pending:
		_trial_pending = false
	if is_instance_valid(_trial_button):
		_trial_button.disabled = not _edit_valid() or _library_dialog.visible or _name_dialog.visible or is_instance_valid(_guard_dialog)


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
	var title := _label("Aircraft Workshop", "CardTitle", true)
	title.max_lines_visible = 1
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.name = "WorkshopTitle"
	heading.add_child(title)
	_build_identity = _label("", "SecondaryLabel", true, false)
	_build_identity.name = "BuildIdentity"
	_build_identity.max_lines_visible = 1
	_build_identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(_build_identity)
	_header.add_child(heading)
	var back := _button("Back to Pause" if return_destination == "Pause" else "Back to Home", "", "CloseWorkshop")
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	back.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	back.pressed.connect(_request_close)
	_header.add_child(back)

	_identity_line = BoxContainer.new()
	_identity_line.add_theme_constant_override("separation", 8)
	page.add_child(_identity_line)
	_library_button = _button("Library", "", "OpenLibrary")
	_library_button.pressed.connect(_open_library)
	_identity_line.add_child(_library_button)
	var group := ButtonGroup.new()
	for spec: Array in [["appearance", "Appearance"], ["smoke", "Smoke"], ["setup", "Flight setup"], ["compare", "Compare"]]:
		var tab := _button(spec[1], "", "Page" + str(spec[0]).capitalize())
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = spec[0] == "setup"
		tab.pressed.connect(_set_page.bind(spec[0]))
		_identity_line.add_child(tab)
		_page_buttons[spec[0]] = tab
	_page_selector = OptionButton.new()
	_page_selector.name = "WorkshopPage"
	_page_selector.fit_to_longest_item = false
	_page_selector.clip_text = true
	_page_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for page_title: String in ["Appearance", "Smoke", "Flight setup", "Compare"]: _page_selector.add_item(page_title)
	_page_selector.select(PAGE_IDS.find(_active_page))
	_page_selector.item_selected.connect(func(index: int) -> void: _set_page(PAGE_IDS[index]))
	_identity_line.add_child(_page_selector)
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
	var caption := _label("Visual preview · no flight simulation", "SecondaryLabel", true)
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
	for kind: String in ["appearance", "smoke"]:
		var panel := CustomizationPanel.new()
		panel.page_kind = kind
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.profile_changed.connect(set_presentation)
		panel.validity_changed.connect(_presentation_validity_changed)
		panel.visible = false
		inspector_body.add_child(panel)
		_page_nodes[kind] = panel
		_customization_panels.append(panel)
	var setup := VBoxContainer.new()
	setup.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup.add_theme_constant_override("separation", 16)
	inspector_body.add_child(setup)
	_page_nodes.setup = setup
	_trial_conditions_label = _label(trial_conditions, "SecondaryLabel", true)
	_trial_conditions_label.visible = not trial_conditions.is_empty()
	setup.add_child(_trial_conditions_label)
	setup.add_child(_label("Trial start", "SectionLabel"))
	var start := OptionButton.new()
	start.name = "WorkshopTrialStart"
	start.add_item("In the air")
	start.add_item("On the runway")
	start.item_selected.connect(func(index: int) -> void:
		trial_start_choice = "airborne" if index == 0 else "runway"
		_refresh_issues())
	setup.add_child(start)
	_build_presets_panel(setup)
	_mass_button = _button("Measured components…", "", "MeasuredComponents")
	_mass_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mass_button.pressed.connect(_show_mass_editor)
	setup.add_child(_mass_button)
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
	inspector_body.add_child(history)
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
	_action_notes = notes
	notes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer.add_child(notes)
	_validation_label = _label("", "SecondaryLabel", true)
	_validation_label.name = "ValidationLimit"
	_validation_label.max_lines_visible = 2
	_validation_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	notes.add_child(_validation_label)
	_status_label = _label("", "SecondaryLabel", true)
	_status_label.name = "WorkshopStatus"
	_status_label.max_lines_visible = 2
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	notes.add_child(_status_label)
	_review_button = _button("Review issues", "", "ReviewBuildIssues")
	_review_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_review_button.pressed.connect(_review_issues)
	notes.add_child(_review_button)
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
	var tight := enlarged and available.y < 600
	_compact = available.x < 1050 or enlarged
	var inspecting := _compact and _compact_view
	_header.visible = not inspecting
	_action_notes.visible = not inspecting
	find_child("PreviewCaption", true, false).visible = not inspecting
	_header.vertical = available.x < 650
	var back := find_child("CloseWorkshop", true, false) as Button
	back.custom_minimum_size.x = (200 if available.x < 1100 else 380) if enlarged else 200
	back.text = tr("Back") if available.x < 1100 and enlarged else tr("Back to Pause" if return_destination == "Pause" else "Back to Home")
	back.tooltip_text = tr("Back to Pause" if return_destination == "Pause" else "Back to Home")
	for tab: Button in _page_buttons.values(): tab.visible = not _compact
	_page_selector.visible = _compact and not inspecting
	_library_button.visible = not inspecting
	_identity_line.vertical = available.x < 650
	_footer.vertical = available.x < 1100 or enlarged
	_inspector.custom_minimum_size.x = 0 if _compact else (520 if available.x >= 1550 else 400)
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL if _compact else Control.SIZE_FILL
	_preview.custom_minimum_size.y = 0 if _compact else 240
	_aircraft_column.visible = not _compact or _compact_view
	_inspector.visible = not _compact or not _compact_view
	_view_button.visible = _compact
	_view_button.text = tr("Edit") if _compact_view else (tr("View") if enlarged else tr("Preview"))
	_save_button.text = tr("Save") if available.x < 1100 and enlarged else tr("Save build")
	var note_parent: Node = _page_nodes.setup.get_parent() if tight else _footer
	if _action_notes.get_parent() != note_parent:
		_action_notes.reparent(note_parent)
		if not tight: _footer.move_child(_action_notes, 0)
	_recipe_selectors.columns = 1 if enlarged else 2
	_trial_button.custom_minimum_size.x = 0 if enlarged else 190
	


func _build_variants_panel(parent: VBoxContainer) -> void:
	var card := _card("SavedVariantsCard")
	parent.add_child(card)
	var content := _card_content(card)
	content.add_child(_section_label("SAVED BUILDS"))
	_build_search = LineEdit.new()
	_build_search.name = "BuildSearch"
	_build_search.placeholder_text = tr("Search saved builds")
	_build_search.max_length = 128
	_build_search.text_changed.connect(func(_value: String) -> void: _refresh_variants(false))
	content.add_child(_build_search)
	_favorites_only = CheckButton.new()
	_favorites_only.text = "Favorites only"
	_favorites_only.toggled.connect(func(_value: bool) -> void: _refresh_variants(false))
	content.add_child(_favorites_only)
	_favorites_hint = _label("Unavailable favorites remain listed under Favorites only and can be removed.", "SecondaryLabel", true)
	_favorites_hint.visible = false
	content.add_child(_favorites_hint)
	_variant_selector = OptionButton.new()
	_variant_selector.fit_to_longest_item = false
	_variant_selector.clip_text = true
	_variant_selector.name = "SavedVariant"
	_variant_selector.focus_mode = Control.FOCUS_ALL
	_variant_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_variant_selector.item_selected.connect(_on_variant_selected)
	content.add_child(_variant_selector)
	_thumbnail_image = TextureRect.new()
	_thumbnail_image.name = "SavedBuildThumbnail"
	_thumbnail_image.custom_minimum_size.y = 144
	_thumbnail_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_thumbnail_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_thumbnail_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_thumbnail_image.visible = false
	content.add_child(_thumbnail_image)
	_thumbnail_note = _label("", "SecondaryLabel", true)
	_thumbnail_note.name = "SavedBuildThumbnailStatus"
	_thumbnail_note.visible = false
	content.add_child(_thumbnail_note)
	_thumbnail = Thumbnail.new()
	_thumbnail.name = "SavedBuildThumbnailProducer"
	_thumbnail.thumbnail_ready.connect(_receive_thumbnail)
	_thumbnail.unavailable.connect(func(_reason: String) -> void:
		if not _thumbnail_selection.is_empty() and _library_dialog.visible:
			_thumbnail_note.text = tr("Thumbnail unavailable. Build details and actions are still available.")
			_thumbnail_note.visible = true)
	add_child(_thumbnail)

	var variant_actions := HFlowContainer.new()
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
	var import_button := _button("Import build…", "", "ImportBuild")
	import_button.pressed.connect(_choose_bundle_import)
	variant_actions.add_child(import_button)
	_export_button = _button("Export selected…", "", "ExportBuild")
	_export_button.disabled = true
	_export_button.pressed.connect(_choose_bundle_export)
	variant_actions.add_child(_export_button)
	_favorite_button = _button("Add favorite", "", "FavoriteBuild")
	_favorite_button.pressed.connect(_toggle_favorite)
	variant_actions.add_child(_favorite_button)
	_copy_profile_button = _button("Copy appearance and smoke…", "", "CopyBuildProfile")
	_copy_profile_button.pressed.connect(_review_profile_transfer)
	variant_actions.add_child(_copy_profile_button)
	content.add_child(variant_actions)

	_variant_name = LineEdit.new()
	_variant_name.name = "VariantName"
	_variant_name.placeholder_text = tr("Name this build")
	_variant_name.max_length = 64
	_variant_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_variant_name.text_changed.connect(_on_variant_name_changed)
	_variant_name.visible = false
	content.add_child(_variant_name)
	_copy_button = _button("Save a copy", "", "CopyVariant")
	_copy_button.pressed.connect(_request_copy)
	content.add_child(_copy_button)
	var rename := _button("Name or rename this build", "", "RenameBuild")
	rename.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rename.pressed.connect(func() -> void: _show_name_dialog(false))
	content.add_child(rename)


func _build_presets_panel(parent: VBoxContainer) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_label("Starting preset", "SectionLabel"))
	_preset_selector = OptionButton.new()
	_preset_selector.name = "StartingPreset"
	_preset_selector.fit_to_longest_item = false
	_preset_selector.add_item("Custom settings")
	_preset_selector.set_item_metadata(0, "")
	for id: String in PRESETS:
		_preset_selector.add_item(PRESET_LABELS[id])
		_preset_selector.set_item_metadata(_preset_selector.item_count - 1, id)
	_preset_selector.item_selected.connect(func(index: int) -> void:
		if index > 0: _apply_preset(str(_preset_selector.get_item_metadata(index))))
	row.add_child(_preset_selector)
	parent.add_child(row)



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
	for scale: float in _scale_option_values():
		_scale_selector.add_item(String.num(scale * 100.0, 4) + "%")
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

	var scale_steps := HBoxContainer.new()
	scale_steps.name = "ScaleSteps"
	scale_steps.add_theme_constant_override("separation", 8)
	_scale_smaller_button = _button("Smaller", "", "ScaleSmaller")
	_scale_smaller_button.tooltip_text = tr("Reduce aircraft size one step.")
	_scale_smaller_button.pressed.connect(_step_scale.bind(-1))
	_scale_smaller_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_steps.add_child(_scale_smaller_button)
	_scale_larger_button = _button("Larger", "", "ScaleLarger")
	_scale_larger_button.tooltip_text = tr("Increase aircraft size one step.")
	_scale_larger_button.pressed.connect(_step_scale.bind(1))
	_scale_larger_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_steps.add_child(_scale_larger_button)
	content.add_child(scale_steps)

	var shortcut_row := HFlowContainer.new()
	shortcut_row.name = "ScaleShortcuts"
	shortcut_row.add_theme_constant_override("h_separation", 6)
	shortcut_row.add_theme_constant_override("v_separation", 6)
	var shortcut_group := ButtonGroup.new()
	var shortcut_scales: Array[float] = []
	for shortcut: Dictionary in _scale_shortcut_specs():
		var shortcut_scale := float(shortcut.scale)
		if not _within_scale_bounds(shortcut_scale) or shortcut_scales.has(shortcut_scale):
			continue
		shortcut_scales.append(shortcut_scale)
		var shortcut_button := _button(str(shortcut.label), "", "Scale" + str(shortcut.key))
		shortcut_button.toggle_mode = true
		shortcut_button.button_group = shortcut_group
		shortcut_button.set_meta("scale_value", shortcut_scale)
		shortcut_button.tooltip_text = tr("Set the aircraft to %s%% of its original size.") % String.num(shortcut_scale * 100.0, 4)
		shortcut_button.pressed.connect(_apply_scale.bind(shortcut_scale))
		shortcut_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shortcut_row.add_child(shortcut_button)
		_scale_shortcut_buttons.append(shortcut_button)
	content.add_child(shortcut_row)

	_scale_readout = _label("", "SecondaryLabel", true)
	_scale_readout.name = "ScaleReadout"
	content.add_child(_scale_readout)

	var factor_hint := _label("1× keeps the original value. Changes apply to a new trial flight.", "SecondaryLabel", true)
	content.add_child(factor_hint)
	for definition: Dictionary in Parameters.definitions().parameters:
		if _factor_capabilities.has(definition.key): _add_factor_row(content, definition.key, definition.label)

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
	parent.add_child(_label("Experimental values · static estimates, not measured flight performance.", "SecondaryLabel", true))
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
	for definition: Dictionary in Parameters.definitions().parameters:
		if definition.key == key and definition.kind == "number": return Vector2(definition.minimum, definition.maximum)
	return Vector2.ONE


func _build_delete_dialog() -> void:
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = tr("Delete saved build?")
	_delete_dialog.exclusive = true
	_delete_dialog.theme = _screen.theme
	_delete_dialog.dialog_autowrap = true
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
		_presentation = {}
		_resolve_presentation()
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


func _refresh_variants(reload := true) -> void:
	var selected := _selected_variant_id
	var preferences := LibraryPreferences.load_state(variants_root)
	_favorites_ok = preferences.ok
	_favorites = preferences.favorites if preferences.ok else []
	_unavailable_favorite_ids.clear()
	_variant_selector.clear()
	_variant_selector.add_item(tr("Choose a saved build…"))
	_variant_selector.set_item_metadata(0, "")
	if reload:
		_library_summaries.clear()
		for variant: Dictionary in Store.list_variants(variants_root):
			_library_summaries.append({id = variant.get("id", ""), name = variant.get("name", ""), base_id = variant.get("base_id", ""), revision = variant.get("revision", 0)})
	var known_ids: Array[String] = []
	for variant: Dictionary in _library_summaries: known_ids.append(str(variant.id))
	var query := _build_search.text.strip_edges().to_lower()
	for variant: Dictionary in _library_summaries:
		var variant_id := str(variant.get("id", ""))
		if variant_id == "":
			continue
		var source_name := str(Catalog.entry(str(variant.get("base_id", ""))).get("name", tr("Unavailable aircraft")))
		if _favorites_only.button_pressed and variant_id not in _favorites: continue
		if not query.is_empty() and not (str(variant.get("name", "")) + " " + source_name).to_lower().contains(query): continue
		var current := tr("Current") + " · " if variant_id == _saved_variant_id else ""
		if variant_id in _favorites: current = tr("Favorite") + " · " + current
		_variant_selector.add_item(current + str(variant.get("name", variant_id)) + " · " + source_name + " · " + tr("revision %d") % int(variant.get("revision", 0)))
		_variant_selector.set_item_metadata(_variant_selector.item_count - 1, variant_id)
	var missing_count := 0
	for favorite_id: String in _favorites:
		if favorite_id in known_ids: continue
		missing_count += 1
		if not _favorites_only.button_pressed: continue
		var missing_title := tr("Unavailable favorite %d") % missing_count
		if not query.is_empty() and not missing_title.to_lower().contains(query): continue
		_variant_selector.add_item(missing_title)
		_variant_selector.set_item_metadata(_variant_selector.item_count - 1, favorite_id)
		_variant_selector.set_item_tooltip(_variant_selector.item_count - 1, tr("Restore this saved build or remove its favorite."))
		_unavailable_favorite_ids.append(favorite_id)
	_favorites_hint.visible = missing_count > 0
	_variant_selector.select(0)
	_selected_variant_id = ""
	for index in range(1, _variant_selector.item_count):
		if str(_variant_selector.get_item_metadata(index)) == selected:
			_variant_selector.select(index)
			_selected_variant_id = selected
			break
	_sync_variant_actions()
	if not preferences.ok: set_note("Favorites could not be read; existing metadata was preserved.")


func _sync_variant_actions() -> void:
	var available := _selected_variant_id != ""
	var source_available := available and _selected_variant_id not in _unavailable_favorite_ids
	_load_button.disabled = not source_available
	_delete_button.disabled = not source_available
	_export_button.disabled = not source_available
	_favorite_button.disabled = not available or not _favorites_ok
	_favorite_button.text = tr("Remove favorite" if _selected_variant_id in _favorites else "Add favorite")
	_copy_profile_button.disabled = not source_available or not _presentation_buffers.is_empty() or not _presentation_errors.is_empty()
	_sync_save_button()
	_refresh_thumbnail()


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


func _cancel_thumbnail() -> void:
	if is_instance_valid(_thumbnail): _thumbnail.cancel()
	_thumbnail_selection = ""
	_thumbnail_identity.clear()
	if is_instance_valid(_thumbnail_image):
		_thumbnail_image.texture = null
		_thumbnail_image.hide()
	if is_instance_valid(_thumbnail_note): _thumbnail_note.hide()


func _show_mass_editor() -> void:
	if not _pending_numbers.is_empty() or not _presentation_buffers.is_empty():
		set_note("Apply or cancel pending fields before editing measured components.")
		_review_issues()
		return
	if _base.is_empty(): return
	if not is_instance_valid(_mass_dialog):
		_mass_dialog = load("res://ui/workshop_mass.gd").new()
		_mass_dialog.name = "MeasuredComponentsDialog"
		_mass_dialog.theme = _screen.theme
		_mass_dialog.exclusive = true
		_mass_dialog.recipe_proposed.connect(_apply_measured_recipe)
		_mass_dialog.canceled.connect(func() -> void:
			_mass_snapshot.clear()
			_mass_button.grab_focus())
		add_child(_mass_dialog)
	_mass_snapshot = _draft_payload()
	_mass_dialog.configure(_base.duplicate(true), _recipe.duplicate(true))
	_mass_dialog.popup_centered_clamped(Vector2i(820, 560), 0.9)
	_mass_dialog.get_cancel_button().grab_focus()


func _apply_measured_recipe(recipe: Dictionary) -> void:
	if _mass_snapshot.is_empty() or _draft_payload() != _mass_snapshot:
		set_note("The draft changed while measurements were open. Review the measurements again.")
		return
	var checked := Compiler.compile(_base.duplicate(true), recipe)
	if not checked.ok:
		set_note(_messages(checked.errors, "Measured components could not be applied."))
		return
	_mass_dialog.hide()
	_mass_snapshot.clear()
	# The explicit action creates a new draft, preserving every saved original.
	if not _saved_variant_id.is_empty():
		_saved_variant_id = ""
		_saved_variant_revision = 0
		_saved_compiler_version = ""
	_set_recipe(recipe, true)
	_sync_variant_actions()
	set_note("Measured components applied to the draft. The saved build is unchanged.")
	_mass_button.grab_focus()


func _refresh_thumbnail() -> void:
	if not is_instance_valid(_thumbnail) or not _library_dialog.visible or _selected_variant_id.is_empty() or _selected_variant_id in _unavailable_favorite_ids:
		_cancel_thumbnail()
		return
	var revision := 0
	for summary: Dictionary in _library_summaries:
		if str(summary.id) == _selected_variant_id: revision = int(summary.get("revision", 0))
	var selection := "%s:%d" % [_selected_variant_id, revision]
	if selection == _thumbnail_selection: return
	_cancel_thumbnail()
	_thumbnail_selection = selection
	_thumbnail_note.text = tr("Preparing thumbnail…")
	_thumbnail_note.show()
	var loaded := Store.load_variant(_selected_variant_id, variants_root)
	if not loaded.ok:
		_thumbnail_note.text = tr("Thumbnail unavailable. Build details and actions are still available.")
		return
	var requested: Dictionary = _thumbnail.request(loaded.variant)
	_thumbnail_identity = requested.get("identity", {}).duplicate(true)


func _receive_thumbnail(identity: Dictionary, texture: ImageTexture) -> void:
	if not _library_dialog.visible or _thumbnail_selection.is_empty() or identity != _thumbnail_identity: return
	if not _thumbnail_selection.begins_with(_selected_variant_id + ":"): return
	_thumbnail_image.texture = texture
	_thumbnail_image.show()
	_thumbnail_note.hide()


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
	_presentation = variant.get("presentation_profile", {}).duplicate(true)
	_resolve_presentation()
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
	if display_name.is_empty():
		set_note("Name this build before saving.")
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
		_saved_variant_revision if not _saved_variant_id.is_empty() else -1,
		_presentation.duplicate(true)
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
	_delete_dialog.popup_centered_clamped(Vector2i(mini(900, int(get_viewport().get_visible_rect().size.x * 0.9)), 240), 0.9)
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
	if index < 0 or index >= _scale_selector.item_count:
		return
	_apply_scale(float(_scale_selector.get_item_metadata(index)))


func _step_scale(direction: int) -> void:
	if direction == 0:
		return
	var current := float(_recipe.get("scale", 1.0))
	var next := current * SCALE_STEP_RATIO if direction > 0 else current / SCALE_STEP_RATIO
	_apply_scale(next)


func _apply_scale(requested_scale: float) -> void:
	if _syncing_controls or _base.is_empty() or not bool(_capabilities.get("scale", false)):
		return
	if not is_finite(requested_scale):
		set_note("The requested size is not a finite number.")
		return
	var bounded_scale := clampf(requested_scale, Parameters.MIN_SCALE, Parameters.MAX_SCALE)
	var proposed_recipe := _recipe.duplicate(true)
	proposed_recipe["scale"] = bounded_scale
	var checked: Dictionary = Parameters.validate(proposed_recipe)
	if not bool(checked.get("ok", false)):
		set_note(_messages(checked.get("errors", []), "The requested size could not be applied."))
		return
	var accepted_scale := float(checked.values.get("scale", bounded_scale))
	if float(_recipe.get("scale", 1.0)) == accepted_scale:
		return
	_capture_undo()
	_recipe["scale"] = accepted_scale
	_sync_scale_controls()
	_preview.set_aircraft(_base_id, _preview_scale())
	_compile_recipe()


func _scale_option_values() -> Array[float]:
	var values: Array[float] = []
	for candidate: float in SCALE_OPTIONS:
		if _within_scale_bounds(candidate) and not values.has(candidate):
			values.append(candidate)
	for endpoint: float in [Parameters.MIN_SCALE, Parameters.MAX_SCALE]:
		if _within_scale_bounds(endpoint) and not values.has(endpoint):
			values.append(endpoint)
	var current := float(_recipe.get("scale", 1.0))
	if is_finite(current) and not values.has(current):
		values.append(current)
	values.sort()
	return values


func _within_scale_bounds(scale: float) -> bool:
	return is_finite(scale) and scale >= Parameters.MIN_SCALE and scale <= Parameters.MAX_SCALE


func _scale_shortcut_specs() -> Array[Dictionary]:
	var mini_scale := 0.5
	if not _within_scale_bounds(mini_scale) or mini_scale <= Parameters.MIN_SCALE:
		mini_scale = -1.0
		for candidate: float in SCALE_OPTIONS:
			if _within_scale_bounds(candidate) and candidate > Parameters.MIN_SCALE and candidate < 1.0:
				mini_scale = candidate
				break
		if mini_scale < 0.0:
			mini_scale = (Parameters.MIN_SCALE + 1.0) * 0.5
	var large_scale := 1.5
	if not _within_scale_bounds(large_scale) or large_scale >= Parameters.MAX_SCALE:
		large_scale = -1.0
		for candidate: float in SCALE_OPTIONS:
			if _within_scale_bounds(candidate) and candidate > 1.0 and candidate < Parameters.MAX_SCALE:
				large_scale = candidate
		if large_scale < 0.0:
			large_scale = (1.0 + Parameters.MAX_SCALE) * 0.5
	return [
		{"key": "Tiny", "label": "Tiny", "scale": Parameters.MIN_SCALE},
		{"key": "Mini", "label": "Mini", "scale": mini_scale},
		{"key": "Original", "label": "Original", "scale": 1.0},
		{"key": "Large", "label": "Large", "scale": large_scale},
		{"key": "Giant", "label": "Giant", "scale": Parameters.MAX_SCALE},
	]


func _sync_scale_controls() -> void:
	if not is_instance_valid(_scale_selector) or _recipe.is_empty():
		return
	var current := float(_recipe.get("scale", 1.0))
	_scale_selector.clear()
	var selected_index := -1
	for scale: float in _scale_option_values():
		_scale_selector.add_item(String.num(scale * 100.0, 4) + "%")
		var index := _scale_selector.item_count - 1
		_scale_selector.set_item_metadata(index, scale)
		if scale == current:
			selected_index = index
	if selected_index >= 0:
		_scale_selector.select(selected_index)
	var supported := bool(_capabilities.get("scale", false))
	_scale_selector.disabled = not supported
	var effective_scale := _preview_scale()
	_scale_smaller_button.disabled = not supported or effective_scale <= Parameters.MIN_SCALE
	_scale_larger_button.disabled = not supported or effective_scale >= Parameters.MAX_SCALE
	for button: Button in _scale_shortcut_buttons:
		var shortcut_scale := float(button.get_meta("scale_value", -1.0))
		button.set_pressed_no_signal(supported and is_equal_approx(effective_scale, shortcut_scale))
		button.disabled = not supported


func _refresh_size_readout() -> void:
	if not is_instance_valid(_scale_readout):
		return
	var size_percent := String.num(_preview_scale() * 100.0, 4)
	var summary: Dictionary = _compiled.get("summary", {})
	if _edit_valid() and _pending_numbers.is_empty() and summary.has("wing_span_m"):
		_scale_readout.text = tr("Size: %s%% · wingspan: %s m") % [size_percent, String.num(float(summary.wing_span_m), 4)]
	else:
		_scale_readout.text = tr("Proposed size: %s%% · wingspan pending validation.") % size_percent


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
	for key: String in _factor_capabilities:
		var capability := str(_factor_capabilities[key])
		next[key] = preset.get(key, next.get(key, 1.0)) if bool(caps.get(capability, false)) else _recipe.get(key, next.get(key, 1.0))
	_set_recipe(next, true)
	for index in _preset_selector.item_count:
		if _preset_selector.get_item_metadata(index) == preset_id: _preset_selector.select(index)
	set_note(tr("Applied the %s preset where this aircraft supports it.") % tr(PRESET_LABELS[preset_id]))


func _reset_recipe() -> void:
	if _base.is_empty():
		return
	if _active_page in ["appearance", "smoke"]:
		var next := _presentation.duplicate(true)
		if _active_page == "appearance":
			next.paint = []
			next.markings = []
		else: next.smoke = []
		set_presentation(next)
		return
	_set_recipe(Compiler.defaults(), true)
	set_note("Recipe reset to defaults. Use Undo to restore the previous values.")


func _undo() -> void:
	if _undo_history.is_empty():
		return
	_redo_history.append(_history_snapshot())
	var previous: Dictionary = _undo_history.pop_back()
	_restore_history(previous)
	_update_undo_button()
	set_note("Previous recipe restored.")


func _redo() -> void:
	if _redo_history.is_empty():
		return
	_undo_history.append(_history_snapshot())
	var next: Dictionary = _redo_history.pop_back()
	_restore_history(next)
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
	_undo_history.append(_history_snapshot())
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
	_preset_selector.select(0)
	_sync_scale_controls()
	var policy := str(_recipe.get("mass_policy", "constant_wing_loading"))
	for index in _mass_policy_selector.item_count:
		if str(_mass_policy_selector.get_item_metadata(index)) == policy:
			_mass_policy_selector.select(index)
			break
	_mass_policy_selector.disabled = not bool(_capabilities.get("weight", false))
	for key: String in _factor_capabilities:
		var bounds := _factor_bounds(key)
		var value := float(_recipe.get(key, 1.0))
		# Range preserves its exact value when step is restored; avoid quantizing a loaded recipe.
		_factor_sliders[key].step = 0.0
		_factor_sliders[key].set_value_no_signal(value)
		_factor_sliders[key].step = FACTOR_STEP
		_factor_values[key].text = String.num(value, 4) + "×"
		_factor_inputs[key].text = String.num(value, 4)
		var supported := bool(_capabilities.get(str(_factor_capabilities[key]), false))
		_factor_sliders[key].editable = supported
		_factor_inputs[key].editable = supported
		if supported and key == "tank_capacity_multiplier":
			_factor_hints[key].text = tr("Estimated sizing proposal; tank dimensions scale uniformly. Fill fraction and blend density are preserved.")
		elif not supported and key == "tank_capacity_multiplier":
			_factor_hints[key].text = tr("No declared finite tank.")
		else:
			_factor_hints[key].text = (
				tr("Range %.2f×–%.2f×") % [bounds.x, bounds.y]
				if supported else tr("Not available for this engine type.")
			)
	_syncing_controls = false
	_sync_presentation()
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
	_trial_button.disabled = not valid or not _edit_valid()
	var compiled_data: Dictionary = _compiled.get("data", {})
	var compiled_model: Variant = compiled_data.get("model", {})
	_summary_label.text = _format_summary(
		_compiled.get("summary", {}),
		compiled_model if compiled_model is Dictionary else {}
	)
	_refresh_issues()
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
	if is_instance_valid(_mass_dialog) and _mass_dialog.visible: return
	if is_instance_valid(_recovery_dialog) and _recovery_dialog.visible: return
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
	if recovery_enabled: _autosave_draft()
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
		"presentation_profile": _presentation.duplicate(true),
		"start_choice": trial_start_choice,
	})


func _request_close() -> void:
	if dismiss_modal_for_exit(): return
	if _active_page in ["appearance", "smoke"] and _page_nodes[_active_page].cancel_pending_edit(): return
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


## Main-window close consumes one active editor modal before beginning an exit decision.
func dismiss_modal_for_exit() -> bool:
	if is_instance_valid(_mass_dialog) and _mass_dialog.visible:
		_mass_dialog.hide()
		_mass_snapshot.clear()
		_mass_button.grab_focus()
		return true
	if is_instance_valid(_recovery_dialog) and _recovery_dialog.visible:
		_recovery_dialog.hide()
		_trial_button.disabled = not _edit_valid()
		set_note("Automatic draft recovery is paused until you restore or discard the recovered draft.")
		_library_button.grab_focus()
		return true
	if is_instance_valid(_transfer_dialog) and _transfer_dialog.visible:
		_transfer_dialog.hide()
		_transfer_proposal.clear()
		_transfer_snapshot.clear()
		return true
	if is_instance_valid(_bundle_dialog) and _bundle_dialog.visible:
		_bundle_dialog.hide()
		return true
	if is_instance_valid(_guard_dialog) and _guard_dialog.visible:
		_navigation_abort()
		return true
	if _delete_dialog.visible:
		_delete_dialog.hide()
		_delete_dialog.canceled.emit()
		return true
	if _name_dialog.visible:
		_name_dialog.hide()
		_name_dialog.canceled.emit()
		return true
	if _library_dialog.visible:
		_close_library()
		return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	# Keyboard Escape is consumed by Screen; selected-menu-pad Back uses ui_cancel.
	if event is InputEventKey or not _screen._active or not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	_request_close()


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
	var scroll := ScrollContainer.new()
	scroll.name = "LibraryScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(300, 100)
	_library_dialog.add_child(scroll)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	body.add_child(_label("Stock aircraft", "CardTitle"))
	_base_selector = OptionButton.new()
	_base_selector.name = "BaseAircraft"
	_base_selector.fit_to_longest_item = false
	_base_selector.clip_text = true
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
	_library_note = _label("", "SecondaryLabel", true)
	_library_note.visible = false
	body.add_child(_library_note)
	_bundle_dialog = FileDialog.new()
	_bundle_dialog.name = "WorkshopBundleFile"
	_bundle_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_bundle_dialog.filters = PackedStringArray(["*.json ; " + tr("Aircraft build")])
	_bundle_dialog.display_mode = FileDialog.DISPLAY_LIST
	_bundle_dialog.favorites_enabled = false
	_bundle_dialog.recent_list_enabled = false
	_bundle_dialog.layout_toggle_enabled = false
	_bundle_dialog.file_sort_options_enabled = false
	_bundle_dialog.file_filter_toggle_enabled = false
	_bundle_dialog.deleting_enabled = false
	_bundle_dialog.theme = _screen.theme.duplicate()
	# File navigation needs denser rows than the editor's large primary actions.
	for type_name: String in ["Label", "Button", "LineEdit", "ItemList", "OptionButton", "PopupMenu"]:
		_bundle_dialog.theme.set_font_size("font_size", type_name, UiTheme._font_size(18))
	_bundle_dialog.add_theme_font_size_override("title_font_size", UiTheme._font_size(18))
	_bundle_dialog.exclusive = true
	_library_dialog.add_child(_bundle_dialog)
	_bundle_dialog.file_selected.connect(_bundle_file_selected)
	_transfer_dialog = ConfirmationDialog.new()
	_transfer_dialog.name = "ReviewProfileCopy"
	_transfer_dialog.title = tr("Review compatible settings")
	_transfer_dialog.ok_button_text = tr("Apply settings")
	_transfer_dialog.theme = _screen.theme
	_transfer_dialog.exclusive = true
	_library_dialog.add_child(_transfer_dialog)
	var transfer_scroll := ScrollContainer.new()
	transfer_scroll.custom_minimum_size = Vector2(260, 100)
	transfer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_transfer_dialog.add_child(transfer_scroll)
	_transfer_text = _label("", "SecondaryLabel", true)
	_transfer_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transfer_scroll.add_child(_transfer_text)
	_transfer_dialog.confirmed.connect(_apply_profile_transfer)
	_transfer_dialog.canceled.connect(func() -> void:
		_transfer_proposal.clear()
		_transfer_snapshot.clear()
		_copy_profile_button.grab_focus())


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
		if succeeded:
			_name_dialog.hide()
			_trial_button.disabled = not _edit_valid()
		else:
			_name_error.text = _status_label.text)
	_name_dialog.canceled.connect(func() -> void:
		_variant_name.text = _name_before
		_refresh_identity()
		_trial_button.disabled = not _edit_valid()
		if _save_button.is_visible_in_tree(): _save_button.grab_focus())
	add_child(_name_dialog)
	_name_body = VBoxContainer.new()
	_name_body.add_child(_label("Build name", "SecondaryLabel"))
	_name_error = _label("", "ErrorLabel", true)
	_name_body.add_child(_name_error)
	_name_dialog.add_child(_name_body)
	# The name field is created with library controls; saving a new draft can show it here.


func _open_library() -> void:
	_library_note.text = ""
	_refresh_variants()
	_select_base(_base_id)
	_trial_button.disabled = true
	_library_dialog.popup_centered_clamped(Vector2i(680, 520), 0.9)
	_refresh_thumbnail()
	_base_selector.grab_focus()


func _close_library() -> void:
	_library_dialog.hide()
	_cancel_thumbnail()
	_trial_button.disabled = not _edit_valid() or _trial_pending
	if _library_button.is_visible_in_tree(): _library_button.grab_focus()


func _request_save() -> void:
	if is_instance_valid(_mass_dialog) and _mass_dialog.visible: return
	if is_instance_valid(_recovery_dialog) and _recovery_dialog.visible: return
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
	_variant_name.reparent(_name_body)
	_name_body.move_child(_variant_name, 1)
	_name_error.text = ""
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
	_page_selector.select(PAGE_IDS.find(page))
	_compact_view = false
	for id: String in _page_nodes:
		_page_nodes[id].visible = id == page
		_page_buttons[id].set_pressed_no_signal(id == page)
	_body_scroll.scroll_vertical = 0
	_resize_layout()
	_schedule_recovery()


func _toggle_compact_view() -> void:
	_compact_view = not _compact_view
	_resize_layout()


func _draft_payload() -> Dictionary:
	return {base_id = _base_id, base_bytes = _base_bytes.duplicate(), recipe = _recipe.duplicate(true),
		name = _variant_name.text.strip_edges(), descriptor = _workshop_descriptor.duplicate(true),
		dependencies = _variant_dependencies.duplicate(true), compiler = _saved_compiler_version,
		presentation_profile = _presentation.duplicate(true)}


func has_unsaved_changes() -> bool:
	return _recovery_requires_copy or not _invalid_fields.is_empty() or not _pending_numbers.is_empty() or not _presentation_buffers.is_empty() \
		or (not _baseline.is_empty() and _draft_payload() != _baseline)


func _mark_baseline() -> void:
	_recovery_requires_copy = false
	_baseline = _draft_payload()
	if is_instance_valid(_recovery_timer) and not _recovery_pending and not _recovery_restoring:
		_discard_current_recovery()
	_refresh_identity()


func _refresh_identity() -> void:
	if not is_instance_valid(_build_identity): return
	var display_name := _variant_name.text.strip_edges()
	if display_name.is_empty(): display_name = tr("Unsaved build")
	var state := tr("Unsaved changes") if has_unsaved_changes() else (tr("Saved") if not _saved_variant_id.is_empty() else tr("New build"))
	var revision := " · " + tr("revision %d") % _saved_variant_revision if _saved_variant_revision > 0 else ""
	_build_identity.text = "%s · %s%s · %s" % [display_name, tr(str(Catalog.entry(_base_id).get("name", _base_id))), revision, state]
	_build_identity.tooltip_text = _build_identity.text
	_schedule_recovery()


func _edit_valid() -> bool:
	return bool(_compiled.get("ok", false)) and _invalid_fields.is_empty() and _presentation_errors.is_empty() and _presentation_buffers.is_empty()


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
	_guard_dialog.theme = _screen.theme
	_guard_dialog.exclusive = true
	_guard_dialog.dialog_hide_on_ok = false
	_guard_dialog.ok_button_text = tr("Save and continue")
	_guard_dialog.cancel_button_text = tr("Cancel")
	var discard := _guard_dialog.add_button(tr("Discard changes"), false, "discard")
	var host: Node = dialog_host if dialog_host != null else self
	var popup_width := mini(1100, int(host.get_viewport().get_visible_rect().size.x * 0.9))
	_guard_dialog.add_theme_constant_override("buttons_min_width", maxi(100, (popup_width - 64) / 3))
	for button: Button in [_guard_dialog.get_ok_button(), _guard_dialog.get_cancel_button(), discard]:
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_guard_dialog.confirmed.connect(_navigation_save)
	_guard_dialog.canceled.connect(_navigation_abort)
	_guard_dialog.custom_action.connect(func(action: String) -> void:
		if action == "discard": _navigation_finish())
	host.add_child(_guard_dialog)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(300, 100)
	_guard_dialog.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	body.add_child(_label("Save this build before continuing?", "SecondaryLabel", true))
	body.add_child(_label(destination, "SecondaryLabel", true))
	_guard_name = LineEdit.new()
	_guard_name.placeholder_text = tr("Name this build")
	_guard_name.max_length = 64
	_guard_name.text = _variant_name.text
	body.add_child(_label("Build name", "SecondaryLabel"))
	body.add_child(_guard_name)
	_guard_error = _label("", "ErrorLabel", true)
	body.add_child(_guard_error)
	_guard_dialog.get_ok_button().disabled = not _edit_valid()
	if not _edit_valid(): _guard_error.text = tr("This build cannot be saved until its errors are resolved.")
	_guard_dialog.popup_centered_clamped(Vector2i(popup_width, 440), 0.9)
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
	if recovery_enabled and not _recovery_pending: _discard_current_recovery()
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
	_refresh_issues()


func _commit_number(key: String) -> void:
	if not _pending_numbers.has(key) or _invalid_fields.has(key): return
	var value := str(_pending_numbers[key]).to_float()
	_pending_numbers.erase(key)
	if float(_recipe.get(key, 1.0)) != value:
		_capture_undo()
		_recipe[key] = value
		_factor_values[key].text = String.num(value, 4) + "×"
		_factor_sliders[key].step = 0.0
		_factor_sliders[key].set_value_no_signal(value)
		_factor_sliders[key].step = FACTOR_STEP
	_compile_recipe()


func _refresh_issues() -> void:
	_refresh_size_readout()
	var messages := _messages(_compiled.get("errors", []), "")
	if not _presentation_buffers.is_empty(): messages += ("\n" if not messages.is_empty() else "") + tr("Apply or cancel the edited color or inscription before saving or starting a trial.")
	if not _presentation_errors.is_empty(): messages += ("\n" if not messages.is_empty() else "") + "\n".join(_presentation_errors)
	for key: String in _factor_inputs:
		var entry: LineEdit = _factor_inputs[key]
		entry.tooltip_text = str(_invalid_fields.get(key, ""))
		if _invalid_fields.has(key):
			entry.add_theme_color_override("font_color", _screen.theme.get_color("font_color", "ErrorLabel"))
			messages += ("\n" if not messages.is_empty() else "") + str(_invalid_fields[key])
		else:
			entry.remove_theme_color_override("font_color")
	_errors_label.text = messages
	_errors_label.visible = not messages.is_empty()
	_review_button.visible = not _edit_valid()
	_validation_label.text = tr("Ready for a trial · runway qualification required" if trial_start_choice == "runway" else "Ready for a trial · start in the air") if _edit_valid() else tr("Build blocked until the listed validation errors are resolved.")


func _review_issues() -> void:
	if not _presentation_buffers.is_empty():
		_set_page(str(_presentation_buffers.keys()[0]))
		var pending: Control = _page_nodes[_active_page].pending_control()
		pending.grab_focus()
		_body_scroll.ensure_control_visible(pending)
		return
	_set_page("setup")
	for key: String in _invalid_fields:
		var entry: LineEdit = _factor_inputs[key]
		entry.grab_focus()
		_body_scroll.ensure_control_visible(entry)
		return
	_errors_label.focus_mode = Control.FOCUS_ALL
	_errors_label.grab_focus()
	_body_scroll.ensure_control_visible(_errors_label)


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
	for key: String in ["paint", "markings", "smoke"]:
		var count: int = _presentation.get(key, []).size()
		if count > 0 or _all_values.button_pressed:
			for value: String in [tr(key.capitalize()), tr("Stock"), str(count), tr("Visual only")]: _comparison_cell(value)
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


func get_presentation() -> Dictionary:
	return _presentation.duplicate(true)


func _presentation_validity_changed(page: String, pending: bool) -> void:
	if pending: _presentation_buffers[page] = true
	else: _presentation_buffers.erase(page)
	if is_instance_valid(_review_button):
		_refresh_issues()
		_sync_save_button()
		_trial_button.disabled = not _edit_valid()
		if is_instance_valid(_copy_profile_button): _sync_variant_actions()


func _toggle_favorite() -> void:
	if _selected_variant_id.is_empty(): return
	var result := LibraryPreferences.set_favorite(_selected_variant_id, _selected_variant_id not in _favorites, variants_root)
	if not result.ok:
		set_note(_messages(result.errors, "Favorites could not be saved."))
		return
	_refresh_variants(false)


func _review_profile_transfer() -> void:
	if _selected_variant_id.is_empty() or not _presentation_buffers.is_empty(): return
	var loaded := Store.load_variant(_selected_variant_id, variants_root)
	if not loaded.ok:
		set_note(_messages(loaded.errors, "The saved build could not be loaded."))
		return
	var described := Customization.describe(str(loaded.variant.base_id))
	if not described.get("ok", false):
		set_note("The source build has no current presentation bindings.")
		return
	var result := ProfileTransfer.propose(loaded.variant.presentation_profile, described.bindings, _presentation, _presentation_bindings)
	if not result.ok:
		set_note(_messages(result.errors, "These presentation settings cannot be copied."))
		return
	_transfer_snapshot = _presentation.duplicate(true)
	_transfer_base_id = _base_id
	_transfer_proposal = result.profile.duplicate(true)
	var lines := PackedStringArray([tr("From %s · revision %d") % [str(loaded.variant.name), int(loaded.variant.revision)], tr("Only listed compatible settings will change. Physical adjustments stay unchanged.")])
	for group: String in ["applied", "skipped"]:
		lines.append("")
		lines.append(tr("Settings to apply" if group == "applied" else "Settings skipped"))
		if result[group].is_empty(): lines.append(tr("None"))
		for row: Dictionary in result[group]:
			lines.append(_transfer_setting_label(row, described.bindings))
	_transfer_text.text = "\n".join(lines)
	_transfer_dialog.get_ok_button().disabled = result.applied.is_empty()
	_transfer_dialog.popup_centered_clamped(Vector2i(900, 520), 0.9)
	_transfer_dialog.get_cancel_button().grab_focus()


func _apply_profile_transfer() -> void:
	_transfer_dialog.hide()
	if _transfer_proposal.is_empty(): return
	if _base_id != _transfer_base_id or _presentation != _transfer_snapshot or not _presentation_buffers.is_empty():
		_transfer_proposal.clear()
		set_note("The draft changed. Review the settings again before applying them.")
		return
	var accepted := _transfer_proposal.duplicate(true)
	_transfer_proposal.clear()
	_transfer_snapshot.clear()
	_close_library()
	set_presentation(accepted)
	set_note("Compatible appearance and smoke settings copied. Undo restores the previous presentation.")


func _transfer_setting_label(row: Dictionary, source_bindings: Dictionary) -> String:
	var fields := {paint = "paint_slots", markings = "marking_slots", smoke = "smoke_slots"}
	var title := ""
	for slot: Dictionary in source_bindings.get(fields.get(row.domain, ""), []):
		if slot.id == row.slot: title = tr(str(slot.label))
	var reasons := {
		compatible = "Compatible", source_slot_missing = "Source setting is unavailable.",
		target_slot_missing = "No matching region or emitter on this aircraft.",
		paint_pattern_unsupported = "This pattern is unavailable.",
		paint_kind_mismatch = "This region uses a different material.",
		paint_accent_unsupported = "This accent is unavailable.",
		paint_accent_kind_mismatch = "This accent uses a different material.",
		marking_glyph_support_unpinned = "These inscription characters cannot be verified.",
		marking_text_too_long = "The inscription exceeds this panel's limit.",
		smoke_endpoint_mismatch = "The emitter has a different purpose or source.",
	}
	return "• %s / %s · %s" % [tr(str(row.domain).capitalize()), title, tr(str(reasons.get(row.reason, "This setting is unavailable.")))]


func _choose_bundle_import() -> void:
	_bundle_import = true
	_bundle_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_bundle_dialog.title = tr("Import aircraft build")
	_prepare_bundle_dialog()
	_bundle_dialog.popup_centered_clamped(Vector2i(800, 520), 0.9)


func _choose_bundle_export() -> void:
	var loaded := Store.load_variant(_selected_variant_id, variants_root)
	if not loaded.ok:
		set_note(_messages(loaded.errors, "The saved build could not be loaded."))
		return
	var exported := Bundle.export_variant(loaded.variant)
	if not exported.ok:
		set_note(_messages(exported.errors, "The build could not be exported."))
		return
	_bundle_export_bytes = exported.bytes.duplicate()
	_bundle_import = false
	_bundle_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_bundle_dialog.current_file = "aircraft-build.json"
	_bundle_dialog.title = tr("Export aircraft build")
	_prepare_bundle_dialog()
	_bundle_dialog.popup_centered_clamped(Vector2i(800, 520), 0.9)


func _prepare_bundle_dialog() -> void:
	# Godot's built-in dialog strings do not use the project's translation catalog automatically.
	for node: Node in _bundle_dialog.find_children("*", "Control", true, false):
		if node is Label or node is Button: node.text = tr(node.text)


func _bundle_file_selected(path: String) -> void:
	if _bundle_import:
		_close_library()
		request_navigation("Import aircraft build", _import_bundle_file.bind(path))
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		set_note("The build could not be exported.")
		return
	file.store_buffer(_bundle_export_bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or FileAccess.get_file_as_bytes(path) != _bundle_export_bytes:
		set_note("The exported file failed its readback check.")
		return
	_bundle_export_bytes.clear()
	set_note("Aircraft build exported.")
	_close_library()


func _import_bundle_file(path: String) -> void:
	var imported := Bundle.import_file(path, variants_root)
	if not imported.ok:
		set_note(_messages(imported.errors, "The build could not be imported."))
		return
	_refresh_variants()
	_load_variant_snapshot(str(imported.variant.id))
	set_note("Aircraft build imported as a new local copy.")


func set_presentation(profile: Dictionary) -> void:
	var checked := Presentation.validate(profile, _presentation_bindings)
	if not checked.ok:
		set_note("; ".join(PackedStringArray(checked.errors)))
		return
	if checked.profile == _presentation: return
	_capture_undo()
	_presentation = checked.profile.duplicate(true)
	_presentation_errors.clear()
	_sync_presentation()
	_refresh_issues()
	_sync_save_button()
	_refresh_comparison()


func _resolve_presentation() -> void:
	var described := Customization.describe(_base_id)
	_presentation_bindings = described.get("bindings", {}) if described.get("ok", false) else {}
	var checked := Presentation.validate(_presentation, _presentation_bindings)
	_presentation_errors = PackedStringArray(checked.get("errors", []))
	if checked.ok: _presentation = checked.profile.duplicate(true)
	_sync_presentation()


func _sync_presentation() -> void:
	for panel in _customization_panels: panel.configure(_presentation_bindings, _presentation)
	if is_instance_valid(_preview): _preview.set_presentation(_presentation)


func _history_snapshot() -> Dictionary:
	return {recipe = _recipe.duplicate(true), presentation_profile = _presentation.duplicate(true)}


func _restore_history(snapshot: Dictionary) -> void:
	_recipe = snapshot.recipe.duplicate(true)
	_presentation = snapshot.presentation_profile.duplicate(true)
	_invalid_fields.clear()
	_pending_numbers.clear()
	_resolve_presentation()
	_sync_controls()
	_preview.set_aircraft(_base_id, _preview_scale())
	_compile_recipe()


func _start_recovery() -> void:
	if not recovery_enabled or is_instance_valid(_recovery_timer): return
	_recovery_timer = Timer.new()
	_recovery_timer.name = "DraftRecoveryDebounce"
	_recovery_timer.one_shot = true
	_recovery_timer.wait_time = 0.75
	_recovery_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_recovery_timer.timeout.connect(_autosave_draft)
	add_child(_recovery_timer)
	_recovery_button = _button("Recovered draft…", "", "RecoverDraft")
	_recovery_button.visible = false
	_recovery_button.pressed.connect(_show_recovery)
	_library_note.get_parent().add_child(_recovery_button)
	var service: Script = load("res://workshop/draft_store.gd")
	_recovery_loaded = service.load_snapshot(recovery_root)
	_recovery_digest = str(_recovery_loaded.get("digest", ""))
	_recovery_pending = bool(_recovery_loaded.get("exists", false))
	_recovery_button.visible = _recovery_pending
	if _recovery_pending: _show_recovery()


func _recovery_editor_state() -> Dictionary:
	var buffers := {}
	for page: String in ["appearance", "smoke"]:
		buffers[page] = _page_nodes[page].get_editor_state()
	return {"page": _active_page, "name": _variant_name.text, "numeric_buffers": _pending_numbers.duplicate(true),
		"presentation_buffers": buffers, "camera": _preview.get_view_state()}


func _schedule_recovery() -> void:
	if not recovery_enabled or _recovery_pending or _recovery_restoring or not is_instance_valid(_recovery_timer): return
	_recovery_timer.start()


## Explicitly callable for teardown/tests. Does not create a named library revision.
func _autosave_draft() -> bool:
	if not recovery_enabled or _recovery_pending or _recovery_restoring or _base_bytes.is_empty(): return false
	if _recovery_digest.is_empty():
		set_note("Recovery data cannot be safely replaced. Review the recovery files before retrying.")
		return false
	if not has_unsaved_changes(): return true
	var build := _draft_payload()
	var state := _recovery_editor_state()
	var snapshot := {"build": build, "editor": state}
	if snapshot == _recovery_last: return true
	if build.descriptor.is_empty():
		var descriptor: Dictionary = load("res://workshop/descriptor.gd").load_for(_base_id, _base_bytes)
		if not descriptor.ok:
			set_note("Automatic draft recovery is unavailable: " + _messages(descriptor.errors, "Source pins could not be read."))
			return false
		build.descriptor = descriptor.descriptor
	if build.dependencies.is_empty():
		var dependencies: Dictionary = load("res://workshop/dependencies.gd").capture(_base)
		if not dependencies.ok:
			set_note("Automatic draft recovery is unavailable: " + _messages(dependencies.errors, "Dependency pins could not be read."))
			return false
		build.dependencies = dependencies.manifest
	if str(build.compiler).is_empty(): build.compiler = Compiler.version_for_recipe(_recipe)
	var result: Dictionary = load("res://workshop/draft_store.gd").save_snapshot(recovery_root, build, state, "", _recovery_digest)
	if not result.ok:
		if result.get("conflict", false):
			_refresh_recovery_after_conflict()
			return false
		set_note("Automatic draft recovery failed: " + _messages(result.errors, "Retry by editing the build."))
		return false
	_recovery_digest = str(result.digest)
	_recovery_last = snapshot.duplicate(true)
	return true


func _show_recovery() -> void:
	if not _recovery_pending: return
	_close_library()
	if not is_instance_valid(_recovery_dialog):
		_recovery_dialog = ConfirmationDialog.new()
		_recovery_dialog.name = "RecoveredDraftDialog"
		_recovery_dialog.title = tr("Recovered draft")
		_recovery_dialog.ok_button_text = tr("Restore as a new build")
		_recovery_dialog.cancel_button_text = tr("Later")
		_recovery_dialog.theme = _screen.theme
		_recovery_dialog.exclusive = true
		_recovery_dialog.dialog_hide_on_ok = false
		_recovery_dialog.confirmed.connect(_request_recovery_restore)
		_recovery_dialog.canceled.connect(func() -> void:
			_trial_button.disabled = not _edit_valid()
			set_note("Automatic draft recovery is paused until you restore or discard the recovered draft.")
			_library_button.grab_focus())
		_recovery_dialog.add_button(tr("Discard recovered draft"), false, "discard")
		_recovery_dialog.custom_action.connect(func(action: StringName) -> void:
			if action == "discard": _discard_pending_recovery())
		add_child(_recovery_dialog)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(260, 140)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_recovery_dialog.add_child(scroll)
		_recovery_text = _label("", "SecondaryLabel", true, false)
		_recovery_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(_recovery_text)
	var lines := PackedStringArray([tr("Restore keeps the saved library unchanged. Review all values and save a new build.")])
	if _recovery_loaded.get("ok", false):
		var payload: Dictionary = _recovery_loaded.payload
		var state: Dictionary = _recovery_loaded.editor
		lines.append(str(state.get("name", "")))
		lines.append(str(Catalog.entry(str(payload.base_id)).get("name", payload.base_id)))
		lines.append(tr("Accepted settings"))
		for key: String in payload.recipe:
			if key == "mass_edits":
				for edit: Dictionary in payload.recipe[key]:
					var component_name := str(edit.id)
					for item: Dictionary in payload.base.inventory:
						if item.get("id", "") == edit.id: component_name = str(item.name)
					lines.append("%s: %.4f kg" % [component_name, float(edit.mass_kg)])
				continue
			var value := str(payload.recipe[key])
			if key == "scale": value = String.num(float(payload.recipe[key]) * 100.0, 2) + "%"
			elif key == "mass_policy": value = tr("Constant wing loading" if payload.recipe[key] == "constant_wing_loading" else "Geometric")
			else: value += "×"
			lines.append("%s: %s" % [_parameter_label(key), value])
		if not state.get("numeric_buffers", {}).is_empty(): lines.append(tr("Pending input"))
		for key: String in state.get("numeric_buffers", {}): lines.append("%s: %s" % [_parameter_label(key), state.numeric_buffers[key]])
		for page: String in state.get("presentation_buffers", {}):
			var raw: Dictionary = state.presentation_buffers[page]
			if not str(raw.get("color_text", "")).is_empty(): lines.append("%s: %s" % [tr(page.capitalize()), raw.color_text])
			if not str(raw.get("marking_text", "")).is_empty(): lines.append("%s: %s" % [tr("Registration"), raw.marking_text])
	if not _recovery_loaded.get("compatible", false):
		lines.append(tr("This draft is unavailable with the current dependencies. Its stored data remains unchanged."))
		lines.append(_messages(_recovery_loaded.get("compatibility_errors", []), ""))
	lines.append(_messages(_recovery_loaded.get("errors", []), ""))
	_recovery_text.text = "\n".join(lines)
	_recovery_dialog.get_ok_button().disabled = not bool(_recovery_loaded.get("ok", false)) or not bool(_recovery_loaded.get("compatible", false))
	_recovery_dialog.popup_centered_clamped(Vector2i(680, 480), 0.9)
	_recovery_dialog.get_cancel_button().grab_focus()
	_trial_button.disabled = true


func _parameter_label(key: String) -> String:
	return tr(str({"scale": "Size", "mass_policy": "Mass policy", "weight_multiplier": "Weight", "power_multiplier": "Power", "control_multiplier": "Control travel", "tank_capacity_multiplier": "Tank capacity"}.get(key, "Setting")))


func _request_recovery_restore() -> void:
	if not _recovery_pending: return
	_recovery_dialog.hide()
	request_navigation("Restore recovered draft", _apply_recovered_draft, func() -> void:
		_trial_button.disabled = not _edit_valid()
		_library_button.grab_focus())


func _apply_recovered_draft() -> void:
	if not _recovery_pending: return
	var fresh: Dictionary = load("res://workshop/draft_store.gd").load_snapshot(recovery_root)
	if not fresh.get("ok", false) or not fresh.get("compatible", false) or str(fresh.get("digest", "")) != _recovery_digest:
		_refresh_recovery_after_conflict()
		if _recovery_pending: _show_recovery()
		return
	var payload: Dictionary = fresh.payload
	var state: Dictionary = fresh.editor
	for key: String in state.numeric_buffers:
		if not _factor_inputs.has(key):
			set_note("A recovered numeric field is unavailable. The stored draft remains unchanged.")
			_trial_button.disabled = not _edit_valid()
			return
	# Prove every stored selection can be restored before changing the active draft.
	var described := Customization.describe(str(payload.base_id))
	if not described.get("ok", false): return
	for page: String in state.presentation_buffers:
		var probe := CustomizationPanel.new()
		probe.page_kind = page
		probe.visible = false
		add_child(probe)
		probe.configure(described.bindings, payload.presentation_profile)
		var restorable := probe.restore_editor_state(state.presentation_buffers[page])
		probe.free()
		if not restorable:
			set_note("A recovered text field is unavailable. The stored draft remains unchanged.")
			_trial_button.disabled = not _edit_valid()
			return
	_recovery_restoring = true
	_base_id = payload.base_id
	_base = payload.base.duplicate(true)
	_base_bytes = payload.base_bytes.duplicate()
	_workshop_descriptor = payload.workshop_descriptor.duplicate(true)
	_variant_dependencies = payload.dependencies.duplicate(true)
	_saved_compiler_version = payload.compiler_version
	_saved_variant_id = ""
	_saved_variant_revision = 0
	_selected_variant_id = ""
	_recipe = payload.recipe.duplicate(true)
	_presentation = payload.presentation_profile.duplicate(true)
	_invalid_fields.clear()
	_pending_numbers.clear()
	_presentation_buffers.clear()
	_refresh_base_summary()
	_capabilities = Compiler.capabilities(_base)
	_resolve_presentation()
	_clear_history()
	_variant_name.text = state.name
	_select_base(_base_id)
	_update_aircraft_description(Catalog.entry(_base_id))
	_sync_controls()
	_preview.set_aircraft(_base_id, _preview_scale())
	_set_page(state.page)
	if state.has("camera"): _preview.restore_view_state(state.camera)
	for key: String in state.numeric_buffers:
		_factor_inputs[key].text = state.numeric_buffers[key]
		_number_changed(state.numeric_buffers[key], key)
	for page: String in state.presentation_buffers:
		_page_nodes[page].restore_editor_state(state.presentation_buffers[page])
	_recovery_requires_copy = true
	_compile_recipe()
	_recovery_restoring = false
	_recovery_digest = str(fresh.digest)
	_recovery_pending = false
	_recovery_loaded.clear()
	_recovery_button.hide()
	_recovery_last.clear()
	set_note("Draft restored. Review the values and save a new build.")
	_schedule_recovery()


func _discard_pending_recovery() -> void:
	if not _discard_current_recovery(): return
	_recovery_pending = false
	_recovery_loaded.clear()
	_recovery_button.hide()
	_recovery_dialog.hide()
	_trial_button.disabled = not _edit_valid()
	_library_button.grab_focus()
	_schedule_recovery()


func _discard_current_recovery() -> bool:
	if not recovery_enabled: return true
	if _recovery_digest.is_empty():
		set_note("Recovery data cannot be safely replaced. Review the recovery files before retrying.")
		return false
	var result: Dictionary = load("res://workshop/draft_store.gd").discard_snapshot(recovery_root, _recovery_digest)
	if not result.ok:
		if result.get("conflict", false):
			_refresh_recovery_after_conflict()
			return false
		set_note("Recovered draft could not be discarded: " + _messages(result.errors, "Retry later."))
		return false
	_recovery_digest = "missing"
	if is_instance_valid(_recovery_timer): _recovery_timer.stop()
	_recovery_last.clear()
	return true


func _refresh_recovery_after_conflict() -> void:
	_recovery_loaded = load("res://workshop/draft_store.gd").load_snapshot(recovery_root)
	_recovery_digest = str(_recovery_loaded.get("digest", ""))
	_recovery_pending = bool(_recovery_loaded.get("exists", false))
	_recovery_button.visible = _recovery_pending
	_recovery_timer.stop()
	_recovery_last.clear()
	if is_instance_valid(_recovery_dialog): _recovery_dialog.hide()
	_trial_button.disabled = not _edit_valid()
	if _recovery_pending:
		set_note("Another session changed the recovered draft. Review it in Library before automatic recovery resumes.")
	else:
		set_note("Another session cleared the recovered draft. Automatic recovery will resume on your next edit.")
