# HUD-09: a bounded, read-only rail of prioritized flight alerts.
extends HBoxContainer

const UiTheme := preload("res://ui/ui_theme.gd")
const Frame := preload("res://render/overlays/overlay_frame.gd")
const AlertPolicy := preload("res://render/overlays/alert_policy.gd")
const GLASS := preload("res://ui/shaders/crystal.gdshader")

signal close_requested(id: String)
## The final retiring silhouette ended; owners can hide the empty rail.
signal presentation_changed

const MAX_WIDTH := 640.0
## A five-card rail with wrapped overflow and a centered battery need about 1037 px for a 12 px gap.
const COMPACT_VIEWPORT_HEIGHT := 1040.0
const CLOSE_WIDTH := 28.0
const GAP := 6.0
const LIMITS := [1, 3, 5]
const MOTIONS := ["playful", "subtle", "off"]
const MAX_ACTIVE := 5
const MAX_GHOSTS := 5
const ENTRY_TIME := 0.23
const EXIT_TIME := 0.16
const WELL := Color("#080B0A")
const GLASS_ALPHA := 0.78
const GLASS_TONES := {
	danger = {base = Color("#35090B"), emission = Color("#FF2A18"), crystal = Color("#FFD1C7"),
		ceiling = Vector3(0.26, 0.05, 0.045), text = Color("#FFECE5"), secondary = Color("#F5E5DF")},
	caution = {base = Color("#302606"), emission = Color("#FFD318"), crystal = Color("#FFF0AF"),
		ceiling = Vector3(0.20, 0.15, 0.02), text = Color("#FFF4D5"), secondary = Color("#F8EFD5")},
	info = {base = Color("#08290F"), emission = UiTheme.GLASS_EMISSION, crystal = UiTheme.CRYSTAL,
		ceiling = Vector3(0.06, 0.20, 0.04), text = UiTheme.PRIMARY_TEXT, secondary = Color("#E4F4DE")},
}

var id := "warnings"
var chips: VBoxContainer
var summary: PanelContainer
var close_button: Button
## Complete selected list, including alerts represented by the overflow count.
var codes := PackedStringArray()

var _column: VBoxContainer
var _cards: Array[Dictionary] = []
var _available: Array[Dictionary] = []
var _active := {}
var _ghosts: Array[Dictionary] = []
var _ghost_layer: Node2D
var _summary_card: Dictionary
var _detail := true
var _limit := 3
var _compact_viewport := false
var _motion := "playful"
var _opaque := false
var _entrance: Tween
var _lit_materials := {}
var _motion_dirty := false
var _well_styles := {}
var _badge_styles := {}
var _pending_positions := {}
var _pending_entries := PackedStringArray()
var _reflow_pending := false
var _insertion_floor := -1
var _sort_positions := {}
var _sort_entries := PackedStringArray()
var _summary_reflow_pending := false
var _summary_before := Vector2.ZERO
var _summary_entry := false


func _init() -> void:
	name = "WarningsOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", int(GAP))
	_opaque = UiTheme.opaque_panels
	_column = VBoxContainer.new()
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 4)
	add_child(_column)
	_column.sort_children.connect(_after_column_sort)
	_ghost_layer = Node2D.new()
	_ghost_layer.name = "Retiring"
	add_child(_ghost_layer, false, Node.INTERNAL_MODE_BACK)
	chips = VBoxContainer.new()
	chips.name = "Chips"
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("separation", 4)
	_column.add_child(chips)
	chips.pre_sort_children.connect(_before_chip_sort)
	chips.sort_children.connect(_after_chip_sort)
	_summary_card = _make_card("Summary")
	summary = _summary_card.root
	summary.visible = false
	_column.add_child(summary)
	close_button = Frame.close_x(func() -> void: close_requested.emit(id))
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.tooltip_text = tr("Close") + " · " + tr("Warnings")
	close_button.set("accessibility_name", close_button.tooltip_text)
	add_child(close_button)
	custom_minimum_size.x = MAX_WIDTH
	visible = false
	visibility_changed.connect(_visibility_changed)


func _enter_tree() -> void:
	get_viewport().size_changed.connect(_resize_to_viewport)
	_resize_to_viewport()


