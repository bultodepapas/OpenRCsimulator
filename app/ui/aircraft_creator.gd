extends Control
## Aircraft Creator wizard (AC-10): import a model, orient and size it, describe the aircraft and
## request a test flight.
##
## The screen only sends intents to the authoring document and shows its state: it never infers
## physics, assumes an axis, unit or datum, or scores readiness. The host composes this Control
## into the Workshop, routes Escape through `handle_back` and launches the flight on
## `test_fly_requested`. Text built here is translated with tr(); diagnostics are translated and
## formatted at this boundary.

signal close_requested
signal test_fly_requested(payload: Dictionary)

const Widgets := preload("res://ui/widgets.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const UiScale := preload("res://ui/ui_scale.gd")
const R := preload("res://workshop/creator/result.gd")
const Limits := preload("res://workshop/creator/limits.gd")
const Authoring := preload("res://workshop/creator/authoring.gd")
const Importer := preload("res://workshop/creator/source_importer.gd")
const InspectedSource := preload("res://workshop/creator/inspected_source.gd")
const VisualBuilder := preload("res://workshop/creator/visual_builder.gd")
const PreviewScript := preload("res://ui/aircraft_creator_preview.gd")

## Below this logical width the preview and the inspector take turns instead of sitting side by side.
const NARROW_WIDTH := 1100.0
const RAIL_WIDTH := 300.0
const INSPECTOR_WIDTH := 640.0
const INSPECTOR_WIDTH_COMPACT := 500.0
const NOT_AVAILABLE := "Not available yet"
const NOT_A_NUMBER := "\"%s\" is not a number."
const ENTER_A_NUMBER := "Enter a number."
const NO_MODEL := "No model imported yet"
const STATIC_VISUAL := "Controls simulated · visual is static"
const ELECTRIC_PACKAGE := "4S · 800 Kv · 12×6 propeller — estimated"
const AXIS_CHOICES: PackedStringArray = ["+x", "-x", "+y", "-y", "+z", "-z"]
const UNIT_CHOICES: PackedStringArray = ["mm", "cm", "m", "in", "ft"]
const DATUM_NAMES: PackedStringArray = ["Datum X", "Datum Y", "Datum Z"]
const FORMAT_NAMES := {"stl-binary": "STL (binary)", "stl-ascii": "STL (text)", "glb": "GLB"}
# "Estimated value" and "Upward" are deliberate: the shorter "Estimated" and "Up" already exist in the
# catalogs with other meanings (a price, a retracted gear) and would be translated wrongly here.
const KIND_CHOICES: Array[Array] = [["estimated", "Estimated value"], ["measured", "Measured"], ["manual", "Manual"]]
## Inventory numbers: key of `set_item_raw`, caption and unit.
const ITEM_NUMBERS: Array[Array] = [["mass", "Mass", "kg"], ["x", "Aft", "m"], ["y", "Right", "m"], ["z", "Upward", "m"]]
## Subjects for diagnostics that name a group of the definition instead of one field.
const GROUP_LABELS := {
	"wing": "Wing", "horizontal_tail": "Tailplane", "vertical_tail": "Fin", "fuselage": "Fuselage",
	"equipment": "Equipment positions", "controls": "Control travel", "battery": "Battery",
	"inventory": "Inventory", "horizontal_tail/position": "Tailplane position",
	"vertical_tail/position": "Fin position", "equipment/hub_position": "Propeller hub position",
	"equipment/battery_position": "Battery position", "equipment/esc_position": "Speed controller position",
	"equipment/thrust_angles_deg": "Thrust angles",
}
## Read-outs of the compiler summary: caption, summary key, unit, decimals and display factor.
const READOUTS := {
	"mass": ["Total mass", "mass_kg", "kg", 3, 1.0],
	"cg": ["Centre of gravity (aft, right, up)", "cg_m", "m", 3, 1.0],
	"neutral_point": ["Neutral point (aft)", "neutral_point_x_m", "m", 3, 1.0],
	"static_margin": ["Static margin (of the mean chord)", "static_margin", "%", 1, 100.0],
	"wing_loading": ["Wing loading", "wing_loading_kg_m2", "kg/m²", 2, 1.0],
	"wing_area": ["Wing area", "wing_area_m2", "m²", 3, 1.0],
	"level_speed": ["Level flight speed", "level_speed_mps", "m/s", 1, 1.0],
	"stall_speed": ["Stall speed", "stall_speed_mps", "m/s", 1, 1.0],
	"static_thrust": ["Static thrust", "static_thrust_n", "N", 1, 1.0],
	"thrust_to_weight": ["Thrust to weight", "thrust_to_weight", "", 2, 1.0],
}
const MARKER_COLORS := {
	"datum": Color(1.0, 0.86, 0.2), "cg": Color(1.0, 0.36, 0.3), "neutral_point": Color(0.35, 0.72, 1.0),
	"hub": Color(0.55, 1.0, 0.45), "tailplane": Color(0.9, 0.55, 1.0), "fin": Color(1.0, 0.65, 0.25),
}


## One model inspection handed to a worker thread. Data only: the worker never touches a node.
class ImportJob extends RefCounted:
	var path := ""
	var generation := 0
	var task_id := -1
	var result := {}


## Inspections whose wizard was closed before they finished. Kept alive until their task is released.
static var _abandoned_jobs: Array[ImportJob] = []

var _doc: Authoring
var _current := "import"
var _active := true
var _closing := false
var _refresh_queued := false
var _issues: Array = []
var _summary := {}
var _statuses := {}
var _known_labels := {}

# Shell.
var _name_edit: LineEdit
var _compact_bar: HBoxContainer
var _step_select: OptionButton
var _toggle_preview: Button
var _rail_scroll: ScrollContainer
var _rail_buttons := {}
var _preview: PreviewScript
var _inspector: PanelContainer
var _heading: Label
var _status_label: Label
var _scroll: ScrollContainer
var _pages := {}
var _reason_label: Label
var _note_panel: PanelContainer
var _note_label: Label
var _back_button: Button
var _continue_button: Button
var _test_fly_button: Button
var _file_dialog: FileDialog
var _confirm: ConfirmationDialog
var _confirm_text: Label
var _confirm_action := Callable()
var _compact := false
var _narrow := false
var _show_preview := false
var _cards: Array[Button] = []
var _field_edits := {}
var _field_errors := {}
var _readouts: Array[Dictionary] = []

# Import.
var _choose_button: Button
var _import_status: Label
var _import_details: Label
var _import_notes: VBoxContainer
var _import_errors: VBoxContainer
var _import_state := "idle"
var _import_file_name := ""
var _import_diagnostics: Array = []
var _import_generation := 0
var _discarded_imports := 0
var _job: ImportJob
var _shown_source: InspectedSource
var _preview_signature := ""
var _preview_placed := false

# Orient and size.
var _orient_missing: VBoxContainer
var _orient_controls: VBoxContainer
var _unplaced_hint: Label
var _nose_axis: OptionButton
var _up_axis: OptionButton
var _units: OptionButton
var _wingspan_edit: LineEdit
var _wingspan_error_label: Label
var _wingspan_text := ""
var _wingspan_problem := ""
var _scale_readout: Label
var _datum_edits: Array[LineEdit] = []
var _datum_texts: Array[String] = ["", "", ""]
var _datum_invalid: Array[bool] = [false, false, false]
var _datum_error: Label
var _pick_button: Button
var _pick_hint: Label
var _real_size: Label
var _orient_todo: Label

# Aircraft layout, weight and balance, review.
var _starting_button: Button
var _layout_model_note: Label
var _propose_button: Button
var _add_item_button: Button
var _inventory_note: Label
var _inventory_box: VBoxContainer
var _inventory_signature := "-"
var _item_rows := {}
var _item_texts := {}
var _item_invalid := {}
var _rebuilding_items := false
var _review_sections := {}
var _issue_box: VBoxContainer
var _issue_signature := "-"
var _start_choice := "airborne"


func _init() -> void:
	name = "AircraftCreator"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for entry: Dictionary in Authoring.FIELDS:
		_known_labels[str(entry.label)] = true
	for label: String in DATUM_NAMES:
		_known_labels[label] = true
	_known_labels["Known wingspan (m)"] = true
	_doc = Authoring.new()
	_doc.changed.connect(_schedule_refresh)
	_build()
	_show_step(_current)


func _ready() -> void:
	resized.connect(_apply_layout)
	visibility_changed.connect(_update_preview_active)
	reap_abandoned_imports()
	_apply_layout()
	_refresh()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			# A running inspection finishes on its own; its result is never adopted.
			_closing = true
			_import_generation += 1
			if _job != null:
				_abandoned_jobs.append(_job)
				_job = null
		NOTIFICATION_TRANSLATION_CHANGED, NOTIFICATION_THEME_CHANGED:
			if _scroll != null and not _closing:
				for card: Button in _cards:
					_update_card_text(card)
				_schedule_refresh()
				if what == NOTIFICATION_THEME_CHANGED:
					_apply_layout.call_deferred()


func _process(_delta: float) -> void:
	if _job == null:
		set_process(false)
		return
	if not WorkerThreadPool.is_task_completed(_job.task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_job.task_id)
	var job := _job
	_job = null
	set_process(false)
	_adopt_import(job)


# --- Public interface -----------------------------------------------------------------------

## Status or refusal reason from the host, already translated. Shown beside Test fly.
func set_note(text: String) -> void:
	_note_label.text = text
	_note_panel.visible = not text.strip_edges().is_empty()


## True once a model is imported, a value is set or the aircraft is named.
func has_unsaved_changes() -> bool:
	return _doc.revision > 0 or not _doc.name.is_empty() or _import_state == "inspecting"


## Hides an open file dialog or confirmation. True when something was dismissed.
func dismiss_modal_for_exit() -> bool:
	var dismissed := false
	if _file_dialog.visible:
		_file_dialog.hide()
		dismissed = true
	if _confirm.visible:
		_confirm.hide()
		_confirm_action = Callable()
		dismissed = true
	for picker: OptionButton in _option_buttons():
		if picker.get_popup().visible:
			picker.get_popup().hide()
			dismissed = true
	return dismissed


## Escape/Back from the host: closes the top popup, cancels an edit or a datum pick, or goes to the
## previous step. False on the first step with nothing open: the host then asks to close.
func handle_back() -> bool:
	if dismiss_modal_for_exit():
		return true
	var focused := _focused_edit()
	if focused != null and _restore_edit(focused):
		return true
	if _pick_button.button_pressed:
		_pick_button.button_pressed = false
		return true
	var index := Authoring.STEPS.find(_current)
	if index > 0:
		go_to_step(Authoring.STEPS[index - 1])
		focus_default.call_deferred()
		return true
	return false


## Focuses the first sensible control of the current step.
func focus_default() -> void:
	if _narrow and _show_preview:
		_set_show_preview(false)
	_focus_control(_default_focus(_current))


## The authoring document of this session.
func document() -> RefCounted:
	return _doc


func go_to_step(step_id: String) -> void:
	if not Authoring.STEPS.has(step_id):
		return
	_commit_focused_edit()
	if step_id != "orient_size" and _pick_button.button_pressed:
		_pick_button.button_pressed = false
	_show_step(step_id)
	_refresh()


func current_step() -> String:
	return _current


## The host clears this while another screen covers the wizard: the preview then ignores the pointer.
func set_active(active: bool) -> void:
	_active = active
	_update_preview_active()


func preview() -> Control:
	return _preview


## Starts importing a chosen file: what the file dialog calls. Replacing a model asks first.
func request_import(path: String) -> void:
	if _doc.source() == null:
		_start_import(path)
		return
	# Deferred: the file dialog that reported the path is still closing.
	_ask.call_deferred(tr("Replace the model?"),
		tr("Importing \"%s\" replaces the current model and resets its orientation, units and datum. The values entered for the aircraft are kept.") % path.get_file(),
		tr("Replace model"), _start_import.bind(path))


## State of the import for tests and the debug bridge: idle, inspecting, imported or failed.
func import_state() -> Dictionary:
	return {state = _import_state, file_name = _import_file_name, generation = _import_generation,
		discarded = _discarded_imports}


## Releases finished inspections whose wizard was closed meanwhile. Returns how many still run.
static func reap_abandoned_imports() -> int:
	var running: Array[ImportJob] = []
	for job: ImportJob in _abandoned_jobs:
		if WorkerThreadPool.is_task_completed(job.task_id):
			WorkerThreadPool.wait_for_task_completion(job.task_id)
		else:
			running.append(job)
	_abandoned_jobs = running
	return running.size()


# --- Import ---------------------------------------------------------------------------------

## Worker-thread body. Static and node-free: closing the wizard cannot invalidate it.
static func _inspect(job: ImportJob) -> void:
	var captured: Dictionary = Importer.read_bounded(job.path)
	if captured.ok:
		captured = Importer.inspect_bytes(captured.value, job.path.get_file())
	job.result = captured


static func _start_task(job: ImportJob) -> int:
	# The lambda holds the job, not a wizard: the job outlives a closed screen.
	return WorkerThreadPool.add_task(func() -> void: _inspect(job), false, "Aircraft Creator model inspection")


func _start_import(path: String) -> void:
	if _job != null:
		# A newer selection wins: the running inspection is left to finish and its result is dropped.
		_abandoned_jobs.append(_job)
		_job = null
		_discarded_imports += 1
	_import_generation += 1
	var job := ImportJob.new()
	job.path = path
	job.generation = _import_generation
	job.task_id = _start_task(job)
	_job = job
	_import_state = "inspecting"
	_import_file_name = path.get_file()
	_import_diagnostics = []
	set_process(true)
	_refresh()


func _adopt_import(job: ImportJob) -> void:
	reap_abandoned_imports()
	if _closing or job.generation != _import_generation:
		_discarded_imports += 1
		return
	var result: Dictionary = job.result
	if result.get("ok", false) and result.get("value") is InspectedSource:
		_import_state = "imported"
		_import_diagnostics = []
		_doc.set_source(result.value)
	else:
		_import_state = "failed"
		_import_diagnostics = result.get("diagnostics", [])
	_refresh()


func _choose_model() -> void:
	if not is_inside_tree():
		return
	_file_dialog.title = tr("Choose a model")
	# Filter captions are plain text to the dialog: translate them each time it opens.
	var filters := PackedStringArray()
	for filter: String in PackedStringArray(["*.stl, *.glb ; 3D model"]) + Importer.FILE_FILTERS:
		var parts := filter.split(";", true, 1)
		if parts.size() == 2:
			filters.append("%s ; %s" % [parts[0].strip_edges(), tr(parts[1].strip_edges())])
		else:
			filters.append(filter)
	_file_dialog.filters = filters
	_file_dialog.current_file = ""
	_file_dialog.popup_centered_clamped(Vector2i(900, 600), 0.9)
	_update_preview_active()


# --- Construction ---------------------------------------------------------------------------

func _build() -> void:
	var background := PanelContainer.new()
	background.name = "CreatorBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(UiTheme.PANEL, 1.0)
	fill.content_margin_left = 24
	fill.content_margin_right = 24
	fill.content_margin_top = 16
	fill.content_margin_bottom = 16
	background.add_theme_stylebox_override("panel", fill)
	add_child(background)

	var column := VBoxContainer.new()
	column.name = "CreatorLayout"
	column.add_theme_constant_override("separation", 12)
	background.add_child(column)

	_build_header(column)
	_build_compact_bar(column)

	var body := HBoxContainer.new()
	body.name = "CreatorBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	column.add_child(body)
	_build_rail(body)
	_preview = PreviewScript.new()
	_preview.point_picked.connect(_on_point_picked)
	body.add_child(_preview)
	_build_inspector(body)

	_build_footer(column)
	_build_dialogs()


func _build_header(parent: Container) -> void:
	var header := HFlowContainer.new()
	header.name = "CreatorHeader"
	header.add_theme_constant_override("h_separation", 16)
	header.add_theme_constant_override("v_separation", 8)
	parent.add_child(header)
	var back := _button("Back to Workshop", "", "BackToWorkshop")
	back.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(back)
	var title := Widgets.label("Create aircraft", "TitleLabel")
	title.name = "CreatorTitle"
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	_name_edit = LineEdit.new()
	_name_edit.name = "AircraftName"
	_name_edit.placeholder_text = "Aircraft name"
	_name_edit.accessibility_name = tr("Aircraft name")
	_name_edit.max_length = Limits.NAME_CHARACTERS
	_name_edit.custom_minimum_size.x = 280
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_changed.connect(func(text: String) -> void: _doc.name = text.strip_edges())
	header.add_child(_name_edit)
	var badge := PanelContainer.new()
	badge.name = "ExperimentalBadge"
	badge.theme_type_variation = "Badge"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.add_child(Widgets.label("Experimental · estimated", "SecondaryLabel"))
	header.add_child(badge)


func _build_compact_bar(parent: Container) -> void:
	_compact_bar = HBoxContainer.new()
	_compact_bar.name = "CompactBar"
	_compact_bar.add_theme_constant_override("separation", 12)
	_compact_bar.visible = false
	parent.add_child(_compact_bar)
	_step_select = OptionButton.new()
	_step_select.name = "StepSelect"
	_step_select.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_step_select.accessibility_name = tr("Step")
	_step_select.fit_to_longest_item = false
	_step_select.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_step_select.custom_minimum_size.x = 200
	_step_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for step: String in Authoring.STEPS:
		_step_select.add_item(str(Authoring.STEP_TITLES[step]))
	_step_select.item_selected.connect(func(index: int) -> void: go_to_step(Authoring.STEPS[index]))
	Widgets.fit_option_popup(_step_select)
	_compact_bar.add_child(_step_select)
	_toggle_preview = _button("Show preview", "", "TogglePreview")
	_toggle_preview.pressed.connect(func() -> void: _set_show_preview(not _show_preview))
	_toggle_preview.visible = false
	_compact_bar.add_child(_toggle_preview)


func _build_rail(parent: Container) -> void:
	_rail_scroll = ScrollContainer.new()
	_rail_scroll.name = "StepRail"
	_rail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rail_scroll.follow_focus = true
	_rail_scroll.custom_minimum_size.x = RAIL_WIDTH
	parent.add_child(_rail_scroll)
	var rail := VBoxContainer.new()
	rail.name = "StepButtons"
	rail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rail.add_theme_constant_override("separation", 8)
	_rail_scroll.add_child(rail)
	var group := ButtonGroup.new()
	for step: String in Authoring.STEPS:
		var entry := _button("", "", "Step" + step.to_pascal_case())
		entry.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		entry.toggle_mode = true
		entry.button_group = group
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry.pressed.connect(go_to_step.bind(step))
		rail.add_child(entry)
		_rail_buttons[step] = entry


func _build_inspector(parent: Container) -> void:
	_inspector = PanelContainer.new()
	_inspector.name = "Inspector"
	_inspector.theme_type_variation = "Card"
	_inspector.custom_minimum_size.x = INSPECTOR_WIDTH
	parent.add_child(_inspector)
	var column := VBoxContainer.new()
	column.name = "InspectorLayout"
	column.add_theme_constant_override("separation", 8)
	_inspector.add_child(column)
	_heading = Widgets.label("", "CardTitle", true, false)
	_heading.name = "StepHeading"
	column.add_child(_heading)
	_status_label = Widgets.label("", "SecondaryLabel", true, false)
	_status_label.name = "StepStatus"
	column.add_child(_status_label)
	_scroll = ScrollContainer.new()
	_scroll.name = "InspectorScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_scroll)
	var pages := VBoxContainer.new()
	pages.name = "StepPages"
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
	for step: String in Authoring.STEPS:
		var page := VBoxContainer.new()
		page.name = "Page" + step.to_pascal_case()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation", 12)
		page.visible = false
		pages.add_child(page)
		_pages[step] = page
	_build_import_page(_pages["import"])
	_build_orient_page(_pages["orient_size"])
	_build_layout_page(_pages["aircraft_layout"])
	_build_weight_page(_pages["weight_balance"])
	_build_power_page(_pages["power_mount"])
	_build_controls_page(_pages["controls_ground"])
	_build_paint_page(_pages["paint_skins"])
	_build_review_page(_pages["review_test"])


func _build_footer(parent: Container) -> void:
	var footer := HBoxContainer.new()
	footer.name = "CreatorFooter"
	footer.add_theme_constant_override("separation", 12)
	parent.add_child(footer)
	var messages := VBoxContainer.new()
	messages.name = "FooterMessages"
	messages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	messages.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	footer.add_child(messages)
	_note_panel = PanelContainer.new()
	_note_panel.name = "CreatorNotePanel"
	_note_panel.theme_type_variation = "Notice"
	_note_panel.visible = false
	messages.add_child(_note_panel)
	_note_label = Widgets.label("", "", true, false)
	_note_label.name = "CreatorNote"
	_note_panel.add_child(_note_label)
	_reason_label = Widgets.label("", "SecondaryLabel", true, false)
	_reason_label.name = "TestFlyReason"
	_reason_label.visible = false
	messages.add_child(_reason_label)
	_back_button = _button("Back", "", "StepBack")
	_back_button.size_flags_vertical = Control.SIZE_SHRINK_END
	_back_button.pressed.connect(_step_by.bind(-1))
	footer.add_child(_back_button)
	_continue_button = _button("Continue", "PrimaryButton", "StepContinue")
	_continue_button.size_flags_vertical = Control.SIZE_SHRINK_END
	_continue_button.pressed.connect(_step_by.bind(1))
	footer.add_child(_continue_button)
	_test_fly_button = _button("Test fly", "PrimaryButton", "TestFly")
	_test_fly_button.size_flags_vertical = Control.SIZE_SHRINK_END
	_test_fly_button.pressed.connect(_on_test_fly_pressed)
	_test_fly_button.visible = false
	footer.add_child(_test_fly_button)


func _build_dialogs() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.name = "ModelFileDialog"
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = false
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.filters = Importer.FILE_FILTERS
	_file_dialog.file_selected.connect(request_import)
	_file_dialog.visibility_changed.connect(_update_preview_active)
	add_child(_file_dialog)

	_confirm = ConfirmationDialog.new()
	_confirm.name = "CreatorConfirm"
	_confirm.confirmed.connect(_on_confirmed)
	_confirm.canceled.connect(func() -> void: _confirm_action = Callable())
	_confirm.visibility_changed.connect(_update_preview_active)
	var scroll := ScrollContainer.new()
	scroll.name = "ConfirmScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(420, 180)
	_confirm.add_child(scroll)
	_confirm_text = Widgets.label("", "", true, false)
	_confirm_text.name = "ConfirmText"
	_confirm_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_confirm_text)
	add_child(_confirm)


