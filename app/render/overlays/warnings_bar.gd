# HUD-09: a bounded, read-only rail of prioritized flight alerts.
extends HBoxContainer

const UiTheme := preload("res://ui/ui_theme.gd")
const Frame := preload("res://render/overlays/overlay_frame.gd")
const AlertPolicy := preload("res://render/overlays/alert_policy.gd")
const GLASS := preload("res://ui/shaders/crystal.gdshader")

signal close_requested(id: String)

const MAX_WIDTH := 640.0
const CLOSE_WIDTH := 28.0
const GAP := 6.0
const LIMITS := [1, 3, 5]
const WELL := Color("#101713")

var id := "warnings"
var chips: VBoxContainer
var summary: PanelContainer
var close_button: Button
## Complete selected list, including alerts represented by the overflow count.
var codes := PackedStringArray()

var _column: VBoxContainer
var _cards: Array[Dictionary] = []
var _summary_card: Dictionary
var _detail := true
var _limit := 3
var _opaque := false
var _entrance: Tween


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
	chips = VBoxContainer.new()
	chips.name = "Chips"
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.add_theme_constant_override("separation", 4)
	_column.add_child(chips)
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Cards outside the tree remain in the pool so later alerts reuse them.
		for card: Dictionary in _cards:
			var node: PanelContainer = card.root
			if is_instance_valid(node) and node.get_parent() == null:
				node.free()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and chips != null:
		_render_cards()


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
	var next_detail: bool = detail if typeof(detail) == TYPE_BOOL else true
	var next_limit: int = limit if typeof(limit) == TYPE_INT and limit in LIMITS else 3
	if next_detail == _detail and next_limit == _limit and _opaque == UiTheme.opaque_panels:
		return
	_detail = next_detail
	_limit = next_limit
	_opaque = UiTheme.opaque_panels
	_render_cards()


## Inputs are already filtered and ordered. Repeated samples do not touch the node tree.
func refresh(new_codes: PackedStringArray) -> bool:
	if new_codes == codes:
		return not codes.is_empty()
	var previous := codes
	codes = new_codes.duplicate()
	_render_cards()
	var appeared := false
	for index in mini(codes.size(), _limit):
		if not previous.has(codes[index]):
			appeared = true
			break
	if appeared and is_visible_in_tree() and not UiTheme.reduced_motion:
		_start_entrance()
	return not codes.is_empty()


func _render_cards() -> void:
	var shown := mini(codes.size(), _limit)
	while _cards.size() < shown:
		_cards.append(_make_card("Warning"))
	while chips.get_child_count() > shown:
		chips.remove_child(chips.get_child(chips.get_child_count() - 1))
	for index in shown:
		var card: Dictionary = _cards[index]
		if card.root.get_parent() == null:
			chips.add_child(card.root)
		var code := codes[index]
		_update_card(card, AlertPolicy.severity(code), tr(AlertPolicy.title_for(code)),
			tr(AlertPolicy.detail_for(code)) if _detail else "", code)
	var remaining := codes.size() - shown
	summary.visible = remaining > 0
	if remaining > 0:
		var severity := "info"
		for index in range(shown, codes.size()):
			var candidate := AlertPolicy.severity(codes[index])
			if candidate == "danger":
				severity = candidate
				break
			if candidate == "caution": severity = candidate
		_update_card(_summary_card, severity, tr("+%d MORE ALERTS") % remaining, "", "")