func _exit_tree() -> void:
	if get_viewport().size_changed.is_connected(_resize_to_viewport):
		get_viewport().size_changed.disconnect(_resize_to_viewport)
	_stop_entrance()
	_settle_motion()
	# Exiting a queued-for-deletion rail can retire nodes after PREDELETE has run.
	if is_queued_for_deletion():
		for card: Dictionary in _cards:
			if is_instance_valid(card.root) and card.root.get_parent() == null: card.root.free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Cards outside the tree remain in the pool so later alerts reuse them.
		for card: Dictionary in _cards:
			if is_instance_valid(card.root) and card.root.get_parent() == null:
				card.root.free()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and chips != null:
		_render_cards(false, codes)


## Preserve the original public text mapping for consumers outside the rail.
static func text_for(code: String) -> String:
	match code:
		"failsafe": return "FAILSAFE · radio lost"
		"safe": return "RADIO SAFE · throttle low to arm"
		"controller_lost": return "CONTROLLER LOST · select controls to continue"
		"stall": return "STALL"
		"low": return "LOW · sinking"
		"far": return "FAR · come closer"
		"battery": return "BATTERY LOW"
		"battery_empty": return "BATTERY EMPTY"
		"battery_critical": return "BATTERY CRITICAL"
		"battery_lvc": return "LVC · land now"
		"battery_hot": return "BATTERY HOT"
		"fuel_reserve": return "FUEL RESERVE"
		"fuel_reserve_estimated": return "FUEL RESERVE · ESTIMATED"
		"experimental": return "EXPERIMENTAL MODEL"
	return AlertPolicy.title_for(code)


## Settings affect presentation only; the manager owns filtering and priority.
func configure(settings: Dictionary) -> void:
	var detail: Variant = settings.get("warning_detail", true)
	var limit: Variant = settings.get("warning_limit", 3)
	var motion: Variant = settings.get("warning_motion", "playful")
	var next_detail: bool = detail if typeof(detail) == TYPE_BOOL else true
	var next_limit: int = limit if typeof(limit) == TYPE_INT and limit in LIMITS else 3
	var next_motion: String = motion if typeof(motion) == TYPE_STRING and motion in MOTIONS else "playful"
	if UiTheme.reduced_motion or next_motion == "off" or next_motion != _motion:
		_stop_entrance()
		_settle_motion()
	if next_detail == _detail and next_limit == _limit and next_motion == _motion and _opaque == UiTheme.opaque_panels:
		return
	_detail = next_detail
	_limit = next_limit
	_motion = next_motion
	_opaque = UiTheme.opaque_panels
	_render_cards(_can_animate(), codes)


## Inputs are already filtered and ordered. Retiring silhouettes remain present briefly after the last alert clears.
func refresh(new_codes: PackedStringArray, animate := true) -> bool:
	if new_codes == codes:
		if not animate:
			_stop_entrance()
			_settle_motion()
		return is_presenting()
	var previous := codes
	codes = new_codes.duplicate()
	var animate_change := animate and _can_animate()
	if not animate_change:
		_stop_entrance()
		_settle_motion()
	_render_cards(animate_change, previous)
	if codes.is_empty():
		_stop_entrance()
	var appeared := false
	for index in mini(codes.size(), _visible_limit()):
		if not previous.has(codes[index]):
			appeared = true
			break
	if appeared and animate_change:
		_start_entrance()
	return is_presenting()


## Public truth is `codes`; this also accounts for a fading, non-interactive silhouette.
func is_presenting() -> bool:
	return not codes.is_empty() or not _ghosts.is_empty()


## Used by explicit hide/reset: no exit visuals remain and no deferred callback can resurrect them.
func clear_immediate() -> void:
	if codes.is_empty() and _active.is_empty() and _ghosts.is_empty() and not _motion_dirty \
			and _lit_materials.is_empty() and (_entrance == null or not _entrance.is_valid()) and not summary.visible:
		return
	_stop_entrance()
	_settle_motion()
	codes = PackedStringArray()
	for code: String in _active.keys():
		_recycle(_active[code])
	_active.clear()
	summary.visible = false
	_clear_light(_summary_card.material)
	_reflow_pending = false
	_summary_reflow_pending = false
	_pending_positions.clear()
	_pending_entries.clear()


