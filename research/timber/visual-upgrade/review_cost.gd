## TT-20 read-only layout review of a deterministic Turbo Lumber cost report.
## The report is manufactured by the current Incident + Catalog path using the same
## propeller-strike fixture pattern as test_economy_cr39.gd; no amount is authored here.
extends SceneTree

const Incident := preload("res://economy/incident.gd")
const AccidentReport := preload("res://ui/accident_report.gd")
const UiTheme := preload("res://ui/ui_theme.gd")

var _out := ""
var _locale := "en"
var _viewport := Vector2i(1600, 1000)
var _scale := 1.0
var _failures: Array[String] = []


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--review-out="):
			_out = arg.trim_prefix("--review-out=")
		elif arg.begins_with("--locale="):
			_locale = arg.trim_prefix("--locale=")
		elif arg.begins_with("--viewport="):
			var dimensions := arg.trim_prefix("--viewport=").split("x")
			if dimensions.size() == 2:
				_viewport = Vector2i(int(dimensions[0]), int(dimensions[1]))
		elif arg.begins_with("--text-scale="):
			_scale = float(arg.trim_prefix("--text-scale="))
	_run.call_deferred()


func _run() -> void:
	if _out.is_empty() or _viewport.x <= 0 or _viewport.y <= 0:
		push_error("Pass a valid --review-out and positive --viewport")
		quit(2)
		return
	var absolute_out := ProjectSettings.globalize_path(_out) if not _out.is_absolute_path() else _out
	DirAccess.make_dir_recursive_absolute(absolute_out)
	root.size = _viewport
	DisplayServer.window_set_size(_viewport)
	RenderingServer.set_default_clear_color(Color("#202d33"))
	TranslationServer.set_locale(_locale)
	UiTheme.text_scale = _scale

	# This mirrors the deterministic lumber propeller-strike test in test_economy_cr39.gd.
	# Incident.begin loads the current route dossier/catalog; its calculator supplies every amount.
	var incident := Incident.new()
	incident.begin("turbo-lumber-evolution", "")
	if incident.dossier.is_empty():
		_failures.append("current Turbo Lumber catalog dossier did not load: %s" % str(incident._catalog_errors))
		_write_failure(absolute_out)
		quit(1)
		return
	incident._mark_propeller()
	incident._queue_assessment(1)
	incident.evaluate_pending()
	var report: Dictionary = incident.report.duplicate(true)
	if report.is_empty() or str(report.get("identity", {}).get("aircraft_id", "")) != "turbo-lumber-evolution":
		_failures.append("Incident did not produce a report with Turbo Lumber identity")
		_write_failure(absolute_out)
		quit(1)
		return
	var before_json := JSON.stringify(incident.report, "", true, true)
	var money_before := _amount_snapshot(incident.report)

	var view := AccidentReport.new()
	root.add_child(view)
	view.show_assessment(report, true)
	view.controller_action("details")
	await process_frame
	await process_frame
	view._layout()
	await process_frame
	await RenderingServer.frame_post_draw

	var image := root.get_texture().get_image()
	if image == null or image.get_width() != _viewport.x or image.get_height() != _viewport.y:
		_failures.append("capture texture dimensions differ from requested viewport: %s" % str(image.get_size() if image != null else Vector2i.ZERO))
	else:
		var png_path := absolute_out.path_join("cost-report.png")
		if image.save_png(png_path) != OK:
			_failures.append("could not save capture PNG: " + png_path)

	var panel := view.find_child("AccidentReportCard", true, false) as Control
	var scroll := view.find_child("DamageDetailsScroll", true, false) as Control
	var viewport_rect := Rect2(Vector2.ZERO, Vector2(_viewport))
	if panel == null or not panel.visible:
		_failures.append("expanded accident report card is not visible")
	else:
		_check_rect("report card", panel.get_global_rect(), viewport_rect)
	if scroll == null or not scroll.visible:
		_failures.append("expanded damage details scroll area is not visible")
	else:
		_check_rect("damage details viewport", scroll.get_global_rect(), viewport_rect)
	for control_name: String in ["InspectWreck", "DamageBreakdown", "RestartFlight"]:
		var control := view.find_child(control_name, true, false) as Control
		if control != null and control.visible:
			var rect := control.get_global_rect()
			_check_rect(control_name, rect, viewport_rect)
			if panel != null and (rect.position.x < panel.get_global_rect().position.x - 1.0
				or rect.end.x > panel.get_global_rect().end.x + 1.0
				or rect.position.y < panel.get_global_rect().position.y - 1.0
				or rect.end.y > panel.get_global_rect().end.y + 1.0):
				_failures.append("visible action control lies outside report card: %s %s" % [control_name, str(rect)])
	_audit_non_scrolled_controls(view, viewport_rect, panel, scroll)

	var money_after := _amount_snapshot(incident.report)
	var after_json := JSON.stringify(incident.report, "", true, true)
	var headline_before := money_before
	var headline_after := _amount_snapshot(view._report)
	if before_json != after_json or money_before != money_after or money_before != headline_after:
		_failures.append("opening the view or expanding details changed report or amount state")
	var amount_label := view.find_child("ReportAmount", true, false) as Label
	var amount_text_before := amount_label.text if amount_label != null else ""
	view.controller_action("details")
	await process_frame
	if amount_label != null and amount_label.text != amount_text_before:
		_failures.append("toggling expanded details changed the displayed headline amount")
	view.controller_action("details")
	await process_frame
	if money_before != _amount_snapshot(incident.report) or before_json != JSON.stringify(incident.report, "", true, true):
		_failures.append("second expansion toggle changed the source incident report")

	var manifest := {
		"format": "openrc-timber-cost-review v1",
		"fixture": "Manufactured deterministic propeller-strike scenario using Incident.begin(turbo-lumber-evolution), Incident._mark_propeller(), and the current Catalog/Calculator; follows the existing test_economy_cr39.gd pattern. No amount fields are authored or overridden by this capture script.",
		"aircraft_id": report.get("identity", {}).get("aircraft_id", ""),
		"incident_id": report.get("incident_id", ""),
		"catalog_hash": report.get("catalog_hash", ""),
		"locale": _locale,
		"requested_text_scale": _scale,
		"effective_text_scale": clampf(_scale, 0.8, 1.5),
		"text_scale_cap": 1.5,
		"viewport": [_viewport.x, _viewport.y],
		"expanded": bool(view._expanded),
		"report_amount_state_before": money_before,
		"report_amount_state_after": money_after,
		"headline": amount_text_before,
		"card_rect": _rect_json(panel),
		"details_scroll_rect": _rect_json(scroll),
		"action_rects": _action_rects(view),
		"offscreen_failures": _failures.duplicate(),
		"screenshot": "cost-report.png",
	}
	FileAccess.open(absolute_out.path_join("review.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t") + "\n")
	print("TT-20 cost display review: %s %dx%d, scale %.2f, %d failures" % [_locale, _viewport.x, _viewport.y, _scale, _failures.size()])
	quit(0 if _failures.is_empty() else 1)


