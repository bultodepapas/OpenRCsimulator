# UI-31 (UI-30 PS-1): the radio calibration steps, shown over the flight whatever overlay preset is active.
# Presentation only: Enter/Esc and the controller Accept/Back actions stay with the flight and the shell, and the card
# never takes the keyboard focus. Ending the wizard reopens Pause through the flight's own input handlers.
# UI-15-UX-01: the steps are drawn by the shared CalibrationView; every node ignores the mouse and focus.
extends CanvasLayer

const UiTheme := preload("res://ui/ui_theme.gd")
const CalibrationView := preload("res://ui/controls/calibration_view.gd")

const LAYER := 9 # above the flight HUD and the first-flight hint (5), below Pause (10)

var view: CalibrationView
var _session: Node


func _init(session: Node) -> void:
	name = "CalibrationCard"
	layer = LAYER
	visible = false
	_session = session
	var screen := Control.new()
	screen.theme = UiTheme.build()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(center)
	var card := PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = "Card"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(card)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	view = CalibrationView.new()
	column.add_child(view)
	var hint := Label.new()
	hint.name = "Keys"
	hint.theme_type_variation = "SecondaryLabel"
	hint.text = "Enter or controller Accept: next step · Esc or controller Back: cancel"
	hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 600.0
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(hint)
	_make_passive(screen)


func _ready() -> void:
	view.stick_mode = CalibrationView.presentation_stick_mode(self)


func _process(_delta: float) -> void:
	var wizard: Variant = _session.get("calibration") if is_instance_valid(_session) else null
	visible = wizard != null
	if visible and wizard is Object and wizard.has_method("requested_target"):
		var radio: Variant = _session.get("radio")
		var axes: PackedFloat64Array = radio.axes if radio is Object and radio.get("axes") is PackedFloat64Array else PackedFloat64Array()
		view.update(wizard, axes)


## The card never takes focus or the mouse, whatever widgets the shared view contains.
static func _make_passive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(node as Control).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_make_passive(child)