func _build_import_page(page: VBoxContainer) -> void:
	page.add_child(_label("Choose an STL file or a self-contained GLB file. A picture is not a 3D model."))
	_choose_button = _button("Choose model…", "PrimaryButton", "ChooseModel")
	_choose_button.pressed.connect(_choose_model)
	page.add_child(_choose_button)
	_import_status = _label("", "", false)
	_import_status.name = "ImportStatus"
	page.add_child(_import_status)
	_import_errors = VBoxContainer.new()
	_import_errors.name = "ImportErrors"
	page.add_child(_import_errors)
	_import_details = _label("", "SecondaryLabel", false)
	_import_details.name = "ImportDetails"
	page.add_child(_import_details)
	_import_notes = VBoxContainer.new()
	_import_notes.name = "ImportNotes"
	page.add_child(_import_notes)


func _build_orient_page(page: VBoxContainer) -> void:
	_orient_missing = VBoxContainer.new()
	_orient_missing.name = "OrientNoModel"
	_orient_missing.add_theme_constant_override("separation", 12)
	page.add_child(_orient_missing)
	_orient_missing.add_child(_label("Import a model first", ""))
	var go := _button("Go to Import", "", "GoToImport")
	go.pressed.connect(_go_and_focus.bind("import"))
	_orient_missing.add_child(go)

	_orient_controls = VBoxContainer.new()
	_orient_controls.name = "OrientControls"
	_orient_controls.add_theme_constant_override("separation", 12)
	page.add_child(_orient_controls)
	var box := _orient_controls
	box.add_child(_label("Say how the model sits in its file. Nothing is assumed."))
	_unplaced_hint = _label("Until the placement is complete, the preview shows the model in the file's own axes.")
	_unplaced_hint.name = "UnplacedHint"
	box.add_child(_unplaced_hint)
	_nose_axis = _add_axis_row(box, "NoseAxis", "Model axis pointing to the nose", "nose_axis")
	_up_axis = _add_axis_row(box, "UpAxis", "Model axis pointing up", "up_axis")

	var unit_row := _row(box, "UnitsRow")
	unit_row.add_child(_label("Model units"))
	_units = OptionButton.new()
	_units.name = "Units"
	_units.add_item("Choose units")
	_units.set_item_metadata(0, "")
	for unit: String in UNIT_CHOICES:
		_units.add_item(unit)
		_units.set_item_metadata(_units.item_count - 1, unit)
		_units.set_item_auto_translate_mode(_units.item_count - 1, Node.AUTO_TRANSLATE_MODE_DISABLED)
	_units.item_selected.connect(_on_units_selected)
	Widgets.fit_option_popup(_units)
	unit_row.add_child(_units)

	box.add_child(_label("If the units are unknown, enter the real wingspan instead."))
	var span_row := _row(box, "KnownWingspanRow")
	span_row.add_child(_label("Known wingspan (m)"))
	_wingspan_edit = _number_edit("KnownWingspan", _commit_wingspan)
	span_row.add_child(_wingspan_edit)
	_wingspan_error_label = _label("", "ErrorLabel", false)
	_wingspan_error_label.name = "KnownWingspanError"
	_wingspan_error_label.visible = false
	box.add_child(_wingspan_error_label)
	_scale_readout = _label("", "SecondaryLabel", false)
	_scale_readout.name = "ScaleReadout"
	box.add_child(_scale_readout)

	box.add_child(Widgets.label("Datum: wing leading edge on the centreline", "SectionLabel", true))
	box.add_child(_label("Type the point in the model's own coordinates, or pick it on the preview."))
	var datum_row := HFlowContainer.new()
	datum_row.name = "DatumRow"
	datum_row.add_theme_constant_override("h_separation", 12)
	datum_row.add_theme_constant_override("v_separation", 8)
	box.add_child(datum_row)
	for axis: int in 3:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 6)
		datum_row.add_child(cell)
		cell.add_child(Widgets.label(["X", "Y", "Z"][axis], "SecondaryLabel", false, false))
		var edit := _number_edit(["DatumX", "DatumY", "DatumZ"][axis], _commit_datum)
		edit.accessibility_name = tr(DATUM_NAMES[axis])
		edit.custom_minimum_size.x = 120
		cell.add_child(edit)
		_datum_edits.append(edit)
	_datum_error = _label(ENTER_A_NUMBER, "ErrorLabel")
	_datum_error.name = "DatumError"
	_datum_error.visible = false
	box.add_child(_datum_error)
	_pick_button = _button("Pick on the preview", "", "PickDatum")
	_pick_button.toggle_mode = true
	_pick_button.toggled.connect(_on_pick_toggled)
	box.add_child(_pick_button)
	_pick_hint = _label("Click the wing leading edge at the centreline on the preview.")
	_pick_hint.name = "PickHint"
	_pick_hint.visible = false
	box.add_child(_pick_hint)

	box.add_child(Widgets.label("Real size", "SectionLabel", true))
	_real_size = _label("", "", false)
	_real_size.name = "RealSize"
	box.add_child(_real_size)
	_orient_todo = _label("", "SecondaryLabel", false)
	_orient_todo.name = "OrientTodo"
	box.add_child(_orient_todo)


