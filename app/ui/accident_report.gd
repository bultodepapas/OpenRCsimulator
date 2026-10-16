extends CanvasLayer

const UiTheme := preload("res://ui/ui_theme.gd")

signal restart_requested
signal inspect_requested

const LAYER := 9 # above the flight HUD; the pause menu and report screens stay above it
const TOAST_SECONDS := 5.0
const MAX_MINOR_AMOUNT := 9000000000000000000
const COMPONENT_LABELS := {
	"central_aileron_servo": "Central aileron servo",
	"covered_airframe_and_installation_hardware": "Airframe and installation hardware",
	"engine_and_muffler": "Engine and muffler",
	"final_assembly_and_commissioning": "Final assembly and commissioning",
	"fuselage_servos": "Fuselage servos",
	"onboard_fuel": "Onboard fuel system",
	"propeller": "Propeller",
	"receiver": "Receiver",
	"receiver_battery": "Receiver battery",
}

var _surface: Control
var _report_panel: PanelContainer
var _toast_panel: PanelContainer
var _restore_button: Button
var _title_label: Label
var _outcome_label: Label
var _status_label: Label
var _amount_label: Label
var _caption_label: Label
var _details_button: Button
var _inspect_button: Button
var _restart_button: Button
var _hide_archived_button: Button
var _details_scroll: ScrollContainer
var _details_content: VBoxContainer
var _toast_status: Label
var _toast_amount: Label

var _report: Dictionary = {}
var _terminal := false
var _archived := false
var _settled_report := false
var _auto_settled := false
var _reopen_only := false
var _expanded := false
var _minimized := false
var _suspended := false
var _content_visible := false
var _toast_remaining := 0.0
var _layout_retry_frames := 0


func _init() -> void:
	name = "AccidentReport"
	layer = LAYER


