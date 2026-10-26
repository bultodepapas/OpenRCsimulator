extends CanvasLayer
## UI-15-GP-01: capture a radio calibration without a flight or a storage write.
## The caller owns the draft and Save; this surface owns one connection generation.

const Screen := preload("res://ui/screen.gd")
const Widgets := preload("res://ui/widgets.gd")
const Calibration := preload("res://input/rc_calibration.gd")
const RcInput := preload("res://input/rc_input.gd")

signal completed(profile: Dictionary, warning: String)
signal cancelled(reason: String)

var read_axis: Callable = Input.get_joy_axis
var next_button: Button
var cancel_button: Button
var _registry: Object
var _device_id: int = -1
var _generation: int = -1
var _wizard: RefCounted
var _surface: Control
var _prompt: Label
var _step_label: Label
var _error_label: Label
var _axes_label: Label
var _finished: bool = false


func _init() -> void:
	name = "RadioCalibrationSetup"
	layer = 13
	_surface = Screen.mount(self)
	_surface.escape_before_gui = true
	_surface.close_requested.connect(request_close)
	_surface.dim(0.45)
	var card: PanelContainer = PanelContainer.new()
	card.name = "RadioCalibrationCard"
	card.theme_type_variation = "Card"
	card.custom_minimum_size.x = 640.0
	_surface.center(24.0).add_child(card)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	card.add_child(column)
	column.add_child(Widgets.label("Radio calibration", "TitleLabel"))
	_step_label = Widgets.label("", "SectionLabel", true, false)
	column.add_child(_step_label)
	_prompt = Widgets.label("", "", true, false)
	_prompt.custom_minimum_size.x = 560.0
	column.add_child(_prompt)
	_error_label = Widgets.label("", "ErrorLabel", true, false)
	column.add_child(_error_label)
	_axes_label = Widgets.label("", "SecondaryLabel", true, false)
	column.add_child(_axes_label)
	column.add_child(Widgets.label("Calibration stays in the draft until you Save controller settings.", "SecondaryLabel", true))
	var buttons: HBoxContainer = Widgets.button_row()
	column.add_child(buttons)
	cancel_button = Widgets.button("Cancel", "QuietButton", "CancelCalibration")
	cancel_button.pressed.connect(request_close)
	buttons.add_child(cancel_button)
	next_button = Widgets.button("Next", "PrimaryButton", "NextCalibrationStep")
	next_button.pressed.connect(advance)
	buttons.add_child(next_button)


func configure(registry: Object, device_id: int, profile: Dictionary) -> bool:
	_registry = registry
	_device_id = device_id
	_generation = int(registry.connection_generation(device_id))
	if profile.get("kind", "") != "radio" or not connection_is_current():
		return false
	_wizard = Calibration.new(profile)
	_refresh()
	return true


func connection_is_current() -> bool:
	return _registry != null and _device_id >= 0 and _generation > 0 \
		and bool(_registry.device_for_id(_device_id).get("connected", false)) \
		and int(_registry.connection_generation(_device_id)) == _generation


func _ready() -> void:
	_registry.devices_changed.connect(_check_connection)
	next_button.grab_focus()
	_check_connection()


func _notification(what: int) -> void:
	if is_inside_tree() and what in [NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_cancel(tr("Calibration cancelled because the application lost focus. The draft is unchanged."))


func _check_connection() -> bool:
	if _finished:
		return false
	if not connection_is_current():
		_cancel(tr("The radio disconnected or changed. Calibration was cancelled; the draft is unchanged."))
		return false
	return true


func _process(delta: float) -> void:
	if _finished or not _surface.visible:
		return
	if delta > 5.0:
		_cancel(tr("Calibration was interrupted. Start again; the draft is unchanged."))
		return
	_sample()


func _sample() -> PackedFloat64Array:
	var axes: PackedFloat64Array = PackedFloat64Array()
	if not _check_connection():
		return axes
	for axis: int in RcInput.AXES:
		var value: Variant = read_axis.call(_device_id, axis)
		if typeof(value) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(value)) or absf(float(value)) > 1.0:
			_cancel(tr("The radio returned an invalid axis reading. Calibration was cancelled; the draft is unchanged."))
			return PackedFloat64Array()
		axes.append(float(value))
	_wizard.sample(axes)
	_axes_label.text = tr("Radio axes: %s") % " ".join(Array(axes).map(func(value: float) -> String: return "%+.2f" % value))
	return axes


func advance() -> void:
	if _finished or not _surface.visible:
		return
	var axes: PackedFloat64Array = _sample()
	if axes.is_empty():
		return
	if _wizard.done():
		_finished = true
		completed.emit(_wizard.profile.duplicate(true), str(_wizard.aux_warning))
		return
	_wizard.advance(axes)
	_refresh()


func request_close() -> void:
	_cancel(tr("Calibration cancelled. The draft is unchanged."))


func _cancel(reason: String) -> void:
	if _finished:
		return
	_finished = true
	cancelled.emit(reason)


func _refresh() -> void:
	if _wizard.done():
		_step_label.text = tr("Calibration complete")
		_prompt.text = tr("Use these ranges, then Save controller settings. Lower the throttle before flying.")
		next_button.text = tr("Use calibration")
	else:
		var step: int = int(_wizard.step)
		_step_label.text = tr("Step %d of %d") % [step + 1, Calibration.STEPS.size()]
		_prompt.text = tr(Calibration.PROMPTS[Calibration.STEPS[step]])
	_error_label.text = tr(str(_wizard.error))
	_error_label.visible = not _error_label.text.is_empty()
