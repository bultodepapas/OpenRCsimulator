# HUD-09: event-driven alert motion, truth and bounded retirement lifecycle.
extends SceneTree

const WarningsBar := preload("res://render/overlays/warnings_bar.gd")
const UiTheme := preload("res://ui/ui_theme.gd")

var _count := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var old_reduced: bool = UiTheme.reduced_motion
	UiTheme.reduced_motion = false
	TranslationServer.set_locale("en")
	root.size = Vector2i(1920, 1080)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var warnings := WarningsBar.new()
	warnings.theme = UiTheme.build()
	layer.add_child(warnings)
	warnings.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	warnings.grow_horizontal = Control.GROW_DIRECTION_BOTH
	warnings.visible = true
	var capture := {entry = true, reflow = false, subtle = false, entry_x = 0.0, reflow_x = 0.0, subtle_x = 0.0}
	warnings.chips.sort_children.connect(func() -> void:
		var a: Dictionary = warnings.get("_active")
		if a.has("stall"):
			var c: Dictionary = a.stall
			if capture.entry and c.visual.position.x > 0.0 and c.motion_tween != null:
				capture.entry_x = c.visual.position.x
				capture.entry = false
				c.motion_tween.pause()
			if capture.reflow and c.root.global_position.y > 20.0 and c.root.global_position.y < 200.0 \
				and absf(c.visual.global_position.y - c.root.global_position.y) < 0.5 \
				and c.visual.position.x > 0.0 and c.motion_tween != null:
				capture.reflow_x = c.visual.position.x
				capture.reflow = false
				c.motion_tween.pause()
			if capture.subtle and c.visual.position.x > 0.0 and c.visual.position.x <= 4.1 and c.motion_tween != null:
				capture.subtle_x = c.visual.position.x
				capture.subtle = false
				c.motion_tween.pause())
	var completions: Array[int] = []
	warnings.presentation_changed.connect(func() -> void: completions.append(1))
	_check("new alerts are present immediately", warnings.refresh(PackedStringArray(["stall", "far"]))
		and warnings.codes == PackedStringArray(["stall", "far"]))
	await process_frame
	await process_frame
	await process_frame
	var stall: Dictionary = _card(warnings, "stall")
	var far: Dictionary = _card(warnings, "far")
	_check("entry keeps urgent text fully opaque and readable", stall.root.modulate.a == 1.0
		and stall.row.visible and stall.headline.text == "STALL" and stall.detail.visible)
	_check("entry uses a bounded visual tween", stall.motion_tween != null and stall.motion_tween.is_valid()
		and capture.entry_x >= 9.9 and capture.entry_x <= 10.1)
	var entry: Tween = stall.motion_tween
	var before_x: float = stall.visual.position.x
	entry.custom_step(0.11)
	_check("entry moves toward its layout slot", absf(stall.visual.position.x) < absf(before_x))
	var sweep: Tween = warnings.get("_entrance")
	warnings.refresh(PackedStringArray(["stall", "far"]))
	_check("unchanged samples keep existing tweens and nodes", stall.root == _card(warnings, "stall").root
		and stall.motion_tween == entry and warnings.get("_entrance") == sweep)
	entry.custom_step(0.5)
	if far.motion_tween != null and far.motion_tween.is_valid(): far.motion_tween.custom_step(0.5)
	var old_stall_y: float = stall.visual.global_position.y
	capture.reflow = true
	warnings.refresh(PackedStringArray(["failsafe", "stall", "far"]))
	await process_frame
	await process_frame
	await process_frame
	_check("existing alert keeps its identity on insertion", stall.root == _card(warnings, "stall").root)
	_check("insertion moves survivors to new slots and settles horizontally", stall.root.global_position.y > old_stall_y + 10.0
		and not capture.reflow and capture.reflow_x > 0.0 and capture.reflow_x <= 6.1
		and stall.motion_tween != null and stall.motion_tween.is_valid(),
		"old=%s offset=%s slot=%s" % [old_stall_y, capture.reflow_x, stall.root.global_position.y])
	var incoming: Dictionary = _card(warnings, "failsafe")
	if incoming.motion_tween != null and incoming.motion_tween.is_valid(): incoming.motion_tween.pause()
	var disjoint := true
	for step in 5:
		disjoint = disjoint and _text_disjoint(incoming, stall)
		if incoming.motion_tween != null and incoming.motion_tween.is_valid(): incoming.motion_tween.custom_step(0.04)
		if stall.motion_tween != null and stall.motion_tween.is_valid(): stall.motion_tween.custom_step(0.04)
	_check("urgent text rectangles never overlap during insertion", disjoint)
	_check("moving card carries its glass and shadow together", stall.surface.get_parent() == stall.visual
		and stall.root.get_node("Glass/Face").get_parent() == stall.visual)
	warnings.refresh(PackedStringArray(["failsafe", "far"]))
	_check("removed alert leaves live truth and becomes an unlabelled silhouette", not warnings.codes.has("stall")
		and not warnings.get("_active").has("stall") and warnings.get("_ghosts").size() == 1
		and not stall.row.visible and stall.root.modulate.a <= 0.361)
	warnings.refresh(PackedStringArray(["failsafe", "stall", "far"]))
	_check("returning alert reclaims its retiring card", _card(warnings, "stall").root == stall.root
		and stall.row.visible and stall.root.modulate.a == 1.0 and warnings.get("_ghosts").is_empty())
	_check("empty truth remains presented while silhouettes retire", warnings.refresh(PackedStringArray())
		and warnings.codes.is_empty() and warnings.chips.get_child_count() == 0 and warnings.is_presenting())
	_check("retiring cards contain no warning copy", _ghosts_hide_copy(warnings))
	_finish_all(warnings)
	_check("last retirement signals once and releases presentation", completions.size() == 1
		and not warnings.is_presenting() and not warnings.refresh(PackedStringArray()))
	warnings.configure({warning_motion = "off", warning_limit = 1})
	warnings.refresh(PackedStringArray(["stall", "low"]))
	_check("motion off still displays urgent content and summary", warnings.chips.get_child_count() == 1
		and warnings.summary.visible and warnings.get("_entrance") == null
		and _card(warnings, "stall").motion_tween == null)
	_check("motion off removes immediately", not warnings.refresh(PackedStringArray())
		and warnings.get("_ghosts").is_empty())
	warnings.configure({warning_motion = "subtle", warning_limit = 1})
	capture.subtle = true
	warnings.refresh(PackedStringArray(["stall", "low"]))
	await process_frame
	await process_frame
	_check("subtle arrival has smaller displacement", not capture.subtle and capture.subtle_x > 0.0 and capture.subtle_x <= 4.1)
	warnings.refresh(PackedStringArray(["stall"]))
	_check("overflow retires without stale copy", not warnings.get("_ghosts").is_empty()
		and not warnings.get("_summary_card").row.visible)
	warnings.refresh(PackedStringArray(["stall", "low"]))
	_check("returning overflow reclaims its summary", warnings.summary.get_parent() == warnings.get("_column")
		and warnings.summary.visible and warnings.get("_summary_card").row.visible)
	UiTheme.reduced_motion = true
	warnings.configure({warning_motion = "playful", warning_limit = 1})
	_check("global reduced motion cancels every transition", warnings.get("_ghosts").is_empty()
		and warnings.get("_entrance") == null and _card(warnings, "stall").visual.position.is_zero_approx())
	_check("global reduced motion clears instantly", not warnings.refresh(PackedStringArray()))
	UiTheme.reduced_motion = false
	warnings.configure({warning_motion = "playful", warning_limit = 3})
	warnings.refresh(PackedStringArray(["stall", "far"]))
	await process_frame
	warnings.visible = false
	_check("hiding cancels motion and ghosts", warnings.get("_ghosts").is_empty()
		and warnings.get("_entrance") == null and _card(warnings, "stall").visual.position.is_zero_approx())
	warnings.visible = true
	warnings.refresh(PackedStringArray(["stall", "far"]))
	_check("reopening and unchanged sample do not replay", warnings.get("_entrance") == null
		and _card(warnings, "stall").motion_tween == null)
	warnings.refresh(PackedStringArray(["stall", "far", "low"]))
	await process_frame
	warnings.refresh(PackedStringArray(["stall", "far", "low"]), false)
	_check("nonanimated unchanged refresh settles ongoing motion", warnings.get("_entrance") == null
		and warnings.get("_ghosts").is_empty() and _card(warnings, "stall").visual.position.is_zero_approx()
		and _card(warnings, "low").visual.position.is_zero_approx())
	warnings.refresh(PackedStringArray(["stall"]))
	warnings.clear_immediate()
	_check("explicit reset clears active truth and retiring silhouettes", warnings.codes.is_empty()
		and not warnings.is_presenting() and warnings.get("_ghosts").is_empty()
		and warnings.chips.get_child_count() == 0)
	warnings.refresh(PackedStringArray(["stall", "far"]), false)
	_check("nonanimated refresh populates without motion", warnings.chips.get_child_count() == 2
		and warnings.get("_entrance") == null and _card(warnings, "stall").motion_tween == null)
	await process_frame
	await process_frame
	_check("nonanimated layout leaves card visuals at their slots", _card(warnings, "stall").visual.position.is_zero_approx()
		and _card(warnings, "far").visual.position.is_zero_approx()
		and not _card(warnings, "stall").root.get_global_rect().intersects(_card(warnings, "far").root.get_global_rect()))
	warnings.configure({warning_motion = "playful", warning_limit = 5})
	var group_a := PackedStringArray(["stall", "low", "battery_empty", "fuel_empty", "far"])
	var group_b := PackedStringArray(["failsafe", "controller_lost", "battery_hot", "battery", "experimental"])
	for index in 24:
		warnings.refresh(group_a if index % 2 == 0 else group_b)
	_check("rapid churn keeps five live cards and at most five ghosts", warnings.chips.get_child_count() == 5
		and warnings.get("_ghosts").size() <= 5 and warnings.get("_cards").size() <= 10)
	warnings.clear_immediate()
	_check("churn leaves bounded reusable cards and no ghosts", warnings.get("_ghosts").is_empty()
		and warnings.get("_available").size() <= 10)
	await _efficiency_checks(warnings)
	# Deletion during active content/summary exercises child-before-parent shutdown order.
	warnings.configure({warning_limit = 1})
	warnings.refresh(PackedStringArray(["stall", "low"]))
	var retire_ref: WeakRef = weakref(stall.root)
	warnings.queue_free()
	await process_frame
	await process_frame
	_check("queued deletion frees pooled and visible cards", retire_ref.get_ref() == null)
	layer.queue_free()
	UiTheme.reduced_motion = old_reduced
	print("warning motion: %d checks, %d failed" % [_count, _failures])
	quit(1 if _failures else 0)