func _ready() -> void:
	_build_ui()
	set_process(true)
	set_process_unhandled_input(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and not _report.is_empty() and _surface != null:
		_render_report()


## Shows a copied assessment. Incomplete values stay labeled as a range, subtotal, or unknown amount.
func show_assessment(report: Dictionary, terminal: bool = true) -> void:
	if _surface == null:
		_build_ui()
	_report = report.duplicate(true)
	_terminal = terminal
	_archived = false
	_settled_report = false
	_auto_settled = false
	_reopen_only = false
	_expanded = false
	_minimized = false
	_content_visible = true
	_toast_remaining = TOAST_SECONDS if not terminal else 0.0
	_render_report()
	_report_panel.visible = terminal
	_toast_panel.visible = not terminal
	_restore_button.visible = false
	_details_button.button_pressed = false
	_details_scroll.visible = false
	_details_scroll.custom_minimum_size.y = 0.0
	_surface.mouse_filter = Control.MOUSE_FILTER_STOP if terminal else Control.MOUSE_FILTER_IGNORE
	_surface.visible = not _suspended
	_layout()
	_layout_retry_frames = 2
	if terminal and not _suspended:
		_focus_inspect.call_deferred()


## Restores an immutable previous assessment behind a small reopen control, without taking focus or input.
func show_archived(report: Dictionary) -> void:
	if _surface == null:
		_build_ui()
	_report = report.duplicate(true)
	_terminal = false
	_archived = true
	_settled_report = false
	_auto_settled = false
	_reopen_only = true
	_expanded = false
	_minimized = true
	_content_visible = true
	_toast_remaining = 0.0
	_render_report()
	_report_panel.visible = false
	_toast_panel.visible = false
	_restore_button.visible = true
	_release_report_focus()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.visible = not _suspended
	_apply_action_visibility()
	_layout()
	_layout_retry_frames = 2


## Shows a prominent read-only report when a nonterminal incident settles on the ground.
func show_settled(report: Dictionary) -> void:
	if _surface == null:
		_build_ui()
	_report = report.duplicate(true)
	_terminal = false
	_archived = false
	_settled_report = true
	_auto_settled = true
	_reopen_only = true
	_expanded = false
	_minimized = false
	_content_visible = true
	_toast_remaining = 0.0
	_render_report()
	_report_panel.visible = true
	_toast_panel.visible = false
	_restore_button.visible = false
	_release_report_focus()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.visible = not _suspended
	_apply_action_visibility()
	_layout()
	_layout_retry_frames = 2


## Collapses only the automatically presented settled card and keeps its passive reopen control.
func dismiss_settled() -> void:
	if not _auto_settled:
		return
	_auto_settled = false
	if not _settled_report or not _reopen_only or _report_panel == null or not _report_panel.visible:
		return
	_hide_read_only_report()


## Removes the current report after an intentional caller action, such as restarting the incident.
func clear_report() -> void:
	_report.clear()
	_content_visible = false
	_terminal = false
	_archived = false
	_settled_report = false
	_auto_settled = false
	_reopen_only = false
	_expanded = false
	_minimized = false
	_toast_remaining = 0.0
	if _surface != null:
		_surface.visible = false
		_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_report_panel.visible = false
		_toast_panel.visible = false
		_restore_button.visible = false
		_details_button.button_pressed = false
		_details_scroll.visible = false
		_details_scroll.custom_minimum_size.y = 0.0
		for child: Node in _details_content.get_children():
			_details_content.remove_child(child)
			child.queue_free()


## Hides the report while pause or another screen owns input, preserving its display state for resume.
func suspend(on: bool) -> void:
	if _suspended == on:
		return
	_suspended = on
	if _surface == null:
		return
	if on:
		var focused := get_viewport().gui_get_focus_owner()
		if focused in _interactive_controls():
			focused.release_focus()
		for button: Control in _interactive_controls():
			button.focus_mode = Control.FOCUS_NONE
		_surface.visible = false
		_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		for button: Control in _interactive_controls():
			button.focus_mode = Control.FOCUS_ALL
		_surface.visible = _content_visible
		_surface.mouse_filter = Control.MOUSE_FILTER_STOP if _terminal else Control.MOUSE_FILTER_IGNORE
		_layout()
		_layout_retry_frames = 2


func _process(delta: float) -> void:
	if not _suspended and _content_visible and _layout_retry_frames > 0:
		_layout()
		_layout_retry_frames -= 1
	if _suspended or _terminal or _toast_remaining <= 0.0:
		return
	_toast_remaining = maxf(0.0, _toast_remaining - delta)
	if _toast_remaining == 0.0 and _toast_panel != null:
		_toast_panel.visible = false
		_minimized = true
		_reopen_only = true
		_restore_button.visible = true
		_restore_button.text = tr("View damage report")
		_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_action_visibility()
		_layout()


func _unhandled_input(event: InputEvent) -> void:
	if not _terminal or _archived or _suspended or _minimized or _surface == null or not _surface.visible:
		return
	if event is InputEventKey:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_NONE:
			key = (event as InputEventKey).keycode
		# The app root owns pause (Escape) and explicit restart (R); other flight/camera keys are safe to ignore
		# while the terminal card is open. Inspect minimizes the card and lets all camera input through.
		if key != KEY_ESCAPE and key != KEY_R:
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	if _surface != null:
		return
	_surface = Control.new()
	_surface.name = "AccidentReportSurface"
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.visible = false
	_surface.theme = UiTheme.build()
	_surface.resized.connect(_layout)
	add_child(_surface)

	_report_panel = PanelContainer.new()
	_report_panel.name = "AccidentReportCard"
	_report_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_report_panel.visible = false
	_report_panel.add_theme_stylebox_override("panel", _card_style())
	_surface.add_child(_report_panel)
	var column := VBoxContainer.new()
	column.name = "ReportColumn"
	column.add_theme_constant_override("separation", _scaled(9))
	_report_panel.add_child(column)

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", _scaled(14))
	column.add_child(heading)
	_title_label = _label("ACCIDENT REPORT", UiTheme.TEXT, _scaled(30))
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.theme_type_variation = "TitleLabel"
	heading.add_child(_title_label)
	_outcome_label = _label("", UiTheme.TEXT_2, _scaled(16))
	_outcome_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_outcome_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(_outcome_label)

	_status_label = _label("", UiTheme.FOCUS, _scaled(18))
	column.add_child(_status_label)
	_amount_label = _label("", UiTheme.TEXT, _scaled(56))
	_amount_label.name = "ReportAmount"
	_amount_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_amount_label)
	_caption_label = _label("", UiTheme.TEXT_2, _scaled(18))
	_caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_caption_label)

	var actions := HFlowContainer.new()
	actions.name = "ReportActions"
	actions.add_theme_constant_override("h_separation", _scaled(10))
	actions.add_theme_constant_override("v_separation", _scaled(8))
	column.add_child(actions)
	_inspect_button = _button("Inspect wreck", "PrimaryButton")
	_inspect_button.name = "InspectWreck"
	_inspect_button.pressed.connect(_on_inspect_pressed)
	actions.add_child(_inspect_button)
	_details_button = _button("Show damage breakdown")
	_details_button.name = "DamageBreakdown"
	_details_button.toggle_mode = true
	_details_button.toggled.connect(_set_expanded)
	actions.add_child(_details_button)
	_restart_button = _button("Restart flight")
	_restart_button.name = "RestartFlight"
	_restart_button.pressed.connect(_on_restart_pressed)
	actions.add_child(_restart_button)
	_hide_archived_button = _button("Hide accident report")
	_hide_archived_button.name = "HideArchivedReport"
	_hide_archived_button.visible = false
	_hide_archived_button.pressed.connect(_hide_read_only_report)
	actions.add_child(_hide_archived_button)

	_details_scroll = ScrollContainer.new()
	_details_scroll.name = "DamageDetailsScroll"
	_details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_details_scroll.follow_focus = true
	_details_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_details_scroll.visible = false
	column.add_child(_details_scroll)
	_details_content = VBoxContainer.new()
	_details_content.name = "DamageDetails"
	_details_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_content.add_theme_constant_override("separation", _scaled(6))
	_details_scroll.add_child(_details_content)

	var estimate_note := _label(tr("Estimated prices and repair outcomes may differ."), UiTheme.TEXT_2, _scaled(14))
	estimate_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(estimate_note)

	_toast_panel = PanelContainer.new()
	_toast_panel.name = "AccidentToast"
	_toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_panel.visible = false
	_toast_panel.add_theme_stylebox_override("panel", _toast_style())
	_surface.add_child(_toast_panel)
	var toast_column := VBoxContainer.new()
	toast_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_column.add_theme_constant_override("separation", _scaled(4))
	_toast_panel.add_child(toast_column)
	_toast_status = _label("DAMAGE REPORTED", UiTheme.TEXT_2, _scaled(15))
	_toast_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_column.add_child(_toast_status)
	_toast_amount = _label("", UiTheme.TEXT, _scaled(24))
	_toast_amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_amount.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_column.add_child(_toast_amount)

	_restore_button = _button("Show accident report", "PrimaryButton")
	_restore_button.name = "ReopenAccidentReport"
	_restore_button.custom_minimum_size.y = _scaled(52)
	_restore_button.visible = false
	_restore_button.pressed.connect(_reopen_report)
	_surface.add_child(_restore_button)
	for button: Button in [_inspect_button, _details_button, _restart_button, _hide_archived_button, _restore_button]:
		button.custom_minimum_size.y = _scaled(54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_ALL
	_layout()


func _layout() -> void:
	if _surface == null or _report_panel == null:
		return
	var viewport_size := _surface.size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport().get_visible_rect().size
	var metrics := layout_metrics(viewport_size, UiTheme.text_scale)
	var gutter := float(metrics.gutter)
	var width := float(metrics.panel_width)
	_report_panel.custom_minimum_size.x = width
	_details_scroll.custom_minimum_size.y = float(metrics.details_max_height) if _expanded else 0.0
	_details_scroll.custom_maximum_size.y = float(metrics.details_max_height)
	_report_panel.size = _report_panel.get_combined_minimum_size()
	_report_panel.size.x = width
	var max_height := float(metrics.max_panel_height)
	_report_panel.size.y = minf(_report_panel.size.y, max_height)
	_report_panel.position = Vector2((viewport_size.x - width) * 0.5,
		maxf(gutter, viewport_size.y - gutter - _report_panel.size.y))
	var toast_width := minf(_scaled(470), maxf(0.0, viewport_size.x - gutter * 2.0))
	_toast_panel.position = Vector2(viewport_size.x - gutter - toast_width, gutter)
	_toast_panel.size = Vector2(toast_width, _toast_panel.get_combined_minimum_size().y)
	_restore_button.size = _restore_button.get_combined_minimum_size()
	_restore_button.position = Vector2((viewport_size.x - _restore_button.size.x) * 0.5,
		viewport_size.y - gutter - _restore_button.size.y)


static func layout_metrics(viewport_size: Vector2, ui_scale: float = 1.0) -> Dictionary:
	var safe_scale := 1.0
	if is_finite(ui_scale):
		safe_scale = clampf(ui_scale, 0.8, 1.5)
	var gutter := clampf(28.0 * safe_scale, 20.0, 48.0)
	var max_width := minf(920.0 * safe_scale, maxf(0.0, viewport_size.x - gutter * 2.0))
	var max_height := maxf(0.0, viewport_size.y - gutter * 2.0)
	# Keep the details pane scrollable on short displays so the full card and its actions fit.
	var details_capacity := 108.0 + maxf(0.0, viewport_size.y - 720.0) * 0.25
	var details_height := minf(180.0 * safe_scale, maxf(96.0, details_capacity))
	return {
		"panel_width": max_width,
		"gutter": gutter,
		"max_panel_height": max_height,
		"details_max_height": details_height,
		"headline_size": clampi(roundi(56.0 * safe_scale), 32, 84),
	}


func _render_report() -> void:
	if _surface == null:
		return
	_title_label.text = tr("DAMAGE REPORT") if _settled_report else tr("ACCIDENT REPORT")
	var state := _headline_state(_report)
	_outcome_label.text = _outcome_text(_report.get("outcome", "unavailable"))
	_status_label.text = state.status
	_amount_label.text = state.amount
	_amount_label.add_theme_font_size_override("font_size", int(layout_metrics(_surface.size, UiTheme.text_scale).headline_size))
	_caption_label.text = state.caption
	_details_button.text = tr("Hide damage breakdown") if _expanded else tr("Show damage breakdown")
	_inspect_button.text = tr("Inspect aircraft") if _settled_report else tr("Inspect wreck")
	_restart_button.text = tr("Restart flight")
	_hide_archived_button.text = tr("Hide damage report") if _settled_report else tr("Hide accident report")
	if _archived:
		_restore_button.text = tr("View archived accident report")
	elif _reopen_only:
		_restore_button.text = tr("View damage report")
	else:
		_restore_button.text = tr("Show accident report")
	_toast_status.text = tr("DAMAGE REPORTED")
	_toast_amount.text = state.amount
	_rebuild_details()
	_apply_action_visibility()
	_layout()
	_layout_retry_frames = 2


func _headline_state(report: Dictionary) -> Dictionary:
	var complete: bool = typeof(report.get("complete", false)) == TYPE_BOOL and bool(report.get("complete", false))
	var currency := _currency_code(report.get("currency", "USD"))
	var total: Variant = _valid_minor(report.get("total_minor"))
	var low: Variant = _valid_minor(report.get("low_minor"))
	var high: Variant = _valid_minor(report.get("high_minor"))
	var subtotal: Variant = _valid_minor(report.get("known_subtotal_minor"))
	var has_priced_action := _has_priced_action(report)
	if complete and total != null:
		return {
			"status": _complete_status(str(report.get("outcome", "unavailable"))),
			"amount": _format_headline_money(int(total), currency),
			"caption": tr("Estimated total. Expand for cents, line items, and price assumptions."),
		}
	if not complete:
		if low != null and high != null and (int(low) != 0 or int(high) != 0 or has_priced_action):
			var low_value := mini(int(low), int(high))
			var high_value := maxi(int(low), int(high))
			return {
				"status": tr("INCOMPLETE ESTIMATE RANGE"),
				"amount": "%s – %s" % [_format_headline_money(low_value, currency), _format_headline_money(high_value, currency)],
				"caption": tr("Range only. Some required costs or inspection results are unresolved."),
			}
		if low != null and (int(low) != 0 or has_priced_action):
			return {
				"status": tr("INCOMPLETE ESTIMATE · LOWER BOUND"),
				"amount": tr("At least %s") % _format_headline_money(int(low), currency),
				"caption": tr("This is a lower bound; unresolved costs are excluded."),
			}
		if high != null and (int(high) != 0 or has_priced_action):
			return {
				"status": tr("INCOMPLETE ESTIMATE · UPPER BOUND"),
				"amount": tr("Up to %s") % _format_headline_money(int(high), currency),
				"caption": tr("This is an upper bound; unresolved costs may change the result."),
			}
		if subtotal != null and (int(subtotal) != 0 or _has_priced_action(report)):
			return {
				"status": tr("KNOWN SUBTOTAL · INCOMPLETE"),
				"amount": _format_headline_money(int(subtotal), currency),
				"caption": tr("Known subtotal only. It is not the complete cost."),
			}
		return {
			"status": tr("AMOUNT UNKNOWN"),
			"amount": tr("Cost unavailable"),
			"caption": tr("No complete amount or priced subtotal is available."),
		}
	if subtotal != null and (int(subtotal) != 0 or _has_priced_action(report)):
		return {
			"status": tr("KNOWN SUBTOTAL · INCOMPLETE"),
			"amount": _format_headline_money(int(subtotal), currency),
			"caption": tr("Known subtotal only. It is not the complete cost."),
		}
	return {
		"status": _complete_status(str(report.get("outcome", "unavailable"))),
		"amount": tr("Amount unavailable"),
		"caption": tr("A complete amount was not supplied for this assessment."),
	}


func _complete_status(outcome: String) -> String:
	match outcome:
		"repair": return tr("REPAIR ESTIMATE")
		"total_loss": return tr("ESTIMATED LOSS")
		"inspection": return tr("INSPECTION REQUIRED")
		_: return tr("COST UNAVAILABLE")


func _outcome_text(value: Variant) -> String:
	match str(value):
		"repair": return tr("OUTCOME · REPAIR")
		"total_loss": return tr("OUTCOME · TOTAL LOSS")
		"inspection": return tr("OUTCOME · INSPECTION")
		_: return tr("OUTCOME · UNAVAILABLE")


func _rebuild_details() -> void:
	if _details_content == null:
		return
	for child: Node in _details_content.get_children():
		_details_content.remove_child(child)
		child.queue_free()
	if not _expanded:
		return
	var currency := _currency_code(_report.get("currency", "USD"))
	var identity_value: Variant = _report.get("identity", {})
	var identity: Dictionary = identity_value if identity_value is Dictionary else {}
	var price_date: Variant = _report.get("price_date")
	_add_detail_text(tr("Price date: %s") % (str(price_date) if price_date != null and str(price_date) != "" else tr("unavailable")), true)
	var valuation: Variant = _report.get("valuation_kind")
	_add_detail_text(tr("Valuation: %s") % (_humanize_identifier(str(valuation)) if valuation != null and str(valuation) != "" else tr("method unavailable")), true)
	var aircraft_name := str(_report.get("aircraft_name", identity.get("aircraft_id", "")))
	if aircraft_name != "":
		_add_detail_text(tr("Aircraft: %s") % _display_identifier(aircraft_name), true)
	var incident_id := str(_report.get("incident_id", identity.get("incident_id", "")))
	if incident_id != "":
		_add_detail_text(tr("Incident: %s") % incident_id, true)
	_add_detail_text(tr("All amounts are estimates. Market prices, labor, and repair outcomes may differ."), true)
	_add_detail_money(tr("Known subtotal"), _report.get("known_subtotal_minor"), currency)
	var complete: bool = typeof(_report.get("complete", false)) == TYPE_BOOL and bool(_report.get("complete", false))
	if complete:
		_add_detail_money(tr("Complete estimated total"), _report.get("total_minor"), currency)
	_add_detail_money(tr("Salvage value reported"), _report.get("salvage_minor"), currency)
	_add_detail_money(tr("Replacement reference reported"), _report.get("replacement_minor"), currency)
	var replacement_quote_low: Variant = _valid_minor(_report.get("replacement_quote_low_minor"))
	var replacement_quote_high: Variant = _valid_minor(_report.get("replacement_quote_high_minor"))
	if replacement_quote_low != null or replacement_quote_high != null:
		_add_detail_section(tr("Complete-build replacement quote comparison (reference only)"))
		if replacement_quote_low != null:
			_add_detail_money(tr("Low reference"), replacement_quote_low, currency)
		if replacement_quote_high != null:
			_add_detail_money(tr("High reference"), replacement_quote_high, currency)
	_add_replacement_comparison(currency)
	_add_detail_section(tr("Parts and actions"))
	var lines: Variant = _report.get("lines", [])
	var line_count := 0
	if lines is Array:
		for line_value: Variant in lines:
			if not line_value is Dictionary:
				continue
			var line: Dictionary = line_value
			var raw_id := str(line.get("id", ""))
			var descriptor := _humanize_identifier(raw_id) if raw_id != "" else tr("Unspecified item")
			var action := _action_text(line.get("action", ""))
			if action != "":
				descriptor += " · " + action
			var quantity := _quantity_text(line.get("quantity"))
			if quantity != "":
				descriptor += " × " + quantity
			_add_detail_money(descriptor, line.get("amount_minor"), currency)
			var price_basis := str(line.get("price_basis", ""))
			if price_basis != "":
				_add_detail_text(tr("Price basis: %s") % _humanize_identifier(price_basis), true)
			var observed_on := str(line.get("observed_on", ""))
			if observed_on != "":
				_add_detail_text(tr("Observed: %s") % observed_on, true)
			var source_url := str(line.get("source_url", ""))
			if source_url.begins_with("https://"):
				_add_detail_source(source_url)
			var notes := str(line.get("notes", ""))
			if notes != "":
				_add_detail_text(notes, true)
			line_count += 1
	if line_count == 0:
		_add_detail_text(tr("No priced line items were supplied."), true)
	var unresolved: Variant = _report.get("unresolved", [])
	if unresolved is Array and not unresolved.is_empty():
		_add_detail_section(tr("Unresolved items"))
		for item: Variant in unresolved:
			_add_detail_text("• " + _unresolved_text(item), true)
	elif not complete:
		_add_detail_text(tr("Some costs or inspection results remain unresolved."), true)
	var assumptions: Variant = _report.get("assumptions", [])
	if assumptions is Array and not assumptions.is_empty():
		_add_detail_section(tr("Assumptions"))
		for assumption: Variant in assumptions:
			_add_detail_text("• " + _unresolved_text(assumption), true)


func _add_replacement_comparison(currency: String) -> void:
	var value: Variant = _report.get("replacement_comparison")
	if not value is Dictionary:
		return
	var status: Variant = value.get("status")
	if status not in ["optimal", "unknown_cost", "search_limit", "infeasible", "cost_out_of_range"]:
		return
	_add_detail_section(tr("Replacement parts comparison"))
	_add_detail_text(tr("Parts only. Inspection, repairs and labor are separate; this comparison is not added to the accident total."), true)
	var proven: bool = value.get("optimality_proven") == true and status == "optimal" and _valid_minor(value.get("total_cost_cents")) != null
	_add_detail_money(tr("Lowest priced combination for these parts") if proven else tr("Provisional parts estimate"), value.get("total_cost_cents"), currency)
	if not proven:
		var explanation := tr("Some package prices are unknown; the cheapest option is unresolved.")
		if status == "search_limit":
			explanation = tr("Comparison is incomplete; a cheaper combination may exist.")
		elif status == "infeasible":
			explanation = tr("No compatible combination covers all requested parts.")
		elif status == "cost_out_of_range":
			explanation = tr("Parts estimate exceeds the supported amount range.")
		_add_detail_text(explanation, true)
	if value.get("assessment_complete") != true:
		_add_detail_text(tr("Other damage or inspection costs remain unresolved."), true)
	_add_detail_text(tr("Catalog estimates; availability and physical fit require confirmation."), true)


func _add_detail_section(text: String) -> void:
	var label := _label(text, UiTheme.FOCUS, _scaled(16))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_content.add_child(label)


func _add_detail_text(text: String, secondary: bool) -> void:
	var label := _label(text, UiTheme.TEXT_2 if secondary else UiTheme.TEXT, _scaled(15))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details_content.add_child(label)


func _add_detail_source(source_url: String) -> void:
	var label := RichTextLabel.new()
	label.text = tr("Source: %s") % source_url
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.selection_enabled = true
	label.scroll_active = false
	label.fit_content = true
	label.add_theme_color_override("default_color", UiTheme.TEXT_2)
	label.add_theme_font_size_override("normal_font_size", _scaled(14))
	_details_content.add_child(label)


func _add_detail_money(label_text: String, value: Variant, currency: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _scaled(12))
	_details_content.add_child(row)
	var label := _label(label_text, UiTheme.TEXT_2, _scaled(15))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	var amount: Variant = _valid_minor(value)
	var value_label := _label(_format_money(int(amount), currency, true) if amount != null else tr("Not priced"), UiTheme.TEXT, _scaled(15))
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)