func _render_cards(animate_change: bool, previous: PackedStringArray) -> void:
	var shown := mini(codes.size(), _visible_limit())
	var desired := codes.slice(0, shown)
	_insertion_floor = -1
	if animate_change:
		for index in shown:
			if not _active.has(codes[index]):
				_insertion_floor = index
				break
	var had_summary := summary.get_parent() == _column and summary.visible
	var summary_before: Vector2 = _summary_card.visual.global_position if had_summary and animate_change else Vector2.ZERO
	var before := {}
	var old_survivors := PackedStringArray()
	if animate_change:
		for node: Control in chips.get_children():
			var old_code: String = node.get_meta("code", "")
			if desired.has(old_code): old_survivors.append(old_code)
		for code: String in _active:
			var current: Dictionary = _active[code]
			before[code] = current.visual.global_position
		var new_survivors := PackedStringArray()
		for code: String in desired:
			if before.has(code): new_survivors.append(code)
		# Crossing full-width cards would obscure urgent copy. Such swaps settle in place.
		if old_survivors != new_survivors: before.clear()
	for code: String in _active.keys():
		if not desired.has(code):
			var removed: Dictionary = _active[code]
			_active.erase(code)
			_retire(removed, animate_change)
	var entries := PackedStringArray()
	for index in shown:
		var code := codes[index]
		var card: Dictionary
		if _active.has(code):
			card = _active[code]
		else:
			card = _acquire(code)
			_active[code] = card
			chips.add_child(card.root)
			if not previous.has(code): entries.append(code)
		if card.root.get_index() != index: chips.move_child(card.root, index)
		_update_card(card, AlertPolicy.severity(code), tr(AlertPolicy.title_for(code)),
			tr(AlertPolicy.detail_for(code)) if _detail else "", code)
	var remaining := codes.size() - shown
	if remaining <= 0 and summary.visible and summary.get_parent() == _column:
		_retire(_summary_card, animate_change)
	elif remaining <= 0:
		_clear_light(_summary_card.material)
	if remaining > 0:
		_restore_summary()
		summary.visible = true
		var severity := "info"
		var hidden_danger := PackedStringArray()
		for index in range(shown, codes.size()):
			var candidate := AlertPolicy.severity(codes[index])
			if candidate == "danger":
				severity = "danger"
				hidden_danger.append(tr(AlertPolicy.title_for(codes[index])))
			elif candidate == "caution" and severity != "danger":
				severity = "caution"
		# A cap never hides the identity of a critical condition, even in compact mode.
		_update_card(_summary_card, severity, "%s +%d" % [tr("Alerts").to_upper(), remaining],
			" · ".join(hidden_danger), "")
	if animate_change and not _active.is_empty():
		_pending_positions = before
		_pending_entries = entries
		_reflow_pending = true
		_motion_dirty = true
		chips.queue_sort()
	if animate_change and remaining > 0:
		var new_hidden := false
		for index in range(shown, codes.size()):
			if not previous.has(codes[index]): new_hidden = true
		_summary_reflow_pending = had_summary or new_hidden
		_summary_before = summary_before
		_summary_entry = not had_summary and new_hidden
		if _summary_reflow_pending:
			_motion_dirty = true
			_column.queue_sort()


func _can_animate() -> bool:
	return is_inside_tree() and is_visible_in_tree() and not UiTheme.reduced_motion and _motion != "off"


func _acquire(code: String) -> Dictionary:
	# A returning condition takes back its own retiring slot without leaving a ghost behind.
	for ghost: Dictionary in _ghosts.duplicate():
		if not ghost.is_summary and ghost.root.get_meta("code", "") == code:
			_finish_ghost(ghost, false)
			break
	if _available.is_empty() and _cards.size() >= MAX_ACTIVE + MAX_GHOSTS:
		for ghost: Dictionary in _ghosts.duplicate():
			if not ghost.is_summary:
				_finish_ghost(ghost, false)
				break
	if not _available.is_empty():
		return _available.pop_back()
	var card := _make_card("Warning")
	_cards.append(card)
	return card


func _retire(card: Dictionary, animate_change: bool) -> void:
	_cancel_card_motion(card)
	_clear_light(card.material)
	if not animate_change:
		_recycle(card)
		return
	while _ghosts.size() >= MAX_GHOSTS:
		_finish_ghost(_ghosts[0], false)
	var root: Control = card.root
	var origin := root.global_position
	var extent := root.size
	if root.get_parent() != null: root.get_parent().remove_child(root)
	_ghost_layer.add_child(root)
	root.position = _ghost_layer.to_local(origin)
	root.size = extent
	# Retired silhouettes never show stale warning text or severity badges.
	card.row.visible = false
	root.set("accessibility_name", "")
	root.modulate = Color(0.72, 0.72, 0.72, 0.36)
	_ghosts.append(card)
	_motion_dirty = true
	var tween := create_tween().set_parallel(true).set_ignore_time_scale().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	card.ghost_tween = tween
	var distance := 6.0 if _motion == "subtle" else 12.0
	tween.tween_property(card.visual, "position", card.visual.position + Vector2(distance, 0), EXIT_TIME)
	tween.tween_property(root, "modulate:a", 0.0, EXIT_TIME)
	tween.finished.connect(_finish_ghost.bind(card))