func _efficiency_checks(warnings: Control) -> void:
	var old_opaque: bool = UiTheme.opaque_panels
	UiTheme.opaque_panels = false
	warnings.clear_immediate()
	warnings.configure({warning_motion = "off", warning_limit = 3, warning_detail = true})
	warnings.refresh(PackedStringArray(["stall", "far"]), false)
	var stall: Dictionary = _card(warnings, "stall")
	var far: Dictionary = _card(warnings, "far")
	var badge: StyleBox = stall.badge.get_theme_stylebox("panel")
	var well: StyleBox = stall.well.get_theme_stylebox("panel")
	var name_before: String = stall.root.get("accessibility_name")
	_check("cards retain independently mutable glass materials", stall.material != far.material)
	warnings.refresh(PackedStringArray(["failsafe", "stall", "far"]), false)
	_check("unchanged survivor reuses styles and accessible text", stall.badge.get_theme_stylebox("panel") == badge
		and stall.well.get_theme_stylebox("panel") == well and stall.root.get("accessibility_name") == name_before)
	var failsafe: Dictionary = _card(warnings, "failsafe")
	_check("same-severity cards share immutable styles but keep separate materials",
		failsafe.badge.get_theme_stylebox("panel") == badge and failsafe.well.get_theme_stylebox("panel") == well
		and failsafe.material != stall.material)
	warnings.configure({warning_motion = "off", warning_limit = 3, warning_detail = false})
	_check("detail changes without rebuilding the palette", not stall.detail.visible
		and stall.badge.get_theme_stylebox("panel") == badge and stall.well.get_theme_stylebox("panel") == well)
	UiTheme.opaque_panels = true
	warnings.configure({warning_motion = "off", warning_limit = 3, warning_detail = true})
	_check("opaque mode selects an opaque cached well", (stall.well.get_theme_stylebox("panel") as StyleBoxFlat).bg_color.a == 1.0)
	UiTheme.opaque_panels = false
	warnings.configure({warning_motion = "off", warning_limit = 3, warning_detail = true})
	_check("restoring translucent mode reuses its original style", stall.well.get_theme_stylebox("panel") == well)
	TranslationServer.set_locale("es")
	await process_frame
	_check("locale change invalidates visible and accessible copy", stall.headline.text == "PÉRDIDA"
		and str(stall.root.get("accessibility_name")).contains("PELIGRO"))
	TranslationServer.set_locale("en")
	await process_frame
	warnings.configure({warning_motion = "playful", warning_limit = 3})
	warnings.refresh(PackedStringArray(["stall", "far"]), false)
	warnings.refresh(PackedStringArray(["far"]))
	_check("retired card clears its accessible name", stall.root.get("accessibility_name") == "")
	warnings.refresh(PackedStringArray(["stall", "far"]))
	_check("reactivated card restores accessible copy", _card(warnings, "stall").root == stall.root
		and str(stall.root.get("accessibility_name")).contains("STALL"))
	warnings.clear_immediate()
	warnings.configure({warning_motion = "playful", warning_limit = 1})
	warnings.refresh(PackedStringArray(["stall", "far"]))
	warnings._reveal_light(0.5)
	var summary_material: ShaderMaterial = warnings.get("_summary_card").material
	_check("visible summary participates in the sweep", float(summary_material.get_shader_parameter("energy")) > 0.0)
	warnings.refresh(PackedStringArray(["stall"]))
	warnings._reveal_light(0.5)
	_check("retiring summary stays dark while active card continues sweeping",
		summary_material.get_shader_parameter("energy") == 0.0
		and summary_material.get_shader_parameter("shine_progress") == -1.0
		and float(_card(warnings, "stall").material.get_shader_parameter("energy")) > 0.0)
	warnings.clear_immediate()
	for index in 4:
		warnings.refresh(PackedStringArray(), false)
		warnings.clear_immediate()
	_check("repeated empty cleanup stays quiescent", warnings.get("_lit_materials").is_empty()
		and not warnings.get("_motion_dirty") and warnings.get("_ghosts").is_empty() and not warnings.is_presenting()
		and warnings.get("_well_styles").size() <= 2 and warnings.get("_badge_styles").size() <= 6)
	UiTheme.opaque_panels = old_opaque
	warnings.configure({warning_motion = "playful", warning_limit = 3})


func _card(warnings: Control, code: String) -> Dictionary:
	return warnings.get("_active").get(code, {})


func _ghosts_hide_copy(warnings: Control) -> bool:
	for ghost: Dictionary in warnings.get("_ghosts"):
		if ghost.row.visible: return false
	return true


func _text_disjoint(first: Dictionary, second: Dictionary) -> bool:
	for a: Label in [first.severity, first.headline, first.detail]:
		if not a.visible: continue
		for b: Label in [second.severity, second.headline, second.detail]:
			if b.visible and a.get_global_rect().intersects(b.get_global_rect()): return false
	return true


func _finish_all(warnings: Control) -> void:
	for ghost: Dictionary in warnings.get("_ghosts").duplicate():
		var tween: Tween = ghost.ghost_tween
		if tween != null and tween.is_valid(): tween.custom_step(0.5)


func _check(description: String, passed: bool, detail := "") -> void:
	_count += 1
	if not passed:
		_failures += 1
		printerr("FAIL %s %s" % [description, detail])