func _set_expanded(expanded: bool) -> void:
	_expanded = expanded
	if _details_scroll == null:
		return
	_details_scroll.visible = expanded
	_rebuild_details()
	_layout()
	_details_button.text = tr("Hide damage breakdown") if expanded else tr("Show damage breakdown")
	_layout_retry_frames = 2


func _on_inspect_pressed() -> void:
	if not _terminal or _reopen_only:
		return
	_minimized = true
	_report_panel.visible = false
	_restore_button.visible = true
	_restore_button.grab_focus()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout()
	inspect_requested.emit()


func _reopen_report() -> void:
	if (not _terminal and not _reopen_only) or _suspended:
		return
	_auto_settled = false
	_minimized = false
	_restore_button.visible = false
	_report_panel.visible = true
	_surface.mouse_filter = Control.MOUSE_FILTER_STOP if _terminal and not _archived else Control.MOUSE_FILTER_IGNORE
	_apply_action_visibility()
	if _terminal and not _reopen_only:
		_inspect_button.grab_focus()
	else:
		_hide_archived_button.grab_focus()
	_layout()


func _hide_read_only_report() -> void:
	if not _reopen_only:
		return
	_auto_settled = false
	_minimized = true
	_report_panel.visible = false
	_restore_button.visible = true
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_release_report_focus()
	_layout()


