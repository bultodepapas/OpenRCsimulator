extends SceneTree

## Native 1280x720 composition capture for the standalone accident report overlay.
## Run with Godot --path app --script ../research/crash-economics/capture_report.gd -- --out=<png>.
const AccidentReport := preload("res://ui/accident_report.gd")
const UiTheme := preload("res://ui/ui_theme.gd")
const Calculator := preload("res://economy/calculator.gd")
const Catalog := preload("res://economy/catalog.gd")
const ReplacementQuote := preload("res://economy/replacement_quote.gd")


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var output_path := "user://cr32-accident-report.png"
	var language := "en"
	var requested_size := Vector2i(1280, 720)
	var requested_scale := 1.0
	var expanded := false
	var scroll_to_bottom := false
	var show_parts_comparison := false
	var show_price_sources := false
	var settled := false
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_path = argument.trim_prefix("--out=")
		elif argument.begins_with("--lang="):
			language = argument.trim_prefix("--lang=")
		elif argument.begins_with("--size="):
			var dimensions := argument.trim_prefix("--size=").split("x")
			if dimensions.size() != 2 or not dimensions[0].is_valid_int() or not dimensions[1].is_valid_int():
				push_error("Capture size must be WIDTHxHEIGHT")
				quit(ERR_INVALID_PARAMETER)
				return
			requested_size = Vector2i(int(dimensions[0]), int(dimensions[1]))
		elif argument.begins_with("--scale="):
			requested_scale = argument.trim_prefix("--scale=").to_float()
		elif argument == "--details":
			expanded = true
		elif argument == "--parts-comparison":
			expanded = true
			show_parts_comparison = true
		elif argument == "--price-sources":
			expanded = true
			show_price_sources = true
		elif argument == "--settled":
			settled = true
		elif argument == "--details-bottom":
			expanded = true
			scroll_to_bottom = true
	if language not in ["en", "es"] or requested_size.x < 640 or requested_size.y < 480 \
		or not is_finite(requested_scale) or requested_scale < 0.8 or requested_scale > 1.5:
		push_error("Capture needs en/es, a viewport of at least 640x480, and a scale from 0.8 to 1.5")
		quit(ERR_INVALID_PARAMETER)
		return
	root.size = requested_size
	root.content_scale_size = requested_size
	DisplayServer.window_set_size(requested_size)
	UiTheme.text_scale = requested_scale
	TranslationServer.set_locale(language)

	var backdrop := ColorRect.new()
	backdrop.name = "CaptureBackdrop"
	backdrop.color = Color("26323c")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(backdrop)
	var horizon := ColorRect.new()
	horizon.name = "CaptureHorizon"
	horizon.color = Color("37454a")
	horizon.anchor_top = 0.64
	horizon.anchor_bottom = 1.0
	horizon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE)
	# Keep the horizon as a shallow lower strip, leaving most of the scene visible above the report.
	horizon.anchor_top = 0.64
	horizon.anchor_bottom = 1.0
	horizon.offset_top = 0.0
	horizon.offset_bottom = 0.0
	root.add_child(horizon)

	var report := AccidentReport.new()
	root.add_child(report)
	await process_frame
	var loaded: Dictionary = Catalog.load_for("jensen-das-ugly-stik-60")
	if not bool(loaded.get("ok", false)):
		push_error("Could not load the baseline Stik economic dossier: %s" % str(loaded.get("errors", [])))
		quit(1)
		return
	var dossier: Dictionary = loaded.get("dossier", {})
	var scenario_components: Dictionary = {"propeller": {"disposition": "replace"}}
	for inspection_id: Variant in dossier.get("propeller_inspection_ids", []):
		scenario_components[str(inspection_id)] = {"disposition": "inspect"}
	var assessment := {
		"components": scenario_components,
		"terminal": not settled,
		"total_loss": false,
		"unresolved": ["Propeller strike: inspect the powertrain, shaft and mount before return to service."],
	}
	var report_data: Dictionary = Calculator.calculate(dossier, assessment)
	if show_parts_comparison:
		report_data.replacement_comparison = ReplacementQuote.quote(dossier, assessment)
	if not bool(report_data.get("ok", false)) or report_data.get("known_subtotal_minor") != 539 \
		or report_data.get("low_minor") != 539 or report_data.get("high_minor") != null \
		or report_data.get("total_minor") != null or bool(report_data.get("complete", true)) \
		or str(report_data.get("outcome", "")) != "inspection":
		push_error("The prop-strike capture report does not match the incomplete lower-bound baseline case: %s" % str(report_data))
		quit(1)
		return
	var components_by_id: Dictionary = {}
	for component_value: Variant in dossier.get("components", []):
		if component_value is Dictionary:
			components_by_id[str(component_value.get("id", ""))] = component_value
	var offer_sources: Dictionary = loaded.get("offer_sources", {})
	var enriched_lines: Array = []
	for line_value: Variant in report_data.get("lines", []):
		if not line_value is Dictionary:
			continue
		var line: Dictionary = line_value.duplicate(true)
		var component: Dictionary = components_by_id.get(str(line.get("id", "")), {})
		line["notes"] = str(component.get("notes", ""))
		var offer_id := str(component.get("offer_id", ""))
		if offer_sources.has(offer_id):
			var source: Dictionary = offer_sources[offer_id]
			line["source_url"] = str(source.get("source_url", ""))
			line["observed_on"] = str(source.get("observed_on", ""))
			line["availability"] = str(source.get("availability", ""))
		enriched_lines.append(line)
	report_data["lines"] = enriched_lines
	report_data["aircraft_name"] = "Jensen Das Ugly Stik 60"
	if settled:
		report.show_settled(report_data)
	else:
		report.show_assessment(report_data, true)
	if expanded:
		report.controller_action("details")
	for frame_index: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw

	var viewport := root.get_viewport()
	var panel := report.find_child("AccidentReportCard", true, false) as Control
	var size_checks: Array[Dictionary] = []
	for check_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3840, 2160)]:
		root.size = check_size
		root.content_scale_size = check_size
		DisplayServer.window_set_size(check_size)
		for frame_index: int in 3:
			await process_frame
		report._layout()
		await process_frame
		var viewport_size_at_check := viewport.get_visible_rect().size
		var panel_rect_at_check := panel.get_global_rect()
		var panel_fits_at_check := panel_rect_at_check.position.x >= 0.0 and panel_rect_at_check.position.y >= 0.0 \
			and panel_rect_at_check.end.x <= viewport_size_at_check.x and panel_rect_at_check.end.y <= viewport_size_at_check.y
		var checks: Dictionary = {"requested_size": [check_size.x, check_size.y],
			"viewport_size": [viewport_size_at_check.x, viewport_size_at_check.y],
			"panel_rect": [panel_rect_at_check.position.x, panel_rect_at_check.position.y,
				panel_rect_at_check.size.x, panel_rect_at_check.size.y], "panel_fits_viewport": panel_fits_at_check}
		var action_bounds_fit := true
		for action_name: String in ["InspectWreck", "DamageBreakdown", "RestartFlight", "HideArchivedReport"]:
			var action_control := report.find_child(action_name, true, false) as Control
			if action_control.visible:
				var action_rect := action_control.get_global_rect()
				if action_rect.position.x < panel_rect_at_check.position.x or action_rect.position.y < panel_rect_at_check.position.y \
					or action_rect.end.x > panel_rect_at_check.end.x or action_rect.end.y > panel_rect_at_check.end.y:
					action_bounds_fit = false
		checks["action_bounds_fit"] = action_bounds_fit
		size_checks.append(checks)
	root.size = requested_size
	root.content_scale_size = requested_size
	DisplayServer.window_set_size(requested_size)
	for frame_index: int in 3:
		await process_frame
	report._layout()
	await process_frame
	if scroll_to_bottom:
		var details_scroll := report.find_child("DamageDetailsScroll", true, false) as ScrollContainer
		var details_bar := details_scroll.get_v_scroll_bar()
		details_scroll.scroll_vertical = int(details_bar.max_value)
		await process_frame
	elif show_parts_comparison or show_price_sources:
		var details_scroll := report.find_child("DamageDetailsScroll", true, false) as ScrollContainer
		var target_text: String = report.tr("Observed: %s") % "2026-10-15" if show_price_sources else report.tr("Replacement parts comparison")
		for child: Node in report._details_content.get_children():
			if child is Label and child.text == target_text:
				details_scroll.scroll_vertical = int(child.position.y)
				break
		await process_frame
	var panel_rect := panel.get_global_rect()
	var viewport_size := viewport.get_visible_rect().size
	var image := viewport.get_texture().get_image()
	var image_error := image.save_png(output_path)
	var panel_fits := panel_rect.position.x >= 0.0 and panel_rect.position.y >= 0.0 \
		and panel_rect.end.x <= viewport_size.x and panel_rect.end.y <= viewport_size.y
	var all_size_checks_pass := true
	for size_check: Dictionary in size_checks:
		all_size_checks_pass = all_size_checks_pass and bool(size_check.panel_fits_viewport) and bool(size_check.action_bounds_fit)
	var detail_bounds_fit := true
	var detail_rect := Rect2()
	if expanded:
		var detail_panel := report.find_child("DamageDetailsScroll", true, false) as Control
		detail_rect = detail_panel.get_global_rect()
		detail_bounds_fit = detail_rect.position.y >= panel_rect.position.y \
			and detail_rect.end.y <= panel_rect.end.y and detail_rect.size.y <= 270.0 + 1.0
	if image_error != OK or not panel_fits or not all_size_checks_pass or not detail_bounds_fit:
		push_error("Accident report capture failed: image=%d panel=%s viewport=%s" % [image_error, panel_rect, viewport_size])
		print(JSON.stringify({"size_checks": size_checks, "panel_fits": panel_fits,
			"all_size_checks_pass": all_size_checks_pass, "detail_bounds_fit": detail_bounds_fit,
			"detail_rect": [detail_rect.position.x, detail_rect.position.y, detail_rect.size.x, detail_rect.size.y]}))
		quit(1)
		return
	var amount := (report.find_child("ReportAmount", true, false) as Label).text
	var evidence := {
		"format": "openrc-cr32-accident-report-capture-v1",
		"image": output_path.get_file(),
		"requested_size": [requested_size.x, requested_size.y],
		"image_size": [image.get_width(), image.get_height()],
		"locale": language,
		"presentation": "settled" if settled else "terminal",
		"text_scale": requested_scale,
		"details_expanded": expanded,
		"details_scrolled_to_bottom": scroll_to_bottom,
		"parts_comparison": report_data.get("replacement_comparison", {}),
		"price_sources_visible": show_price_sources,
		"aircraft_id": "jensen-das-ugly-stik-60",
		"known_subtotal_minor": report_data.get("known_subtotal_minor"),
		"complete": report_data.get("complete"),
		"total_minor": report_data.get("total_minor"),
		"outcome": report_data.get("outcome"),
		"panel_rect": [panel_rect.position.x, panel_rect.position.y, panel_rect.size.x, panel_rect.size.y],
		"panel_fits_viewport": panel_fits,
		"action_bounds_fit": true,
		"detail_bounds_fit": detail_bounds_fit,
		"viewport_size_bounds_checks": size_checks,
		"headline": amount,
		"headline_font_size": (report.find_child("ReportAmount", true, false) as Label).get_theme_font_size("font_size"),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
	}
	var manifest_path := output_path.get_basename() + ".json"
	var manifest := FileAccess.open(manifest_path, FileAccess.WRITE)
	if manifest == null:
		push_error("Could not save accident report capture manifest")
		quit(1)
		return
	manifest.store_string(JSON.stringify(evidence, "  ", true) + "\n")
	manifest.close()
	print(JSON.stringify(evidence))
	quit(0)
