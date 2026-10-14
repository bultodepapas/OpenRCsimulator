# O3 Warnings (HUD-09): short annunciators at the top centre, text plus colour (never colour alone). Codes and
# triggers come from Telemetry.warnings(); the bar shows nothing when nothing needs the pilot's attention.
extends HBoxContainer

const UiTheme := preload("res://ui/ui_theme.gd")
const Frame := preload("res://render/overlays/overlay_frame.gd")

signal close_requested(id: String)

const DANGER := ["failsafe", "controller_lost", "stall", "low"]
const INFO := ["experimental"]
## The chips wrap inside this width (px), so many warnings never reach the corner overlays (Wind is ≈ 232 px wide).
const MAX_WIDTH := 640.0

var id := "warnings"
var chips: HFlowContainer
var close_button: Button
var codes := PackedStringArray()


func _init() -> void:
	name = "WarningsOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	chips = HFlowContainer.new()
	chips.name = "Chips"
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chips.alignment = FlowContainer.ALIGNMENT_CENTER
	chips.custom_minimum_size.x = MAX_WIDTH
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	add_child(chips)
	close_button = Frame.close_x(func() -> void: close_requested.emit(id))
	close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close_button.add_theme_stylebox_override("normal", Frame.backplate())
	add_child(close_button)
	visible = false


## The words on each chip (translated at display time).
static func text_for(code: String) -> String:
	match code:
		"failsafe":
			return "FAILSAFE · radio lost"
		"safe":
			return "RADIO SAFE · throttle low to arm"
		"gamepad_safe":
			return "GAMEPAD SAFE · move controls, then release"
		"controller_lost":
			return "CONTROLLER LOST · select controls to continue"
		"stall":
			return "STALL"
		"low":
			return "LOW · sinking"
		"far":
			return "FAR · come closer"
		"battery":
			return "BATTERY LOW"
		"experimental":
			return "EXPERIMENTAL MODEL"
	return code.to_upper()


## Shows `new_codes`; returns whether anything is shown. Chips are rebuilt only when the set changes.
func refresh(new_codes: PackedStringArray) -> bool:
	if new_codes != codes:
		codes = new_codes
		for child in chips.get_children():
			chips.remove_child(child)
			child.queue_free()
		for code in codes:
			chips.add_child(_chip(code))
	return not codes.is_empty()


func _chip(code: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = code.capitalize()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	var text_color := UiTheme.TEXT
	if code in DANGER:
		box.bg_color = UiTheme.PRIMARY.pressed # contrast under the cream text checked by test_overlay_manager
	elif code in INFO:
		box.bg_color = Color(UiTheme.PANEL, Frame.BACKPLATE_ALPHA)
	else:
		box.bg_color = UiTheme.FOCUS # amber caution, dark text
		text_color = UiTheme.PANEL
	box.set_corner_radius_all(UiTheme.RADIUS)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", box)
	var label := Frame.text_label(tr(text_for(code)), 18, text_color)
	chip.add_child(label)
	return chip
