# UI-31 (UI-30 PS-1): the radio calibration steps, shown over the flight whatever overlay preset is active.
# Presentation only: Enter/Esc and the controller Accept/Back actions stay with the flight and the shell, and the card
# never takes the keyboard focus. Ending the wizard reopens Pause through the flight's own input handlers.
extends CanvasLayer

const UiTheme := preload("res://ui/ui_theme.gd")
const RcCalibration := preload("res://input/rc_calibration.gd")

const LAYER := 9 # above the flight HUD and the first-flight hint (5), below Pause (10)

var _session: Node
var _step_label: Label
var _prompt_label: Label
var _error_label: Label
var _axes_label: Label


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
	card.custom_minimum_size.x = 640.0
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	card.add_child(column)
	var title := _label("TitleLabel", "Title")
	title.text = "Radio calibration"
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	column.add_child(title)
	_step_label = _label("SectionLabel", "Step")
	column.add_child(_step_label)
	_prompt_label = _label("", "Prompt")
	column.add_child(_prompt_label)
	_error_label = _label("ErrorLabel", "Error")
	column.add_child(_error_label)
	_axes_label = _label("SecondaryLabel", "Axes")
	column.add_child(_axes_label)
	var hint := _label("SecondaryLabel", "Keys")
	hint.text = "Enter or controller Accept: next step · Esc or controller Back: cancel"
	hint.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	column.add_child(hint)


func _process(_delta: float) -> void:
	var wizard: Variant = _session.get("calibration") if is_instance_valid(_session) else null
	visible = wizard != null
	if visible:
		_refresh(wizard)


func _refresh(wizard: RefCounted) -> void:
	var step := clampi(int(wizard.get("step")), 0, RcCalibration.STEPS.size() - 1)
	_step_label.text = tr("Step %d of %d") % [step + 1, RcCalibration.STEPS.size()]
	_prompt_label.text = tr(RcCalibration.PROMPTS[RcCalibration.STEPS[step]])
	var error := str(wizard.get("error"))
	_error_label.text = tr(error) if not error.is_empty() else ""
	_error_label.visible = not error.is_empty()
	var axes: PackedFloat64Array = _session.radio.axes
	_axes_label.text = tr("Radio axes: %s") % " ".join(Array(axes).map(func(v: float) -> String: return "%+.2f" % v))


func _label(variation: String, node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	if not variation.is_empty():
		label.theme_type_variation = variation
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED # live texts are built with tr()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 600.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
