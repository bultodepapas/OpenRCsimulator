# CR-32: report math labels, persistent terminal state, nonterminal input/focus, responsive bounds and details.
# Run: godot --headless --path . --script res://tests/test_accident_report.gd
extends SceneTree

const AccidentReport := preload("res://ui/accident_report.gd")
const UiDriver := preload("res://tests/ui_driver.gd")


class KeyProbe extends Node:
	var key_count := 0

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed:
			key_count += 1


var _failures := 0
var _checks := 0
var _ui: RefCounted


func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	TranslationServer.set_locale("en")
	_ui = UiDriver.new(self)
	_run()


func _run() -> void:
	_layout_bounds()
	await _report_behavior()
	print("accident report: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(label: String, ok: bool, detail: String = "") -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _layout_bounds() -> void:
	for size: Vector2 in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(3840.0, 2160.0)]:
		var metrics: Dictionary = AccidentReport.layout_metrics(size, 1.0)
		var gutter := float(metrics.gutter)
		var panel_width := float(metrics.panel_width)
		var max_height := float(metrics.max_panel_height)
		var bounded_panel := Rect2(Vector2((size.x - panel_width) * 0.5, gutter), Vector2(panel_width, max_height))
		_check("panel stays inside %dx%d viewport" % [int(size.x), int(size.y)],
			bounded_panel.position.x >= 0.0 and bounded_panel.position.y >= 0.0
			and bounded_panel.end.x <= size.x and bounded_panel.end.y <= size.y, str(bounded_panel))
		_check("comfortable gutter at %dx%d" % [int(size.x), int(size.y)], gutter >= 20.0 and panel_width <= size.x - 2.0 * gutter)
		var minimum_scale: Dictionary = AccidentReport.layout_metrics(size, 0.8)
		_check("headline remains readable at the smallest supported text scale for %dx%d" % [int(size.x), int(size.y)],
			int(minimum_scale.headline_size) >= 32)
	var default_720: Dictionary = AccidentReport.layout_metrics(Vector2(1280.0, 720.0), 1.0)
	_check("720p headline uses the requested 48–64 px design range", int(default_720.headline_size) >= 48 and int(default_720.headline_size) <= 64,
		str(default_720.headline_size))