func _amount_snapshot(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in ["currency", "total_minor", "known_subtotal_minor", "low_minor", "high_minor", "complete", "outcome", "replacement_minor", "salvage_minor", "lines"]:
		result[key] = value.get(key)
	return result


func _check_rect(name: String, rect: Rect2, viewport_rect: Rect2) -> void:
	if rect.position.x < -1.0 or rect.position.y < -1.0 \
		or rect.end.x > viewport_rect.end.x + 1.0 or rect.end.y > viewport_rect.end.y + 1.0:
		_failures.append("%s is outside viewport: %s" % [name, str(rect)])


func _audit_non_scrolled_controls(node: Node, viewport_rect: Rect2, panel: Control, scroll: Control) -> void:
	if node is Control:
		var control := node as Control
		if control.is_visible_in_tree() and not _has_scrolled_ancestor(control, scroll):
			var rect := control.get_global_rect()
			_check_rect(str(control.get_path()), rect, viewport_rect)
			if panel != null and control != panel and _is_descendant_of(control, panel):
				var panel_rect := panel.get_global_rect()
				if rect.position.x < panel_rect.position.x - 1.0 or rect.end.x > panel_rect.end.x + 1.0 \
					or rect.position.y < panel_rect.position.y - 1.0 or rect.end.y > panel_rect.end.y + 1.0:
					_failures.append("visible report control lies outside card: %s %s" % [str(control.name), str(rect)])
	for child: Node in node.get_children():
		_audit_non_scrolled_controls(child, viewport_rect, panel, scroll)


func _has_scrolled_ancestor(control: Control, scroll: Control) -> bool:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor == scroll:
			return true
		ancestor = ancestor.get_parent()
	return false


func _is_descendant_of(control: Control, ancestor: Control) -> bool:
	var parent := control.get_parent()
	while parent != null:
		if parent == ancestor:
			return true
		parent = parent.get_parent()
	return false


func _rect_json(control: Control) -> Array:
	if control == null:
		return []
	var rect := control.get_global_rect()
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _action_rects(view: Node) -> Dictionary:
	var result: Dictionary = {}
	for control_name: String in ["InspectWreck", "DamageBreakdown", "RestartFlight"]:
		var control := view.find_child(control_name, true, false) as Control
		if control != null and control.visible:
			result[control_name] = _rect_json(control)
	return result


func _write_failure(absolute_out: String) -> void:
	FileAccess.open(absolute_out.path_join("failure.txt"), FileAccess.WRITE).store_string("\n".join(_failures) + "\n")