func _on_restart_pressed() -> void:
	if _terminal and not _reopen_only and _report_panel.visible:
		restart_requested.emit()


## Routes controller actions without forcing callers to depend on the current button layout.
## Supported actions are next, previous, accept, cancel, inspect, restart, details, and reopen.
func controller_action(action: String) -> bool:
	if _suspended or _report.is_empty() or not _content_visible or _surface == null or not _surface.visible:
		return false
	match action:
		"navigate_right", "navigate_down": action = "next"
		"navigate_left", "navigate_up": action = "previous"
		"back": action = "cancel"
		"pause": return false # Escape/pause belongs to app_root, even while this card is open.
	var controls := _visible_action_controls()
	if action == "next" or action == "previous":
		if controls.is_empty():
			return false
		var focused := get_viewport().gui_get_focus_owner()
		var index := controls.find(focused)
		if index < 0:
			index = controls.size() - 1 if action == "previous" else 0
		else:
			index = posmod(index + (-1 if action == "previous" else 1), controls.size())
		controls[index].grab_focus()
		return true
	if action == "accept":
		var focused := get_viewport().gui_get_focus_owner()
		if focused == _inspect_button and _terminal and not _reopen_only and _report_panel.visible:
			_on_inspect_pressed()
			return true
		if focused == _restart_button and _terminal and not _reopen_only and _report_panel.visible:
			restart_requested.emit()
			return true
		if focused == _details_button and _report_panel.visible:
			_set_expanded(not _expanded)
			return true
		if focused == _hide_archived_button and _reopen_only and _report_panel.visible:
			_hide_read_only_report()
			return true
		if focused == _restore_button and _restore_button.visible:
			_reopen_report()
			return true
		return false
	if action == "cancel":
		if _reopen_only and _report_panel.visible:
			_hide_read_only_report()
			return true
		if _terminal and not _reopen_only and _report_panel.visible:
			_minimize_terminal_report()
			return true
		return false
	if action == "inspect" and _terminal and not _reopen_only and _report_panel.visible:
		_on_inspect_pressed()
		return true
	if action == "restart" and _terminal and not _reopen_only and _report_panel.visible:
		restart_requested.emit()
		return true
	if action == "details" and _report_panel.visible:
		_set_expanded(not _expanded)
		return true
	if action == "reopen" and _restore_button.visible:
		_reopen_report()
		return true
	return false