func _finish_ghost(card: Dictionary, announce := true) -> void:
	if not _ghosts.has(card): return
	_ghosts.erase(card)
	var tween: Tween = card.ghost_tween
	if tween != null and tween.is_valid(): tween.kill()
	card.ghost_tween = null
	_recycle(card)
	if announce and _ghosts.is_empty() and codes.is_empty():
		presentation_changed.emit()


func _recycle(card: Dictionary) -> void:
	_cancel_card_motion(card)
	if not is_instance_valid(card.root): return
	var root: Control = card.root
	if root.get_parent() != null: root.get_parent().remove_child(root)
	if is_instance_valid(card.visual): card.visual.position = Vector2.ZERO
	if is_instance_valid(card.row): card.row.visible = true
	root.modulate = Color.WHITE
	card.render_valid = false # retirement clears the accessibility name
	_clear_light(card.material)
	if card.is_summary:
		root.visible = false
		if is_instance_valid(_column):
			_column.add_child(root)
		else:
			root.free()
	elif not _available.has(card):
		_available.append(card)


func _restore_summary() -> void:
	if _ghosts.has(_summary_card): _finish_ghost(_summary_card, false)
	if summary.get_parent() == null: _column.add_child(summary)


func _before_chip_sort() -> void:
	_sort_positions.clear()
	_sort_entries.clear()
	if not _can_animate(): return
	if _reflow_pending:
		_sort_positions = _pending_positions.duplicate()
		_sort_entries = _pending_entries.duplicate()
	else:
		var moving := false
		for current: Dictionary in _active.values():
			var tween: Tween = current.motion_tween
			if tween != null and tween.is_valid():
				moving = true
				break
		if not moving: return
		# Width and wrapped text can require several sorts. Preserve the visible
		# location through each one, including an already-moving card.
		for code: String in _active:
			var card: Dictionary = _active[code]
			_sort_positions[code] = card.visual.global_position


func _after_chip_sort() -> void:
	_reflow_pending = false
	if not _can_animate(): return
	for code: String in _active:
		var card: Dictionary = _active[code]
		var start := Vector2.ZERO
		var entry := _sort_entries.has(code)
		if _sort_positions.has(code):
			start = Vector2(_sort_positions[code]) - card.root.global_position
		elif entry:
			start.x = 4.0 if _motion == "subtle" else 10.0
		else:
			continue
		# A new row immediately owns its slot. Move survivors horizontally, not
		# through the newly visible warning text, even across intermediate sorts.
		if _insertion_floor >= 0 and card.root.get_index() >= _insertion_floor and not entry and absf(start.y) > 0.5:
			start.y = 0.0
			start.x = 4.0 if _motion == "subtle" else 6.0
		if not entry and start.is_equal_approx(card.visual.position): continue
		_move_card(card, start, entry)
	_pending_positions.clear()
	_pending_entries.clear()
	_sort_positions.clear()
	_sort_entries.clear()


func _after_column_sort() -> void:
	if not _summary_reflow_pending: return
	_summary_reflow_pending = false
	if not _can_animate() or summary.get_parent() != _column or not summary.visible: return
	var start := Vector2.ZERO
	if _summary_entry:
		start.x = 4.0 if _motion == "subtle" else 10.0
	else:
		start = _summary_before - summary.global_position
	_move_card(_summary_card, start, _summary_entry)


func _move_card(card: Dictionary, start: Vector2, entry: bool) -> void:
	_cancel_card_motion(card)
	card.visual.position = start
	if start.is_zero_approx(): return
	_motion_dirty = true
	var tween := create_tween().set_ignore_time_scale().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	card.motion_tween = tween
	var transition := Tween.TRANS_BACK if entry and _motion == "playful" else Tween.TRANS_CUBIC
	tween.tween_property(card.visual, "position", Vector2.ZERO, ENTRY_TIME).set_trans(transition).set_ease(Tween.EASE_OUT)


func _cancel_card_motion(card: Dictionary) -> void:
	var tween: Tween = card.motion_tween
	if tween != null and tween.is_valid(): tween.kill()
	card.motion_tween = null


