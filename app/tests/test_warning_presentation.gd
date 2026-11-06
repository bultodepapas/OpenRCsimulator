# Focused HUD-09 warning presentation contract; manager owns selection and visibility.
extends SceneTree

const WarningsBar := preload("res://render/overlays/warnings_bar.gd")
const UiTheme := preload("res://ui/ui_theme.gd")

var _count := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("en")
	var original_motion: bool = UiTheme.reduced_motion
	var original_opaque: bool = UiTheme.opaque_panels
	UiTheme.reduced_motion = false
	UiTheme.opaque_panels = false
	root.size = Vector2i(1920, 1080)
	var warnings := WarningsBar.new()
	warnings.theme = UiTheme.build()
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(warnings)
	warnings.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	warnings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	warnings.visible = true
	var signal_ids: Array[String] = []
	warnings.close_requested.connect(func(id: String) -> void: signal_ids.append(id))
	_check("close remains mouse-only and emits the warning id", warnings.id == "warnings"
		and warnings.close_button.focus_mode == Control.FOCUS_NONE)
	warnings.close_button.pressed.emit()
	_check("close signal carries its id", signal_ids == ["warnings"])
	var alerts := PackedStringArray(["failsafe", "stall", "low", "battery_hot", "far", "experimental"])
	_check("nonempty refresh reports shown", warnings.refresh(alerts))
	await process_frame
	await process_frame
	_check("complete selected list is retained", warnings.codes == alerts)
	_check("default cap displays three in supplied order", _shown(warnings) == ["failsafe", "stall", "low"])
	_check("overflow is separate and marks its strongest severity", warnings.summary.visible
		and _label(warnings.summary, "Headline").text == "+3 MORE ALERTS"
		and _label(warnings.summary, "Severity").text == "CAUTION")
	var first: Control = warnings.chips.get_child(0)
	var first_id := first.get_instance_id()
	_check("card states severity and corrective action", _label(first, "Severity").text == "DANGER"
		and _label(first, "Headline").text == "RADIO LOST"
		and _label(first, "Detail").text == "Reconnect the radio to continue.")
	_check("1080p action text has a full line of height", _fits_lines(_label(first, "Detail")),
		str(_label(first, "Detail").size))
	_check("noninteractive descendants ignore pointer input", _ignores_pointer(warnings, warnings.close_button))
	_check("unchanged sample reports shown", warnings.refresh(alerts.duplicate()))
	_check("unchanged sample keeps card instances", warnings.chips.get_child(0).get_instance_id() == first_id)
	warnings.refresh(PackedStringArray(["stall", "far", "experimental"]))
	await process_frame
	await process_frame
	_material_checks(warnings)
	warnings.refresh(alerts)
	warnings.configure({"warning_limit": 1, "warning_detail": false})
	_check("compact setting caps cards without dropping codes", warnings.codes == alerts
		and _shown(warnings) == ["failsafe"] and not _label(first, "Detail").visible)
	_check("compact overflow names all hidden dangers", _label(warnings.summary, "Headline").text == "+5 MORE ALERTS"
		and _label(warnings.summary, "Severity").text == "DANGER"
		and _label(warnings.summary, "Detail").text == "STALL · LOW ALTITUDE"
		and _label(warnings.summary, "Detail").visible)
	warnings.configure({"warning_limit": 5, "warning_detail": true})
	_check("larger cap reuses cards and retains overflow", _shown(warnings) == Array(alerts.slice(0, 5))
		and warnings.chips.get_child(0).get_instance_id() == first_id and warnings.summary.visible
		and _label(first, "Detail").visible)
	warnings.configure({"warning_limit": 2, "warning_detail": "invalid"})
	_check("invalid settings fall back to three detailed cards", warnings.chips.get_child_count() == 3
		and _label(first, "Detail").visible)
	UiTheme.opaque_panels = true
	warnings.configure({})
	var well: PanelContainer = _label(first, "Headline").get_parent().get_parent()
	_check("opaque preference applies to dark well", (well.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a == 1.0)
	_check("clear removes cards and summary", not warnings.refresh(PackedStringArray())
		and warnings.codes.is_empty() and warnings.chips.get_child_count() == 0 and not warnings.summary.visible)
	UiTheme.reduced_motion = true
	warnings.refresh(PackedStringArray(["stall"]))
	_check("pooled card returns without animation under reduced motion", warnings.chips.get_child(0).get_instance_id() == first_id
		and warnings.get("_entrance") == null and is_equal_approx(warnings.modulate.a, 1.0))
	UiTheme.reduced_motion = false
	warnings.refresh(PackedStringArray(["stall", "far"]))
	_check("new visible alert starts a bounded transition", warnings.get("_entrance") != null)
	_check("arrival light never fades the alert text", is_equal_approx(warnings.modulate.a, 1.0))
	var transition: Tween = warnings.get("_entrance")
	warnings.refresh(PackedStringArray(["stall", "far"]))
	_check("unchanged sample does not restart transition", warnings.get("_entrance") == transition)
	warnings.refresh(PackedStringArray(["stall", "far", "experimental", "low"]))
	warnings.get("_entrance").custom_step(0.22)
	var retired: Control = warnings.chips.get_child(2)
	var retired_material: ShaderMaterial = retired.get_node("Glass/Face").material
	warnings.configure({warning_limit = 1})
	_check("a pooled card stops its light immediately when detached",
		retired.get_parent() == null and retired_material.get_shader_parameter("energy") == 0.0
		and retired_material.get_shader_parameter("shine_progress") == -1.0)
	warnings.configure({warning_limit = 3})
	UiTheme.reduced_motion = true
	warnings.configure({})
	_check("enabling reduced motion stops an active transition", warnings.get("_entrance") == null)
	UiTheme.reduced_motion = false
	warnings.refresh(PackedStringArray(["stall", "far", "battery_hot"]))
	warnings.visible = false
	_check("hiding stops transition and restores opacity", warnings.get("_entrance") == null
		and is_equal_approx(warnings.modulate.a, 1.0))
	warnings.visible = true
	warnings.refresh(PackedStringArray(["stall", "far", "battery_hot", "low"]))
	layer.visible = false
	_check("hiding the overlay layer stops transition", warnings.get("_entrance") == null)
	layer.visible = true
	await process_frame
	_check("1080p rail stays within 640 pixels", warnings.size.x <= WarningsBar.MAX_WIDTH + 0.5, str(warnings.size))
	root.size = Vector2i(1280, 720)
	TranslationServer.set_locale("es")
	warnings.configure({"warning_limit": 1, "warning_detail": true})
	warnings.refresh(PackedStringArray(["fuel_reserve_estimated", "stall", "low"]))
	await process_frame
	await process_frame
	await process_frame
	var action := _label(first, "Detail")
	var badge := _label(first, "Severity")
	_check("720p Spanish rail stays bounded and action lines fit", warnings.size.x <= WarningsBar.MAX_WIDTH + 0.5
		and action.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART and _fits_lines(action), str(action.size))
	_check("Spanish caution badge has room for its translated word", badge.text == "PRECAUCIÓN" and _fits_text(badge),
		"%s %s" % [badge.text, badge.size])
	root.size = Vector2i(480, 720)
	await process_frame
	await process_frame
	await process_frame
	_check("narrow window reduces rail width", warnings.size.x <= 456.5, str(warnings.size))
	_check("wrapped Spanish action and overflow lines fit", action.get_line_count() > 1
		and _fits_lines(action) and _fits_lines(_label(warnings.summary, "Detail")),
		"action=%s lines=%d summary=%s" % [action.size, action.get_line_count(), _label(warnings.summary, "Detail").size])
	if DisplayServer.get_name() != "headless":
		await _rendered_materials(warnings)
	# Free a pooled node outside the tree as well as the visible ones.
	warnings.refresh(PackedStringArray())
	var pooled: WeakRef = weakref(first)
	warnings.queue_free()
	await process_frame
	await process_frame
	_check("retired pooled cards are freed with the rail", pooled.get_ref() == null)
	layer.queue_free()
	UiTheme.reduced_motion = original_motion
	UiTheme.opaque_panels = original_opaque
	TranslationServer.set_locale("en")
	print("warning presentation: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _material_checks(warnings: Control) -> void:
	var levels := ["danger", "caution", "info"]
	for index in levels.size():
		var card: Control = warnings.chips.get_child(index)
		var material: ShaderMaterial = card.get_node("Glass/Face").material
		var emission: Color = material.get_shader_parameter("emission_color")
		var base: Color = material.get_shader_parameter("base_color")
		var hue_ok := emission.r > emission.g * 2.0 if index == 0 else (
			emission.r > 0.9 and emission.g > 0.6 and emission.b < 0.2 if index == 1 else emission.g > emission.r * 2.0)
		_check("glass light matches severity: " + levels[index], hue_ok)
		var title := _label(card, "Headline")
		var well: PanelContainer = title.get_parent().get_parent()
		_check("tinted glass and interior film remain translucent: " + levels[index], base.a < 0.85
			and (well.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a < 0.25)
		var ceiling: Vector3 = material.get_shader_parameter("well_ceiling")
		var brightest := Color(ceiling.x, ceiling.y, ceiling.z, base.a)
		var readable := true
		for label_name: String in ["Headline", "Detail", "Severity"]:
			readable = readable and UiTheme.contrast(_label(card, label_name).get_theme_color("font_color"), brightest) >= 4.5
		_check("glass ceiling protects all text over bright and dark scenes: " + levels[index], readable)


## Sample the actual shader at rest and through its single sweep; no glyphs cover the measured text area.
func _rendered_materials(warnings: Control) -> void:
	root.size = Vector2i(1920, 1080)
	TranslationServer.set_locale("en")
	UiTheme.opaque_panels = false
	warnings.configure({warning_limit = 3, warning_detail = true})
	warnings.refresh(PackedStringArray(["stall", "far", "experimental"]))
	warnings._stop_entrance()
	var backdrop := ColorRect.new()
	backdrop.size = Vector2(1920, 1080)
	root.add_child(backdrop)
	root.move_child(backdrop, 0)
	for card: Control in warnings.chips.get_children():
		for label_name: String in ["Headline", "Detail", "Severity"]:
			_label(card, label_name).self_modulate.a = 0.0
	var centers: Array[Color] = []
	for background: Color in [Color.WHITE, Color.BLACK]:
		backdrop.color = background
		var worst := [INF, INF, INF]
		var worst_at := ["", "", ""]
		for phase: float in [0.0, 0.5, 1.0]:
			warnings._reveal_light(phase)
			await RenderingServer.frame_post_draw
			var rendered := root.get_texture().get_image()
			for index in warnings.chips.get_child_count():
				var card: Control = warnings.chips.get_child(index)
				for label_name: String in ["Headline", "Detail", "Severity"]:
					var label := _label(card, label_name)
					var rect := Rect2i(label.get_global_rect())
					for x in range(rect.position.x + 1, rect.end.x - 1, 6):
						for y in range(rect.position.y + 1, rect.end.y - 1, 3):
							var pixel := rendered.get_pixel(x, y)
							var contrast := UiTheme.contrast(label.get_theme_color("font_color"), pixel)
							if contrast < worst[index]:
								worst[index] = contrast
								worst_at[index] = "%s at %d,%d phase %.2f bg=%s" % [label_name, x, y, phase, pixel]
				if phase == 1.0:
					var well: Control = _label(card, "Headline").get_parent().get_parent()
					centers.append(rendered.get_pixelv(Vector2i(well.get_global_rect().get_center())))
		for index in worst.size():
			_check("rendered severity %d keeps text contrast through sweep over %s" % [index, "white" if background == Color.WHITE else "black"],
				worst[index] >= 4.5, "%s %s" % [worst[index], worst_at[index]])
	for index in 3:
		var difference := maxf(absf(centers[index].r - centers[index + 3].r),
			maxf(absf(centers[index].g - centers[index + 3].g), absf(centers[index].b - centers[index + 3].b)))
		_check("rendered glass transmits the scene behind severity %d" % index, difference > 0.05, str(difference))
	for card: Control in warnings.chips.get_children():
		for label_name: String in ["Headline", "Detail", "Severity"]:
			_label(card, label_name).self_modulate = Color.WHITE
	warnings._stop_entrance()
	backdrop.queue_free()
	await process_frame


func _shown(warnings: Control) -> Array:
	var result: Array = []
	for child: Control in warnings.chips.get_children(): result.append(child.get_meta("code"))
	return result


func _label(parent: Node, label_name: String) -> Label:
	return parent.find_child(label_name, true, false) as Label


func _fits_lines(label: Label) -> bool:
	var font := label.get_theme_font("font")
	var height := font.get_height(label.get_theme_font_size("font_size"))
	return label.size.y + 0.5 >= height * label.get_line_count()


func _fits_text(label: Label) -> bool:
	var font := label.get_theme_font("font")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		label.get_theme_font_size("font_size")).x <= label.size.x + 0.5


func _ignores_pointer(node: Node, close: Button) -> bool:
	if node is Control and node != close and node.mouse_filter != Control.MOUSE_FILTER_IGNORE: return false
	for child in node.get_children():
		if not _ignores_pointer(child, close): return false
	return true


func _check(description: String, passed: bool, detail := "") -> void:
	_count += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [description, detail])