func _report_behavior() -> void:
	var probe := KeyProbe.new()
	probe.name = "UnderlyingFlightInputProbe"
	root.add_child(probe)
	var external_focus := Button.new()
	external_focus.name = "ExternalFocus"
	external_focus.focus_mode = Control.FOCUS_ALL
	root.add_child(external_focus)
	await _ui.settle()
	external_focus.grab_focus()
	await _ui.settle()

	var report := AccidentReport.new()
	root.add_child(report)
	await _ui.settle()
	_check("no report panel appears before an assessment", not report.find_child("AccidentReportSurface", true, false).visible
		and not report.find_child("AccidentReportCard", true, false).visible)

	var partial: Dictionary = {
		"currency": "USD",
		"known_subtotal_minor": 98765,
		"low_minor": null,
		"high_minor": null,
		"total_minor": 1234567,
		"complete": false,
		"valuation_kind": "catalog_snapshot",
		"outcome": "repair",
		"lines": [
			{"id": "propeller", "quantity": 1, "action": "replace", "amount_minor": 125050},
			{"id": "thermal_review", "quantity": 1, "action": "inspect", "amount_minor": NAN},
		],
		"salvage_minor": null,
		"replacement_minor": null,
		"unresolved": ["post-impact inspection"],
		"price_date": "2026-10-15",
	}
	var original_line_count: int = partial.lines.size()
	report.show_assessment(partial, false)
	await _ui.settle()
	_check("nonterminal report is a small toast", report.find_child("AccidentToast", true, false).visible
		and not report.find_child("AccidentReportCard", true, false).visible)
	_check("nonterminal notification does not move focus", _ui.focus_name() == "ExternalFocus", _ui.focus_name())
	_check("toast does not claim the controller menu", not report.wants_controller_menu())
	_check("nonterminal notification leaves flight keyboard input available", probe.key_count == 0)
	await _ui.tap(KEY_G)
	_check("nonterminal notification passes unhandled keys through", probe.key_count > 0, str(probe.key_count))
	_check("incomplete subtotal is explicitly labeled", report.find_child("ReportAmount", true, false).text == "US$988"
		and report.find_child("DamageBreakdown", true, false).text == "Show damage breakdown"
		and (report.find_child("ReportColumn", true, false).get_child(1) as Label).text == "KNOWN SUBTOTAL · INCOMPLETE")
	_check("incomplete total_minor is never presented as a total", not report.find_child("ReportAmount", true, false).text.contains("12,345"))
	_check("non-finite amounts do not leak into the collapsed headline", not report.find_child("ReportAmount", true, false).text.to_lower().contains("nan"))
	_check("the report reads its snapshot without mutating the source", partial.lines.size() == original_line_count
		and partial.total_minor == 1234567 and is_nan(float(partial.lines[1].amount_minor)))
	var range_report: Dictionary = partial.duplicate(true)
	range_report.known_subtotal_minor = null
	range_report.low_minor = 25025
	range_report.high_minor = 37499
	report.show_assessment(range_report, false)
	_check("incomplete bounds are shown as an explicit range", report.find_child("ReportAmount", true, false).text == "US$250 – US$375"
		and (report.find_child("ReportColumn", true, false).get_child(1) as Label).text == "INCOMPLETE ESTIMATE RANGE")
	var replacement_ceiling := range_report.duplicate(true)
	replacement_ceiling.known_subtotal_minor = null
	replacement_ceiling.low_minor = null
	replacement_ceiling.high_minor = null
	replacement_ceiling.replacement_quote_low_minor = 120000
	replacement_ceiling.replacement_quote_high_minor = 133134
	replacement_ceiling.replacement_quote_scope = "complete_build_replacement_quote_comparison"
	report.show_assessment(replacement_ceiling, true)
	report.controller_action("details")
	_check("replacement quote ceiling is never presented as a repair estimate", report.find_child("ReportAmount", true, false).text == "Cost unavailable"
		and not report.find_child("ReportAmount", true, false).text.contains("Up to")
		and _details_text(report).contains("Complete-build replacement quote comparison")
		and _details_text(report).contains("US$1,200.00") and _details_text(report).contains("US$1,331.34"), _details_text(report))
	var unknown: Dictionary = range_report.duplicate(true)
	unknown.low_minor = null
	unknown.high_minor = null
	unknown.total_minor = null
	report.show_assessment(unknown, false)
	external_focus.grab_focus()
	_check("missing values are reported as unknown instead of zero", report.find_child("ReportAmount", true, false).text == "Cost unavailable"
		and not report.find_child("ReportAmount", true, false).text.contains("$0"))
	var zero_without_actions: Dictionary = unknown.duplicate(true)
	zero_without_actions.known_subtotal_minor = 0
	zero_without_actions.low_minor = 0
	zero_without_actions.high_minor = 0
	zero_without_actions.lines = []
	report.show_assessment(zero_without_actions, false)
	_check("an unsupported zero subtotal and zero range are reported as unknown", report.find_child("ReportAmount", true, false).text == "Cost unavailable"
		and (report.find_child("ReportColumn", true, false).get_child(1) as Label).text == "AMOUNT UNKNOWN")
	report._process(6.0)
	_check("expired nonterminal toast leaves a persistent view-only reopen control", report.find_child("ReopenAccidentReport", true, false).visible
		and not report.find_child("AccidentToast", true, false).visible
		and report.find_child("AccidentReportSurface", true, false).mouse_filter == Control.MOUSE_FILTER_IGNORE
		and _ui.focus_name() == "ExternalFocus"
		and not report.wants_controller_menu())
	_check("nonterminal report can be reopened without inspect or restart", report.controller_action("reopen")
		and report.find_child("AccidentReportCard", true, false).visible
		and not report.find_child("InspectWreck", true, false).visible
		and not report.find_child("RestartFlight", true, false).visible
		and report.wants_controller_menu())
	_check("expanded view marks non-finite line amounts as unpriced", report.controller_action("details")
		and _details_text(report).contains("Not priced") and not _details_text(report).to_lower().contains("nan"), _details_text(report))
	_check("view-only damage report can return to its reopen control", report.controller_action("cancel")
		and report.find_child("ReopenAccidentReport", true, false).visible
		and not report.wants_controller_menu())

	var restart_events: Array[String] = []
	var inspect_events: Array[String] = []
	report.restart_requested.connect(func() -> void: restart_events.append("restart"))
	report.inspect_requested.connect(func() -> void: inspect_events.append("inspect"))
	var complete: Dictionary = {
		"identity": {"aircraft_id": "trainer-v2", "incident_id": "evt-007"},
		"currency": "USD",
		"known_subtotal_minor": 125050,
		"total_minor": 125050,
		"low_minor": null,
		"high_minor": null,
		"complete": true,
		"valuation_kind": "catalog_snapshot",
		"outcome": "repair",
		"lines": [
			{"id": "propeller", "quantity": 1, "action": "replace", "amount_minor": 125050},
			{"id": "spare_motor", "quantity": 2, "action": "replacement", "amount_minor": 0},
			{"id": "servo", "quantity": 1, "action": "salvage_credit", "amount_minor": -500},
		],
		"salvage_minor": null,
		"replacement_minor": null,
		"unresolved": [],
		"price_date": "2026-10-15",
	}
	report.show_assessment(complete, true)
	await _ui.settle()
	_check_live_panel_bounds(report, "collapsed terminal card")
	_check("terminal report takes keyboard focus on Inspect and owns controller menu", _ui.focus_name() == "InspectWreck"
		and report.wants_controller_menu(), _ui.focus_name())
	_check("complete total uses rounded whole dollars as the headline", report.find_child("ReportAmount", true, false).text == "US$1,251")
	var low_repair: Dictionary = complete.duplicate(true)
	low_repair.total_minor = 539
	low_repair.known_subtotal_minor = 539
	low_repair.lines = [{"id": "propeller", "quantity": 1, "action": "replace", "amount_minor": 539}]
	report.show_assessment(low_repair, true)
	_check("small repair headline preserves cents", report.find_child("ReportAmount", true, false).text == "US$5.39")
	var missing_complete_total: Dictionary = low_repair.duplicate(true)
	missing_complete_total.total_minor = null
	report.show_assessment(missing_complete_total, true)
	_check("missing complete total falls back to a clearly partial subtotal", report.find_child("ReportAmount", true, false).text == "US$5.39"
		and (report.find_child("ReportColumn", true, false).get_child(1) as Label).text == "KNOWN SUBTOTAL · INCOMPLETE")
	var invalid_total: Dictionary = missing_complete_total.duplicate(true)
	invalid_total.known_subtotal_minor = null
	invalid_total.lines = []
	invalid_total.total_minor = NAN
	report.show_assessment(invalid_total, true)
	_check("non-finite total is shown as unavailable instead of NaN", report.find_child("ReportAmount", true, false).text == "Amount unavailable"
		and not report.find_child("ReportAmount", true, false).text.to_lower().contains("nan"))
	report.show_assessment(complete, true)
	await _ui.settle()
	var breakdown_button := report.find_child("DamageBreakdown", true, false) as Button
	_check("controller navigation reaches the details action", report.controller_action("next") and _ui.focus_name() == "DamageBreakdown")
	_check("controller accept expands the breakdown", report.controller_action("accept")
		and report.find_child("DamageDetailsScroll", true, false).visible)
	await _ui.settle()
	_check_live_panel_bounds(report, "expanded terminal card")
	_check("expanded breakdown retains cents, price date, estimate caveat, identity, quantity, and actions", _details_text(report).contains("US$1,250.50")
		and _details_text(report).contains("2026-10-15") and _details_text(report).contains("Market prices")
		and _details_text(report).contains("Aircraft: trainer-v2") and _details_text(report).contains("Incident: evt-007")
		and _details_text(report).contains("Replacement") and _details_text(report).contains("Salvage credit")
		and _details_text(report).contains("× 2"), _details_text(report))
	_check("expanded details switch to the collapse action", report.find_child("DamageDetailsScroll", true, false).visible
		and breakdown_button.text == "Hide damage breakdown")
	var restart_button := report.find_child("RestartFlight", true, false) as Button
	restart_button.pressed.emit()
	_check("Restart button signal emits and keeps the report open for caller handling", restart_events.size() == 1
		and report.find_child("AccidentReportCard", true, false).visible, "count=%d focus=%s" % [restart_events.size(), _ui.focus_name()])
	_check("controller restart emits the same signal", report.controller_action("restart") and restart_events.size() == 2)
	var inspect_button := report.find_child("InspectWreck", true, false) as Button
	inspect_button.pressed.emit()
	_check("Inspect emits its signal and minimizes to a visible reopen control", inspect_events.size() == 1
		and report.find_child("ReopenAccidentReport", true, false).visible
		and not report.find_child("AccidentReportCard", true, false).visible,
		"count=%d reopen=%s focus=%s" % [inspect_events.size(), str(report.find_child("ReopenAccidentReport", true, false).visible), _ui.focus_name()])
	_check("minimized report yields the controller menu", not report.wants_controller_menu())
	var reopen_button := report.find_child("ReopenAccidentReport", true, false) as Button
	_check("inspect-minimized camera controls pass through", await _key_reaches_probe(probe, KEY_G))
	_check("controller accept reopens the terminal report", report.controller_action("accept"))
	_check("reopen restores the persistent report", report.find_child("AccidentReportCard", true, false).visible
		and not reopen_button.visible and report.wants_controller_menu())
	_check("controller navigation aliases move through the report actions", report.controller_action("navigate_down")
		and _ui.focus_name() == "DamageBreakdown"
		and report.controller_action("navigate_right") and _ui.focus_name() == "RestartFlight"
		and report.controller_action("navigate_up") and _ui.focus_name() == "DamageBreakdown"
		and report.controller_action("navigate_left") and _ui.focus_name() == "InspectWreck")
	_check("controller back collapses to the reopen control and yields the menu", report.controller_action("back")
		and reopen_button.visible and not report.wants_controller_menu())
	_check("controller accept restores a collapsed report", report.controller_action("accept")
		and report.find_child("AccidentReportCard", true, false).visible and report.wants_controller_menu())
	_check("controller pause is left to the parent", not report.controller_action("pause")
		and report.find_child("AccidentReportCard", true, false).visible)
	_check("Escape reaches the parent pause handler", await _key_reaches_probe(probe, KEY_ESCAPE))
	_check("R reaches the parent explicit-restart handler", await _key_reaches_probe(probe, KEY_R))
	report.suspend(true)
	_check("suspend hides the report and removes focus", not report.find_child("AccidentReportSurface", true, false).visible and inspect_button.focus_mode == Control.FOCUS_NONE
		and restart_button.focus_mode == Control.FOCUS_NONE)
	report.suspend(false)
	_check("resume restores the report and controller focus eligibility", report.find_child("AccidentReportSurface", true, false).visible
		and inspect_button.focus_mode == Control.FOCUS_ALL and restart_button.focus_mode == Control.FOCUS_ALL)
	external_focus.grab_focus()
	await _ui.settle()
	report.show_archived(complete)
	await _ui.settle()
	_check("archived report starts as one nonmodal reopen control without taking focus", report.find_child("ReopenAccidentReport", true, false).visible
		and not report.find_child("AccidentReportCard", true, false).visible and report.find_child("AccidentReportSurface", true, false).mouse_filter == Control.MOUSE_FILTER_IGNORE
		and _ui.focus_name() == "ExternalFocus" and not report.wants_controller_menu())
	_check("archived report does not offer inspect or restart", not inspect_button.visible and not restart_button.visible)
	_check("controller reopens archived report as read-only", report.controller_action("reopen")
		and report.find_child("AccidentReportCard", true, false).visible
		and not inspect_button.visible and not restart_button.visible
		and report.find_child("HideArchivedReport", true, false).visible and report.wants_controller_menu())
	_check("archived report cannot restart or inspect", not report.controller_action("restart") and not report.controller_action("inspect")
		and restart_events.size() == 2 and inspect_events.size() == 1)
	_check("controller details and cancel work for the archived report", report.controller_action("details")
		and report.find_child("DamageDetailsScroll", true, false).visible and report.controller_action("cancel")
		and report.find_child("ReopenAccidentReport", true, false).visible)
	report.clear_report()
	_check("clear_report removes the report intentionally", not report.find_child("AccidentReportSurface", true, false).visible
		and not report.find_child("ReopenAccidentReport", true, false).visible)
	root.remove_child(report)
	report.free()
	root.remove_child(external_focus)
	external_focus.free()
	root.remove_child(probe)
	probe.free()
	await _ui.settle()


func _key_reaches_probe(probe: KeyProbe, key: Key) -> bool:
	var previous := probe.key_count
	await _ui.tap(key)
	return probe.key_count > previous


func _details_text(report: Node) -> String:
	var details := report.find_child("DamageDetails", true, false)
	var parts: PackedStringArray = []
	for node: Node in _collect_nodes(details):
		if node is Label:
			parts.append((node as Label).text)
	return " ".join(parts)


func _check_live_panel_bounds(report: Node, label: String) -> void:
	var panel := report.find_child("AccidentReportCard", true, false) as Control
	var rect := panel.get_global_rect()
	var viewport_size := report.get_viewport().get_visible_rect().size
	_check("%s actual bounds fit the live viewport" % label,
		rect.position.x >= 0.0 and rect.position.y >= 0.0
		and rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y,
		"panel=%s viewport=%s" % [str(rect), str(viewport_size)])


func _collect_nodes(parent: Node) -> Array[Node]:
	var result: Array[Node] = []
	if parent == null:
		return result
	for child: Node in parent.get_children():
		result.append(child)
		result.append_array(_collect_nodes(child))
	return result