func _settle_motion() -> void:
	if not _motion_dirty: return
	_reflow_pending = false
	_summary_reflow_pending = false
	_insertion_floor = -1
	_pending_positions.clear()
	_pending_entries.clear()
	_sort_positions.clear()
	_sort_entries.clear()
	for card: Dictionary in _cards:
		_cancel_card_motion(card)
		if is_instance_valid(card.visual): card.visual.position = Vector2.ZERO
	_cancel_card_motion(_summary_card)
	if is_instance_valid(_summary_card.visual): _summary_card.visual.position = Vector2.ZERO
	while not _ghosts.is_empty():
		_finish_ghost(_ghosts[0], false)
	_motion_dirty = false


func _make_card(card_name: String) -> Dictionary:
	var card := PanelContainer.new()
	card.name = card_name
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var outer := StyleBoxFlat.new()
	outer.bg_color = Color.TRANSPARENT
	outer.set_corner_radius_all(12)
	outer.shadow_size = 5
	outer.content_margin_left = 9
	outer.content_margin_right = 9
	outer.content_margin_top = 5 if _compact_viewport else 7
	outer.content_margin_bottom = 5 if _compact_viewport else 7
	# The layout slot stays in the VBox. Its complete visual, including shadow,
	# moves independently so the container never fights the motion tween.
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var underlay := Node2D.new()
	underlay.name = "Glass"
	underlay.show_behind_parent = true
	card.add_child(underlay, false, Node.INTERNAL_MODE_BACK)
	var material := ShaderMaterial.new()
	material.shader = GLASS
	material.set_shader_parameter("primary", 1.0)
	material.set_shader_parameter("corner_radius", 12.0)
	material.set_shader_parameter("edge_width", 0.70)
	material.set_shader_parameter("edge_strength", 0.90)
	material.set_shader_parameter("reflection_strength", 0.62)
	material.set_shader_parameter("glint_strength", 0.65)
	material.set_shader_parameter("energy", 0.0)
	material.set_shader_parameter("shine_progress", -1.0)
	var glass := ColorRect.new()
	glass.name = "Face"
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.material = material
	underlay.add_child(glass)
	var surface := PanelContainer.new()
	surface.name = "Surface"
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_theme_stylebox_override("panel", outer)
	underlay.add_child(surface)
	card.resized.connect(_resize_glass.bind(card, glass, material, surface))
	surface.minimum_size_changed.connect(_sync_card_minimum.bind(card, surface))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	surface.add_child(row)
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size.x = 76
	row.add_child(badge)
	var severity := Frame.text_label("", 12, UiTheme.TEXT)
	severity.name = "Severity"
	severity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	severity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(severity)
	var well := PanelContainer.new()
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(well)
	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_theme_constant_override("separation", 0)
	well.add_child(copy)
	var headline := Frame.text_label("", 17, UiTheme.TEXT)
	headline.name = "Headline"
	headline.clip_text = true
	headline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(headline)
	var detail := Frame.text_label("", 14, UiTheme.TEXT_2)
	detail.name = "Detail"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(detail)
	_sync_card_minimum(card, surface)
	_resize_glass(card, glass, material, surface)
	return {root = card, visual = underlay, surface = surface, row = row, material = material,
		outer = outer, badge = badge, severity = severity, well = well, headline = headline, detail = detail,
		motion_tween = null, ghost_tween = null, is_summary = card_name == "Summary", render_valid = false}


func _update_card(card: Dictionary, level: String, title: String, detail: String, code: String) -> void:
	var severity_text := tr(level.to_upper())
	if card.render_valid and card.render_level == level and card.render_title == title \
			and card.render_detail == detail and card.render_code == code and card.render_opaque == _opaque \
			and card.render_severity == severity_text:
		return
	var tone_changed: bool = not card.render_valid or card.render_level != level or card.render_opaque != _opaque
	var tone: Dictionary = GLASS_TONES.get(level, GLASS_TONES.info)
	var severity: Label = card.severity
	severity.text = severity_text
	var headline: Label = card.headline
	headline.text = title
	var description: Label = card.detail
	description.text = detail
	description.visible = not detail.is_empty()
	card.root.set_meta("code", code)
	card.root.set("accessibility_name", ": ".join([severity.text, title, detail]).trim_suffix(": "))
	if tone_changed:
		severity.add_theme_color_override("font_color", tone.crystal)
		headline.add_theme_color_override("font_color", tone.text)
		description.add_theme_color_override("font_color", tone.secondary)
		card.badge.add_theme_stylebox_override("panel", _badge_style(level, tone))
		card.well.add_theme_stylebox_override("panel", _well_style())
		card.outer.shadow_color = Color(tone.emission, 0.26)
		card.material.set_shader_parameter("base_color", Color(tone.base, 1.0 if _opaque else GLASS_ALPHA))
		card.material.set_shader_parameter("crystal_color", tone.crystal)
		card.material.set_shader_parameter("emission_color", tone.emission)
		card.material.set_shader_parameter("well_ceiling", tone.ceiling)
	card.render_level = level
	card.render_title = title
	card.render_detail = detail
	card.render_code = code
	card.render_opaque = _opaque
	card.render_severity = severity_text
	card.render_valid = true