## The app routes controller UI actions here only while the report owns a full interactive card.
func wants_controller_menu() -> bool:
	return not _suspended and _surface != null and _surface.visible and _report_panel != null \
		and _report_panel.visible and not _minimized and (_terminal or _reopen_only)


func _minimize_terminal_report() -> void:
	if not _terminal or _reopen_only:
		return
	_minimized = true
	_report_panel.visible = false
	_restore_button.visible = true
	_restore_button.grab_focus()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout()


func _visible_action_controls() -> Array[Control]:
	var controls: Array[Control] = []
	if _restore_button.visible:
		controls.append(_restore_button)
	elif _report_panel.visible:
		if _reopen_only:
			controls.append(_details_button)
			controls.append(_hide_archived_button)
		else:
			controls.append(_inspect_button)
			controls.append(_details_button)
			controls.append(_restart_button)
	return controls


func _apply_action_visibility() -> void:
	if _inspect_button == null:
		return
	_inspect_button.visible = not _reopen_only
	_restart_button.visible = not _reopen_only
	_details_button.visible = not _minimized
	_hide_archived_button.visible = _reopen_only and not _minimized


func _focus_inspect() -> void:
	if _terminal and not _suspended and _report_panel != null and _report_panel.visible:
		_inspect_button.grab_focus()