func _make_card(card_name: String) -> Dictionary:
	var card := PanelContainer.new()
	card.name = card_name
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var outer := StyleBoxFlat.new()
	outer.bg_color = Color.TRANSPARENT
	outer.content_margin_left = 7
	outer.content_margin_right = 7
	outer.content_margin_top = 5
	outer.content_margin_bottom = 5
	card.add_theme_stylebox_override("panel", outer)
	var underlay := Node2D.new()
	underlay.name = "Glass"
	underlay.show_behind_parent = true
	card.add_child(underlay, false, Node.INTERNAL_MODE_BACK)
	var material := ShaderMaterial.new()
	material.shader = GLASS
	material.set_shader_parameter("primary", 1.0)
	material.set_shader_parameter("corner_radius", 9.0)
	material.set_shader_parameter("crystal_color", UiTheme.CRYSTAL)
	material.set_shader_parameter("emission_color", UiTheme.FOCUS)
	material.set_shader_parameter("edge_width", 0.65)
	material.set_shader_parameter("edge_strength", 0.60)
	material.set_shader_parameter("reflection_strength", 0.25)
	material.set_shader_parameter("glint_strength", 0.0)
	material.set_shader_parameter("energy", 0.0)
	material.set_shader_parameter("shine_progress", -1.0)
	var glass := ColorRect.new()
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.material = material
	underlay.add_child(glass)
	card.resized.connect(_resize_glass.bind(card, glass, material))
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	card.add_child(row)
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size.x = 76
	row.add_child(badge)
	var severity := Frame.text_label("", 12, UiTheme.TEXT)
	severity.name = "Severity"
	severity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	severity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	severity.clip_text = true
	badge.add_child(severity)
	var well := PanelContainer.new()
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(well)
	var copy := VBoxContainer.new()
	copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_theme_constant_override("separation", 0)
	well.add_child(copy)
	var headline := Frame.text_label("", 15, UiTheme.TEXT)
	headline.name = "Headline"
	headline.clip_text = true
	headline.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	copy.add_child(headline)
	var detail := Frame.text_label("", 14, UiTheme.TEXT_2)
	detail.name = "Detail"
	detail.clip_text = true
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(detail)
	return {root = card, material = material, badge = badge, severity = severity,
		well = well, headline = headline, detail = detail}


func _update_card(card: Dictionary, level: String, title: String, detail: String, code: String) -> void:
	var accent := UiTheme.CRYSTAL
	if level == "danger": accent = UiTheme.ERROR
	elif level == "caution": accent = UiTheme.CAUTION
	var severity: Label = card.severity
	severity.text = tr(level.to_upper())
	severity.add_theme_color_override("font_color", accent)
	var headline: Label = card.headline
	headline.text = title
	var description: Label = card.detail
	description.text = detail
	description.visible = not detail.is_empty()
	card.root.set_meta("code", code)
	card.root.set("accessibility_name", ": ".join([severity.text, title, detail]).trim_suffix(": "))
	var badge_style := _well_style()
	badge_style.set_border_width_all(1)
	badge_style.border_color = Color(accent, 0.75)
	card.badge.add_theme_stylebox_override("panel", badge_style)
	card.well.add_theme_stylebox_override("panel", _well_style())
	card.material.set_shader_parameter("base_color", Color("#08290F", 1.0 if _opaque else 0.94))


func _well_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(WELL, 1.0 if _opaque else 0.96)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func _resize_glass(card: Control, glass: ColorRect, material: ShaderMaterial) -> void:
	glass.size = card.size
	material.set_shader_parameter("rect_size", card.size)


func _resize_to_viewport() -> void:
	var width := minf(MAX_WIDTH, maxf(0.0, get_viewport_rect().size.x - 24.0))
	if is_equal_approx(custom_minimum_size.x, width): return
	custom_minimum_size.x = width
	reset_size()


func _start_entrance() -> void:
	_stop_entrance()
	modulate.a = 0.85
	_entrance = create_tween()
	_entrance.tween_property(self, "modulate:a", 1.0, 0.16)


func _stop_entrance() -> void:
	if _entrance != null and _entrance.is_valid(): _entrance.kill()
	_entrance = null
	modulate.a = 1.0


func _visibility_changed() -> void:
	if not is_visible_in_tree():
		_stop_entrance()
	elif _opaque != UiTheme.opaque_panels:
		_opaque = UiTheme.opaque_panels
		_render_cards()
