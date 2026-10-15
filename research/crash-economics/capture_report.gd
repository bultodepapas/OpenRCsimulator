extends SceneTree

## Native 1280x720 composition capture for the standalone accident report overlay.
## Run with Godot --path app --script ../research/crash-economics/capture_report.gd -- --out=<png>.
const AccidentReport := preload("res://ui/accident_report.gd")


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	var output_path := "user://cr32-accident-report.png"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			output_path = argument.trim_prefix("--out=")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	TranslationServer.set_locale("en")

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
	report.show_assessment({
		"identity": {"aircraft_id": "trainer-v2", "incident_id": "demo-incident"},
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
			{"id": "front_gear", "quantity": 1, "action": "inspect", "amount_minor": null},
		],
		"salvage_minor": null,
		"replacement_minor": null,
		"unresolved": ["front landing gear inspection"],
		"price_date": "2026-10-15",
	}, true)
	for frame_index: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw

	var viewport := root.get_viewport()
	var panel := report.find_child("AccidentReportCard", true, false) as Control
	var panel_rect := panel.get_global_rect()
	var viewport_size := viewport.get_visible_rect().size
	var image := viewport.get_texture().get_image()
	var image_error := image.save_png(output_path)
	_debug_tree(report)
	var panel_fits := panel_rect.position.x >= 0.0 and panel_rect.position.y >= 0.0 \
		and panel_rect.end.x <= viewport_size.x and panel_rect.end.y <= viewport_size.y
	if image_error != OK or not panel_fits:
		push_error("Accident report capture failed: image=%d panel=%s viewport=%s" % [image_error, panel_rect, viewport_size])
		quit(1)
		return
	var amount := (report.find_child("ReportAmount", true, false) as Label).text
	var evidence := {
		"format": "openrc-cr32-accident-report-capture-v1",
		"image": output_path.get_file(),
		"requested_size": [1280, 720],
		"image_size": [image.get_width(), image.get_height()],
		"panel_rect": [panel_rect.position.x, panel_rect.position.y, panel_rect.size.x, panel_rect.size.y],
		"panel_fits_viewport": panel_fits,
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


func _debug_tree(node: Node) -> void:
	if node is Control:
		var control := node as Control
		print("UI_DEBUG %s %s rect=%s min=%s visible=%s" % [control.get_class(), control.name,
			str(control.get_global_rect()), str(control.get_combined_minimum_size()), str(control.visible)])
	for child: Node in node.get_children():
		_debug_tree(child)