func _well_style() -> StyleBoxFlat:
	if not _well_styles.has(_opaque):
		_well_styles[_opaque] = _new_well_style()
	return _well_styles[_opaque]


func _badge_style(level: String, tone: Dictionary) -> StyleBoxFlat:
	var key := level + ("/opaque" if _opaque else "/glass")
	if not _badge_styles.has(key):
		var style := _new_well_style()
		style.bg_color = Color(tone.base, 1.0 if _opaque else 0.20)
		style.set_border_width_all(1)
		style.border_color = Color(tone.crystal, 0.32)
		_badge_styles[key] = style
	return _badge_styles[key]


func _new_well_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(WELL, 1.0 if _opaque else 0.14)
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func _sync_card_minimum(card: Control, surface: Control) -> void:
	var minimum := surface.get_combined_minimum_size()
	if not card.custom_minimum_size.is_equal_approx(minimum):
		card.custom_minimum_size = minimum


func _resize_glass(card: Control, glass: ColorRect, material: ShaderMaterial, surface: Control) -> void:
	glass.size = card.size
	surface.size = card.size
	material.set_shader_parameter("rect_size", card.size)


## The requested limit is a maximum; keep overflow and every hidden danger name on short screens.
func _visible_limit() -> int:
	return mini(_limit, 3) if _compact_viewport else _limit


func _resize_to_viewport() -> void:
	var viewport := get_viewport_rect().size
	var width := minf(MAX_WIDTH, maxf(0.0, viewport.x - 24.0))
	var compact := viewport.y < COMPACT_VIEWPORT_HEIGHT
	var changed := compact != _compact_viewport
	_compact_viewport = compact
	if not is_equal_approx(custom_minimum_size.x, width):
		custom_minimum_size.x = width
		reset_size()
	if changed:
		var was_presenting := is_presenting()
		for card: Dictionary in _cards + [_summary_card]:
			card.outer.content_margin_top = 5 if compact else 7
			card.outer.content_margin_bottom = 5 if compact else 7
		_stop_entrance()
		_settle_motion()
		_render_cards(false, codes)
		if was_presenting and not is_presenting(): presentation_changed.emit()


func _start_entrance() -> void:
	_stop_entrance()
	_entrance = create_tween().set_ignore_time_scale().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_entrance.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_entrance.tween_method(_reveal_light, 0.0, 1.0, 0.56)
	_entrance.finished.connect(_stop_entrance)


## Animate the optical layer only. Text stays fully opaque, and no clock runs at rest.
func _reveal_light(progress: float) -> void:
	if not _can_animate():
		_stop_entrance()
		return
	var shine := lerpf(-0.25, 1.65, progress)
	var energy := 0.8 * sin(PI * progress)
	for code: String in _active:
		_set_light(_active[code].material, shine, energy)
	if summary.visible and summary.get_parent() == _column:
		_set_light(_summary_card.material, shine, energy)


func _set_light(material: ShaderMaterial, shine: float, energy: float) -> void:
	material.set_shader_parameter("shine_progress", shine)
	material.set_shader_parameter("energy", energy)
	_lit_materials[material] = true


func _clear_light(material: ShaderMaterial) -> void:
	if not _lit_materials.has(material): return
	material.set_shader_parameter("shine_progress", -1.0)
	material.set_shader_parameter("energy", 0.0)
	_lit_materials.erase(material)


func _stop_entrance() -> void:
	if _entrance != null and _entrance.is_valid(): _entrance.kill()
	_entrance = null
	if modulate.a != 1.0: modulate.a = 1.0
	if _lit_materials.is_empty(): return
	for material: ShaderMaterial in _lit_materials.keys():
		_clear_light(material)


func _visibility_changed() -> void:
	if not is_visible_in_tree():
		_stop_entrance()
		_settle_motion()
	elif _opaque != UiTheme.opaque_panels:
		_opaque = UiTheme.opaque_panels
		_render_cards(false, codes)