func _button(text: String, variation: String = "") -> Button:
	var button := Button.new()
	button.text = tr(text)
	button.focus_mode = Control.FOCUS_ALL
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	if variation != "":
		button.theme_type_variation = variation
	return button


func _label(text: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = tr(text)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _card_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.PANEL, 0.98)
	style.border_color = UiTheme.EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	var padding := _scaled(22)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _toast_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UiTheme.PANEL, 0.96)
	style.border_color = UiTheme.EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	var padding := _scaled(14)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style


func _scaled(value: float) -> int:
	var factor := 1.0
	if is_finite(UiTheme.text_scale):
		factor = clampf(UiTheme.text_scale, 0.8, 1.5)
	return maxi(1, roundi(value * factor))


func _interactive_controls() -> Array[Control]:
	return [_inspect_button, _details_button, _restart_button, _hide_archived_button, _restore_button]


func _release_report_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused in _interactive_controls():
		focused.release_focus()


func _currency_code(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return "USD"
	var code := String(value).strip_edges().to_upper()
	if code.is_empty() or code.length() > 8:
		return "USD"
	return code


func _valid_minor(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		var integer_value := int(value)
		return integer_value if integer_value >= -MAX_MINOR_AMOUNT and integer_value <= MAX_MINOR_AMOUNT else null
	if typeof(value) == TYPE_FLOAT:
		var float_value := float(value)
		if is_finite(float_value) and float_value == floor(float_value) and absf(float_value) <= float(MAX_MINOR_AMOUNT):
			return int(float_value)
	return null


func _format_headline_money(minor: int, currency: String) -> String:
	return _format_money(minor, currency, absi(minor) < 10000)


func _has_priced_action(report: Dictionary) -> bool:
	var lines: Variant = report.get("lines", [])
	if not lines is Array:
		return false
	for line_value: Variant in lines:
		if not line_value is Dictionary:
			continue
		var line: Dictionary = line_value
		if _valid_minor(line.get("amount_minor")) != null and str(line.get("action", "")).strip_edges() != "":
			return true
	return false


func _format_money(minor: int, currency: String, cents: bool) -> String:
	var negative := minor < 0
	var absolute_minor := absi(minor)
	var amount_text: String
	if cents:
		var dollars: int = absolute_minor / 100
		var remainder := absolute_minor % 100
		amount_text = _group_digits(str(dollars)) + _decimal_separator() + "%02d" % remainder
	else:
		var dollars_rounded: int = (absolute_minor + 50) / 100
		amount_text = _group_digits(str(dollars_rounded))
	var prefix := "US$" if currency == "USD" else currency + " "
	return ("-" if negative else "") + prefix + amount_text


func _group_digits(digits: String) -> String:
	var thousands := "." if TranslationServer.get_locale().begins_with("es") else ","
	var groups: Array[String] = []
	var remaining := digits
	while remaining.length() > 3:
		groups.push_front(remaining.substr(remaining.length() - 3, 3))
		remaining = remaining.substr(0, remaining.length() - 3)
	groups.push_front(remaining)
	return thousands.join(PackedStringArray(groups))


func _decimal_separator() -> String:
	return "," if TranslationServer.get_locale().begins_with("es") else "."


func _quantity_text(value: Variant) -> String:
	if typeof(value) == TYPE_INT:
		return str(value)
	if typeof(value) == TYPE_FLOAT and is_finite(float(value)):
		return str(float(value))
	return ""


func _action_text(value: Variant) -> String:
	match str(value):
		"repair": return tr("Repair")
		"replace": return tr("Replace")
		"replacement": return tr("Replacement")
		"inspect": return tr("Inspect")
		"inspection": return tr("Inspection")
		"salvage": return tr("Salvage")
		"credit": return tr("Credit")
		"salvage_credit": return tr("Salvage credit")
		_: return str(value).strip_edges()


func _unresolved_text(value: Variant) -> String:
	if value is Dictionary:
		var item_id: String = str(value.get("id", ""))
		var reason: String = str(value.get("reason", ""))
		if reason != "":
			var localized_reason := _localize_reason(reason)
			if item_id != "":
				var item_label := _humanize_identifier(item_id)
				if not localized_reason.begins_with(item_label + " · "):
					return "%s · %s" % [item_label, localized_reason]
			return localized_reason
		if item_id != "":
			return _humanize_identifier(item_id)
		return tr("Unresolved item")
	if str(value).strip_edges() == "":
		return tr("Unresolved item")
	return _localize_reason(str(value))


func _localize_reason(value: String) -> String:
	var translated := tr(value)
	if translated != value:
		return translated
	var parts := value.split(": ", true, 1)
	if parts.size() == 2:
		return "%s · %s" % [_humanize_identifier(parts[0]), tr(parts[1])]
	return translated


func _humanize_identifier(value: String) -> String:
	var identifier := value.strip_edges()
	if identifier.is_empty():
		return tr("Unresolved item")
	var display := str(COMPONENT_LABELS.get(identifier, identifier.replace("_", " ").replace("-", " ")))
	if not display.is_empty():
		display = display.left(1).to_upper() + display.substr(1)
	return tr(display)


func _display_identifier(value: String) -> String:
	if value.contains("_") or (value.contains("-") and not value.contains(" ")):
		return _humanize_identifier(value)
	return value