func _build_layout_page(page: VBoxContainer) -> void:
	var grid := _card_grid(page, "LayoutCards", 2)
	var group := ButtonGroup.new()
	_add_card(grid, "LayoutConventional", "Conventional", "", group, true)
	_add_card(grid, "LayoutFlyingWing", "Flying wing", "", group, false, NOT_AVAILABLE)
	_add_card(grid, "LayoutCanard", "Canard", "", group, false, NOT_AVAILABLE)
	_add_card(grid, "LayoutVTail", "V-tail", "", group, false, NOT_AVAILABLE)
	_starting_button = _button("Use starting values…", "", "UseStartingValues")
	_starting_button.pressed.connect(_ask_starting_values)
	page.add_child(_starting_button)
	page.add_child(_label("Estimated starting values — correct them with your measurements."))
	_layout_model_note = _label("Flight dimensions are entered here; they do not reshape the visual model.")
	_layout_model_note.name = "LayoutModelNote"
	_layout_model_note.visible = false
	page.add_child(_layout_model_note)
	page.add_child(_label("Distances are in metres from the wing leading edge on the centreline."))
	_add_fields(page, "aircraft_layout")


func _build_weight_page(page: VBoxContainer) -> void:
	var notice := PanelContainer.new()
	notice.name = "PowerHardwareNotice"
	notice.theme_type_variation = "Notice"
	notice.add_child(_label("Power package hardware is added automatically"))
	page.add_child(notice)
	page.add_child(_label("The motor, propeller, speed controller and battery are not listed here. List everything else the airplane carries."))
	var actions := HFlowContainer.new()
	actions.name = "InventoryActions"
	actions.add_theme_constant_override("h_separation", 12)
	actions.add_theme_constant_override("v_separation", 8)
	page.add_child(actions)
	_propose_button = _button("Propose airframe items", "", "ProposeAirframe")
	_propose_button.pressed.connect(_on_propose_pressed)
	actions.add_child(_propose_button)
	_add_item_button = _button("Add item", "", "AddItem")
	_add_item_button.pressed.connect(_on_add_item_pressed)
	actions.add_child(_add_item_button)
	page.add_child(_label("Propose replaces items marked Estimated. Mark an item Measured or Manual to keep your values."))
	_inventory_note = _label("", "SecondaryLabel", false)
	_inventory_note.name = "InventoryNote"
	_inventory_note.visible = false
	page.add_child(_inventory_note)
	page.add_child(Widgets.label("Inventory", "SectionLabel", true))
	_inventory_box = VBoxContainer.new()
	_inventory_box.name = "InventoryList"
	_inventory_box.add_theme_constant_override("separation", 12)
	page.add_child(_inventory_box)
	page.add_child(Widgets.label("Battery position", "SectionLabel", true))
	_add_fields(page, "weight_balance")
	_add_readouts(page, "WeightReadout", ["mass", "cg", "neutral_point", "static_margin", "wing_loading"])


func _build_power_page(page: VBoxContainer) -> void:
	var cards := _card_grid(page, "PowerCards", 1)
	var group := ButtonGroup.new()
	_add_card(cards, "PowerElectric", "Electric", ELECTRIC_PACKAGE, group, true)
	_add_card(cards, "PowerGasoline", "Gasoline", "", group, false, NOT_AVAILABLE)
	_add_card(cards, "PowerGlow", "Glow", "", group, false, NOT_AVAILABLE)
	_add_fields(page, "power_mount")
	_add_readouts(page, "PowerReadout", ["static_thrust", "thrust_to_weight"])


func _build_controls_page(page: VBoxContainer) -> void:
	_add_fields(page, "controls_ground")
	var notice := PanelContainer.new()
	notice.name = "StaticVisualNotice"
	notice.theme_type_variation = "Notice"
	notice.add_child(_label(STATIC_VISUAL))
	page.add_child(notice)
	page.add_child(Widgets.label("Landing gear", "SectionLabel", true))
	var grid := _card_grid(page, "GearCards", 2)
	var group := ButtonGroup.new()
	_add_card(grid, "GearNone", "No gear", "", group, true)
	_add_card(grid, "GearTricycle", "Fixed tricycle", "", group, false, NOT_AVAILABLE)
	_add_card(grid, "GearTaildragger", "Taildragger", "", group, false, NOT_AVAILABLE)
	_add_card(grid, "GearRetractable", "Retractable", "", group, false, NOT_AVAILABLE)


func _build_paint_page(page: VBoxContainer) -> void:
	var grid := _card_grid(page, "PaintCards", 2)
	var group := ButtonGroup.new()
	_add_card(grid, "PaintOriginal", "Original", "The model's own colours", group, true)
	_add_card(grid, "PaintGenerate", "Generate paint", "", group, false, NOT_AVAILABLE)
	_add_card(grid, "PaintUpload", "Upload image", "", group, false, NOT_AVAILABLE)
	_add_card(grid, "PaintImportSkin", "Import skin", "", group, false, NOT_AVAILABLE)


func _build_review_page(page: VBoxContainer) -> void:
	var notice := PanelContainer.new()
	notice.name = "EstimateNotice"
	notice.theme_type_variation = "Notice"
	notice.add_child(_label("Estimated aircraft — not a measurement of a real airplane."))
	page.add_child(notice)
	page.add_child(Widgets.label("Issues", "SectionLabel", true))
	_issue_box = VBoxContainer.new()
	_issue_box.name = "IssueList"
	_issue_box.add_theme_constant_override("separation", 8)
	page.add_child(_issue_box)
	page.add_child(Widgets.label("Start", "SectionLabel", true))
	var grid := _card_grid(page, "StartCards", 2)
	var group := ButtonGroup.new()
	_add_card(grid, "StartAirborne", "Airborne", "", group, true).set_meta("choice", "airborne")
	_add_card(grid, "StartHandLaunch", "Hand launch", "", group, false).set_meta("choice", "hand_launch")
	_add_card(grid, "StartRunway", "Runway", "", group, false, "Needs landing gear")
	group.pressed.connect(func(card: BaseButton) -> void: _start_choice = str(card.get_meta("choice", "airborne")))
	page.add_child(Widgets.label("Summary", "SectionLabel", true))
	var sections := VBoxContainer.new()
	sections.name = "ReviewSections"
	sections.add_theme_constant_override("separation", 8)
	page.add_child(sections)
	for step: String in Authoring.STEPS:
		if step == "review_test":
			continue
		var line := _label("", "SecondaryLabel", false)
		line.name = "Review" + step.to_pascal_case()
		sections.add_child(line)
		_review_sections[step] = line
	_add_readouts(page, "ReviewReadout", ["mass", "cg", "neutral_point", "static_margin", "wing_area", "wing_loading",
		"level_speed", "stall_speed", "static_thrust", "thrust_to_weight"])


# --- Builders -------------------------------------------------------------------------------

## A wrapped label that takes the row's remaining width.
func _label(text: String, variation := "SecondaryLabel", translate := true) -> Label:
	var control := Widgets.label(text, variation, true, translate)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.x = 110
	return control


func _button(text: String, variation := "", node_name := "") -> Button:
	return Widgets.button(text, variation, node_name)


func _row(parent: Container, node_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = node_name
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	return row


func _card_grid(parent: Container, node_name: String, columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.name = node_name
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	return grid


## A choice card. With a `reason` it is disabled and shows that reason as its second line.
func _add_card(parent: Container, node_name: String, title: String, detail: String, group: ButtonGroup,
		selected: bool, reason := "") -> Button:
	var card := _button("", "", node_name)
	card.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	card.toggle_mode = true
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.custom_minimum_size.x = 150
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.set_meta("title", title)
	card.set_meta("detail", detail)
	card.set_meta("reason", reason)
	if reason.is_empty():
		card.button_group = group
		card.set_pressed_no_signal(selected)
		card.toggled.connect(func(_pressed: bool) -> void: _update_card_text(card))
	else:
		card.disabled = true
		card.tooltip_text = reason
	_cards.append(card)
	_update_card_text(card)
	parent.add_child(card)
	return card


## The state is text, never colour alone: "Selected" or the reason a card is unavailable.
func _update_card_text(card: Button) -> void:
	var lines := PackedStringArray([tr(str(card.get_meta("title")))])
	var detail := str(card.get_meta("detail"))
	if not detail.is_empty():
		lines.append(tr(detail))
	var reason := str(card.get_meta("reason"))
	if not reason.is_empty():
		lines.append(tr(reason))
	elif card.button_pressed:
		lines.append(tr("Selected"))
	card.text = "\n".join(lines)


func _add_axis_row(parent: Container, node_name: String, caption: String, which: String) -> OptionButton:
	var row := _row(parent, node_name + "Row")
	row.add_child(_label(caption))
	var picker := OptionButton.new()
	picker.name = node_name
	picker.add_item("Choose…")
	picker.set_item_metadata(0, "")
	for axis: String in AXIS_CHOICES:
		picker.add_item(axis.to_upper())
		picker.set_item_metadata(picker.item_count - 1, axis)
		picker.set_item_auto_translate_mode(picker.item_count - 1, Node.AUTO_TRANSLATE_MODE_DISABLED)
	picker.item_selected.connect(_on_axis_selected.bind(picker, which))
	Widgets.fit_option_popup(picker)
	row.add_child(picker)
	return picker


## A LineEdit that commits on Enter and on focus loss and restores its text on Escape.
func _number_edit(node_name: String, commit: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = node_name
	edit.custom_minimum_size.x = 140
	edit.placeholder_text = "Not set"
	edit.set_meta("commit", commit)
	edit.set_meta("origin", "")
	edit.set_meta("typed", false)
	edit.focus_entered.connect(func() -> void:
		if not bool(edit.get_meta("typed")):
			edit.set_meta("origin", edit.text))
	edit.text_changed.connect(func(_text: String) -> void: edit.set_meta("typed", true))
	edit.text_submitted.connect(func(_text: String) -> void: _commit_edit(edit))
	edit.focus_exited.connect(_commit_edit.bind(edit))
	edit.gui_input.connect(_on_edit_gui_input.bind(edit))
	return edit


func _add_fields(parent: Container, step: String) -> void:
	for entry: Dictionary in Authoring.fields_for(step):
		var path := str(entry.path)
		var holder := VBoxContainer.new()
		holder.name = "Row" + _pascal(path)
		holder.add_theme_constant_override("separation", 2)
		parent.add_child(holder)
		var row := _row(holder, "Line")
		row.add_child(_label(str(entry.label)))
		var edit := _number_edit("Field" + _pascal(path), _commit_field.bind(path))
		row.add_child(edit)
		var unit := Widgets.label(str(entry.unit), "SecondaryLabel", false, false)
		unit.custom_minimum_size.x = 44
		row.add_child(unit)
		var error := _label("", "ErrorLabel", false)
		error.name = edit.name + "Error"
		error.visible = false
		holder.add_child(error)
		_field_edits[path] = edit
		_field_errors[path] = error


## A two-column read-out of compiler estimates. Absent values show a dash.
func _add_readouts(parent: Container, node_name: String, ids: Array) -> void:
	parent.add_child(Widgets.label("Estimated read-out", "SectionLabel", true))
	var grid := GridContainer.new()
	grid.name = node_name
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	for id: String in ids:
		var spec: Array = READOUTS[id]
		grid.add_child(_label(str(spec[0])))
		var value := Widgets.label("—", "", false, false)
		value.name = "Readout" + id.to_pascal_case()
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
		_readouts.append({label = value, spec = spec})


static func _pascal(path: String) -> String:
	return path.replace("/", "_").to_pascal_case()


# --- Navigation and layout ------------------------------------------------------------------

func _show_step(step: String) -> void:
	_current = step
	for id: String in _pages:
		(_pages[id] as Control).visible = id == step
	for id: String in _rail_buttons:
		(_rail_buttons[id] as Button).set_pressed_no_signal(id == step)
	var index := Authoring.STEPS.find(step)
	_step_select.selected = index
	_back_button.visible = index > 0
	_continue_button.visible = index < Authoring.STEPS.size() - 1
	_test_fly_button.visible = index == Authoring.STEPS.size() - 1
	_scroll.scroll_vertical = 0


func _step_by(offset: int) -> void:
	var index := clampi(Authoring.STEPS.find(_current) + offset, 0, Authoring.STEPS.size() - 1)
	_go_and_focus(Authoring.STEPS[index])


func _go_and_focus(step: String) -> void:
	go_to_step(step)
	focus_default.call_deferred()


func _apply_layout() -> void:
	if _scroll == null or size.x <= 0.0 or size.y <= 0.0:
		return
	_compact = UiTheme.compact_layout or size.x < UiScale.COMPACT_WIDTH or size.y < UiScale.COMPACT_HEIGHT
	_narrow = size.x < NARROW_WIDTH
	_rail_scroll.visible = not _compact
	_compact_bar.visible = _compact
	_toggle_preview.visible = _narrow
	_toggle_preview.text = "Show details" if _show_preview else "Show preview"
	_preview.visible = not _narrow or _show_preview
	_inspector.visible = not _narrow or not _show_preview
	if _narrow:
		_inspector.custom_minimum_size.x = 0.0
		_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		_inspector.custom_minimum_size.x = INSPECTOR_WIDTH_COMPACT if _compact else INSPECTOR_WIDTH
		_inspector.size_flags_horizontal = Control.SIZE_FILL
	_update_preview_active()


func _set_show_preview(show_preview: bool) -> void:
	_show_preview = show_preview
	_apply_layout()


func _update_preview_active() -> void:
	if _preview == null or _file_dialog == null or _confirm == null:
		return
	_preview.set_active(_active and is_visible_in_tree() and not _file_dialog.visible and not _confirm.visible)


func _default_focus(step: String) -> Control:
	match step:
		"import":
			return _choose_button
		"orient_size":
			return _nose_axis if _doc.source() != null else _orient_missing.get_node("GoToImport") as Control
		"aircraft_layout":
			return _starting_button
		"weight_balance":
			return _propose_button
		"paint_skins":
			return _pages[step].find_child("PaintOriginal", true, false) as Control
		"review_test":
			if not _test_fly_button.disabled:
				return _test_fly_button
			if _issue_box.get_child_count() > 0 and _issue_box.get_child(0) is Button:
				return _issue_box.get_child(0) as Control
			return _pages[step].find_child("StartAirborne", true, false) as Control
	var owned: Array[Dictionary] = Authoring.fields_for(step)
	return _field_edits.get(str(owned[0].path)) as Control if not owned.is_empty() else null


func _focus_control(target: Control) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree() or not target.is_visible_in_tree():
		return
	target.grab_focus()
	if _scroll.is_ancestor_of(target):
		_scroll.ensure_control_visible(target)


func _option_buttons() -> Array[OptionButton]:
	var found: Array[OptionButton] = [_step_select, _nose_axis, _up_axis, _units]
	for id: String in _item_rows:
		found.append(_item_rows[id].kind as OptionButton)
	return found


# --- Dialogs --------------------------------------------------------------------------------

func _ask(title: String, text: String, confirm_text: String, action: Callable) -> void:
	if _closing or not is_inside_tree():
		return
	_confirm.title = title
	_confirm.ok_button_text = confirm_text
	_confirm_text.text = text
	_confirm_action = action
	_confirm.popup_centered_clamped(Vector2i(720, 520), 0.9)
	_update_preview_active()


func _on_confirmed() -> void:
	var action := _confirm_action
	_confirm_action = Callable()
	if action.is_valid():
		action.call()


func _ask_starting_values() -> void:
	var values: Dictionary = _doc.starting_values()
	var lines := PackedStringArray([tr("These estimated values replace the current ones:"), ""])
	for entry: Dictionary in Authoring.FIELDS:
		if values.has(entry.path):
			lines.append("%s: %s %s" % [tr(str(entry.label)), Authoring.format_number(float(values[entry.path])), str(entry.unit)])
	# Marked as estimates: until the player types a value, the record does not call it theirs.
	_ask(tr("Use starting values?"), "\n".join(lines), tr("Use starting values"), _doc.apply_values.bind(values, true))


# --- Committing edits -----------------------------------------------------------------------

func _commit_edit(edit: LineEdit) -> void:
	if _closing or _rebuilding_items or not is_instance_valid(edit) or edit.is_queued_for_deletion():
		return
	(edit.get_meta("commit") as Callable).call()
	edit.set_meta("origin", edit.text)
	edit.set_meta("typed", false)


func _focused_edit() -> LineEdit:
	if not is_inside_tree():
		return null
	var focused := get_viewport().gui_get_focus_owner() as LineEdit
	return focused if focused != null and focused.has_meta("commit") and is_ancestor_of(focused) else null


func _commit_focused_edit() -> void:
	var focused := _focused_edit()
	if focused != null:
		_commit_edit(focused)


## Escape: back to the text from before this edit. False when there is nothing to undo.
func _restore_edit(edit: LineEdit) -> bool:
	var origin := str(edit.get_meta("origin", ""))
	if edit.text == origin:
		return false
	edit.text = origin
	edit.caret_column = origin.length()
	edit.set_meta("typed", false)
	return true


func _on_edit_gui_input(event: InputEvent, edit: LineEdit) -> void:
	# The field's own handling then ends the edit; an Escape with nothing to undo reaches the host.
	if event.is_action_pressed("ui_cancel") and _restore_edit(edit):
		edit.accept_event()


## Writes document text into an edit unless the player is typing in it.
func _show_text(edit: LineEdit, text: String) -> void:
	if edit.has_focus() and bool(edit.get_meta("typed", false)):
		return
	if edit.text != text:
		edit.text = text
	if not edit.has_focus():
		edit.set_meta("origin", text)


func _commit_field(path: String) -> void:
	var edit: LineEdit = _field_edits[path]
	if edit.text != _doc.raw(path):
		_doc.set_raw(path, edit.text)


## Keeps what the player typed while it still names the stored number.
static func _number_text(previous: String, value: float) -> String:
	var typed := Authoring.parse_number(previous)
	return previous if not is_nan(typed) and typed == value else Authoring.format_number(value)


# --- Orient and size ------------------------------------------------------------------------

func _on_axis_selected(index: int, picker: OptionButton, which: String) -> void:
	_doc.set_axis(which, str(picker.get_item_metadata(index)))
	_reapply_wingspan()


func _on_units_selected(index: int) -> void:
	_wingspan_text = ""
	_wingspan_problem = ""
	_doc.set_units(str(_units.get_item_metadata(index)))


## A scale derived from the wingspan depends on the axes: derive it again, or leave it unresolved.
func _reapply_wingspan() -> void:
	var known := Authoring.parse_number(_wingspan_text)
	if is_nan(known) or not _doc.units().is_empty():
		return
	if _doc.set_scale_from_wingspan(known):
		_wingspan_problem = ""
	else:
		_doc.set_units("")


func _commit_wingspan() -> void:
	var text := _wingspan_edit.text
	if text == _wingspan_text:
		return
	var from_wingspan := _doc.units().is_empty() and float(_doc.placement().unit_scale) > 0.0
	_wingspan_text = text
	_wingspan_problem = ""
	if text.strip_edges().is_empty():
		if from_wingspan:
			_doc.set_units("")
	else:
		var known := Authoring.parse_number(text)
		if is_nan(known):
			_wingspan_problem = NOT_A_NUMBER
		elif not _doc.set_scale_from_wingspan(known):
			_wingspan_problem = "Choose the nose and up axes first, then enter a wingspan above zero."
	_schedule_refresh()


func _commit_datum() -> void:
	var texts: Array[String] = []
	for edit: LineEdit in _datum_edits:
		texts.append(edit.text)
	if texts == _datum_texts:
		return
	_datum_texts = texts
	var point: Array = []
	for axis: int in 3:
		_datum_invalid[axis] = false
		if texts[axis].strip_edges().is_empty():
			continue
		var component := Authoring.parse_number(texts[axis])
		if is_nan(component):
			_datum_invalid[axis] = true
		else:
			point.append(component)
	if point.size() == 3:
		_doc.set_datum(point)
	elif not (_doc.placement().datum as Array).is_empty():
		# The three boxes no longer name a point: the datum is unresolved again.
		_doc.set_datum([])
	_schedule_refresh()


func _on_pick_toggled(pressed: bool) -> void:
	_preview.set_pick_mode(pressed)
	_pick_hint.visible = pressed
	if _narrow:
		_set_show_preview(pressed)


func _on_point_picked(source_point: Vector3) -> void:
	if not _pick_button.button_pressed or _doc.source() == null:
		return
	_pick_button.button_pressed = false
	_doc.set_datum([float(source_point.x), float(source_point.y), float(source_point.z)])


func _reset_orient_inputs() -> void:
	_wingspan_text = ""
	_wingspan_problem = ""
	_datum_texts = ["", "", ""]
	_datum_invalid = [false, false, false]
	for edit: LineEdit in _datum_edits:
		edit.set_meta("typed", false)
	_wingspan_edit.set_meta("typed", false)
	if _pick_button.button_pressed:
		_pick_button.button_pressed = false


# --- Inventory ------------------------------------------------------------------------------

func _on_propose_pressed() -> void:
	var before: Array = _doc.inventory()
	_doc.propose_inventory()
	var after: Array = _doc.inventory()
	var has_estimate := false
	for item: Dictionary in after:
		has_estimate = has_estimate or str(item.get("kind", "")) == "estimated"
	_set_inventory_note("" if has_estimate or after != before
		else tr("Nothing can be proposed yet. Enter the wing, tail and fuselage dimensions in Aircraft layout first."))


func _on_add_item_pressed() -> void:
	var id: String = _doc.add_item(tr("New item"))
	if id.is_empty():
		_set_inventory_note(tr("The inventory is full (%s items).") % Limits.INVENTORY_ITEMS)
		return
	_set_inventory_note("")
	_refresh()
	if _item_rows.has(id):
		_focus_control(_item_rows[id].name as Control)


func _set_inventory_note(text: String) -> void:
	_inventory_note.text = text
	_inventory_note.visible = not text.is_empty()


func _item(id: String) -> Dictionary:
	for item: Dictionary in _doc.inventory():
		if str(item.id) == id:
			return item
	return {}


static func _item_value(item: Dictionary, key: String) -> float:
	match key:
		"mass": return float(item.get("mass", 0.0))
		"x": return float(item.position[0])
		"y": return float(item.position[1])
	return float(item.position[2])


func _commit_item_number(id: String, key: String) -> void:
	if not _item_rows.has(id):
		return
	var edit: LineEdit = _item_rows[id][key]
	var slot := id + "/" + key
	if edit.text == str(_item_texts.get(slot, "")) and not _item_invalid.has(slot):
		return
	_item_texts[slot] = edit.text
	if _doc.set_item_raw(id, key, edit.text):
		_item_invalid.erase(slot)
	else:
		# Not a number: the stored value is unchanged and the text stays visible.
		_item_invalid[slot] = true
		_schedule_refresh()


func _commit_item_name(id: String) -> void:
	if not _item_rows.has(id):
		return
	var edit: LineEdit = _item_rows[id].name
	if edit.text != str(_item(id).get("name", "")):
		_doc.set_item_name(id, edit.text)


func _remove_item(id: String) -> void:
	_doc.remove_item(id)
	_focus_control.call_deferred(_add_item_button)


func _rebuild_inventory(items: Array) -> void:
	_rebuilding_items = true
	for child: Node in _inventory_box.get_children():
		_inventory_box.remove_child(child)
		child.queue_free()
	_item_rows.clear()
	var live := {}
	for item: Dictionary in items:
		var id := str(item.id)
		for number: Array in ITEM_NUMBERS:
			live[id + "/" + str(number[0])] = true
		_add_item_row(id)
	for slot: String in _item_texts.keys():
		if not live.has(slot):
			_item_texts.erase(slot)
			_item_invalid.erase(slot)
	if items.is_empty():
		_inventory_box.add_child(_label("No items yet. Propose the airframe items or add your own."))
	_rebuilding_items = false


func _add_item_row(id: String) -> void:
	var suffix := id.to_pascal_case()
	var holder := VBoxContainer.new()
	holder.name = "Item" + suffix
	holder.add_theme_constant_override("separation", 6)
	_inventory_box.add_child(holder)
	var top := _row(holder, "Title")
	top.add_theme_constant_override("separation", 8)
	var name_edit := _number_edit("ItemName" + suffix, _commit_item_name.bind(id))
	name_edit.placeholder_text = "Item name"
	name_edit.accessibility_name = tr("Item name")
	name_edit.max_length = Limits.NAME_CHARACTERS
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_edit)
	var remove := _button("Remove", "", "ItemRemove" + suffix)
	remove.pressed.connect(_remove_item.bind(id))
	top.add_child(remove)
	var row := {holder = holder, name = name_edit}
	# Evidence and mass on one line, the position on the next: each wraps on a narrow inspector.
	var evidence := _flow(holder, "Evidence")
	var kind := OptionButton.new()
	kind.name = "ItemKind" + suffix
	kind.accessibility_name = tr("Evidence")
	for choice: Array in KIND_CHOICES:
		kind.add_item(str(choice[1]))
		kind.set_item_metadata(kind.item_count - 1, str(choice[0]))
	kind.item_selected.connect(func(index: int) -> void: _doc.set_item_kind(id, str(kind.get_item_metadata(index))))
	Widgets.fit_option_popup(kind)
	evidence.add_child(kind)
	row["kind"] = kind
	var position_row := _flow(holder, "Position")
	for number: Array in ITEM_NUMBERS:
		var key := str(number[0])
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		(evidence if key == "mass" else position_row).add_child(cell)
		cell.add_child(Widgets.label(str(number[1]), "SectionLabel"))
		var edit := _number_edit("Item%s%s" % [key.capitalize(), suffix], _commit_item_number.bind(id, key))
		edit.custom_minimum_size.x = 92
		cell.add_child(edit)
		cell.add_child(Widgets.label(str(number[2]), "SectionLabel", false, false))
		row[key] = edit
	var error := _label(ENTER_A_NUMBER, "ErrorLabel")
	error.name = "ItemError" + suffix
	error.visible = false
	holder.add_child(error)
	row["error"] = error
	holder.add_child(HSeparator.new())
	_item_rows[id] = row


func _flow(parent: Container, node_name: String) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.name = node_name
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 6)
	parent.add_child(flow)
	return flow


# --- Test flight ----------------------------------------------------------------------------

func _on_test_fly_pressed() -> void:
	_commit_focused_edit()
	_issues = _collect_issues()
	if not _issues.is_empty() or _import_state == "inspecting":
		_refresh()
		return
	var compiled: Dictionary = _doc.compile()
	if not compiled.get("ok", false) or not compiled.get("value") is Object:
		set_note(_diagnostics_text(compiled.get("diagnostics", [])))
		return
	set_note("")
	var source: InspectedSource = _doc.source()
	var shown_name: String = _doc.name
	if shown_name.is_empty():
		shown_name = source.file_name().get_basename()
	test_fly_requested.emit({creator_candidate = compiled.value, creator_source = source,
		creator_placement = _doc.placement(), creator_name = shown_name, start_choice = _start_choice})


# --- Diagnostics ----------------------------------------------------------------------------

## Translates one diagnostic and fills its placeholders. Field labels and sentences among the
## arguments are translated (a file name has no catalog entry and stays as it is); numbers are
## shortened for reading.
func _diagnostic_text(entry: Dictionary) -> String:
	var message := tr(str(entry.get("message", "")))
	var arguments: Array = []
	for argument: Variant in entry.get("arguments", []):
		if typeof(argument) == TYPE_FLOAT:
			arguments.append(String.num(argument, 3))
		elif typeof(argument) == TYPE_STRING and (_known_labels.has(argument) or (argument as String).contains(" ")):
			arguments.append(tr(argument))
		else:
			arguments.append(str(argument))
	if not arguments.is_empty() and message.count("%s") == arguments.size():
		message = message % arguments
	return message


func _diagnostics_text(diagnostics: Array) -> String:
	var lines := PackedStringArray()
	for entry: Variant in diagnostics:
		if entry is Dictionary:
			lines.append(_diagnostic_text(entry))
	return "\n".join(lines)


## Invalid text held by the screen (wingspan, datum, inventory): it blocks a test flight like an
## invalid typed field of the document.
func _local_issues() -> Array:
	var found: Array = []
	if not _wingspan_problem.is_empty():
		found.append(R.diagnostic(R.FIELD_INVALID, _wingspan_problem, "local/wingspan", "orient_size", ["Known wingspan (m)"]))
	for axis: int in 3:
		if _datum_invalid[axis]:
			found.append(R.diagnostic(R.FIELD_INVALID, NOT_A_NUMBER, "local/datum/%d" % axis, "orient_size", [DATUM_NAMES[axis]]))
	for slot: String in _item_invalid.keys():
		var parts := slot.rsplit("/", true, 1)
		if _item(parts[0]).is_empty():
			# The item is gone: so is its invalid text.
			_item_invalid.erase(slot)
			_item_texts.erase(slot)
			continue
		var caption := str(parts[1])
		for number: Array in ITEM_NUMBERS:
			if str(number[0]) == caption:
				caption = tr(str(number[1]))
		found.append(R.diagnostic(R.FIELD_INVALID, NOT_A_NUMBER, "local/item/" + slot, "weight_balance",
			["%s · %s" % [str(_item(parts[0]).get("name", parts[0])), caption]]))
	return found


func _collect_issues() -> Array:
	var found: Array = _local_issues()
	found.append_array(_doc.issues())
	return found


## The step an issue belongs to, or "" when it names none.
func _issue_step(entry: Dictionary) -> String:
	var step := str(entry.get("step", ""))
	if Authoring.STEPS.has(step):
		return step
	var path := str(entry.get("field", ""))
	if path.begins_with("inventory"):
		return "weight_balance"
	for candidate: Dictionary in Authoring.FIELDS:
		if str(candidate.path) == path or str(candidate.path).begins_with(path + "/"):
			return str(candidate.step)
	return ""


## The control created for a field path, or null: the caller then falls back to the step.
func _focus_target(path: String) -> Control:
	if _field_edits.has(path):
		return _field_edits[path]
	match path:
		"source": return _choose_button
		"placement/nose_axis": return _nose_axis
		"placement/up_axis": return _up_axis
		"placement/unit_scale": return _units
		"placement/datum": return _datum_edits[0]
		"local/wingspan": return _wingspan_edit
		"inventory": return _propose_button
	var parts := path.split("/")
	if path.begins_with("local/datum/"):
		return _datum_edits[clampi(int(parts[2]), 0, 2)]
	if path.begins_with("local/item/") and parts.size() == 4 and _item_rows.has(parts[2]):
		return _item_rows[parts[2]].get(parts[3]) as Control
	if parts[0] == "inventory" and parts.size() >= 2 and parts[1].is_valid_int():
		var items: Array = _doc.inventory()
		var index := int(parts[1])
		if index >= 0 and index < items.size() and _item_rows.has(str(items[index].id)):
			var row: Dictionary = _item_rows[str(items[index].id)]
			var key := "name"
			if parts.size() >= 3:
				key = str({"mass": "mass", "position": "x", "kind": "kind"}.get(parts[2], "name"))
			return row[key] as Control
	for candidate: Dictionary in Authoring.FIELDS:
		if str(candidate.path).begins_with(path + "/"):
			return _field_edits[str(candidate.path)]
	return null


## What an issue is about, for messages such as "This value is required." that do not say.
func _issue_subject(entry: Dictionary) -> String:
	var path := str(entry.get("field", ""))
	if not (entry.get("arguments", []) as Array).is_empty() and str(entry.get("message", "")).begins_with("\"%s\""):
		return ""
	var known: Dictionary = Authoring.field(path)
	if not known.is_empty():
		return tr(str(known.label))
	if GROUP_LABELS.has(path):
		return tr(str(GROUP_LABELS[path]))
	var parts := path.split("/")
	if parts[0] == "inventory" and parts.size() >= 2 and parts[1].is_valid_int():
		var items: Array = _doc.inventory()
		var index := int(parts[1])
		if index >= 0 and index < items.size():
			return str(items[index].get("name", items[index].id))
	return ""


func _issue_text(entry: Dictionary) -> String:
	var text := _diagnostic_text(entry)
	var subject := _issue_subject(entry)
	if not subject.is_empty():
		text = "%s: %s" % [subject, text]
	var step := _issue_step(entry)
	if not step.is_empty():
		text = "%s · %s" % [tr(str(Authoring.STEP_TITLES[step])), text]
	return text


func _go_to_issue(entry: Dictionary) -> void:
	var step := _issue_step(entry)
	if step.is_empty():
		return
	go_to_step(step)
	if _narrow and _show_preview:
		_set_show_preview(false)
	var target := _focus_target(str(entry.get("field", "")))
	if not is_instance_valid(target) or not target.is_visible_in_tree():
		target = _default_focus(step)
	_focus_control.call_deferred(target)


# --- Refresh --------------------------------------------------------------------------------

func _schedule_refresh() -> void:
	if _refresh_queued or _closing:
		return
	_refresh_queued = true
	_refresh.call_deferred()


## Shows the document's state. Never moves focus and never rewrites text being typed.
func _refresh() -> void:
	_refresh_queued = false
	if _closing or _scroll == null:
		return
	var source: InspectedSource = _doc.source()
	if source != _shown_source:
		_shown_source = source
		_reset_orient_inputs()
	if (_doc.placement().datum as Array).size() == 3:
		# A complete datum, typed or picked, supersedes text that was not a number.
		_datum_invalid = [false, false, false]
	_issues = _collect_issues()
	_summary = _doc.summary()
	_refresh_steps()
	_sync_preview()
	_sync_markers()
	match _current:
		"import": _refresh_import()
		"orient_size": _refresh_orient()
		"aircraft_layout":
			_layout_model_note.visible = _preview_placed
			_refresh_fields(_current)
		"weight_balance":
			_refresh_inventory()
			_refresh_fields(_current)
		"review_test": _refresh_review()
		_: _refresh_fields(_current)
	_refresh_readouts()
	_refresh_footer()


func _refresh_steps() -> void:
	for index: int in Authoring.STEPS.size():
		var step: String = Authoring.STEPS[index]
		var title := tr(str(Authoring.STEP_TITLES[step]))
		_statuses[step] = _doc.step_status(step)
		var status := tr(str(_statuses[step]))
		(_rail_buttons[step] as Button).text = "%d. %s\n%s" % [index + 1, title, status]
		_step_select.set_item_text(index, "%d. %s — %s" % [index + 1, title, status])
		if step == _current:
			_heading.text = title
			_status_label.text = tr("Status: %s") % status


func _refresh_footer() -> void:
	var reason := ""
	if _import_state == "inspecting":
		reason = tr("Inspecting model…")
	elif not _issues.is_empty():
		reason = tr("Test fly is available once the issues listed above are resolved.")
	_test_fly_button.disabled = not reason.is_empty()
	_test_fly_button.tooltip_text = reason
	_reason_label.text = reason
	_reason_label.visible = _test_fly_button.visible and not reason.is_empty()


func _refresh_fields(step: String) -> void:
	# Inline messages for values that are set: an empty field is listed in Review, not painted red.
	var messages := {}
	for entry: Variant in _issues:
		if not entry is Dictionary or str((entry as Dictionary).get("code", "")) == R.FIELD_INVALID \
				and str((entry as Dictionary).get("message", "")) == NOT_A_NUMBER:
			continue
		var target := _focus_target(str((entry as Dictionary).get("field", "")))
		if target != null and not messages.has(target):
			messages[target] = _diagnostic_text(entry)
	for entry: Dictionary in Authoring.fields_for(step):
		var path := str(entry.path)
		var edit: LineEdit = _field_edits[path]
		var error: Label = _field_errors[path]
		_show_text(edit, _doc.raw(path))
		if _doc.is_invalid(path):
			error.text = tr(ENTER_A_NUMBER)
			error.visible = true
		elif _doc.value(path) != null and messages.has(edit):
			error.text = str(messages[edit])
			error.visible = true
		else:
			error.visible = false


func _refresh_import() -> void:
	var source: InspectedSource = _doc.source()
	_choose_button.text = "Replace model…" if source != null else "Choose model…"
	match _import_state:
		"inspecting":
			_import_status.text = "%s\n%s" % [tr("Inspecting model…"), _import_file_name]
		"failed":
			_import_status.text = "%s\n%s" % [tr("The model could not be imported"), _import_file_name]
			if source != null:
				_import_status.text += "\n" + tr("The current model is unchanged.")
		_:
			_import_status.text = tr("Model imported") if source != null else tr(NO_MODEL)
	_fill_lines(_import_errors, _import_diagnostics if _import_state == "failed" else [], "ErrorLabel", false)
	_fill_lines(_import_notes, source.notes() if source != null else [], "SecondaryLabel", true)
	if source == null:
		_import_details.text = ""
		_import_details.visible = false
		return
	var low: PackedFloat64Array = source.bounds_min()
	var high: PackedFloat64Array = source.bounds_max()
	var format := str(FORMAT_NAMES.get(source.format(), source.format()))
	_import_details.visible = true
	_import_details.text = "\n".join(PackedStringArray([
		tr("File: %s") % source.file_name(),
		tr("Format: %s") % tr(format),
		tr("Triangles: %s") % source.triangle_count(),
		tr("Size in model units: %s × %s × %s") % [_plain(high[0] - low[0]), _plain(high[1] - low[1]), _plain(high[2] - low[2])],
		tr("File size: %s") % String.humanize_size(source.byte_length()),
	]))


## One wrapped line per diagnostic. Admission notes carry their severity as a word.
func _fill_lines(box: VBoxContainer, diagnostics: Array, variation: String, with_severity: bool) -> void:
	var lines := PackedStringArray()
	for entry: Variant in diagnostics:
		if not entry is Dictionary:
			continue
		var text := _diagnostic_text(entry)
		if with_severity:
			var warning: bool = str((entry as Dictionary).get("severity", "")) == R.SEVERITY_WARNING
			text = (tr("Warning: %s") if warning else tr("Note: %s")) % text
		lines.append(text)
	var signature := "\n".join(lines)
	if str(box.get_meta("shown", "")) == signature and box.get_child_count() == lines.size():
		return
	box.set_meta("shown", signature)
	for child: Node in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for line: String in lines:
		box.add_child(_label(line, variation, false))


static func _plain(value: float) -> String:
	return String.num(value, 3)


func _refresh_orient() -> void:
	var source: InspectedSource = _doc.source()
	_orient_missing.visible = source == null
	_orient_controls.visible = source != null
	if source == null:
		return
	var placement: Dictionary = _doc.placement()
	_unplaced_hint.visible = not _preview_placed
	_select_metadata(_nose_axis, str(placement.nose_axis))
	_select_metadata(_up_axis, str(placement.up_axis))
	_select_metadata(_units, _doc.units())
	_show_text(_wingspan_edit, _wingspan_text)
	_wingspan_error_label.visible = not _wingspan_problem.is_empty()
	if not _wingspan_problem.is_empty():
		_wingspan_error_label.text = tr(ENTER_A_NUMBER) if _wingspan_problem == NOT_A_NUMBER else tr(_wingspan_problem)
	var scale := float(placement.unit_scale)
	_scale_readout.visible = scale > 0.0
	_scale_readout.text = tr("Scale: 1 model unit = %s m") % String.num(scale, 6)

	var datum: Array = placement.datum
	var any_invalid := false
	for axis: int in 3:
		if datum.size() == 3:
			_datum_texts[axis] = _number_text(_datum_texts[axis], float(datum[axis]))
		_show_text(_datum_edits[axis], _datum_texts[axis])
		any_invalid = any_invalid or _datum_invalid[axis]
	_datum_error.visible = any_invalid

	var bounds: Dictionary = _doc.placed_bounds()
	_real_size.text = _real_size_text(bounds) if not bounds.is_empty() \
		else tr("Choose the axes, the units and the datum to see the real size.")
	var resolved: Dictionary = _doc.placement_result()
	_orient_todo.visible = not resolved.ok
	_orient_todo.text = "" if resolved.ok else _diagnostics_text(resolved.diagnostics)


func _real_size_text(bounds: Dictionary) -> String:
	return tr("Span %s m · Length %s m · Height %s m") % [
		"%.2f" % (float(bounds.max[1]) - float(bounds.min[1])),
		"%.2f" % (float(bounds.max[0]) - float(bounds.min[0])),
		"%.2f" % (float(bounds.max[2]) - float(bounds.min[2]))]


func _select_metadata(picker: OptionButton, value: String) -> void:
	for index: int in picker.item_count:
		if str(picker.get_item_metadata(index)) == value:
			if picker.selected != index:
				picker.selected = index
			return
	picker.selected = 0


func _refresh_inventory() -> void:
	var items: Array = _doc.inventory()
	var ids := PackedStringArray()
	for item: Dictionary in items:
		ids.append(str(item.id))
	var signature := ",".join(ids)
	if signature != _inventory_signature:
		_inventory_signature = signature
		_rebuild_inventory(items)
	for item: Dictionary in items:
		var id := str(item.id)
		var row: Dictionary = _item_rows[id]
		_show_text(row.name as LineEdit, str(item.get("name", "")))
		_select_metadata(row.kind as OptionButton, str(item.get("kind", "manual")))
		var flagged := false
		for number: Array in ITEM_NUMBERS:
			var key := str(number[0])
			var slot := id + "/" + key
			if _item_invalid.has(slot):
				flagged = true
			else:
				_item_texts[slot] = _number_text(str(_item_texts.get(slot, "")), _item_value(item, key))
			_show_text(row[key] as LineEdit, str(_item_texts[slot]))
		(row.error as Label).visible = flagged


func _refresh_readouts() -> void:
	for readout: Dictionary in _readouts:
		var label: Label = readout.label
		if label.is_visible_in_tree() or not is_inside_tree():
			label.text = _readout_text(_summary, readout.spec)


static func _readout_text(summary: Dictionary, spec: Array) -> String:
	var value: Variant = summary.get(str(spec[1]))
	var decimals: int = spec[3]
	var factor: float = spec[4]
	var parts := PackedStringArray()
	if value is Array or value is PackedFloat64Array:
		for component: Variant in value:
			parts.append(("%." + str(decimals) + "f") % (float(component) * factor))
	elif typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		parts.append(("%." + str(decimals) + "f") % (float(value) * factor))
	if parts.is_empty():
		return "—"
	return ("%s %s" % [", ".join(parts), str(spec[2])]).strip_edges()


func _refresh_review() -> void:
	for step: String in _review_sections:
		(_review_sections[step] as Label).text = "%s — %s\n%s" % [tr(str(Authoring.STEP_TITLES[step])),
			tr(str(_statuses.get(step, ""))), _section_detail(step)]
	var texts := PackedStringArray()
	for entry: Variant in _issues:
		if entry is Dictionary:
			texts.append(_issue_text(entry))
	var signature := "\n".join(texts)
	if signature == _issue_signature:
		return
	_issue_signature = signature
	for child: Node in _issue_box.get_children():
		_issue_box.remove_child(child)
		child.queue_free()
	if texts.is_empty():
		_issue_box.add_child(_label("No open issues."))
		return
	var index := 0
	for entry: Variant in _issues:
		if not entry is Dictionary:
			continue
		if _issue_step(entry).is_empty():
			_issue_box.add_child(_label(texts[index], "ErrorLabel", false))
		else:
			var jump := _button(texts[index], "", "Issue%d" % index)
			jump.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
			jump.alignment = HORIZONTAL_ALIGNMENT_LEFT
			jump.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			jump.pressed.connect(_go_to_issue.bind((entry as Dictionary).duplicate(true)))
			_issue_box.add_child(jump)
		index += 1


func _section_detail(step: String) -> String:
	var source: InspectedSource = _doc.source()
	match step:
		"import":
			return source.file_name() if source != null else tr(NO_MODEL)
		"orient_size":
			var bounds: Dictionary = _doc.placed_bounds()
			return _real_size_text(bounds) if not bounds.is_empty() else tr("Not placed yet")
		"aircraft_layout":
			var span: Variant = _doc.value("wing/span")
			return tr("Conventional") if span == null else "%s · %s %s m" % [tr("Conventional"), tr("Wingspan"), _plain(float(span))]
		"weight_balance":
			return tr("%s inventory items") % _doc.inventory().size()
		"power_mount":
			return "%s · %s" % [tr("Electric"), tr(ELECTRIC_PACKAGE)]
		"controls_ground":
			return "%s · %s" % [tr("No gear"), tr(STATIC_VISUAL)]
	return tr("Original")


# --- Preview --------------------------------------------------------------------------------

## Rebuilds the preview only when the source or its placement changed.
func _sync_preview() -> void:
	var source: InspectedSource = _doc.source()
	var placement: Dictionary = _doc.placement()
	var signature := "" if source == null else "%d|%s" % [source.get_instance_id(), str(placement)]
	if signature == _preview_signature:
		return
	_preview_signature = signature
	_preview_placed = false
	if source == null:
		_preview.clear()
		return
	var built: Dictionary = VisualBuilder.build_preview(source, placement)
	if not built.ok:
		_preview.show_message(_diagnostics_text(built.diagnostics))
		return
	_preview_placed = bool(built.value.placed)
	_preview.show_root(built.value.root)


func _sync_markers() -> void:
	var markers: Array = []
	var placement: Dictionary = _doc.placement()
	if _doc.source() != null and _preview_placed:
		markers.append({name = tr("Datum"), position = Vector3.ZERO, color = MARKER_COLORS.datum})
		var summary: Dictionary = _summary
		var cg: Variant = summary.get("cg_m")
		if (cg is Array or cg is PackedFloat64Array) and cg.size() == 3:
			markers.append({name = tr("CG"), position = _model_point(float(cg[0]), float(cg[1]), float(cg[2])),
				color = MARKER_COLORS.cg})
		if summary.has("neutral_point_x_m"):
			markers.append({name = tr("Neutral point"), position = _model_point(float(summary.neutral_point_x_m), 0.0, 0.0),
				color = MARKER_COLORS.neutral_point})
		_add_value_marker(markers, tr("Propeller hub"), "equipment/hub_position", true, MARKER_COLORS.hub)
		_add_value_marker(markers, tr("Tailplane"), "horizontal_tail/position", false, MARKER_COLORS.tailplane)
		_add_value_marker(markers, tr("Fin"), "vertical_tail/position", false, MARKER_COLORS.fin)
	elif _doc.source() != null and (placement.datum as Array).size() == 3:
		# Not placed yet: the preview shows the file's own axes, so the datum is drawn where it was typed.
		var datum: Array = placement.datum
		markers.append({name = tr("Datum"), position = Vector3(float(datum[0]), float(datum[1]), float(datum[2])),
			color = MARKER_COLORS.datum})
	_preview.set_markers(markers)


## A marker at a position typed in the leading-edge frame. Tail positions have no lateral value.
func _add_value_marker(markers: Array, caption: String, path: String, lateral: bool, color: Color) -> void:
	var aft: Variant = _doc.value(path + "/0")
	var right: Variant = _doc.value(path + "/1") if lateral else 0.0
	var up: Variant = _doc.value(path + "/2")
	if aft == null or right == null or up == null:
		return
	markers.append({name = caption, position = _model_point(float(aft), float(right), float(up)), color = color})


static func _model_point(aft: float, right: float, up: float) -> Vector3:
	return VisualBuilder.structural_to_model(PackedFloat64Array([aft, right, up]))
